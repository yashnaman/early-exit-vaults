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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title EarlyExitVault
 * @dev ERC4626 tokenized vault that allows arbitragers to exit early by combining opposite
 *      allowed outcome tokens. For example, on Opinion prediction market, arbitagers can buy
 *      YES outcome token of will trump win, bridge it to Polygon, combine it with NO outcome token
 *      of will trump win on PolyMarket, and get 1 USDC back immediately.
 */
contract EarlyExitVault is ERC4626, Ownable, ERC165, IERC1155Receiver {
    using SafeERC20 for IERC20;

    uint256 public totalEarlyExitedAmount;

    // vault where the underlying assets are deposited when it is not being used for early exits
    IERC4626 public vault;
    uint256 public immutable ASSET_DECIMALS;

    // vault depositors will trust the admin of the vault to set these such that only opposite outcome tokens are allowed
    // one of the outcome should be guaranteed to be worth 1 when the market expires
    struct OppositeOutcomeTokens {
        IERC1155 outcomeTokenA;
        uint256 outcomeIdA;
        IERC1155 outcomeTokenB;
        uint256 outcomeIdB;
    }

    struct OppositeOutcomeTokensInfo {
        bool isAllowed;
        bool isPaused; // pause to transfer the outcome tokens to owner
        uint8 decimalsA;
        uint8 decimalsB;
        IGetEarlyExitAmount earlyExitAmountContract;
        uint256 earlyExitedAmount;
    }

    OppositeOutcomeTokens[] public oppositeOutcomeTokenPairs;
    mapping(bytes32 => OppositeOutcomeTokensInfo) public allowedOppositeOutcomeTokensInfo;

    error VaultAssetMismatch();
    error PairAlreadyAllowed();
    error DirectTransfersNotAllowed();
    error BatchTransfersNotAllowed();

    event NewOppositeOutcomeTokenPairAdded(
        uint256 indexed outcomeIdA,
        uint256 indexed outcomeIdB,
        IGetEarlyExitAmount indexed earlyExitAmountContract,
        IERC1155 outcomeTokenA,
        IERC1155 outcomeTokenB,
        uint8 decimalsA,
        uint8 decimalsB
    );
    event OppositeOutcomeTokenPairRemoved(
        uint256 indexed outcomeIdA, uint256 indexed outcomeIdB, IERC1155 outcomeTokenA, IERC1155 outcomeTokenB
    );
    event OppositeOutcomeTokenPairPaused(
        uint256 indexed outcomeIdA, uint256 indexed outcomeIdB, IERC1155 outcomeTokenA, IERC1155 outcomeTokenB
    );
    event ProfitOrLossReported(
        uint256 indexed outcomeIdA,
        uint256 indexed outcomeIdB,
        IERC1155 outcomeTokenA,
        IERC1155 outcomeTokenB,
        int256 profitOrLoss
    );
    event EarlyExit(
        uint256 indexed outcomeIdA,
        uint256 indexed outcomeIdB,
        IERC1155 outcomeTokenA,
        IERC1155 outcomeTokenB,
        uint256 amount,
        uint256 exitAmount
    );
    event SplitOppositeOutcomeTokens(
        uint256 indexed outcomeIdA,
        uint256 indexed outcomeIdB,
        IERC1155 outcomeTokenA,
        IERC1155 outcomeTokenB,
        uint256 amount
    );

    constructor(IERC20 asset_, IERC4626 _vault, string memory name_, string memory symbol_)
        ERC4626(asset_)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        vault = _vault;
        if (_vault.asset() != address(asset_)) revert VaultAssetMismatch();
        asset_.forceApprove(address(_vault), type(uint256).max);

        ASSET_DECIMALS = ERC20(address(asset_)).decimals();
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        vault.deposit(assets, address(this));
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        vault.withdraw(assets, address(this), address(this));
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _hashTokenPair(IERC1155 outcomeTokenA, uint256 outcomeIdA, IERC1155 outcomeTokenB, uint256 outcomeIdB)
        internal
        pure
        returns (bytes32 pairHash)
    {
        pairHash = keccak256(abi.encodePacked(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB));
    }

    function _hashTokenInfo(OppositeOutcomeTokens memory tokenInfo) internal pure returns (bytes32 pairHash) {
        pairHash = keccak256(
            abi.encodePacked(
                tokenInfo.outcomeTokenA, tokenInfo.outcomeIdA, tokenInfo.outcomeTokenB, tokenInfo.outcomeIdB
            )
        );
    }

    function convertFromAssetsToOutcomeTokenAmount(uint256 assets, uint8 outcomeTokenDecimals, bool shouldRoundUp)
        public
        view
        returns (uint256)
    {
        if (ASSET_DECIMALS >= outcomeTokenDecimals) {
            // round up in favor of the protocol
            if (shouldRoundUp) {
                return Math.ceilDiv(assets, 10 ** (ASSET_DECIMALS - outcomeTokenDecimals));
            } else {
                return assets / (10 ** (ASSET_DECIMALS - outcomeTokenDecimals));
            }
        } else {
            return assets * (10 ** (outcomeTokenDecimals - ASSET_DECIMALS));
        }
    }

    // here the amount will be in the asset decimals
    // we will convert it into the outcome token decimals using the owner provided decimals while adding the pair

    // @arbitragers provide opposite outcome tokens and get underlying assets back immediately
    // there is no need to trust the owner of this contract at all. 
    function earlyExit(
        IERC1155 outcomeTokenA,
        uint256 outcomeIdA,
        IERC1155 outcomeTokenB,
        uint256 outcomeIdB,
        uint256 amount, //amount in assets decimals
        address to
    ) external returns (uint256 exitAmount) {
        bytes32 pairHash = _hashTokenPair(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB);

        OppositeOutcomeTokensInfo storage info = allowedOppositeOutcomeTokensInfo[pairHash];
        require(info.isAllowed, "Not an allowed opposite outcome token pair");
        require(!info.isPaused, "Transfers are paused for this pair");

        // Transfer outcome tokens from the caller to this contract
        outcomeTokenA.safeTransferFrom(
            msg.sender, address(this), outcomeIdA, convertFromAssetsToOutcomeTokenAmount(amount, info.decimalsA, true), ""
        );
        outcomeTokenB.safeTransferFrom(
            msg.sender, address(this), outcomeIdB, convertFromAssetsToOutcomeTokenAmount(amount, info.decimalsB, true), ""
        );

        exitAmount = info.earlyExitAmountContract
        .getEarlyExitAmount(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB, amount);

        vault.withdraw(exitAmount, to, address(this));
        info.earlyExitedAmount += exitAmount;
        totalEarlyExitedAmount += exitAmount;

        emit EarlyExit(outcomeIdA, outcomeIdB, outcomeTokenA, outcomeTokenB, amount, exitAmount);
    }

    // provide the underlying assets and get the opposite outcome tokens back 
    // for example, you can provide 1 USDC and get back 1 YES outcome token of will trump win on Opinion and 1 NO token of will trump win on Opinion
    // this contract will only have the outcome tokens to be split if some arbitager has done an early exit before 
    function splitOppositeOutcomeTokens(
        IERC1155 outcomeTokenA,
        uint256 outcomeIdA,
        IERC1155 outcomeTokenB,
        uint256 outcomeIdB,
        uint256 amount, // amount in asset decimals
        address to
    ) external {
        bytes32 pairHash = _hashTokenPair(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB);

        OppositeOutcomeTokensInfo storage info = allowedOppositeOutcomeTokensInfo[pairHash];
        require(info.isAllowed, "Not an allowed opposite outcome token pair");
        require(!info.isPaused, "Transfers are paused for this pair");

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        vault.deposit(amount, address(this));

        // Decrease the tracked early exit amounts to reflect the split operation.
        // During early exits, outcome tokens are acquired at a discount (less than 1:1 ratio).
        // This split operation converts them back to underlying assets at full value (1:1 ratio).
        // The profit from this action will not be reported when the owner calls reportProfitOrLoss.
        totalEarlyExitedAmount = totalEarlyExitedAmount > amount ? totalEarlyExitedAmount - amount : 0;
        info.earlyExitedAmount = info.earlyExitedAmount > amount ? info.earlyExitedAmount - amount : 0;

        // Transfer opposite outcome tokens to the caller
        outcomeTokenA.safeTransferFrom(
            address(this), to, outcomeIdA, convertFromAssetsToOutcomeTokenAmount(amount, info.decimalsA, false), ""
        );
        outcomeTokenB.safeTransferFrom(
            address(this), to, outcomeIdB, convertFromAssetsToOutcomeTokenAmount(amount, info.decimalsB, false), ""
        );

        // Note: The profit from this split operation cannot be accurately calculated on-chain.
        // To track profitability, monitor off-chain: compare the average discount rate from early exits
        // against the 1:1 redemption rate used here. The difference represents the realized profit.
        emit SplitOppositeOutcomeTokens(outcomeIdA, outcomeIdB, outcomeTokenA, outcomeTokenB, amount);
    }

    // the owner needs to make sure that the decimals of the outcome tokens are the same as the asset decimals
    // for ERC1155 tokens, the data is in the URI, so there is no way to enforce this on-chain
    function addAllowedOppositeOutcomeTokens(
        IERC1155 outcomeTokenA,
        uint8 decimalsA,
        uint256 outcomeIdA,
        IERC1155 outcomeTokenB,
        uint8 decimalsB,
        uint256 outcomeIdB,
        IGetEarlyExitAmount earlyExitAmountContract
    ) external onlyOwner {
        bytes32 pairHash = _hashTokenPair(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB);
        OppositeOutcomeTokensInfo memory info = allowedOppositeOutcomeTokensInfo[pairHash];
        require(!info.isAllowed, PairAlreadyAllowed());

        allowedOppositeOutcomeTokensInfo[pairHash] = OppositeOutcomeTokensInfo({
            isAllowed: true,
            isPaused: false,
            decimalsA: decimalsA,
            decimalsB: decimalsB,
            earlyExitAmountContract: earlyExitAmountContract,
            earlyExitedAmount: 0
        });

        oppositeOutcomeTokenPairs.push(
            OppositeOutcomeTokens({
                outcomeTokenA: outcomeTokenA,
                outcomeIdA: outcomeIdA,
                outcomeTokenB: outcomeTokenB,
                outcomeIdB: outcomeIdB
            })
        );

        emit NewOppositeOutcomeTokenPairAdded(
            outcomeIdA, outcomeIdB, earlyExitAmountContract, outcomeTokenA, outcomeTokenB, decimalsA, decimalsB
        );
    }

    function removeAllowedOppositeOutcomeTokens(
        IERC1155 outcomeTokenA,
        uint256 outcomeIdA,
        IERC1155 outcomeTokenB,
        uint256 outcomeIdB
    ) public onlyOwner {
        bytes32 pairHash = _hashTokenPair(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB);
        OppositeOutcomeTokensInfo storage info = allowedOppositeOutcomeTokensInfo[pairHash];
        require(info.isAllowed, "Pair not allowed");
        require(info.earlyExitedAmount == 0, "Cannot remove pair with pending exited amount");
        require(!info.isPaused, "Cannot remove pair while paused");

        delete allowedOppositeOutcomeTokensInfo[pairHash];

        emit OppositeOutcomeTokenPairRemoved(outcomeIdA, outcomeIdB, outcomeTokenA, outcomeTokenB);
    }

    // make sure the owner does this only after the corresponding markets have expired
    // right now it is upto the owner to verify that the market has expired
    function startRedeemProcess(IERC1155 outcomeTokenA, uint256 outcomeIdA, IERC1155 outcomeTokenB, uint256 outcomeIdB)
        external
        onlyOwner
    {
        bytes32 pairHash = _hashTokenPair(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB);
        OppositeOutcomeTokensInfo storage info = allowedOppositeOutcomeTokensInfo[pairHash];
        require(info.isAllowed, "Pair not allowed");
        require(!info.isPaused, "Transfers are paused for this pair");
        info.isPaused = true;

        outcomeTokenA.safeTransferFrom(
            address(this), msg.sender, outcomeIdA, outcomeTokenA.balanceOf(address(this), outcomeIdA), ""
        );
        outcomeTokenB.safeTransferFrom(
            address(this), msg.sender, outcomeIdB, outcomeTokenB.balanceOf(address(this), outcomeIdB), ""
        );

        emit OppositeOutcomeTokenPairPaused(outcomeIdA, outcomeIdB, outcomeTokenA, outcomeTokenB);
    }

    // this can be automated using a contract
    // right this is done manually by the owner after market expiry
    // owner takes 10% of the profit as fee (can be enforced on-chain by making all the manual process that owner does on-chain)
    // next version will rely on the owner very less. For now, we keep it simple
    function reportProfitOrLoss(
        IERC1155 outcomeTokenA,
        uint256 outcomeIdA,
        IERC1155 outcomeTokenB,
        uint256 outcomeIdB,
        uint256 amount
    ) public onlyOwner {
        bytes32 pairHash = _hashTokenPair(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB);
        OppositeOutcomeTokensInfo storage info = allowedOppositeOutcomeTokensInfo[pairHash];
        require(info.isAllowed, "Pair not allowed");
        require(info.isPaused, "Not paused");

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        vault.deposit(amount, address(this));

        // if there is a profit, the amount will be greater than the info.earlyExitedAmount
        // if there is a loss, the amount will be less than the info.earlyExited

        int256 profitOrLoss;
        if (amount > info.earlyExitedAmount) {
            // forge-lint: disable-next-line(unsafe-typecast)
            profitOrLoss = int256(amount - info.earlyExitedAmount);
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            profitOrLoss = -int256(info.earlyExitedAmount - amount);
        }

        totalEarlyExitedAmount -= info.earlyExitedAmount;
        info.earlyExitedAmount = 0;
        info.isPaused = false;

        emit ProfitOrLossReported(outcomeIdA, outcomeIdB, outcomeTokenA, outcomeTokenB, profitOrLoss);
    }

    function reportProfitOrLossAndRemovePair(
        IERC1155 outcomeTokenA,
        uint256 outcomeIdA,
        IERC1155 outcomeTokenB,
        uint256 outcomeIdB,
        uint256 amount
    ) external onlyOwner {
        reportProfitOrLoss(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB, amount);
        removeAllowedOppositeOutcomeTokens(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB);
    }

    function changeUnderlyingVault(IERC4626 newVault) external onlyOwner {
        IERC4626 oldVault = IERC4626(address(vault));

        require(newVault.asset() == asset(), VaultAssetMismatch());
        vault = newVault;

        uint256 assetsReceived = oldVault.redeem(oldVault.balanceOf(address(this)), address(this), address(this));
        IERC20(asset()).forceApprove(address(newVault), type(uint256).max);

        newVault.deposit(assetsReceived, address(this));

        // take away approval from the old vault
        IERC20(asset()).forceApprove(address(oldVault), 0);
    }

    function checkIsAllowedOppositeOutcomeTokenPair(
        IERC1155 outcomeTokenA,
        uint256 outcomeIdA,
        IERC1155 outcomeTokenB,
        uint256 outcomeIdB
    ) external view returns (bool) {
        bytes32 pairHash = _hashTokenPair(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB);
        return
            allowedOppositeOutcomeTokensInfo[pairHash].isAllowed && !allowedOppositeOutcomeTokensInfo[pairHash].isPaused;
    }

    // estimate how much underlying assets you will get back if you do an early exit
    // likely to be near 1:1 ratio minus some small discount
    function estimateEarlyExitAmount(
        IERC1155 outcomeTokenA,
        uint256 outcomeIdA,
        IERC1155 outcomeTokenB,
        uint256 outcomeIdB,
        uint256 amount
    ) external view returns (uint256) {
        bytes32 pairHash = _hashTokenPair(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB);

        OppositeOutcomeTokensInfo storage info = allowedOppositeOutcomeTokensInfo[pairHash];
        require(info.isAllowed, "Not an allowed opposite outcome token pair");

        uint256 exitAmount = info.earlyExitAmountContract
        .getEarlyExitAmount(outcomeTokenA, outcomeIdA, outcomeTokenB, outcomeIdB, amount);

        return exitAmount;
    }

    function totalAssets() public view override returns (uint256) {
        return totalEarlyExitedAmount + vault.previewRedeem(vault.balanceOf(address(this)));
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
