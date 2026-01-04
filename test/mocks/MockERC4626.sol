// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC4626 is ERC4626 {
    constructor(ERC20 asset) ERC4626(asset) ERC20("Mock Vault", "MV") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
