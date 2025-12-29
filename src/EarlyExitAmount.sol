// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title EarlyExitAmount
 * @dev Contract that calculates the exit amount for opposite outcome token pairs
 */
contract EarlyExitAmountBasedOnFixedAPY {
    uint256 public immutable MARKET_EXPIRY_TIME;
    uint256 public immutable EXPECTED_APY; // expressed in basis points, e.g., 500 = 5%

    uint256 private constant BASIS_POINTS = 10_000;
    uint256 private constant SECONDS_IN_YEAR = 365 days;

    // If market is already expired, early exit is not allowed
    error MarketAlreadyExpired();

    constructor(uint256 _marketExpiryTime, uint256 _expectedApy) {
        MARKET_EXPIRY_TIME = _marketExpiryTime;
        EXPECTED_APY = _expectedApy;
    }

    function getEarlyExitAmount(IERC1155, uint256, IERC1155, uint256, uint256 amount) external view returns (uint256) {
        uint256 currentTime = block.timestamp;
        if (currentTime >= MARKET_EXPIRY_TIME) {
            revert MarketAlreadyExpired();
        }
        uint256 remainingTime = MARKET_EXPIRY_TIME - currentTime;
        uint256 fee =
            Math.mulDiv(amount, EXPECTED_APY * remainingTime, BASIS_POINTS * SECONDS_IN_YEAR, Math.Rounding.Ceil);
        return amount - fee;
    }
}

contract EarlyExitAmountFactoryBasedOnFixedAPY {
    function createEarlyExitAmountContract(uint256 marketExpiryTime, uint256 expectedApy)
        external
        returns (EarlyExitAmountBasedOnFixedAPY)
    {
        EarlyExitAmountBasedOnFixedAPY newContract = new EarlyExitAmountBasedOnFixedAPY(marketExpiryTime, expectedApy);
        return newContract;
    }
}
