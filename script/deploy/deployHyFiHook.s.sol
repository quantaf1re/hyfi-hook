pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {Utils} from "../../test/Utils.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";

contract DeployHyFiHook is Script, Utils {
    // BEFORE_ADD_LIQUIDITY | BEFORE_SWAP | BEFORE_SWAP_RETURNS_DELTA
    uint160 internal constant HOOK_FLAGS = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);

    // Foundry's deterministic CREATE2 deployer used during broadcast
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    uint256 public deployerPrivateKey = vm.envUint("PRIVATE_KEY_HYFIHOOK_DEPLOYER");
    address public deployer = vm.addr(deployerPrivateKey);
    address public owner = deployer;

    IPoolManager public pm = IPoolManager(AddressConstants.getPoolManagerAddress(block.chainid));

    function run() public {
        console2.log("=== HyFiHook Deployment Script ===");
        console2.log("Deployer:", deployer);
        console2.log("Owner:", owner);
        console2.log("Chain ID:", block.chainid);
        console2.log("PoolManager:", address(pm));

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy implementation
        console2.log("\n1. Deploying HyFiHook implementation...");
        HyFiHook impl = new HyFiHook();
        console2.log("Implementation deployed at:", address(impl));

        // 2. Mine CREATE2 salt for proxy address with correct hook-flag bits
        console2.log("\n2. Mining CREATE2 salt...");
        bytes memory initData = abi.encodeCall(HyFiHook.initialize, (address(pm), owner));
        bytes memory proxyInitcode = abi.encodePacked(type(TransparentUpgradeableProxy).creationCode, abi.encode(address(impl), deployer, initData));
        bytes32 salt = _mineSalt(proxyInitcode, HOOK_FLAGS, CREATE2_DEPLOYER);
        console2.log("Salt:", vm.toString(salt));

        // 3. Deploy proxy (constructor delegatecalls initialize)
        console2.log("\n3. Deploying TransparentUpgradeableProxy...");
        vm.recordLogs();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy{salt: salt}(address(impl), deployer, initData);
        console2.log("Proxy deployed at:", address(proxy));

        // Get ProxyAdmin address from AdminChanged event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address proxyAdminAddr;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == IERC1967.AdminChanged.selector) {
                (, proxyAdminAddr) = abi.decode(logs[i].data, (address, address));
                break;
            }
        }
        require(proxyAdminAddr != ADDR_ZERO, "AdminChanged event not found");
        console2.log("ProxyAdmin deployed at:", proxyAdminAddr);

        vm.stopBroadcast();

        // 4. Verify deployment
        console2.log("\n=== Deployment Verification ===");
        HyFiHook hook = HyFiHook(payable(address(proxy)));
        console2.log("Hook owner:", hook.owner());
        console2.log("Hook PoolManager:", address(hook.pm()));

        require(hook.owner() == owner, "Owner not set correctly");
        require(address(hook.pm()) == address(pm), "PoolManager not set correctly");
        require(uint160(address(proxy)) & Hooks.ALL_HOOK_MASK == HOOK_FLAGS, "Hook flag bits mismatch");
        console2.log("All checks passed");

        // 5. Output deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("HyFiHook Implementation:", address(impl));
        console2.log("HyFiHook Proxy (Hook):", address(proxy));
        console2.log("Owner:", owner);
        console2.log("PoolManager:", address(pm));
        console2.log("ProxyAdmin:", proxyAdminAddr);

        console2.log("\nDeployment completed successfully!");
    }
}
