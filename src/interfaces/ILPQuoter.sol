// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @title ILPQuoter — Interface for LP pricing contracts used by HyFiHook.
/// @notice Each LP deploys their own Quoter implementing this interface.
///         The hook provides centralised price data; quoters focus on fees,
///         inventory management, and custom curve logic.
/// @dev    Conventions:
///         - For exact-input  (amountSpecified < 0): amIn  MUST equal |amountSpecified|.
///         - For exact-output (amountSpecified > 0): amOut MUST equal  amountSpecified.
///         - Revert or return amOut = 0 for unsupported pools.
interface ILPQuoter {
    function quoteTrade(
        PoolKey calldata key,
        bool zeroForOne,
        int256 amountSpecified,
        uint256 bidPriceX96,
        uint256 spreadX96,
        uint32 timestamp
    ) external view returns (uint256 amIn, uint256 amOut);
}
