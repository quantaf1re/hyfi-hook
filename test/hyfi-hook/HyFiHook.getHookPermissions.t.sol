// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "./HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

contract HyFiHookGetHookPermissionsTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    function test_getHookPermissions() public view {
        Hooks.Permissions memory p = hook.getHookPermissions();
        assertTrue(p.beforeAddLiquidity, "beforeAddLiquidity should be true");
        assertTrue(p.beforeSwap, "beforeSwap should be true");
        assertTrue(p.beforeSwapReturnDelta, "beforeSwapReturnDelta should be true");
        assertFalse(p.beforeInitialize, "beforeInitialize");
        assertFalse(p.afterInitialize, "afterInitialize");
        assertFalse(p.afterAddLiquidity, "afterAddLiquidity");
        assertFalse(p.beforeRemoveLiquidity, "beforeRemoveLiquidity");
        assertFalse(p.afterRemoveLiquidity, "afterRemoveLiquidity");
        assertFalse(p.afterSwap, "afterSwap");
        assertFalse(p.beforeDonate, "beforeDonate");
        assertFalse(p.afterDonate, "afterDonate");
        assertFalse(p.afterSwapReturnDelta, "afterSwapReturnDelta");
        assertFalse(p.afterAddLiquidityReturnDelta, "afterAddLiquidityReturnDelta");
        assertFalse(p.afterRemoveLiquidityReturnDelta, "afterRemoveLiquidityReturnDelta");
    }
}
