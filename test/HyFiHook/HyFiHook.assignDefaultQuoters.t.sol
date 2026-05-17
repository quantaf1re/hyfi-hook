pragma solidity ^0.8.30;

import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {ILPQuoter} from "../../src/interfaces/ILPQuoter.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract HyFiHookAssignDefaultQuotersTest is HyFiHookSharedSetup {
    function setUp() public {
        sharedSetup();
    }

    function test_assignDefaultQuoters_setsQuoter() public {
        address q2 = makeAddr("q2");
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        ILPQuoter[] memory quoters = new ILPQuoter[](1);
        quoters[0] = ILPQuoter(q2);

        vm.expectEmit(true, true, false, false, address(hook));
        emit HyFiHook.DefaultQuoterSet(poolId, q2);
        hook.assignDefaultQuoters(pids, quoters);
        assertEq(address(hook.getDefaultQuoter(poolId)), q2, "default quoter set");
    }

    function test_assignDefaultQuoters_overwritesExisting() public {
        // sharedSetup already set `quoter` as default; overwrite with a new address.
        address q2 = makeAddr("q2");
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        ILPQuoter[] memory quoters = new ILPQuoter[](1);
        quoters[0] = ILPQuoter(q2);

        vm.expectEmit(true, true, false, false, address(hook));
        emit HyFiHook.DefaultQuoterSet(poolId, q2);
        hook.assignDefaultQuoters(pids, quoters);
        assertEq(address(hook.getDefaultQuoter(poolId)), q2, "default quoter overwritten");
    }

    function test_assignDefaultQuoters_multiplePools() public {
        PoolId pidA = PoolId.wrap(bytes32(uint256(1)));
        PoolId pidB = PoolId.wrap(bytes32(uint256(2)));
        address qA = makeAddr("qA");
        address qB = makeAddr("qB");

        PoolId[] memory pids = new PoolId[](2);
        pids[0] = pidA;
        pids[1] = pidB;
        ILPQuoter[] memory quoters = new ILPQuoter[](2);
        quoters[0] = ILPQuoter(qA);
        quoters[1] = ILPQuoter(qB);

        vm.expectEmit(true, true, false, false, address(hook));
        emit HyFiHook.DefaultQuoterSet(pidA, qA);
        vm.expectEmit(true, true, false, false, address(hook));
        emit HyFiHook.DefaultQuoterSet(pidB, qB);
        hook.assignDefaultQuoters(pids, quoters);
        assertEq(address(hook.getDefaultQuoter(pidA)), qA);
        assertEq(address(hook.getDefaultQuoter(pidB)), qB);
    }

    function test_assignDefaultQuoters_RevertWhen_lengthMismatch() public {
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        ILPQuoter[] memory quoters = new ILPQuoter[](2);

        vm.expectRevert(HyFiHook.LengthMismatch.selector);
        hook.assignDefaultQuoters(pids, quoters);
    }

    function test_assignDefaultQuoters_RevertWhen_notOwner() public {
        address attacker = makeAddr("attacker");
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        ILPQuoter[] memory quoters = new ILPQuoter[](1);
        quoters[0] = ILPQuoter(address(quoter));

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        hook.assignDefaultQuoters(pids, quoters);
    }
}
