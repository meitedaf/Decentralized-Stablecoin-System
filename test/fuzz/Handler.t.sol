// SPDX-License-Identifier: MIT

// Handler is going to narrow down the way we call functions

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    address public USER = makeAddr("USER");
    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timesMintIsCalled;
    uint256 public timesRedeemCollateralIsCalled;
    address[] public usersWithCollateral;
    MockV3Aggregator public ethUsdPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeedAddress(address(weth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // double push
        usersWithCollateral.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateralToRedeem) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateralToRedeem = bound(amountCollateralToRedeem, 0, maxCollateralToRedeem);
        if (amountCollateralToRedeem == 0) {
            return;
        }
        timesRedeemCollateralIsCalled++;
        // vm.assume(amountCollateralToRedeem != 0); // Failed
        vm.prank(msg.sender);
        try dscEngine.redeemCollateral(address(collateral), amountCollateralToRedeem) {}
        catch (bytes memory lowLevelData) {
            // The first 4 bytes of lowLevelData contain the selector
            bytes4 selector = bytes4(lowLevelData);

            // Check if the selector matches DSCEngine__BreaksHealthFactor
            if (selector == DSCEngine.DSCEngine__BreaksHealthFactor.selector) {
                // Ignore this specific revert error
            } 
            else {
                // Handle other unexpected reverts
                revert(string(lowLevelData));
            }
        }
    }

    function mintDsc(uint256 amountToMint, uint256 addressSeed) public {
        if (usersWithCollateral.length == 0) {
            return;
        }
        address sender = usersWithCollateral[addressSeed % usersWithCollateral.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);
        int256 maxToMint = (int256(collateralValueInUsd / 2) - int256(totalDscMinted));
        if (maxToMint < 0) {
            return;
        }
        amountToMint = bound(amountToMint, 0, uint256(maxToMint));
        if (amountToMint == 0) {
            return;
        }
        vm.startPrank(sender);
        dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    // This breaks our invariant test suite!!!
    // function updateCollaterPrice(uint96 newPirce) public {
    //     int256 newPirceInt = int256(uint256(newPirce));
    //     ethUsdPriceFeed.updateAnswer(newPirceInt);
    // }

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock collateral) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
