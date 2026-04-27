pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {ILPQuoter} from "../../src/interfaces/ILPQuoter.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract HyFiHookGetMMTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    function test_getMM_returnsCorrectData() public view {
        (address mm, address q) = hook.getMM(poolId, 0);
        assertEq(mm, mm1);
        assertEq(q, address(quoter));
    }

    function test_getMM_RevertWhen_outOfBounds() public {
        vm.expectRevert(); // array out of bounds
        hook.getMM(poolId, 1);
    }

    function test_getMM_afterDeregisterAndSwap() public {
        // Add mm2 and mm3
        address mm2 = makeAddr("mm2");
        address mm3 = makeAddr("mm3");
        hook.addToWhitelist(mm2);
        hook.addToWhitelist(mm3);
        SimpleQuoter q2 = deployQuoterProxy(pm, address(hook), mm2, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);
        SimpleQuoter q3 = deployQuoterProxy(pm, address(hook), mm3, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);
        registerMM(hook, mm2, poolId, ILPQuoter(address(q2)));
        registerMM(hook, mm3, poolId, ILPQuoter(address(q3)));

        // Deregister mm2 (index 1) — mm3 (last) should move to index 1
        deregisterMM(hook, mm2, poolId);

        assertEq(hook.getMMCount(poolId), 2);
        (address first,) = hook.getMM(poolId, 0);
        (address second, address secondQ) = hook.getMM(poolId, 1);
        assertEq(first, mm1);
        assertEq(second, mm3);
        assertEq(secondQ, address(q3));
    }
}
