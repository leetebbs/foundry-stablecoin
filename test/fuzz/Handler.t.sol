// SPDX-License-Identifier: MIT


pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {

    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc){
        dsce = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }


    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // require(amountCollateral <= 1000 ether, "Amount too large");
        ERC20Mock collateral = getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        collateral.mint(address(this), amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        // vm.startPrank(msg.sender);
        // collateral.mint(msg.sender, amountCollateral);
        // collateral.approve(address(collateral), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        // vm.stopPrank;
        
    }

    function getCollateralFromSeed(uint256 collateralSeed) private view returns(ERC20Mock){
        if(collateralSeed % 2 == 0){
         
            return weth;
        }
        return wbtc;
    }
}