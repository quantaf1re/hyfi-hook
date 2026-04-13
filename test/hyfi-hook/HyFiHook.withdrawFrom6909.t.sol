pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "./HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract HyFiHookWithdrawFrom6909Test is HyFiHookSharedSetup {
    using CurrencyLibrary for Currency;

    function setUp() public {
        sharedSetup();
    }

    // ─── Native withdraw (currency0 = POL) ────────────────────────────────

    function test_withdrawFrom6909_native_decreasesClaims() public {
        uint256 amount = 50e18;
        uint256 claimsBefore = pm.balanceOf(address(hook), c0.toId());
        uint256 balBefore = address(this).balance;

        hook.withdrawFrom6909(c0, amount);

        uint256 claimsAfter = pm.balanceOf(address(hook), c0.toId());
        uint256 balAfter = address(this).balance;

        assertEq(claimsBefore - claimsAfter, amount, "claims should decrease by amount");
        assertEq(balAfter - balBefore, amount, "native balance should increase by amount");
    }

    function test_withdrawFrom6909_native_entireBalance() public {
        uint256 fullBalance = pm.balanceOf(address(hook), c0.toId());
        assertGt(fullBalance, 0, "hook should have claims");

        uint256 balBefore = address(this).balance;

        hook.withdrawFrom6909(c0, fullBalance);

        assertEq(pm.balanceOf(address(hook), c0.toId()), 0, "all claims withdrawn");
        assertEq(address(this).balance - balBefore, fullBalance, "full amount returned");
    }

    function test_withdrawFrom6909_native_oneWei() public {
        uint256 claimsBefore = pm.balanceOf(address(hook), c0.toId());

        hook.withdrawFrom6909(c0, 1);

        assertEq(pm.balanceOf(address(hook), c0.toId()), claimsBefore - 1, "1 wei withdraw");
    }

    function test_withdrawFrom6909_native_doesNotAffectOtherCurrency() public {
        uint256 claims1Before = pm.balanceOf(address(hook), c1.toId());

        hook.withdrawFrom6909(c0, 10e18);

        assertEq(pm.balanceOf(address(hook), c1.toId()), claims1Before, "other currency unchanged");
    }

    // ─── ERC-20 withdraw (currency1 = USDC) ──────────────────────────────

    function test_withdrawFrom6909_ERC20_multipleWithdrawals() public {
        uint256 amount1 = 10e6;
        uint256 amount2 = 20e6;
        uint256 claimsBefore = pm.balanceOf(address(hook), c1.toId());
        uint256 erc20Before = IERC20(Currency.unwrap(c1)).balanceOf(address(this));

        hook.withdrawFrom6909(c1, amount1);
        hook.withdrawFrom6909(c1, amount2);

        assertEq(claimsBefore - pm.balanceOf(address(hook), c1.toId()), amount1 + amount2, "claims decrease by total");
        assertEq(
            IERC20(Currency.unwrap(c1)).balanceOf(address(this)) - erc20Before,
            amount1 + amount2,
            "ERC20 increase by total"
        );
    }

    // ─── Access control ──────────────────────────────────────────────────

    function test_withdrawFrom6909_RevertWhen_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        hook.withdrawFrom6909(c0, 1e18);
    }
}
