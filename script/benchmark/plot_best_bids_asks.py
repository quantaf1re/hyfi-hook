#!/usr/bin/env python3
"""
analyze.py — Plot benchmark CSV and print best-bid/ask statistics.
"""

import sys

import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import pandas as pd

# ---- Config ----
CSV_PATH = 'script/benchmark/benchmark_V3_POL-USDC_0.05%_V4_HyFiHook_POL-USDC_V3_POL-USDT_0.05%.csv'
INPUT_USD = 6000
# ----------------


def main():
    df = pd.read_csv(CSV_PATH, parse_dates=['timestamp'])
    df = df[df['input_usd'] == INPUT_USD].copy()
    if df.empty:
        print(f'No rows with input_usd={INPUT_USD}')
        sys.exit(1)

    pools = df['pool'].unique()
    print(f'Pools: {list(pools)}')
    print(f'Rows per pool: {len(df) // len(pools)}')
    print(f'input_usd: {INPUT_USD}\n')

    # -----------------------------------------------------------------------
    # Best bid / best ask statistics
    # -----------------------------------------------------------------------
    # Best sell = highest sell_price (trader gets most quote per base)
    # Best buy  = lowest buy_price  (trader pays least quote per base)
    # Only consider rows where the quote succeeded.

    sell_ok = df[df['sell_ok']].copy()
    buy_ok = df[df['buy_ok']].copy()

    if not sell_ok.empty:
        best_sell_idx = sell_ok.groupby('timestamp')['sell_price'].idxmax()
        best_sell = sell_ok.loc[best_sell_idx, 'pool'].value_counts()
        total_sell = len(best_sell_idx)
        print('=== Best Bid (highest sell_price) ===')
        for pool in pools:
            count = best_sell.get(pool, 0)
            print(f'  {pool}: {count}/{total_sell} ({count/total_sell*100:.1f}%)')
    else:
        print('No successful sell quotes.')

    print()

    if not buy_ok.empty:
        best_buy_idx = buy_ok.groupby('timestamp')['buy_price'].idxmin()
        best_buy = buy_ok.loc[best_buy_idx, 'pool'].value_counts()
        total_buy = len(best_buy_idx)
        print('=== Best Ask (lowest buy_price) ===')
        for pool in pools:
            count = best_buy.get(pool, 0)
            print(f'  {pool}: {count}/{total_buy} ({count/total_buy*100:.1f}%)')
    else:
        print('No successful buy quotes.')

    # -----------------------------------------------------------------------
    # Plot
    # -----------------------------------------------------------------------
    fig, ax = plt.subplots(figsize=(14, 6))

    colors = plt.cm.tab10.colors
    for i, pool in enumerate(pools):
        pdf = df[df['pool'] == pool]
        color = colors[i % len(colors)]

        mask_buy = pdf['buy_ok'].astype(bool)
        mask_sell = pdf['sell_ok'].astype(bool)

        ax.plot(
            pdf.loc[mask_buy, 'timestamp'], pdf.loc[mask_buy, 'buy_price'],
            color=color, linestyle='-', alpha=0.8, label=f'{pool} ask',
        )
        ax.plot(
            pdf.loc[mask_sell, 'timestamp'], pdf.loc[mask_sell, 'sell_price'],
            color=color, linestyle='--', alpha=0.8, label=f'{pool} bid',
        )

    ax.set_xlabel('Time (UTC)')
    ax.set_ylabel('Price (quote/base)')
    ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))
    fig.autofmt_xdate()
    ax.legend(loc='upper left', fontsize=8)

    plt.title(f'Benchmark — ${INPUT_USD} input')
    plt.tight_layout()
    plt.show()


if __name__ == '__main__':
    main()
