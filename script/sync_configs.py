"""
Pair configurations for sync.py (HyFiHook price sync + perps hedge).
Run with: python script/sync.py -c <config_name>
"""

CONFIGS = {
    'MATIC_POL-USDC': {
        'chain_name': 'MATIC',
        'base_sym': 'POL',
        'quote_sym': 'USDC',
        't0_sym': 'NATIVE',            # token0 in Uniswap ordering (lower address)
        't1_sym': 'USDC',              # token1 in Uniswap ordering
        'dex_tokens_inverted': False,   # False = base is t0, True = base is t1
        'spot_pair': 'POLUSDC',         # Binance spot pair for price feed
        'perps_pair': 'POLUSDT',        # Binance USDⓈ-M futures pair for hedging
        'am_base_target_w': 1_000 * (10**18),  # target base exposure in hook claims (wei)
        'hedge_tolerance_d': '0.001',    # don't hedge if delta < this fraction of target (0.1%)
    },
}

CHAIN_NAME_TO_RPC_ENV = {
    'MATIC': 'RPC_URL_MATIC',
    'ETH': 'RPC_URL_ETH',
}

CHAIN_ID_TO_NAME = {
    137: 'MATIC',
    1: 'ETH',
}

CHAIN_NAME_TO_ADDRS = {
    'MATIC': {
        'pm': '0x67366782805870060151383F4BbFF9daB53e5cD6',
        'hook': '0x23bECbf4bA776B910E105A20060e47ae43020888',
        'v3_quoter': '0x61fFE014bA17989E743c5F6cB21bF9697530B21e',
        'v4_quoter': '0xb3d5c3dfc3a7aebff71895a7191796bffc2c81b9',
    },
    'ETH': {
        'pm': '0x000000000004444c5dc75cB358380D2e3dE08A90',
        'hook': '',
        'v3_quoter': '',
        'v4_quoter': '',
    },
}

CHAIN_TO_SYM_TO_TOKEN = {
    'MATIC': {
        'WMATIC': {'addr': '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270', 'decs': 18},
        'USDC': {'addr': '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359', 'decs': 6},
        'USDT': {'addr': '0xc2132D05D31c914a87C6611C10748AEb04B58e8F', 'decs': 6},
    },
    'ETH': {
        'USDC': {'addr': '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', 'decs': 6},
    },
}

BENCHMARK_CONFIGS = {
    'MATIC': {
        'V3_POL-USDC_0.05%': {
            'pool_type': 0,
            't0': 'WMATIC',
            't1': 'USDC',
            'fee': 500,
            'tick_spacing': 0,
            'hooks': None,
            'hook_data': b'',
            't0_is_base': True,
        },
        'V4_HyFiHook_POL-USDC': {
            'pool_type': 1,
            't0': 'NATIVE',
            't1': 'USDC',
            'fee': 0,
            'tick_spacing': 1,
            'hooks': 'hook',
            'hook_data': b'',
            't0_is_base': True,
        },
        'V3_POL-USDT_0.05%': {
            'pool_type': 0,
            't0': 'WMATIC',
            't1': 'USDT',
            'fee': 500,
            'tick_spacing': 0,
            'hooks': None,
            'hook_data': b'',
            't0_is_base': True,
        },
    },
}
