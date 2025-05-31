//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;

    address USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /////////////// Constructor Tests /////////////
    address[] public tokenAddresses;
    address[] public priceFeedsAddresses;

    function testRevertsIfTokenLengthDoesntMatchPricefeedsLength() public {
        tokenAddresses.push(weth);
        priceFeedsAddresses.push(ethUsdPriceFeed);
        priceFeedsAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPricefeedAddressMustBeTheSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedsAddresses, address(dsc));
    }

    function testContractInitializesWithCorrectAddresses() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedsAddresses.push(ethUsdPriceFeed);
        priceFeedsAddresses.push(btcUsdPriceFeed);

        DSCEngine newEngine = new DSCEngine(tokenAddresses, priceFeedsAddresses, address(dsc));

        assertEq(newEngine.getTokenPriceFeed(weth), ethUsdPriceFeed);
        assertEq(newEngine.getTokenPriceFeed(wbtc), btcUsdPriceFeed);
    }

    /////////////// Price Tests ////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /////////////// Deposit Collateral Tests ////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NeedsMoreThanZero.selector));
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("Ran", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedTotalUsdMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalUsdMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    /////////////// Withdraw Collateral Tests ////////////////
    function testRevertsIfCollateralRedemptionIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NeedsMoreThanZero.selector));
        engine._redeemCollateral(weth, 0, USER, USER);
        vm.stopPrank();
    }

    function testRevertsIfCollateralIsUnapprovedToken() public {
        ERC20Mock ranToken = new ERC20Mock("Ran", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine._redeemCollateral(address(ranToken), AMOUNT_COLLATERAL, USER, USER);
        vm.stopPrank();
    }

    function testSuccessfullyRedeemCollateral() public depositCollateral {
        uint256 startingBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 expectedBalance = startingBalance + AMOUNT_COLLATERAL;
        engine._redeemCollateral(weth, AMOUNT_COLLATERAL, USER, USER);
        assertEq(ERC20Mock(weth).balanceOf(USER), expectedBalance);
    }

    //////////////// Mint Dsc Tests ////////////////

    // Test successful DSC minting
    function testMintDSC() public depositCollateral {
        uint256 MINT_AMOUNT = 10e18;
        vm.startPrank(USER);
        engine.mintDSC(MINT_AMOUNT);
        (uint256 userMintedAmount,) = engine.getAccountInformation(USER);
        assertEq(userMintedAmount, MINT_AMOUNT);
        vm.stopPrank();
    }

    // Test minting breaks health factor
    function testCannotMintBrokenHealthFactor() public {
        // Mint an excessive amount that breaks health factor
        uint256 MINT_AMOUNT = 1000e18;
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSignature("DSCEngine__BreaksHealthFactor(uint256)", 0));
        engine.mintDSC(MINT_AMOUNT);
        vm.stopPrank();
    }

    // Zero Minting: Ensure the function reverts if the mint amount is zero.
    function testRevertsIfMintingZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NeedsMoreThanZero.selector));
        engine.mintDSC(0);
        vm.stopPrank();
    }

    ////////////////// Burn Dsc Tests ////////////////

    // Zero Burning: Ensure the function reverts if the burn amount is zero.
    function testRevertsIfBurningZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NeedsMoreThanZero.selector));
        engine.burnDSC(0);
        vm.stopPrank();
    }

    // // Successful Burning: Verify that DSC burning updates the user's balance and emits the correct event.
    // function testBurnDSC() public depositCollateral {
    //     uint256 MINT_AMOUNT = 10e18;
    //     vm.startPrank(USER);
    //     engine.mintDSC(MINT_AMOUNT);
    //     dsc.approve(address(engine), MINT_AMOUNT);
    //     engine.burnDSC(MINT_AMOUNT);
    //     (uint256 userMintedAmount,) = engine.getAccountInformation(USER);
    //     assertEq(userMintedAmount, 0);
    //     vm.stopPrank();
    // }

    ////////////////// Liquidation Tests ////////////////

        function testRevertsIfHealthFactorIsNotBroken() public depositCollateral {
        uint256 MINT_AMOUNT = 5e18;
        vm.startPrank(USER);
        engine.mintDSC(MINT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(address(this)); // Liquidator
        vm.expectRevert(DSCEngine.DSCEngine__HealtFactorOK.selector);
        engine.liquidate(weth, USER, MINT_AMOUNT / 2);
        vm.stopPrank();
    }

    
 
}
