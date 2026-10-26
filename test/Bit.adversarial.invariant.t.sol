// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Bit} from "../src/Bit.sol";

/// @dev Drives Bit with both succeeding and failing calls. Ghost balances and allowances record what
/// each successful call should have done; every failing call must revert with the exact ERC-6093 error
/// and leave the tracked state untouched. Tokens may leave the actor set to arbitrary recipients, which
/// are recorded so the conservation invariant still sums every holder.
contract BitAdversarialHandler is Test {
    Bit public immutable token;
    address[5] public actors;
    address[] public holders;
    mapping(address => bool) public isHolder;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostRejected;
    uint256 public ghostMovedOut;

    constructor(Bit token_, address seeded) {
        token = token_;
        actors[0] = seeded;
        actors[1] = makeAddr("adv holder 1");
        actors[2] = makeAddr("adv holder 2");
        actors[3] = makeAddr("adv holder 3");
        actors[4] = makeAddr("adv holder 4");
        for (uint256 i; i < actors.length; ++i) {
            _track(actors[i]);
        }
        ghostBalance[seeded] = token_.totalSupply();
    }

    function holderCount() external view returns (uint256) {
        return holders.length;
    }

    function _track(address account) internal {
        if (!isHolder[account]) {
            isHolder[account] = true;
            holders.push(account);
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _move(address from, address to, uint256 amount) internal {
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
    }

    // ---------------------------------------------------------------- succeeding operations

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
    }

    /// @dev Sends to any nonzero address, including precompiles, the token itself and this handler.
    function transferOut(uint256 fromSeed, address to, uint256 amount) external {
        if (to == address(0)) to = address(token);
        address from = _actor(fromSeed);
        amount = bound(amount, 0, token.balanceOf(from));
        _track(to);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
        if (!_isActor(to)) ghostMovedOut += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (unlimited) amount = type(uint256).max;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 held = ghostBalance[owner];
        amount = bound(amount, 0, allowed < held ? allowed : held);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (allowed != type(uint256).max) ghostAllowance[owner][spender] = allowed - amount;
        _move(owner, to, amount);
    }

    // ---------------------------------------------------------------- failing operations

    function overdraw(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = token.balanceOf(from);
        uint256 amount = held + bound(excess, 1, type(uint256).max - held);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        vm.prank(from);
        token.transfer(to, amount);
        ++ghostRejected;
    }

    function overspendAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 excess) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = token.allowance(owner, spender);
        if (allowed == type(uint256).max) return; // unlimited allowance cannot be exceeded
        uint256 amount = allowed + bound(excess, 1, type(uint256).max - allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        ++ghostRejected;
    }

    /// @dev Allowance covers the amount but the owner's balance does not: the allowance must not be spent.
    function allowanceAboveBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = token.allowance(owner, spender);
        uint256 held = token.balanceOf(owner);
        if (allowed <= held) return;
        amount = bound(amount, held + 1, allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        ++ghostRejected;
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, token.balanceOf(from));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(from);
        token.transfer(address(0), amount);
        ++ghostRejected;
    }

    function transferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = token.allowance(owner, spender);
        uint256 held = token.balanceOf(owner);
        amount = bound(amount, 0, allowed < held ? allowed : held);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
        ++ghostRejected;
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
        ++ghostRejected;
    }

    /// @dev Admin-shaped calls the token must not expose, tried from a holder and from the deployer.
    function adminCall(uint256 which, uint256 callerSeed, uint256 amount) external {
        address caller = _actor(callerSeed);
        bytes memory data;
        which = which % 6;
        if (which == 0) data = abi.encodeWithSignature("mint(address,uint256)", caller, amount);
        else if (which == 1) data = abi.encodeWithSignature("burn(uint256)", amount);
        else if (which == 2) data = abi.encodeWithSignature("burnFrom(address,uint256)", actors[0], amount);
        else if (which == 3) data = abi.encodeWithSignature("pause()");
        else if (which == 4) data = abi.encodeWithSignature("blacklist(address)", actors[0]);
        else data = abi.encodeWithSignature("transferOwnership(address)", caller);
        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        assertFalse(ok);
        ++ghostRejected;
    }

    function _isActor(address account) internal view returns (bool) {
        for (uint256 i; i < actors.length; ++i) {
            if (actors[i] == account) return true;
        }
        return false;
    }
}

contract BitAdversarialInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 100_000_000 * 10 ** 18;
    Bit internal token;
    BitAdversarialHandler internal handler;

    function setUp() public {
        token = new Bit();
        address seeded = makeAddr("adv holder 0");
        handler = new BitAdversarialHandler(token, seeded);
        token.transfer(seeded, SUPPLY);

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = BitAdversarialHandler.transfer.selector;
        selectors[1] = BitAdversarialHandler.transferOut.selector;
        selectors[2] = BitAdversarialHandler.approve.selector;
        selectors[3] = BitAdversarialHandler.transferFrom.selector;
        selectors[4] = BitAdversarialHandler.overdraw.selector;
        selectors[5] = BitAdversarialHandler.overspendAllowance.selector;
        selectors[6] = BitAdversarialHandler.allowanceAboveBalance.selector;
        selectors[7] = BitAdversarialHandler.transferToZero.selector;
        selectors[8] = BitAdversarialHandler.transferFromToZero.selector;
        selectors[9] = BitAdversarialHandler.approveZeroSpender.selector;
        selectors[10] = BitAdversarialHandler.adminCall.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_TotalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_EveryBalanceMatchesGhostAndSumsToSupply() public view {
        uint256 n = handler.holderCount();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            address holder = handler.holders(i);
            uint256 balance = token.balanceOf(holder);
            assertEq(balance, handler.ghostBalance(holder));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_AllowancesMatchGhost() public view {
        for (uint256 i; i < 5; ++i) {
            for (uint256 j; j < 5; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.ghostAllowance(owner, spender));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_TokenHoldsNoEther() public view {
        assertEq(address(token).balance, 0);
    }
}
