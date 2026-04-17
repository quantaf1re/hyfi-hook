BENCHMARK_QUOTER_ABI = """[
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "_quoterV2",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_v4Quoter",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "quoteAll",
    "inputs": [
      {
        "name": "pools",
        "type": "tuple[]",
        "internalType": "struct BenchmarkQuoter.PoolConfig[]",
        "components": [
          {
            "name": "poolType",
            "type": "uint8",
            "internalType": "enum BenchmarkQuoter.PoolType"
          },
          {
            "name": "t0",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "t1",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "fee",
            "type": "uint24",
            "internalType": "uint24"
          },
          {
            "name": "tickSpacing",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "hooks",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "hookData",
            "type": "bytes",
            "internalType": "bytes"
          }
        ]
      },
      {
        "name": "amtsZeroToOne",
        "type": "uint256[]",
        "internalType": "uint256[]"
      },
      {
        "name": "amtsOneToZero",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "outputs": [
      {
        "name": "outsZeroToOne",
        "type": "tuple[][]",
        "internalType": "struct BenchmarkQuoter.QuoteResult[][]",
        "components": [
          {
            "name": "amountOut",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "success",
            "type": "bool",
            "internalType": "bool"
          }
        ]
      },
      {
        "name": "outsOneToZero",
        "type": "tuple[][]",
        "internalType": "struct BenchmarkQuoter.QuoteResult[][]",
        "components": [
          {
            "name": "amountOut",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "success",
            "type": "bool",
            "internalType": "bool"
          }
        ]
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "quoterV2",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IQuoterV2"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "v4Quoter",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IV4Quoter"
      }
    ],
    "stateMutability": "view"
  }
]"""