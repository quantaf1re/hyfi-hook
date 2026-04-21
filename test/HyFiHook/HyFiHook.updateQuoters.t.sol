pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {ILPQuoter} from "../../src/interfaces/ILPQuoter.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {RevertingQuoter} from "./mocks/MockQuoters.sol";

contract HyFiHookUpdateQuotersTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    // ─── Happy path ──────────────────────────────────────────────────────

    function test_updateQuoters_changesQuoter() public {
        SimpleQuoter newQ = new SimpleQuoter(mm1, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);

        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        ILPQuoter[] memory quoters = new ILPQuoter[](1);
        quoters[0] = ILPQuoter(address(newQ));

        vm.prank(mm1);
        hook.updateQuoters(pids, quoters);

        (, address storedQuoter) = hook.getMM(poolId, 0);
        assertEq(storedQuoter, address(newQ));
    }

    // ─── Multiple pools ──────────────────────────────────────────────────

    function test_updateQuoters_multiplePools() public {
        PoolId otherId = PoolId.wrap(keccak256("other"));
        registerMM(hook, mm1, otherId, ILPQuoter(address(quoter)));

        SimpleQuoter newQ = new SimpleQuoter(mm1, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);

        PoolId[] memory pids = new PoolId[](2);
        pids[0] = poolId;
        pids[1] = otherId;
        ILPQuoter[] memory quoters = new ILPQuoter[](2);
        quoters[0] = ILPQuoter(address(newQ));
        quoters[1] = ILPQuoter(address(newQ));

        vm.prank(mm1);
        hook.updateQuoters(pids, quoters);

        (, address q1) = hook.getMM(poolId, 0);
        (, address q2) = hook.getMM(otherId, 0);
        assertEq(q1, address(newQ));
        assertEq(q2, address(newQ));
    }

    // ─── Revert: not registered ──────────────────────────────────────────

    function test_updateQuoters_RevertWhen_notRegistered() public {
        address notReg = makeAddr("notReg");
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        ILPQuoter[] memory quoters = new ILPQuoter[](1);
        quoters[0] = ILPQuoter(address(quoter));

        vm.prank(notReg);
        vm.expectRevert(HyFiHook.NotRegistered.selector);
        hook.updateQuoters(pids, quoters);
    }

    // ─── Revert: length mismatch ─────────────────────────────────────────

    function test_updateQuoters_RevertWhen_lengthMismatch() public {
        PoolId[] memory pids = new PoolId[](2);
        ILPQuoter[] memory quoters = new ILPQuoter[](1);

        vm.prank(mm1);
        vm.expectRevert(HyFiHook.LengthMismatch.selector);
        hook.updateQuoters(pids, quoters);
    }

    // ─── Integration: updated quoter is consulted on next swap ───────────

    function test_updateQuoters_newQuoterConsultedOnSwap() public {
        // Replace mm1's quoter with a reverting one.
        RevertingQuoter qRevert = new RevertingQuoter();
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        ILPQuoter[] memory quoters = new ILPQuoter[](1);
        quoters[0] = ILPQuoter(address(qRevert));

        vm.prank(mm1);
        hook.updateQuoters(pids, quoters);

        // Swapping through the Universal Router should now revert because
        // the new quoter reverts in beforeSwap → NoQuoteAvailable bubbles up
        // (wrapped by Uniswap V4's hook-call failure mechanism).
        vm.expectRevert();
        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(1e18));
    }

    // ─── Updating one MM's quoter does not affect another MM ─────────────

    function test_updateQuoters_doesNotAffectOtherMMQuoter() public {
        // Register mm2 with its own quoter.
        address mm2 = makeAddr("mm2");
        hook.addToWhitelist(mm2);
        SimpleQuoter q2 = new SimpleQuoter(mm2, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);
        registerMM(hook, mm2, poolId, ILPQuoter(address(q2)));

        // mm1 updates its quoter.
        SimpleQuoter newQ1 = new SimpleQuoter(mm1, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        ILPQuoter[] memory qs = new ILPQuoter[](1);
        qs[0] = ILPQuoter(address(newQ1));
        vm.prank(mm1);
        hook.updateQuoters(pids, qs);

        (, address mm1Q) = hook.getMM(poolId, 0);
        (, address mm2Q) = hook.getMM(poolId, 1);
        assertEq(mm1Q, address(newQ1), "mm1 quoter updated");
        assertEq(mm2Q, address(q2), "mm2 quoter unchanged");
    }
}
