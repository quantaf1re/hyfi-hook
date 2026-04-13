pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "./HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract HyFiHookGetFeeTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    // ─── Base fee at zero elapsed ────────────────────────────────────────

    function test_getFee_baseFeeAtZeroElapsed() public view {
        uint256 fee = hook.getFee(poolId);
        assertEq(fee, BASE_FEE, "fee at 0 elapsed = BASE_FEE");
    }

    // ─── Linear increase ─────────────────────────────────────────────────

    function test_getFee_linearIncrease() public {
        vm.warp(block.timestamp + 10);
        uint256 fee = hook.getFee(poolId);
        assertEq(fee, BASE_FEE + 10 * FEE_PER_SECOND, "fee at 10s");
    }

    function test_getFee_linearAt1Second() public {
        vm.warp(block.timestamp + 1);
        uint256 fee = hook.getFee(poolId);
        assertEq(fee, BASE_FEE + FEE_PER_SECOND, "fee at 1s");
    }

    // ─── Cap at MAX_FEE ──────────────────────────────────────────────────

    function test_getFee_capsAtMaxFee() public {
        // (MAX_FEE - BASE_FEE) / FEE_PER_SECOND = 9995 seconds to reach cap
        uint256 exactCapSeconds = (MAX_FEE - BASE_FEE) / FEE_PER_SECOND;
        vm.warp(block.timestamp + exactCapSeconds);
        assertEq(hook.getFee(poolId), MAX_FEE, "fee at exact cap");
    }

    function test_getFee_beyondCapStillMaxFee() public {
        vm.warp(block.timestamp + 100_000); // way past cap
        assertEq(hook.getFee(poolId), MAX_FEE, "fee beyond cap");
    }

    // ─── Resets after setPrice ───────────────────────────────────────────

    function test_getFee_resetsAfterSetPrice() public {
        vm.warp(block.timestamp + 50);
        assertEq(hook.getFee(poolId), BASE_FEE + 50 * FEE_PER_SECOND, "stale fee");

        hook.setPrice(poolId, BID_PRICE_X96, SPREAD_X96);
        assertEq(hook.getFee(poolId), BASE_FEE, "fee reset to base");
    }

    // ─── Unregistered pool (lastUpdate = 0) ──────────────────────────────

    function test_getFee_unregisteredPool_highFee() public {
        // lastUpdate = 0, elapsed = block.timestamp.
        // On a fork the timestamp is large so the fee caps at MAX_FEE.
        // Warp to a known small timestamp to test the linear region.
        vm.warp(1);
        PoolId unknownId = PoolId.wrap(keccak256("unknown"));
        assertEq(hook.getFee(unknownId), BASE_FEE + FEE_PER_SECOND, "unregistered pool fee at ts=1");
    }

    function test_getFee_unregisteredPool_atLargeTimestamp_capsAtMax() public {
        vm.warp(100_000);
        PoolId unknownId = PoolId.wrap(keccak256("unknown"));
        assertEq(hook.getFee(unknownId), MAX_FEE, "unregistered pool at large ts -> max fee");
    }
}
