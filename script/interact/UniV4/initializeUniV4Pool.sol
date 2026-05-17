pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Utils} from "../../../test/Utils.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";


contract InitializeUniV4Pool is Script, Utils {

    using StateLibrary for IPoolManager;

    uint public senderPrivateKey = vm.envUint("PRIVATE_KEY_HYFIHOOK_DEPLOYER");
    address public sender = vm.addr(senderPrivateKey);

    IPoolManager public pm = IPoolManager(AddressConstants.getPoolManagerAddress(block.chainid));
    // IERC20Metadata public t1 = IERC20Metadata(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);         // MATIC USDC
    IERC20Metadata public t1 = IERC20Metadata(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);            // Base USDC

    function run() public {
        vm.startBroadcast(senderPrivateKey);

        PoolKey memory poolKey = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(address(t1)),
            fee: 0,
            tickSpacing: 1,
            hooks: IHooks(0x2948AC0d34895c5449D728B6569c8Fc92B9C4888)
        });

        pm.initialize(poolKey, getSqrtPriceX96FromPrice(1 ether, false, 18, 18));

        (uint160 sqrtPriceX96, int24 tick, , ) = pm.getSlot0(poolKey.toId());
        console2.log("sqrtPriceX96:", sqrtPriceX96);
        console2.log("tick:", tick);
        console2.log("Done!");
    }
}
