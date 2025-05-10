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
    error DSCEngine__BreaksHealtFactor(uint256 healthFactor);
    error DSCEngine__MintedFailed();

    ///////////////// State Variables /////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1;


    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

   address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ////////////////// Events /////////////////
    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 amountCollateral);

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

    function depositCollateralAndMintDSC() external {}

    /**
     * @notice Follows CEI pattern (Check, Effect, Interact)
     * @param tokenCollateralAddress token address of the collateral token
     * @param amountCollateral amount of collateral to deposit
     * @notice This function is used to deposit collateral into the system.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
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
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateral() external {}

    /**
     * 
     * @param amountDscToMint amount of DSC to mint
     * @notice They must have more collatreal then the mnimum threshold
     */

    function mintDSC(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant{
        s_DSCMinted[msg.sender] += amountDscToMint;
       _revertIfHealthFactorIsBroken(msg.sender);
        // mint the DSC
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if(!minted) {
            revert DSCEngine__MintedFailed();
        }
    }

    function redeemCollateralForDSC() external {}

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    ////////////////// Private & Internal Functions ////////////////////

    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        // get the total dsc minted
        totalDscMinted = s_DSCMinted[user];
        // get the collateral value in usd
        collateralValueInUsd = getAccountCollateralValue(user);

        
    }

    /**
     * 
     * @param user address of the user
     * @return health factor of the user
     * If a user goes below a health factor of 1 , then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealtFactor(userHealthFactor);
        }
    }

    ////////////////// View & Pure Functions ////////////////////

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        
        for(uint256 i = 0; i < s_collateralTokens.length; i++){
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
           totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}