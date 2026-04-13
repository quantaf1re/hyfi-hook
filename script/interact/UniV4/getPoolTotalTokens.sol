pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Utils} from "../../../test/Utils.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

contract GetPoolTotalTokens is Script, Utils {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager public poolManager = IPoolManager(0x67366782805870060151383F4BbFF9daB53e5cD6);
    IERC20Metadata public t1 = IERC20Metadata(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359); // USDC

    // Tick range to scan (adjust based on pool activity)
    int24 constant TICK_SCAN_START = -887272; // Min tick for most pools
    int24 constant TICK_SCAN_END = 887272;    // Max tick for most pools
    int24 constant TICK_SCAN_STEP = 60;       // Step size for efficiency

    function run() public view {
        console2.log("=== Pool Total Token Analysis ===");
        
        // Create pool key
        PoolKey memory poolKey = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO, // POL
            currency1: Currency.wrap(address(t1)),   // USDC
            fee: 1000,
            tickSpacing: 1,
            hooks: IHooks(ADDR_ZERO)
        });

        PoolId poolId = poolKey.toId();
        console2.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));

        // Get current pool state
        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(poolId);
        
        if (sqrtPriceX96 == 0) {
            console2.log("Pool not initialized or no liquidity");
            return;
        }

        console2.log("Current Tick:", currentTick);
        console2.log("Current Price: %e", getPriceFromSqrtPriceX96(sqrtPriceX96, false, 18, t1.decimals()));

        // Get total liquidity at current price
        uint128 totalLiquidity = poolManager.getLiquidity(poolId);
        console2.log("Total Active Liquidity:", totalLiquidity);

        if (totalLiquidity == 0) {
            console2.log("No active liquidity in pool");
            return;
        }

        // Calculate total token amounts using the simplified approach
        // This calculates how much of each token would be needed to provide the current total liquidity
        // at the current price across a representative range
        calculateTotalTokenAmounts(poolId, sqrtPriceX96, currentTick, totalLiquidity);

        // Also show liquidity distribution analysis
        analyzeLiquidityDistribution(poolId, currentTick, sqrtPriceX96);
    }

    function calculateTotalTokenAmounts(
        PoolId poolId,
        uint160 sqrtPriceX96,
        int24 currentTick,
        uint128 totalLiquidity
    ) internal view {
        console2.log("\n=== Total Token Amounts ===");

        // Method 1: Calculate based on total liquidity at current tick
        // This assumes all liquidity is concentrated at the current tick (approximation)
        (uint amount0, uint amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(currentTick),
            TickMath.getSqrtPriceAtTick(currentTick + 1),
            totalLiquidity
        );

        console2.log("Approximate Total POL: %e", amount0);
        console2.log("Approximate Total USDC: %e", amount1);

        // Method 2: More accurate calculation by scanning tick ranges
        // This is computationally intensive but more accurate
        console2.log("\n=== Detailed Tick Analysis ===");
        scanTickRanges(poolId, sqrtPriceX96, currentTick);
    }

    function scanTickRanges(PoolId poolId, uint160 sqrtPriceX96, int24 currentTick) internal view {
        uint256 totalAmount0 = 0;
        uint256 totalAmount1 = 0;
        uint256 activeTicks = 0;

        console2.log("Scanning tick ranges for active liquidity...");

        // Scan around current tick first (most likely to have liquidity)
        int24 scanStart = currentTick - 1000;
        int24 scanEnd = currentTick + 1000;
        int24 step = 10; // Smaller step for better accuracy

        for (int24 tickLower = scanStart; tickLower < scanEnd; tickLower += step) {
            int24 tickUpper = tickLower + step;
            
            // Get liquidity info for this tick range
            uint128 liquidity = poolManager.getLiquidity(poolId);
            
            if (liquidity > 0) {
                // Calculate token amounts for this range
                (uint amount0, uint amount1) = LiquidityAmounts.getAmountsForLiquidity(
                    sqrtPriceX96,
                    TickMath.getSqrtPriceAtTick(tickLower),
                    TickMath.getSqrtPriceAtTick(tickUpper),
                    liquidity
                );

                totalAmount0 += amount0;
                totalAmount1 += amount1;
                activeTicks++;

                if (activeTicks <= 5) { // Show first few ranges for debugging
                    console2.log("Tick range found with liquidity");
                    console2.log("  Lower tick:", tickLower);
                    console2.log("  Upper tick:", tickUpper);
                    console2.log("  POL amount: %e", amount0);
                    console2.log("  USDC amount: %e", amount1);
                }
            }
        }

        console2.log("\n=== Scan Results ===");
        console2.log("Active tick ranges found:", activeTicks);
        console2.log("Total POL from scan: %e", totalAmount0);
        console2.log("Total USDC from scan: %e", totalAmount1);
    }

    function analyzeLiquidityDistribution(
        PoolId poolId,
        int24 currentTick,
        uint160 sqrtPriceX96
    ) internal view {
        console2.log("\n=== Liquidity Distribution Analysis ===");

        // Check liquidity at different price ranges
        int24[] memory tickRanges = new int24[](5);
        tickRanges[0] = currentTick - 100;
        tickRanges[1] = currentTick - 50;
        tickRanges[2] = currentTick;
        tickRanges[3] = currentTick + 50;
        tickRanges[4] = currentTick + 100;

        for (uint i = 0; i < tickRanges.length - 1; i++) {
            int24 tickLower = tickRanges[i];
            int24 tickUpper = tickRanges[i + 1];

            // Calculate what tokens would be needed for this range
            uint128 sampleLiquidity = 1e18; // 1 unit of liquidity for comparison
            (uint amount0, uint amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                sampleLiquidity
            );

            console2.log("Range details:");
            console2.log("  Lower tick:", tickLower);
            console2.log("  Upper tick:", tickUpper);
            console2.log("  POL per unit liquidity: %e", amount0);
            console2.log("  USDC per unit liquidity: %e", amount1);
        }
    }
}
