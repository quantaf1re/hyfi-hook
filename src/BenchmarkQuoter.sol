pragma solidity ^0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IQuoterV2} from "@uniswap/universal-router/lib/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {IV4Quoter} from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";

/// @notice Atomically quote multiple V3 and V4 pools in a single eth_call.
contract BenchmarkQuoter {
    enum PoolType { V3, V4 }

    struct PoolConfig {
        PoolType poolType;
        address t0;                 // lower-sorted token (currency0)
        address t1;                 // higher-sorted token (currency1)
        uint24 fee;
        int24 tickSpacing;          // V4 only (ignored for V3)
        address hooks;              // V4 only (ignored for V3)
        bytes hookData;             // V4 only (ignored for V3)
    }

    struct QuoteResult {
        uint256 amountOut;
        bool success;
    }

    IV4Quoter private immutable _v4Quoter;
    IQuoterV2 private immutable _quoterV2;

    constructor(address v4Quoter_, address quoterV2_) {
        _quoterV2 = IQuoterV2(quoterV2_);
        _v4Quoter = IV4Quoter(v4Quoter_);
    }

    function getV4Quoter() external view returns (IV4Quoter) { return _v4Quoter; }
    function getQuoterV2() external view returns (IQuoterV2) { return _quoterV2; }

    /// @param pools            Unified pool configs (V3 and V4 mixed).
    /// @param amtsZeroToOne    Exact input amounts of t0 for swapping t0 → t1.
    /// @param amtsOneToZero    Exact input amounts of t1 for swapping t1 → t0.
    /// @return outsZeroToOne   [pool][amount] t1 received when swapping amtsZeroToOne[j] of t0.
    /// @return outsOneToZero   [pool][amount] t0 received when swapping amtsOneToZero[j] of t1.
    function batchQuote(
        PoolConfig[] memory pools,
        uint256[] calldata amtsZeroToOne,
        uint256[] calldata amtsOneToZero
    )
        external
        returns (QuoteResult[][] memory outsZeroToOne, QuoteResult[][] memory outsOneToZero)
    {
        outsOneToZero = new QuoteResult[][](pools.length);
        outsZeroToOne = new QuoteResult[][](pools.length);

        for (uint i; i < pools.length; ++i) {
            outsOneToZero[i] = new QuoteResult[](amtsOneToZero.length);
            outsZeroToOne[i] = new QuoteResult[](amtsZeroToOne.length);

            if (pools[i].poolType != PoolType.V3) {
                _quoteV4All(pools[i], amtsZeroToOne, amtsOneToZero, outsZeroToOne[i], outsOneToZero[i]);
            } else {
                _quoteV3All(pools[i], amtsZeroToOne, amtsOneToZero, outsZeroToOne[i], outsOneToZero[i]);
            }
        }
    }

    function _quoteV3All(
        PoolConfig memory p,
        uint256[] calldata amts0to1,
        uint256[] calldata amts1to0,
        QuoteResult[] memory out0to1,
        QuoteResult[] memory out1to0
    ) internal {
        for (uint j; j < amts1to0.length; ++j) {
            out1to0[j] = _quoteV3(p.t1, p.t0, p.fee, amts1to0[j]);
        }
        for (uint j; j < amts0to1.length; ++j) {
            out0to1[j] = _quoteV3(p.t0, p.t1, p.fee, amts0to1[j]);
        }
    }

    function _quoteV4All(
        PoolConfig memory p,
        uint256[] calldata amts0to1,
        uint256[] calldata amts1to0,
        QuoteResult[] memory out0to1,
        QuoteResult[] memory out1to0
    ) internal {
        PoolKey memory key = PoolKey(Currency.wrap(p.t0), Currency.wrap(p.t1), p.fee, p.tickSpacing, IHooks(p.hooks));
        for (uint j; j < amts1to0.length; ++j) {
            out1to0[j] = _quoteV4(key, false, uint128(amts1to0[j]), p.hookData);
        }
        for (uint j; j < amts0to1.length; ++j) {
            out0to1[j] = _quoteV4(key, true, uint128(amts0to1[j]), p.hookData);
        }
    }

    function _quoteV3(address tIn, address tOut, uint24 fee, uint256 amtIn)
        internal
        returns (QuoteResult memory r)
    {
        try _quoterV2.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams(tIn, tOut, amtIn, fee, 0)
        ) returns (uint256 out, uint160, uint32, uint256) {
            r = QuoteResult(out, true);
        } catch {
            r = QuoteResult(0, false);
        }
    }

    function _quoteV4(PoolKey memory key, bool zfo, uint128 amt, bytes memory hd)
        internal
        returns (QuoteResult memory r)
    {
        try _v4Quoter.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams(key, zfo, amt, hd)
        ) returns (uint256 out, uint256) {
            r = QuoteResult(out, true);
        } catch {
            r = QuoteResult(0, false);
        }
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
