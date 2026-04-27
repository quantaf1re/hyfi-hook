pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {ILPQuoter} from "./interfaces/ILPQuoter.sol";

/// @title SimpleQuoter — Reference ILPQuoter that also custodies MM inventory as ERC6909 on the PoolManager.
/// @notice The MM (owner) deposits ERC20 / native into this contract; the contract converts them into
///         ERC6909 claims held at its own address on the PoolManager. During swaps, the HyFiHook is a
///         pre-approved PM operator of this contract's 6909 balances, which lets the hook burn
///         output-side claims to settle swap deltas without any cross-contract token movement.
/// @dev    Upgradeable via TransparentUpgradeableProxy. The implementation's constructor disables
///         initializers; the proxy calls `initialize(...)` once to set up pm/hook/owner/fees and
///         authorises the hook as a PM operator of the proxy's 6909 balances.
contract SimpleQuoter is ILPQuoter, IUnlockCallback, Initializable, OwnableUpgradeable {
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;

    uint internal constant MAX_FEE   = 1_000_000;  // 100 % cap
    uint internal constant FEE_DENOM = 1_000_000;
    uint internal constant Q96       = 1 << 96;

    IPoolManager public pm;
    address      public hook;

    uint public baseFee;
    uint public feePerSecond;

    error ZeroOutput();
    error FeeTooHigh();
    error OnlyPoolManager();
    error BadMsgValue();

    event FeeUpdated(uint newBaseFee, uint newFeePerSecond);
    event Deposited(Currency indexed currency, uint amount);
    event Withdrawn(Currency indexed currency, uint amount, address indexed to);

    modifier onlyPM() {
        if (msg.sender != address(pm)) revert OnlyPoolManager();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IPoolManager _pm,
        address _hook,
        address _owner,
        uint _baseFee,
        uint _feePerSecond
    ) external initializer {
        if (_baseFee > MAX_FEE) revert FeeTooHigh();
        __Ownable_init(_owner);
        pm           = _pm;
        hook         = _hook;
        baseFee      = _baseFee;
        feePerSecond = _feePerSecond;

        // Authorise the hook to burn this quoter's ERC6909 balances during swap settlement.
        _pm.setOperator(_hook, true);
    }

    /// @notice Update the base fee and per-second staleness rate (in pips; FEE_DENOM = 1e6 = 100%).
    function setFee(uint newBaseFee, uint newFeePerSecond) external onlyOwner {
        if (newBaseFee > MAX_FEE) revert FeeTooHigh();
        baseFee = newBaseFee;
        feePerSecond = newFeePerSecond;
        emit FeeUpdated(newBaseFee, newFeePerSecond);
    }

    // -----------------------------------------------------------------------
    // Custody — deposit / withdraw ERC6909 inventory
    // -----------------------------------------------------------------------

    /// @notice Pull `amount` of `currency` from the owner and mint ERC6909 claims to this contract.
    /// @dev    For native, call with `msg.value == amount`. For ERC20, owner must have approved this contract.
    function depositTo6909(Currency currency, uint amount) external payable onlyOwner {
        if (currency.isAddressZero()) {
            if (msg.value != amount) revert BadMsgValue();
        } else {
            if (msg.value != 0) revert BadMsgValue();
            IERC20(Currency.unwrap(currency)).transferFrom(msg.sender, address(this), amount);
        }
        pm.unlock(abi.encode(true, currency, amount, address(0)));
        emit Deposited(currency, amount);
    }

    /// @notice Burn `amount` of this contract's ERC6909 claims and send the underlying to `to`.
    function withdrawFrom6909(Currency currency, uint amount, address to) external onlyOwner {
        pm.unlock(abi.encode(false, currency, amount, to));
        emit Withdrawn(currency, amount, to);
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external override onlyPM returns (bytes memory) {
        (bool isDeposit, Currency currency, uint amount, address to) =
            abi.decode(data, (bool, Currency, uint, address));

        if (isDeposit) {
            // Pay tokens to PM from this contract's balance, mint 6909 to self.
            currency.settle(pm, address(this), amount, false);
            currency.take(pm, address(this), amount, true);
        } else {
            // Burn self's 6909, release underlying to `to`.
            currency.settle(pm, address(this), amount, true);
            currency.take(pm, to, amount, false);
        }
        return "";
    }

    receive() external payable {}

    // -----------------------------------------------------------------------
    // ILPQuoter
    // -----------------------------------------------------------------------

    function quoteTrade(
        PoolKey calldata,
        bool zeroForOne,
        int256 amountSpecified,
        uint256 bidPriceX96,
        uint256 spreadX96,
        uint32 timestamp
    ) external view override returns (uint256 amIn, uint256 amOut) {
        uint effectivePriceX96 = zeroForOne ? bidPriceX96 : bidPriceX96 + spreadX96;
        uint fee = _fee(timestamp);

        if (amountSpecified < 0) {
            amIn = uint(-amountSpecified);
            uint amInAfterFee = amIn * (FEE_DENOM - fee) / FEE_DENOM;
            amOut = zeroForOne
                ? FullMath.mulDiv(amInAfterFee, effectivePriceX96, Q96)
                : FullMath.mulDiv(amInAfterFee, Q96, effectivePriceX96);
            if (amOut == 0) revert ZeroOutput();
        } else {
            amOut = uint(amountSpecified);
            uint amInBeforeFee = zeroForOne
                ? FullMath.mulDivRoundingUp(amOut, Q96, effectivePriceX96)
                : FullMath.mulDivRoundingUp(amOut, effectivePriceX96, Q96);
            amIn = FullMath.mulDivRoundingUp(amInBeforeFee, FEE_DENOM, FEE_DENOM - fee);
        }
    }

    function _fee(uint32 timestamp) internal view returns (uint fee) {
        uint f = baseFee + (block.timestamp - uint(timestamp)) * feePerSecond;
        fee = f > MAX_FEE ? MAX_FEE : f;
    }
}
