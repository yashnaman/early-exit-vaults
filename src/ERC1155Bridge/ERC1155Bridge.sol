// SPDX-License-Identifier: GPL-2.0-or-later
// SPDX license identifier specifies which open-source license is being used for the contract
pragma solidity ^0.8.20;

// Importing external contracts for dependencies
import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/interfaces/IERC1155Receiver.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {
    AddressToString,
    StringToAddress
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressString.sol";

abstract contract ERC1155Bridge is AxelarExecutable, ERC165, IERC1155Receiver {
    error InvalidSourceChain(string provided, string expected);
    error InvalidSourceAddress(address provided, address expected);
    error InvalidTokenSender(address provided, address expected);

    string public destinationChain;
    address public immutable DESTINATION_ERC1155_TOKEN;

    IERC1155 public immutable SOURCE_ERC1155_TOKEN;

    //@dev "to" is the address that will receive the bridged tokens
    event ERC1155SingleReceived(address indexed from, address indexed to, uint256 id, uint256 amount);
    event ERC1155BatchReceived(address indexed from, address indexed to, uint256[] ids, uint256[] amounts);

    constructor(
        address _gateway,
        address _sourceErc1155Token,
        address _destinationErc1155Token,
        string memory _destinationChain
    ) AxelarExecutable(_gateway) {
        SOURCE_ERC1155_TOKEN = IERC1155(_sourceErc1155Token);
        DESTINATION_ERC1155_TOKEN = _destinationErc1155Token;
        destinationChain = _destinationChain;
    }

    function _execute(uint256[] memory tokenIds, uint256[] memory amounts, address to) internal virtual;

    function _execute(
        bytes32,
        /*commandId*/
        string calldata sourceChain_,
        string calldata sourceAddress_,
        bytes calldata payload_
    ) internal override {
        // gateway.validateContractCall(commandId, sourceChain_, sourceAddress_, payload_); will make sure destination chain and address are correct
        // we make sure source chain and address are correct
        require(
            keccak256(bytes(sourceChain_)) == keccak256(bytes(destinationChain)),
            InvalidSourceChain(sourceChain_, destinationChain)
        );
        address sourceAddr = StringToAddress.toAddress(sourceAddress_);
        require(sourceAddr == DESTINATION_ERC1155_TOKEN, InvalidSourceAddress(sourceAddr, DESTINATION_ERC1155_TOKEN));
        (address to, uint256[] memory tokenIds, uint256[] memory amounts) =
            abi.decode(payload_, (address, uint256[], uint256[]));
        _execute(tokenIds, amounts, to);
    }

    function bridgeERC1155Tokens(address to, uint256[] memory tokenIds, uint256[] memory amounts) internal {
        // Encodes the new value string into bytes, which can be sent to the Axelar gateway contract
        bytes memory payload = abi.encode(to, tokenIds, amounts);

        // Calls the Axelar gateway contract with the specified destination chain and address, and sends the payload along with the call
        gateway().callContract(destinationChain, AddressToString.toString(DESTINATION_ERC1155_TOKEN), payload);
    }

    function onERC1155Received(address, address from, uint256 tokenId, uint256 amount, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        // caller should be SOURCE_ERC1155_TOKEN
        require(
            msg.sender == address(SOURCE_ERC1155_TOKEN), InvalidTokenSender(msg.sender, address(SOURCE_ERC1155_TOKEN))
        );

        //by default, the bridged tokens are sent to the `from` address
        //if data contains a 20-byte address, use that as the `to` address
        address to = data.length == 20 ? abi.decode(data, (address)) : from;

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokenIds[0] = tokenId;
        amounts[0] = amount;

        bridgeERC1155Tokens(to, tokenIds, amounts);

        emit ERC1155SingleReceived(from, to, tokenId, amount);

        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        bytes calldata data
    ) external override returns (bytes4) {
        require(
            msg.sender == address(SOURCE_ERC1155_TOKEN), InvalidTokenSender(msg.sender, address(SOURCE_ERC1155_TOKEN))
        );
        address to = data.length == 20 ? abi.decode(data, (address)) : from;
        bridgeERC1155Tokens(to, tokenIds, amounts);

        emit ERC1155BatchReceived(from, to, tokenIds, amounts);

        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }
}
