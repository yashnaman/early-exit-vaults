// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EarlyExitVault} from "src/EarlyExitVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {EarlyExitAmountFactoryBasedOnFixedAPY} from "src/EarlyExitAmount.sol";
import {console} from "forge-std/console.sol";

interface ICREATE3Factory {
    function deploy(bytes32 salt, bytes memory creationCode) external payable returns (address deployed);
    function getDeployed(address deployer, bytes32 salt) external view returns (address deployed);
}

contract DeployEarlyExitVault is Script {
    ICREATE3Factory internal constant CREATE3_FACTORY = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    function run() external {

        address assetAddress = vm.envAddress("ASSET_ADDRESS");
        address underlyingVaultAddress = vm.envAddress("UNDERLYING_VAULT_ADDRESS");
        string memory vaultName = vm.envString("VAULT_NAME");
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");

 
        bytes32 salt = keccak256(abi.encodePacked("early exit vault beta - vault", uint256(1)));

        vm.startBroadcast();

        IERC20 asset = IERC20(assetAddress);
        IERC4626 underlyingVault = IERC4626(underlyingVaultAddress);

        // new EarlyExitVault(
        //     asset,
        //     underlyingVault,
        //     vaultName,
        //     vaultSymbol
        // );

        address vaultAddress = CREATE3_FACTORY.deploy(
            salt,
            abi.encodePacked(
                type(EarlyExitVault).creationCode,
                abi.encode(asset, underlyingVault, vaultName, vaultSymbol)
            )
        );

        EarlyExitVault earlyExitVault = EarlyExitVault(vaultAddress);
        EarlyExitAmountFactoryBasedOnFixedAPY earlyExitAmountFactory = new EarlyExitAmountFactoryBasedOnFixedAPY();

        vm.stopBroadcast();

        // Log the deployed addresses
        console.log("EarlyExitVault deployed at:", vaultAddress);
        console.log("EarlyExitAmountFactoryBasedOnFixedAPY deployed at:", address(earlyExitAmountFactory));
    }
}
