pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract HyFiHookUpdateProtocolFeeTest is HyFiHookSharedSetup {
    using CurrencyLibrary for Currency;

    function setUp() public {
        sharedSetup();
    }

    // ─── Happy path ──────────────────────────────────────────────────────

    function test_updateProtocolFee_setsValue() public {
        hook.updateProtocolFee(1000); // 0.1%
        assertEq(hook.getProtocolFeePips(), 1000);
    }

    function test_updateProtocolFee_zero() public {
        hook.updateProtocolFee(1000);
        hook.updateProtocolFee(0);
        assertEq(hook.getProtocolFeePips(), 0);
    }

    function test_updateProtocolFee_maxValue() public {
        hook.updateProtocolFee(1_000_000); // 100% = FEE_DENOM
        assertEq(hook.getProtocolFeePips(), 1_000_000);
    }

    // ─── Revert: fee too high ────────────────────────────────────────────

    function test_updateProtocolFee_RevertWhen_exceedsDenom() public {
        vm.expectRevert(HyFiHook.FeeTooHigh.selector);
        hook.updateProtocolFee(1_000_001);
    }

    // ─── Access control ──────────────────────────────────────────────────

    function test_updateProtocolFee_RevertWhen_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        hook.updateProtocolFee(1000);
    }

    // ─── Deep: fee deducted from MM input on swap ────────────────────────

    function test_updateProtocolFee_feeDeductedFromMMInputOnSwap_oneForZero() public {
        uint256 feePips = 10_000; // 1%
        hook.updateProtocolFee(feePips);

        uint256 amountIn = 1e6; // 1 USDC in
        uint256 expectedCut = amountIn * feePips / FEE_DENOM;

        uint256 mm1UsdcBefore = pm.balanceOf(address(quoter), usdc.toId());
        uint256 protocolFeesBefore = pm.balanceOf(address(hook), usdc.toId());

        swap(UNIVERSAL_ROUTER, poolKey, false, -int256(amountIn));

        uint256 protocolFeesAfter = pm.balanceOf(address(hook), usdc.toId());
        uint256 mm1UsdcAfter = pm.balanceOf(address(quoter), usdc.toId());

        // Protocol gets exactly the cut
        assertEq(protocolFeesAfter - protocolFeesBefore, expectedCut, "protocol fee accumulation");
        // MM gets input minus the protocol cut
        assertEq(mm1UsdcAfter - mm1UsdcBefore, amountIn - expectedCut, "MM receives input minus fee");
    }
}
