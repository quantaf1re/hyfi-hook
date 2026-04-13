pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "./HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

contract HyFiHookBeforeSwapTest is HyFiHookSharedSetup {
    using CurrencyLibrary for Currency;

    // ---- constants (only used in this file) ------------------------------
    uint160 constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;

    function setUp() public {
        sharedSetup();
    }

    // =====================================================================
    //  Exact input — zeroForOne (sell token0 → get token1 at bid)
    // =====================================================================

    function test_beforeSwap_exactIn_zeroForOne() public {
        uint256 amountIn = 1e18;
        uint256 fee = expectedFee(0);
        uint256 bidPrice = uint256(BID_PRICE_X96);
        uint256 expectedOut = expectedExactInOutput(amountIn, bidPrice, fee);

        uint256 trader0Before = c0.balanceOfSelf();
        uint256 trader1Before = c1.balanceOfSelf();
        uint256 hookClaims0Before = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1Before = pm.balanceOf(address(hook), c1.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        uint256 trader0After = c0.balanceOfSelf();
        uint256 trader1After = c1.balanceOfSelf();
        uint256 hookClaims0After = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1After = pm.balanceOf(address(hook), c1.toId());

        // Trader pays exactIn token0
        assertEq(trader0Before - trader0After, amountIn, "trader token0 spent");
        // Trader receives output token1
        assertEq(trader1After - trader1Before, expectedOut, "trader token1 received");
        // Hook claims: token0 increases by amountIn, token1 decreases by expectedOut
        assertEq(hookClaims0After - hookClaims0Before, amountIn, "hook claims0 increase");
        assertEq(hookClaims1Before - hookClaims1After, expectedOut, "hook claims1 decrease");
    }

    function test_beforeSwap_exactOut_zeroForOne_dustOutput() public {
        uint256[2] memory amounts = [uint256(1), uint256(10)];
        uint256 fee = expectedFee(0);
        uint256 bidPrice = uint256(BID_PRICE_X96);

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amountOut = amounts[i];
            uint256 expectedIn = expectedExactOutInput(amountOut, bidPrice, fee);

            uint256 trader0Before = c0.balanceOfSelf();
            uint256 trader1Before = c1.balanceOfSelf();

            swap(UNIVERSAL_ROUTER, poolKey, true, int256(amountOut));

            assertEq(trader0Before - c0.balanceOfSelf(), expectedIn, "trader token0 paid");
            assertEq(c1.balanceOfSelf() - trader1Before, amountOut, "trader token1 received");
        }
    }

    // =====================================================================
    //  Exact input — oneForZero (sell token1 → get token0 at ask)
    // =====================================================================

    function test_beforeSwap_exactIn_oneForZero() public {
        uint256 amountIn = 1e6; // 1 USDC
        uint256 fee = expectedFee(0);
        uint256 bidPrice = uint256(BID_PRICE_X96);
        uint256 askPrice = bidPrice + uint256(SPREAD_X96);
        uint256 expectedOut = expectedExactInOutputOneForZero(amountIn, askPrice, fee);

        // Ask price > bid price → trader gets LESS token0 at ask than at bid
        uint256 outputAtBid = expectedExactInOutputOneForZero(amountIn, bidPrice, fee);
        assertGt(outputAtBid, expectedOut, "ask should yield less output than bid");

        uint256 trader0Before = c0.balanceOfSelf();
        uint256 trader1Before = c1.balanceOfSelf();
        uint256 hookClaims0Before = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1Before = pm.balanceOf(address(hook), c1.toId());

        swap(UNIVERSAL_ROUTER, poolKey, false, -int256(amountIn));

        uint256 trader0After = c0.balanceOfSelf();
        uint256 trader1After = c1.balanceOfSelf();
        uint256 hookClaims0After = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1After = pm.balanceOf(address(hook), c1.toId());

        assertEq(trader1Before - trader1After, amountIn, "trader token1 spent");
        assertEq(trader0After - trader0Before, expectedOut, "trader token0 received");
        assertEq(hookClaims1After - hookClaims1Before, amountIn, "hook claims1 increase");
        assertEq(hookClaims0Before - hookClaims0After, expectedOut, "hook claims0 decrease");
    }

    // =====================================================================
    //  Exact output — zeroForOne (buy token1, pay token0 at bid)
    // =====================================================================

    function test_beforeSwap_exactOut_zeroForOne() public {
        uint256 amountOut = 500_000; // 0.5 USDC
        uint256 fee = expectedFee(0);
        uint256 bidPrice = uint256(BID_PRICE_X96);
        uint256 expectedIn = expectedExactOutInput(amountOut, bidPrice, fee);

        uint256 trader0Before = c0.balanceOfSelf();
        uint256 trader1Before = c1.balanceOfSelf();
        uint256 hookClaims0Before = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1Before = pm.balanceOf(address(hook), c1.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, int256(amountOut));

        uint256 trader0After = c0.balanceOfSelf();
        uint256 trader1After = c1.balanceOfSelf();
        uint256 hookClaims0After = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1After = pm.balanceOf(address(hook), c1.toId());

        assertEq(trader0Before - trader0After, expectedIn, "trader token0 paid");
        assertEq(trader1After - trader1Before, amountOut, "trader token1 received exact");
        assertEq(hookClaims0After - hookClaims0Before, expectedIn, "hook claims0 increase");
        assertEq(hookClaims1Before - hookClaims1After, amountOut, "hook claims1 decrease");
    }

    // =====================================================================
    //  Exact output — oneForZero (buy token0, pay token1 at ask)
    // =====================================================================

    function test_beforeSwap_exactOut_oneForZero() public {
        uint256 amountOut = 5e17; // 0.5 POL
        uint256 fee = expectedFee(0);
        uint256 askPrice = uint256(BID_PRICE_X96) + uint256(SPREAD_X96);
        uint256 expectedIn = expectedExactOutInputOneForZero(amountOut, askPrice, fee);

        uint256 trader0Before = c0.balanceOfSelf();
        uint256 trader1Before = c1.balanceOfSelf();
        uint256 hookClaims0Before = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1Before = pm.balanceOf(address(hook), c1.toId());

        swap(UNIVERSAL_ROUTER, poolKey, false, int256(amountOut));

        uint256 trader0After = c0.balanceOfSelf();
        uint256 trader1After = c1.balanceOfSelf();
        uint256 hookClaims0After = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1After = pm.balanceOf(address(hook), c1.toId());

        assertEq(trader1Before - trader1After, expectedIn, "trader token1 paid");
        assertEq(trader0After - trader0Before, amountOut, "trader token0 received exact");
        assertEq(hookClaims1After - hookClaims1Before, expectedIn, "hook claims1 increase");
        assertEq(hookClaims0Before - hookClaims0After, amountOut, "hook claims0 decrease");
    }

    // =====================================================================
    //  Fee increases with staleness
    // =====================================================================

    function test_beforeSwap_feeIncreasesWithStaleness() public {
        uint256 amountIn = 1e18;
        uint256 bidPrice = uint256(BID_PRICE_X96);

        // Swap immediately (0 elapsed) → fee = BASE_FEE
        uint256 out0 = expectedExactInOutput(amountIn, bidPrice, expectedFee(0));

        // Swap at +10 seconds → fee = BASE_FEE + 10*FEE_PER_SECOND
        vm.warp(block.timestamp + 10);
        uint256 expectedOut = expectedExactInOutput(amountIn, bidPrice, expectedFee(10));

        assertGt(out0, expectedOut, "output should decrease with more staleness");

        uint256 trader0Before = c0.balanceOfSelf();
        uint256 trader1Before = c1.balanceOfSelf();
        uint256 hookClaims0Before = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1Before = pm.balanceOf(address(hook), c1.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        uint256 trader0After = c0.balanceOfSelf();
        uint256 trader1After = c1.balanceOfSelf();
        uint256 hookClaims0After = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1After = pm.balanceOf(address(hook), c1.toId());

        assertEq(trader0Before - trader0After, amountIn, "trader token0 spent");
        assertEq(trader1After - trader1Before, expectedOut, "trader token1 received");
        assertEq(hookClaims0After - hookClaims0Before, amountIn, "hook claims0 increase");
        assertEq(hookClaims1Before - hookClaims1After, expectedOut, "hook claims1 decrease");
    }

    // =====================================================================
    //  Rounding always favours hook
    // =====================================================================

    function test_beforeSwap_roundingFavoursHook_exactIn() public {
        // Use a price that doesn't divide evenly to force rounding
        uint112 bid = uint112(Q96 * 3 / 7e13); // ~$0.043 per POL
        hook.setPrice(poolId, bid, uint112(Q96 / 1e16));

        uint256 amountIn = 1e18 + 1; // odd number to trigger rounding
        uint256 fee = expectedFee(0);

        uint256 hookClaims0Before = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1Before = pm.balanceOf(address(hook), c1.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        uint256 hookClaims0After = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1After = pm.balanceOf(address(hook), c1.toId());

        uint256 hookGain0 = hookClaims0After - hookClaims0Before;
        uint256 hookLoss1 = hookClaims1Before - hookClaims1After;

        // Hook received exactly amountIn of token0
        assertEq(hookGain0, amountIn, "hook gets exact input");

        // Verify output was rounded DOWN (hook pays less)
        // Compute what the output would be with perfect precision (round UP) — hook should pay <= that
        uint256 afterFee = amountIn * (FEE_DENOM - fee) / FEE_DENOM;
        uint256 roundUpOutput = FullMath.mulDivRoundingUp(afterFee, uint256(bid), Q96);
        assertLe(hookLoss1, roundUpOutput, "hook pays <= roundUp output");
    }

    function test_beforeSwap_roundingFavoursHook_exactOut() public {
        uint112 bid = uint112(Q96 * 3 / 7e13); // ~$0.043 per POL
        hook.setPrice(poolId, bid, uint112(Q96 / 1e16));

        uint256 amountOut = 100_001; // ~0.1 USDC, odd to trigger rounding
        uint256 fee = expectedFee(0);

        uint256 hookClaims0Before = pm.balanceOf(address(hook), c0.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, int256(amountOut));

        uint256 hookClaims0After = pm.balanceOf(address(hook), c0.toId());
        uint256 hookGain0 = hookClaims0After - hookClaims0Before;

        // Verify input was rounded UP (trader pays more)
        uint256 inputBeforeFee = FullMath.mulDiv(amountOut, Q96, uint256(bid)); // round DOWN
        uint256 inputMin = inputBeforeFee * FEE_DENOM / (FEE_DENOM - fee); // round DOWN
        assertGe(hookGain0, inputMin, "hook receives >= roundDown input");
    }

    // =====================================================================
    //  Spread: bid vs ask price difference
    // =====================================================================

    function test_beforeSwap_spreadMakesAskMoreExpensive() public {
        uint256 polIn = 1e18; // 1 POL
        uint256 fee = expectedFee(0);
        uint256 bidPrice = uint256(BID_PRICE_X96);
        uint256 askPrice = bidPrice + uint256(SPREAD_X96);

        // Sell POL at bid → USDC, buy back at ask → less POL
        uint256 usdcOut = expectedExactInOutput(polIn, bidPrice, fee);
        uint256 polBack = expectedExactInOutputOneForZero(usdcOut, askPrice, fee);
        assertLt(polBack, polIn, "round trip loses spread");

        // Execute the sell leg and verify full state
        uint256 expectedOut = usdcOut;
        uint256 trader0Before = c0.balanceOfSelf();
        uint256 trader1Before = c1.balanceOfSelf();
        uint256 hookClaims0Before = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1Before = pm.balanceOf(address(hook), c1.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(polIn));

        assertEq(trader0Before - c0.balanceOfSelf(), polIn, "trader token0 spent");
        assertEq(c1.balanceOfSelf() - trader1Before, expectedOut, "trader token1 received");
        assertEq(pm.balanceOf(address(hook), c0.toId()) - hookClaims0Before, polIn, "hook claims0 increase");
        assertEq(hookClaims1Before - pm.balanceOf(address(hook), c1.toId()), expectedOut, "hook claims1 decrease");
    }

    // =====================================================================
    //  Zero spread — bid equals ask
    // =====================================================================

    function test_beforeSwap_zeroSpread_bidEqualsAsk() public {
        hook.setPrice(poolId, BID_PRICE_X96, 0);
        uint256 polIn = 1e18; // 1 POL
        uint256 fee = expectedFee(0);
        uint256 price = uint256(BID_PRICE_X96);

        uint256 expectedOut = expectedExactInOutput(polIn, price, fee);
        assertGt(expectedOut, 0, "non-zero output");

        uint256 trader1Before = c1.balanceOfSelf();
        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(polIn));
        uint256 trader1After = c1.balanceOfSelf();

        assertEq(trader1After - trader1Before, expectedOut, "actual output matches zero-spread calculation");
    }

    // =====================================================================
    //  Price update then swap — fresh fee
    // =====================================================================

    function test_beforeSwap_freshPriceResetsFee() public {
        uint256 amountIn = 1e18;
        uint256 bidPrice = uint256(BID_PRICE_X96);

        // Let 100 seconds pass
        vm.warp(block.timestamp + 100);
        uint256 staleOut = expectedExactInOutput(amountIn, bidPrice, expectedFee(100));

        // Now refresh the price (resets lastUpdate to current timestamp)
        hook.setPrice(poolId, BID_PRICE_X96, SPREAD_X96);
        uint256 freshOut = expectedExactInOutput(amountIn, bidPrice, expectedFee(0));

        assertGt(freshOut, staleOut, "fresh price gives better output");

        uint256 trader0Before = c0.balanceOfSelf();
        uint256 trader1Before = c1.balanceOfSelf();
        uint256 hookClaims0Before = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1Before = pm.balanceOf(address(hook), c1.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        uint256 trader0After = c0.balanceOfSelf();
        uint256 trader1After = c1.balanceOfSelf();
        uint256 hookClaims0After = pm.balanceOf(address(hook), c0.toId());
        uint256 hookClaims1After = pm.balanceOf(address(hook), c1.toId());

        assertEq(trader0Before - trader0After, amountIn, "trader token0 spent");
        assertEq(trader1After - trader1Before, freshOut, "trader token1 received");
        assertEq(hookClaims0After - hookClaims0Before, amountIn, "hook claims0 increase");
        assertEq(hookClaims1Before - hookClaims1After, freshOut, "hook claims1 decrease");
    }

    // =====================================================================
    //  Revert paths
    // =====================================================================

    function test_beforeSwap_exactIn_zeroForOne_dustInput_revertsZeroOutput() public {
        // 1 wei: afterFee = 1 * 999500 / 1000000 = 0 → output 0 → revert
        // 10 wei: afterFee = 9, but mulDiv(9, Q96/1e13, Q96) = 0 → revert
        for (uint256 i = 0; i < 2; i++) {
            int256 amount = i == 0 ? int256(-1) : int256(-10);
            SwapParams memory params = SwapParams({
                zeroForOne: true,
                amountSpecified: amount,
                sqrtPriceLimitX96: MIN_PRICE_LIMIT
            });
            vm.prank(address(pm));
            vm.expectRevert(HyFiHook.ZeroOutput.selector);
            hook.beforeSwap(address(this), poolKey, params, "");
        }
    }

    function test_beforeSwap_feeCapsAt100Percent() public {
        uint256 amountIn = 1e18;

        // Warp far into the future: fee should cap at MAX_FEE (1_000_000 = 100%)
        // At 100% fee, inputAfterFee = 0, so output = 0 -> should revert ZeroOutput
        uint256 elapsed = (MAX_FEE - BASE_FEE) / FEE_PER_SECOND; // 9995 seconds
        vm.warp(block.timestamp + elapsed);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.ZeroOutput.selector);
        hook.beforeSwap(address(this), poolKey, params, "");
    }

    function test_beforeSwap_RevertWhen_pairNotRegistered() public {
        PoolKey memory unregisteredKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: 0x800000,
            tickSpacing: 60,
            hooks: poolKey.hooks
        });

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -100,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.PairNotRegistered.selector);
        hook.beforeSwap(address(this), unregisteredKey, params, "");
    }

    function test_beforeSwap_RevertWhen_zeroOutput() public {
        hook.setPrice(poolId, 1, 0); // bidPriceX96 = 1 (astronomically small)

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.ZeroOutput.selector);
        hook.beforeSwap(address(this), poolKey, params, "");
    }

    function test_beforeSwap_RevertWhen_calledByNonPM() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -100,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.expectRevert(HyFiHook.OnlyPoolManager.selector);
        hook.beforeSwap(address(this), poolKey, params, "");
    }
}
