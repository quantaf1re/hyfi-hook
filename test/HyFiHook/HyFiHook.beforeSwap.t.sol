pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {ILPQuoter} from "../../src/interfaces/ILPQuoter.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {RevertingQuoter} from "./mocks/MockQuoters.sol";

contract HyFiHookBeforeSwapTest is HyFiHookSharedSetup {
    using CurrencyLibrary for Currency;

    uint160 constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

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
        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;

        uint256 protocolFees0Before = hook.protocolFees(native);
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        assertEq(hook.protocolFees(native) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(hook.protocolFees(usdc), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), amountIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, expectedOut, "trader token1 received");
        assertEq(hook.lpBalances(mm1, native) - mm1Bal0Before, amountIn - protocolCut, "mm1 native balance increase minus protocol cut");
        assertEq(mm1Bal1Before - hook.lpBalances(mm1, usdc), expectedOut, "mm1 usdc balance decrease");
    }

    // =====================================================================
    //  Exact input — oneForZero (sell token1 → get token0 at ask)
    // =====================================================================

    function test_beforeSwap_exactIn_oneForZero() public {
        assertEq(hook.protocolFeePips(), DEFAULT_PROTOCOL_FEE_PIPS);

        uint256 amountIn = 1e6; // 1 USDC
        uint256 fee = expectedFee(0);
        uint256 askPrice = uint256(BID_PRICE_X96) + uint256(SPREAD_X96);
        uint256 expectedOut = expectedExactInOutputOneForZero(amountIn, askPrice, fee);
        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;

        uint256 protocolFees1Before = hook.protocolFees(usdc);
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);

        swap(UNIVERSAL_ROUTER, poolKey, false, -int256(amountIn));

        assertEq(hook.protocolFees(native), 0, "no protocol fees on output side");
        assertEq(hook.protocolFees(usdc) - protocolFees1Before, protocolCut, "protocol fee accrues on input side");
        assertEq(trader1Before - usdc.balanceOfSelf(), amountIn, "trader token1 spent");
        assertEq(native.balanceOfSelf() - trader0Before, expectedOut, "trader token0 received");
        assertEq(hook.lpBalances(mm1, usdc) - mm1Bal1Before, amountIn - protocolCut, "mm1 usdc balance increase minus protocol cut");
        assertEq(mm1Bal0Before - hook.lpBalances(mm1, native), expectedOut, "mm1 native balance decrease");
    }

    // =====================================================================
    //  Exact output — zeroForOne (buy token1, pay token0 at bid)
    // =====================================================================

    function test_beforeSwap_exactOut_zeroForOne() public {
        uint256 amountOut = 500_000; // 0.5 USDC
        uint256 fee = expectedFee(0);
        uint256 bidPrice = uint256(BID_PRICE_X96);
        uint256 expectedIn = expectedExactOutInput(amountOut, bidPrice, fee);
        uint256 protocolCut = expectedIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;

        uint256 protocolFees0Before = hook.protocolFees(native);
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);

        swap(UNIVERSAL_ROUTER, poolKey, true, int256(amountOut));

        assertEq(hook.protocolFees(native) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(hook.protocolFees(usdc), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), expectedIn, "trader token0 paid");
        assertEq(usdc.balanceOfSelf() - trader1Before, amountOut, "trader token1 received exact");
        assertEq(hook.lpBalances(mm1, native) - mm1Bal0Before, expectedIn - protocolCut, "mm1 native balance increase minus protocol cut");
        assertEq(mm1Bal1Before - hook.lpBalances(mm1, usdc), amountOut, "mm1 usdc balance decrease");
    }

    // =====================================================================
    //  Exact output — oneForZero (buy token0, pay token1 at ask)
    // =====================================================================

    function test_beforeSwap_exactOut_oneForZero() public {
        uint256 amountOut = 5e17; // 0.5 POL
        uint256 fee = expectedFee(0);
        uint256 askPrice = uint256(BID_PRICE_X96) + uint256(SPREAD_X96);
        uint256 expectedIn = expectedExactOutInputOneForZero(amountOut, askPrice, fee);
        uint256 protocolCut = expectedIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;

        uint256 protocolFees1Before = hook.protocolFees(usdc);
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);

        swap(UNIVERSAL_ROUTER, poolKey, false, int256(amountOut));

        assertEq(hook.protocolFees(native), 0, "no protocol fees on output side");
        assertEq(hook.protocolFees(usdc) - protocolFees1Before, protocolCut, "protocol fee accrues on input side");
        assertEq(trader1Before - usdc.balanceOfSelf(), expectedIn, "trader token1 paid");
        assertEq(native.balanceOfSelf() - trader0Before, amountOut, "trader token0 received exact");
        assertEq(hook.lpBalances(mm1, usdc) - mm1Bal1Before, expectedIn - protocolCut, "mm1 usdc balance increase minus protocol cut");
        assertEq(mm1Bal0Before - hook.lpBalances(mm1, native), amountOut, "mm1 native balance decrease");
    }

    // =====================================================================
    //  Fee increases with staleness
    // =====================================================================

    function test_beforeSwap_feeIncreasesWithStaleness() public {
        uint256 amountIn = 1e18;
        uint256 bidPrice = uint256(BID_PRICE_X96);

        uint256 out0 = expectedExactInOutput(amountIn, bidPrice, expectedFee(0));

        vm.warp(block.timestamp + 10);
        uint256 expectedOut = expectedExactInOutput(amountIn, bidPrice, expectedFee(10));

        assertGt(out0, expectedOut, "output should decrease with more staleness");

        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;
        uint256 protocolFees0Before = hook.protocolFees(native);
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        assertEq(hook.protocolFees(native) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(hook.protocolFees(usdc), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), amountIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, expectedOut, "trader token1 received");
        assertEq(hook.lpBalances(mm1, native) - mm1Bal0Before, amountIn - protocolCut, "mm1 native balance increase minus protocol cut");
        assertEq(mm1Bal1Before - hook.lpBalances(mm1, usdc), expectedOut, "mm1 usdc balance decrease");
    }

    // =====================================================================
    //  Protocol fee accumulation
    // =====================================================================

    function test_beforeSwap_protocolFeeAccumulates() public {
        hook.setProtocolFee(10_000); // 1%

        uint256 amountIn = 1e18;
        uint256 protocolFeesBefore = hook.protocolFees(native);
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);
        uint256 expectedOut = expectedExactInOutput(amountIn, uint256(BID_PRICE_X96), expectedFee(0));

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        uint256 protocolFeesAfter = hook.protocolFees(native);
        uint256 expectedCut = amountIn * 10_000 / 1_000_000;
        assertEq(protocolFeesAfter - protocolFeesBefore, expectedCut, "protocol fee should accumulate");
        assertEq(hook.protocolFees(usdc), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), amountIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, expectedOut, "trader token1 received");
        assertEq(hook.lpBalances(mm1, native) - mm1Bal0Before, amountIn - expectedCut, "mm1 gets input minus protocol cut");
        assertEq(mm1Bal1Before - hook.lpBalances(mm1, usdc), expectedOut, "mm1 usdc should decrease by exact output");
    }

    // =====================================================================
    //  Multi-MM: best quote wins
    // =====================================================================

    function test_beforeSwap_bestQuoteWins() public {
        // mm1 already registered with SimpleQuoter (BASE_FEE=500)
        // Add mm2 with same quoter — both should have same price, mm1 wins (first found)
        address mm2 = makeAddr("mm2");
        hook.addToWhitelist(mm2);
        SimpleQuoter q2 = new SimpleQuoter(mm2, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);
        registerMM(hook, mm2, poolId, ILPQuoter(address(q2)));

        // Fund mm2
        vm.deal(mm2, 1_000_000 * 10 ** POL_DECIMALS);
        deal(USDC_ADDR, mm2, 1_000_000 * 10 ** USDC_DECIMALS);
        vm.startPrank(mm2);
        hook.deposit{value: 1_000 * 10 ** POL_DECIMALS}(native, 1_000 * 10 ** POL_DECIMALS);
        IERC20(USDC_ADDR).approve(address(hook), 1_000 * 10 ** USDC_DECIMALS);
        hook.deposit(usdc, 1_000 * 10 ** USDC_DECIMALS);
        vm.stopPrank();

        uint256 amountIn = 1e18;
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);
        uint256 mm2Bal0Before = hook.lpBalances(mm2, native);
        uint256 mm2Bal1Before = hook.lpBalances(mm2, usdc);
        uint256 expectedOut = expectedExactInOutput(amountIn, uint256(BID_PRICE_X96), expectedFee(0));
        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;
        uint256 protocolFees0Before = hook.protocolFees(native);

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        // Both quoters return the same output, so the first one (mm1) should win
        assertEq(hook.protocolFees(native) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(hook.protocolFees(usdc), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), amountIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, expectedOut, "trader token1 received");
        assertEq(hook.lpBalances(mm1, native) - mm1Bal0Before, amountIn - protocolCut, "mm1 native should increase minus protocol cut");
        assertEq(mm1Bal1Before - hook.lpBalances(mm1, usdc), expectedOut, "mm1 usdc should decrease by exact output");
        assertEq(hook.lpBalances(mm2, native), mm2Bal0Before, "mm2 native should be unchanged");
        assertEq(hook.lpBalances(mm2, usdc), mm2Bal1Before, "mm2 usdc should be unchanged");
    }

    // =====================================================================
    //  MM with insufficient balance is skipped
    // =====================================================================

    function test_beforeSwap_skipsMMWithInsufficientBalance() public {
        // Add mm2 with no balance
        address mm2 = makeAddr("mm2");
        hook.addToWhitelist(mm2);
        SimpleQuoter q2 = new SimpleQuoter(mm2, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);
        registerMM(hook, mm2, poolId, ILPQuoter(address(q2)));
        // mm2 has no deposits — should be skipped

        uint256 amountIn = 1e18;
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);
        uint256 mm2Bal0Before = hook.lpBalances(mm2, native);
        uint256 mm2Bal1Before = hook.lpBalances(mm2, usdc);
        uint256 expectedOut = expectedExactInOutput(amountIn, uint256(BID_PRICE_X96), expectedFee(0));
        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;
        uint256 protocolFees0Before = hook.protocolFees(native);

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        // mm1 should have filled the trade
        assertEq(hook.protocolFees(native) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(hook.protocolFees(usdc), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), amountIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, expectedOut, "trader token1 received");
        assertEq(hook.lpBalances(mm1, native) - mm1Bal0Before, amountIn - protocolCut, "mm1 native balance increase minus protocol cut");
        assertEq(mm1Bal1Before - hook.lpBalances(mm1, usdc), expectedOut, "mm1 usdc balance decrease");
        assertEq(hook.lpBalances(mm2, native), mm2Bal0Before, "mm2 native should be unchanged");
        assertEq(hook.lpBalances(mm2, usdc), mm2Bal1Before, "mm2 usdc should be unchanged");
    }

    // =====================================================================
    //  Spread: bid vs ask price difference
    // =====================================================================

    function test_beforeSwap_spreadMakesAskMoreExpensive() public {
        uint256 polIn = 1e18;
        uint256 fee = expectedFee(0);
        uint256 bidPrice = uint256(BID_PRICE_X96);
        uint256 askPrice = bidPrice + uint256(SPREAD_X96);

        uint256 usdcOut = expectedExactInOutput(polIn, bidPrice, fee);
        uint256 polBack = expectedExactInOutputOneForZero(usdcOut, askPrice, fee);
        assertLt(polBack, polIn, "round trip loses spread");
    }

    // =====================================================================
    //  Zero spread — bid equals ask
    // =====================================================================

    function test_beforeSwap_zeroSpread_bidEqualsAsk() public {
        setPricesSingle(hook, poolId, BID_PRICE_X96, 0);
        uint256 polIn = 1e18;
        uint256 fee = expectedFee(0);
        uint256 price = uint256(BID_PRICE_X96);

        uint256 expectedOut = expectedExactInOutput(polIn, price, fee);
        uint256 protocolCut = polIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;

        uint256 protocolFees0Before = hook.protocolFees(native);
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(polIn));

        assertEq(hook.protocolFees(native) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(hook.protocolFees(usdc), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), polIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, expectedOut, "trader token1 received");
        assertEq(hook.lpBalances(mm1, native) - mm1Bal0Before, polIn - protocolCut, "mm1 native balance increase minus protocol cut");
        assertEq(mm1Bal1Before - hook.lpBalances(mm1, usdc), expectedOut, "mm1 usdc balance decrease");
    }

    // =====================================================================
    //  Fresh price resets fee
    // =====================================================================

    function test_beforeSwap_freshPriceResetsFee() public {
        uint256 amountIn = 1e18;
        uint256 bidPrice = uint256(BID_PRICE_X96);

        vm.warp(block.timestamp + 100);
        uint256 staleOut = expectedExactInOutput(amountIn, bidPrice, expectedFee(100));

        setPricesSingle(hook, poolId, BID_PRICE_X96, SPREAD_X96);
        uint256 freshOut = expectedExactInOutput(amountIn, bidPrice, expectedFee(0));
        assertGt(freshOut, staleOut);

        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;
        uint256 protocolFees0Before = hook.protocolFees(native);
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        assertEq(hook.protocolFees(native) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(hook.protocolFees(usdc), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), amountIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, freshOut, "trader token1 received");
        assertEq(hook.lpBalances(mm1, native) - mm1Bal0Before, amountIn - protocolCut, "mm1 native balance increase minus protocol cut");
        assertEq(mm1Bal1Before - hook.lpBalances(mm1, usdc), freshOut, "mm1 usdc balance decrease");
    }

    // =====================================================================
    //  Rounding always favours hook / MM
    // =====================================================================

    function test_beforeSwap_roundingFavoursHook_exactIn() public {
        uint112 bid = uint112(Q96 * 3 / 7e13);
        setPricesSingle(hook, poolId, bid, uint112(Q96 / 1e16));

        uint256 amountIn = 1e18 + 1;
        uint256 fee = expectedFee(0);
        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;

        uint256 protocolFees0Before = hook.protocolFees(native);
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        uint256 hookGain0 = hook.lpBalances(mm1, native) - mm1Bal0Before;
        uint256 hookLoss1 = mm1Bal1Before - hook.lpBalances(mm1, usdc);

        assertEq(hookGain0, amountIn - protocolCut, "hook gets exact input minus protocol cut");

        uint256 afterFee = amountIn * (FEE_DENOM - fee) / FEE_DENOM;
        uint256 roundUpOutput = FullMath.mulDivRoundingUp(afterFee, uint256(bid), Q96);
        assertLe(hookLoss1, roundUpOutput, "hook pays <= roundUp output");

        assertEq(hook.protocolFees(native) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(hook.protocolFees(usdc), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), amountIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, hookLoss1, "trader token1 received equals hook payout");
    }

    function test_beforeSwap_roundingFavoursHook_exactOut() public {
        uint112 bid = uint112(Q96 * 3 / 7e13);
        setPricesSingle(hook, poolId, bid, uint112(Q96 / 1e16));

        uint256 amountOut = 100_001;
        uint256 fee = expectedFee(0);

        uint256 protocolFees0Before = hook.protocolFees(native);
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);

        swap(UNIVERSAL_ROUTER, poolKey, true, int256(amountOut));

        uint256 traderPaid = trader0Before - native.balanceOfSelf();
        uint256 protocolCut = traderPaid * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;
        uint256 hookGain0 = hook.lpBalances(mm1, native) - mm1Bal0Before;
        uint256 hookLoss1 = mm1Bal1Before - hook.lpBalances(mm1, usdc);

        uint256 inputBeforeFee = FullMath.mulDiv(amountOut, Q96, uint256(bid));
        uint256 inputMin = inputBeforeFee * FEE_DENOM / (FEE_DENOM - fee);
        assertGe(traderPaid, inputMin, "trader pays >= roundDown input");
        assertEq(hookGain0, traderPaid - protocolCut, "hook gets trader input minus protocol cut");
        assertEq(hookLoss1, amountOut, "hook pays exact output");

        assertEq(hook.protocolFees(native) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(hook.protocolFees(usdc), 0, "no protocol fees on output side");
        assertEq(usdc.balanceOfSelf() - trader1Before, amountOut, "trader token1 received exact");
    }

    // =====================================================================
    //  Dust exact-out
    // =====================================================================

    function test_beforeSwap_exactOut_zeroForOne_dustOutput() public {
        uint256[2] memory amounts = [uint256(1), uint256(10)];
        uint256 fee = expectedFee(0);
        uint256 bidPrice = uint256(BID_PRICE_X96);

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amountOut = amounts[i];
            uint256 expectedIn = expectedExactOutInput(amountOut, bidPrice, fee);
            uint256 protocolCut = expectedIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;

            uint256 protocolFees0Before = hook.protocolFees(native);
            uint256 trader0Before = native.balanceOfSelf();
            uint256 trader1Before = usdc.balanceOfSelf();
            uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
            uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);

            swap(UNIVERSAL_ROUTER, poolKey, true, int256(amountOut));

            assertEq(hook.protocolFees(native) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
            assertEq(hook.protocolFees(usdc), 0, "no protocol fees on output side");
            assertEq(trader0Before - native.balanceOfSelf(), expectedIn, "trader token0 paid");
            assertEq(usdc.balanceOfSelf() - trader1Before, amountOut, "trader token1 received");
            assertEq(hook.lpBalances(mm1, native) - mm1Bal0Before, expectedIn - protocolCut, "mm1 native balance increase minus protocol cut");
            assertEq(mm1Bal1Before - hook.lpBalances(mm1, usdc), amountOut, "mm1 usdc balance decrease");
        }
    }

    // =====================================================================
    //  Revert paths
    // =====================================================================

    function test_beforeSwap_RevertWhen_pairNotRegistered() public {
        PoolKey memory unregisteredKey = PoolKey({
            currency0: native,
            currency1: usdc,
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

    function test_beforeSwap_RevertWhen_noMMsRegistered() public {
        // Deregister mm1
        deregisterMM(hook, mm1, poolId);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1e18),
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.NoQuoteAvailable.selector);
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

    function test_beforeSwap_RevertWhen_zeroOutputFromQuoter() public {
        // Set price so low that output rounds to 0
        setPricesSingle(hook, poolId, 1, 0);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.NoQuoteAvailable.selector);
        hook.beforeSwap(address(this), poolKey, params, "");
    }

    function test_beforeSwap_RevertWhen_feeCapsAt100Percent() public {
        uint256 elapsed = (MAX_FEE - BASE_FEE) / FEE_PER_SECOND;
        vm.warp(block.timestamp + elapsed);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1e18),
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(pm));
        // At 100% fee, quoter reverts with ZeroOutput → catch → NoQuoteAvailable
        vm.expectRevert(HyFiHook.NoQuoteAvailable.selector);
        hook.beforeSwap(address(this), poolKey, params, "");
    }

    // =====================================================================
    //  Multi-MM: strictly better quote wins (different quoter logic)
    // =====================================================================

    function _fundMM(address mm) internal {
        hook.addToWhitelist(mm);
        vm.deal(mm, 1_000_000 * 10 ** POL_DECIMALS);
        deal(USDC_ADDR, mm, 1_000_000 * 10 ** USDC_DECIMALS);
        vm.startPrank(mm);
        hook.deposit{value: 1_000 * 10 ** POL_DECIMALS}(native, 1_000 * 10 ** POL_DECIMALS);
        IERC20(USDC_ADDR).approve(address(hook), 1_000 * 10 ** USDC_DECIMALS);
        hook.deposit(usdc, 1_000 * 10 ** USDC_DECIMALS);
        vm.stopPrank();
    }

    function test_beforeSwap_betterQuoterWins_exactIn_zeroForOne() public {
        // mm1 uses SimpleQuoter (default baseFee=500). mm2 uses a zero-fee SimpleQuoter.
        address mm2 = makeAddr("mm2");
        _fundMM(mm2);
        SimpleQuoter q2 = new SimpleQuoter(mm2, 0, 0);
        registerMM(hook, mm2, poolId, ILPQuoter(address(q2)));

        uint256 amountIn = 1e18;
        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;
        // Zero-fee quote: mulDiv(amountIn, BID_PRICE_X96, Q96) — no fee applied
        uint256 expectedOut = FullMath.mulDiv(amountIn, uint256(BID_PRICE_X96), Q96);

        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);
        uint256 mm2Bal0Before = hook.lpBalances(mm2, native);
        uint256 mm2Bal1Before = hook.lpBalances(mm2, usdc);
        uint256 trader1Before = usdc.balanceOfSelf();

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        // mm2 should win because zero-fee quoter gives strictly higher output
        assertEq(usdc.balanceOfSelf() - trader1Before, expectedOut, "trader gets zero-fee output");
        assertEq(hook.lpBalances(mm2, native) - mm2Bal0Before, amountIn - protocolCut, "mm2 native credited minus protocol cut");
        assertEq(mm2Bal1Before - hook.lpBalances(mm2, usdc), expectedOut, "mm2 usdc debited by exact output");
        assertEq(hook.lpBalances(mm1, native), mm1Bal0Before, "mm1 native untouched (lost bid)");
        assertEq(hook.lpBalances(mm1, usdc), mm1Bal1Before, "mm1 usdc untouched (lost bid)");
    }

    function test_beforeSwap_betterQuoterWins_exactOut_zeroForOne() public {
        // mm2 with zero-fee SimpleQuoter requires strictly less input than mm1
        address mm2 = makeAddr("mm2");
        _fundMM(mm2);
        SimpleQuoter q2 = new SimpleQuoter(mm2, 0, 0);
        registerMM(hook, mm2, poolId, ILPQuoter(address(q2)));

        uint256 amountOut = 500_000;
        uint256 expectedIn = FullMath.mulDivRoundingUp(amountOut, Q96, uint256(BID_PRICE_X96));
        uint256 protocolCut = expectedIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;

        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);
        uint256 mm2Bal0Before = hook.lpBalances(mm2, native);
        uint256 mm2Bal1Before = hook.lpBalances(mm2, usdc);
        uint256 trader0Before = native.balanceOfSelf();

        swap(UNIVERSAL_ROUTER, poolKey, true, int256(amountOut));

        assertEq(trader0Before - native.balanceOfSelf(), expectedIn, "trader pays zero-fee input");
        assertEq(hook.lpBalances(mm2, native) - mm2Bal0Before, expectedIn - protocolCut, "mm2 native credited");
        assertEq(mm2Bal1Before - hook.lpBalances(mm2, usdc), amountOut, "mm2 usdc debited exact output");
        assertEq(hook.lpBalances(mm1, native), mm1Bal0Before, "mm1 untouched");
        assertEq(hook.lpBalances(mm1, usdc), mm1Bal1Before, "mm1 untouched");
    }

    // =====================================================================
    //  Reverting quoter is skipped, next MM fills
    // =====================================================================

    function test_beforeSwap_revertingQuoterSkipped() public {
        // Add mm2 with a quoter that always reverts. mm1 should still fill the trade.
        address mm2 = makeAddr("mm2");
        _fundMM(mm2);
        RevertingQuoter qRevert = new RevertingQuoter();
        registerMM(hook, mm2, poolId, ILPQuoter(address(qRevert)));

        uint256 amountIn = 1e18;
        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;
        uint256 expectedOut = expectedExactInOutput(amountIn, uint256(BID_PRICE_X96), expectedFee(0));

        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);
        uint256 mm2Bal0Before = hook.lpBalances(mm2, native);
        uint256 mm2Bal1Before = hook.lpBalances(mm2, usdc);

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        assertEq(hook.lpBalances(mm1, native) - mm1Bal0Before, amountIn - protocolCut, "mm1 fills after mm2 skipped");
        assertEq(mm1Bal1Before - hook.lpBalances(mm1, usdc), expectedOut, "mm1 usdc debited");
        assertEq(hook.lpBalances(mm2, native), mm2Bal0Before, "mm2 (reverting) untouched");
        assertEq(hook.lpBalances(mm2, usdc), mm2Bal1Before, "mm2 (reverting) untouched");
    }

    // =====================================================================
    //  All MMs' quoters revert → NoQuoteAvailable
    // =====================================================================

    function test_beforeSwap_RevertWhen_allQuotersRevert() public {
        // Replace mm1's quoter with a reverting one
        RevertingQuoter qRevert = new RevertingQuoter();
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        ILPQuoter[] memory qs = new ILPQuoter[](1);
        qs[0] = ILPQuoter(address(qRevert));
        vm.prank(mm1);
        hook.updateQuoters(pids, qs);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1e18),
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.NoQuoteAvailable.selector);
        hook.beforeSwap(address(this), poolKey, params, "");
    }

    // =====================================================================
    //  Better quoter skipped due to balance → worse quoter wins
    // =====================================================================

    function test_beforeSwap_betterMMSkippedForBalance_worseWins() public {
        // mm2 has a better quoter but no output-side balance
        address mm2 = makeAddr("mm2");
        hook.addToWhitelist(mm2);
        SimpleQuoter q2 = new SimpleQuoter(mm2, 0, 0);
        registerMM(hook, mm2, poolId, ILPQuoter(address(q2)));
        // mm2 never deposits → insufficient USDC for any swap output

        uint256 amountIn = 1e18;
        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;
        uint256 expectedOut = expectedExactInOutput(amountIn, uint256(BID_PRICE_X96), expectedFee(0));

        uint256 mm1Bal0Before = hook.lpBalances(mm1, native);
        uint256 mm1Bal1Before = hook.lpBalances(mm1, usdc);

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        // mm1 fills with its worse quote since mm2 was skipped for insufficient balance
        assertEq(hook.lpBalances(mm1, native) - mm1Bal0Before, amountIn - protocolCut, "mm1 native credited");
        assertEq(mm1Bal1Before - hook.lpBalances(mm1, usdc), expectedOut, "mm1 debits SimpleQuoter output");
    }

    // =====================================================================
    //  Reentrancy: malicious quoter tries to call beforeSwap during quoting
    // =====================================================================

    // NOTE: Constructing a true reentrancy test against beforeSwap requires
    // either a malicious PoolManager or a quoter that can re-enter during the
    // staticcall — neither of which is possible given the EVM staticcall
    // semantics in _findBestQuote. The `nonReentrant` modifier is defensive
    // and protects against future non-staticcall code paths.
}
