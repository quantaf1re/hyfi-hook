pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract HyFiHookWithdrawTest is HyFiHookSharedSetup {
    using CurrencyLibrary for Currency;

    function setUp() public {
        sharedSetup();
    }

    // ─── Native withdraw ─────────────────────────────────────────────────

    function test_withdraw_native_decreasesClaims() public {
        uint256 amount = 50e18;
        uint256 balBefore = hook.lpBalances(mm1, native);
        uint256 claimsBefore = pm.balanceOf(address(hook), native.toId());
        uint256 mm1NativeBefore = mm1.balance;

        vm.prank(mm1);
        hook.withdraw(native, amount);

        assertEq(balBefore - hook.lpBalances(mm1, native), amount, "lpBalance should decrease");
        assertEq(claimsBefore - pm.balanceOf(address(hook), native.toId()), amount, "hook claims should decrease");
        assertEq(mm1.balance - mm1NativeBefore, amount, "mm1 should receive native");
    }

    function test_withdraw_native_entireBalance() public {
        uint256 fullBal = hook.lpBalances(mm1, native);
        assertEq(fullBal, 1_000 * 10 ** POL_DECIMALS, "shared setup deposits fixed native inventory");
        uint256 claimsBefore = pm.balanceOf(address(hook), native.toId());
        uint256 mm1NativeBefore = mm1.balance;

        vm.prank(mm1);
        hook.withdraw(native, fullBal);

        assertEq(hook.lpBalances(mm1, native), 0, "lpBalance should be zero");
        assertEq(claimsBefore - pm.balanceOf(address(hook), native.toId()), fullBal, "hook claims should decrease");
        assertEq(mm1.balance - mm1NativeBefore, fullBal, "mm1 should receive native");
    }

    // ─── ERC20 withdraw ──────────────────────────────────────────────────

    function test_withdraw_ERC20() public {
        uint256 amount = 10e6;
        uint256 balBefore = hook.lpBalances(mm1, usdc);
        uint256 claimsBefore = pm.balanceOf(address(hook), usdc.toId());
        uint256 erc20Before = usdc.balanceOf(mm1);

        vm.prank(mm1);
        hook.withdraw(usdc, amount);

        assertEq(balBefore - hook.lpBalances(mm1, usdc), amount, "lpBalance should decrease");
        assertEq(claimsBefore - pm.balanceOf(address(hook), usdc.toId()), amount, "hook claims should decrease");
        assertEq(usdc.balanceOf(mm1) - erc20Before, amount, "mm1 should receive ERC20");
    }

    // ─── Revert: insufficient balance ────────────────────────────────────

    function test_withdraw_RevertWhen_insufficientBalance() public {
        uint256 balance = hook.lpBalances(mm1, native);

        vm.prank(mm1);
        vm.expectRevert(HyFiHook.InsufficientBalance.selector);
        hook.withdraw(native, balance + 1);
    }

    function test_withdraw_RevertWhen_zeroBalance() public {
        address mm2 = makeAddr("mm2");
        hook.addToWhitelist(mm2);

        vm.prank(mm2);
        vm.expectRevert(HyFiHook.InsufficientBalance.selector);
        hook.withdraw(native, 1);
    }

    // ─── Isolation: withdraw does not touch another MM's balance ─────────

    function test_withdraw_doesNotAffectOtherMM() public {
        address mm2 = makeAddr("mm2");
        hook.addToWhitelist(mm2);
        vm.deal(mm2, 100e18);
        vm.prank(mm2);
        hook.deposit{value: 10e18}(native, 10e18);

        uint256 mm1BalBefore = hook.lpBalances(mm1, native);
        uint256 mm2BalBefore = hook.lpBalances(mm2, native);

        vm.prank(mm1);
        hook.withdraw(native, 5e18);

        assertEq(mm1BalBefore - hook.lpBalances(mm1, native), 5e18, "mm1 balance decreased");
        assertEq(hook.lpBalances(mm2, native), mm2BalBefore, "mm2 balance unchanged");
    }

    // ─── Withdrawing immediately after a swap works against reduced balance ─

    function test_withdraw_afterSwapReducesBalance() public {
        uint256 amountIn = 1e18;
        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(amountIn));

        uint256 usdcBalAfterSwap = hook.lpBalances(mm1, usdc);
        assertLt(usdcBalAfterSwap, 1_000 * 10 ** USDC_DECIMALS, "usdc balance reduced after swap");

        // Withdraw full remaining USDC
        vm.prank(mm1);
        hook.withdraw(usdc, usdcBalAfterSwap);
        assertEq(hook.lpBalances(mm1, usdc), 0, "lpBalance should be zero after full withdraw");
    }
}
