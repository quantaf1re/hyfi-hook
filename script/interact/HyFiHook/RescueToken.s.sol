pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {HyFiHook} from "../../../src/HyFiHook.sol";
import {Utils} from "../../../test/Utils.sol";

contract RescueToken is Script, Utils {
    using CurrencyLibrary for Currency;

    uint256 public deployerPrivateKey = vm.envUint("PRIVATE_KEY_HYFIHOOK_DEPLOYER");
    address public deployer = vm.addr(deployerPrivateKey);

    HyFiHook public hook = HyFiHook(payable(0x23bECbf4bA776B910E105A20060e47ae43020888));
    // Currency public currency = Currency.wrap(ADDR_ZERO);
    Currency public currency = Currency.wrap(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);

    function run() public {
        uint256 amount = currency.balanceOf(address(hook));

        console2.log("=== RescueToken ===");
        console2.log("Hook:", address(hook));
        console2.log("Token:", Currency.unwrap(currency));
        console2.log("Amount: %e", amount);

        vm.startBroadcast(deployerPrivateKey);
        hook.rescueToken(currency, amount);
        vm.stopBroadcast();

        console2.log("RescueToken successful");
    }
}
