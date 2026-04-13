pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Utils} from "../../../test/Utils.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

contract SwapViaUniversalRouter is Script, Utils {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    uint256 public senderPrivateKey = vm.envUint("PRIVATE_KEY_HYFIHOOK_DEPLOYER");
    address public sender = vm.addr(senderPrivateKey);

    IPoolManager public pm = IPoolManager(AddressConstants.getPoolManagerAddress(block.chainid));
    IUniversalRouter public universalRouter;
    IAllowanceTransfer public permit2 = IAllowanceTransfer(AddressConstants.getPermit2Address());

    // ----------- Pool configuration -----------
    Currency public currency0 = CurrencyLibrary.ADDRESS_ZERO; // Native chain token
    IERC20Metadata public token1 = IERC20Metadata(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359); // USDC on Polygon
    Currency public currency1 = Currency.wrap(address(token1));
    PoolKey public poolKey = PoolKey({
        currency0: currency0,
        currency1: currency1,
        fee: 0,
        tickSpacing: 1,
        hooks: IHooks(0x23bECbf4bA776B910E105A20060e47ae43020888)
    });

    // Swap config
    bool public swapZeroForOne = true;
    // bool public swapZeroForOne = false;
    uint256 public amountIn = 100e18;
    // uint256 public amountIn = 10e6;
    uint256 public slippageBps = 100; // 0.30% buffer
    uint256 public constant BPS_DENOM = 10_000;
    uint256 public constant DEADLINE_BUFFER = 5 minutes;
    string public nativeSymbol = "MATIC";
    uint8 public constant NATIVE_DECIMALS = 18;
    bytes1 internal constant V4_SWAP_COMMAND = bytes1(uint8(0x10));

    function run() external {
        address urAddr = 0x1095692A6237d83C6a72F3F5eFEdb9A670C49223;
        require(urAddr != ADDR_ZERO, "set UNIVERSAL_ROUTER_ADDRESS");
        universalRouter = IUniversalRouter(urAddr);
        require(address(pm) != ADDR_ZERO, "pm not deployed on this chain");

        vm.startBroadcast(senderPrivateKey);

        (uint160 sqrtPriceX96, int24 tick, , uint24 lpFee) = pm.getSlot0(poolKey.toId());
        require(sqrtPriceX96 != 0, "pool not initialized");
        uint256 priceT0ToT1 = getPriceFromSqrtPriceX96(sqrtPriceX96, false, 18, token1.decimals());
        uint256 priceT1ToT0 = getPriceFromSqrtPriceX96(sqrtPriceX96, true, 18, token1.decimals());
        _logPoolState(sqrtPriceX96, tick, lpFee, priceT0ToT1);

        Currency inputCurrency = swapZeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = swapZeroForOne ? poolKey.currency1 : poolKey.currency0;
        bool inputIsNative = inputCurrency.isAddressZero();
        uint256 minAmountOut = _computeMinAmountOut(priceT0ToT1, priceT1ToT0);
        console2.log("Min amount out (buffered): %e", minAmountOut);

        _prepareInput(inputCurrency);
        uint256 balInBefore = inputCurrency.balanceOf(sender);
        uint256 balOutBefore = outputCurrency.balanceOf(sender);

        uint256 swapAmount = amountIn;
        if (!inputIsNative) {
            if (swapAmount == 0 || swapAmount > balInBefore) {
                swapAmount = balInBefore;
            }
        } else {
            require(swapAmount > 0, "amountIn required");
        }
        require(swapAmount > 0, "no input to swap");

        _logBalances("before", inputCurrency, outputCurrency);

        require(swapAmount <= type(uint128).max, "amountIn too large");
        require(minAmountOut <= type(uint128).max, "minOut too large");

        console2.log("Time now: ", block.timestamp);

        uint256 valueToSend = inputIsNative ? swapAmount : 0;
        {
            bytes memory actions = abi.encodePacked(
                bytes1(uint8(Actions.SWAP_EXACT_IN_SINGLE)),
                bytes1(uint8(Actions.SETTLE_ALL)),
                bytes1(uint8(Actions.TAKE_ALL))
            );

            bytes[] memory params = new bytes[](3);
            params[0] = abi.encode(
                IV4Router.ExactInputSingleParams({
                    poolKey: poolKey,
                    zeroForOne: swapZeroForOne,
                    amountIn: uint128(swapAmount),
                    amountOutMinimum: uint128(minAmountOut),
                    minHopPriceX36: 0,
                    hookData: bytes("")
                })
            );
            params[1] = abi.encode(inputCurrency, type(uint256).max);
            params[2] = abi.encode(outputCurrency, uint256(0));

            bytes[] memory inputs = new bytes[](1);
            inputs[0] = abi.encode(actions, params);
            bytes memory commands = abi.encodePacked(V4_SWAP_COMMAND);
            universalRouter.execute{value: valueToSend}(commands, inputs, block.timestamp + DEADLINE_BUFFER);
        }

        console2.log("=== Swap submitted via Universal Router ===");
        uint256 balInAfter = inputCurrency.balanceOf(sender);
        uint256 balOutAfter = outputCurrency.balanceOf(sender);
        _logBalances("after", inputCurrency, outputCurrency);

        {
            uint256 spent = inputIsNative ? valueToSend : (balInBefore > balInAfter ? balInBefore - balInAfter : 0);
            uint256 received = balOutAfter > balOutBefore ? balOutAfter - balOutBefore : 0;
            _logNominal("Actual input used", inputCurrency, spent);
            _logNominal("Output received", outputCurrency, received);
        }

        vm.stopBroadcast();
    }

    function _computeMinAmountOut(uint256 priceT0ToT1, uint256 priceT1ToT0) internal view returns (uint256) {
        uint256 expectedOut;
        if (swapZeroForOne) {
            expectedOut = convAmToOther(amountIn, priceT0ToT1, 18, token1.decimals());
        } else {
            expectedOut = convAmToOther(amountIn, priceT1ToT0, token1.decimals(), 18);
        }

        if (expectedOut == 0) {
            return 0;
        }

        uint256 buffer = Math.mulDiv(expectedOut, slippageBps, BPS_DENOM);
        return expectedOut > buffer ? expectedOut - buffer : 0;
    }

    function _prepareInput(Currency inputCurrency) internal {
        if (inputCurrency.isAddressZero()) {
            console2.log("Using native currency for input; sending value with transaction");
            return;
        }

        IERC20Metadata tokenIn = IERC20Metadata(Currency.unwrap(inputCurrency));
        address permit2Address = address(permit2);

        uint256 allowance = tokenIn.allowance(sender, permit2Address);
        if (allowance < amountIn) {
            console2.log("Approving Permit2 to pull input token allowance");
            tokenIn.approve(permit2Address, type(uint256).max);
        }

        (uint160 permitAllowance, uint48 expiration,) = permit2.allowance(sender, address(tokenIn), address(universalRouter));
        if (permitAllowance < amountIn || expiration < block.timestamp) {
            console2.log("Setting Permit2 allowance for the Universal Router");
            permit2.approve(address(tokenIn), address(universalRouter), type(uint160).max, type(uint48).max);
        }
    }

    function _logPoolState(uint160 sqrtPriceX96, int24 tick, uint24 lpFee, uint256 price) internal pure {
        console2.log("=== Pool State ===");
        console2.log("sqrtPriceX96:", sqrtPriceX96);
        console2.log("tick:", tick);
        console2.log("lpFee (in bps*1e2):", lpFee);
        console2.log("price: %e", price);
    }

    function _logBalances(string memory prefix, Currency inputCurrency, Currency outputCurrency) internal view {
        uint256 balIn = inputCurrency.balanceOf(sender);
        uint256 balOut = outputCurrency.balanceOf(sender);
        (string memory inSymbol, uint8 inDecimals) = _currencyMetadata(inputCurrency);
        (string memory outSymbol, uint8 outDecimals) = _currencyMetadata(outputCurrency);
        console2.log(string.concat("=== Balances ", prefix, " ==="));
        logTokenBal("Input token balance", inSymbol, balIn, inDecimals);
        logTokenBal("Output token balance", outSymbol, balOut, outDecimals);
    }

    function _logNominal(string memory label, Currency currency, uint256 amount) internal view {
        (string memory symbol, uint8 decimals) = _currencyMetadata(currency);
        console2.log(string.concat(label, ": ", formatNumToStrDecimal(amount, decimals), " ", symbol));
    }

    function _currencyMetadata(Currency currency) internal view returns (string memory symbol, uint8 decimals) {
        if (currency.isAddressZero()) {
            return (nativeSymbol, NATIVE_DECIMALS);
        }

        IERC20Metadata meta = IERC20Metadata(Currency.unwrap(currency));
        return (meta.symbol(), meta.decimals());
    }

    receive() external payable {}
}
