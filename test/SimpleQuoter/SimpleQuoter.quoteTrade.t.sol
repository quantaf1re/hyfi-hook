pragma solidity ^0.8.30;

import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

contract SimpleQuoterQuoteTradeTest is HyFiHookSharedSetup {
    uint256 internal BID;
    uint256 internal SPREAD;

    function setUp() public {
        sharedSetup();
        BID = uint256(BID_PRICE_X96);
        SPREAD = uint256(SPREAD_X96);
    }

    // =====================================================================
    //  Exact input — zeroForOne (uses bid price)
    // =====================================================================

    function test_quoteTrade_exactIn_zeroForOne() public view {
        uint256 amountIn = 1e18;
        uint32 timestamp = uint32(block.timestamp);

        (uint256 amIn, uint256 amOut) = quoter.quoteTrade(
            poolKey, true, -int256(amountIn), BID, SPREAD, timestamp
        );

        assertEq(amIn, amountIn, "amIn should equal abs(amountSpecified)");

        uint256 fee = BASE_FEE;
        uint256 afterFee = amountIn * (FEE_DENOM - fee) / FEE_DENOM;
        uint256 expected = FullMath.mulDiv(afterFee, BID, Q96);
        assertEq(amOut, expected, "amOut should match expected");
    }

    // =====================================================================
    //  Exact input — oneForZero (uses ask = bid + spread)
    // =====================================================================

    function test_quoteTrade_exactIn_oneForZero() public view {
        uint256 amountIn = 1e6;
        uint32 timestamp = uint32(block.timestamp);
        uint256 askPrice = BID + SPREAD;

        (uint256 amIn, uint256 amOut) = quoter.quoteTrade(
            poolKey, false, -int256(amountIn), BID, SPREAD, timestamp
        );

        assertEq(amIn, amountIn);

        uint256 fee = BASE_FEE;
        uint256 afterFee = amountIn * (FEE_DENOM - fee) / FEE_DENOM;
        uint256 expected = FullMath.mulDiv(afterFee, Q96, askPrice);
        assertEq(amOut, expected);
    }

    // =====================================================================
    //  Exact output — zeroForOne (uses bid price)
    // =====================================================================

    function test_quoteTrade_exactOut_zeroForOne() public view {
        uint256 amountOut = 500_000;
        uint32 timestamp = uint32(block.timestamp);

        (uint256 amIn, uint256 amOut) = quoter.quoteTrade(
            poolKey, true, int256(amountOut), BID, SPREAD, timestamp
        );

        assertEq(amOut, amountOut, "amOut should equal amountSpecified");

        uint256 fee = BASE_FEE;
        uint256 beforeFee = FullMath.mulDivRoundingUp(amountOut, Q96, BID);
        uint256 expectedIn = FullMath.mulDivRoundingUp(beforeFee, FEE_DENOM, FEE_DENOM - fee);
        assertEq(amIn, expectedIn, "amIn should match expected");
    }

    // =====================================================================
    //  Exact output — oneForZero (uses ask price)
    // =====================================================================

    function test_quoteTrade_exactOut_oneForZero() public view {
        uint256 amountOut = 5e17;
        uint32 timestamp = uint32(block.timestamp);
        uint256 askPrice = BID + SPREAD;

        (uint256 amIn, uint256 amOut) = quoter.quoteTrade(
            poolKey, false, int256(amountOut), BID, SPREAD, timestamp
        );

        assertEq(amOut, amountOut);

        uint256 fee = BASE_FEE;
        uint256 beforeFee = FullMath.mulDivRoundingUp(amountOut, askPrice, Q96);
        uint256 expectedIn = FullMath.mulDivRoundingUp(beforeFee, FEE_DENOM, FEE_DENOM - fee);
        assertEq(amIn, expectedIn);
    }

    // =====================================================================
    //  Staleness fee increases over time
    // =====================================================================

    function test_quoteTrade_feeIncreasesWithStaleness() public {
        uint256 amountIn = 1e18;
        uint32 now0 = uint32(block.timestamp);

        (, uint256 outFresh) = quoter.quoteTrade(
            poolKey, true, -int256(amountIn), BID, SPREAD, now0
        );

        vm.warp(block.timestamp + 10);
        (, uint256 outStale) = quoter.quoteTrade(
            poolKey, true, -int256(amountIn), BID, SPREAD, now0
        );

        assertGt(outFresh, outStale, "stale should give less output");
    }

    function test_quoteTrade_feeIncreasesExactOut() public {
        uint256 amountOut = 500_000;
        uint32 now0 = uint32(block.timestamp);

        (uint256 inFresh,) = quoter.quoteTrade(
            poolKey, true, int256(amountOut), BID, SPREAD, now0
        );

        vm.warp(block.timestamp + 10);
        (uint256 inStale,) = quoter.quoteTrade(
            poolKey, true, int256(amountOut), BID, SPREAD, now0
        );

        assertGt(inStale, inFresh, "stale should require more input");
    }

    // =====================================================================
    //  Fee caps at 100%
    // =====================================================================

    function test_quoteTrade_feeCapsAt100Percent_exactIn() public {
        uint256 amountIn = 1e18;
        uint32 now0 = uint32(block.timestamp);

        uint256 elapsed = (MAX_FEE - BASE_FEE) / FEE_PER_SECOND;
        vm.warp(block.timestamp + elapsed);

        vm.expectRevert(SimpleQuoter.ZeroOutput.selector);
        quoter.quoteTrade(poolKey, true, -int256(amountIn), BID, SPREAD, now0);
    }

    function test_quoteTrade_feeCapsAt100Percent_exactOut() public {
        uint256 amountOut = 500_000;
        uint32 now0 = uint32(block.timestamp);

        uint256 elapsed = (MAX_FEE - BASE_FEE) / FEE_PER_SECOND;
        vm.warp(block.timestamp + elapsed);

        vm.expectRevert();
        quoter.quoteTrade(poolKey, true, int256(amountOut), BID, SPREAD, now0);
    }

    function test_quoteTrade_feeBeyond100Percent_staysAtMax() public {
        uint256 amountIn = 1e18;
        uint32 now0 = uint32(block.timestamp);

        vm.warp(block.timestamp + 100_000);

        vm.expectRevert(SimpleQuoter.ZeroOutput.selector);
        quoter.quoteTrade(poolKey, true, -int256(amountIn), BID, SPREAD, now0);
    }

    // =====================================================================
    //  Zero spread — bid equals ask
    // =====================================================================

    function test_quoteTrade_zeroSpread() public view {
        uint256 amountIn = 1e18;
        uint32 timestamp = uint32(block.timestamp);

        (uint256 amIn1, uint256 amOut1) = quoter.quoteTrade(
            poolKey, true, -int256(amountIn), BID, 0, timestamp
        );
        (uint256 amIn2, uint256 amOut2) = quoter.quoteTrade(
            poolKey, false, -int256(amountIn), BID, 0, timestamp
        );

        assertEq(amIn1, amountIn);
        assertEq(amIn2, amountIn);
        uint256 fee = BASE_FEE;
        uint256 afterFee = amountIn * (FEE_DENOM - fee) / FEE_DENOM;
        uint256 expectedOut1 = FullMath.mulDiv(afterFee, BID, Q96);
        uint256 expectedOut2 = FullMath.mulDiv(afterFee, Q96, BID);
        assertEq(amOut1, expectedOut1);
        assertEq(amOut2, expectedOut2);
    }

    // =====================================================================
    //  Revert: zero output from tiny input
    // =====================================================================

    function test_quoteTrade_RevertWhen_zeroOutput_tinyInput() public {
        uint32 timestamp = uint32(block.timestamp);

        vm.expectRevert(SimpleQuoter.ZeroOutput.selector);
        quoter.quoteTrade(poolKey, true, -1, BID, SPREAD, timestamp);
    }

    function test_quoteTrade_RevertWhen_zeroOutput_10wei() public {
        uint32 timestamp = uint32(block.timestamp);

        vm.expectRevert(SimpleQuoter.ZeroOutput.selector);
        quoter.quoteTrade(poolKey, true, -10, BID, SPREAD, timestamp);
    }

    // =====================================================================
    //  Rounding: exact-out rounds up input (favours MM)
    // =====================================================================

    function test_quoteTrade_exactOut_roundsUpInput() public view {
        uint256 oddBid = Q96 * 3 / 7e13;
        uint256 amountOut = 100_001;
        uint32 timestamp = uint32(block.timestamp);

        (uint256 amIn, uint256 amOut) = quoter.quoteTrade(
            poolKey, true, int256(amountOut), oddBid, 0, timestamp
        );

        assertEq(amOut, amountOut);

        uint256 fee = BASE_FEE;
        uint256 beforeFee = FullMath.mulDivRoundingUp(amountOut, Q96, oddBid);
        uint256 expectedIn = FullMath.mulDivRoundingUp(beforeFee, FEE_DENOM, FEE_DENOM - fee);
        assertEq(amIn, expectedIn);
    }

    // =====================================================================
    //  Large amounts
    // =====================================================================

    function test_quoteTrade_largeExactIn() public view {
        uint256 amountIn = 1_000_000e18;
        uint32 timestamp = uint32(block.timestamp);

        (uint256 amIn, uint256 amOut) = quoter.quoteTrade(
            poolKey, true, -int256(amountIn), BID, SPREAD, timestamp
        );

        assertEq(amIn, amountIn);
        uint256 fee = BASE_FEE;
        uint256 afterFee = amountIn * (FEE_DENOM - fee) / FEE_DENOM;
        uint256 expectedOut = FullMath.mulDiv(afterFee, BID, Q96);
        assertEq(amOut, expectedOut);
    }

    function test_quoteTrade_largeExactOut() public view {
        uint256 amountOut = 100_000e6;
        uint32 timestamp = uint32(block.timestamp);

        (uint256 amIn, uint256 amOut) = quoter.quoteTrade(
            poolKey, true, int256(amountOut), BID, SPREAD, timestamp
        );

        assertEq(amOut, amountOut);
        uint256 fee = BASE_FEE;
        uint256 beforeFee = FullMath.mulDivRoundingUp(amountOut, Q96, BID);
        uint256 expectedIn = FullMath.mulDivRoundingUp(beforeFee, FEE_DENOM, FEE_DENOM - fee);
        assertEq(amIn, expectedIn);
    }
}
