pragma solidity ^0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HyFiHook} from "../src/HyFiHook.sol";
import {ILPQuoter} from "../src/interfaces/ILPQuoter.sol";
import {SimpleQuoter} from "../src/SimpleQuoter.sol";

abstract contract Utils is StdCheats {
    Vm private constant _cheats = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    using CurrencyLibrary for Currency;

    uint256 internal constant BASE_FEE       = 500;
    uint256 internal constant FEE_PER_SECOND = 100;
    uint256 internal constant MAX_FEE        = 1_000_000;
    uint256 internal constant FEE_DENOM      = 1_000_000;
    uint256 internal constant Q96            = 1 << 96;
    address internal constant ADDR_ZERO      = address(0);

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
            inputs[1] = abi.encode(ADDR_ZERO, address(this), uint256(0));
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

    function _mineSalt(bytes memory initcode, uint160 flags, address deployer) internal pure returns (bytes32 salt) {
        bytes32 initcodeHash = keccak256(initcode);
        uint256 i;
        while (true) {
            salt = bytes32(i);
            address predicted = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initcodeHash))))
            );
            if (uint160(predicted) & Hooks.ALL_HOOK_MASK == flags) return salt;
            ++i;
        }
    }

    function getPriceFromSqrtPriceX96(uint160 sqrtPriceX96, bool invertPrice, uint8 decsT0, uint8 decsT1) internal pure returns (uint256 price) {
        uint256 priceX192 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        price = Math.mulDiv(priceX192, 1e18, 1 << 192);
        price = (price * (10 ** decsT0)) / (10 ** decsT1);
        if (invertPrice) {
            price = Math.mulDiv(1e18, 1e18, price);
        }
    }

    function getSqrtPriceX96FromPrice(uint256 price, bool invertPrice, uint8 decsT0, uint8 decsT1) internal pure returns (uint160) {
        if (invertPrice) {
            price = Math.mulDiv(1e18, 1e18, price);
        }
        price = (price * (10 ** decsT1)) / (10 ** decsT0);
        uint256 priceX192 = Math.mulDiv(price, 1 << 192, 1e18);
        return uint160(Math.sqrt(priceX192));
    }

    function convAmToOther(uint256 am, uint256 price, uint8 decsOriginal, uint8 decsOutput) internal pure returns (uint256) {
        return (am * price * (10 ** decsOutput)) / (1e18 * (10 ** decsOriginal));
    }

    function formatNumToStrDecimal(uint256 amount, uint8 decimals) internal pure returns (string memory) {
        if (decimals == 0) return Strings.toString(amount);
        uint256 divisor = 10 ** uint256(decimals);
        uint256 integerPart = amount / divisor;
        uint256 fractionalPart = amount % divisor;
        if (fractionalPart == 0) return Strings.toString(integerPart);

        bytes memory fractionalDigits = bytes(Strings.toString(fractionalPart));
        bytes memory padded = new bytes(decimals);
        uint256 leadingZeros = decimals - fractionalDigits.length;
        for (uint256 i = 0; i < decimals; ++i) {
            padded[i] = i < leadingZeros ? bytes1("0") : fractionalDigits[i - leadingZeros];
        }

        uint256 end = decimals;
        while (end > 0 && padded[end - 1] == bytes1("0")) end--;
        if (end == 0) return Strings.toString(integerPart);

        bytes memory trimmed = new bytes(end);
        for (uint256 i = 0; i < end; ++i) trimmed[i] = padded[i];
        return string(abi.encodePacked(Strings.toString(integerPart), ".", trimmed));
    }

    function logTokenBal(string memory label, string memory symbol, uint256 amount, uint8 decimals) internal pure {
        console2.log(string.concat(label, ": ", formatNumToStrDecimal(amount, decimals), " ", symbol));
    }

    function setPricesSingle(HyFiHook hook_, PoolId pid, uint112 bid, uint112 spread) internal {
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = pid;
        uint112[] memory bids = new uint112[](1);
        bids[0] = bid;
        uint112[] memory spreads = new uint112[](1);
        spreads[0] = spread;
        hook_.setPrices(pids, bids, spreads);
    }

    function registerMM(HyFiHook hook_, address mm, PoolId pid, ILPQuoter q) internal {
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = pid;
        ILPQuoter[] memory quoters = new ILPQuoter[](1);
        quoters[0] = q;
        _cheats.prank(mm);
        hook_.registerPools(pids, quoters);
    }

    function deregisterMM(HyFiHook hook_, address mm, PoolId pid) internal {
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = pid;
        _cheats.prank(mm);
        hook_.deregisterPools(pids);
    }

    function fundMM(
        HyFiHook hook_,
        address mm,
        SimpleQuoter q,
        address token,
        uint256 nativeAm,
        uint256 tokenAm
    ) internal {
        hook_.addToWhitelist(mm);
        _cheats.deal(mm, nativeAm);
        deal(token, mm, tokenAm);
        _cheats.startPrank(mm);
        q.deposit{value: nativeAm}(Currency.wrap(address(0)), nativeAm);
        IERC20(token).approve(address(q), tokenAm);
        q.deposit(Currency.wrap(token), tokenAm);
        _cheats.stopPrank();
    }
}
