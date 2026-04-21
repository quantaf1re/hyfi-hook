pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IV4Quoter} from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {Utils} from "../../test/Utils.sol";

/// @notice Debug script: call V4 Quoter for HyFiHook pool WITHOUT try/catch
///         so the full revert reason is visible.
///
/// Usage:
///   source .env && forge script script/benchmark/DebugBenchmarkQuote.s.sol \
///       --rpc-url $RPC_URL_MATIC -vvvv
contract DebugBenchmarkQuote is Script, Utils {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    IV4Quoter public v4Quoter = IV4Quoter(0xb3d5c3Dfc3a7aEbFF71895A7191796BFFc2c81b9);
    IPoolManager public pm = IPoolManager(AddressConstants.getPoolManagerAddress(block.chainid));
    HyFiHook public hook = HyFiHook(payable(0x23bECbf4bA776B910E105A20060e47ae43020888));

    // HyFiHook pool key
    Currency public currency0 = Currency.wrap(address(0));                                     // Native
    Currency public currency1 = Currency.wrap(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);     // USDC
    uint24 public fee = 0;
    int24 public tickSpacing = 1;
    IHooks public hooks = IHooks(address(hook));

    // Quote params
    uint128 public amountIn = 200e18;       // 200 POL (~$50)
    bool public zeroForOne = true;          // sell POL for USDC

    function run() external {
        PoolKey memory key = PoolKey(currency0, currency1, fee, tickSpacing, hooks);
        PoolId id = key.toId();

        // --- Pool state ---
        console2.log("=== Pool State ===");
        console2.log("PoolManager:", address(pm));
        console2.log("V4Quoter:", address(v4Quoter));
        console2.log("Hook:", address(hooks));

        (uint160 sqrtPriceX96, int24 tick,,) = pm.getSlot0(id);
        console2.log("sqrtPriceX96:", sqrtPriceX96);
        console2.log("tick:", tick);

        uint128 liquidity = pm.getLiquidity(id);
        console2.log("liquidity:", liquidity);

        // 6909 balances of the hook
        uint256 bal0 = pm.balanceOf(address(hooks), uint256(uint160(Currency.unwrap(currency0))));
        uint256 bal1 = pm.balanceOf(address(hooks), uint256(uint160(Currency.unwrap(currency1))));
        console2.log("hook 6909 bal0: %e", bal0);
        console2.log("hook 6909 bal1: %e", bal1);

        // --- Hook price state ---
        (uint112 bidPriceX96, uint112 spreadX96, uint32 lastUpdate) = hook.getPrices(id);
        console2.log("\n=== Hook Price State ===");
        console2.log("bidPriceX96:", uint256(bidPriceX96));
        console2.log("spreadX96:", uint256(spreadX96));
        console2.log("lastUpdate:", uint256(lastUpdate));
        if (bidPriceX96 > 0) {
            // price = bidPriceX96 / 2^96  (token1 per token0)
            // Use 1e18 scaling for display: price_e18 = bidPriceX96 * 1e18 / 2^96
            uint256 priceE18 = uint256(bidPriceX96) * 1e18 / (1 << 96);
            console2.log("bid price (token1/token0, 18dp): %e", priceE18);
            uint256 askE18 = (uint256(bidPriceX96) + uint256(spreadX96)) * 1e18 / (1 << 96);
            console2.log("ask price (token1/token0, 18dp): %e", askE18);
        }

        // --- Quote (no try/catch — revert will show full trace with -vvvv) ---
        console2.log("\n=== Quoting ===");
        console2.log("zeroForOne:", zeroForOne);
        console2.log("amountIn: %e", uint256(amountIn));

        (uint256 amountOut, uint256 gasEstimate) = v4Quoter.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams(key, zeroForOne, amountIn, bytes(""))
        );

        console2.log("amountOut: %e", amountOut);
        console2.log("gasEstimate:", gasEstimate);
    }
}
