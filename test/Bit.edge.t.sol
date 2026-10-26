// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Bit} from "../src/Bit.sol";

/// @dev Stands in for the launch factory: deploys Bit through CREATE2 with the launch number as salt
/// and moves the launch shares in the same call, as one transaction does on chain.
contract BitLaunchFixture {
    function launch(uint64 launchNumber, address distributor, address pool, address remainder)
        external
        returns (Bit token)
    {
        token = new Bit{salt: bytes32(uint256(launchNumber))}();
        uint256 supply = token.totalSupply();
        require(token.balanceOf(address(this)) == supply, "factory does not hold supply");
        uint256 swarm = supply * 1_000 / 10_000;
        uint256 seeded = supply * 8_000 / 10_000;
        require(token.transfer(distributor, swarm));
        require(token.transfer(pool, seeded));
        require(token.transfer(remainder, supply - swarm - seeded));
    }
}

contract BitEdgeTest is Test {
    uint256 internal constant SUPPLY = 100_000_000 * 10 ** 18;
    Bit internal token;
    address internal alice = makeAddr("edge alice");
    address internal bob = makeAddr("edge bob");
    address internal carol = makeAddr("edge carol");

    function setUp() public {
        token = new Bit();
    }

    function test_SupplyConstantIsExactBaseUnits() public view {
        assertEq(token.totalSupply(), 100000000000000000000000000);
        assertEq(token.totalSupply(), 100_000_000 * 10 ** uint256(token.decimals()));
    }

    function test_DeploymentIsDeterministicAndIndependentOfCaller() public {
        BitLaunchFixture factory = new BitLaunchFixture();
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");
        address remainder = makeAddr("remainder");
        bytes32 initHash = keccak256(type(Bit).creationCode);
        address predicted = vm.computeCreate2Address(bytes32(uint256(7)), initHash, address(factory));
        vm.prank(alice);
        Bit launched = factory.launch(7, distributor, pool, remainder);
        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(distributor), SUPPLY / 10);
        assertEq(launched.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(launched.balanceOf(remainder), SUPPLY / 10);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_SameLaunchNumberCannotBeDeployedTwice() public {
        BitLaunchFixture factory = new BitLaunchFixture();
        factory.launch(1, alice, bob, carol);
        vm.expectRevert();
        factory.launch(1, alice, bob, carol);
    }

    function test_RuntimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += op - 0x5F;
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE) reachable = false;
        }
    }

    function test_OneWeiMoreThanBalanceReverts() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(alice);
        token.transfer(bob, 2);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
        assertEq(token.balanceOf(bob), 1);
    }

    function test_DeployerCannotExceedSupply() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
    }

    function test_MaxUintTransferReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_AllowanceOneBelowMaxIsFiniteAndDecrements() public {
        token.approve(alice, type(uint256).max - 1);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 5);
        assertEq(token.allowance(address(this), alice), type(uint256).max - 6);
    }

    function test_InfiniteAllowanceStillBoundByBalance() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        vm.prank(bob);
        token.transferFrom(alice, carol, 11);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.balanceOf(alice), 10);
    }

    function test_HolderSpendingOwnTokensViaTransferFromNeedsSelfAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
    }

    function test_AllowancesArePerOwnerSpenderPair() public {
        token.transfer(alice, 100);
        token.approve(bob, 50);
        vm.prank(alice);
        token.approve(bob, 20);
        token.approve(carol, 30);
        vm.prank(bob);
        token.transferFrom(alice, carol, 20);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.allowance(address(this), bob), 50);
        assertEq(token.allowance(address(this), carol), 30);
        // bob's allowance from the deployer is unusable against alice
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, carol, 1);
    }

    function test_SpentAllowanceCannotBeReused() public {
        token.approve(alice, 10);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(address(this), bob, 1);
    }

    function test_TokensSentToTokenContractAreStuckButCounted() public {
        token.transfer(address(token), 1 ether);
        assertEq(token.balanceOf(address(token)), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
        // No function lets anyone move them back out.
        (bool ok,) = address(token).call(abi.encodeWithSignature("rescueTokens(address,uint256)", address(this), 1));
        assertFalse(ok);
        assertEq(token.balanceOf(address(token)), 1 ether);
    }

    function test_ForcedEtherDoesNotAffectAccounting() public {
        vm.deal(address(token), 3 ether);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_UnknownSelectorWithValueReverts() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1}(abi.encodeWithSignature("deposit()"));
        assertFalse(ok);
        vm.prank(alice);
        (ok,) = address(token).call{value: 1}(abi.encodeWithSignature("transfer(address,uint256)", bob, 0));
        assertFalse(ok, "non-payable transfer accepted ETH");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_SplitTransfersAreExact(uint256 a, uint256 b) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, SUPPLY - a);
        token.transfer(alice, a);
        token.transfer(bob, b);
        vm.prank(alice);
        token.transfer(bob, a);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), a + b);
        assertEq(token.balanceOf(address(this)), SUPPLY - a - b);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_UnlimitedAllowanceNeverDecrements(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        token.approve(alice, type(uint256).max);
        vm.startPrank(alice);
        token.transferFrom(address(this), bob, first);
        token.transferFrom(address(this), carol, second);
        vm.stopPrank();
        assertEq(token.allowance(address(this), alice), type(uint256).max);
        assertEq(token.balanceOf(bob), first);
        assertEq(token.balanceOf(carol), second);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ApproveSetsExactValue(address owner, address spender, uint256 first, uint256 second) public {
        vm.assume(owner != address(0) && spender != address(0));
        vm.startPrank(owner);
        token.approve(spender, first);
        assertEq(token.allowance(owner, spender), first);
        token.approve(spender, second);
        vm.stopPrank();
        assertEq(token.allowance(owner, spender), second);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_StrangerCannotMoveDeployerFunds(address stranger, uint256 amount) public {
        vm.assume(stranger != address(this));
        amount = bound(amount, 1, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        vm.prank(stranger);
        token.transferFrom(address(this), stranger, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_TransferFromOverBalanceKeepsAllowance(uint256 held, uint256 allowed, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        allowed = bound(allowed, held + 1, type(uint256).max);
        amount = bound(amount, held + 1, allowed);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(bob, allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(bob);
        token.transferFrom(alice, carol, amount);
        assertEq(token.allowance(alice, bob), allowed);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(carol), 0);
    }
}
