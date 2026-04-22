pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SimpleQuoter} from "../../../src/SimpleQuoter.sol";
import {Utils} from "../../../test/Utils.sol";

contract WithdrawFrom6909 is Script, Utils {
    uint256 public deployerPrivateKey = vm.envUint("PRIVATE_KEY_HYFIHOOK_DEPLOYER");
    address public deployer = vm.addr(deployerPrivateKey);

    // MM's own SimpleQuoter (holds the 6909 inventory). Set to the deployed quoter address.
    SimpleQuoter public quoter = SimpleQuoter(payable(address(0)));
    // Currency public currency = Currency.wrap(ADDR_ZERO);
    // uint256 public amount = 2e18;
    Currency public currency = Currency.wrap(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);
    uint256 public amount = 2e6;

    function run() public {
        console2.log("=== Withdraw ===");
        console2.log("Quoter:", address(quoter));
        console2.log("Token:", Currency.unwrap(currency));
        console2.log("Amount: %e", amount);

        vm.startBroadcast(deployerPrivateKey);
        quoter.withdraw(currency, amount, deployer);
        vm.stopBroadcast();

        console2.log("Withdraw successful");
    }
}
