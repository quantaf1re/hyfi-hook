pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";
import {Utils} from "../../../test/Utils.sol";

contract GetBalances6909 is Script, Utils {
    address public quoter = 0xBeE34963e519D8A24d35983219812173fc34BDF5;
    IPoolManager public pm = IPoolManager(AddressConstants.getPoolManagerAddress(block.chainid));

    // Default: native (address(0)) and USDC on Base
    address public token0 = address(0);
    address public token1 = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    string public nativeSymbol = "NATIVE";
    uint8 public constant NATIVE_DECIMALS = 18;

    function run() public view {
        uint256 bal0 = pm.balanceOf(quoter, uint256(uint160(token0)));
        uint256 bal1 = pm.balanceOf(quoter, uint256(uint160(token1)));

        (string memory sym0, uint8 dec0) = token0 == ADDR_ZERO
            ? (nativeSymbol, NATIVE_DECIMALS)
            : (IERC20Metadata(token0).symbol(), IERC20Metadata(token0).decimals());
        (string memory sym1, uint8 dec1) = token1 == ADDR_ZERO
            ? (nativeSymbol, NATIVE_DECIMALS)
            : (IERC20Metadata(token1).symbol(), IERC20Metadata(token1).decimals());

        console2.log("=== 6909 Balances ===");
        console2.log("Quoter:", quoter);
        console2.log("PoolManager:", address(pm));
        logTokenBal("Token0", sym0, bal0, dec0);
        logTokenBal("Token1", sym1, bal1, dec1);
    }
}
