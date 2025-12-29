// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IGetEarlyExitAmount {
    function getEarlyExitAmount(IERC1155, uint256, IERC1155, uint256, uint256 amount) external view returns (uint256);
}
