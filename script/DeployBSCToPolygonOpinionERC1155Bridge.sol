// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1155BridgeSource} from "src/ERC1155Bridge/ERC1155BridgeSource.sol";
import {ERC1155BridgeReceiver} from "src/ERC1155Bridge/ERC1155BridgeReceiver.sol";

interface ICREATE3Factory {
    /// @notice Deploys a contract using CREATE3
    /// @dev The provided salt is hashed together with msg.sender to generate the final salt
    /// @param salt The deployer-specific salt for determining the deployed contract's address
    /// @param creationCode The creation code of the contract to deploy
    /// @return deployed The address of the deployed contract
    function deploy(bytes32 salt, bytes memory creationCode) external payable returns (address deployed);

    /// @notice Predicts the address of a deployed contract
    /// @dev The provided salt is hashed together with the deployer address to generate the final salt
    /// @param deployer The deployer account that will call deploy()
    /// @param salt The deployer-specific salt for determining the deployed contract's address
    /// @return deployed The address of the contract that will be deployed
    function getDeployed(address deployer, bytes32 salt) external view returns (address deployed);
}

contract DeployERC1155Bridge is Script {
    address internal constant AXELAR_GATEWAY_BSC = 0x304acf330bbE08d1e512eefaa92F6a57871fD895;
    address internal constant AXELAR_GATEWAY_POLYGON = 0x6f015F16De9fC8791b234eF68D486d2bF203FBA8;

    ICREATE3Factory internal constant CREATE3_FACTORY = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    string internal bnb = "binance";
    string internal polygon = "polygon";

    address internal constant OPINION_ERC1155_BSC = 0x2C5D8C7C8Db3F4E3dBEF5e8a2d1E3b3F4f5e6a7B;

    bytes32 constant SALT = keccak256(abi.encodePacked("early exit vault", uint256(1)));

    function run() external {
        vm.createSelectFork(vm.envString("BSC_RPC_URL"));

        address sourceAndReceiverAddresses = CREATE3_FACTORY.getDeployed(msg.sender, SALT);

        // new ERC1155BridgeSource(
        //     AXELAR_GATEWAY_BSC,
        //     OPINION_ERC1155_BSC,
        //     sourceAndReceiverAddresses,
        //     polygon
        // );

        // new ERC1155BridgeReceiver(
        //     AXELAR_GATEWAY_POLYGON,
        //     sourceAndReceiverAddresses,
        //     bnb,
        //     ""
        // );

        vm.startBroadcast();    

        address bscBridgeSource = CREATE3_FACTORY.deploy(
            SALT,
            abi.encodePacked(
                type(ERC1155BridgeSource).creationCode,
                abi.encode(AXELAR_GATEWAY_BSC, OPINION_ERC1155_BSC, sourceAndReceiverAddresses, polygon)
            )
        );

        require(bscBridgeSource == sourceAndReceiverAddresses, "Deployed address mismatch");

        vm.stopBroadcast();

        vm.createSelectFork(vm.envString("POLYGON_RPC_URL"));

        vm.startBroadcast();    

        address polygonBridgeReceiver = CREATE3_FACTORY.deploy(
            SALT,
            abi.encodePacked(
                type(ERC1155BridgeReceiver).creationCode,
                abi.encode(AXELAR_GATEWAY_POLYGON, sourceAndReceiverAddresses, bnb, "") // add the right tokenURI here
            )
        );

        require(polygonBridgeReceiver == sourceAndReceiverAddresses, "Deployed address mismatch");

        vm.stopBroadcast();
    }
}
