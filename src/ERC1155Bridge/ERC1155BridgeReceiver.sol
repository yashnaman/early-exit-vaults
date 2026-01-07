// SPDX-License-Identifier: MIT
// SPDX license identifier specifies which open-source license is being used for the contract
pragma solidity ^0.8.20;

import {ERC1155Bridge} from "src/ERC1155Bridge/ERC1155Bridge.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

// Contract definition and name
contract ERC1155BridgeReceiver is ERC1155Bridge, ERC1155 {
    constructor(
        address _gateway,
        string memory _destinationErc1155Token,
        string memory _sourceChain,
        string memory _destinationChain,
        string memory uri_
    ) ERC1155(uri_) ERC1155Bridge(_gateway, address(this), _destinationErc1155Token, _sourceChain, _destinationChain) {}

    function _execute(uint256[] memory tokenIds, uint256[] memory amounts, address to) internal override {
        _mintBatch(to, tokenIds, amounts, "");
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override {
        super._update(from, to, ids, values);
        // burn the tokens if they were sent to this contract
        // onBatchReceived and onReceived would have already bridged the tokens
        if (to == address(this)) {
            _burnBatch(address(this), ids, values);
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, ERC1155Bridge) returns (bool) {
        return ERC1155.supportsInterface(interfaceId) || ERC1155Bridge.supportsInterface(interfaceId);
    }
}
