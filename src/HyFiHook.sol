// SPDX-License-Identifier: MIT
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
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {ILPQuoter} from "./interfaces/ILPQuoter.sol";


/// @title HyFiHook — Multi-LP Proprietor AMM Hook for Uniswap V4
/// @notice Whitelisted MMs register with their own Quoter contracts that define
///         fee logic and inventory management.  The hook stores centralised
///         price data (bid + spread) per pool that the owner updates off-chain.
///         On each swap the hook iterates registered quoters, passes in the
///         current price, picks the best effective price for the trader, and
///         fills against that MM's inventory.
contract HyFiHook is IHooks, IUnlockCallback, Initializable, OwnableUpgradeable, ReentrancyGuardTransient {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;

    uint8  internal constant MAX_LPS          = 10;
    uint   internal constant QUOTER_GAS_LIMIT = 100_000;
    uint   internal constant FEE_DENOM        = 1_000_000;  // 1 000 000 = 100 %

    IPoolManager public pm;
    uint public protocolFeePips;  // fee in FEE_DENOM pips (e.g. 1000 = 0.1%)

    // --- MM registry (per-pool) ----------------------------------------------
    struct MM {
        address   mm;
        ILPQuoter quoter;
    }

    mapping(PoolId => MM[])                          internal _poolMMs;
    mapping(PoolId => mapping(address => uint8))     internal _poolMMIndex; // 1-indexed
    mapping(address => bool)                         public   whitelisted;

    // --- Centralised price data (owner-updated) ------------------------------
    struct PriceData {
        uint112 bidPriceX96;
        uint112 spreadX96;
        uint32  lastUpdate;
    }

    mapping(PoolId => PriceData) internal _prices;

    // --- Protocol fee accumulator (owner's share) ----------------------------
    mapping(Currency => uint256) public protocolFees;

    // --- Errors --------------------------------------------------------------
    error OnlyPoolManager();
    error NoDirectLiquidity();
    error HookNotUsed();
    error NotWhitelisted();
    error AlreadyRegistered();
    error NotRegistered();
    error MaxLPsReached();
    error NoQuoteAvailable();
    error BadQuoteInput();
    error BadQuoteOutput();
    error FeeTooHigh();
    error PairNotRegistered();
    error LengthMismatch();
    error NoFeesToCollect();

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
    // Owner — whitelist management
    // -----------------------------------------------------------------------

    function addToWhitelist(address mm) external onlyOwner {
        whitelisted[mm] = true;
    }

    function removeFromWhitelist(address mm) external onlyOwner {
        whitelisted[mm] = false;
    }

    function setProtocolFee(uint newFeePips) external onlyOwner {
        if (newFeePips > FEE_DENOM) revert FeeTooHigh();
        protocolFeePips = newFeePips;
    }

    function collectProtocolFees(Currency currency) external onlyOwner {
        uint amount = protocolFees[currency];
        if (amount == 0) revert NoFeesToCollect();
        protocolFees[currency] = 0;
        pm.unlock(abi.encode(currency, amount, msg.sender));
    }

    // -----------------------------------------------------------------------
    // Owner — price updates
    // -----------------------------------------------------------------------

    function setPrices(
        PoolId[] calldata poolIds,
        uint112[] calldata bidPrices,
        uint112[] calldata spreads
    ) external onlyOwner {
        if (poolIds.length != bidPrices.length || poolIds.length != spreads.length)
            revert LengthMismatch();
        uint32 ts = uint32(block.timestamp);
        for (uint i; i < poolIds.length; ++i) {
            _prices[poolIds[i]] = PriceData(bidPrices[i], spreads[i], ts);
        }
    }

    function getPrices(PoolId[] calldata poolIds) external view returns (PriceData[] memory out) {
        out = new PriceData[](poolIds.length);
        for (uint i; i < poolIds.length; ++i) {
            out[i] = _prices[poolIds[i]];
        }
    }

    // -----------------------------------------------------------------------
    // MM — registration (per-pool)
    // -----------------------------------------------------------------------

    function registerPools(PoolId[] calldata poolIds, ILPQuoter[] calldata quoters) external {
        if (!whitelisted[msg.sender]) revert NotWhitelisted();
        if (poolIds.length != quoters.length) revert LengthMismatch();
        for (uint i; i < poolIds.length; ++i) {
            PoolId pid = poolIds[i];
            if (_poolMMIndex[pid][msg.sender] != 0) revert AlreadyRegistered();
            if (_poolMMs[pid].length >= MAX_LPS) revert MaxLPsReached();
            _poolMMs[pid].push(MM(msg.sender, quoters[i]));
            _poolMMIndex[pid][msg.sender] = uint8(_poolMMs[pid].length);
        }
    }

    function deregisterPools(PoolId[] calldata poolIds) external {
        for (uint i; i < poolIds.length; ++i) {
            _deregister(poolIds[i], msg.sender);
        }
    }

    function ownerDeregister(PoolId[] calldata poolIds, address mm) external onlyOwner {
        for (uint i; i < poolIds.length; ++i) {
            _deregister(poolIds[i], mm);
        }
    }

    function _deregister(PoolId poolId, address mm) internal {
        uint8 idx1 = _poolMMIndex[poolId][mm];
        if (idx1 == 0) revert NotRegistered();

        uint idx     = uint(idx1) - 1;
        uint lastIdx = _poolMMs[poolId].length - 1;

        if (idx != lastIdx) {
            MM storage last = _poolMMs[poolId][lastIdx];
            _poolMMs[poolId][idx] = last;
            _poolMMIndex[poolId][last.mm] = idx1;
        }
        _poolMMs[poolId].pop();
        delete _poolMMIndex[poolId][mm];
    }

    function updateQuoters(PoolId[] calldata poolIds, ILPQuoter[] calldata newQuoters) external {
        if (poolIds.length != newQuoters.length) revert LengthMismatch();
        for (uint i; i < poolIds.length; ++i) {
            uint8 idx1 = _poolMMIndex[poolIds[i]][msg.sender];
            if (idx1 == 0) revert NotRegistered();
            _poolMMs[poolIds[i]][uint(idx1) - 1].quoter = newQuoters[i];
        }
    }

    function getMMCount(PoolId poolId) external view returns (uint) {
        return _poolMMs[poolId].length;
    }

    function getMM(PoolId poolId, uint index) external view returns (address mm, address quoter) {
        MM storage m = _poolMMs[poolId][index];
        return (m.mm, address(m.quoter));
    }

    // -----------------------------------------------------------------------
    // PoolManager unlock callback — protocol-fee collection only.
    // MM inventory deposits / withdrawals are handled on each quoter contract
    // directly; the hook has no custody of MM funds.
    // -----------------------------------------------------------------------

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external override onlyPM returns (bytes memory) {
        (Currency currency, uint amount, address to) = abi.decode(data, (Currency, uint, address));
        // Burn hook's own protocol-fee 6909, release underlying to `to`.
        currency.settle(pm, address(this), amount, true);
        currency.take(pm, to, amount, false);
        return "";
    }

    receive() external payable {}

    // =======================================================================
    //  IHooks — beforeSwap  (iterate quoters, pick best, execute)
    // =======================================================================

    function beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) external override onlyPM nonReentrant returns (bytes4, BeforeSwapDelta, uint24) {
        int128 unspecDelta = _findAndExecuteBest(key, params);
        return (
            IHooks.beforeSwap.selector,
            toBeforeSwapDelta(int128(-params.amountSpecified), unspecDelta),
            0
        );
    }

    function _findAndExecuteBest(
        PoolKey calldata key,
        SwapParams calldata params
    ) internal returns (int128 unspecDelta) {
        bool exactIn = params.amountSpecified < 0;
        Currency inputCurrency  = params.zeroForOne ? key.currency0 : key.currency1;
        Currency outputCurrency = params.zeroForOne ? key.currency1 : key.currency0;
        PoolId poolId = key.toId();

        (uint bestInput, uint bestOutput, uint bestIdx) = _findBestQuote(key, poolId, params.zeroForOne, params.amountSpecified, outputCurrency);

        // Validate the winning quote matches PM delta conventions
        if (exactIn) {
            if (bestInput != uint(-params.amountSpecified)) revert BadQuoteInput();
        } else {
            if (bestOutput != uint(params.amountSpecified)) revert BadQuoteOutput();
        }

        // Winning MM's quoter contract (custodies the inventory)
        address quoter = address(_poolMMs[poolId][bestIdx].quoter);

        // Protocol fee: taken from the input side, retained as hook-owned 6909.
        uint feePips = protocolFeePips;
        uint protocolCut;
        if (feePips > 0) {
            protocolCut = bestInput * feePips / FEE_DENOM;
            protocolFees[inputCurrency] += protocolCut;
            inputCurrency.take(pm, address(this), protocolCut, true);
        }

        // Winning MM's share of the input → mint 6909 directly to its quoter.
        uint mmShare = bestInput - protocolCut;
        if (mmShare > 0) {
            inputCurrency.take(pm, quoter, mmShare, true);
        }

        // Burn output-side 6909 from the quoter (pre-authorised via setOperator).
        outputCurrency.settle(pm, quoter, bestOutput, true);

        unspecDelta = exactIn
            // forge-lint: disable-next-line(unsafe-typecast)
            ? -int128(uint128(bestOutput))
            // forge-lint: disable-next-line(unsafe-typecast)
            :  int128(uint128(bestInput));
    }

    /// @dev Pure scan — STATICCALL each quoter, track the best.
    ///      MMs whose quoter has insufficient output-side 6909 inventory are
    ///      skipped, so a stale/over-optimistic quote can never make a swap
    ///      revert on the settle step.
    function _findBestQuote(
        PoolKey calldata key,
        PoolId poolId,
        bool zeroForOne,
        int256 amountSpecified,
        Currency outputCurrency
    ) internal view returns (uint bestInput, uint bestOutput, uint bestIdx) {
        PriceData memory p = _prices[poolId];
        if (p.bidPriceX96 == 0) revert PairNotRegistered();

        bool exactIn = amountSpecified < 0;
        bestInput = type(uint256).max;

        MM[] storage mms = _poolMMs[poolId];
        uint len = mms.length;
        for (uint i; i < len; ++i) {
            try mms[i].quoter.quoteTrade{gas: QUOTER_GAS_LIMIT}(
                key, zeroForOne, amountSpecified,
                uint256(p.bidPriceX96), uint256(p.spreadX96), p.lastUpdate
            ) returns (uint256 amIn, uint256 amOut) {
                if (amOut == 0) continue;



                // TODO: remove this step to save gas


                // Skip MMs whose quoter cannot settle the output-side 6909 burn.
                if (pm.balanceOf(address(mms[i].quoter), outputCurrency.toId()) < amOut) continue;

                if (exactIn) {
                    if (amOut > bestOutput) {
                        bestOutput = amOut;
                        bestInput  = amIn;
                        bestIdx    = i;
                    }
                } else {
                    if (amIn < bestInput) {
                        bestInput  = amIn;
                        bestOutput = amOut;
                        bestIdx    = i;
                    }
                }
            } catch {
                continue;
            }
        }

        if (bestInput == type(uint256).max) revert NoQuoteAvailable();
    }

    // -----------------------------------------------------------------------
    // Owner — rescue tokens sent directly to the hook
    // -----------------------------------------------------------------------

    function withdrawToken(Currency currency, uint amount) external onlyOwner {
        currency.transfer(msg.sender, amount);
    }

    // =======================================================================
    //  Hook permissions & stubs
    // =======================================================================

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize:                 false,
            afterInitialize:                  false,
            beforeAddLiquidity:               true,
            afterAddLiquidity:                false,
            beforeRemoveLiquidity:            false,
            afterRemoveLiquidity:             false,
            beforeSwap:                       true,
            afterSwap:                        false,
            beforeDonate:                     false,
            afterDonate:                      false,
            beforeSwapReturnDelta:            true,
            afterSwapReturnDelta:             false,
            afterAddLiquidityReturnDelta:     false,
            afterRemoveLiquidityReturnDelta:  false
        });
    }

    function beforeAddLiquidity(
        address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata
    ) external view override onlyPM returns (bytes4) {
        revert NoDirectLiquidity();
    }

    function beforeInitialize(address, PoolKey calldata, uint160)
        external pure override returns (bytes4) { revert HookNotUsed(); }
    function afterInitialize(address, PoolKey calldata, uint160, int24)
        external pure override returns (bytes4) { revert HookNotUsed(); }
    function afterAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata)
        external pure override returns (bytes4, BalanceDelta) { revert HookNotUsed(); }
    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external pure override returns (bytes4) { revert HookNotUsed(); }
    function afterRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata)
        external pure override returns (bytes4, BalanceDelta) { revert HookNotUsed(); }
    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external pure override returns (bytes4, int128) { revert HookNotUsed(); }
    function beforeDonate(address, PoolKey calldata, uint, uint, bytes calldata)
        external pure override returns (bytes4) { revert HookNotUsed(); }
    function afterDonate(address, PoolKey calldata, uint, uint, bytes calldata)
        external pure override returns (bytes4) { revert HookNotUsed(); }

    uint[45] private __gap;
}
