// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Handler} from "./Handler.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Invariant is Test {

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;

    address USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(engine, dsc);
        targetContract(address(handler));

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), STARTING_ERC20_BALANCE);
        ERC20Mock(weth).approve(address(handler), STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).approve(address(handler), STARTING_ERC20_BALANCE);
        vm.stopPrank();
    }


    function invariant_protocolMustHaveMoreValueThanSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposied = IERC20(weth).balanceOf(address(engine));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposied);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalBtcDeposited);

        assert(wethValue + wbtcValue >= totalSupply);
    }
}