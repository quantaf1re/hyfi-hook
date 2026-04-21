pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract HyFiHookAddToWhitelistTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    function test_addToWhitelist_setsTrue() public {
        address newMM = makeAddr("newMM");
        assertFalse(hook.whitelisted(newMM), "should start false");

        hook.addToWhitelist(newMM);
        assertTrue(hook.whitelisted(newMM), "should be true after add");
    }

    function test_addToWhitelist_idempotent() public {
        address newMM = makeAddr("newMM");
        hook.addToWhitelist(newMM);
        hook.addToWhitelist(newMM); // no revert
        assertTrue(hook.whitelisted(newMM));
    }

    function test_addToWhitelist_RevertWhen_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        hook.addToWhitelist(makeAddr("mm"));
    }
}
