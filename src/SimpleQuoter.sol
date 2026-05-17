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

    uint internal constant FEE_DENOM = 1_000_000;  // 100 % cap
    uint internal constant Q96       = 1 << 96;

    IPoolManager private _pm;
    address      private _hookAddr;

    uint private _baseFee;
    uint private _feePerSecond;

    error ZeroOutput();
    error FeeTooHigh();
    error OnlyPoolManager();
    error BadMsgValue();

    event FeeUpdated(uint newBaseFee, uint newFeePerSecond);
    event Deposited(Currency indexed currency, uint amount);
    event Withdrawn(Currency indexed currency, uint amount, address indexed to);

    modifier onlyPM() {
        if (msg.sender != address(_pm)) revert OnlyPoolManager();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function getPm() external view returns (IPoolManager) { return _pm; }
    function getHook() external view returns (address) { return _hookAddr; }
    function getBaseFee() external view returns (uint) { return _baseFee; }
    function getFeePerSecond() external view returns (uint) { return _feePerSecond; }

    function initialize(
        IPoolManager pm_,
        address hook_,
        address owner_,
        uint baseFee_,
        uint feePerSecond_
    ) external initializer {
        __Ownable_init(owner_);
        if (baseFee_ > FEE_DENOM) revert FeeTooHigh();
        _feePerSecond = feePerSecond_;
        _baseFee      = baseFee_;
        _pm           = pm_;

        // Authorise the hook to burn this quoter's ERC6909 balances during swap settlement.
        pm_.setOperator(hook_, true);
        _hookAddr     = hook_;
    }

    /// @notice Update the base fee and per-second staleness rate (in pips; FEE_DENOM = 1e6 = 100%).
    function updateFeeParams(uint newBaseFee, uint newFeePerSecond) external onlyOwner {
        if (newBaseFee > FEE_DENOM) revert FeeTooHigh();
        _feePerSecond = newFeePerSecond;
        _baseFee = newBaseFee;
        emit FeeUpdated(newBaseFee, newFeePerSecond);
    }

    // =======================================================================
    // Custody — deposit / withdraw ERC6909 inventory
    // =======================================================================

    /// @notice Pull `amount` of `currency` from the owner and mint ERC6909 claims to this contract.
    /// @dev    For native, call with `msg.value == amount`. For ERC20, owner must have approved this contract.
    function depositInventory(Currency currency, uint amount) external payable onlyOwner {
        if (!currency.isAddressZero()) {
            if (msg.value != 0) revert BadMsgValue();
            IERC20(Currency.unwrap(currency)).transferFrom(msg.sender, address(this), amount);
        } else {
            if (msg.value != amount) revert BadMsgValue();
        }
        _pm.unlock(abi.encode(true, currency, amount, address(0)));
        emit Deposited(currency, amount);
    }

    /// @notice Burn `amount` of this contract's ERC6909 claims and send the underlying to `to`.
    function withdrawInventory(Currency currency, uint amount, address to) external onlyOwner {
        _pm.unlock(abi.encode(false, currency, amount, to));
        emit Withdrawn(currency, amount, to);
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external override onlyPM returns (bytes memory) {
        (bool isDeposit, Currency currency, uint amount, address to) =
            abi.decode(data, (bool, Currency, uint, address));

        if (!isDeposit) {
            // Burn self's 6909, release underlying to `to`.
            currency.settle(_pm, address(this), amount, true);
            currency.take(_pm, to, amount, false);
        } else {
            // Pay tokens to PM from this contract's balance, mint 6909 to self.
            currency.settle(_pm, address(this), amount, false);
            currency.take(_pm, address(this), amount, true);
        }
        return "";
    }

    receive() external payable {}

    // =======================================================================
    // ILPQuoter
    // =======================================================================

    function getQuote(
        PoolKey calldata,
        bool zeroForOne,
        int256 amountSpecified,
        uint256 bidPriceX96,
        uint256 spreadX96,
        uint32 timestamp
    ) external view override returns (uint256 amIn, uint256 amOut) {
        uint fee = _fee(timestamp);
        uint effectivePriceX96 = zeroForOne ? bidPriceX96 : bidPriceX96 + spreadX96;

        if (amountSpecified >= 0) {
            amOut = uint(amountSpecified);
            uint amInBeforeFee = zeroForOne
                ? FullMath.mulDivRoundingUp(amOut, Q96, effectivePriceX96)
                : FullMath.mulDivRoundingUp(amOut, effectivePriceX96, Q96);
            amIn = FullMath.mulDivRoundingUp(amInBeforeFee, FEE_DENOM, FEE_DENOM - fee);
        } else {
            amIn = uint(-amountSpecified);
            uint amInAfterFee = amIn * (FEE_DENOM - fee) / FEE_DENOM;
            amOut = zeroForOne
                ? FullMath.mulDiv(amInAfterFee, effectivePriceX96, Q96)
                : FullMath.mulDiv(amInAfterFee, Q96, effectivePriceX96);
            if (amOut == 0) revert ZeroOutput();
        }
    }

    function _fee(uint32 timestamp) internal view returns (uint fee) {
        uint f = (block.timestamp - uint(timestamp)) * _feePerSecond + _baseFee;
        fee = f > FEE_DENOM ? FEE_DENOM : f;
    }

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
}
