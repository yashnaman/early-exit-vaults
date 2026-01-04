// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/interfaces/IERC1155Receiver.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IGetEarlyExitAmount} from "src/interface/IGetEarlyExitAmount.sol";

/**
 * @title EarlyExitVault
 * @dev ERC4626 tokenized vault that allows arbitragers to exit early by combining opposite
 *      allowed outcome tokens. For example, on Opinion prediction market, arbitagers can buy
 *      YES outcome token of will trump win, bridge it to Polygon, combine it with NO outcome token
 *      of will trump win on PolyMarket, and get 1 USDC back immediately.
 */
contract EarlyExitVault is ERC4626, Ownable, ERC165, IERC1155Receiver {
    using SafeERC20 for IERC20;

    uint256 internal _totalAssets;

    // vault where the underlying assets are deposited when it is not being used for early exits
    IERC4626 public vault;

    // vault depositors will trust the admin of the vault to set these such that only opposite outcome tokens are allowed
    // one of the outcome should be guaranteed to be worth 1 when the market expires
    struct OppositeOutcomeTokensInfo {
        IERC1155 outcomeTokenA;
        uint256 outcomeIdA;
        IERC1155 outcomeTokenB;
        uint256 outcomeIdB;
    }

    OppositeOutcomeTokensInfo[] public allowedOppositeOutcomeTokens;
    mapping(bytes32 => bool) public isAllowedOppositeOutcomeTokenPair;
    mapping(bytes32 => IGetEarlyExitAmount) public earlyExitAmountContracts;
    mapping(bytes32 => uint256) public totalEarlyExitedAmounts;

    error VaultAssetMismatch();
    error PairAlreadyAllowed();
    error DirectTransfersNotAllowed();
    error BatchTransfersNotAllowed();

    constructor(IERC20 asset_, IERC4626 _vault, string memory name_, string memory symbol_)
        ERC4626(asset_)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        vault = _vault;
        if (_vault.asset() != address(asset_)) revert VaultAssetMismatch();
        asset_.forceApprove(address(_vault), type(uint256).max);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        vault.deposit(assets, address(this));
        _totalAssets += assets;
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        vault.withdraw(assets, address(this), address(this));
        super._withdraw(caller, receiver, owner, assets, shares);
        _totalAssets -= assets;
    }

    function _hashTokenPair(IERC1155 outcomeTokenA, uint256 outcomeIdA, IERC1155 outcomeTokenB, uint256 outcomeIdB)
        internal
        pure
        returns (bytes32 pairHash)
    {
        pairHash = keccak256(abi.encodePacked(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB));
    }

    function _hashTokenInfo(OppositeOutcomeTokensInfo memory tokenInfo) internal pure returns (bytes32 pairHash) {
        pairHash = keccak256(abi.encodePacked(tokenInfo.outcomeTokenA, tokenInfo.outcomeIdA, tokenInfo.outcomeTokenB, tokenInfo.outcomeIdB));
    }

    function earlyExit(
        IERC1155 outcomeTokenA,
        uint256 outcomeIdA,
        IERC1155 outcomeTokenB,
        uint256 outcomeIdB,
        uint256 amount,
        address to
    ) external {
        bytes32 pairHash = _hashTokenPair(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB);
        require(isAllowedOppositeOutcomeTokenPair[pairHash], "Not an allowed opposite outcome token pair");

        // Transfer outcome tokens from the caller to this contract
        outcomeTokenA.safeTransferFrom(msg.sender, address(this), outcomeIdA, amount, "");
        outcomeTokenB.safeTransferFrom(msg.sender, address(this), outcomeIdB, amount, "");

        uint256 exitAmount = earlyExitAmountContracts[pairHash].getEarlyExitAmount(
            outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB, amount
        );

        vault.withdraw(exitAmount, to, address(this));
        totalEarlyExitedAmounts[pairHash] += exitAmount;
    }

    // the owner needs to make sure that the decimals of the outcome tokens are the same as the asset decimals
    // for ERC1155 tokens, the data is in the URI, so there is no way to enforce this on-chain
    function addAllowedOppositeOutcomeTokens(
        IERC1155 outcomeTokenA,
        uint256 outcomeIdA,
        IERC1155 outcomeTokenB,
        uint256 outcomeIdB,
        IGetEarlyExitAmount earlyExitAmountContract
    ) external onlyOwner {
        bytes32 pairHash = _hashTokenPair(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB);
        require(!isAllowedOppositeOutcomeTokenPair[pairHash], PairAlreadyAllowed());

        allowedOppositeOutcomeTokens.push(
            OppositeOutcomeTokensInfo({
                outcomeTokenA: outcomeTokenA,
                outcomeIdA: outcomeIdA,
                outcomeTokenB: outcomeTokenB,
                outcomeIdB: outcomeIdB
            })
        );
        isAllowedOppositeOutcomeTokenPair[pairHash] = true;
        earlyExitAmountContracts[pairHash] = earlyExitAmountContract;
    }

    function removeAllowedOppositeOutcomeTokens(uint256 index) external onlyOwner {
        require(index < allowedOppositeOutcomeTokens.length, "Index out of bounds");

        OppositeOutcomeTokensInfo memory tokenInfo = allowedOppositeOutcomeTokens[index];
        bytes32 pairHash = _hashTokenInfo(tokenInfo);
        isAllowedOppositeOutcomeTokenPair[pairHash] = false;
        delete earlyExitAmountContracts[pairHash];

        allowedOppositeOutcomeTokens[index] = allowedOppositeOutcomeTokens[allowedOppositeOutcomeTokens.length - 1];
        allowedOppositeOutcomeTokens.pop();
    }

    // make sure the owner does this only after the corresponding market has expired
    // right now it is upto the owner to verify that the market has expired
    function transferTokensToAdmin(IERC1155 outcomeToken, uint256 outcomeId) external onlyOwner {
        outcomeToken.safeTransferFrom(address(this), msg.sender, outcomeId, outcomeToken.balanceOf(address(this), outcomeId), "");
    }

    // this can be automated using a contract
    // right this is done manually by the owner after market expiry
    // owner takes 10% of the profit as fee (can be enforced on-chain by making all the manual process that owner does on-chain)
    function reportProfitOrLoss(
        IERC1155 outcomeTokenA,
        uint256 outcomeIdA,
        IERC1155 outcomeTokenB,
        uint256 outcomeIdB,
        uint256 amount
    ) external onlyOwner {
        bytes32 pairHash = _hashTokenPair(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB);
        uint256 totalExited = totalEarlyExitedAmounts[pairHash];

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        vault.deposit(amount, address(this));
        
        int256 profitOrLoss;

        if(amount > totalExited) {
            // forge-lint: disable-next-line(unsafe-typecast)
            profitOrLoss = int256(amount - totalExited);
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            profitOrLoss = -int256(totalExited - amount);
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        _totalAssets = uint256(int256(_totalAssets) + profitOrLoss);

        delete totalEarlyExitedAmounts[pairHash];
    }

    function checkIsAllowedOppositeOutcomeTokenPair(
        IERC1155 outcomeTokenA,
        uint256 outcomeIdA,
        IERC1155 outcomeTokenB,
        uint256 outcomeIdB
    ) external view returns (bool) {
        bytes32 pairHash = _hashTokenPair(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB);
        return isAllowedOppositeOutcomeTokenPair[pairHash];
    }

    function totalAssets() public view override returns (uint256) {
        return _totalAssets;
    }

    function onERC1155Received(address operator, address, uint256, uint256, bytes calldata)
        external
        view
        override
        returns (bytes4)
    {
        require(operator == address(this), DirectTransfersNotAllowed());
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert BatchTransfersNotAllowed();
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }
}
