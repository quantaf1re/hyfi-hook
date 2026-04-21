pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract HyFiHookCollectProtocolFeesTest is HyFiHookSharedSetup {
    using CurrencyLibrary for Currency;

    function setUp() public {
        sharedSetup();
        // Enable protocol fee
        hook.setProtocolFee(10_000); // 1%
    }

    // ─── Happy path: collect after a swap ────────────────────────────────

    function test_collectProtocolFees_transfersAccumulatedFees() public {
        // Execute a swap to generate protocol fees
        uint256 amountIn = 1e18;
        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        uint256 feeAmount = hook.protocolFees(native);
        assertEq(feeAmount, amountIn * 10_000 / FEE_DENOM, "fees should match protocol cut");

        uint256 claimsBefore = pm.balanceOf(address(hook), native.toId());
        uint256 ownerNativeBefore = owner.balance;

        hook.collectProtocolFees(native);

        assertEq(hook.protocolFees(native), 0, "fees should be zeroed");
        assertEq(claimsBefore - pm.balanceOf(address(hook), native.toId()), feeAmount, "hook claims should decrease");
        assertEq(owner.balance - ownerNativeBefore, feeAmount, "owner should receive native");
    }

    // ─── No-op when zero fees ────────────────────────────────────────────

    function test_collectProtocolFees_RevertWhen_zeroFees() public {
        assertEq(hook.protocolFees(native), 0);
        vm.expectRevert(HyFiHook.NoFeesToCollect.selector);
        hook.collectProtocolFees(native);
    }

    // ─── Access control ──────────────────────────────────────────────────

    function test_collectProtocolFees_RevertWhen_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        hook.collectProtocolFees(native);
    }

    // ─── Collect ERC20 fees ──────────────────────────────────────────────

    function test_collectProtocolFees_ERC20() public {
        // Swap oneForZero to generate fees in usdc (USDC)
        uint256 amountIn = 1e6;
        swap(UNIVERSAL_ROUTER, poolKey, false, -int256(amountIn));

        uint256 feeAmount = hook.protocolFees(usdc);
        assertEq(feeAmount, amountIn * 10_000 / FEE_DENOM, "USDC fees should match protocol cut");

        uint256 claimsBefore = pm.balanceOf(address(hook), usdc.toId());
        uint256 ownerUsdcBefore = usdc.balanceOf(owner);

        hook.collectProtocolFees(usdc);

        assertEq(hook.protocolFees(usdc), 0, "USDC fees should be zeroed");
        assertEq(claimsBefore - pm.balanceOf(address(hook), usdc.toId()), feeAmount, "hook claims should decrease");
        assertEq(usdc.balanceOf(owner) - ownerUsdcBefore, feeAmount, "owner should receive USDC");
    }
}
