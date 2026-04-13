#!/usr/bin/env python3
"""
sync.py — Sync HyFiHook bid/ask prices with Binance spot orderbook
           and hedge received trades via Binance perpetual futures.

Usage:
    python script/sync.py -c <config_name>
"""

import time
import os
import logging
import sys
import argparse
import traceback
import json
from web3 import Web3, HTTPProvider
from web3.middleware import ExtraDataToPOAMiddleware
from dotenv import load_dotenv
from eth_account import Account
from binance.client import Client
import decimal as dec
from eth_abi import encode
from sync_configs import CONFIGS, CHAIN_NAME_TO_RPC_ENV, CHAIN_NAME_TO_ADDRS, CHAIN_TO_SYM_TO_TOKEN
from ABIs.hyfiHook_abi import HYFIHOOK_ABI
from ABIs.poolManager_abi import POOLMANAGER_ABI
from ABIs.erc20_abi import ERC20_ABI as ERC20_ABI_STR

D = dec.Decimal


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
ADDR_ZERO = '0x0000000000000000000000000000000000000000'
Q96 = 2 ** 96
POOL_FEE = 0
TICK_SPACING = 1
BINANCE_SPOT_PRICE_URL = "https://api.binance.com/api/v3/ticker/price"

HOOK_ABI = json.loads(HYFIHOOK_ABI)
PM_ABI = json.loads(POOLMANAGER_ABI)
ERC20_ABI = json.loads(ERC20_ABI_STR)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
class NativeToken:
    def __init__(self):
        self.address = ADDR_ZERO


NATIVE = NativeToken()


def currency_to_id(address):
    """ERC6909 id = uint256(uint160(address))."""
    return int(address, 16) if address != ADDR_ZERO else 0


def calculate_pool_id(t0_addr, t1_addr, fee):
    c0 = t0_addr
    c1 = t1_addr
    if c0.lower() > c1.lower():
        c0, c1 = c1, c0
    encoded = encode(
        ['address', 'address', 'uint24', 'int24', 'address'],
        [c0, c1, fee, TICK_SPACING, addrs['hook']],
    )
    return '0x' + w3.keccak(encoded).hex()


def to_decs(val_w, decs):
    d = D(val_w) / D(10 ** decs)
    return d.quantize(D(10) ** -decs)


def to_wei(decs, val_d):
    if not isinstance(val_d, D):
        val_d = D(str(val_d))
    return int(val_d * D(10 ** decs))


def to_unit(am, decs, sym):
    if isinstance(am, int):
        am = am / (10 ** decs)
    return f'{am} {sym}'


# ---------------------------------------------------------------------------
# Transaction sending (same retry logic as mirror_orderbook.py)
# ---------------------------------------------------------------------------
def send_tx(fcn_call, timeout_s=10, max_retries=7):
    nonce = w3.eth.get_transaction_count(sender.address)
    gas = int(fcn_call.estimate_gas({'from': sender.address}) * 1.3)
    priority_multiplier = 2
    tx_hashes = []

    for attempt in range(max_retries):
        priority_fee = w3.eth.max_priority_fee * priority_multiplier
        max_fee = (w3.eth.get_block('latest').baseFeePerGas * 5) + priority_fee
        tx = fcn_call.build_transaction({
            'from':                 sender.address,
            'nonce':                nonce,
            'gas':                  gas,
            'maxPriorityFeePerGas': priority_fee,
            'maxFeePerGas':         max_fee,
            'chainId':              chain_id,
            'type':                 '0x2',
        })
        signed_tx = sender.sign_transaction(tx)
        try:
            tx_hash = w3.eth.send_raw_transaction(signed_tx.raw_transaction)
            tx_hashes.append(tx_hash)
            logger.info(f'Tx sent: 0x{tx_hash.hex()}, priorityMultiplier: {priority_multiplier}')
            receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=timeout_s)
            return tx_hash, receipt
        except Exception as e:
            logger.warning(f'xx Error sending tx: {e}.')
            for prev_hash in tx_hashes:
                try:
                    receipt = w3.eth.get_transaction_receipt(prev_hash)
                    logger.info(f'Previous tx 0x{prev_hash.hex()} mined in block {receipt["blockNumber"]}')
                    return prev_hash, receipt
                except Exception:
                    pass
            if 'nonce too low' in str(e):
                logger.info("Nonce too low, a previous tx was mined, but checking couldn't find it")
                raise
            priority_multiplier += 1
            logger.warning(
                f'Not mined within {timeout_s}s. Increasing priorityMultiplier to '
                f'{priority_multiplier} and retrying... (attempt {attempt + 1}/{max_retries})'
            )
            time.sleep(1)
    logger.error(f'xxx Send_tx failed after {max_retries} retries, giving up')
    raise RuntimeError(f'send_tx failed after {max_retries} retries')


