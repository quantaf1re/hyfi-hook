pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {HyFiHook} from "../../../src/HyFiHook.sol";
import {Utils} from "../../../test/Utils.sol";

contract UpdatePrices is Script, Utils {
    uint256 public deployerPrivateKey = vm.envUint("PRIVATE_KEY_HYFIHOOK_DEPLOYER");
    address public deployer = vm.addr(deployerPrivateKey);

    HyFiHook public hook = HyFiHook(payable(ADDR_ZERO)); // TODO: set hook address

    function run() public {
        PoolId[] memory poolIds = new PoolId[](2);
        poolIds[0] = PoolId.wrap(bytes32(0)); // TODO: set pool ID
        poolIds[1] = PoolId.wrap(bytes32(0)); // TODO: set pool ID

        HyFiHook.PriceData[] memory prices = new HyFiHook.PriceData[](2);
        // TODO: set bid / spread / oracle timestamp for each pool
        prices[0] = HyFiHook.PriceData(0, 0, uint32(block.timestamp));
        prices[1] = HyFiHook.PriceData(0, 0, uint32(block.timestamp));

        console2.log("=== SetPrices ===");
        console2.log("Hook:", address(hook));
        console2.log("Pool count:", poolIds.length);

        vm.startBroadcast(deployerPrivateKey);
        hook.updatePrices(poolIds, prices);
        vm.stopBroadcast();

        console2.log("Prices set successfully");
    }
}
