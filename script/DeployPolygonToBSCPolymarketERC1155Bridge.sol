// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1155BridgeSource} from "src/ERC1155Bridge/ERC1155BridgeSource.sol";
import {ERC1155BridgeReceiver} from "src/ERC1155Bridge/ERC1155BridgeReceiver.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface ICREATE3Factory {
    function deploy(bytes32 salt, bytes memory creationCode) external payable returns (address deployed);
    function getDeployed(address deployer, bytes32 salt) external view returns (address deployed);
}

contract DeployERC1155Bridge is Script {
    address internal constant AXELAR_GATEWAY_BSC = 0x304acf330bbE08d1e512eefaa92F6a57871fD895;
    address internal constant AXELAR_GATEWAY_POLYGON = 0x6f015F16De9fC8791b234eF68D486d2bF203FBA8;

    ICREATE3Factory internal constant CREATE3_FACTORY = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    string internal bnb = "binance";
    string internal Polygon = "Polygon";

    address internal constant OPINION_ERC1155_BSC = 0xAD1a38cEc043e70E83a3eC30443dB285ED10D774;
    address internal constant POLYMARKET_ERC1155_POLYGON = 0x4D97DCd97eC945f40cF65F87097ACe5EA0476045;

    bytes32 constant SALT = keccak256(abi.encodePacked("early exit vault bridge", uint256(1)));

    function run() external {
        vm.createSelectFork(vm.envString("BSC_RPC_URL"));

        address sourceAndReceiverAddresses = CREATE3_FACTORY.getDeployed(msg.sender, SALT);

        // new ERC1155BridgeSource(
        //     AXELAR_GATEWAY_POLYGON,
        //     POLYMARKET_ERC1155_POLYGON,
        //     sourceAndReceiverAddresses,
        //     bnb
        // );

        // new ERC1155BridgeReceiver(
        //     AXELAR_GATEWAY_BSC,
        //     sourceAndReceiverAddresses,
        //     Polygon,
        //     ""
        // );

        vm.createSelectFork(vm.envString("POLYGON_RPC_URL"));
        vm.startBroadcast();

        address bscBridgeSource = CREATE3_FACTORY.deploy(
            SALT,
            abi.encodePacked(
                type(ERC1155BridgeSource).creationCode,
                abi.encode(AXELAR_GATEWAY_POLYGON, POLYMARKET_ERC1155_POLYGON, sourceAndReceiverAddresses, bnb)
            )
        );

        require(bscBridgeSource == sourceAndReceiverAddresses, "Deployed address mismatch");

        vm.stopBroadcast();

        vm.createSelectFork(vm.envString("BSC_RPC_URL"));

        vm.startBroadcast();

        address polygonBridgeReceiver = CREATE3_FACTORY.deploy(
            SALT,
            abi.encodePacked(
                type(ERC1155BridgeReceiver).creationCode,
                abi.encode(AXELAR_GATEWAY_BSC, sourceAndReceiverAddresses, Polygon, "https://metadata.pokvault.xyz/")
            )
        );

        require(polygonBridgeReceiver == sourceAndReceiverAddresses, "Deployed address mismatch");
        vm.stopBroadcast();

        vm.createSelectFork(vm.envString("POLYGON_RPC_URL"));
        vm.startBroadcast();

        // safeTransferFrom
        IERC1155(POLYMARKET_ERC1155_POLYGON).safeTransferFrom(msg.sender, sourceAndReceiverAddresses, 1, 0, "");

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokenIds[0] = 1;
        amounts[0] = 0;

        IERC1155(POLYMARKET_ERC1155_POLYGON)
            .safeBatchTransferFrom(msg.sender, sourceAndReceiverAddresses, tokenIds, amounts, abi.encode(address(1)));

        vm.stopBroadcast();
    }
}