# ---------------------------------------------------------------------------
# Price conversion  (human price → Q96)
# ---------------------------------------------------------------------------
def price_to_x96(price_d, t0_decs, t1_decs):
    """Convert a human-readable price (token1 per token0, e.g. 0.2437 USDC/POL)
    into the Q96 uint112 that the hook expects.

    hookPrice = price * 10^(t1_decs - t0_decs) * 2^96
    """
    return int(price_d * D(10 ** (t1_decs - t0_decs)) * D(Q96))


def price_to_x96_inverted(bid_d, ask_d, t0_decs, t1_decs):
    """When the CEX pair is the inverse of the on-chain token ordering
    (base = t1 not t0), the caller must invert bid/ask:
        hookBid = 1/cexAsk  (CEX ask inverts to DEX bid)
        hookAsk = 1/cexBid  (CEX bid inverts to DEX ask)
    Returns (bidPriceX96, spreadX96).
    """
    bid_x96 = price_to_x96(D(1) / ask_d, t0_decs, t1_decs)   # DEX bid = 1 / CEX ask
    ask_x96 = price_to_x96(D(1) / bid_d, t0_decs, t1_decs)   # DEX ask = 1 / CEX bid
    return bid_x96, ask_x96 - bid_x96


# ---------------------------------------------------------------------------
# Binance helpers
# ---------------------------------------------------------------------------
def get_spot_orderbook(symbol, limit=5):
    """Get spot orderbook.  Returns (bids, asks) sorted closest-to-mid first."""
    book = client.get_order_book(symbol=symbol, limit=limit)
    bids = [(D(p), D(q)) for p, q in book['bids']]
    asks = [(D(p), D(q)) for p, q in book['asks']]
    bids.sort(key=lambda x: x[0], reverse=True)
    asks.sort(key=lambda x: x[0])
    if not bids or not asks:
        raise RuntimeError(f"Empty orderbook for {symbol}: bids={len(bids)}, asks={len(asks)}")
    logger.debug(f"Spot book {symbol}: bid={bids[0][0]}, ask={asks[0][0]}, spread={asks[0][0] - bids[0][0]}")
    return bids, asks


def get_perps_position_amt(symbol):
    """Return current futures position amount as Decimal (positive=long, negative=short)."""
    positions = client.futures_position_information(symbol=symbol)
    for p in positions:
        if p['symbol'] == symbol:
            return D(p['positionAmt'])
    return D(0)


def cancel_open_perps_orders(symbol):
    """Cancel all open futures orders for symbol."""
    client.futures_cancel_all_open_orders(symbol=symbol)


def place_perps_limit(symbol, side, qty_d, price_d):
    """Place a LIMIT GTC order on USDⓈ-M futures.  Returns order dict."""
    qty_str = format(qty_d, 'f')
    price_str = format(price_d, 'f')
    logger.info(f"Placing futures limit: {symbol} {side} qty={qty_str} price={price_str}")
    order = client.futures_create_order(
        symbol=symbol,
        side=side,
        type='LIMIT',
        timeInForce='GTC',
        quantity=qty_str,
        price=price_str,
    )
    logger.info(f"Futures order placed: orderId={order['orderId']} status={order['status']}")
    return order


# ---------------------------------------------------------------------------
# Core logic
# ---------------------------------------------------------------------------
def sync_price_if_changed(c, bids, asks):
    """Convert spot best bid/ask to Q96 and call hook.setPrice if changed.
    Returns (bid_x96, spread_x96, changed_bool)."""
    best_bid_d = bids[0][0]
    best_ask_d = asks[0][0]

    if c['dex_tokens_inverted']:
        bid_x96, spread_x96 = price_to_x96_inverted(best_bid_d, best_ask_d, t0_decs, t1_decs)
    else:
        bid_x96 = price_to_x96(best_bid_d, t0_decs, t1_decs)
        ask_x96 = price_to_x96(best_ask_d, t0_decs, t1_decs)
        spread_x96 = ask_x96 - bid_x96

    if bid_x96 == c['last_bid_x96'] and spread_x96 == c['last_spread_x96']:
        logger.debug("Prices unchanged, skipping setPrice")
        return bid_x96, spread_x96, False

    logger.info(
        f"Prices changed: bid {best_bid_d} ask {best_ask_d} → "
        f"bidX96={bid_x96} spreadX96={spread_x96}"
    )
    send_tx(hook.functions.setPrice(bytes.fromhex(c['pool_id'][2:]), bid_x96, spread_x96))
    c['last_bid_x96'] = bid_x96
    c['last_spread_x96'] = spread_x96
    logger.info("setPrice tx confirmed")
    return bid_x96, spread_x96, True


