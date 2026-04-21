// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {ILPQuoter} from "./interfaces/ILPQuoter.sol";

/// @title SimpleQuoter — Reference ILPQuoter with staleness fee.
/// @notice Uses the centralised bid/spread/lastUpdate provided by HyFiHook
///         and applies a linear staleness fee on top.
contract SimpleQuoter is ILPQuoter, Ownable {
    uint internal constant MAX_FEE   = 1_000_000;  // 100 % cap
    uint internal constant FEE_DENOM = 1_000_000;
    uint internal constant Q96       = 1 << 96;

    uint public baseFee;
    uint public feePerSecond;

    error ZeroOutput();
    error FeeTooHigh();

    event FeeUpdated(uint newBaseFee, uint newFeePerSecond);

    constructor(address _owner, uint _baseFee, uint _feePerSecond) Ownable(_owner) {
        if (_baseFee > MAX_FEE) revert FeeTooHigh();
        baseFee = _baseFee;
        feePerSecond = _feePerSecond;
    }

    /// @notice Update the base fee and per-second staleness rate (in pips; FEE_DENOM = 1e6 = 100%).
    function setFee(uint newBaseFee, uint newFeePerSecond) external onlyOwner {
        if (newBaseFee > MAX_FEE) revert FeeTooHigh();
        baseFee = newBaseFee;
        feePerSecond = newFeePerSecond;
        emit FeeUpdated(newBaseFee, newFeePerSecond);
    }

    // -----------------------------------------------------------------------
    // ILPQuoter
    // -----------------------------------------------------------------------

    function quoteTrade(
        PoolKey calldata,
        bool zeroForOne,
        int256 amountSpecified,
        uint256 bidPriceX96,
        uint256 spreadX96,
        uint32 lastUpdate
    ) external view override returns (uint256 amIn, uint256 amOut) {
        uint effectivePriceX96 = zeroForOne ? bidPriceX96 : bidPriceX96 + spreadX96;
        uint fee = _fee(lastUpdate);

        if (amountSpecified < 0) {
            amIn = uint(-amountSpecified);
            uint amInAfterFee = amIn * (FEE_DENOM - fee) / FEE_DENOM;
            amOut = zeroForOne
                ? FullMath.mulDiv(amInAfterFee, effectivePriceX96, Q96)
                : FullMath.mulDiv(amInAfterFee, Q96, effectivePriceX96);
            if (amOut == 0) revert ZeroOutput();
        } else {
            amOut = uint(amountSpecified);
            uint amInBeforeFee = zeroForOne
                ? FullMath.mulDivRoundingUp(amOut, Q96, effectivePriceX96)
                : FullMath.mulDivRoundingUp(amOut, effectivePriceX96, Q96);
            amIn = FullMath.mulDivRoundingUp(amInBeforeFee, FEE_DENOM, FEE_DENOM - fee);
        }
    }

    function _fee(uint32 lastUpdate) internal view returns (uint fee) {
        uint f = baseFee + (block.timestamp - uint(lastUpdate)) * feePerSecond;
        fee = f > MAX_FEE ? MAX_FEE : f;
    }
}
