pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract HyFiHookWithdrawTokenTest is HyFiHookSharedSetup {
    using CurrencyLibrary for Currency;

    function setUp() public {
        sharedSetup();
    }

    // ─── withdrawToken (ERC-20) ───────────────────────────────────────────

    function test_withdrawToken_transfersERC20ToOwner() public {
        uint256 amount = 100e6;
        deal(USDC_ADDR, address(hook), amount);

        uint256 ownerBefore = usdc.balanceOf(owner);
        hook.withdrawToken(usdc, amount);
        uint256 ownerAfter = usdc.balanceOf(owner);

        assertEq(ownerAfter - ownerBefore, amount, "owner should receive tokens");
        assertEq(usdc.balanceOf(address(hook)), 0, "hook should have 0 ERC20 balance");
    }

    function test_withdrawToken_partialAmount() public {
        uint256 total = 200e6;
        uint256 withdrawAmt = 50e6;
        deal(USDC_ADDR, address(hook), total);

        uint256 ownerBefore = usdc.balanceOf(owner);
        hook.withdrawToken(usdc, withdrawAmt);

        assertEq(usdc.balanceOf(address(hook)), total - withdrawAmt, "hook should retain remainder");
        assertEq(usdc.balanceOf(owner) - ownerBefore, withdrawAmt, "owner should receive tokens");
    }

    // ─── withdrawToken (native) ───────────────────────────────────────────

    function test_withdrawToken_native_transfersToOwner() public {
        uint256 amount = 5e18;
        vm.deal(address(hook), amount);

        uint256 ownerBefore = owner.balance;
        hook.withdrawToken(native, amount);
        uint256 ownerAfter = owner.balance;

        assertEq(ownerAfter - ownerBefore, amount, "owner should receive native");
        assertEq(address(hook).balance, 0, "hook should have 0 native balance");
    }

    function test_withdrawToken_native_partialAmount() public {
        uint256 total = 10e18;
        uint256 withdrawAmt = 3e18;
        vm.deal(address(hook), total);

        uint256 ownerBefore = owner.balance;
        hook.withdrawToken(native, withdrawAmt);

        assertEq(address(hook).balance, total - withdrawAmt, "hook should retain remainder");
        assertEq(owner.balance - ownerBefore, withdrawAmt, "owner should receive native");
    }

    // ─── Access control ──────────────────────────────────────────────────

    function test_withdrawToken_RevertWhen_notOwner() public {
        deal(USDC_ADDR, address(hook), 100e6);

        address notOwner = address(0xdead);
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner));
        hook.withdrawToken(usdc, 100e6);
    }

    function test_withdrawToken_native_RevertWhen_notOwner() public {
        vm.deal(address(hook), 5e18);

        address notOwner = address(0xdead);
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner));
        hook.withdrawToken(native, 5e18);
    }
}