def read_hook_claims(c):
    """Read the hook's ERC6909 claims from the PoolManager.
    Returns (base_claims_w, quote_claims_w)."""
    base_id = currency_to_id(c['base_token'].address)
    quote_id = currency_to_id(c['quote_token'].address)
    base_w = pm.functions.balanceOf(addrs['hook'], base_id).call()
    quote_w = pm.functions.balanceOf(addrs['hook'], quote_id).call()
    logger.debug(
        f"Hook claims: base={to_unit(base_w, base_decs, c['base_sym'])}, "
        f"quote={to_unit(quote_w, quote_decs, c['quote_sym'])}"
    )
    return base_w, quote_w


def hedge_if_needed(c, bids, asks, base_claims_w):
    """Cancel stale limit orders and place a new one if the hook's base exposure
    has drifted from target.

    hedge_remaining = excess_base + perps_position
      - positive → need to SELL on perps (place limit sell just above best bid)
      - negative → need to BUY on perps (place limit buy just below best ask)
    """
    excess_base_d = to_decs(base_claims_w - c['am_base_target_w'], base_decs)
    logger.debug(f"Excess base exposure: {excess_base_d} {c['base_sym']} (claims {to_unit(base_claims_w, base_decs, c['base_sym'])}, target {to_unit(c['am_base_target_w'], base_decs, c['base_sym'])})")
    perps_pos_d = get_perps_position_amt(c['perps_pair'])
    logger.debug(f"Current perps position: {perps_pos_d} {c['base_sym']}")
    hedge_remaining_d = excess_base_d + perps_pos_d
    logger.debug(f"Hedge remaining: {hedge_remaining_d} {c['base_sym']}")

    logger.debug(
        f"Hedge state: excess_base={excess_base_d}, perps_pos={perps_pos_d}, "
        f"hedge_remaining={hedge_remaining_d}"
    )

    # Always cancel existing orders before (re-)placing
    cancel_open_perps_orders(c['perps_pair'])

    if abs(hedge_remaining_d) < c['hedge_tolerance_d'] * to_decs(c['am_base_target_w'], base_decs):
        logger.debug("Within hedge tolerance, nothing to do")
        return

    # Determine side, quantity, and price
    if hedge_remaining_d > 0:
        # We have excess base → sell on perps
        side = 'SELL'
        qty_d = hedge_remaining_d
        # Limit sell just above best bid
        price_d = bids[0][0] + c['perps_tick_size']
    else:
        # We are short base → buy on perps
        side = 'BUY'
        qty_d = abs(hedge_remaining_d)
        # Limit buy just below best ask
        price_d = asks[0][0] - c['perps_tick_size']

    # Quantize quantity to step size
    if c['perps_step_size'] > 0:
        qty_d = qty_d.quantize(c['perps_step_size'], rounding=dec.ROUND_DOWN)

    if qty_d < c['perps_min_qty']:
        logger.debug(f"Hedge qty {qty_d} below min {c['perps_min_qty']}, skipping")
        return

    if qty_d > c['perps_max_qty']:
        raise RuntimeError(f"Hedge qty {qty_d} exceeds max {c['perps_max_qty']}")

    place_perps_limit(c['perps_pair'], side, qty_d, price_d)


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
parser = argparse.ArgumentParser(description='Sync HyFiHook prices and hedge via perps')
parser.add_argument('-c', '--config_name', type=str, required=True,
                    help='Config name from sync_configs.py')
args = parser.parse_args()

if args.config_name not in CONFIGS:
    print(f"Config '{args.config_name}' not found. Available: {', '.join(CONFIGS.keys())}")
    sys.exit(1)
c = dict(CONFIGS[args.config_name])

# Logger
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
log_format = '%(asctime)s - %(levelname)-8s:        %(message)s'
date_format = '%Y-%m-%d %H:%M:%S'
formatter = logging.Formatter(fmt=log_format, datefmt=date_format)

console_handler = logging.StreamHandler(sys.stdout)
console_handler.setLevel(logging.DEBUG)
console_handler.setFormatter(formatter)
logger.addHandler(console_handler)

os.makedirs('script/logs', exist_ok=True)
t0_sym = c['t0_sym']
t1_sym = c['t1_sym']
pair_str = f"{c['chain_name']}_{t0_sym}-{t1_sym}_hook"
file_handler = logging.FileHandler(f'script/logs/{pair_str}.log', mode='a')
file_handler.setLevel(logging.DEBUG)
file_handler.setFormatter(formatter)
logger.addHandler(file_handler)

