pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "./HyFiHookSharedSetup.sol";
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

        uint256 ownerBefore = IERC20(USDC_ADDR).balanceOf(owner);
        hook.withdrawToken(c1, amount);
        uint256 ownerAfter = IERC20(USDC_ADDR).balanceOf(owner);

        assertEq(ownerAfter - ownerBefore, amount, "owner should receive tokens");
        assertEq(IERC20(USDC_ADDR).balanceOf(address(hook)), 0, "hook should have 0 ERC20 balance");
    }

    function test_withdrawToken_partialAmount() public {
        uint256 total = 200e6;
        uint256 withdrawAmt = 50e6;
        deal(USDC_ADDR, address(hook), total);

        hook.withdrawToken(c1, withdrawAmt);

        assertEq(IERC20(USDC_ADDR).balanceOf(address(hook)), total - withdrawAmt);
    }

    function test_withdrawToken_RevertWhen_notOwner() public {
        deal(USDC_ADDR, address(hook), 100e6);

        address notOwner = address(0xdead);
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner));
        hook.withdrawToken(c1, 100e6);
    }

    // ─── withdrawToken (native) ───────────────────────────────────────────

    function test_withdrawToken_native_transfersToOwner() public {
        uint256 amount = 5e18;
        vm.deal(address(hook), amount);

        uint256 ownerBefore = owner.balance;
        hook.withdrawToken(c0, amount);
        uint256 ownerAfter = owner.balance;

        assertEq(ownerAfter - ownerBefore, amount, "owner should receive native");
        assertEq(address(hook).balance, 0, "hook should have 0 native balance");
    }

    function test_withdrawToken_native_partialAmount() public {
        uint256 total = 10e18;
        uint256 withdrawAmt = 3e18;
        vm.deal(address(hook), total);

        hook.withdrawToken(c0, withdrawAmt);

        assertEq(address(hook).balance, total - withdrawAmt);
    }

    function test_withdrawToken_native_RevertWhen_notOwner() public {
        vm.deal(address(hook), 5e18);

        address notOwner = address(0xdead);
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner));
        hook.withdrawToken(c0, 5e18);
    }
}
