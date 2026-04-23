HYFIHOOK_ABI = """
[
  {
    "type": "constructor",
    "inputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "receive",
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "addToWhitelist",
    "inputs": [
      {
        "name": "mm",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "afterAddLiquidity",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct PoolKey",
        "components": [
          {
            "name": "currency0",
            "type": "address",
            "internalType": "Currency"
          },
          {
            "name": "currency1",
            "type": "address",
            "internalType": "Currency"
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
            "internalType": "contract IHooks"
          }
        ]
      },
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct ModifyLiquidityParams",
        "components": [
          {
            "name": "tickLower",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "tickUpper",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "liquidityDelta",
            "type": "int256",
            "internalType": "int256"
          },
          {
            "name": "salt",
            "type": "bytes32",
            "internalType": "bytes32"
          }
        ]
      },
      {
        "name": "",
        "type": "int256",
        "internalType": "BalanceDelta"
      },
      {
        "name": "",
        "type": "int256",
        "internalType": "BalanceDelta"
      },
      {
        "name": "",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes4",
        "internalType": "bytes4"
      },
      {
        "name": "",
        "type": "int256",
        "internalType": "BalanceDelta"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "afterDonate",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct PoolKey",
        "components": [
          {
            "name": "currency0",
            "type": "address",
            "internalType": "Currency"
          },
          {
            "name": "currency1",
            "type": "address",
            "internalType": "Currency"
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
            "internalType": "contract IHooks"
          }
        ]
      },
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes4",
        "internalType": "bytes4"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "afterInitialize",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct PoolKey",
        "components": [
          {
            "name": "currency0",
            "type": "address",
            "internalType": "Currency"
          },
          {
            "name": "currency1",
            "type": "address",
            "internalType": "Currency"
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
            "internalType": "contract IHooks"
          }
        ]
      },
      {
        "name": "",
        "type": "uint160",
        "internalType": "uint160"
      },
      {
        "name": "",
        "type": "int24",
        "internalType": "int24"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes4",
        "internalType": "bytes4"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "afterRemoveLiquidity",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct PoolKey",
        "components": [
          {
            "name": "currency0",
            "type": "address",
            "internalType": "Currency"
          },
          {
            "name": "currency1",
            "type": "address",
            "internalType": "Currency"
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
            "internalType": "contract IHooks"
          }
        ]
      },
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct ModifyLiquidityParams",
        "components": [
          {
            "name": "tickLower",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "tickUpper",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "liquidityDelta",
            "type": "int256",
            "internalType": "int256"
          },
          {
            "name": "salt",
            "type": "bytes32",
            "internalType": "bytes32"
          }
        ]
      },
      {
        "name": "",
        "type": "int256",
        "internalType": "BalanceDelta"
      },
      {
        "name": "",
        "type": "int256",
        "internalType": "BalanceDelta"
      },
      {
        "name": "",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes4",
        "internalType": "bytes4"
      },
      {
        "name": "",
        "type": "int256",
        "internalType": "BalanceDelta"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "afterSwap",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct PoolKey",
        "components": [
          {
            "name": "currency0",
            "type": "address",
            "internalType": "Currency"
          },
          {
            "name": "currency1",
            "type": "address",
            "internalType": "Currency"
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
            "internalType": "contract IHooks"
          }
        ]
      },
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct SwapParams",
        "components": [
          {
            "name": "zeroForOne",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "amountSpecified",
            "type": "int256",
            "internalType": "int256"
          },
          {
            "name": "sqrtPriceLimitX96",
            "type": "uint160",
            "internalType": "uint160"
          }
        ]
      },
      {
        "name": "",
        "type": "int256",
        "internalType": "BalanceDelta"
      },
      {
        "name": "",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes4",
        "internalType": "bytes4"
      },
      {
        "name": "",
        "type": "int128",
        "internalType": "int128"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "beforeAddLiquidity",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct PoolKey",
        "components": [
          {
            "name": "currency0",
            "type": "address",
            "internalType": "Currency"
          },
          {
            "name": "currency1",
            "type": "address",
            "internalType": "Currency"
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
            "internalType": "contract IHooks"
          }
        ]
      },
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct ModifyLiquidityParams",
        "components": [
          {
            "name": "tickLower",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "tickUpper",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "liquidityDelta",
            "type": "int256",
            "internalType": "int256"
          },
          {
            "name": "salt",
            "type": "bytes32",
            "internalType": "bytes32"
          }
        ]
      },
      {
        "name": "",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes4",
        "internalType": "bytes4"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "beforeDonate",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct PoolKey",
        "components": [
          {
            "name": "currency0",
            "type": "address",
            "internalType": "Currency"
          },
          {
            "name": "currency1",
            "type": "address",
            "internalType": "Currency"
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
            "internalType": "contract IHooks"
          }
        ]
      },
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes4",
        "internalType": "bytes4"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "beforeInitialize",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct PoolKey",
        "components": [
          {
            "name": "currency0",
            "type": "address",
            "internalType": "Currency"
          },
          {
            "name": "currency1",
            "type": "address",
            "internalType": "Currency"
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
            "internalType": "contract IHooks"
          }
        ]
      },
      {
        "name": "",
        "type": "uint160",
        "internalType": "uint160"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes4",
        "internalType": "bytes4"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "beforeRemoveLiquidity",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct PoolKey",
        "components": [
          {
            "name": "currency0",
            "type": "address",
            "internalType": "Currency"
          },
          {
            "name": "currency1",
            "type": "address",
            "internalType": "Currency"
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
            "internalType": "contract IHooks"
          }
        ]
      },
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct ModifyLiquidityParams",
        "components": [
          {
            "name": "tickLower",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "tickUpper",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "liquidityDelta",
            "type": "int256",
            "internalType": "int256"
          },
          {
            "name": "salt",
            "type": "bytes32",
            "internalType": "bytes32"
          }
        ]
      },
      {
        "name": "",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes4",
        "internalType": "bytes4"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "beforeSwap",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "key",
        "type": "tuple",
        "internalType": "struct PoolKey",
        "components": [
          {
            "name": "currency0",
            "type": "address",
            "internalType": "Currency"
          },
          {
            "name": "currency1",
            "type": "address",
            "internalType": "Currency"
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
            "internalType": "contract IHooks"
          }
        ]
      },
      {
        "name": "params",
        "type": "tuple",
        "internalType": "struct SwapParams",
        "components": [
          {
            "name": "zeroForOne",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "amountSpecified",
            "type": "int256",
            "internalType": "int256"
          },
          {
            "name": "sqrtPriceLimitX96",
            "type": "uint160",
            "internalType": "uint160"
          }
        ]
      },
      {
        "name": "",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes4",
        "internalType": "bytes4"
      },
      {
        "name": "",
        "type": "int256",
        "internalType": "BeforeSwapDelta"
      },
      {
        "name": "",
        "type": "uint24",
        "internalType": "uint24"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "collectProtocolFees",
    "inputs": [
      {
        "name": "currency",
        "type": "address",
        "internalType": "Currency"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "deregisterPools",
    "inputs": [
      {
        "name": "poolIds",
        "type": "bytes32[]",
        "internalType": "PoolId[]"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getHookPermissions",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct Hooks.Permissions",
        "components": [
          {
            "name": "beforeInitialize",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "afterInitialize",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "beforeAddLiquidity",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "afterAddLiquidity",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "beforeRemoveLiquidity",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "afterRemoveLiquidity",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "beforeSwap",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "afterSwap",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "beforeDonate",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "afterDonate",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "beforeSwapReturnDelta",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "afterSwapReturnDelta",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "afterAddLiquidityReturnDelta",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "afterRemoveLiquidityReturnDelta",
            "type": "bool",
            "internalType": "bool"
          }
        ]
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "getMM",
    "inputs": [
      {
        "name": "poolId",
        "type": "bytes32",
        "internalType": "PoolId"
      },
      {
        "name": "index",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "mm",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "quoter",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getMMCount",
    "inputs": [
      {
        "name": "poolId",
        "type": "bytes32",
        "internalType": "PoolId"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getPrices",
    "inputs": [
      {
        "name": "poolIds",
        "type": "bytes32[]",
        "internalType": "PoolId[]"
      }
    ],
    "outputs": [
      {
        "name": "out",
        "type": "tuple[]",
        "internalType": "struct HyFiHook.PriceData[]",
        "components": [
          {
            "name": "bidPriceX96",
            "type": "uint112",
            "internalType": "uint112"
          },
          {
            "name": "spreadX96",
            "type": "uint112",
            "internalType": "uint112"
          },
          {
            "name": "timestamp",
            "type": "uint32",
            "internalType": "uint32"
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "initialize",
    "inputs": [
      {
        "name": "_pm",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_owner",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "owner",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "ownerDeregister",
    "inputs": [
      {
        "name": "poolIds",
        "type": "bytes32[]",
        "internalType": "PoolId[]"
      },
      {
        "name": "mm",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "pm",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IPoolManager"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "protocolFeePips",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "protocolFees",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "Currency"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "registerPools",
    "inputs": [
      {
        "name": "poolIds",
        "type": "bytes32[]",
        "internalType": "PoolId[]"
      },
      {
        "name": "quoters",
        "type": "address[]",
        "internalType": "contract ILPQuoter[]"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "removeFromWhitelist",
    "inputs": [
      {
        "name": "mm",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "renounceOwnership",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setPrices",
    "inputs": [
      {
        "name": "poolIds",
        "type": "bytes32[]",
        "internalType": "PoolId[]"
      },
      {
        "name": "prices",
        "type": "tuple[]",
        "internalType": "struct HyFiHook.PriceData[]",
        "components": [
          {
            "name": "bidPriceX96",
            "type": "uint112",
            "internalType": "uint112"
          },
          {
            "name": "spreadX96",
            "type": "uint112",
            "internalType": "uint112"
          },
          {
            "name": "timestamp",
            "type": "uint32",
            "internalType": "uint32"
          }
        ]
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setProtocolFee",
    "inputs": [
      {
        "name": "newFeePips",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "transferOwnership",
    "inputs": [
      {
        "name": "newOwner",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "unlockCallback",
    "inputs": [
      {
        "name": "data",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "updateQuoters",
    "inputs": [
      {
        "name": "poolIds",
        "type": "bytes32[]",
        "internalType": "PoolId[]"
      },
      {
        "name": "newQuoters",
        "type": "address[]",
        "internalType": "contract ILPQuoter[]"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "whitelisted",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "withdrawToken",
    "inputs": [
      {
        "name": "currency",
        "type": "address",
        "internalType": "Currency"
      },
      {
        "name": "amount",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "Initialized",
    "inputs": [
      {
        "name": "version",
        "type": "uint64",
        "indexed": false,
        "internalType": "uint64"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "OwnershipTransferred",
    "inputs": [
      {
        "name": "previousOwner",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "newOwner",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "AlreadyRegistered",
    "inputs": []
  },
  {
    "type": "error",
    "name": "BadQuoteInput",
    "inputs": []
  },
  {
    "type": "error",
    "name": "BadQuoteOutput",
    "inputs": []
  },
  {
    "type": "error",
    "name": "FeeTooHigh",
    "inputs": []
  },
  {
    "type": "error",
    "name": "HookNotUsed",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidInitialization",
    "inputs": []
  },
  {
    "type": "error",
    "name": "LengthMismatch",
    "inputs": []
  },
  {
    "type": "error",
    "name": "MaxLPsReached",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NoDirectLiquidity",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NoFeesToCollect",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NoQuoteAvailable",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NotInitializing",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NotRegistered",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NotWhitelisted",
    "inputs": []
  },
  {
    "type": "error",
    "name": "OnlyPoolManager",
    "inputs": []
  },
  {
    "type": "error",
    "name": "OwnableInvalidOwner",
    "inputs": [
      {
        "name": "owner",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "OwnableUnauthorizedAccount",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "PairNotRegistered",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ReentrancyGuardReentrantCall",
    "inputs": []
  }
]
"""
