BENCHMARK_QUOTER_ABI = """[
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "v4Quoter_",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "quoterV2_",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "batchQuote",
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
    "name": "getQuoterV2",
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
    "name": "getV4Quoter",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IV4Quoter"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "junkA",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "junkB",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "string",
        "internalType": "string"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "junkC",
    "inputs": [
      {
        "name": "n",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "junkD",
    "inputs": [
      {
        "name": "a",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "b",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "junkE",
    "inputs": [
      {
        "name": "seed",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "junkF",
    "inputs": [
      {
        "name": "xs",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "outputs": [
      {
        "name": "sum",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "product",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "junkG",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "stateMutability": "pure"
  }
]"""