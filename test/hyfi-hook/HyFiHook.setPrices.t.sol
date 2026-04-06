// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "./HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract HyFiHookSetPricesTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    // ─── Happy path ──────────────────────────────────────────────────────

    function test_setPrices_singlePool() public {
        PoolId[] memory ids = new PoolId[](1);
        ids[0] = poolId;
        uint112[] memory bids = new uint112[](1);
        bids[0] = uint112(2 * Q96);
        uint112[] memory spreads = new uint112[](1);
        spreads[0] = uint112(Q96 / 50);

        vm.warp(5000);
        hook.setPrices(ids, bids, spreads);

        (uint112 storedBid, uint112 storedSpread, uint32 lastUpdate) = hook.getPrice(poolId);
        assertEq(storedBid, bids[0], "bid");
        assertEq(storedSpread, spreads[0], "spread");
        assertEq(lastUpdate, 5000, "timestamp");
    }

    function test_setPrices_multiplePools() public {
        PoolId id2 = PoolId.wrap(keccak256("pool2"));
        PoolId id3 = PoolId.wrap(keccak256("pool3"));

        PoolId[] memory ids = new PoolId[](3);
        ids[0] = poolId;
        ids[1] = id2;
        ids[2] = id3;

        uint112[] memory bids = new uint112[](3);
        bids[0] = uint112(Q96);
        bids[1] = uint112(2 * Q96);
        bids[2] = uint112(3 * Q96);

        uint112[] memory spreads = new uint112[](3);
        spreads[0] = uint112(Q96 / 100);
        spreads[1] = uint112(Q96 / 50);
        spreads[2] = uint112(Q96 / 25);

        vm.warp(7777);
        hook.setPrices(ids, bids, spreads);

        for (uint256 i; i < 3; ++i) {
            (uint112 b, uint112 s, uint32 t) = hook.getPrice(ids[i]);
            assertEq(b, bids[i], "bid mismatch");
            assertEq(s, spreads[i], "spread mismatch");
            assertEq(t, 7777, "timestamp mismatch");
        }
    }

    function test_setPrices_emptyArrays() public {
        PoolId[] memory ids = new PoolId[](0);
        uint112[] memory bids = new uint112[](0);
        uint112[] memory spreads = new uint112[](0);

        // Should succeed (no-op)
        hook.setPrices(ids, bids, spreads);

        // Existing price unchanged
        (uint112 storedBid, uint112 storedSpread,) = hook.getPrice(poolId);
        assertEq(storedBid, BID_PRICE_X96, "bid unchanged");
        assertEq(storedSpread, SPREAD_X96, "spread unchanged");
    }

    // ─── Revert: length mismatch ─────────────────────────────────────────

    function test_setPrices_RevertWhen_bidLengthMismatch() public {
        PoolId[] memory ids = new PoolId[](2);
        uint112[] memory bids = new uint112[](1); // mismatch
        uint112[] memory spreads = new uint112[](2);

        vm.expectRevert(HyFiHook.LengthMismatch.selector);
        hook.setPrices(ids, bids, spreads);
    }

    function test_setPrices_RevertWhen_spreadLengthMismatch() public {
        PoolId[] memory ids = new PoolId[](2);
        uint112[] memory bids = new uint112[](2);
        uint112[] memory spreads = new uint112[](1); // mismatch

        vm.expectRevert(HyFiHook.LengthMismatch.selector);
        hook.setPrices(ids, bids, spreads);
    }

    // ─── Access control ──────────────────────────────────────────────────

    function test_setPrices_RevertWhen_notOwner() public {
        PoolId[] memory ids = new PoolId[](1);
        ids[0] = poolId;
        uint112[] memory bids = new uint112[](1);
        bids[0] = uint112(Q96);
        uint112[] memory spreads = new uint112[](1);
        spreads[0] = uint112(Q96 / 100);

        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        hook.setPrices(ids, bids, spreads);
    }
}
