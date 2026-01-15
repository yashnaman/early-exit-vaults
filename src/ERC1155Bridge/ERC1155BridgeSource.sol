// SPDX-License-Identifier: GPL-2.0-or-later
// SPDX license identifier specifies which open-source license is being used for the contract
pragma solidity ^0.8.20;

import {ERC1155Bridge} from "src/ERC1155Bridge/ERC1155Bridge.sol";

/// @title ERC1155 Bridge Source
/// @author @yashnaman
/// @dev Send the source ERC1155 tokens to this contract to bridge them to the destination chain.
/// After bridging, visit https://axelarscan.io/ with the transaction hash to pay the required gas for bridging.
contract ERC1155BridgeSource is ERC1155Bridge {
    constructor(
        address _gateway,
        address _sourceErc1155Token,
        address _destinationErc1155Token,
        string memory _destinationChain
    ) ERC1155Bridge(_gateway, _sourceErc1155Token, _destinationErc1155Token, _destinationChain) {}

    function _execute(uint256[] memory tokenIds, uint256[] memory amounts, address to) internal override {
        SOURCE_ERC1155_TOKEN.safeBatchTransferFrom(address(this), to, tokenIds, amounts, "");
    }
}
