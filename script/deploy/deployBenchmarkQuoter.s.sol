pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {BenchmarkQuoter} from "../../src/BenchmarkQuoter.sol";

contract DeployBenchmarkQuoter is Script {
    uint256 public deployerPrivateKey = vm.envUint("PRIVATE_KEY_HYFIHOOK_DEPLOYER");
    address public quoterV2 = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;
    address public v4Quoter = 0xb3d5c3Dfc3a7aEbFF71895A7191796BFFc2c81b9;

    function run() public {
        console2.log("=== BenchmarkQuoter Deployment ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("QuoterV2:", quoterV2);
        console2.log("V4Quoter:", v4Quoter);

        vm.startBroadcast(deployerPrivateKey);
        BenchmarkQuoter bq = new BenchmarkQuoter(quoterV2, v4Quoter);
        vm.stopBroadcast();

        console2.log("BenchmarkQuoter deployed at:", address(bq));
    }
}
