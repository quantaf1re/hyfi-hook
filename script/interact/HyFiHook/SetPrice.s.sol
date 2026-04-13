pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {HyFiHook} from "../../../src/HyFiHook.sol";
import {Utils} from "../../../test/Utils.sol";

contract SetPrice is Script, Utils {
    uint256 public deployerPrivateKey = vm.envUint("PRIVATE_KEY_HYFIHOOK_DEPLOYER");
    address public deployer = vm.addr(deployerPrivateKey);

    HyFiHook public hook = HyFiHook(payable(ADDR_ZERO)); // TODO: set hook address
    PoolId public poolId = PoolId.wrap(bytes32(0)); // TODO: set pool ID
    uint112 public bidPriceX96 = 0; // TODO: set bid price
    uint112 public spreadX96 = 0; // TODO: set spread

    function run() public {
        console2.log("=== SetPrice ===");
        console2.log("Hook:", address(hook));
        console2.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));
        console2.log("Bid Price X96: %e", bidPriceX96);
        console2.log("Spread X96: %e", spreadX96);

        vm.startBroadcast(deployerPrivateKey);
        hook.setPrice(poolId, bidPriceX96, spreadX96);
        vm.stopBroadcast();

        console2.log("Price set successfully");
    }
}
