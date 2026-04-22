pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {ILPQuoter} from "../../src/interfaces/ILPQuoter.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract HyFiHookDeregisterPoolsTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    // ─── Happy path: deregister only MM ──────────────────────────────────

    function test_deregisterPools_removesMMFromPool() public {
        assertEq(hook.getMMCount(poolId), 1);

        deregisterMM(hook, mm1, poolId);

        assertEq(hook.getMMCount(poolId), 0, "should have 0 MMs");
    }

    // ─── Deregister with swap-and-pop (middle element) ───────────────────

    function test_deregisterPools_swapAndPop() public {
        // Add mm2 and mm3
        address mm2 = makeAddr("mm2");
        address mm3 = makeAddr("mm3");
        hook.addToWhitelist(mm2);
        hook.addToWhitelist(mm3);
        SimpleQuoter q2 = new SimpleQuoter(pm, address(hook), mm2, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);
        SimpleQuoter q3 = new SimpleQuoter(pm, address(hook), mm3, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);
        registerMM(hook, mm2, poolId, ILPQuoter(address(q2)));
        registerMM(hook, mm3, poolId, ILPQuoter(address(q3)));
        assertEq(hook.getMMCount(poolId), 3);

        // Deregister mm1 (index 0) — mm3 should take its place
        deregisterMM(hook, mm1, poolId);

        assertEq(hook.getMMCount(poolId), 2);
        (address first,) = hook.getMM(poolId, 0);
        assertEq(first, mm3, "last element should be swapped to index 0");
        (address second,) = hook.getMM(poolId, 1);
        assertEq(second, mm2);
    }

    // ─── Deregister last element (no swap needed) ────────────────────────

    function test_deregisterPools_lastElement_noSwap() public {
        address mm2 = makeAddr("mm2");
        hook.addToWhitelist(mm2);
        SimpleQuoter q2 = new SimpleQuoter(pm, address(hook), mm2, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);
        registerMM(hook, mm2, poolId, ILPQuoter(address(q2)));
        assertEq(hook.getMMCount(poolId), 2);

        // Deregister mm2 (last element)
        deregisterMM(hook, mm2, poolId);

        assertEq(hook.getMMCount(poolId), 1);
        (address first,) = hook.getMM(poolId, 0);
        assertEq(first, mm1);
    }

    // ─── Deregister from multiple pools in one call ──────────────────────

    function test_deregisterPools_multiplePools() public {
        PoolId otherId = PoolId.wrap(keccak256("other"));
        registerMM(hook, mm1, otherId, ILPQuoter(address(quoter)));

        assertEq(hook.getMMCount(poolId), 1);
        assertEq(hook.getMMCount(otherId), 1);

        PoolId[] memory pids = new PoolId[](2);
        pids[0] = poolId;
        pids[1] = otherId;
        vm.prank(mm1);
        hook.deregisterPools(pids);

        assertEq(hook.getMMCount(poolId), 0);
        assertEq(hook.getMMCount(otherId), 0);
    }

    // ─── Can re-register after deregister ────────────────────────────────

    function test_deregisterPools_thenReRegister() public {
        deregisterMM(hook, mm1, poolId);
        assertEq(hook.getMMCount(poolId), 0);

        registerMM(hook, mm1, poolId, ILPQuoter(address(quoter)));
        assertEq(hook.getMMCount(poolId), 1);
        (address stored,) = hook.getMM(poolId, 0);
        assertEq(stored, mm1);
    }

    // ─── Revert: not registered ──────────────────────────────────────────

    function test_deregisterPools_RevertWhen_notRegistered() public {
        address notReg = makeAddr("notReg");
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;

        vm.prank(notReg);
        vm.expectRevert(HyFiHook.NotRegistered.selector);
        hook.deregisterPools(pids);
    }
}
