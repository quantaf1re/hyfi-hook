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
import {IERC6909Claims} from "@uniswap/v4-core/src/interfaces/external/IERC6909Claims.sol";

import {ILPQuoter} from "./interfaces/ILPQuoter.sol";


/// @title HyFiHook — Single-Quoter-per-Trade AMM Hook for Uniswap V4
/// @notice Each pool has a default Quoter set by the owner. Traders may
///         override the quoter on a per-trade basis by passing
///         `abi.encode(address)` as the swap's hookData; if empty, the pool's
///         default quoter is used. The hook stores centralised price data
///         (bid + spread) per pool that the owner updates off-chain.
contract HyFiHook is IHooks, IUnlockCallback, Initializable, OwnableUpgradeable, ReentrancyGuardTransient {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;

    uint   internal constant FEE_DENOM        = 1_000_000;  // 1 000 000 = 100 %

    IPoolManager private _pm;
    uint private _protocolFeePips;  // fee in FEE_DENOM pips (e.g. 1000 = 0.1%)

    // === Default quoter per pool (owner-set) ===============================

    
    
    // TODO: change to a hash of sorted t0 and t1 since there can be many poolIds for the same pair technically
    
    
    
    mapping(PoolId => ILPQuoter) private _defaultQuoter;

    // === Centralised price data (oracle-timestamped) =======================
    struct PriceData {
        uint112 bidPriceX96;
        uint112 spreadX96;
        uint32  timestamp;
    }

    mapping(PoolId => PriceData) internal _prices;

    // === Errors ============================================================
    error OnlyPoolManager();
    error NoDirectLiquidity();
    error HookNotUsed();
    error NoQuoteAvailable();
    error BadQuoteInput();
    error BadQuoteOutput();
    error FeeTooHigh();
    error PairNotRegistered();
    error LengthMismatch();
    error NoFeesToCollect();
    error NoDefaultQuoter();
    error InvalidHookData();

    // === Events ============================================================
    event DefaultQuoterSet(PoolId indexed poolId, address indexed quoter);

    modifier onlyPM() {
        if (msg.sender != address(_pm)) revert OnlyPoolManager();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function getPm() external view returns (IPoolManager) { return _pm; }
    function getProtocolFeePips() external view returns (uint) { return _protocolFeePips; }
    function getDefaultQuoter(PoolId poolId) external view returns (ILPQuoter) { return _defaultQuoter[poolId]; }

    function initialize(address pm_, address owner_) external initializer {
        __Ownable_init(owner_);
        _pm = IPoolManager(pm_);
    }

    // =======================================================================
    // Owner — protocol fees
    // =======================================================================

    function updateProtocolFee(uint newFeePips) external onlyOwner {
        if (newFeePips > FEE_DENOM) revert FeeTooHigh();
        _protocolFeePips = newFeePips;
    }

    function withdrawProtocolFees(Currency currency) external onlyOwner {
        uint amount = IERC6909Claims(address(_pm)).balanceOf(address(this), currency.toId());
        if (amount == 0) revert NoFeesToCollect();
        _pm.unlock(abi.encode(currency, amount, msg.sender));
    }

    // =======================================================================
    // Owner — price updates
    // =======================================================================

    function updatePrices(
        PoolId[] calldata poolIds,
        PriceData[] calldata prices
    ) external onlyOwner {
        if (poolIds.length != prices.length) revert LengthMismatch();
        for (uint i; i < poolIds.length; ++i) {
            _prices[poolIds[i]] = prices[i];
        }
    }

    function readPrices(PoolId[] calldata poolIds) external view returns (PriceData[] memory out) {
        out = new PriceData[](poolIds.length);
        for (uint i; i < poolIds.length; ++i) {
            out[i] = _prices[poolIds[i]];
        }
    }

    // =======================================================================
    // Owner — default quoter management (per-pool)
    // =======================================================================

    function assignDefaultQuoters(PoolId[] calldata poolIds, ILPQuoter[] calldata quoters) external onlyOwner {
        if (poolIds.length != quoters.length) revert LengthMismatch();
        for (uint i; i < poolIds.length; ++i) {
            _defaultQuoter[poolIds[i]] = quoters[i];
            emit DefaultQuoterSet(poolIds[i], address(quoters[i]));
        }
    }

    // =======================================================================
    // PoolManager unlock callback — protocol-fee collection only.
    // =======================================================================

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external override onlyPM returns (bytes memory) {
        (Currency currency, uint amount, address to) = abi.decode(data, (Currency, uint, address));
        // Burn hook's own protocol-fee 6909, release underlying to `to`.
        currency.settle(_pm, address(this), amount, true);
        currency.take(_pm, to, amount, false);
        return "";
    }

    receive() external payable {}

    // =======================================================================
    //  IHooks — beforeSwap
    //
    //  hookData encoding:
    //    - empty      → use pool's default quoter
    //    - abi.encode(address quoter) → use the supplied quoter
    // =======================================================================

    function beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external override onlyPM nonReentrant returns (bytes4, BeforeSwapDelta, uint24) {
        ILPQuoter quoter = _resolveQuoter(key.toId(), hookData);
        int128 unspecDelta = _executeQuote(key, params, quoter);
        return (
            IHooks.beforeSwap.selector,
            toBeforeSwapDelta(int128(-params.amountSpecified), unspecDelta),
            0
        );
    }

    /// @dev Decode hookData → quoter address. Empty hookData = default quoter.
    function _resolveQuoter(PoolId poolId, bytes calldata hookData) internal view returns (ILPQuoter quoter) {
        if (hookData.length != 0) {
            if (hookData.length != 32) revert InvalidHookData();
            address q = abi.decode(hookData, (address));
            if (q == address(0)) revert InvalidHookData();
            quoter = ILPQuoter(q);
        } else {
            quoter = _defaultQuoter[poolId];
            if (address(quoter) == address(0)) revert NoDefaultQuoter();
        }
    }

    function _executeQuote(
        PoolKey calldata key,
        SwapParams calldata params,
        ILPQuoter quoter
    ) internal returns (int128 unspecDelta) {
        PoolId poolId = key.toId();
        Currency outputCurrency = params.zeroForOne ? key.currency1 : key.currency0;
        Currency inputCurrency  = params.zeroForOne ? key.currency0 : key.currency1;
        bool exactIn = params.amountSpecified < 0;

        PriceData memory p = _prices[poolId];
        if (p.bidPriceX96 == 0) revert PairNotRegistered();

        (uint amIn, uint amOut) = quoter.getQuote(
            key, params.zeroForOne, params.amountSpecified,
            uint256(p.bidPriceX96), uint256(p.spreadX96), p.timestamp
        );
        if (amOut == 0) revert NoQuoteAvailable();

        // Validate the quote matches PM delta conventions
        if (!exactIn) {
            if (amOut != uint(params.amountSpecified)) revert BadQuoteOutput();
        } else {
            if (amIn != uint(-params.amountSpecified)) revert BadQuoteInput();
        }

        // Protocol fee: taken from the input side, retained as hook-owned 6909.
        uint feePips = _protocolFeePips;
        uint protocolCut;
        if (feePips != 0) {
            protocolCut = amIn * feePips / FEE_DENOM;
            inputCurrency.take(_pm, address(this), protocolCut, true);
        }

        // Quoter's share of the input → mint 6909 directly to the quoter.
        uint quoterShare = amIn - protocolCut;
        if (quoterShare != 0) {
            inputCurrency.take(_pm, address(quoter), quoterShare, true);
        }

        // Burn output-side 6909 from the quoter (pre-authorised via setOperator).
        outputCurrency.settle(_pm, address(quoter), amOut, true);

        unspecDelta = exactIn
            // forge-lint: disable-next-line(unsafe-typecast)
            ? -int128(uint128(amOut))
            // forge-lint: disable-next-line(unsafe-typecast)
            :  int128(uint128(amIn));
    }

    // =======================================================================
    // Owner — rescue tokens sent directly to the hook
    // =======================================================================

    function rescueToken(Currency currency, uint amount) external onlyOwner {
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

    // =======================================================================
    // Junk
    // =======================================================================

    function junkA(address, uint) external pure returns (uint) {
        uint x;
        for (uint i = 0; i < 100; i++) {
            x = i * i;
            if (x % 10 != 0) {
                x *= 2;
            } else {
                x /= 3;
            }
        }
        return x;
    }

    function junkB() external pure returns (string memory) {
        string memory s = "This is some junk code to increase the bytecode size of the SimpleQuoter implementation contract.";
        for (uint i = 0; i < 10; i++) {
            s = string(abi.encodePacked(s, " More junk code."));
        }
        return s;
    }

    function junkC(uint n) external pure returns (uint) {
        uint result = 1;
        for (uint i = 1; i <= n; i++) {
            if (result > 1e18) {
                result /= 1e18;
            }
            result *= i;
        }
        return result;
    }

    function junkD(uint a, uint b) external pure returns (uint) {
        uint acc;
        for (uint i = 0; i < 64; i++) {
            uint x = (a ^ (b << (i % 32))) + i;
            if (x % 5 == 0) {
                acc += x >> 2;
            } else if (x % 7 == 0) {
                acc ^= x * 13;
            } else {
                acc -= x & 0xff;
            }
        }
        return acc;
    }

    function junkE(bytes32 seed) external pure returns (bytes32) {
        bytes32 h = seed;
        for (uint i = 0; i < 32; i++) {
            h = keccak256(abi.encodePacked(h, i));
            if (uint256(h) % 3 == 0) {
                h = bytes32(uint256(h) ^ uint256(seed));
            }
        }
        return h;
    }

    function junkF(uint[] memory xs) external pure returns (uint sum, uint product) {
        product = 1;
        for (uint i = 0; i < xs.length; i++) {
            if (i % 4 == 3) {
                sum ^= (product >> 1);
            }
            sum += xs[i];
            if (xs[i] != 0 && product < 1e30) {
                product *= xs[i];
            }
        }
    }

    function junkG() external pure returns (uint[] memory) {
        uint[] memory out = new uint[](16);
        out[1] = 1;
        out[0] = 1;
        for (uint i = 2; i < 16; i++) {
            out[i] = out[i - 1] + out[i - 2];
            if (out[i] % 2 != 0) {
                out[i] ^= i;
            } else {
                out[i] += i * i;
            }
        }
        return out;
    }

    uint[46] private __gap;
}
