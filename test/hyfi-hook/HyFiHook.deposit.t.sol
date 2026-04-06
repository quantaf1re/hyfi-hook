// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "./HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract HyFiHookDepositTest is HyFiHookSharedSetup {
    using CurrencyLibrary for Currency;

    function setUp() public {
        sharedSetup();
    }

    // ─── Native deposit (currency0 = POL) ────────────────────────────────

    function test_deposit_native_increasesClaims() public {
        uint256 amount = 50e18;
        uint256 balBefore = address(this).balance;
        uint256 claims0Before = pm.balanceOf(address(hook), c0.toId());
        uint256 claims1Before = pm.balanceOf(address(hook), c1.toId());

        hook.deposit{value: amount}(c0, amount);

        uint256 balAfter = address(this).balance;
        uint256 claims0After = pm.balanceOf(address(hook), c0.toId());

        assertEq(balBefore - balAfter, amount, "native balance should decrease by amount");
        assertEq(claims0After - claims0Before, amount, "claims should increase by amount");
        assertEq(pm.balanceOf(address(hook), c1.toId()), claims1Before, "other currency claims unchanged");
    }

    function test_deposit_native_oneWei() public {
        uint256 claimsBefore = pm.balanceOf(address(hook), c0.toId());

        hook.deposit{value: 1}(c0, 1);

        assertEq(pm.balanceOf(address(hook), c0.toId()), claimsBefore + 1, "1 wei deposit");
    }

    // ─── ERC-20 deposit (currency1 = USDC) ───────────────────────────────

    function test_deposit_ERC20_multipleDeposits() public {
        uint256 amount1 = 10e6;
        uint256 amount2 = 20e6;
        uint256 claimsBefore = pm.balanceOf(address(hook), c1.toId());

        IERC20(Currency.unwrap(c1)).approve(address(hook), amount1 + amount2);
        hook.deposit(c1, amount1);
        hook.deposit(c1, amount2);

        uint256 claimsAfter = pm.balanceOf(address(hook), c1.toId());
        assertEq(claimsAfter - claimsBefore, amount1 + amount2, "claims should sum");
    }

    // ─── Access control ──────────────────────────────────────────────────

    function test_deposit_RevertWhen_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        hook.deposit(c0, 1e18);
    }

    // ─── unlockCallback access control ───────────────────────────────────

    function test_unlockCallback_RevertWhen_calledByNonPM() public {
        bytes memory data = abi.encode(true, c0, uint256(1e18), address(this));
        vm.expectRevert(HyFiHook.OnlyPoolManager.selector);
        hook.unlockCallback(data);
    }
}
