#!/usr/bin/env python3
"""
Fetch all Uniswap V4 swaps that touched a specific hook over a block range
and export them to CSV.

Strategy:
  V4 Swap events are emitted by the PoolManager and indexed by the poolId
  (= keccak256(abi.encode(PoolKey))).  We compute the poolId for every
  PoolKey listed in HOOK_POOLS and pull Swap events for those ids.

For each swap we also fetch the parent transaction's `from` (the trader)
and `to` (router/aggregator).

Usage:
    Edit the CONFIG block below, then run:
        python script/analysis/trades/get_hook_trades.py
"""

import os
import sys
import csv
import time

import requests
from dotenv import load_dotenv
from eth_abi import encode as abi_encode
from web3 import Web3, HTTPProvider
from web3.middleware import ExtraDataToPOAMiddleware

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..', '..'))
if SCRIPT_ROOT not in sys.path:
    sys.path.insert(0, SCRIPT_ROOT)

from ABIs.poolManager_abi import POOLMANAGER_ABI
from sync_configs import CHAIN_NAME_TO_RPC_ENV, CHAIN_NAME_TO_ADDRS

# ---------------------------------------------------------------------------
# Configuration — edit before running
# ---------------------------------------------------------------------------
CHAIN        = 'BASE'
HOOK         = '0x2948AC0d34895c5449D728B6569c8Fc92B9C4888'
START_BLOCK  = 45328008
END_BLOCK    = None       # None = latest
OUTPUT       = None       # None → trades_<CHAIN>_<HOOK[:8]>_<from>-<to>.csv
FETCH_TX     = True       # fetch tx.from and tx.to (set False to skip)
BATCH_SIZE   = 9_000      # eth_getLogs window (Quicknode caps at 10_000)
TX_BATCH     = 50         # JSON-RPC batch size for eth_getTransactionByHash

# Pool to scan. Token addresses use Currency convention:
#   address(0) for native, otherwise the ERC20 address.
POOL_NAME    = 'ETH-USDC'
CURRENCY0    = '0x0000000000000000000000000000000000000000'
CURRENCY1    = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913'  # Base USDC
FEE          = 0
TICK_SPACING = 1

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
RATE_LIMIT_S = 0.15
MAX_RETRIES  = 3
ZERO_ADDR    = '0x0000000000000000000000000000000000000000'

# Swap(bytes32 indexed id, address indexed sender, int128 amount0, int128 amount1,
#      uint160 sqrtPriceX96, uint128 liquidity, int24 tick, uint24 fee)
V4_SWAP_TOPIC0 = '0x' + Web3.keccak(
    text='Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)'
).hex()

