// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IGetEarlyExitAmount {
    enum ActionType {
        MERGE,
        SPLIT
    }
    function getEarlyExitAmount(IERC1155, uint256, IERC1155, uint256, uint256 amount, ActionType action)
        external
        view
        returns (uint256);
}
