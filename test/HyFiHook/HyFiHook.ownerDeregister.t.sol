pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {ILPQuoter} from "../../src/interfaces/ILPQuoter.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract HyFiHookOwnerDeregisterTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    // ─── Happy path ──────────────────────────────────────────────────────

    function test_ownerDeregister_removesMMFromPool() public {
        assertEq(hook.getMMCount(poolId), 1);

        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        hook.ownerDeregister(pids, mm1);

        assertEq(hook.getMMCount(poolId), 0);
    }

    // ─── Owner can deregister even non-whitelisted MM ────────────────────

    function test_ownerDeregister_worksAfterWhitelistRemoval() public {
        hook.removeFromWhitelist(mm1);
        assertFalse(hook.whitelisted(mm1));

        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        hook.ownerDeregister(pids, mm1);

        assertEq(hook.getMMCount(poolId), 0);
    }

    // ─── Multiple pools ──────────────────────────────────────────────────

    function test_ownerDeregister_multiplePools() public {
        PoolId otherId = PoolId.wrap(keccak256("other"));
        registerMM(hook, mm1, otherId, ILPQuoter(address(quoter)));

        PoolId[] memory pids = new PoolId[](2);
        pids[0] = poolId;
        pids[1] = otherId;
        hook.ownerDeregister(pids, mm1);

        assertEq(hook.getMMCount(poolId), 0);
        assertEq(hook.getMMCount(otherId), 0);
    }

    // ─── Revert: not registered ──────────────────────────────────────────

    function test_ownerDeregister_RevertWhen_notRegistered() public {
        address notReg = makeAddr("notReg");
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;

        vm.expectRevert(HyFiHook.NotRegistered.selector);
        hook.ownerDeregister(pids, notReg);
    }

    // ─── Access control ──────────────────────────────────────────────────

    function test_ownerDeregister_RevertWhen_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        hook.ownerDeregister(pids, mm1);
    }
}
