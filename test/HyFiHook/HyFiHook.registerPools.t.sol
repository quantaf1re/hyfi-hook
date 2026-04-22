pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {ILPQuoter} from "../../src/interfaces/ILPQuoter.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract HyFiHookRegisterPoolsTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    // ─── Happy path ──────────────────────────────────────────────────────

    function test_registerPools_addsMMToPool() public {
        address mm2 = makeAddr("mm2");
        hook.addToWhitelist(mm2);
        SimpleQuoter q2 = new SimpleQuoter(pm, address(hook), mm2, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);

        registerMM(hook, mm2, poolId, ILPQuoter(address(q2)));

        assertEq(hook.getMMCount(poolId), 2, "should have 2 MMs");
        (address storedMM, address storedQuoter) = hook.getMM(poolId, 1);
        assertEq(storedMM, mm2);
        assertEq(storedQuoter, address(q2));
    }

    // ─── Register for multiple pools in one call ─────────────────────────

    function test_registerPools_multiplePools() public {
        address mm2 = makeAddr("mm2");
        hook.addToWhitelist(mm2);
        SimpleQuoter q2 = new SimpleQuoter(pm, address(hook), mm2, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);

        PoolId otherId = PoolId.wrap(keccak256("other"));

        PoolId[] memory pids = new PoolId[](2);
        pids[0] = poolId;
        pids[1] = otherId;
        ILPQuoter[] memory quoters = new ILPQuoter[](2);
        quoters[0] = ILPQuoter(address(q2));
        quoters[1] = ILPQuoter(address(q2));

        vm.prank(mm2);
        hook.registerPools(pids, quoters);

        assertEq(hook.getMMCount(poolId), 2, "poolId should have 2 MMs");
        assertEq(hook.getMMCount(otherId), 1, "otherId should have 1 MM");
        (address storedMM1, address storedQ1) = hook.getMM(poolId, 1);
        assertEq(storedMM1, mm2, "poolId MM should be mm2");
        assertEq(storedQ1, address(q2), "poolId quoter should be q2");
        (address storedMM2, address storedQ2) = hook.getMM(otherId, 0);
        assertEq(storedMM2, mm2, "otherId MM should be mm2");
        assertEq(storedQ2, address(q2), "otherId quoter should be q2");
    }

    // ─── Revert: not whitelisted ─────────────────────────────────────────

    function test_registerPools_RevertWhen_notWhitelisted() public {
        address notWL = makeAddr("notWL");
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        ILPQuoter[] memory quoters = new ILPQuoter[](1);
        quoters[0] = ILPQuoter(address(quoter));

        vm.prank(notWL);
        vm.expectRevert(HyFiHook.NotWhitelisted.selector);
        hook.registerPools(pids, quoters);
    }

    // ─── Revert: already registered ──────────────────────────────────────

    function test_registerPools_RevertWhen_alreadyRegistered() public {
        // mm1 is already registered from sharedSetup
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        ILPQuoter[] memory quoters = new ILPQuoter[](1);
        quoters[0] = ILPQuoter(address(quoter));

        vm.prank(mm1);
        vm.expectRevert(HyFiHook.AlreadyRegistered.selector);
        hook.registerPools(pids, quoters);
    }

    // ─── Revert: max LPs reached ────────────────────────────────────────

    function test_registerPools_RevertWhen_maxLPsReached() public {
        // mm1 already registered = 1. Add 9 more to hit MAX_LPS=10
        for (uint i = 0; i < 9; i++) {
            address mm = makeAddr(string(abi.encodePacked("mmExtra", i)));
            hook.addToWhitelist(mm);
            SimpleQuoter q = new SimpleQuoter(pm, address(hook), mm, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);
            registerMM(hook, mm, poolId, ILPQuoter(address(q)));
        }
        assertEq(hook.getMMCount(poolId), 10);

        // 11th should revert
        address mm11 = makeAddr("mm11");
        hook.addToWhitelist(mm11);
        SimpleQuoter q11 = new SimpleQuoter(pm, address(hook), mm11, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);

        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        ILPQuoter[] memory quoters = new ILPQuoter[](1);
        quoters[0] = ILPQuoter(address(q11));

        vm.prank(mm11);
        vm.expectRevert(HyFiHook.MaxLPsReached.selector);
        hook.registerPools(pids, quoters);
    }

    // ─── Revert: length mismatch ─────────────────────────────────────────

    function test_registerPools_RevertWhen_lengthMismatch() public {
        address mm2 = makeAddr("mm2");
        hook.addToWhitelist(mm2);

        PoolId[] memory pids = new PoolId[](2);
        ILPQuoter[] memory quoters = new ILPQuoter[](1);

        vm.prank(mm2);
        vm.expectRevert(HyFiHook.LengthMismatch.selector);
        hook.registerPools(pids, quoters);
    }
}
