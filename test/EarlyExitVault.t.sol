// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {EarlyExitVault} from "src/EarlyExitVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";
import {MockERC1155} from "test/mocks/MockERC1155.sol";
import {IGetEarlyExitAmount} from "src/interface/IGetEarlyExitAmount.sol";

contract MockEarlyExitAmount is IGetEarlyExitAmount {
    function getEarlyExitAmount(IERC1155, uint256, IERC1155, uint256, uint256 amount) external pure returns (uint256) {
        return amount; // Return full amount for simplicity
    }
}

contract EarlyExitVaultTest is Test {
    EarlyExitVault vault;
    MockERC20 asset;
    MockERC4626 underlyingVault;
    MockERC1155 tokenA;
    MockERC1155 tokenB;
    MockEarlyExitAmount earlyExitAmountContract;

    address owner = address(1);
    address user = address(2);

    uint256 outcomeIdA = 1;
    uint256 outcomeIdB = 2;

    function setUp() public {
        vm.startPrank(owner);
        asset = new MockERC20("USDC", "USDC");
        underlyingVault = new MockERC4626(asset);
        vault = new EarlyExitVault(asset, underlyingVault, "Early Exit Vault", "EEV");

        tokenA = new MockERC1155();
        tokenB = new MockERC1155();
        earlyExitAmountContract = new MockEarlyExitAmount();

        // Mint some assets to user
        asset.mint(user, 10000);
        asset.mint(owner, 10000);
        tokenA.mint(user, outcomeIdA, 1000);
        tokenB.mint(user, outcomeIdB, 1000);

        vm.stopPrank();
    }

    function testConstructor() public view {
        assertEq(address(vault.asset()), address(asset));
        assertEq(address(vault.vault()), address(underlyingVault));
        assertEq(vault.owner(), owner);
        assertEq(vault.ASSET_DECIMALS(), 6);
    }

    function testDeposit() public {
        vm.startPrank(user);
        asset.approve(address(vault), 1000);
        uint256 shares = vault.deposit(1000, user);
        assertEq(shares, 1000); // Assuming 1:1 for simplicity
        assertEq(vault.totalAssets(), 1000);
        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(user);
        asset.approve(address(vault), 1000);
        vault.deposit(1000, user);
        uint256 assets = vault.withdraw(500, user, user);
        assertEq(assets, 500);
        assertEq(vault.totalAssets(), 500);
        vm.stopPrank();
    }

    function testAddAllowedOppositeOutcomeTokens() public {
        vm.startPrank(owner);
        vault.addAllowedOppositeOutcomeTokens(tokenA, 6, outcomeIdA, tokenB, 6, outcomeIdB, earlyExitAmountContract);
        assertTrue(vault.checkIsAllowedOppositeOutcomeTokenPair(tokenA, outcomeIdA, tokenB, outcomeIdB));
        vm.stopPrank();
    }

    function testEarlyExit() public {
        vm.startPrank(owner);
        vault.addAllowedOppositeOutcomeTokens(tokenA, 6, outcomeIdA, tokenB, 6, outcomeIdB, earlyExitAmountContract);
        vm.stopPrank();

        vm.startPrank(user);
        tokenA.setApprovalForAll(address(vault), true);
        tokenB.setApprovalForAll(address(vault), true);
        asset.approve(address(vault), 1000);
        vault.deposit(1000, user);

        vault.earlyExit(tokenA, outcomeIdA, tokenB, outcomeIdB, 100, user);
        // Check balances, etc.
        vm.stopPrank();
    }

    function testRemoveAllowedOppositeOutcomeTokens() public {
        vm.startPrank(owner);
        vault.addAllowedOppositeOutcomeTokens(tokenA, 6, outcomeIdA, tokenB, 6, outcomeIdB, earlyExitAmountContract);
        vault.removeAllowedOppositeOutcomeTokens(tokenA, outcomeIdA, tokenB, outcomeIdB);
        assertFalse(vault.checkIsAllowedOppositeOutcomeTokenPair(tokenA, outcomeIdA, tokenB, outcomeIdB));
        vm.stopPrank();
    }

    function testTransferTokensToAdmin() public {
        vm.startPrank(owner);
        vault.addAllowedOppositeOutcomeTokens(tokenA, 6, outcomeIdA, tokenB, 6, outcomeIdB, earlyExitAmountContract);
        // Set balance directly to avoid onERC1155Received check
        bytes32 idHash = keccak256(abi.encode(outcomeIdA, uint256(0)));
        bytes32 balanceSlot = keccak256(abi.encode(address(vault), idHash));
        vm.store(address(tokenA), balanceSlot, bytes32(uint256(100)));
        vault.startRedeemProcess(tokenA, outcomeIdA, tokenB, outcomeIdB);
        assertEq(tokenA.balanceOf(owner, outcomeIdA), 100);
        vm.stopPrank();
    }

    function testReportProfitOrLoss() public {
        vm.startPrank(owner);
        vault.addAllowedOppositeOutcomeTokens(tokenA, 6, outcomeIdA, tokenB, 6, outcomeIdB, earlyExitAmountContract);
        vm.stopPrank();

        vm.startPrank(user);
        tokenA.setApprovalForAll(address(vault), true);
        tokenB.setApprovalForAll(address(vault), true);
        asset.approve(address(vault), 1000);
        vault.deposit(1000, user);
        vault.earlyExit(tokenA, outcomeIdA, tokenB, outcomeIdB, 100, user); // sets earlyExitedAmount to 100
        vm.stopPrank();

        vm.startPrank(owner);
        vault.startRedeemProcess(tokenA, outcomeIdA, tokenB, outcomeIdB); // pause the pair
        asset.approve(address(vault), 50); // report 50, which is less than 100, so loss
        vault.reportProfitOrLoss(tokenA, outcomeIdA, tokenB, outcomeIdB, 50);
        vm.stopPrank();
    }

    function testReportProfitOrLossAndRemovePair() public {
        vm.startPrank(owner);
        vault.addAllowedOppositeOutcomeTokens(tokenA, 6, outcomeIdA, tokenB, 6, outcomeIdB, earlyExitAmountContract);
        vm.stopPrank();

        vm.startPrank(user);
        tokenA.setApprovalForAll(address(vault), true);
        tokenB.setApprovalForAll(address(vault), true);
        asset.approve(address(vault), 1000);
        vault.deposit(1000, user);
        vault.earlyExit(tokenA, outcomeIdA, tokenB, outcomeIdB, 100, user); // sets earlyExitedAmount to 100
        vm.stopPrank();

        vm.startPrank(owner);
        vault.startRedeemProcess(tokenA, outcomeIdA, tokenB, outcomeIdB); // pause the pair
        asset.approve(address(vault), 50); // report 50, which is less than 100, so loss
        vault.reportProfitOrLossAndRemovePair(tokenA, outcomeIdA, tokenB, outcomeIdB, 50);
        vm.stopPrank();

        // Check that the pair is removed
        bool isAllowed = vault.checkIsAllowedOppositeOutcomeTokenPair(tokenA, outcomeIdA, tokenB, outcomeIdB);
        assertFalse(isAllowed);
    }

    function testAddAllowedOppositeOutcomeTokensAlreadyAllowed() public {
        vm.startPrank(owner);
        vault.addAllowedOppositeOutcomeTokens(tokenA, 6, outcomeIdA, tokenB, 6, outcomeIdB, earlyExitAmountContract);
        vm.expectRevert(EarlyExitVault.PairAlreadyAllowed.selector);
        vault.addAllowedOppositeOutcomeTokens(tokenA, 6, outcomeIdA, tokenB, 6, outcomeIdB, earlyExitAmountContract);
        vm.stopPrank();
    }

    function testEarlyExitNotAllowedPair() public {
        vm.startPrank(user);
        tokenA.setApprovalForAll(address(vault), true);
        tokenB.setApprovalForAll(address(vault), true);
        asset.approve(address(vault), 1000);
        vault.deposit(1000, user);

        vm.expectRevert("Not an allowed opposite outcome token pair");
        vault.earlyExit(tokenA, outcomeIdA, tokenB, outcomeIdB, 100, user);
        vm.stopPrank();
    }

    function testRemoveAllowedOppositeOutcomeTokensInvalidIndex() public {
        vm.startPrank(owner);
        vm.expectRevert("Pair not allowed");
        vault.removeAllowedOppositeOutcomeTokens(tokenA, outcomeIdA, tokenB, outcomeIdB); // no pairs added
        vm.stopPrank();
    }

    function testOnERC1155Received() public {
        vm.expectRevert(EarlyExitVault.DirectTransfersNotAllowed.selector);
        vault.onERC1155Received(address(0), address(0), 0, 0, "");
    }

    function testOnERC1155ReceivedAllowed() public view {
        bytes4 result = vault.onERC1155Received(address(vault), address(0), 0, 0, "");
        assertEq(result, vault.onERC1155Received.selector);
    }

    function testOnERC1155BatchReceived() public {
        vm.expectRevert(EarlyExitVault.BatchTransfersNotAllowed.selector);
        vault.onERC1155BatchReceived(address(0), address(0), new uint256[](0), new uint256[](0), "");
    }

    function testChangeUnderlyingVault() public {
        MockERC4626 newVault = new MockERC4626(asset);
        vm.startPrank(owner);
        vault.changeUnderlyingVault(IERC4626(address(newVault)));
        vm.stopPrank();
        assertEq(address(vault.asset()), address(asset));
    }

    function testConvertFromAssetsToOutcomeTokenAmount() public view {
        // Test conversion with same decimals (6)
        uint256 amount = vault.convertFromAssetsToOutcomeTokenAmount(1000000, 6, false); // 1 USDC = 1 outcome token
        assertEq(amount, 1000000);

        // Test conversion with different decimals (18)
        amount = vault.convertFromAssetsToOutcomeTokenAmount(1000000, 18, false); // 1 USDC = 10^12 outcome tokens
        assertEq(amount, 1000000000000000000);

        // Test with round up (but since it's multiplication, no rounding)
        amount = vault.convertFromAssetsToOutcomeTokenAmount(1, 18, true); // 1 wei = 10^12 outcome tokens
        assertEq(amount, 1000000000000);

        // Test division with rounding
        amount = vault.convertFromAssetsToOutcomeTokenAmount(1, 0, false); // 1 USDC = 0 outcome tokens (truncated)
        assertEq(amount, 0);

        amount = vault.convertFromAssetsToOutcomeTokenAmount(1, 0, true); // round up to 1
        assertEq(amount, 1);
    }

    function testStartRedeemProcess() public {
        vm.startPrank(owner);
        vault.addAllowedOppositeOutcomeTokens(tokenA, 6, outcomeIdA, tokenB, 6, outcomeIdB, earlyExitAmountContract);
        vault.startRedeemProcess(tokenA, outcomeIdA, tokenB, outcomeIdB);
        vm.stopPrank();

        // Check that the pair is paused
        bool isAllowed = vault.checkIsAllowedOppositeOutcomeTokenPair(tokenA, outcomeIdA, tokenB, outcomeIdB);
        assertFalse(isAllowed);
    }

    function testEstimateEarlyExitAmount() public {
        vm.startPrank(owner);
        vault.addAllowedOppositeOutcomeTokens(tokenA, 6, outcomeIdA, tokenB, 6, outcomeIdB, earlyExitAmountContract);
        vm.stopPrank();

        uint256 estimated = vault.estimateEarlyExitAmount(tokenA, outcomeIdA, tokenB, outcomeIdB, 100);
        // The mock earlyExitAmountContract returns the amount * 1, so 100
        assertEq(estimated, 100);
    }

    function testSplitOppositeOutcomeTokens() public {
        vm.startPrank(owner);
        vault.addAllowedOppositeOutcomeTokens(tokenA, 6, outcomeIdA, tokenB, 6, outcomeIdB, earlyExitAmountContract);
        vm.stopPrank();

        vm.startPrank(user);
        tokenA.setApprovalForAll(address(vault), true);
        tokenB.setApprovalForAll(address(vault), true);
        asset.approve(address(vault), 1000);
        vault.deposit(1000, user);
        vault.earlyExit(tokenA, outcomeIdA, tokenB, outcomeIdB, 100, user); // transfers outcome tokens to vault
        vm.stopPrank();

        // Now split: provide assets back, get outcome tokens
        vm.startPrank(user);
        asset.approve(address(vault), 50); // split 50
        vault.splitOppositeOutcomeTokens(tokenA, outcomeIdA, tokenB, outcomeIdB, 50, user);
        vm.stopPrank();

        // Check that earlyExitedAmount decreased
        bytes32 pairHash = keccak256(abi.encodePacked(tokenA, outcomeIdA, tokenB, outcomeIdB));
        (, , , , , uint256 earlyExitedAmount) = vault.allowedOppositeOutcomeTokensInfo(pairHash);
        assertEq(earlyExitedAmount, 50); // 100 - 50

        // Check totalEarlyExitedAmount
        assertEq(vault.totalEarlyExitedAmount(), 50);
    }
}
