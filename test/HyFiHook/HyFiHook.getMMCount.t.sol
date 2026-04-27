pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HyFiHookSharedSetup} from "../HyFiHookSharedSetup.sol";
import {HyFiHook} from "../../src/HyFiHook.sol";
import {SimpleQuoter} from "../../src/SimpleQuoter.sol";
import {ILPQuoter} from "../../src/interfaces/ILPQuoter.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract HyFiHookGetMMCountTest is HyFiHookSharedSetup {

    function setUp() public {
        sharedSetup();
    }

    function test_getMMCount_returnsCorrectCount() public view {
        assertEq(hook.getMMCount(poolId), 1);
    }

    function test_getMMCount_emptyPool() public view {
        PoolId unknown = PoolId.wrap(keccak256("unknown"));
        assertEq(hook.getMMCount(unknown), 0);
    }

    function test_getMMCount_afterMultipleRegistrations() public {
        address mm2 = makeAddr("mm2");
        address mm3 = makeAddr("mm3");
        hook.addToWhitelist(mm2);
        hook.addToWhitelist(mm3);
        registerMM(hook, mm2, poolId, ILPQuoter(address(deployQuoterProxy(pm, address(hook), mm2, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND))));
        registerMM(hook, mm3, poolId, ILPQuoter(address(deployQuoterProxy(pm, address(hook), mm3, DEFAULT_BASE_FEE, DEFAULT_FEE_PER_SECOND))));

        assertEq(hook.getMMCount(poolId), 3);
    }
}
