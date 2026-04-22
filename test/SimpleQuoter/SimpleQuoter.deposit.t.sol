// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SimpleQuoterDepositTest is HyFiHookSharedSetup {
    using CurrencyLibrary for Currency;

    function setUp() public {
        sharedSetup();
    }

    function test_deposit_native_mintsClaimsToQuoter() public {
        uint256 before = pm.balanceOf(address(quoter), native.toId());
        vm.deal(mm1, 10 ether);
        vm.prank(mm1);
        quoter.deposit{value: 5 ether}(native, 5 ether);
        assertEq(pm.balanceOf(address(quoter), native.toId()) - before, 5 ether, "native claims minted");
    }

    function test_deposit_erc20_mintsClaimsToQuoter() public {
        uint256 before = pm.balanceOf(address(quoter), usdc.toId());
        deal(USDC_ADDR, mm1, 10e6);
        vm.startPrank(mm1);
        IERC20(USDC_ADDR).approve(address(quoter), 10e6);
        quoter.deposit(usdc, 10e6);
        vm.stopPrank();
        assertEq(pm.balanceOf(address(quoter), usdc.toId()) - before, 10e6, "usdc claims minted");
    }

    function test_deposit_RevertWhen_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.deal(nonOwner, 1 ether);
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        quoter.deposit{value: 1 ether}(native, 1 ether);
    }

    function test_deposit_RevertWhen_nativeMsgValueMismatch() public {
        vm.deal(mm1, 10 ether);
        vm.prank(mm1);
        vm.expectRevert(SimpleQuoter.BadMsgValue.selector);
        quoter.deposit{value: 1 ether}(native, 2 ether);
    }

    function test_deposit_RevertWhen_erc20MsgValueNonZero() public {
        deal(USDC_ADDR, mm1, 10e6);
        vm.deal(mm1, 1 ether);
        vm.startPrank(mm1);
        IERC20(USDC_ADDR).approve(address(quoter), 10e6);
        vm.expectRevert(SimpleQuoter.BadMsgValue.selector);
        quoter.deposit{value: 1}(usdc, 10e6);
        vm.stopPrank();
    }
}
