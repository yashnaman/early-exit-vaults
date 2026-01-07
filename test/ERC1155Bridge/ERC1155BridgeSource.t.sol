// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC1155BridgeSource} from "src/ERC1155Bridge/ERC1155BridgeSource.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract ERC1155BridgeSourceForkTest is Test {
    ERC1155BridgeSource internal erc1155BridgeSource;

    address internal constant AXELAR_GATEWAY_BSC = 0x304acf330bbE08d1e512eefaa92F6a57871fD895;
    address internal constant AXELAR_GATEWAY_POLYGON = 0x6f015F16De9fC8791b234eF68D486d2bF203FBA8;

    string internal bnb = "binance";
    string internal polygon = "Polygon";

    IERC1155 internal constant OPINION_ERC1155_BSC = IERC1155(0xAD1a38cEc043e70E83a3eC30443dB285ED10D774);

    function setUp() public {
        vm.createSelectFork(vm.envString("BSC_RPC_URL"));

        erc1155BridgeSource =
            new ERC1155BridgeSource(AXELAR_GATEWAY_BSC, address(OPINION_ERC1155_BSC), address(1), polygon);
    }

    function _test_transfer_opinion_tokens() public {
        uint256 opinionTokenId = 73032218533883501840491186035840211294006503910193843191671845582502015322254;
        address tokenIdHolder = 0x8A7f538B6f6Bdab69edD0E311aeDa9214bC5384A;

        vm.startPrank(tokenIdHolder);
        OPINION_ERC1155_BSC.safeTransferFrom(tokenIdHolder, address(erc1155BridgeSource), opinionTokenId, 1, "");
        vm.stopPrank();
    }

    function _test_execute_BSC() public {
        vm.startPrank(AXELAR_GATEWAY_BSC);

        bytes32 commandId = 0xadcd9048eb55eb037935e3466202f92cb267b58f7beef6a561c7b741a009cb4b;
        string memory sourceChain = "Polygon";
        string memory sourceAddress = "0x33b9c567B0F6E295b5a1e79CfCd783C51AECdb67";
        bytes memory payload =
            hex"0000000000000000000000008a7f538b6f6bdab69edd0e311aeda9214bc5384a000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000001a176c555d7a00a57f8edd76caf6c6c5a1fae20febf7103855c7eb974a064c88e00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000";

        ERC1155BridgeSource(0x33b9c567B0F6E295b5a1e79CfCd783C51AECdb67)
            .execute(commandId, sourceChain, sourceAddress, payload);
    }
}
