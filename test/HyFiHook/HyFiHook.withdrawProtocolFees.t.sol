pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract HyFiHookWithdrawProtocolFeesTest is HyFiHookSharedSetup {
    using CurrencyLibrary for Currency;

    function setUp() public {
        sharedSetup();
        // Enable protocol fee
        hook.updateProtocolFee(10_000); // 1%
    }

    // ─── Happy path: collect after a swap ────────────────────────────────

    function test_withdrawProtocolFees_transfersAccumulatedFees() public {
        // Execute a swap to generate protocol fees
        uint256 amountIn = 1e18;
        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        uint256 feeAmount = pm.balanceOf(address(hook), native.toId());
        assertEq(feeAmount, amountIn * 10_000 / FEE_DENOM, "fees should match protocol cut");

        uint256 ownerNativeBefore = owner.balance;

        hook.withdrawProtocolFees(native);

        assertEq(pm.balanceOf(address(hook), native.toId()), 0, "hook claims should be zeroed");
        assertEq(owner.balance - ownerNativeBefore, feeAmount, "owner should receive native");
    }

    // ─── No-op when zero fees ────────────────────────────────────────────

    function test_withdrawProtocolFees_RevertWhen_zeroFees() public {
        assertEq(pm.balanceOf(address(hook), native.toId()), 0);
        vm.expectRevert(HyFiHook.NoFeesToCollect.selector);
        hook.withdrawProtocolFees(native);
    }

    // ─── Access control ──────────────────────────────────────────────────

    function test_withdrawProtocolFees_RevertWhen_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        hook.withdrawProtocolFees(native);
    }

    // ─── Collect ERC20 fees ──────────────────────────────────────────────

    function test_withdrawProtocolFees_ERC20() public {
        // Swap oneForZero to generate fees in usdc (USDC)
        uint256 amountIn = 1e6;
        swap(UNIVERSAL_ROUTER, poolKey, false, -int256(amountIn));

        uint256 feeAmount = pm.balanceOf(address(hook), usdc.toId());
        assertEq(feeAmount, amountIn * 10_000 / FEE_DENOM, "USDC fees should match protocol cut");

        uint256 ownerUsdcBefore = usdc.balanceOf(owner);

        hook.withdrawProtocolFees(usdc);

        assertEq(pm.balanceOf(address(hook), usdc.toId()), 0, "hook USDC claims should be zeroed");
        assertEq(usdc.balanceOf(owner) - ownerUsdcBefore, feeAmount, "owner should receive USDC");
    }
}
