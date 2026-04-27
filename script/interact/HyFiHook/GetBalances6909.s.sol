pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";
import {Utils} from "../../../test/Utils.sol";

contract GetBalances6909 is Script, Utils {
    address public quoter = 0x722756f53bb4C42Ea3E53e4BbfA3A457cfa9aB27;
    IPoolManager public pm = IPoolManager(AddressConstants.getPoolManagerAddress(block.chainid));

    // Default: native (address(0)) and USDC on Polygon
    address public token0 = address(0);
    address public token1 = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
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
