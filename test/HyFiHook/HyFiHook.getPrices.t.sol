pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract HyFiHookGetPricesTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    function test_getPrices_returnsStoredValues() public view {
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        HyFiHook.PriceData[] memory out = hook.getPrices(pids);
        assertEq(out.length, 1);
        assertEq(out[0].bidPriceX96, BID_PRICE_X96);
        assertEq(out[0].spreadX96, SPREAD_X96);
        assertGt(out[0].lastUpdate, 0);
    }

    function test_getPrices_unsetPool_returnsZeros() public view {
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = PoolId.wrap(keccak256("unknown"));
        HyFiHook.PriceData[] memory out = hook.getPrices(pids);
        assertEq(out.length, 1);
        assertEq(out[0].bidPriceX96, 0);
        assertEq(out[0].spreadX96, 0);
        assertEq(out[0].lastUpdate, 0);
    }

    function test_getPrices_multiplePools() public {
        PoolId other = PoolId.wrap(keccak256("other"));
        PoolId unset = PoolId.wrap(keccak256("unset"));

        // Set prices on `other` too
        PoolId[] memory sp = new PoolId[](1);
        sp[0] = other;
        uint112[] memory bids = new uint112[](1);
        bids[0] = uint112(2 * Q96);
        uint112[] memory spreads = new uint112[](1);
        spreads[0] = uint112(Q96 / 50);
        vm.warp(9999);
        hook.setPrices(sp, bids, spreads);

        PoolId[] memory pids = new PoolId[](3);
        pids[0] = poolId;
        pids[1] = other;
        pids[2] = unset;
        HyFiHook.PriceData[] memory out = hook.getPrices(pids);

        assertEq(out.length, 3);
        assertEq(out[0].bidPriceX96, BID_PRICE_X96);
        assertEq(out[1].bidPriceX96, uint112(2 * Q96));
        assertEq(out[1].spreadX96, uint112(Q96 / 50));
        assertEq(out[1].lastUpdate, 9999);
        assertEq(out[2].bidPriceX96, 0);
        assertEq(out[2].lastUpdate, 0);
    }

    function test_getPrices_emptyArray() public view {
        PoolId[] memory pids = new PoolId[](0);
        HyFiHook.PriceData[] memory out = hook.getPrices(pids);
        assertEq(out.length, 0);
    }
}
