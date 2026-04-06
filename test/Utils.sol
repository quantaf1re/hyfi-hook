// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";

abstract contract TestUtils {
    using CurrencyLibrary for Currency;

    uint256 internal constant BASE_FEE       = 500;
    uint256 internal constant FEE_PER_SECOND = 100;
    uint256 internal constant MAX_FEE        = 1_000_000;
    uint256 internal constant FEE_DENOM      = 1_000_000;
    uint256 internal constant Q96            = 1 << 96;

    function swap(address router, PoolKey memory key, bool zeroForOne, int256 amountSpecified) internal {
        Currency input = zeroForOne ? key.currency0 : key.currency1;
        Currency output = zeroForOne ? key.currency1 : key.currency0;

        bytes memory actions;
        bytes[] memory actionParams;
        uint256 nativeValue;
        bool needsSweep;

        if (amountSpecified < 0) {
            // Exact input
            uint128 amountIn = uint128(uint256(-amountSpecified));
            actions = abi.encodePacked(
                uint8(Actions.SWAP_EXACT_IN_SINGLE),
                uint8(Actions.SETTLE_ALL),
                uint8(Actions.TAKE_ALL)
            );
            actionParams = new bytes[](3);
            actionParams[0] = abi.encode(
                IV4Router.ExactInputSingleParams({
                    poolKey: key,
                    zeroForOne: zeroForOne,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    minHopPriceX36: 0,
                    hookData: ""
                })
            );
            actionParams[1] = abi.encode(input, type(uint256).max);
            actionParams[2] = abi.encode(output, uint256(0));
            if (input.isAddressZero()) nativeValue = amountIn;
        } else {
            // Exact output
            uint128 amountOut = uint128(uint256(amountSpecified));
            actions = abi.encodePacked(
                uint8(Actions.SWAP_EXACT_OUT_SINGLE),
                uint8(Actions.SETTLE_ALL),
                uint8(Actions.TAKE_ALL)
            );
            actionParams = new bytes[](3);
            actionParams[0] = abi.encode(
                IV4Router.ExactOutputSingleParams({
                    poolKey: key,
                    zeroForOne: zeroForOne,
                    amountOut: amountOut,
                    amountInMaximum: type(uint128).max,
                    minHopPriceX36: 0,
                    hookData: ""
                })
            );
            actionParams[1] = abi.encode(input, type(uint256).max);
            actionParams[2] = abi.encode(output, uint256(0));
            if (input.isAddressZero()) {
                nativeValue = 100e18;
                needsSweep = true;
            }
        }

        bytes memory commands;
        bytes[] memory inputs;

        if (needsSweep) {
            commands = abi.encodePacked(uint8(Commands.V4_SWAP), uint8(Commands.SWEEP));
            inputs = new bytes[](2);
            inputs[0] = abi.encode(actions, actionParams);
            inputs[1] = abi.encode(address(0), address(this), uint256(0));
        } else {
            commands = abi.encodePacked(uint8(Commands.V4_SWAP));
            inputs = new bytes[](1);
            inputs[0] = abi.encode(actions, actionParams);
        }

        IUniversalRouter(router).execute{value: nativeValue}(commands, inputs, block.timestamp);
    }

    function expectedFee(uint256 elapsed) internal pure returns (uint256) {
        uint256 f = BASE_FEE + elapsed * FEE_PER_SECOND;
        return f > MAX_FEE ? MAX_FEE : f;
    }

    function expectedExactInOutput(uint256 amountIn, uint256 priceX96, uint256 fee)
        internal pure returns (uint256)
    {
        uint256 afterFee = amountIn * (FEE_DENOM - fee) / FEE_DENOM;
        return FullMath.mulDiv(afterFee, priceX96, Q96);
    }

    function expectedExactOutInput(uint256 amountOut, uint256 priceX96, uint256 fee)
        internal pure returns (uint256)
    {
        uint256 beforeFee = FullMath.mulDivRoundingUp(amountOut, Q96, priceX96);
        return FullMath.mulDivRoundingUp(beforeFee, FEE_DENOM, FEE_DENOM - fee);
    }

    function expectedExactInOutputOneForZero(uint256 amountIn, uint256 priceX96, uint256 fee)
        internal pure returns (uint256)
    {
        uint256 afterFee = amountIn * (FEE_DENOM - fee) / FEE_DENOM;
        return FullMath.mulDiv(afterFee, Q96, priceX96);
    }

    function expectedExactOutInputOneForZero(uint256 amountOut, uint256 priceX96, uint256 fee)
        internal pure returns (uint256)
    {
        uint256 beforeFee = FullMath.mulDivRoundingUp(amountOut, priceX96, Q96);
        return FullMath.mulDivRoundingUp(beforeFee, FEE_DENOM, FEE_DENOM - fee);
    }
}
