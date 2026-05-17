pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {ILPQuoter} from "../../src/interfaces/ILPQuoter.sol";
import {Utils} from "../../test/Utils.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";

contract DeploySimpleQuoter is Script, Utils {
    using PoolIdLibrary for PoolKey;

    IPoolManager public pm = IPoolManager(AddressConstants.getPoolManagerAddress(block.chainid));
    HyFiHook public hook = HyFiHook(payable(0x2948AC0d34895c5449D728B6569c8Fc92B9C4888));

    // SimpleQuoter fee parameters
    uint256 public baseFee = 500;        // 0.05%
    uint256 public feePerSecond = 50;    // +0.005%/s

    // Pool to register the quoter against (matches initializeUniV4Pool.sol).
    // currency0 = native, currency1 = MATIC USDC, fee = 0, tickSpacing = 1.
    PoolKey public poolKey = PoolKey({
        currency0: CurrencyLibrary.ADDRESS_ZERO,
        // currency1: Currency.wrap(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359), // USDC on Polygon
        currency1: Currency.wrap(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913), // USDC on Base
        fee: 0,
        tickSpacing: 1,
        hooks: IHooks(address(hook))
    });

    uint256 public deployerPrivateKey = vm.envUint("PRIVATE_KEY_HYFIHOOK_DEPLOYER");
    address public deployer = vm.addr(deployerPrivateKey);
    address public owner = deployer;

    function run() public {
        PoolId poolId = poolKey.toId();

        console2.log("=== SimpleQuoter Deployment Script ===");
        console2.log("Deployer:", deployer);
        console2.log("Owner:", owner);
        console2.log("Chain ID:", block.chainid);
        console2.log("PoolManager:", address(pm));
        console2.log("HyFiHook:", address(hook));
        console2.log("Target Pool ID:", vm.toString(PoolId.unwrap(poolId)));

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy SimpleQuoter implementation
        console2.log("\n1. Deploying SimpleQuoter implementation...");
        SimpleQuoter quoterImpl = new SimpleQuoter();
        console2.log("SimpleQuoter implementation deployed at:", address(quoterImpl));

        // 2. Deploy proxy + initialize
        console2.log("\n2. Deploying SimpleQuoter proxy...");
        bytes memory quoterInitData = abi.encodeCall(
            SimpleQuoter.initialize,
            (pm, address(hook), owner, baseFee, feePerSecond)
        );
        vm.recordLogs();
        TransparentUpgradeableProxy quoterProxy = new TransparentUpgradeableProxy(address(quoterImpl), deployer, quoterInitData);
        SimpleQuoter quoter = SimpleQuoter(payable(address(quoterProxy)));
        console2.log("SimpleQuoter proxy deployed at:", address(quoterProxy));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        address quoterProxyAdminAddr;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == IERC1967.AdminChanged.selector) {
                (, quoterProxyAdminAddr) = abi.decode(logs[i].data, (address, address));
                break;
            }
        }
        require(quoterProxyAdminAddr != ADDR_ZERO, "Quoter AdminChanged event not found");
        console2.log("SimpleQuoter ProxyAdmin deployed at:", quoterProxyAdminAddr);

        // 3. Set the new quoter as the pool's default (owner-only on the hook).
        console2.log("\n3. Setting SimpleQuoter as default quoter for pool...");
        require(hook.owner() == deployer, "Deployer is not hook owner; cannot set default quoter");
        PoolId[] memory poolIds = new PoolId[](1);
        poolIds[0] = poolId;
        ILPQuoter[] memory quoters = new ILPQuoter[](1);
        quoters[0] = ILPQuoter(address(quoter));
        hook.assignDefaultQuoters(poolIds, quoters);

        vm.stopBroadcast();

        // 4. Verify
        _verify(quoter, poolId);

        // 5. Summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("SimpleQuoter Implementation:", address(quoterImpl));
        console2.log("SimpleQuoter Proxy:", address(quoterProxy));
        console2.log("SimpleQuoter ProxyAdmin:", quoterProxyAdminAddr);
        console2.log("HyFiHook:", address(hook));
        console2.log("Default-quoter Pool ID:", vm.toString(PoolId.unwrap(poolId)));

        console2.log("\nDeployment completed successfully!");
    }

    function _verify(SimpleQuoter quoter, PoolId poolId) internal view {
        console2.log("\n=== Deployment Verification ===");
        require(address(quoter.getPm()) == address(pm), "Quoter PoolManager not set correctly");
        require(quoter.getHook() == address(hook), "Quoter hook not set correctly");
        require(quoter.owner() == owner, "Quoter owner not set correctly");
        require(address(hook.getDefaultQuoter(poolId)) == address(quoter), "Default quoter not set for pool");
        console2.log("All checks passed");
    }
}
