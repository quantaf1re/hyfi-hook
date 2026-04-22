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
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {HyFiHook} from "../src/HyFiHook.sol";
import {SimpleQuoter} from "../src/SimpleQuoter.sol";
import {ILPQuoter} from "../src/interfaces/ILPQuoter.sol";
import {Utils} from "./Utils.sol";

interface IPermit2Approve {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

contract HyFiHookSharedSetup is Test, Utils {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // ---- Polygon mainnet addresses ----------------------------------------
    address internal constant POLYGON_PM       = 0x67366782805870060151383F4BbFF9daB53e5cD6;
    address internal constant USDC_ADDR        = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address internal constant UNIVERSAL_ROUTER = 0x1095692A6237d83C6a72F3F5eFEdb9A670C49223;
    address internal constant PERMIT2          = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // ---- constants -------------------------------------------------------
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    uint8 internal constant POL_DECIMALS  = 18;
    uint8 internal constant USDC_DECIMALS = 6;

    // Hook flags: BEFORE_ADD_LIQUIDITY | BEFORE_SWAP | BEFORE_SWAP_RETURNS_DELTA
    uint160 internal constant HOOK_FLAGS =
        uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);

    // $0.10 per POL in Q96: 0.1 USDC/POL = 0.1 * 10^6 / 10^18 * 2^96 = Q96 / 1e13
    uint112 internal constant BID_PRICE_X96 = uint112(Q96 / 1e13);
    // 1% spread in Q96
    uint112 internal constant SPREAD_X96 = uint112(Q96 / 1e15);

    // Default protocol fee: 0.01% (100 pips out of 1_000_000)
    uint256 internal constant DEFAULT_PROTOCOL_FEE_PIPS = 100;

    // Default SimpleQuoter fee parameters
    uint256 internal constant DEFAULT_BASE_FEE       = 500;  // 0.05%
    uint256 internal constant DEFAULT_FEE_PER_SECOND = 100;  // +0.01%/s

    // ---- state -----------------------------------------------------------
    IPoolManager public pm = IPoolManager(POLYGON_PM);
    Currency internal native;
    Currency internal usdc;
    HyFiHook     public hook;
    SimpleQuoter  public quoter;
    PoolKey       public poolKey;
    PoolId        public poolId;
    address       public owner;
    address       public mm1;

    // ---- setup -----------------------------------------------------------

    function sharedSetup() internal {
        owner = address(this);
        mm1   = makeAddr("mm1");

        // Native POL (address(0)) < any ERC-20 address
        native = CurrencyLibrary.ADDRESS_ZERO;
        usdc = Currency.wrap(USDC_ADDR);

        // Fund test contract
        vm.deal(address(this), 1_000_000 * 10 ** POL_DECIMALS);
        deal(USDC_ADDR, address(this), 1_000_000 * 10 ** USDC_DECIMALS);

        // Deploy hook implementation
        HyFiHook impl = new HyFiHook();

        // Mine CREATE2 salt so the proxy address has the correct hook-flag bits
        bytes memory initData = abi.encodeCall(HyFiHook.initialize, (address(pm), owner));
        bytes memory proxyInitcode = abi.encodePacked(type(TransparentUpgradeableProxy).creationCode, abi.encode(address(impl), owner, initData));
        bytes32 salt = _mineSalt(proxyInitcode, HOOK_FLAGS, address(this));

        // Deploy proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy{salt: salt}(address(impl), owner, initData);
        hook = HyFiHook(payable(address(proxy)));

        // Deploy SimpleQuoter for mm1 (custodies MM inventory; hook is pre-approved PM operator)
        quoter = new SimpleQuoter(pm, address(hook), mm1, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND);

        // Create pool
        poolKey = PoolKey({
            currency0: native,
            currency1: usdc,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 1,
            hooks: IHooks(address(hook))
        });
        poolId = poolKey.toId();

        // Initialize the pool in the PM
        pm.initialize(poolKey, SQRT_PRICE_1_1);

        // Whitelist mm1 and register it for the pool
        hook.addToWhitelist(mm1);

        PoolId[] memory pids = new PoolId[](1);
        pids[0] = poolId;
        ILPQuoter[] memory quoters = new ILPQuoter[](1);
        quoters[0] = ILPQuoter(address(quoter));

        vm.prank(mm1);
        hook.registerPools(pids, quoters);

        // Fund mm1 with tokens, then deposit into the quoter (the custody contract)
        vm.deal(mm1, 1_000_000 * 10 ** POL_DECIMALS);
        deal(USDC_ADDR, mm1, 1_000_000 * 10 ** USDC_DECIMALS);

        vm.startPrank(mm1);
        quoter.deposit{value: 1_000 * 10 ** POL_DECIMALS}(native, 1_000 * 10 ** POL_DECIMALS);
        IERC20(USDC_ADDR).approve(address(quoter), 1_000 * 10 ** USDC_DECIMALS);
        quoter.deposit(usdc, 1_000 * 10 ** USDC_DECIMALS);
        vm.stopPrank();

        // Set a default price
        PoolId[] memory priceIds = new PoolId[](1);
        priceIds[0] = poolId;
        uint112[] memory bids = new uint112[](1);
        bids[0] = BID_PRICE_X96;
        uint112[] memory spreads = new uint112[](1);
        spreads[0] = SPREAD_X96;
        hook.setPrices(priceIds, bids, spreads);

        // Set default protocol fee to 0.01%
        hook.setProtocolFee(DEFAULT_PROTOCOL_FEE_PIPS);

        // Approve Permit2 for USDC (enables Universal Router to pull USDC for swaps)
        IERC20(USDC_ADDR).approve(PERMIT2, type(uint256).max);
        IPermit2Approve(PERMIT2).approve(USDC_ADDR, UNIVERSAL_ROUTER, type(uint160).max, type(uint48).max);
    }

    receive() external payable {}
}
