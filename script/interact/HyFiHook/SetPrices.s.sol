pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {HyFiHook} from "../../../src/HyFiHook.sol";
import {Utils} from "../../../test/Utils.sol";

contract SetPrices is Script, Utils {
    uint256 public deployerPrivateKey = vm.envUint("PRIVATE_KEY_HYFIHOOK_DEPLOYER");
    address public deployer = vm.addr(deployerPrivateKey);

    HyFiHook public hook = HyFiHook(payable(ADDR_ZERO)); // TODO: set hook address

    function run() public {
        PoolId[] memory poolIds = new PoolId[](2);
        poolIds[0] = PoolId.wrap(bytes32(0)); // TODO: set pool ID
        poolIds[1] = PoolId.wrap(bytes32(0)); // TODO: set pool ID

        uint112[] memory bidPrices = new uint112[](2);
        bidPrices[0] = 0; // TODO: set bid price
        bidPrices[1] = 0; // TODO: set bid price

        uint112[] memory spreads = new uint112[](2);
        spreads[0] = 0; // TODO: set spread
        spreads[1] = 0; // TODO: set spread

        console2.log("=== SetPrices ===");
        console2.log("Hook:", address(hook));
        console2.log("Pool count:", poolIds.length);

        vm.startBroadcast(deployerPrivateKey);
        hook.setPrices(poolIds, bidPrices, spreads);
        vm.stopBroadcast();

        console2.log("Prices set successfully");
    }
}
