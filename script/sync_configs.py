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
    'BASE_ETH-USDC': {
        'chain_name': 'BASE',
        'base_sym': 'ETH',
        'quote_sym': 'USDC',
        't0_sym': 'NATIVE',            # token0 in Uniswap ordering (lower address)
        't1_sym': 'USDC',              # token1 in Uniswap ordering
        'dex_tokens_inverted': False,   # False = base is t0, True = base is t1
        'spot_pair': 'ETHUSDC',         # Binance spot pair for price feed
        'perps_pair': 'ETHUSDT',        # Binance USDⓈ-M futures pair for hedging
        'am_base_target_w': 1 * (10**18),  # target base exposure in hook claims (wei)
        'hedge_tolerance_d': '0.001',    # don't hedge if delta < this fraction of target (0.1%)
    },
}

CHAIN_NAME_TO_RPC_ENV = {
    'MATIC': 'RPC_URL_MATIC',
    'ETH': 'RPC_URL_ETH',
    'BASE': 'RPC_URL_BASE',
}

CHAIN_ID_TO_NAME = {
    137: 'MATIC',
    1: 'ETH',
    8453: 'BASE',
}

CHAIN_NAME_TO_ADDRS = {
    'MATIC': {
        'pm': '0x67366782805870060151383F4BbFF9daB53e5cD6',
        'hook': '0x23bECbf4bA776B910E105A20060e47ae43020888',
        'quoter': '',
        'v3_quoter': '0x61fFE014bA17989E743c5F6cB21bF9697530B21e',
        'v4_quoter': '0xb3d5c3dfc3a7aebff71895a7191796bffc2c81b9',
        'benchmark_quoter': '0xa6B8812cD3C76eb31Ee8D40d259fDD48cB554e0a',
    },
    'ETH': {
        'pm': '0x000000000004444c5dc75cB358380D2e3dE08A90',
        'hook': '',
        'quoter': '',
        'v3_quoter': '',
        'v4_quoter': '',
    },
    'BASE': {
        'pm': '0x498581fF718922c3f8e6A244956aF099B2652b2b',
        'hook': '0x2948AC0d34895c5449D728B6569c8Fc92B9C4888',
        'kyber_hook': '0x4440854B2d02C57A0Dc5c58b7A884562D875c0c4',
        'quoter': '0xBeE34963e519D8A24d35983219812173fc34BDF5',
        'v3_quoter': '0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a',
        'v4_quoter': '0x0d5e0f971ed27fbFF6C2837Bf31316121532048D',
        'benchmark_quoter': '0xb167212847b8b7d3d2e2b2412bf0c39065f8aef1',
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
    'BASE': {
        'WETH': {'addr': '0x4200000000000000000000000000000000000006', 'decs': 18},
        'USDC': {'addr': '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913', 'decs': 6},
    },
}

# pool_type: 0=V3, 1=V4
BENCHMARK_CONFIGS = {
    'MATIC': {
        'V3_POL-USDC_0.05%': {
            'pool_type': 0,
            't0': 'WMATIC',
            't1': 'USDC',
            'fee': 500,
            'tick_spacing': None,  # ignored for V3
            'hooks': None,
            'hook_data': b'',
            't0_is_base': True,
        },
        'V3_POL-USDT_0.05%': {
            'pool_type': 0,
            't0': 'WMATIC',
            't1': 'USDT',
            'fee': 500,
            'tick_spacing': None,  # ignored for V3
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
    },
    'BASE': {
        'V3_ETH-USDC_0.3%': {
            'pool_type': 0,
            't0': 'WETH',
            't1': 'USDC',
            'fee': 3000,
            'tick_spacing': None,  # ignored for V3
            'hooks': None,
            'hook_data': b'',
            't0_is_base': True,
        },
        'V3_ETH-USDC_0.05%': {
            'pool_type': 0,
            't0': 'WETH',
            't1': 'USDC',
            'fee': 500,
            'tick_spacing': None,  # ignored for V3
            'hooks': None,
            'hook_data': b'',
            't0_is_base': True,
        },
        'V3_ETH-USDC_0.01%': {
            'pool_type': 0,
            't0': 'WETH',
            't1': 'USDC',
            'fee': 100,
            'tick_spacing': None,  # ignored for V3
            'hooks': None,
            'hook_data': b'',
            't0_is_base': True,
        },
        'V4_ETH-USDC_0.3%': {
            'pool_type': 1,
            't0': 'NATIVE',
            't1': 'USDC',
            'fee': 3000,
            'tick_spacing': 60,
            'hooks': None,
            'hook_data': b'',
            't0_is_base': True,
        },
        'V4_ETH-USDC_0.05%': {
            'pool_type': 1,
            't0': 'NATIVE',
            't1': 'USDC',
            'fee': 500,
            'tick_spacing': 10,
            'hooks': None,
            'hook_data': b'',
            't0_is_base': True,
        },
        'V4_Kyber_ETH-USDC': {
            # https://basescan.org/address/0x4440854B2d02C57A0Dc5c58b7A884562D875c0c4
            # fee/tick_spacing assumed identical to the confirmed Kyber USDC/cbBTC
            # pool on Base (poolId 0x813d…c39e, init block 30270989).
            'pool_type': 1,
            't0': 'NATIVE',
            't1': 'USDC',
            'fee': 1,
            'tick_spacing': 1,
            'hooks': 'kyber_hook',
            'hook_data': b'',
            't0_is_base': True,
        },
        'V4_HyFiHook_ETH-USDC': {
            'pool_type': 1,
            't0': 'NATIVE',
            't1': 'USDC',
            'fee': 0,
            'tick_spacing': 1,
            'hooks': 'hook',
            'hook_data': b'',
            't0_is_base': True,
        },
    },
}
