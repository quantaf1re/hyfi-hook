pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract HyFiHookRemoveFromWhitelistTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    function test_removeFromWhitelist_setsFalse() public {
        address newMM = makeAddr("newMM");
        hook.addToWhitelist(newMM);
        assertTrue(hook.whitelisted(newMM));

        hook.removeFromWhitelist(newMM);
        assertFalse(hook.whitelisted(newMM), "should be false after remove");
    }

    function test_removeFromWhitelist_idempotent() public {
        address newMM = makeAddr("newMM");
        hook.removeFromWhitelist(newMM); // was already false, no revert
        assertFalse(hook.whitelisted(newMM));
    }

    function test_removeFromWhitelist_RevertWhen_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        hook.removeFromWhitelist(mm1);
    }
}
