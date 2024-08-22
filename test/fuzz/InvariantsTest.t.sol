// SPDX-License-Identifier: MIT
// What are our invariants?

// 1.The total supply of DSC should always be less than the total value of collateral
// 2.Getter view functions should never be revert <-- evergreen invariant

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DSCEngine public dscEngine;
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    HelperConfig public config;
    address public weth;
    address public wbtc;
    Handler public handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(dscEngine));
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // Get the value of all the collateral in the protocol
        // Compare it to all the debt(dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);
        uint256 totalValue = wethValue + wbtcValue;

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("total supply: ", totalSupply);
        console.log("Times mint() called: ", handler.timesMintIsCalled());
        console.log("Times redeemCollateral() called: ", handler.timesRedeemCollateralIsCalled());

        assert(totalSupply <= totalValue);
    }

    function Invariant_gettersShouldNotRevert() public {
        // all the DSCEngine getter functions
    }
}
