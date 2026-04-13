pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {Utils} from "../../test/Utils.sol";

contract UpgradeHyFiHook is Script, Utils {
    uint256 public senderPrivateKey = vm.envUint("PRIVATE_KEY_HYFIHOOK_DEPLOYER");
    address public sender = vm.addr(senderPrivateKey);

    // ----------------------
    // Update these addresses before running the script
    address public proxy = 0x23bECbf4bA776B910E105A20060e47ae43020888;
    ProxyAdmin public proxyAdmin = ProxyAdmin(0x92036f614196558F53E02Ea0C5fe3d3501d8d7AC);
    bytes public upgradeCalldata = bytes("");
    // ----------------------

    function run() external {
        require(proxy != ADDR_ZERO, "Proxy not set");
        require(address(proxyAdmin) != ADDR_ZERO, "ProxyAdmin not set");

        HyFiHook hook = HyFiHook(payable(proxy));

        console2.log("=== HyFiHook Upgrade Script ===");
        console2.log("Owner:", hook.owner());
        console2.log("PoolManager:", address(hook.pm()));
        console2.log("Sender:", sender);
        console2.log("Proxy:", proxy);
        console2.log("ProxyAdmin:", address(proxyAdmin));
        console2.log("Upgrade calldata length:", upgradeCalldata.length);

        vm.startBroadcast(senderPrivateKey);

        HyFiHook newImpl = new HyFiHook();
        console2.log("New HyFiHook implementation deployed at:", address(newImpl));

        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(proxy), address(newImpl), upgradeCalldata);
        console2.log("Proxy upgraded via ProxyAdmin.upgradeAndCall");

        vm.stopBroadcast();

        console2.log("=== Post-upgrade Verification ===");
        console2.log("Owner:", hook.owner());
        console2.log("PoolManager:", address(hook.pm()));
        console2.log("Implementation now points to:", address(newImpl));
    }
}
