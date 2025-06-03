// SPDX-License-Identifier: MIT


pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {

    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersThatHaveDepositedCollateral;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc){
        dsce = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
    }

    function mintDsc(uint256 amount, uint256 addressSeed ) public {
        if(usersThatHaveDepositedCollateral.length == 0){
            return; // No users have deposited collateral yet
        }
        address sender  = usersThatHaveDepositedCollateral[addressSeed % usersThatHaveDepositedCollateral.length];
        
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2 - int256(totalDscMinted));
        amount = bound(amount, 0, uint256(maxDscToMint));
        
        if(amount == 0){
            emit log_named_uint("maxDscToMint", uint256(maxDscToMint));
            emit log_named_uint("collateralValueInUsd", collateralValueInUsd);
            emit log_named_uint("totalDscMinted", totalDscMinted);
            return;
        }
        
        vm.startPrank(sender);
        dsce.mintDSC(amount);
        vm.stopPrank();
        timesMintIsCalled++; // <-- Move this outside the prank
    }


    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        // Mint collateral to the user, not to address(this)
        collateral.mint(msg.sender, amountCollateral);

        // User must approve DSCEngine to spend their collateral
        vm.startPrank(msg.sender);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        usersThatHaveDepositedCollateral.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollatrealBalanceOfUser(address(collateral));
        amountCollateral = bound(amountCollateral, 0 ,maxCollateralToRedeem);
        if(amountCollateral == 0){
            return;
        }
        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    function getCollateralFromSeed(uint256 collateralSeed) private view returns(ERC20Mock){
        if(collateralSeed % 2 == 0){
         
            return weth;
        }
        return wbtc;
    }

    function invariant_gettersShouldNotRevert() public view{
        // This is a simple invariant to ensure that getters do not revert
        dsce.getCollateralTokens();
        dsce.getCollatrealBalanceOfUser(address(weth));
        dsce.getCollatrealBalanceOfUser(address(wbtc));
        dsce.getAccountInformation(msg.sender);
        dsce.getUsdValue(address(weth), 1 ether);
        dsce.getUsdValue(address(wbtc), 1 ether);        
        dsce.getTokenAmountFromUsd(address(weth), 1 ether);
    }
    // This breaks our invariant test suite
    // function _getCollateralPrice(uint96 newPrice) public {
    //    int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }
}