// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ILPQuoter} from "../../../src/interfaces/ILPQuoter.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @dev Quoter that always reverts — used to test skip-on-revert behavior.
contract RevertingQuoter is ILPQuoter {
    error AlwaysReverts();
    function quoteTrade(PoolKey calldata, bool, int256, uint256, uint256, uint32)
        external pure returns (uint256, uint256)
    {
        revert AlwaysReverts();
    }
}
