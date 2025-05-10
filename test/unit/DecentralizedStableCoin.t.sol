// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin dsc;
    address owner = address(this);
    address nonOwner = address(0x123);

    function setUp() public {
        dsc = new DecentralizedStableCoin();
    }

    function testInitialState() public view{
        assertEq(dsc.name(), "Decentralized Stable Coin");
        assertEq(dsc.symbol(), "DSC");
    }

    function testMintRevertsIfToIsZeroAddress() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        dsc.mint(address(0), 100);
    }

    function testMintRevertsIfAmountIsZero() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeMoreThanZero.selector);
        dsc.mint(owner, 0);
    }

    function testMintWorks() public {
        dsc.mint(owner, 100);
        assertEq(dsc.balanceOf(owner), 100);
    }

    function testMintRevertsIfNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        dsc.mint(nonOwner, 100);
    }

    function testBurnRevertsIfAmountExceedsBalance() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmmountExceedsBalance.selector);
        dsc.burn(100);
    }

    function testBurnWorks() public {
        dsc.mint(owner, 100);
        dsc.burn(50);
        assertEq(dsc.balanceOf(owner), 50);
    }

    function testBurnRevertsIfNotOwner() public {
        dsc.mint(owner, 100);
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        dsc.burn(50);
    }
}