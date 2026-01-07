// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1155BridgeSource} from "src/ERC1155Bridge/ERC1155BridgeSource.sol";

contract DeployERC1155Bridge is Script {
    function run() external {
        // Load environment variables or set defaults
        address gateway = vm.envOr("AXELAR_GATEWAY", address(0x123)); // Replace with actual gateway address for the chain
        address sourceERC1155Token = vm.envAddress("SOURCE_ERC1155_TOKEN");
        address destinationERC1155Token = vm.envAddress("DESTINATION_ERC1155_TOKEN");
        string memory sourceChain = vm.envString("SOURCE_CHAIN");
        string memory destinationChain = vm.envString("DESTINATION_CHAIN");

        vm.startBroadcast();

        // Deploy the ERC1155BridgeSource contract
        ERC1155BridgeSource bridge = new ERC1155BridgeSource(
            gateway,
            sourceERC1155Token,
            destinationERC1155Token,
            sourceChain,
            destinationChain
        );

        vm.stopBroadcast();

        // Log the deployed address
        console.log("ERC1155BridgeSource deployed at:", address(bridge));
    }
}