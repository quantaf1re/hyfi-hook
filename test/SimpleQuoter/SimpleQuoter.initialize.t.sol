pragma solidity ^0.8.30;

import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract SimpleQuoterInitializeTest is HyFiHookSharedSetup {
    function setUp() public {
        sharedSetup();
    }

    function test_initialize_setsState() public view {
        // Shared setup deploys `quoter` proxy with mm1 as owner
        assertEq(quoter.owner(), mm1, "owner from initialize");
        assertEq(quoter.baseFee(), DEFAULT_BASE_FEE, "base fee from initialize");
        assertEq(quoter.feePerSecond(), DEFAULT_FEE_PER_SECOND, "fee per second from initialize");
        assertEq(address(quoter.pm()), address(pm), "pm from initialize");
        assertEq(quoter.hook(), address(hook), "hook from initialize");
    }

    function test_initialize_RevertWhen_baseFeeAboveMax() public {
        SimpleQuoter impl = new SimpleQuoter();
        bytes memory initData = abi.encodeCall(
            SimpleQuoter.initialize, (pm, address(hook), address(this), MAX_FEE + 1, DEFAULT_FEE_PER_SECOND)
        );
        // Initializer revert is wrapped by the proxy constructor; expect a generic revert
        vm.expectRevert();
        new TransparentUpgradeableProxy(address(impl), address(this), initData);
    }

    function test_initialize_RevertWhen_calledTwice() public {
        vm.expectRevert();
        quoter.initialize(pm, address(hook), address(this), DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);
    }
}
