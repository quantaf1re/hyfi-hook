pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "./HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract HyFiHookGetPriceTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    // ─── Returns values from setPrice ────────────────────────────────────

    function test_getPrice_returnsSetValues() public {
        uint112 bid = uint112(2 * Q96);
        uint112 spread = uint112(Q96 / 50);
        vm.warp(12345);
        hook.setPrice(poolId, bid, spread);

        (uint112 storedBid, uint112 storedSpread, uint32 lastUpdate) = hook.getPrice(poolId);

        assertEq(storedBid, bid, "bid");
        assertEq(storedSpread, spread, "spread");
        assertEq(lastUpdate, 12345, "lastUpdate");
    }

    // ─── Unregistered pool returns zeroes ─────────────────────────────────

    function test_getPrice_unregisteredPool_returnsZeroes() public view {
        PoolId unknownId = PoolId.wrap(keccak256("unknown"));

        (uint112 bid, uint112 spread, uint32 lastUpdate) = hook.getPrice(unknownId);

        assertEq(bid, 0, "bid zero");
        assertEq(spread, 0, "spread zero");
        assertEq(lastUpdate, 0, "lastUpdate zero");
    }
}
