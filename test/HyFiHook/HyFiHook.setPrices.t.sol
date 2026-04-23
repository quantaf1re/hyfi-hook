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
        uint32 oracleTs = 12345;

        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        HyFiHook.PriceData[] memory prices = new HyFiHook.PriceData[](1);
        prices[0] = HyFiHook.PriceData(bid, spread, oracleTs);

        hook.setPrices(pids, prices);

        HyFiHook.PriceData[] memory got = hook.getPrices(pids);
        assertEq(got[0].bidPriceX96, bid, "bid should match");
        assertEq(got[0].spreadX96, spread, "spread should match");
        assertEq(got[0].timestamp, oracleTs, "timestamp should be oracle-supplied");
    }

    // ─── Oracle timestamp preserved (does NOT use block.timestamp) ──────

    function test_setPrices_oracleTimestampPreserved() public {
        uint32 oracleTs = 42;

        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        HyFiHook.PriceData[] memory prices = new HyFiHook.PriceData[](1);
        prices[0] = HyFiHook.PriceData(uint112(Q96), uint112(Q96 / 100), oracleTs);

        vm.warp(999_999);
        hook.setPrices(pids, prices);

        HyFiHook.PriceData[] memory got = hook.getPrices(pids);
        assertEq(got[0].timestamp, oracleTs, "timestamp must be the oracle value, not block.timestamp");
    }

    // ─── Multiple pools in one call (each with its own timestamp) ───────

    function test_setPrices_multiplePoolIds() public {
        PoolId otherId = PoolId.wrap(keccak256("other"));

        uint112 bid1 = uint112(Q96);
        uint112 spread1 = uint112(Q96 / 100);
        uint112 bid2 = uint112(2 * Q96);
        uint112 spread2 = uint112(Q96 / 50);

        PoolId[] memory pids = new PoolId[](2);
        pids[0] = poolId;
        pids[1] = otherId;
        HyFiHook.PriceData[] memory prices = new HyFiHook.PriceData[](2);
        prices[0] = HyFiHook.PriceData(bid1, spread1, 1000);
        prices[1] = HyFiHook.PriceData(bid2, spread2, 2000);

        hook.setPrices(pids, prices);

        HyFiHook.PriceData[] memory got = hook.getPrices(pids);

        assertEq(got[0].bidPriceX96, bid1);
        assertEq(got[0].spreadX96, spread1);
        assertEq(got[0].timestamp, 1000);
        assertEq(got[1].bidPriceX96, bid2);
        assertEq(got[1].spreadX96, spread2);
        assertEq(got[1].timestamp, 2000);
    }

    // ─── Zero spread ─────────────────────────────────────────────────────

    function test_setPrices_zeroSpread() public {
        setPricesSingle(hook, poolId, uint112(Q96), 0, uint32(block.timestamp));

        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        HyFiHook.PriceData[] memory got = hook.getPrices(pids);
        assertEq(got[0].bidPriceX96, uint112(Q96));
        assertEq(got[0].spreadX96, 0);
        assertEq(got[0].timestamp, uint32(block.timestamp));
    }

    // ─── Overwrite existing price ────────────────────────────────────────

    function test_setPrices_overwritesExisting() public {
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;

        HyFiHook.PriceData[] memory p1 = new HyFiHook.PriceData[](1);
        p1[0] = HyFiHook.PriceData(uint112(Q96), uint112(Q96 / 100), 100);
        hook.setPrices(pids, p1);

        HyFiHook.PriceData[] memory p2 = new HyFiHook.PriceData[](1);
        p2[0] = HyFiHook.PriceData(uint112(2 * Q96), uint112(Q96 / 50), 200);
        hook.setPrices(pids, p2);

        HyFiHook.PriceData[] memory got = hook.getPrices(pids);
        assertEq(got[0].bidPriceX96, uint112(2 * Q96));
        assertEq(got[0].spreadX96, uint112(Q96 / 50));
        assertEq(got[0].timestamp, 200);
    }

    // ─── Length mismatch ─────────────────────────────────────────────────

    function test_setPrices_RevertWhen_lengthMismatch() public {
        PoolId[] memory pids = new PoolId[](2);
        HyFiHook.PriceData[] memory prices = new HyFiHook.PriceData[](1);

        vm.expectRevert(HyFiHook.LengthMismatch.selector);
        hook.setPrices(pids, prices);
    }

    // ─── Access control ──────────────────────────────────────────────────

    function test_setPrices_RevertWhen_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        HyFiHook.PriceData[] memory prices = new HyFiHook.PriceData[](1);
        prices[0] = HyFiHook.PriceData(uint112(Q96), 0, uint32(block.timestamp));

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        hook.setPrices(pids, prices);
    }
}
