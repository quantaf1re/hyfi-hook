pragma solidity ^0.8.30;

import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

contract SimpleQuoterUpdateFeeParamsTest is HyFiHookSharedSetup {
    function setUp() public {
        sharedSetup();
    }

    function test_updateFeeParams_zero() public {
        vm.expectEmit(false, false, false, true, address(quoter));
        emit SimpleQuoter.FeeUpdated(0, 0);
        vm.prank(mm1);
        quoter.updateFeeParams(0, 0);
        assertEq(quoter.getBaseFee(), 0);
        assertEq(quoter.getFeePerSecond(), 0);

        uint256 amountIn = 1e18;
        uint32 now0 = uint32(block.timestamp);
        (, uint256 amOut) = quoter.getQuote(
            poolKey, true, -int256(amountIn), uint256(BID_PRICE_X96), uint256(SPREAD_X96), now0
        );
        // With zero base fee and zero elapsed, no fee is applied
        assertEq(amOut, FullMath.mulDiv(amountIn, uint256(BID_PRICE_X96), Q96));
    }

    function test_updateFeeParams_updatesFeeCurve() public {
        vm.expectEmit(false, false, false, true, address(quoter));
        emit SimpleQuoter.FeeUpdated(1000, 50);
        vm.prank(mm1);
        quoter.updateFeeParams(1000, 50); // 0.1% base, 0.005%/s staleness
        assertEq(quoter.getBaseFee(), 1000);
        assertEq(quoter.getFeePerSecond(), 50);

        uint256 amountIn = 1e18;
        uint32 now0 = uint32(block.timestamp);
        (, uint256 amOut) = quoter.getQuote(
            poolKey, true, -int256(amountIn), uint256(BID_PRICE_X96), uint256(SPREAD_X96), now0
        );
        uint256 afterFee = amountIn * (FEE_DENOM - 1000) / FEE_DENOM;
        assertEq(amOut, FullMath.mulDiv(afterFee, uint256(BID_PRICE_X96), Q96));
    }

    function test_updateFeeParams_RevertWhen_aboveMaxFee() public {
        vm.prank(mm1);
        vm.expectRevert(SimpleQuoter.FeeTooHigh.selector);
        quoter.updateFeeParams(MAX_FEE + 1, 0);
    }

    function test_updateFeeParams_RevertWhen_notOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert();
        quoter.updateFeeParams(0, 0);
    }
}
