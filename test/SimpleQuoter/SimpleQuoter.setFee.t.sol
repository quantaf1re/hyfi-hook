// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

contract SimpleQuoterSetFeeTest is HyFiHookSharedSetup {
    function setUp() public {
        sharedSetup();
    }

    function test_setFee_zero() public {
        vm.prank(mm1);
        quoter.setFee(0, 0);
        assertEq(quoter.baseFee(), 0);
        assertEq(quoter.feePerSecond(), 0);

        uint256 amountIn = 1e18;
        uint32 now0 = uint32(block.timestamp);
        (, uint256 amOut) = quoter.quoteTrade(
            poolKey, true, -int256(amountIn), uint256(BID_PRICE_X96), uint256(SPREAD_X96), now0
        );
        // With zero base fee and zero elapsed, no fee is applied
        assertEq(amOut, FullMath.mulDiv(amountIn, uint256(BID_PRICE_X96), Q96));
    }

    function test_setFee_updatesFeeCurve() public {
        vm.prank(mm1);
        quoter.setFee(1000, 50); // 0.1% base, 0.005%/s staleness
        assertEq(quoter.baseFee(), 1000);
        assertEq(quoter.feePerSecond(), 50);

        uint256 amountIn = 1e18;
        uint32 now0 = uint32(block.timestamp);
        (, uint256 amOut) = quoter.quoteTrade(
            poolKey, true, -int256(amountIn), uint256(BID_PRICE_X96), uint256(SPREAD_X96), now0
        );
        uint256 afterFee = amountIn * (FEE_DENOM - 1000) / FEE_DENOM;
        assertEq(amOut, FullMath.mulDiv(afterFee, uint256(BID_PRICE_X96), Q96));
    }

    function test_setFee_RevertWhen_aboveMaxFee() public {
        vm.prank(mm1);
        vm.expectRevert(SimpleQuoter.FeeTooHigh.selector);
        quoter.setFee(MAX_FEE + 1, 0);
    }

    function test_setFee_RevertWhen_notOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert();
        quoter.setFee(0, 0);
    }
}