CSV_FIELDS = [
    'tx_hash', 'block_num', 'log_index',
    'pool_id', 'fee_emitted',
    'sender', 'tx_from', 'tx_to',
    'currency0', 'currency1',
    'amount0', 'amount1',
    'token_in', 'token_out', 'amount_in', 'amount_out',
    'sqrtPriceX96', 'liquidity', 'tick',
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def pool_id_from_key(c0, c1, fee, tick_spacing, hooks):
    """keccak256(abi.encode(PoolKey)). c0/c1 must already be in canonical order."""
    encoded = abi_encode(
        ['address', 'address', 'uint24', 'int24', 'address'],
        [
            Web3.to_checksum_address(c0),
            Web3.to_checksum_address(c1),
            fee, tick_spacing,
            Web3.to_checksum_address(hooks),
        ],
    )
    return '0x' + Web3.keccak(encoded).hex()


def get_logs_batched(w3, address, topics, from_block, to_block, label):
    """Paginate eth_getLogs in BATCH_SIZE chunks. Yields (logs, cur, end, fetched, total) per batch."""
    cur = from_block
    total = to_block - from_block + 1
    fetched = 0
    while cur <= to_block:
        end = min(cur + BATCH_SIZE - 1, to_block)
        fetched += end - cur + 1
        params = {
            'fromBlock': hex(cur), 'toBlock': hex(end),
            'address': address, 'topics': topics,
        }
        logs = None
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                logs = w3.eth.get_logs(params)
                break
            except Exception as e:
                if attempt == MAX_RETRIES:
                    raise
                wait = 2 ** attempt
                print(f'  Retry {attempt}/{MAX_RETRIES} for {label} blocks {cur}-{end}: {e}. Waiting {wait}s…')
                time.sleep(wait)
        yield logs, cur, end, fetched, total
        cur = end + 1
        time.sleep(RATE_LIMIT_S)


def batch_get_tx(rpc_url, tx_hashes):
    """Batch-fetch tx objects (for .from / .to)."""
    result = {}
    remaining = list(tx_hashes)
    total = len(tx_hashes)
    bs = TX_BATCH
    while remaining:
        still_missing = []
        for i in range(0, len(remaining), bs):
            chunk = remaining[i:i + bs]
            payload = [
                {'jsonrpc': '2.0', 'id': h, 'method': 'eth_getTransactionByHash', 'params': ['0x' + h]}
                for h in chunk
            ]
            for attempt in range(1, MAX_RETRIES + 1):
                try:
                    resp = requests.post(rpc_url, json=payload, timeout=60)
                    resp.raise_for_status()
                    for item in resp.json():
                        tx = item.get('result')
                        if tx:
                            result[item['id']] = (tx.get('from') or '', tx.get('to') or '')
                    still_missing.extend(h for h in chunk if h not in result)
                    break
                except Exception as e:
                    if attempt == MAX_RETRIES:
                        print(f'  Warning: tx fetch failed: {e}')
                        still_missing.extend(h for h in chunk if h not in result)
                        break
                    time.sleep(2 ** attempt)
            done = len(result)
            if done % (bs * 20) == 0 or done == total:
                print(f'  tx: {done:,}/{total:,} ({done/total*100:.1f}%)')
            time.sleep(RATE_LIMIT_S)
        remaining = [h for h in still_missing if h not in result]
        if remaining:
            new_bs = max(1, bs // 5)
            if new_bs == bs:
                print(f'  Giving up on {len(remaining):,} tx hashes')
                break
            bs = new_bs
            print(f'  Retrying {len(remaining):,} missing tx (batch_size={bs})…')
    return result


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    load_dotenv(os.path.join(SCRIPT_ROOT, '..', '.env'))
    rpc_url = os.getenv(CHAIN_NAME_TO_RPC_ENV[CHAIN])
    if not rpc_url:
        print(f'RPC URL env var not set for {CHAIN}'); sys.exit(1)

    w3 = Web3(HTTPProvider(rpc_url, request_kwargs={'timeout': 60}))
    w3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)
    end_block = END_BLOCK if END_BLOCK is not None else w3.eth.block_number
    print(f'Connected to chain {w3.eth.chain_id}, latest {w3.eth.block_number:,}')
    print(f'Hook: {HOOK}')
    print(f'Block range: {START_BLOCK:,} – {end_block:,}')

    pm_addr = Web3.to_checksum_address(CHAIN_NAME_TO_ADDRS[CHAIN]['pm'])
    pm = w3.eth.contract(address=pm_addr, abi=POOLMANAGER_ABI)

    # Compute poolId. Canonical order: address(0) first, else lower address.
    c0, c1 = CURRENCY0, CURRENCY1
    if c0 != ZERO_ADDR and c1 != ZERO_ADDR and c1.lower() < c0.lower():
        c0, c1 = c1, c0
    pool_id = pool_id_from_key(c0, c1, FEE, TICK_SPACING, HOOK)
    print(f'  Pool {POOL_NAME}: poolId={pool_id}')

    output_path = OUTPUT or os.path.join(
        SCRIPT_DIR,
        f'trades_{CHAIN}_{POOL_NAME}_{HOOK[:8].lower()}_{START_BLOCK}-{end_block}.csv',
    )
    csv_file = open(output_path, 'w', newline='')
    writer = csv.DictWriter(csv_file, fieldnames=CSV_FIELDS)
    writer.writeheader()
    csv_file.flush()
    print(f'Output: {output_path}')

    print('\n=== Fetching Swap events ===')
    t0 = time.time()
    total_rows = 0
    total_logs = 0
    for swap_logs, cur, end, fetched, total in get_logs_batched(
        w3, pm_addr,
        [V4_SWAP_TOPIC0, pool_id],
        START_BLOCK, end_block, 'V4 Swap',
    ):
        total_logs += len(swap_logs)
        batch_rows = []
        for log in swap_logs:
            try:
                a = pm.events.Swap.process_log(log)['args']
            except Exception as e:
                print(f'  Warning: failed to decode log {log["transactionHash"].hex()}: {e}')
                continue
            pid = '0x' + a['id'].hex()
            amt0, amt1 = a['amount0'], a['amount1']
            # Pool-centric: positive = token flowed INTO pool from trader.
            if amt0 > 0:
                tin, tout = c0, c1
                ain, aout = amt0, abs(amt1)
            else:
                tin, tout = c1, c0
                ain, aout = amt1, abs(amt0)
            batch_rows.append({
                'tx_hash': log['transactionHash'].hex(),
                'block_num': log['blockNumber'],
                'log_index': log['logIndex'],
                'pool_id': pid,
                'fee_emitted': a['fee'],
                'sender': a['sender'],
                'tx_from': '',
                'tx_to': '',
                'currency0': c0,
                'currency1': c1,
                'amount0': amt0,
                'amount1': amt1,
                'token_in': tin,
                'token_out': tout,
                'amount_in': ain,
                'amount_out': aout,
                'sqrtPriceX96': a['sqrtPriceX96'],
                'liquidity': a['liquidity'],
                'tick': a['tick'],
            })

        if FETCH_TX and batch_rows:
            unique = list({r['tx_hash'] for r in batch_rows})
            tx_map = batch_get_tx(rpc_url, unique)
            for r in batch_rows:
                f, t = tx_map.get(r['tx_hash'], ('', ''))
                r['tx_from'] = f
                r['tx_to'] = t

        batch_rows.sort(key=lambda r: (r['block_num'], r['log_index']))
        writer.writerows(batch_rows)
        csv_file.flush()
        total_rows += len(batch_rows)
        print(f'  V4 Swap: {fetched:,}/{total:,} blocks ({fetched/total*100:.1f}%), '
              f'+{len(batch_rows)} rows (total {total_rows:,})')

    csv_file.close()
    print(f'\nFetched {total_logs:,} swap log(s) in {(time.time()-t0)/60:.2f} min')
    print(f'Wrote {total_rows:,} rows to {output_path}')


if __name__ == '__main__':
    main()
