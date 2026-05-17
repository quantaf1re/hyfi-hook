pragma solidity ^0.8.30;

import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {ILPQuoter} from "../../src/interfaces/ILPQuoter.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @notice Property-based fuzz tests for HyFiHook swap semantics.
///         Each test targets one invariant and bounds inputs so the swap
///         path is reachable (non-zero output, sufficient inventory).
contract HyFiHookFuzzTest is HyFiHookSharedSetup {
    using CurrencyLibrary for Currency;

    // Deep-inventory top-up so fuzz amounts up to ~10k POL / ~10k USDC never skip.
    uint256 internal constant EXTRA_NATIVE = 1_000_000e18;
    uint256 internal constant EXTRA_USDC   = 1_000_000e6;

    function setUp() public {
        sharedSetup();

        // Top up mm1 and deposit more into its quoter.
        vm.deal(mm1, EXTRA_NATIVE);
        deal(USDC_ADDR, mm1, EXTRA_USDC);
        vm.startPrank(mm1);
        quoter.depositInventory{value: EXTRA_NATIVE}(native, EXTRA_NATIVE);
        IERC20(USDC_ADDR).approve(address(quoter), EXTRA_USDC);
        quoter.depositInventory(usdc, EXTRA_USDC);
        vm.stopPrank();

        // Give the trader (this contract) plenty of balance for any exact-output bound.
        vm.deal(address(this), 10_000_000e18);
        deal(USDC_ADDR, address(this), 10_000_000e6);
    }

    // =====================================================================
    //  Conservation:  traderPaid == protocolFeeΔ + quoterInputΔ
    //                 traderReceived == quoterOutputΔ
    //                 hook holds no direct ERC20 / native balance
    // =====================================================================

    function testFuzz_conservation_exactIn_zeroForOne(
        uint128 amtIn,
        uint256 feePips,
        uint32 elapsed
    ) public {
        amtIn   = uint128(bound(uint256(amtIn), 1e15, 1e22));        // 0.001 .. 10k POL
        feePips = bound(feePips, 0, 100_000);                        // 0 .. 10%
        elapsed = uint32(bound(uint256(elapsed), 0, 2000));          // cap so _fee < MAX_FEE

        hook.updateProtocolFee(feePips);
        vm.warp(block.timestamp + elapsed);

        _assertConservation(true, -int256(uint256(amtIn)));
    }

    function testFuzz_conservation_exactIn_oneForZero(
        uint64 amtIn,
        uint256 feePips,
        uint32 elapsed
    ) public {
        uint256 amt = bound(uint256(amtIn), 1e3, 1e9);               // 0.001 .. 1k USDC
        feePips = bound(feePips, 0, 100_000);
        elapsed = uint32(bound(uint256(elapsed), 0, 2000));

        hook.updateProtocolFee(feePips);
        vm.warp(block.timestamp + elapsed);

        _assertConservation(false, -int256(amt));
    }

    function testFuzz_conservation_exactOut_zeroForOne(
        uint64 amtOut,
        uint256 feePips,
        uint32 elapsed
    ) public {
        // Utils.swap uses nativeValue = 100e18 for exact-out zfo (native-in) via SWEEP.
        // Required native ≈ amtOut * 1e13 / (1 - totalFee).  Cap amtOut so required < 100 POL.
        uint256 amt = bound(uint256(amtOut), 1e3, 1e6);              // 0.001 .. 1 USDC
        feePips = bound(feePips, 0, 100_000);
        elapsed = uint32(bound(uint256(elapsed), 0, 2000));

        hook.updateProtocolFee(feePips);
        vm.warp(block.timestamp + elapsed);

        _assertConservation(true, int256(amt));
    }

    function testFuzz_conservation_exactOut_oneForZero(
        uint128 amtOut,
        uint256 feePips,
        uint32 elapsed
    ) public {
        amtOut  = uint128(bound(uint256(amtOut), 1e15, 1e22));       // 0.001 .. 10k POL
        feePips = bound(feePips, 0, 100_000);
        elapsed = uint32(bound(uint256(elapsed), 0, 2000));

        hook.updateProtocolFee(feePips);
        vm.warp(block.timestamp + elapsed);

        _assertConservation(false, int256(uint256(amtOut)));
    }

    struct ConsSnap {
        uint256 trIn;
        uint256 trOut;
        uint256 feeIn;
        uint256 feeOut;
        uint256 qIn;
        uint256 qOut;
        uint256 hookIn;
        uint256 hookOut;
    }

    function _snap(Currency inCur, Currency outCur) internal view returns (ConsSnap memory s) {
        s.trIn    = _bal(inCur, address(this));
        s.trOut   = _bal(outCur, address(this));
        s.feeIn   = pm.balanceOf(address(hook), inCur.toId());
        s.feeOut  = pm.balanceOf(address(hook), outCur.toId());
        s.qIn     = pm.balanceOf(address(quoter), inCur.toId());
        s.qOut    = pm.balanceOf(address(quoter), outCur.toId());
        s.hookIn  = _bal(inCur, address(hook));
        s.hookOut = _bal(outCur, address(hook));
    }

    function _assertConservation(bool zeroForOne, int256 amountSpecified) internal {
        Currency inCur  = zeroForOne ? native : usdc;
        Currency outCur = zeroForOne ? usdc   : native;

        ConsSnap memory b = _snap(inCur, outCur);
        swap(UNIVERSAL_ROUTER, poolKey, zeroForOne, amountSpecified);
        ConsSnap memory a = _snap(inCur, outCur);

        uint256 trPaid     = b.trIn - a.trIn;
        uint256 trReceived = a.trOut - b.trOut;
        uint256 feeDelta   = a.feeIn - b.feeIn;
        uint256 qInDelta   = a.qIn - b.qIn;
        uint256 qOutDelta  = b.qOut - a.qOut;

        assertEq(trPaid, feeDelta + qInDelta, "input-side conservation");
        assertEq(trReceived, qOutDelta, "output-side conservation");
        assertEq(a.feeOut, b.feeOut, "no fee on output currency");
        assertEq(a.hookIn, b.hookIn, "hook holds no input tokens");
        assertEq(a.hookOut, b.hookOut, "hook holds no output tokens");

        if (amountSpecified < 0) {
            assertEq(trPaid, uint256(-amountSpecified), "exact-in: trader pays exactly amountIn");
        } else {
            assertEq(trReceived, uint256(amountSpecified), "exact-out: trader receives exactly amountOut");
        }
    }

    // =====================================================================
    //  hookData override: trade routes to chosen quoter
    // =====================================================================

    function testFuzz_hookDataOverride_routesToChosenQuoter(
        uint256 baseFeeOverride,
        uint128 amtIn
    ) public {
        baseFeeOverride = bound(baseFeeOverride, 0, 50_000); // 0..5%
        amtIn = uint128(bound(uint256(amtIn), 1e15, 1e20));  // 0.001..100 POL

        // Deploy a second quoter and fund it; hookData routes the trade here.
        address mm2 = makeAddr("mm2-fuzz");
        SimpleQuoter q2 = deployQuoterProxy(pm, address(hook), mm2, baseFeeOverride, 0);
        fundQuoter(mm2, q2, USDC_ADDR, 1_000e18, 1_000e6);

        hook.updateProtocolFee(0); // isolate routing from fee accrual

        uint256 defaultIn  = pm.balanceOf(address(quoter), native.toId());
        uint256 defaultOut = pm.balanceOf(address(quoter), usdc.toId());
        uint256 q2In       = pm.balanceOf(address(q2), native.toId());
        uint256 q2Out      = pm.balanceOf(address(q2), usdc.toId());

        swap(UNIVERSAL_ROUTER, poolKey, true, -int256(uint256(amtIn)), abi.encode(address(q2)));

        // Override quoter is debited; default is untouched.
        assertEq(pm.balanceOf(address(quoter), native.toId()), defaultIn, "default quoter native untouched");
        assertEq(pm.balanceOf(address(quoter), usdc.toId()), defaultOut, "default quoter usdc untouched");
        assertEq(pm.balanceOf(address(q2), native.toId()) - q2In, uint256(amtIn), "override quoter native credited");
        assertLt(pm.balanceOf(address(q2), usdc.toId()), q2Out, "override quoter usdc debited");
    }

    // =====================================================================
    //  Fee staleness monotonicity (pure property on SimpleQuoter.getQuote)
    // =====================================================================

    function testFuzz_feeStalenessMonotone(uint256 e0, uint256 e1) public view {
        // Bound elapsed so neither quote hits MAX_FEE (which would revert with ZeroOutput).
        e0 = bound(e0, 0, 2000);
        e1 = bound(e1, e0, 2000);                                    // e1 >= e0
        uint32 now_ = uint32(block.timestamp);

        uint256 amtIn = 1e18;
        (, uint256 out0) = quoter.getQuote(
            poolKey, true, -int256(amtIn), uint256(BID_PRICE_X96), uint256(SPREAD_X96), now_ - uint32(e0)
        );
        (, uint256 out1) = quoter.getQuote(
            poolKey, true, -int256(amtIn), uint256(BID_PRICE_X96), uint256(SPREAD_X96), now_ - uint32(e1)
        );

        // Larger elapsed (e1 >= e0) ⇒ larger fee ⇒ smaller output for exact-in.
        assertLe(out1, out0, "fee grows monotonically with staleness");
    }

    // =====================================================================
    //  Helpers
    // =====================================================================

    function _bal(Currency c, address who) internal view returns (uint256) {
        return c.isAddressZero() ? who.balance : IERC20(Currency.unwrap(c)).balanceOf(who);
    }
}
