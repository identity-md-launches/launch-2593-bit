// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Bit (BIT)
/// @notice Fixed-supply ERC-20. The immediate deployer receives all tokens once.
/// @dev No owner, external mint/burn, transfer fee, or upgrade mechanism.
contract Bit is ERC20 {
    /// @notice 100,000,000 BIT expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 10 ** 18;

    constructor() ERC20("Bit", "BIT") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
