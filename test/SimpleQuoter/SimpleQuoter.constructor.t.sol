// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";

contract SimpleQuoterConstructorTest is HyFiHookSharedSetup {
    function setUp() public {
        sharedSetup();
    }

    function test_constructor_setsOwner() public view {
        // Shared setup deploys `quoter` with mm1 as owner
        assertEq(quoter.owner(), mm1);
    }

    function test_constructor_setsFees() public view {
        assertEq(quoter.baseFee(), DEFAULT_BASE_FEE, "base fee from constructor");
        assertEq(quoter.feePerSecond(), DEFAULT_FEE_PER_SECOND, "fee per second from constructor");
    }

    function test_constructor_RevertWhen_baseFeeAboveMax() public {
        vm.expectRevert(SimpleQuoter.FeeTooHigh.selector);
        new SimpleQuoter(address(this), MAX_FEE + 1, DEFAULT_FEE_PER_SECOND);
    }
}
