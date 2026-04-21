pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract HyFiHookGetPricesTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    function test_getPrices_returnsStoredValues() public view {
        (uint112 bid, uint112 spread, uint32 ts) = hook.getPrices(poolId);
        assertEq(bid, BID_PRICE_X96);
        assertEq(spread, SPREAD_X96);
        assertGt(ts, 0);
    }

    function test_getPrices_unsetPool_returnsZeros() public view {
        PoolId unknown = PoolId.wrap(keccak256("unknown"));
        (uint112 bid, uint112 spread, uint32 ts) = hook.getPrices(unknown);
        assertEq(bid, 0);
        assertEq(spread, 0);
        assertEq(ts, 0);
    }
}
