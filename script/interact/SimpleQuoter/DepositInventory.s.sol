pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {SimpleQuoter} from "../../../src/SimpleQuoter.sol";
import {Utils} from "../../../test/Utils.sol";

contract DepositInventory is Script, Utils {
    uint256 public deployerPrivateKey = vm.envUint("PRIVATE_KEY_HYFIHOOK_DEPLOYER");
    address public deployer = vm.addr(deployerPrivateKey);

    // MM's own SimpleQuoter (holds the 6909 inventory). Set to the deployed quoter address.
    SimpleQuoter public quoter = SimpleQuoter(payable(0xBeE34963e519D8A24d35983219812173fc34BDF5));
    // IERC20 public token = IERC20(ADDR_ZERO);
    // uint256 public amount = 0.065e18;
    // IERC20 public token = IERC20(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359); // USDC on MATIC
    IERC20 public token = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913); // USDC on Base
    uint256 public amount = 100e6;

    function run() public {
        Currency currency = Currency.wrap(address(token));

        console2.log("=== Deposit ===");
        console2.log("Quoter:", address(quoter));
        console2.log("Token:", address(token));
        console2.log("Amount: %e", amount);

        vm.startBroadcast(deployerPrivateKey);

        if (address(token) != ADDR_ZERO) {
            if (token.allowance(deployer, address(quoter)) < amount) {
                token.approve(address(quoter), type(uint256).max);
            }
        }

        quoter.depositInventory{value: address(token) == ADDR_ZERO ? amount : 0}(currency, amount);

        vm.stopBroadcast();

        console2.log("Deposit successful");
    }
}
