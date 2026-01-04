// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EarlyExitVault} from "src/EarlyExitVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract DeployEarlyExitVault is Script {
    function run() external {
        // Load environment variables
        address assetAddress = vm.envAddress("ASSET_ADDRESS");
        address underlyingVaultAddress = vm.envAddress("UNDERLYING_VAULT_ADDRESS");
        string memory vaultName = vm.envString("VAULT_NAME");
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");

        vm.startBroadcast();

        IERC20 asset = IERC20(assetAddress);
        IERC4626 underlyingVault = IERC4626(underlyingVaultAddress);

        EarlyExitVault earlyExitVault = new EarlyExitVault(asset, underlyingVault, vaultName, vaultSymbol);

        vm.stopBroadcast();

        // Log the deployed address
        console.log("EarlyExitVault deployed at:", address(earlyExitVault));
    }
}