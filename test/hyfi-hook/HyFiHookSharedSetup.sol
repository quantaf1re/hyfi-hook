// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {TestUtils} from "../Utils.sol";

interface IPermit2Approve {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

contract HyFiHookSharedSetup is Test, TestUtils {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // ---- Polygon mainnet addresses ----------------------------------------
    address internal constant POLYGON_PM       = 0x67366782805870060151383F4BbFF9daB53e5cD6;
    address internal constant USDC_ADDR        = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address internal constant UNIVERSAL_ROUTER = 0x1095692A6237d83C6a72F3F5eFEdb9A670C49223;
    address internal constant PERMIT2          = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // ---- constants -------------------------------------------------------
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    // Token decimals
    uint8 internal constant POL_DECIMALS  = 18;
    uint8 internal constant USDC_DECIMALS = 6;

    // Hook flags: BEFORE_ADD_LIQUIDITY | BEFORE_SWAP | BEFORE_SWAP_RETURNS_DELTA
    uint160 internal constant HOOK_FLAGS =
        uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);

    // $0.10 per POL in Q96: 0.1 USDC/POL = 0.1 * 10^6 / 10^18 * 2^96 = Q96 / 1e13
    uint112 internal constant BID_PRICE_X96 = uint112(Q96 / 1e13);
    // 1% spread in Q96
    uint112 internal constant SPREAD_X96 = uint112(Q96 / 1e15);

    // ---- state -----------------------------------------------------------
    IPoolManager public pm = IPoolManager(POLYGON_PM);
    Currency internal c0;
    Currency internal c1;
    HyFiHook public hook;
    PoolKey  public poolKey;
    PoolId   public poolId;
    address  public owner;

    // ---- setup -----------------------------------------------------------

    function sharedSetup() internal {
        owner = address(this);

        // Native POL (address(0)) < any ERC-20 address
        c0 = CurrencyLibrary.ADDRESS_ZERO;
        c1 = Currency.wrap(USDC_ADDR);

        // Fund test contract
        vm.deal(address(this), 1_000_000 * 10 ** POL_DECIMALS);
        deal(USDC_ADDR, address(this), 1_000_000 * 10 ** USDC_DECIMALS);

        // Deploy hook implementation
        HyFiHook impl = new HyFiHook();

        // Mine CREATE2 salt so the proxy address has the correct hook-flag bits
        bytes memory initData = abi.encodeCall(HyFiHook.initialize, (address(pm), owner));
        bytes memory proxyInitcode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(address(impl), initData));
        bytes32 salt = _mineSalt(proxyInitcode, HOOK_FLAGS);

        // Deploy proxy (constructor delegates to impl.initialize)
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(address(impl), initData);
        hook = HyFiHook(payable(address(proxy)));

        // Create pool with dynamic fee and tickSpacing=1
        poolKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 1,
            hooks: IHooks(address(hook))
        });
        poolId = poolKey.toId();

        // Initialize the pool in the PM
        pm.initialize(poolKey, SQRT_PRICE_1_1);

        // Fund the hook with ERC6909 claims so it can pay out swaps
        hook.deposit{value: 1_000 * 10 ** POL_DECIMALS}(c0, 1_000 * 10 ** POL_DECIMALS);
        IERC20(USDC_ADDR).approve(address(hook), 1_000 * 10 ** USDC_DECIMALS);
        hook.deposit(c1, 1_000 * 10 ** USDC_DECIMALS);

        // Set a default price
        hook.setPrice(poolId, BID_PRICE_X96, SPREAD_X96);

        // Approve Permit2 for USDC (enables Universal Router to pull USDC for swaps)
        IERC20(USDC_ADDR).approve(PERMIT2, type(uint256).max);
        IPermit2Approve(PERMIT2).approve(USDC_ADDR, UNIVERSAL_ROUTER, type(uint160).max, type(uint48).max);
    }

    // ---- CREATE2 salt mining ---------------------------------------------

    function _mineSalt(bytes memory initcode, uint160 flags) internal view returns (bytes32 salt) {
        bytes32 initcodeHash = keccak256(initcode);
        address deployer = address(this);
        uint256 i;
        while (true) {
            salt = bytes32(i);
            address predicted = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initcodeHash))))
            );
            if (uint160(predicted) & Hooks.ALL_HOOK_MASK == flags) return salt;
            ++i;
        }
    }

    receive() external payable {}
}
