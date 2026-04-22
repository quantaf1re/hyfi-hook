pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract HyFiHookSetPricesTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    // ─── Happy path: single pool ─────────────────────────────────────────

    function test_setPrices_storesAllFields() public {
        uint112 bid = uint112(2 * Q96);
        uint112 spread = uint112(Q96 / 50);

        vm.warp(12345);
        setPricesSingle(hook, poolId, bid, spread);

        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        HyFiHook.PriceData[] memory got = hook.getPrices(pids);
        assertEq(got[0].bidPriceX96, bid, "bid should match");
        assertEq(got[0].spreadX96, spread, "spread should match");
        assertEq(got[0].lastUpdate, 12345, "lastUpdate should be block.timestamp");
    }

    // ─── Multiple pools in one call ──────────────────────────────────────

    function test_setPrices_multiplePoolIds() public {
        PoolId otherId = PoolId.wrap(keccak256("other"));

        uint112 bid1 = uint112(Q96);
        uint112 spread1 = uint112(Q96 / 100);
        uint112 bid2 = uint112(2 * Q96);
        uint112 spread2 = uint112(Q96 / 50);

        PoolId[] memory pids = new PoolId[](2);
        pids[0] = poolId;
        pids[1] = otherId;
        uint112[] memory bids = new uint112[](2);
        bids[0] = bid1;
        bids[1] = bid2;
        uint112[] memory spreads = new uint112[](2);
        spreads[0] = spread1;
        spreads[1] = spread2;

        vm.warp(1000);
        hook.setPrices(pids, bids, spreads);

        HyFiHook.PriceData[] memory got = hook.getPrices(pids);

        assertEq(got[0].bidPriceX96, bid1);
        assertEq(got[0].spreadX96, spread1);
        assertEq(got[0].lastUpdate, 1000);
        assertEq(got[1].bidPriceX96, bid2);
        assertEq(got[1].spreadX96, spread2);
        assertEq(got[1].lastUpdate, 1000);
    }

    // ─── Zero spread ─────────────────────────────────────────────────────

    function test_setPrices_zeroSpread() public {
        vm.warp(5555);
        setPricesSingle(hook, poolId, uint112(Q96), 0);

        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        HyFiHook.PriceData[] memory got = hook.getPrices(pids);
        assertEq(got[0].bidPriceX96, uint112(Q96));
        assertEq(got[0].spreadX96, 0);
        assertEq(got[0].lastUpdate, 5555);
    }

    // ─── Overwrite existing price ────────────────────────────────────────

    function test_setPrices_overwritesExisting() public {
        vm.warp(100);
        setPricesSingle(hook, poolId, uint112(Q96), uint112(Q96 / 100));

        vm.warp(200);
        setPricesSingle(hook, poolId, uint112(2 * Q96), uint112(Q96 / 50));

        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        HyFiHook.PriceData[] memory got = hook.getPrices(pids);
        assertEq(got[0].bidPriceX96, uint112(2 * Q96));
        assertEq(got[0].spreadX96, uint112(Q96 / 50));
        assertEq(got[0].lastUpdate, 200);
    }

    // ─── Length mismatch ─────────────────────────────────────────────────

    function test_setPrices_RevertWhen_bidLengthMismatch() public {
        PoolId[] memory pids = new PoolId[](2);
        uint112[] memory bids = new uint112[](1);
        uint112[] memory spreads = new uint112[](2);

        vm.expectRevert(HyFiHook.LengthMismatch.selector);
        hook.setPrices(pids, bids, spreads);
    }

    function test_setPrices_RevertWhen_spreadLengthMismatch() public {
        PoolId[] memory pids = new PoolId[](2);
        uint112[] memory bids = new uint112[](2);
        uint112[] memory spreads = new uint112[](1);

        vm.expectRevert(HyFiHook.LengthMismatch.selector);
        hook.setPrices(pids, bids, spreads);
    }

    // ─── Access control ──────────────────────────────────────────────────

    function test_setPrices_RevertWhen_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        uint112[] memory bids = new uint112[](1);
        bids[0] = uint112(Q96);
        uint112[] memory spreads = new uint112[](1);
        spreads[0] = 0;

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        hook.setPrices(pids, bids, spreads);
    }
}
