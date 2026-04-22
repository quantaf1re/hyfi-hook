// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SimpleQuoterWithdrawTest is HyFiHookSharedSetup {
    using CurrencyLibrary for Currency;

    function setUp() public {
        sharedSetup();
    }

    function test_withdraw_native_burnsClaimsAndSendsETH() public {
        address recipient = makeAddr("recipient");
        uint256 claimsBefore = pm.balanceOf(address(quoter), native.toId());
        uint256 ethBefore = recipient.balance;

        vm.prank(mm1);
        quoter.withdraw(native, 100 ether, recipient);

        assertEq(claimsBefore - pm.balanceOf(address(quoter), native.toId()), 100 ether, "native claims burned");
        assertEq(recipient.balance - ethBefore, 100 ether, "recipient receives native");
    }

    function test_withdraw_erc20_burnsClaimsAndTransfers() public {
        address recipient = makeAddr("recipient");
        uint256 claimsBefore = pm.balanceOf(address(quoter), usdc.toId());
        uint256 tokBefore = IERC20(USDC_ADDR).balanceOf(recipient);

        vm.prank(mm1);
        quoter.withdraw(usdc, 100e6, recipient);

        assertEq(claimsBefore - pm.balanceOf(address(quoter), usdc.toId()), 100e6, "usdc claims burned");
        assertEq(IERC20(USDC_ADDR).balanceOf(recipient) - tokBefore, 100e6, "recipient receives usdc");
    }

    function test_withdraw_RevertWhen_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        quoter.withdraw(native, 1 ether, nonOwner);
    }

    function test_withdraw_RevertWhen_insufficientQuoterBalance() public {
        uint256 bal = pm.balanceOf(address(quoter), native.toId());
        vm.prank(mm1);
        vm.expectRevert();
        quoter.withdraw(native, bal + 1, mm1);
    }
}
