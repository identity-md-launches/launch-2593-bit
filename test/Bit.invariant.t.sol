// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Bit} from "../src/Bit.sol";

/// @dev Closed set of token holders; all generated operations stay within this set.
contract BitHandler is Test {
    Bit public immutable token;
    address[4] public actors;

    constructor(Bit token_) {
        token = token_;
        actors[0] = makeAddr("holder 0");
        actors[1] = makeAddr("holder 1");
        actors[2] = makeAddr("holder 2");
        actors[3] = makeAddr("holder 3");
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, fromBefore);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = token.allowance(owner, spender);
        uint256 ownerBefore = token.balanceOf(owner);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, allowed < ownerBefore ? allowed : ownerBefore);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.allowance(owner, spender), allowed == type(uint256).max ? allowed : allowed - amount);
        assertEq(token.balanceOf(owner), owner == to ? ownerBefore : ownerBefore - amount);
        assertEq(token.balanceOf(to), owner == to ? toBefore : toBefore + amount);
    }
}

contract BitInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 100_000_000 * 10 ** 18;
    Bit internal token;
    BitHandler internal handler;

    function setUp() public {
        token = new Bit();
        handler = new BitHandler(token);
        token.transfer(handler.actors(0), SUPPLY);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = BitHandler.transfer.selector;
        selectors[1] = BitHandler.approve.selector;
        selectors[2] = BitHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyAndSumOfBalancesRemainFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }
}
