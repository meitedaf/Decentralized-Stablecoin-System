// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "src/libraries/OraclesLib.sol";

contract DSCEngineTest is Test {
    using OracleLib for AggregatorV3Interface;

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address wethPriceFeed;
    address wbtcPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (wethPriceFeed, wbtcPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenAddressesLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(wethPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetUsdValue() public view {
        uint256 ethAmount = 5e18;
        // 2000 * 5e18 = 15000e18
        uint256 expectedUsd = 10000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether; // ether does not represent the actual amount of ETH, but is a shortcut used in Solidity to magnify the value by a factor of 10^{18}. Actually, what this code means is to set usdAmount to 100 * 10^{18}
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ft = new ERC20Mock("FakeToken", "FT", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(ft), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testIsAllowedToken() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(0), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralValueInUsd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(totalCollateralValueInUsd, expectedCollateralValueInUsd);
    }

    function testDepositCollateralWithoutMint() public depositedCollateral {
        uint256 actualDscMinted = dsc.balanceOf(USER);
        uint256 expectedDscMinted = 0;
        assertEq(actualDscMinted, expectedDscMinted);
    }

    // this test needs it's own setup
    function testRevertsIfTransferFromFails() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.startPrank(owner);
        MockFailedTransferFrom mockWeth = new MockFailedTransferFrom();
        DecentralizedStableCoin mockDsc = new DecentralizedStableCoin();
        tokenAddresses = [address(mockWeth)];
        priceFeedAddresses = [wethPriceFeed];
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockWeth.mint(USER, AMOUNT_COLLATERAL);
        mockDsc.transferOwnership(address(mockDscEngine));
        vm.stopPrank();
        // Arrange - User
        vm.startPrank(USER);
        mockWeth.approve(address(mockDscEngine), AMOUNT_COLLATERAL);
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.depositCollateral(address(mockWeth), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                   DEPOSITCOLLATERALANDMINTDSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertIfMintedDscBreakHealthFactor() public {
        (, int256 wethPrice,,,) = AggregatorV3Interface(wethPriceFeed).staleCheckLatestRoundData();
        uint256 amountToMint =
            (AMOUNT_COLLATERAL * uint256(wethPrice) * dscEngine.getAdditionalFeedPrecision()) / dscEngine.getPrecision();
        uint256 expectHealthFactor =
            dscEngine.calculateHealthFactor(amountToMint, dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL));
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectHealthFactor));
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    modifier depositCollateralAndMintDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testDepositCollateralAndMintDsc() public depositCollateralAndMintDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assert(userBalance == AMOUNT_TO_MINT);
    }

    /*//////////////////////////////////////////////////////////////
                             MINTDSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfMintFails() public {}

    /*//////////////////////////////////////////////////////////////
                        REDEEM COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfTransferFailed() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.startPrank(owner);
        MockFailedTransfer mockWeth = new MockFailedTransfer();
        DecentralizedStableCoin mockDsc = new DecentralizedStableCoin();
        tokenAddresses = [address(mockWeth)];
        priceFeedAddresses = [wethPriceFeed];
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockWeth.mint(USER, AMOUNT_COLLATERAL);
        mockDsc.transferOwnership(address(mockDscEngine));
        vm.stopPrank();
        // Arrange -USER
        vm.startPrank(USER);
        ERC20Mock(address(mockWeth)).approve(address(mockDscEngine), AMOUNT_COLLATERAL);
        mockDscEngine.depositCollateral(address(mockWeth), AMOUNT_COLLATERAL);
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.redeemCollateral(address(mockWeth), AMOUNT_COLLATERAL);
    }

    function testRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        assert(dsc.balanceOf(USER) == 0);
    }
}
