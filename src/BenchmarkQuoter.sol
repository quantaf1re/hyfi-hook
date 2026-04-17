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

    IQuoterV2 public immutable quoterV2;
    IV4Quoter public immutable v4Quoter;

    constructor(address _quoterV2, address _v4Quoter) {
        quoterV2 = IQuoterV2(_quoterV2);
        v4Quoter = IV4Quoter(_v4Quoter);
    }

    /// @param pools            Unified pool configs (V3 and V4 mixed).
    /// @param amtsZeroToOne    Exact input amounts of t0 for swapping t0 → t1.
    /// @param amtsOneToZero    Exact input amounts of t1 for swapping t1 → t0.
    /// @return outsZeroToOne   [pool][amount] t1 received when swapping amtsZeroToOne[j] of t0.
    /// @return outsOneToZero   [pool][amount] t0 received when swapping amtsOneToZero[j] of t1.
    function quoteAll(
        PoolConfig[] memory pools,
        uint256[] calldata amtsZeroToOne,
        uint256[] calldata amtsOneToZero
    )
        external
        returns (QuoteResult[][] memory outsZeroToOne, QuoteResult[][] memory outsOneToZero)
    {
        outsZeroToOne = new QuoteResult[][](pools.length);
        outsOneToZero = new QuoteResult[][](pools.length);

        for (uint i; i < pools.length; ++i) {
            outsZeroToOne[i] = new QuoteResult[](amtsZeroToOne.length);
            outsOneToZero[i] = new QuoteResult[](amtsOneToZero.length);

            if (pools[i].poolType == PoolType.V3) {
                _quoteV3All(pools[i], amtsZeroToOne, amtsOneToZero, outsZeroToOne[i], outsOneToZero[i]);
            } else {
                _quoteV4All(pools[i], amtsZeroToOne, amtsOneToZero, outsZeroToOne[i], outsOneToZero[i]);
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
        for (uint j; j < amts0to1.length; ++j) {
            out0to1[j] = _quoteV3(p.t0, p.t1, p.fee, amts0to1[j]);
        }
        for (uint j; j < amts1to0.length; ++j) {
            out1to0[j] = _quoteV3(p.t1, p.t0, p.fee, amts1to0[j]);
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
        for (uint j; j < amts0to1.length; ++j) {
            out0to1[j] = _quoteV4(key, true, uint128(amts0to1[j]), p.hookData);
        }
        for (uint j; j < amts1to0.length; ++j) {
            out1to0[j] = _quoteV4(key, false, uint128(amts1to0[j]), p.hookData);
        }
    }

    function _quoteV3(address tIn, address tOut, uint24 fee, uint256 amtIn)
        internal
        returns (QuoteResult memory r)
    {
        try quoterV2.quoteExactInputSingle(
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
        try v4Quoter.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams(key, zfo, amt, hd)
        ) returns (uint256 out, uint256) {
            r = QuoteResult(out, true);
        } catch {
            r = QuoteResult(0, false);
        }
    }
}
