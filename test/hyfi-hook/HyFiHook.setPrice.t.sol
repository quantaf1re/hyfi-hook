pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "./HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract HyFiHookSetPriceTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    // ─── Happy path ──────────────────────────────────────────────────────

    function test_setPrice_storesAllFields() public {
        uint112 bid = uint112(2 * Q96);
        uint112 spread = uint112(Q96 / 50);

        vm.warp(12345);
        hook.setPrice(poolId, bid, spread);

        (uint112 storedBid, uint112 storedSpread, uint32 lastUpdate) = hook.getPrice(poolId);
        assertEq(storedBid, bid, "bid should match");
        assertEq(storedSpread, spread, "spread should match");
        assertEq(lastUpdate, 12345, "lastUpdate should be block.timestamp");
    }

    function test_setPrice_differentPoolIds() public {
        PoolId otherId = PoolId.wrap(keccak256("other"));

        uint112 bid1 = uint112(Q96);
        uint112 spread1 = uint112(Q96 / 100);
        uint112 bid2 = uint112(2 * Q96);
        uint112 spread2 = uint112(Q96 / 50);

        vm.warp(1000);
        hook.setPrice(poolId, bid1, spread1);
        vm.warp(2000);
        hook.setPrice(otherId, bid2, spread2);

        (uint112 storedBid1, uint112 storedSpread1, uint32 lastUpdate1) = hook.getPrice(poolId);
        (uint112 storedBid2, uint112 storedSpread2, uint32 lastUpdate2) = hook.getPrice(otherId);

        assertEq(storedBid1, bid1, "pool1 bid");
        assertEq(storedSpread1, spread1, "pool1 spread");
        assertEq(lastUpdate1, 1000, "pool1 timestamp");
        assertEq(storedBid2, bid2, "pool2 bid");
        assertEq(storedSpread2, spread2, "pool2 spread");
        assertEq(lastUpdate2, 2000, "pool2 timestamp");
    }

    function test_setPrice_zeroSpread() public {
        uint112 bid = uint112(Q96);
        vm.warp(5555);
        hook.setPrice(poolId, bid, 0);

        (uint112 storedBid, uint112 storedSpread, uint32 lastUpdate) = hook.getPrice(poolId);
        assertEq(storedBid, bid, "bid");
        assertEq(storedSpread, 0, "spread should be zero");
        assertEq(lastUpdate, 5555, "timestamp");
    }

    // ─── Access control ──────────────────────────────────────────────────

    function test_setPrice_RevertWhen_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        hook.setPrice(poolId, uint112(Q96), uint112(Q96 / 100));
    }
}
