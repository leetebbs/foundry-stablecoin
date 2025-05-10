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

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";



/**
 * @title DecentralizedStableCoin
 * @author Tebbo
 * collateral: Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 * 
 * This contract is to be governed by DSCEngine. 
 * This contract is the ERC20 token that will be minted and burned by the DSCEngine.
 * The DSCEngine will be responsible for the minting and burning of the Decentralized Stable Coin (DSC).
 */

contract DecentralizedStableCoin is ERC20Burnable , Ownable {

    // Errors
    error DecentralizedStableCoin__not_enoughBalance();
    error DecentralizedStableCoin__BurnAmmountExceedsBalance();  
    error DecentralizedStableCoin__NotZeroAddress();
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();

    constructor() ERC20("Decentralized Stable Coin", "DSC") {
        // constructor code
    }

    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if( amount < 0 ){
            revert DecentralizedStableCoin__not_enoughBalance();
        }
        if( amount > balance ){
            revert DecentralizedStableCoin__BurnAmmountExceedsBalance();
        }
        super.burn(amount);
    }

        function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

}