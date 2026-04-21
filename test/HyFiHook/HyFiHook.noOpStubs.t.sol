pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

contract HyFiHookNoOpStubsTest is HyFiHookSharedSetup {
    ModifyLiquidityParams internal LIQUIDITY_PARAMS =
        ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: 0});

    function setUp() public {
        sharedSetup();
    }

    // ─── beforeAddLiquidity reverts NoDirectLiquidity ─────────────────────

    function test_beforeAddLiquidity_RevertWhen_called() public {
        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.NoDirectLiquidity.selector);
        hook.beforeAddLiquidity(address(this), poolKey, LIQUIDITY_PARAMS, "");
    }

    // ─── beforeInitialize ────────────────────────────────────────────────

    function test_beforeInitialize_RevertWhen_called() public {
        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.HookNotUsed.selector);
        hook.beforeInitialize(ADDR_ZERO, poolKey, 0);
    }

    // ─── afterInitialize ─────────────────────────────────────────────────

    function test_afterInitialize_RevertWhen_called() public {
        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.HookNotUsed.selector);
        hook.afterInitialize(ADDR_ZERO, poolKey, 0, 0);
    }

    // ─── afterAddLiquidity ───────────────────────────────────────────────

    function test_afterAddLiquidity_RevertWhen_called() public {
        BalanceDelta emptyDelta;
        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.HookNotUsed.selector);
        hook.afterAddLiquidity(ADDR_ZERO, poolKey, LIQUIDITY_PARAMS, emptyDelta, emptyDelta, "");
    }

    // ─── beforeRemoveLiquidity ───────────────────────────────────────────

    function test_beforeRemoveLiquidity_RevertWhen_called() public {
        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.HookNotUsed.selector);
        hook.beforeRemoveLiquidity(ADDR_ZERO, poolKey, LIQUIDITY_PARAMS, "");
    }

    // ─── afterRemoveLiquidity ────────────────────────────────────────────

    function test_afterRemoveLiquidity_RevertWhen_called() public {
        BalanceDelta emptyDelta;
        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.HookNotUsed.selector);
        hook.afterRemoveLiquidity(ADDR_ZERO, poolKey, LIQUIDITY_PARAMS, emptyDelta, emptyDelta, "");
    }

    // ─── afterSwap ───────────────────────────────────────────────────────

    function test_afterSwap_RevertWhen_called() public {
        BalanceDelta emptyDelta;
        SwapParams memory params = SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: 0});
        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.HookNotUsed.selector);
        hook.afterSwap(ADDR_ZERO, poolKey, params, emptyDelta, "");
    }

    // ─── beforeDonate ────────────────────────────────────────────────────

    function test_beforeDonate_RevertWhen_called() public {
        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.HookNotUsed.selector);
        hook.beforeDonate(ADDR_ZERO, poolKey, 0, 0, "");
    }

    // ─── afterDonate ─────────────────────────────────────────────────────

    function test_afterDonate_RevertWhen_called() public {
        vm.prank(address(pm));
        vm.expectRevert(HyFiHook.HookNotUsed.selector);
        hook.afterDonate(ADDR_ZERO, poolKey, 0, 0, "");
    }
}
