// SPDX-License-Identifier: MIT
// SPDX license identifier specifies which open-source license is being used for the contract
pragma solidity ^0.8.20;

import {ERC1155Bridge} from "src/ERC1155Bridge/ERC1155Bridge.sol";

// Contract definition and name
contract ERC1155BridgeSource is ERC1155Bridge {
    constructor(
        address _gateway,
        address _gasReceiver,
        address _sourceErc1155Token,
        string memory _destinationErc1155Token,
        string memory _sourceChain,
        string memory _destinationChain
    )
        ERC1155Bridge(
            _gateway, _gasReceiver, _sourceErc1155Token, _destinationErc1155Token, _sourceChain, _destinationChain
        )
    {}

    function _execute(uint256[] memory tokenIds, uint256[] memory amounts, address to) internal override {
        SOURCE_ERC1155_TOKEN.safeBatchTransferFrom(address(this), to, tokenIds, amounts, "");
    }
}
