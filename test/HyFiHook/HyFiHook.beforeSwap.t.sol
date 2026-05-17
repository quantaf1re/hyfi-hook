// SPDX-License-Identifier: MIT
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

        uint256 protocolFees0Before = pm.balanceOf(address(hook), native.toId());
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = pm.balanceOf(address(quoter), native.toId());
        uint256 mm1Bal1Before = pm.balanceOf(address(quoter), usdc.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        assertEq(pm.balanceOf(address(hook), native.toId()) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(pm.balanceOf(address(hook), usdc.toId()), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), amountIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, expectedOut, "trader token1 received");
        assertEq(pm.balanceOf(address(quoter), native.toId()) - mm1Bal0Before, amountIn - protocolCut, "mm1 native balance increase minus protocol cut");
        assertEq(mm1Bal1Before - pm.balanceOf(address(quoter), usdc.toId()), expectedOut, "mm1 usdc balance decrease");
    }

    // =====================================================================
    //  Exact input — oneForZero (sell token1 → get token0 at ask)
    // =====================================================================

    function test_beforeSwap_exactIn_oneForZero() public {
        assertEq(hook.getProtocolFeePips(), DEFAULT_PROTOCOL_FEE_PIPS);

        uint256 amountIn = 1e6; // 1 USDC
        uint256 fee = expectedFee(0);
        uint256 askPrice = uint256(BID_PRICE_X96) + uint256(SPREAD_X96);
        uint256 expectedOut = expectedExactInOutputOneForZero(amountIn, askPrice, fee);
        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;

        uint256 protocolFees1Before = pm.balanceOf(address(hook), usdc.toId());
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = pm.balanceOf(address(quoter), native.toId());
        uint256 mm1Bal1Before = pm.balanceOf(address(quoter), usdc.toId());

        swap(UNIVERSAL_ROUTER, poolKey, false, -int256(amountIn));

        assertEq(pm.balanceOf(address(hook), native.toId()), 0, "no protocol fees on output side");
        assertEq(pm.balanceOf(address(hook), usdc.toId()) - protocolFees1Before, protocolCut, "protocol fee accrues on input side");
        assertEq(trader1Before - usdc.balanceOfSelf(), amountIn, "trader token1 spent");
        assertEq(native.balanceOfSelf() - trader0Before, expectedOut, "trader token0 received");
        assertEq(pm.balanceOf(address(quoter), usdc.toId()) - mm1Bal1Before, amountIn - protocolCut, "mm1 usdc balance increase minus protocol cut");
        assertEq(mm1Bal0Before - pm.balanceOf(address(quoter), native.toId()), expectedOut, "mm1 native balance decrease");
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

        uint256 protocolFees0Before = pm.balanceOf(address(hook), native.toId());
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = pm.balanceOf(address(quoter), native.toId());
        uint256 mm1Bal1Before = pm.balanceOf(address(quoter), usdc.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, int256(amountOut));

        assertEq(pm.balanceOf(address(hook), native.toId()) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(pm.balanceOf(address(hook), usdc.toId()), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), expectedIn, "trader token0 paid");
        assertEq(usdc.balanceOfSelf() - trader1Before, amountOut, "trader token1 received exact");
        assertEq(pm.balanceOf(address(quoter), native.toId()) - mm1Bal0Before, expectedIn - protocolCut, "mm1 native balance increase minus protocol cut");
        assertEq(mm1Bal1Before - pm.balanceOf(address(quoter), usdc.toId()), amountOut, "mm1 usdc balance decrease");
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

        uint256 protocolFees1Before = pm.balanceOf(address(hook), usdc.toId());
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = pm.balanceOf(address(quoter), native.toId());
        uint256 mm1Bal1Before = pm.balanceOf(address(quoter), usdc.toId());

        swap(UNIVERSAL_ROUTER, poolKey, false, int256(amountOut));

        assertEq(pm.balanceOf(address(hook), native.toId()), 0, "no protocol fees on output side");
        assertEq(pm.balanceOf(address(hook), usdc.toId()) - protocolFees1Before, protocolCut, "protocol fee accrues on input side");
        assertEq(trader1Before - usdc.balanceOfSelf(), expectedIn, "trader token1 paid");
        assertEq(native.balanceOfSelf() - trader0Before, amountOut, "trader token0 received exact");
        assertEq(pm.balanceOf(address(quoter), usdc.toId()) - mm1Bal1Before, expectedIn - protocolCut, "mm1 usdc balance increase minus protocol cut");
        assertEq(mm1Bal0Before - pm.balanceOf(address(quoter), native.toId()), amountOut, "mm1 native balance decrease");
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
        uint256 protocolFees0Before = pm.balanceOf(address(hook), native.toId());
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = pm.balanceOf(address(quoter), native.toId());
        uint256 mm1Bal1Before = pm.balanceOf(address(quoter), usdc.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        assertEq(pm.balanceOf(address(hook), native.toId()) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(pm.balanceOf(address(hook), usdc.toId()), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), amountIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, expectedOut, "trader token1 received");
        assertEq(pm.balanceOf(address(quoter), native.toId()) - mm1Bal0Before, amountIn - protocolCut, "mm1 native balance increase minus protocol cut");
        assertEq(mm1Bal1Before - pm.balanceOf(address(quoter), usdc.toId()), expectedOut, "mm1 usdc balance decrease");
    }

    // =====================================================================
    //  Protocol fee accumulation
    // =====================================================================

    function test_beforeSwap_protocolFeeAccumulates() public {
        hook.updateProtocolFee(10_000); // 1%

        uint256 amountIn = 1e18;
        uint256 protocolFeesBefore = pm.balanceOf(address(hook), native.toId());
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = pm.balanceOf(address(quoter), native.toId());
        uint256 mm1Bal1Before = pm.balanceOf(address(quoter), usdc.toId());
        uint256 expectedOut = expectedExactInOutput(amountIn, uint256(BID_PRICE_X96), expectedFee(0));

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        uint256 protocolFeesAfter = pm.balanceOf(address(hook), native.toId());
        uint256 expectedCut = amountIn * 10_000 / 1_000_000;
        assertEq(protocolFeesAfter - protocolFeesBefore, expectedCut, "protocol fee should accumulate");
        assertEq(pm.balanceOf(address(hook), usdc.toId()), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), amountIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, expectedOut, "trader token1 received");
        assertEq(pm.balanceOf(address(quoter), native.toId()) - mm1Bal0Before, amountIn - expectedCut, "mm1 gets input minus protocol cut");
        assertEq(mm1Bal1Before - pm.balanceOf(address(quoter), usdc.toId()), expectedOut, "mm1 usdc should decrease by exact output");
    }

    // =====================================================================
    //  hookData routing
    // =====================================================================

    function test_beforeSwap_emptyHookData_routesToDefaultQuoter() public {
        // With empty hookData the default quoter (mm1) handles the trade and
        // an alternative quoter (q2) must remain completely untouched.
        address mm2 = makeAddr("mm2");
        SimpleQuoter q2 = deployQuoterProxy(pm, address(hook), mm2, 0, 0);
        fundQuoter(mm2, q2, USDC_ADDR, 1_000 * 10 ** POL_DECIMALS, 1_000 * 10 ** USDC_DECIMALS);

        uint256 amountIn = 1e18;
        uint256 expectedOut = expectedExactInOutput(amountIn, uint256(BID_PRICE_X96), expectedFee(0));
        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;

        uint256 protocolFees0Before = pm.balanceOf(address(hook), native.toId());
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = pm.balanceOf(address(quoter), native.toId());
        uint256 mm1Bal1Before = pm.balanceOf(address(quoter), usdc.toId());
        uint256 mm2Bal0Before = pm.balanceOf(address(q2), native.toId());
        uint256 mm2Bal1Before = pm.balanceOf(address(q2), usdc.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn), "");

        // Trader
        assertEq(trader0Before - native.balanceOfSelf(), amountIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, expectedOut, "trader token1 received");
        // Default quoter debited / credited
        assertEq(pm.balanceOf(address(quoter), native.toId()) - mm1Bal0Before, amountIn - protocolCut, "default quoter native credited");
        assertEq(mm1Bal1Before - pm.balanceOf(address(quoter), usdc.toId()), expectedOut, "default quoter usdc debited");
        // Alternative quoter untouched
        assertEq(pm.balanceOf(address(q2), native.toId()), mm2Bal0Before, "q2 native untouched");
        assertEq(pm.balanceOf(address(q2), usdc.toId()), mm2Bal1Before, "q2 usdc untouched");
        // Protocol fees
        assertEq(pm.balanceOf(address(hook), native.toId()) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(pm.balanceOf(address(hook), usdc.toId()), 0, "no protocol fees on output side");
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
        setPricesSingle(hook, poolId, BID_PRICE_X96, 0, uint32(block.timestamp));
        uint256 polIn = 1e18;
        uint256 fee = expectedFee(0);
        uint256 price = uint256(BID_PRICE_X96);

        uint256 expectedOut = expectedExactInOutput(polIn, price, fee);
        uint256 protocolCut = polIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;

        uint256 protocolFees0Before = pm.balanceOf(address(hook), native.toId());
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = pm.balanceOf(address(quoter), native.toId());
        uint256 mm1Bal1Before = pm.balanceOf(address(quoter), usdc.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(polIn));

        assertEq(pm.balanceOf(address(hook), native.toId()) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(pm.balanceOf(address(hook), usdc.toId()), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), polIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, expectedOut, "trader token1 received");
        assertEq(pm.balanceOf(address(quoter), native.toId()) - mm1Bal0Before, polIn - protocolCut, "mm1 native balance increase minus protocol cut");
        assertEq(mm1Bal1Before - pm.balanceOf(address(quoter), usdc.toId()), expectedOut, "mm1 usdc balance decrease");
    }

    // =====================================================================
    //  Fresh price resets fee
    // =====================================================================

    function test_beforeSwap_freshPriceResetsFee() public {
        uint256 amountIn = 1e18;
        uint256 bidPrice = uint256(BID_PRICE_X96);

        vm.warp(block.timestamp + 100);
        uint256 staleOut = expectedExactInOutput(amountIn, bidPrice, expectedFee(100));

        setPricesSingle(hook, poolId, BID_PRICE_X96, SPREAD_X96, uint32(block.timestamp));
        uint256 freshOut = expectedExactInOutput(amountIn, bidPrice, expectedFee(0));
        assertGt(freshOut, staleOut);

        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;
        uint256 protocolFees0Before = pm.balanceOf(address(hook), native.toId());
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = pm.balanceOf(address(quoter), native.toId());
        uint256 mm1Bal1Before = pm.balanceOf(address(quoter), usdc.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        assertEq(pm.balanceOf(address(hook), native.toId()) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(pm.balanceOf(address(hook), usdc.toId()), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), amountIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, freshOut, "trader token1 received");
        assertEq(pm.balanceOf(address(quoter), native.toId()) - mm1Bal0Before, amountIn - protocolCut, "mm1 native balance increase minus protocol cut");
        assertEq(mm1Bal1Before - pm.balanceOf(address(quoter), usdc.toId()), freshOut, "mm1 usdc balance decrease");
    }

    // =====================================================================
    //  Rounding always favours hook / MM
    // =====================================================================

    function test_beforeSwap_roundingFavoursHook_exactIn() public {
        uint112 bid = uint112(Q96 * 3 / 7e13);
        setPricesSingle(hook, poolId, bid, uint112(Q96 / 1e16), uint32(block.timestamp));

        uint256 amountIn = 1e18 + 1;
        uint256 fee = expectedFee(0);
        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;

        uint256 protocolFees0Before = pm.balanceOf(address(hook), native.toId());
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = pm.balanceOf(address(quoter), native.toId());
        uint256 mm1Bal1Before = pm.balanceOf(address(quoter), usdc.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        uint256 hookGain0 = pm.balanceOf(address(quoter), native.toId()) - mm1Bal0Before;
        uint256 hookLoss1 = mm1Bal1Before - pm.balanceOf(address(quoter), usdc.toId());

        assertEq(hookGain0, amountIn - protocolCut, "hook gets exact input minus protocol cut");

        uint256 afterFee = amountIn * (FEE_DENOM - fee) / FEE_DENOM;
        uint256 roundUpOutput = FullMath.mulDivRoundingUp(afterFee, uint256(bid), Q96);
        assertLe(hookLoss1, roundUpOutput, "hook pays <= roundUp output");

        assertEq(pm.balanceOf(address(hook), native.toId()) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(pm.balanceOf(address(hook), usdc.toId()), 0, "no protocol fees on output side");
        assertEq(trader0Before - native.balanceOfSelf(), amountIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, hookLoss1, "trader token1 received equals hook payout");
    }

    function test_beforeSwap_roundingFavoursHook_exactOut() public {
        uint112 bid = uint112(Q96 * 3 / 7e13);
        setPricesSingle(hook, poolId, bid, uint112(Q96 / 1e16), uint32(block.timestamp));

        uint256 amountOut = 100_001;
        uint256 fee = expectedFee(0);

        uint256 protocolFees0Before = pm.balanceOf(address(hook), native.toId());
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = pm.balanceOf(address(quoter), native.toId());
        uint256 mm1Bal1Before = pm.balanceOf(address(quoter), usdc.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, int256(amountOut));

        uint256 traderPaid = trader0Before - native.balanceOfSelf();
        uint256 protocolCut = traderPaid * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;
        uint256 hookGain0 = pm.balanceOf(address(quoter), native.toId()) - mm1Bal0Before;
        uint256 hookLoss1 = mm1Bal1Before - pm.balanceOf(address(quoter), usdc.toId());

        uint256 inputBeforeFee = FullMath.mulDiv(amountOut, Q96, uint256(bid));
        uint256 inputMin = inputBeforeFee * FEE_DENOM / (FEE_DENOM - fee);
        assertGe(traderPaid, inputMin, "trader pays >= roundDown input");
        assertEq(hookGain0, traderPaid - protocolCut, "hook gets trader input minus protocol cut");
        assertEq(hookLoss1, amountOut, "hook pays exact output");

        assertEq(pm.balanceOf(address(hook), native.toId()) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(pm.balanceOf(address(hook), usdc.toId()), 0, "no protocol fees on output side");
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

            uint256 protocolFees0Before = pm.balanceOf(address(hook), native.toId());
            uint256 trader0Before = native.balanceOfSelf();
            uint256 trader1Before = usdc.balanceOfSelf();
            uint256 mm1Bal0Before = pm.balanceOf(address(quoter), native.toId());
            uint256 mm1Bal1Before = pm.balanceOf(address(quoter), usdc.toId());

            swap(UNIVERSAL_ROUTER, poolKey, true, int256(amountOut));

            assertEq(pm.balanceOf(address(hook), native.toId()) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
            assertEq(pm.balanceOf(address(hook), usdc.toId()), 0, "no protocol fees on output side");
            assertEq(trader0Before - native.balanceOfSelf(), expectedIn, "trader token0 paid");
            assertEq(usdc.balanceOfSelf() - trader1Before, amountOut, "trader token1 received");
            assertEq(pm.balanceOf(address(quoter), native.toId()) - mm1Bal0Before, expectedIn - protocolCut, "mm1 native balance increase minus protocol cut");
            assertEq(mm1Bal1Before - pm.balanceOf(address(quoter), usdc.toId()), amountOut, "mm1 usdc balance decrease");
        }
    }

    // =====================================================================
    //  Revert paths
    // =====================================================================

    function test_beforeSwap_RevertWhen_pairNotRegistered() public {
        // An unregistered pool has no default quoter; with empty hookData the hook reverts.
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
        vm.expectRevert(HyFiHook.NoDefaultQuoter.selector);
        hook.beforeSwap(address(this), unregisteredKey, params, "");
    }

    function test_beforeSwap_RevertWhen_noDefaultQuoter() public {
        // Clear the default quoter for the pool; with empty hookData this reverts.
        setDefaultQuoterSingle(hook, poolId, ILPQuoter(address(0)));

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1e18),
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.NoDefaultQuoter.selector);
        hook.beforeSwap(address(this), poolKey, params, "");
    }

    function test_beforeSwap_RevertWhen_invalidHookData() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1e18),
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        // hookData length != 32 → InvalidHookData
        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.InvalidHookData.selector);
        hook.beforeSwap(address(this), poolKey, params, hex"deadbeef");
    }

    function test_beforeSwap_RevertWhen_invalidHookData_zeroAddress() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1e18),
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        // 32-byte encoding of address(0) → InvalidHookData
        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.InvalidHookData.selector);
        hook.beforeSwap(address(this), poolKey, params, abi.encode(address(0)));
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
        setPricesSingle(hook, poolId, 1, 0, uint32(block.timestamp));

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(pm));
        vm.expectRevert(SimpleQuoter.ZeroOutput.selector);
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
        vm.expectRevert(SimpleQuoter.ZeroOutput.selector);
        hook.beforeSwap(address(this), poolKey, params, "");
    }

    // =====================================================================
    //  hookData override — exact-in / exact-out / oneForZero
    // =====================================================================

    function test_beforeSwap_hookDataOverride_exactIn_zeroForOne() public {
        // Override quoter has zero fee; default quoter (mm1) has BASE_FEE.
        address mm2 = makeAddr("mm2");
        SimpleQuoter q2 = deployQuoterProxy(pm, address(hook), mm2, 0, 0);
        fundQuoter(mm2, q2, USDC_ADDR, 1_000 * 10 ** POL_DECIMALS, 1_000 * 10 ** USDC_DECIMALS);

        uint256 amountIn = 1e18;
        uint256 protocolCut = amountIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;
        uint256 expectedOut = FullMath.mulDiv(amountIn, uint256(BID_PRICE_X96), Q96);

        uint256 protocolFees0Before = pm.balanceOf(address(hook), native.toId());
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = pm.balanceOf(address(quoter), native.toId());
        uint256 mm1Bal1Before = pm.balanceOf(address(quoter), usdc.toId());
        uint256 mm2Bal0Before = pm.balanceOf(address(q2), native.toId());
        uint256 mm2Bal1Before = pm.balanceOf(address(q2), usdc.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn), abi.encode(address(q2)));

        // Trader
        assertEq(trader0Before - native.balanceOfSelf(), amountIn, "trader token0 spent");
        assertEq(usdc.balanceOfSelf() - trader1Before, expectedOut, "trader gets override quoter output");
        // Override quoter debited / credited
        assertEq(pm.balanceOf(address(q2), native.toId()) - mm2Bal0Before, amountIn - protocolCut, "override q2 native credited");
        assertEq(mm2Bal1Before - pm.balanceOf(address(q2), usdc.toId()), expectedOut, "override q2 usdc debited");
        // Default quoter untouched
        assertEq(pm.balanceOf(address(quoter), native.toId()), mm1Bal0Before, "default quoter native untouched");
        assertEq(pm.balanceOf(address(quoter), usdc.toId()), mm1Bal1Before, "default quoter usdc untouched");
        // Protocol fees
        assertEq(pm.balanceOf(address(hook), native.toId()) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(pm.balanceOf(address(hook), usdc.toId()), 0, "no protocol fees on output side");
    }

    function test_beforeSwap_hookDataOverride_exactOut_zeroForOne() public {
        address mm2 = makeAddr("mm2");
        SimpleQuoter q2 = deployQuoterProxy(pm, address(hook), mm2, 0, 0);
        fundQuoter(mm2, q2, USDC_ADDR, 1_000 * 10 ** POL_DECIMALS, 1_000 * 10 ** USDC_DECIMALS);

        uint256 amountOut = 500_000;
        uint256 expectedIn = FullMath.mulDivRoundingUp(amountOut, Q96, uint256(BID_PRICE_X96));
        uint256 protocolCut = expectedIn * DEFAULT_PROTOCOL_FEE_PIPS / FEE_DENOM;

        uint256 protocolFees0Before = pm.balanceOf(address(hook), native.toId());
        uint256 trader0Before = native.balanceOfSelf();
        uint256 trader1Before = usdc.balanceOfSelf();
        uint256 mm1Bal0Before = pm.balanceOf(address(quoter), native.toId());
        uint256 mm1Bal1Before = pm.balanceOf(address(quoter), usdc.toId());
        uint256 mm2Bal0Before = pm.balanceOf(address(q2), native.toId());
        uint256 mm2Bal1Before = pm.balanceOf(address(q2), usdc.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, int256(amountOut), abi.encode(address(q2)));

        // Trader
        assertEq(trader0Before - native.balanceOfSelf(), expectedIn, "trader pays zero-fee input");
        assertEq(usdc.balanceOfSelf() - trader1Before, amountOut, "trader receives exact output");
        // Override quoter debited / credited
        assertEq(pm.balanceOf(address(q2), native.toId()) - mm2Bal0Before, expectedIn - protocolCut, "override q2 native credited");
        assertEq(mm2Bal1Before - pm.balanceOf(address(q2), usdc.toId()), amountOut, "override q2 usdc debited exact output");
        // Default quoter untouched
        assertEq(pm.balanceOf(address(quoter), native.toId()), mm1Bal0Before, "default quoter native untouched");
        assertEq(pm.balanceOf(address(quoter), usdc.toId()), mm1Bal1Before, "default quoter usdc untouched");
        // Protocol fees
        assertEq(pm.balanceOf(address(hook), native.toId()) - protocolFees0Before, protocolCut, "protocol fee accrues on input side");
        assertEq(pm.balanceOf(address(hook), usdc.toId()), 0, "no protocol fees on output side");
    }

    // =====================================================================
    //  Default quoter reverts → swap reverts (no fallback)
    // =====================================================================

    function test_beforeSwap_RevertWhen_defaultQuoterReverts() public {
        RevertingQuoter qRevert = new RevertingQuoter();
        setDefaultQuoterSingle(hook, poolId, ILPQuoter(address(qRevert)));

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1e18),
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(pm));
        vm.expectRevert();
        hook.beforeSwap(address(this), poolKey, params, "");
    }

    // =====================================================================
    //  Override quoter with insufficient inventory → swap reverts at settle
    // =====================================================================

    function test_beforeSwap_RevertWhen_overrideQuoterUnderfunded() public {
        // Override quoter has no inventory, so the output-side settle will fail.
        address mm2 = makeAddr("mm2");
        SimpleQuoter q2 = deployQuoterProxy(pm, address(hook), mm2, 0, 0);
        // intentionally: no fundQuoter call

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1e18),
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(pm));
        vm.expectRevert();
        hook.beforeSwap(address(this), poolKey, params, abi.encode(address(q2)));
    }
}
