// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions
 
// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity 0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
/**
 * @title DSCEngine
 * @author Tebbo
 * The system is desgned to be minimal , and to have tokens maintain a pegged value of 1 token == 1 USD
 * The stab;ecoin as the properties
 * - Exogenous
 * - Decentralized
 * - Anchored (pegged)
 * - Crypto Collateralized low volitility coin (ETH & BTC)
 * - Minting: Algorithmic
 * - Relative Stability: Pegged to USD
 * @notice This contract is the core of the DSC system. It is responsible for the minting and burning of the Decentralized Stable Coin (DSC).
 * @notice This contract is loosly based on the MakerDao system (DAI)
 */
contract DSCEngine is ReentrancyGuard {
    ////////////////// Errors /////////////////

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPricefeedAddressMustBeTheSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintedFailed();
    error DSCEngine__HealtFactorOK();
    error DSCEngine__HealtFactorNotImproved();

    ////////////////// Type Declarations /////////////////
    using OracleLib for AggregatorV3Interface;



    ///////////////// State Variables /////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1;
     uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidating a user

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ////////////////// Events /////////////////
    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 amountCollateral);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    ///////////////// modifiers /////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        // check if the token is allowed
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ////////////////// Functions ////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // constructor code
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPricefeedAddressMustBeTheSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////// External Functions ////////////////////
    /**
     *
     * @param tokenCollateralAddress token address of the collateral token
     * @param amountCollateral Amount of collateral to deposit
     * @param amountDscToMint  Amount of DSC to mint
     * @notice This function is used to deposit collateral and mint DSC in one transaction.
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /**
     * @notice Follows CEI pattern (Check, Effect, Interact)
     * @param tokenCollateralAddress token address of the collateral token
     * @param amountCollateral amount of collateral to deposit
     * @notice This function is used to deposit collateral into the system.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // update the collateral deposited mapping
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        // emit the event
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        // transfer the collateral token to the contract
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        nonReentrant
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param amountDscToMint amount of DSC to mint
     * @notice They must have more collatreal then the mnimum threshold
     */
    function mintDSC(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        // mint the DSC
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintedFailed();
        }
    }

    /**
     * @notice This function is used to redeem collateral and burn DSC in one transaction.
     * @param tokenCollateralAddress token address of the collateral token
     * @param amountCollateral amount of collateral to redeem
     * @param amountDscToBurn amount of DSC to burn
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) nonReentrant {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // I dont think this is ever hit??
    }

    /**
     * @notice This function is used to liquidate a user.
     * @notice you can partially liquidate a user
     * @notice You will get a bonus for liquidating a users position
     * @param collateral token address of the collateral token
     * @param user address of the user to liquidate, the user who has a broken helath factor - Their HEALTHFACTOR is below MINIMUM_HEALTH_FACTOR
     * @param debtToCover amount of debt to cover
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // get the health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        console.log("Starting User Health Factor from DSCEngine contract :", startingUserHealthFactor);
        // check if the user is liquidatable
        if (startingUserHealthFactor >= MINIMUM_HEALTH_FACTOR) {
        // if (startingUserHealthFactor >= MINIMUM_HEALTH_FACTOR * PRECISION) {
            revert DSCEngine__HealtFactorOK();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        //give the liquidator a bonus of 10%
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        // burn the dsc
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        console.log("Ending User Health Factor from DSCEngine contract :", endingUserHealthFactor);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealtFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }


        function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    )
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }


        function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ////////////////// Private & Internal Functions ////////////////////
    /**
     * @notice This function is used to burn DSC.
     * @param amountDscTOBurn amount of DSC to burn
     * @param onBehalfOf address of the user to burn DSC for
     * @param dscFrom address of the user to burn DSC from
     * @dev Low-level internal function to burn DSC, do not call unless the function calling is checking for the health factor being broken..
     */
    function _burnDsc(uint256 amountDscTOBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscTOBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscTOBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscTOBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        public
    {
        if (amountCollateral == 0) {
        revert DSCEngine__NeedsMoreThanZero();
    }
        // check if the token is allowed
        if (s_priceFeeds[tokenCollateralAddress] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        // update the collateral deposited mapping
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        // emit the event
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        // transfer the collateral token to the user
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        // _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        // get the total dsc minted
        totalDscMinted = s_DSCMinted[user];
        // get the collateral value in usd
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     *
     * @param user address of the user
     * @return health factor of the user
     * If a user goes below a health factor of 1 , then they can be liquidated.
     */
    // function _healthFactor(address user) private view returns (uint256) {
    //     (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
    //     uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
    //     return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    // }

    
        function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ////////////////// View & Pure Functions ////////////////////

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (ADDITIONAL_FEED_PRECISION * uint256(price));
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user) public view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
        return (totalDscMinted, collateralValueInUsd);
    }

    function getTokenPriceFeed(address token) public view returns (address) {
        return s_priceFeeds[token];
    }

    function getLiquidationBonus() public pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }
    function getLiquidationPrecision() public pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _healthFactor(user);
    }

    function getMinimumHealthFactor() public pure returns (uint256) {
        return MINIMUM_HEALTH_FACTOR;
    }

    //////
        function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }


    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getCollatrealBalanceOfUser(address collateral) public view returns(uint256){
        return s_collateralDeposited[msg.sender][collateral];
    }
}