# Env
load_dotenv()
rpc_env_key = CHAIN_NAME_TO_RPC_ENV[c['chain_name']]
rpc_url = os.getenv(rpc_env_key)
private_key = os.getenv('PRIVATE_KEY_HYFIHOOK_DEPLOYER')
if not rpc_url or not private_key:
    logger.error(f'Missing env vars (rpc_env_key={rpc_env_key})')
    sys.exit(1)

sender = Account.from_key(private_key)
logger.debug(f"Sender: {sender.address}")
w3 = Web3(HTTPProvider(rpc_url, request_kwargs={'timeout': 60}))
w3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)

api_key = os.getenv('BINANCE_API_KEY')
api_secret = os.getenv('BINANCE_API_SECRET_KEY')
client = Client(api_key, api_secret)

chain_id = w3.eth.chain_id
logger.critical(f'Starting on chain {chain_id}')

# Contracts
token_info = CHAIN_TO_SYM_TO_TOKEN[c['chain_name']]
c['t0'] = NATIVE if c['t0_sym'] == 'NATIVE' else w3.eth.contract(address=token_info[c['t0_sym']]['addr'], abi=ERC20_ABI)
c['t1'] = NATIVE if c['t1_sym'] == 'NATIVE' else w3.eth.contract(address=token_info[c['t1_sym']]['addr'], abi=ERC20_ABI)

t_to_decs = {NATIVE: 18}
for t in (c['t0'], c['t1']):
    if t is not NATIVE:
        t_to_decs[t] = t.functions.decimals().call()

t0_decs = t_to_decs[c['t0']]
t1_decs = t_to_decs[c['t1']]

c['base_token'] = c['t0'] if not c['dex_tokens_inverted'] else c['t1']
c['quote_token'] = c['t1'] if not c['dex_tokens_inverted'] else c['t0']
base_decs = t_to_decs[c['base_token']]
quote_decs = t_to_decs[c['quote_token']]

addrs = CHAIN_NAME_TO_ADDRS[c['chain_name']]
pm = w3.eth.contract(address=addrs['pm'], abi=PM_ABI)
hook = w3.eth.contract(address=addrs['hook'], abi=HOOK_ABI)
c['pool_id'] = calculate_pool_id(c['t0'].address, c['t1'].address, POOL_FEE)
logger.info(f"Pool ID: {c['pool_id']}")

# Read current on-chain price as starting state (handles restarts)
on_chain = hook.functions.getPrice(bytes.fromhex(c['pool_id'][2:])).call()
c['last_bid_x96'] = on_chain[0]
c['last_spread_x96'] = on_chain[1]
logger.info(f"On-chain price: bidX96={on_chain[0]}, spreadX96={on_chain[1]}, lastUpdate={on_chain[2]}")

# Futures symbol info (tick size, step size, min qty)
futures_info = client.futures_exchange_info()
perps_sym_info = None
for s in futures_info['symbols']:
    if s['symbol'] == c['perps_pair']:
        perps_sym_info = s
        break
if perps_sym_info is None:
    logger.error(f"Futures symbol {c['perps_pair']} not found")
    sys.exit(1)

perps_filters = {f['filterType']: f for f in perps_sym_info['filters']}
lot_size = perps_filters['LOT_SIZE']
c['perps_min_qty'] = D(lot_size['minQty'])
c['perps_max_qty'] = D(lot_size['maxQty'])
c['perps_step_size'] = D(lot_size['stepSize']).normalize()
price_filter = perps_filters['PRICE_FILTER']
c['perps_tick_size'] = D(price_filter['tickSize']).normalize()
c['hedge_tolerance_d'] = D(c['hedge_tolerance_d'])

logger.info(
    f"Futures {c['perps_pair']}: tick={c['perps_tick_size']}, "
    f"step={c['perps_step_size']}, min_qty={c['perps_min_qty']}"
)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
while True:
    try:
        logger.debug('--------------------------------------------new loop iteration--------------------------------------------')

        # 1. Get spot orderbook
        bids, asks = get_spot_orderbook(c['spot_pair'])

        # 2. Sync hook price if spot moved
        bid_x96, spread_x96, price_changed = sync_price_if_changed(c, bids, asks)

        # # 3. Read hook claims to detect trades
        # base_claims_w, quote_claims_w = read_hook_claims(c)

        # # 4. Hedge exposure delta via perps
        # hedge_if_needed(c, bids, asks, base_claims_w)

        time.sleep(1)

    except Exception as e:
        logger.error(f"Error in sync loop: {str(e)}")
        tb_lines = traceback.format_exception(type(e), e, e.__traceback__)
        logger.error(f"xxx Exception traceback:\n{''.join(tb_lines)}")
        time.sleep(10)



# TODO: add fcn to read mutliple 6909 bals at once