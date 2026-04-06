// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "./HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract HyFiHookInitializeTest is HyFiHookSharedSetup {

    function setUp() public {
        // Fork provides the PoolManager. No router/token setup needed
        // since we test initialize() directly.
    }

    // ─── Happy path ──────────────────────────────────────────────────────

    function test_initialize_setsOwnerAndPoolManager() public {
        HyFiHook impl = new HyFiHook();
        address expectedOwner = makeAddr("hookOwner");
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(HyFiHook.initialize, (address(pm), expectedOwner))
        );
        HyFiHook h = HyFiHook(payable(address(proxy)));

        assertEq(h.owner(), expectedOwner, "owner should be set");
        assertEq(address(h.pm()), address(pm), "pm should be set");
    }

    // ─── Cannot initialize twice ─────────────────────────────────────────

    function test_initialize_RevertWhen_calledTwice() public {
        HyFiHook impl = new HyFiHook();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(HyFiHook.initialize, (address(pm), address(this)))
        );
        HyFiHook h = HyFiHook(payable(address(proxy)));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        h.initialize(address(pm), address(this));
    }

    // ─── Implementation contract cannot be initialized ───────────────────

    function test_initialize_RevertWhen_calledOnImplementation() public {
        HyFiHook impl = new HyFiHook();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(address(pm), address(this));
    }
}
