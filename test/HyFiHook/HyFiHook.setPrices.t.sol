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

        (uint112 storedBid, uint112 storedSpread, uint32 lastUpdate) = hook.getPrices(poolId);
        assertEq(storedBid, bid, "bid should match");
        assertEq(storedSpread, spread, "spread should match");
        assertEq(lastUpdate, 12345, "lastUpdate should be block.timestamp");
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

        (uint112 sb1, uint112 ss1, uint32 lu1) = hook.getPrices(poolId);
        (uint112 sb2, uint112 ss2, uint32 lu2) = hook.getPrices(otherId);

        assertEq(sb1, bid1);
        assertEq(ss1, spread1);
        assertEq(lu1, 1000);
        assertEq(sb2, bid2);
        assertEq(ss2, spread2);
        assertEq(lu2, 1000);
    }

    // ─── Zero spread ─────────────────────────────────────────────────────

    function test_setPrices_zeroSpread() public {
        vm.warp(5555);
        setPricesSingle(hook, poolId, uint112(Q96), 0);

        (uint112 bid, uint112 spread, uint32 ts) = hook.getPrices(poolId);
        assertEq(bid, uint112(Q96));
        assertEq(spread, 0);
        assertEq(ts, 5555);
    }

    // ─── Overwrite existing price ────────────────────────────────────────

    function test_setPrices_overwritesExisting() public {
        vm.warp(100);
        setPricesSingle(hook, poolId, uint112(Q96), uint112(Q96 / 100));

        vm.warp(200);
        setPricesSingle(hook, poolId, uint112(2 * Q96), uint112(Q96 / 50));

        (uint112 bid, uint112 spread, uint32 ts) = hook.getPrices(poolId);
        assertEq(bid, uint112(2 * Q96));
        assertEq(spread, uint112(Q96 / 50));
        assertEq(ts, 200);
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
