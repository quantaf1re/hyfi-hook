#!/usr/bin/env python3
"""
benchmark.py — Poll BenchmarkQuoter every 10s and log quotes to CSV.

Usage:
    cd hyfi-hook
    python script/benchmark/benchmark.py -c V3_POL-USDC_0.05% V4_HyFiHook_POL-USDC V3_POL-USDT_0.05%
"""

import argparse
import csv
import json
import os
import sys
import time
import urllib.request
from datetime import datetime, timezone

from dotenv import load_dotenv
from web3 import Web3, HTTPProvider
from web3.middleware import ExtraDataToPOAMiddleware

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from ABIs.benchmarkQuoter_abi import BENCHMARK_QUOTER_ABI
from sync_configs import CHAIN_NAME_TO_ADDRS, CHAIN_TO_SYM_TO_TOKEN, BENCHMARK_CONFIGS

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
load_dotenv()

CHAIN = 'MATIC'
RPC_URL = os.getenv('RPC_URL_MATIC')
BENCHMARK_QUOTER_ADDR = '0xa6B8812cD3C76eb31Ee8D40d259fDD48cB554e0a' # MATIC
POLL_INTERVAL = 10  # seconds
ADDR_ZERO   = '0x0000000000000000000000000000000000000000'
NATIVE_DECS = 18

# USD_AMOUNTS = [100, 1_000, 10_000]
USD_AMOUNTS = [6000]
CEX_SYMBOL = 'POLUSDC'  # Binance spot symbol: base priced in quote

CSV_HEADERS = [
    'timestamp', 'block', 'pool', 'input_usd',
    'sell_input', 'sell_output', 'sell_price', 'sell_ok',
    'buy_input', 'buy_output', 'buy_price', 'buy_ok',
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def get_cex_price(symbol):
    """Fetch spot price from Binance public API (no key needed)."""
    url = f'https://api.binance.com/api/v3/ticker/price?symbol={symbol}'
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read())
    return float(data['price'])


def build_amounts(base_price, pool_configs):
    """Compute input amounts for both directions at approx USD_AMOUNTS dollar values.

    Uses the first pool's decimals as canonical (all pools should agree on
    base_decs and quote_decs for the amounts to be comparable).

    amts_0to1: t0 token amounts (wei).
    amts_1to0: t1 token amounts (wei).
    For t0_is_base pools: 0to1 sends base-token amounts, 1to0 sends quote-token amounts.
    For inverted pools the contract still receives the same arrays, but the
    interpretation flips in poll_once.
    """
    p0 = pool_configs[0]
    if p0['t0_is_base']:
        base_decs, quote_decs = p0['base_decs'], p0['quote_decs']
    else:
        base_decs, quote_decs = p0['quote_decs'], p0['base_decs']
    # 0to1 amounts are t0 tokens; 1to0 amounts are t1 tokens
    amts_0to1 = [int((usd / base_price) * 10**base_decs) for usd in USD_AMOUNTS]
    amts_1to0 = [usd * 10**quote_decs for usd in USD_AMOUNTS]
    return amts_0to1, amts_1to0


