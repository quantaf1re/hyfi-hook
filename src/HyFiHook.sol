pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";


/// @title HyFiHook — Proprietor AMM Hook for Uniswap V4
/// @notice Single-owner hook that fully overrides UniV4 pricing with owner-set bid/ask
///         prices that mirror a centralised exchange orderbook.  The owner holds token
///         inventory as ERC6909 claims inside the PoolManager, sets bid price + spread
///         per pair, and profits from the spread difference between DEX fees received
///         and CEX fees paid when hedging.
///
/// @dev Pricing model (orderbook pass-through):
///        The owner provides `bidPriceX96` and `spreadX96` per pool, both in Q96
///        (token1 per token0, scaled by 2^96).  The effective prices are:
///          bid = bidPriceX96                     (trader sells token0, buys token1)
///          ask = bidPriceX96 + spreadX96         (trader buys token0, sells token1)
///        E.g. if CEX best bid for ETH-USDC is $1 999.99 and best ask is $2 000.01:
///          bidPriceX96 = 1999.99 * 2^96
///          spreadX96   = 0.02    * 2^96
///        On top of the bid/ask spread a staleness fee is added (see below).
///
///        "token0" and "token1" follow Uniswap ordering (lower address first).  The
///        bidPriceX96 is always expressed as token1-per-token0 scaled by 2^96.  If the
///        CEX pair has the opposite ordering, the off-chain caller must invert the
///        bid/ask before calling setPrice / setPrices:
///          bidPriceX96 = 2^192 / cexAskPriceX96   (CEX ask inverts to DEX bid)
///          askPriceX96 = 2^192 / cexBidPriceX96   (CEX bid inverts to DEX ask)
///          spreadX96   = askPriceX96 - bidPriceX96
///
/// @dev Storage layout — 1 slot (256 bits) per pool (`_pairState[PoolId]`):
///        uint112 bidPriceX96  — bid price: token1 per token0 * 2^96
///                              (112 bits; 2^112 ≈ 5.2e33 covers all practical ratios)
///        uint112 spreadX96    — full bid-ask spread in the same Q96 units
///                              (ask = bid + spread)
///        uint32  lastUpdate   — block.timestamp (good until 2106)
///        Total: 112 + 112 + 32 = 256 bits = 1 storage slot
///
/// @dev Fee schedule (units: 1 = 0.0001 %):
///        base fee       = 500   (0.05 %) — charged when trade is in the same block
///        per-second     = +100  (0.01 %) — added per second since last price update
///        cap            = 1 000 000 (100 %) — absolute maximum
///        Fee denominator = 1 000 000   (so fee=1 000 000 → 100 %)
///
/// @dev Hook flags required on the **proxy** address (lowest 14 bits):
///        BEFORE_ADD_LIQUIDITY      (1 << 11)
///        BEFORE_SWAP               (1 << 7)
///        BEFORE_SWAP_RETURNS_DELTA (1 << 3)
///
/// @dev Pool initialisation: use fee = 0x800000 (DYNAMIC_FEE_FLAG), any valid
///      tickSpacing (e.g. 1), and any sqrtPriceX96 (unused — pricing is fully
///      overridden by this hook).
contract HyFiHook is IHooks, IUnlockCallback, Initializable, OwnableUpgradeable, ReentrancyGuardTransient {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;

    uint internal constant BASE_FEE       = 500;          // 0.05 %
    uint internal constant FEE_PER_SECOND = 100;          // +0.01 % per second
    uint internal constant MAX_FEE        = 1_000_000;    // 100 % cap
    uint internal constant FEE_DENOM      = 1_000_000;
    uint internal constant Q96            = 1 << 96;

    IPoolManager public pm;
    mapping(PoolId => PairState) internal _pairState;

    struct PairState {
        uint112 bidPriceX96;   // bid price: token1 per token0, scaled by 2^96
        uint112 spreadX96;     // full bid-ask spread in Q96 (ask = bid + spread)
        uint32  lastUpdate;    // block.timestamp of last price update
    }

    error OnlyPoolManager();
    error PairNotRegistered();
    error NoDirectLiquidity();
    error ZeroOutput();
    error HookNotUsed();
    error LengthMismatch();


    modifier onlyPM() {
        if (msg.sender != address(pm)) revert OnlyPoolManager();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _pm, address _owner) external initializer {
        __Ownable_init(_owner);
        pm = IPoolManager(_pm);
    }

    // -----------------------------------------------------------------------
    // Owner — price updates  (gas-critical path)
    // -----------------------------------------------------------------------

    /// @notice Set price for one pair.  Costs 1 SSTORE + base tx.
    /// @param poolId        PoolId of the pair (keccak256 of the PoolKey).
    /// @param bidPriceX96   Bid price: token1-per-token0 scaled by 2^96 (112-bit max).
    ///                      This is the price at which the hook buys token0 (trader sells).
    ///                      NOTE: if the CEX pair has the inverse ordering (e.g. CEX quotes
    ///                      token0-per-token1), the off-chain caller must invert:
    ///                      `bidPriceX96 = 2^192 / cexAskPriceX96`.
    /// @param spreadX96     Full bid-ask spread in the same Q96 units.  ask = bid + spread.
    ///                      E.g. if bid = 0.09999 and ask = 0.10001 (in token1/token0),
    ///                      spreadX96 = 0.00002 * 2^96.
    function setPrice(PoolId poolId, uint112 bidPriceX96, uint112 spreadX96) external onlyOwner {
        _pairState[poolId] = PairState(bidPriceX96, spreadX96, uint32(block.timestamp));
    }

    /// @notice Batch-set prices.  N SSTOREs, one timestamp read.
    // Could revert if empty arrays but it's extra gas to check and empty arrays don't do anything anyway
    function setPrices(
        PoolId[] calldata poolIds,
        uint112[] calldata bidPrices,
        uint112[] calldata spreads
    ) external onlyOwner {
        if (poolIds.length != bidPrices.length || poolIds.length != spreads.length) {
            revert LengthMismatch();
        }
        uint32 ts = uint32(block.timestamp);
        for (uint i; i < poolIds.length; ++i) {
            _pairState[poolIds[i]] = PairState(bidPrices[i], spreads[i], ts);
        }
    }

    // =======================================================================
    //  IHooks — beforeSwap  (core pricing logic)
    // =======================================================================

    function beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) external override onlyPM nonReentrant returns (bytes4, BeforeSwapDelta, uint24) {
        PairState memory p = _pairState[key.toId()];
        if (p.bidPriceX96 == 0) revert PairNotRegistered();

        int128 unspecDelta = _executeSwap(key, params, p);

        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(int128(-params.amountSpecified), unspecDelta), 0);
    }

    /// @dev Compute swap, derive bid/ask from state, move tokens.  Kept as a
    ///      separate internal function to avoid stack-too-deep in beforeSwap.
    function _executeSwap(
        PoolKey calldata key,
        SwapParams calldata params,
        PairState memory p
    ) internal returns (int128 unspecDelta) {
        // Effective price: bid when selling token0 (zeroForOne=true),
        // ask when buying token0 (zeroForOne=false).
        // priceX96 is token1-per-token0.
        //   Selling token0 (zeroForOne=true):  trader receives bid (no extra math)
        //   Buying  token0 (zeroForOne=false): trader pays     ask = bid + spread
        uint effectivePriceX96 = params.zeroForOne ? uint(p.bidPriceX96) : uint(p.bidPriceX96) + uint(p.spreadX96);

        uint amInput;
        uint amOutput;
        (amInput, amOutput, unspecDelta) = _computeSwap(params, effectivePriceX96, _fee(p.lastUpdate));

        // input  = what the swapper sends  → mint claims (keep in PM)
        // output = what the swapper gets   → burn claims (pay from PM balance)
        (Currency input, Currency output) = params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);
        input.take(pm, address(this), amInput, true);
        output.settle(pm, address(this), amOutput, true);
    }

    /// @dev Swap math — all rounding favours the hook (more input, less output).
    /// @param params       Swap parameters from the PoolManager.
    /// @param priceX96     Effective bid or ask price (token1/token0 * 2^96).
    /// @param fee          Fee in FEE_DENOM units (1 000 000 = 100 %).
    function _computeSwap(
        SwapParams calldata params,
        uint priceX96,
        uint fee
    ) internal pure returns (uint inputAmount, uint outputAmount, int128 unspecifiedDelta) {
        if (params.amountSpecified < 0) {
            // ---- exact input ------------------------------------------------
            inputAmount = uint(-params.amountSpecified);

            // Apply fee: inputAfterFee = input * (DENOM - fee) / DENOM  (round DOWN → less for trader)
            uint inputAfterFee = inputAmount * (FEE_DENOM - fee) / FEE_DENOM;

            // Convert: round DOWN output (favours hook)
            outputAmount = params.zeroForOne
                ? FullMath.mulDiv(inputAfterFee, priceX96, Q96)        // selling token0 → get token1
                : FullMath.mulDiv(inputAfterFee, Q96, priceX96);       // selling token1 → get token0

            if (outputAmount == 0) revert ZeroOutput();
            // forge-lint: disable-next-line(unsafe-typecast)
            unspecifiedDelta = -int128(uint128(outputAmount));          // negative = PM pays trader
        } else {
            // ---- exact output -----------------------------------------------
            outputAmount = uint(params.amountSpecified);

            // Inverse conversion: round UP input (favours hook)
            uint inputBeforeFee = params.zeroForOne
                ? FullMath.mulDivRoundingUp(outputAmount, Q96, priceX96)
                : FullMath.mulDivRoundingUp(outputAmount, priceX96, Q96);

            // Gross-up for fee: input = inputBeforeFee * DENOM / (DENOM - fee)  (round UP)
            inputAmount = FullMath.mulDivRoundingUp(inputBeforeFee, FEE_DENOM, FEE_DENOM - fee);

            // forge-lint: disable-next-line(unsafe-typecast)
            unspecifiedDelta = int128(uint128(inputAmount));            // positive = PM takes from trader
        }
    }

    // -----------------------------------------------------------------------
    // Owner — deposit / withdraw inventory  (ERC6909 claims in PM)
    // -----------------------------------------------------------------------

    /// @notice Deposit ERC-20 (or native) into PM as ERC6909 claims for this hook.
    ///         For ERC-20: caller must approve this contract.  For native: send msg.value.
    function depositTo6909(Currency currency, uint amount) external payable onlyOwner {
        pm.unlock(abi.encode(true, currency, amount, msg.sender));
    }

    /// @notice Withdraw ERC6909 claims back to ERC-20 (or native) to the owner.
    function withdrawFrom6909(Currency currency, uint amount) external onlyOwner {
        pm.unlock(abi.encode(false, currency, amount, msg.sender));
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external override onlyPM returns (bytes memory) {
        (bool isDeposit, Currency currency, uint amount, address who) = abi.decode(data, (bool, Currency, uint, address));

        if (isDeposit) {
            // Pull ERC-20 from `who` (or use hook's native balance) into PM, mint claims to hook
            currency.settle(pm, who, amount, false);
            currency.take(pm, address(this), amount, true);
        } else {
            // Burn hook's claims, send ERC-20 (or native) to `who`
            currency.settle(pm, address(this), amount, true);
            currency.take(pm, who, amount, false);
        }
        return "";
    }

    /// @notice Accept native currency deposits.
    receive() external payable {}

    // -----------------------------------------------------------------------
    // Owner — rescue tokens sent directly to the hook (not ERC6909 claims)
    // -----------------------------------------------------------------------

    /// @notice Withdraw ERC-20 or native currency held by the hook contract itself.
    ///         Use this to rescue tokens mistakenly sent to the hook address
    ///         (not for ERC6909 claims — use `withdraw` for those).
    function withdrawToken(Currency currency, uint amount) external onlyOwner {
        currency.transfer(msg.sender, amount);
    }

    // -----------------------------------------------------------------------
    // View helpers
    // -----------------------------------------------------------------------

    function getPrice(PoolId poolId) external view returns (uint112 bidPriceX96, uint112 spreadX96, uint32 lastUpdate) {
        PairState storage p = _pairState[poolId];
        return (p.bidPriceX96, p.spreadX96, p.lastUpdate);
    }

    function getFee(PoolId poolId) external view returns (uint) {
        return _fee(_pairState[poolId].lastUpdate);
    }

    /// @dev Compute the dynamic fee based on staleness.
    ///      Fee units: 1 = 0.0001 %.  FEE_DENOM (1 000 000) = 100 %.
    function _fee(uint32 lastUpdate) internal view returns (uint fee) {
        uint elapsed = block.timestamp - uint(lastUpdate);
        uint f = BASE_FEE + elapsed * FEE_PER_SECOND;
        fee = f > MAX_FEE ? MAX_FEE : f;
    }

    /// @notice Declared permissions — use to derive the required proxy address.
    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize:                 false,
            afterInitialize:                  false,
            beforeAddLiquidity:               true,   // block external LPs
            afterAddLiquidity:                false,
            beforeRemoveLiquidity:            false,
            afterRemoveLiquidity:             false,
            beforeSwap:                       true,   // override pricing
            afterSwap:                        false,
            beforeDonate:                     false,
            afterDonate:                      false,
            beforeSwapReturnDelta:            true,   // return custom deltas
            afterSwapReturnDelta:             false,
            afterAddLiquidityReturnDelta:     false,
            afterRemoveLiquidityReturnDelta:  false
        });
    }

    // =======================================================================
    //  IHooks — block external liquidity
    // =======================================================================

    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external view override onlyPM returns (bytes4) {
        revert NoDirectLiquidity();
    }

    // =======================================================================
    //  IHooks — no-op stubs
    //  Flags for these hooks are NOT set, so the PoolManager should never call
    //  them.  If called unexpectedly, revert to fail fast.
    // =======================================================================

    function beforeInitialize(address, PoolKey calldata, uint160)
        external pure override returns (bytes4)
    {
        revert HookNotUsed();
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24)
        external pure override returns (bytes4)
    {
        revert HookNotUsed();
    }

    function afterAddLiquidity(
        address, PoolKey calldata, ModifyLiquidityParams calldata,
        BalanceDelta, BalanceDelta, bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert HookNotUsed();
    }

    function beforeRemoveLiquidity(
        address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata
    ) external pure override returns (bytes4) {
        revert HookNotUsed();
    }

    function afterRemoveLiquidity(
        address, PoolKey calldata, ModifyLiquidityParams calldata,
        BalanceDelta, BalanceDelta, bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert HookNotUsed();
    }

    function afterSwap(
        address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata
    ) external pure override returns (bytes4, int128) {
        revert HookNotUsed();
    }

    function beforeDonate(address, PoolKey calldata, uint, uint, bytes calldata)
        external pure override returns (bytes4)
    {
        revert HookNotUsed();
    }

    function afterDonate(address, PoolKey calldata, uint, uint, bytes calldata)
        external pure override returns (bytes4)
    {
        revert HookNotUsed();
    }

    uint[48] private __gap;
}
