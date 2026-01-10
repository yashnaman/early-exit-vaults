// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EarlyExitAmountBasedOnFixedAPY, EarlyExitAmountFactoryBasedOnFixedAPY} from "src/EarlyExitAmount.sol";
import {IGetEarlyExitAmount} from "src/interface/IGetEarlyExitAmount.sol";

contract EarlyExitAmountTest is Test {
    EarlyExitAmountBasedOnFixedAPY earlyExitAmount;
    EarlyExitAmountFactoryBasedOnFixedAPY factory;

    uint256 marketExpiryTime = block.timestamp + 365 days;
    uint256 expectedApy = 500; // 5%

    uint256 constant BASIS_POINTS = 10_000;
    uint256 constant SECONDS_IN_YEAR = 365 days;

    function setUp() public {
        factory = new EarlyExitAmountFactoryBasedOnFixedAPY();
        earlyExitAmount = factory.createEarlyExitAmountContract(marketExpiryTime, expectedApy, 1 days);
    }

    function testConstructor() public view {
        assertEq(earlyExitAmount.MARKET_EXPIRY_TIME(), marketExpiryTime);
        assertEq(earlyExitAmount.EXPECTED_APY(), expectedApy);
    }

    function testGetEarlyExitAmount() public view {
        uint256 amount = 1000;
        uint256 remainingTime = marketExpiryTime - block.timestamp;
        uint256 expectedFee =
            Math.mulDiv(amount, expectedApy * remainingTime, BASIS_POINTS * SECONDS_IN_YEAR, Math.Rounding.Ceil);
        uint256 expectedExitAmount = amount - expectedFee;

        uint256 exitAmount = earlyExitAmount.getEarlyExitAmount(
            IERC1155(address(0)), 0, IERC1155(address(0)), 0, amount, IGetEarlyExitAmount.ActionType.MERGE
        );
        assertEq(exitAmount, expectedExitAmount);
    }

    function testGetEarlyExitAmountAfterExpiry() public {
        vm.warp(marketExpiryTime + 1);
        earlyExitAmount.getEarlyExitAmount(
            IERC1155(address(0)), 0, IERC1155(address(0)), 0, 1000, IGetEarlyExitAmount.ActionType.MERGE
        );
    }

    function testFactoryCreate() public {
        EarlyExitAmountBasedOnFixedAPY newContract =
            factory.createEarlyExitAmountContract(marketExpiryTime + 100, 1000, 1 days);
        assertEq(newContract.MARKET_EXPIRY_TIME(), marketExpiryTime + 100);
        assertEq(newContract.EXPECTED_APY(), 1000);
    }

    function testFuzzGetEarlyExitAmount(uint256 amount) public view {
        vm.assume(amount > 0 && amount < 1e18);
        uint256 exitAmount = earlyExitAmount.getEarlyExitAmount(
            IERC1155(address(0)), 0, IERC1155(address(0)), 0, amount, IGetEarlyExitAmount.ActionType.SPLIT
        );
        assertLe(exitAmount, amount);
        // Check that fee is correctly calculated
        uint256 remainingTime = marketExpiryTime - block.timestamp;
        uint256 expectedFee =
            Math.mulDiv(amount, expectedApy * remainingTime, BASIS_POINTS * SECONDS_IN_YEAR, Math.Rounding.Ceil);
        assertEq(exitAmount, amount - expectedFee);
    }
}
