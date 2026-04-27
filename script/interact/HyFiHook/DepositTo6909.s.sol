pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {SimpleQuoter} from "../../../src/SimpleQuoter.sol";
import {Utils} from "../../../test/Utils.sol";

contract DepositTo6909 is Script, Utils {
    uint256 public deployerPrivateKey = vm.envUint("PRIVATE_KEY_HYFIHOOK_DEPLOYER");
    address public deployer = vm.addr(deployerPrivateKey);

    // MM's own SimpleQuoter (holds the 6909 inventory). Set to the deployed quoter address.
    SimpleQuoter public quoter = SimpleQuoter(payable(0x722756f53bb4C42Ea3E53e4BbfA3A457cfa9aB27));
    // IERC20 public token = IERC20(ADDR_ZERO);
    // uint256 public amount = 72_000e18;
    IERC20 public token = IERC20(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);
    uint256 public amount = 6000e6;

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

        quoter.depositTo6909{value: address(token) == ADDR_ZERO ? amount : 0}(currency, amount);

        vm.stopBroadcast();

        console2.log("Deposit successful");
    }
}
