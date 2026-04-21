pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract HyFiHookDepositTest is HyFiHookSharedSetup {
    using CurrencyLibrary for Currency;

    function setUp() public {
        sharedSetup();
    }

    // ─── Native deposit ──────────────────────────────────────────────────

    function test_deposit_native_increasesClaims() public {
        uint256 amount = 50e18;
        uint256 balBefore = hook.lpBalances(mm1, native);
        uint256 claimsBefore = pm.balanceOf(address(hook), native.toId());
        uint256 senderBefore = mm1.balance;

        vm.prank(mm1);
        hook.deposit{value: amount}(native, amount);

        assertEq(hook.lpBalances(mm1, native) - balBefore, amount, "lpBalance should increase");
        assertEq(pm.balanceOf(address(hook), native.toId()) - claimsBefore, amount, "hook claims should increase");
        assertEq(senderBefore - mm1.balance, amount, "sender native balance should decrease");
    }

    function test_deposit_native_oneWei() public {
        uint256 balBefore = hook.lpBalances(mm1, native);
        uint256 claimsBefore = pm.balanceOf(address(hook), native.toId());
        uint256 senderBefore = mm1.balance;

        vm.prank(mm1);
        hook.deposit{value: 1}(native, 1);

        assertEq(hook.lpBalances(mm1, native) - balBefore, 1, "lpBalance should increase by 1");
        assertEq(pm.balanceOf(address(hook), native.toId()) - claimsBefore, 1, "hook claims should increase by 1");
        assertEq(senderBefore - mm1.balance, 1, "sender native balance should decrease by 1");
    }

    // ─── ERC20 deposit ───────────────────────────────────────────────────

    function test_deposit_ERC20_increasesClaims() public {
        uint256 amount = 10e6;
        uint256 balBefore = hook.lpBalances(mm1, usdc);
        uint256 claimsBefore = pm.balanceOf(address(hook), usdc.toId());
        uint256 senderBefore = usdc.balanceOf(mm1);

        vm.startPrank(mm1);
        IERC20(USDC_ADDR).approve(address(hook), amount);
        hook.deposit(usdc, amount);
        vm.stopPrank();

        assertEq(hook.lpBalances(mm1, usdc) - balBefore, amount, "lpBalance should increase");
        assertEq(pm.balanceOf(address(hook), usdc.toId()) - claimsBefore, amount, "hook claims should increase");
        assertEq(senderBefore - usdc.balanceOf(mm1), amount, "sender ERC20 balance should decrease");
    }

    function test_deposit_ERC20_multipleDeposits() public {
        uint256 a1 = 10e6;
        uint256 a2 = 20e6;
        uint256 balBefore = hook.lpBalances(mm1, usdc);
        uint256 claimsBefore = pm.balanceOf(address(hook), usdc.toId());
        uint256 senderBefore = usdc.balanceOf(mm1);

        vm.startPrank(mm1);
        IERC20(USDC_ADDR).approve(address(hook), a1 + a2);
        hook.deposit(usdc, a1);
        hook.deposit(usdc, a2);
        vm.stopPrank();

        assertEq(hook.lpBalances(mm1, usdc) - balBefore, a1 + a2, "lpBalance should increase");
        assertEq(pm.balanceOf(address(hook), usdc.toId()) - claimsBefore, a1 + a2, "hook claims should increase");
        assertEq(senderBefore - usdc.balanceOf(mm1), a1 + a2, "sender ERC20 balance should decrease");
    }

    // ─── Revert: not whitelisted ─────────────────────────────────────────

    function test_deposit_RevertWhen_notWhitelisted() public {
        address notWL = makeAddr("notWL");
        vm.deal(notWL, 1 ether);
        vm.prank(notWL);
        vm.expectRevert(HyFiHook.NotWhitelisted.selector);
        hook.deposit{value: 1 ether}(native, 1 ether);
    }

    // ─── unlockCallback access control ───────────────────────────────────

    function test_unlockCallback_RevertWhen_calledByNonPM() public {
        bytes memory data = abi.encode(true, native, uint256(1e18), mm1);
        vm.expectRevert(HyFiHook.OnlyPoolManager.selector);
        hook.unlockCallback(data);
    }

    // ─── Isolation: deposit does not affect another MM's balance ─────────

    function test_deposit_doesNotAffectOtherMM() public {
        address mm2 = makeAddr("mm2");
        hook.addToWhitelist(mm2);
        vm.deal(mm2, 100e18);

        uint256 mm1BalBefore = hook.lpBalances(mm1, native);

        vm.prank(mm2);
        hook.deposit{value: 10e18}(native, 10e18);

        assertEq(hook.lpBalances(mm2, native), 10e18, "mm2 credited");
        assertEq(hook.lpBalances(mm1, native), mm1BalBefore, "mm1 unchanged");
    }
}