def poll_once(contract, w3, pool_configs, pools, amts_0to1, amts_1to0):
    """Call quoteAll and return one CSV row per pool per USD amount.

    Each row contains both the sell and buy side:
      sell = trader sells base for quote  (e.g. sell POL for USDC)
      buy  = trader buys base with quote  (e.g. buy POL with USDC)
    eff_price is always quote-per-base (e.g. USD per POL).
    """
    block = w3.eth.block_number
    ts = datetime.now(timezone.utc).isoformat(timespec='seconds')

    outs_0to1, outs_1to0 = contract.functions.quoteAll(
        pools, amts_0to1, amts_1to0,
    ).call(block_identifier=block)

    rows = []
    for i, pc in enumerate(pool_configs):
        base_d = pc['base_decs']
        quote_d = pc['quote_decs']

        for j, usd in enumerate(USD_AMOUNTS):
            amt_out_0to1, ok_0to1 = outs_0to1[i][j]
            inp_0to1 = amts_0to1[j]
            amt_out_1to0, ok_1to0 = outs_1to0[i][j]
            inp_1to0 = amts_1to0[j]

            if pc['t0_is_base']:
                # sell base: 0to1 (input base t0, output quote t1)
                sell_in, sell_out, sell_ok = inp_0to1, amt_out_0to1, ok_0to1
                sell_price = (sell_out / 10**quote_d) / (sell_in / 10**base_d) if sell_ok and sell_in else 0
                # buy base: 1to0 (input quote t1, output base t0)
                buy_in, buy_out, buy_ok = inp_1to0, amt_out_1to0, ok_1to0
                buy_price = (buy_in / 10**quote_d) / (buy_out / 10**base_d) if buy_ok and buy_out else 0
            else:
                # sell base: 1to0 (input base t1, output quote t0)
                sell_in, sell_out, sell_ok = inp_1to0, amt_out_1to0, ok_1to0
                sell_price = (sell_out / 10**quote_d) / (sell_in / 10**base_d) if sell_ok and sell_in else 0
                # buy base: 0to1 (input quote t0, output base t1)
                buy_in, buy_out, buy_ok = inp_0to1, amt_out_0to1, ok_0to1
                buy_price = (buy_in / 10**quote_d) / (buy_out / 10**base_d) if buy_ok and buy_out else 0

            rows.append({
                'timestamp': ts,
                'block': block,
                'pool': pc['name'],
                'input_usd': usd,
                'sell_input': sell_in,
                'sell_output': sell_out,
                'sell_price': round(sell_price, 10),
                'sell_ok': sell_ok,
                'buy_input': buy_in,
                'buy_output': buy_out,
                'buy_price': round(buy_price, 10),
                'buy_ok': buy_ok,
            })

    return rows


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description='Benchmark HyFiHook vs Uniswap V3/V4 pools')
    parser.add_argument('-c', '--configs', nargs='+', required=True,
                        help='Pool names from BENCHMARK_CONFIGS in sync_configs.py')
    args = parser.parse_args()

    if not RPC_URL or not BENCHMARK_QUOTER_ADDR:
        print('Set RPC_URL_MATIC and BENCHMARK_QUOTER_ADDR in .env')
        sys.exit(1)

    # Validate pool names
    available = BENCHMARK_CONFIGS.get(CHAIN, {})
    for name in args.configs:
        if name not in available:
            print(f"Pool '{name}' not found. Available: {', '.join(available.keys())}")
            sys.exit(1)

    # Resolve pool configs
    addrs = CHAIN_NAME_TO_ADDRS[CHAIN]
    tokens = CHAIN_TO_SYM_TO_TOKEN[CHAIN]

    def tok(sym):
        if sym == 'NATIVE':
            return ADDR_ZERO, NATIVE_DECS
        return tokens[sym]['addr'], tokens[sym]['decs']

    pool_configs = []
    for name in args.configs:
        pc = available[name]
        t0a, t0d = tok(pc['t0'])
        t1a, t1d = tok(pc['t1'])
        pool_configs.append({
            'name': name,
            'tuple': (
                pc['pool_type'], t0a, t1a, pc['fee'], pc['tick_spacing'],
                addrs[pc['hooks']] if pc['hooks'] else ADDR_ZERO, pc['hook_data'],
            ),
            't0_is_base': pc['t0_is_base'],
            'base_decs': t0d if pc['t0_is_base'] else t1d,
            'quote_decs': t1d if pc['t0_is_base'] else t0d,
        })
    pools = [p['tuple'] for p in pool_configs]

    w3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 60}))
    w3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)
    print(f'Connected to chain {w3.eth.chain_id}')
    print(f'Pools: {[p["name"] for p in pool_configs]}')

    contract = w3.eth.contract(
        address=Web3.to_checksum_address(BENCHMARK_QUOTER_ADDR),
        abi=json.loads(BENCHMARK_QUOTER_ABI),
    )

    # amts_1to0 are fixed quote-token amounts; amts_0to1 recomputed each iteration
    p0 = pool_configs[0]
    quote_decs = p0['quote_decs'] if p0['t0_is_base'] else p0['base_decs']
    amts_1to0 = [usd * 10**quote_decs for usd in USD_AMOUNTS]
    print(f'Quote amounts (1to0): {[a / 10**quote_decs for a in amts_1to0]}')

    csv_name = 'benchmark_' + '_'.join(args.configs) + '.csv'
    csv_path = os.path.join(os.path.dirname(__file__), csv_name)
    write_header = not os.path.exists(csv_path)
    print(f'Logging to {csv_path}')
    print(f'Polling every {POLL_INTERVAL}s \u2014 Ctrl+C to stop\n')

    while True:
        try:
            base_price = get_cex_price(CEX_SYMBOL)
            amts_0to1, _ = build_amounts(base_price, pool_configs)
            rows = poll_once(contract, w3, pool_configs, pools, amts_0to1, amts_1to0)

            with open(csv_path, 'a', newline='') as f:
                writer = csv.DictWriter(f, fieldnames=CSV_HEADERS)
                if write_header:
                    writer.writeheader()
                    write_header = False
                writer.writerows(rows)

            n_ok = sum(1 for r in rows if r['sell_ok'] and r['buy_ok'])
            print(f'[{rows[0]["timestamp"]}] block={rows[0]["block"]}  '
                  f'{n_ok}/{len(rows)} quotes OK')

        except KeyboardInterrupt:
            print('\nStopped.')
            break
        except Exception as e:
            print(f'Error: {e}')

        time.sleep(POLL_INTERVAL)


if __name__ == '__main__':
    main()
