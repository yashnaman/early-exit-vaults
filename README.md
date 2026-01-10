# Early Exit Vault Documentation

## Overview

Early Exit Vault is an ERC4626 vault designed to facilitate early exits for arbitragers in prediction markets. It allows users holding opposite outcomes of the same event across different prediction markets to redeem their positions early for a discounted amount, rather than waiting for both markets to expire.

Currently, Early Exit Vault supports:
- **Polymarket** (deployed on Polygon).
- **Opinion** (deployed on Binance Smart Chain - BSC).

Kalshi will be supported in the future.

The vault is an ERC4626-compliant smart contract deployed on the Polygon network. The underlying token is USDC.e (the collateral used in Polymarket markets). The website for the project is going to be [pokvault.com](https://pokvault.com) (WIP).

## User Roles

There are three primary user roles in the Early Exit Vault system:

1. **Depositors**: Users who deposit USDC.e tokens into the vault to earn yield on their holdings. If USDC.e are not being used by arbitragers, they will be deposited into an underlying vault to earn yield. 

2. **Arbitragers**: Users who acquire opposite outcome tokens (e.g., YES on one market and NO on another) for the same event across prediction markets for less than $1 total. Normally, they must wait for both markets to expire to claim profits (as one outcome will win). With Early Exit Vault, they can exit early for slightly less than $1 in USDC.e, avoiding the wait. Arbitrages do not have to trust the owner of the contract at all.

3. **Owner**: The administrator who configures the vault by specifying allowed pairs of opposite outcome tokens. The owner is also responsible for redeeming winnings after market expiration and reporting profits or losses back to the vault. 

## Smart Contract Details

- **Deployment Network**: Polygon.
- **Standard**: ERC4626 (vault standard for tokenized vaults).
- **Underlying Token**: USDC.e.
- **Outcome Tokens**: Conditional ERC1155 tokens from Polymarket (on Polygon) and Opinion (on BSC, bridged to Polygon).
- **Bridging**: A bridge is deployed for Opinion ERC1155 tokens from BSC to Polygon using Axelar's General Message Passing (GMP) system. Bridging is initiated by sending tokens to the bridge contract, and fees can be paid by the arbitrager or anyone else.
- **Early Exit Discount**: Determined by an external contract (`IGetEarlyExitAmount`) provided during configuration.

## Step-by-Step Flow

1. **Vault Deployment**:
   - The owner deploys the Early Exit Vault ERC4626 smart contract on Polygon.

2. **Market Identification and Configuration**:
   - The owner identifies matching events across Polymarket and Opinion, e.g., "Will NVIDIA be the largest company at the end of January?"
     - Polymarket: YES outcome (ERC1155 token on Polygon, decimals: 6).
     - Opinion: NO outcome (ERC1155 token on BSC, decimals: 18).
   - Opinion tokens are bridged to Polygon via the pre-deployed bridge (using Axelar GMP).
   - The owner calls `addAllowedOppositeOutcomeTokens` on the vault to enable the pair:

     ```solidity
     function addAllowedOppositeOutcomeTokens(
         IERC1155 outcomeTokenA,      // Polymarket ERC1155 token
         uint8 decimalsA,             // e.g., 6 for Polymarket
         uint256 outcomeIdA,          // YES outcome ID on Polymarket
         IERC1155 outcomeTokenB,      // Bridged Opinion ERC1155 token
         uint8 decimalsB,             // e.g., 18 for Opinion
         uint256 outcomeIdB,          // NO outcome ID on Opinion
         IGetEarlyExitAmount earlyExitAmountContract  // Contract for calculating early exit discount
     ) external;
     ```

3. **Deposits**:
   - Depositors deposit USDC.e tokens into the vault to provide liquidity and earn yield.

4. **Arbitrage Opportunity**:
   - An arbitrager identifies and executes an arbitrage: Buys YES on Polymarket and NO on Opinion for less than $1 total.
   - Bridges the Opinion NO token from BSC to Polygon (send to bridge contract and pay fees).

5. **Early Exit**:
   - Arbitrager estimates the exit amount using the vault's helper function:

     ```solidity
     function estimateEarlyExitAmount(
         IERC1155 outcomeTokenA,
         uint256 outcomeIdA,
         IERC1155 outcomeTokenB,
         uint256 outcomeIdB,
         uint256 amount  // Amount in asset decimals
     ) external view returns (uint256);
     ```

   - If satisfied, calls `earlyExit` to redeem for discounted USDC.e:

     ```solidity
     function earlyExit(
         IERC1155 outcomeTokenA,
         uint256 outcomeIdA,
         IERC1155 outcomeTokenB,
         uint256 outcomeIdB,
         uint256 amount,  // Amount in asset decimals
         address to       // Recipient of USDC.e
     ) external returns (uint256 exitAmount);
     ```

6. **Market Expiration and Redemption**:
   - After both markets expire, the owner initiates redemption:

     ```solidity
     function startRedeemProcess(
         IERC1155 outcomeTokenA,
         uint256 outcomeIdA,
         IERC1155 outcomeTokenB,
         uint256 outcomeIdB
     ) external onlyOwner;
     ```

   - Depending on the winner:
     - If NO (Opinion) wins: Bridge the NO tokens back to BSC and claim winnings.
     - If YES (Polymarket) wins: Claim winnings directly on Polygon.
   - Winnings are bridged back if necessary.

7. **Report Results**:
   - Owner reports the profit or loss to the vault:

     ```solidity
     function reportProfitOrLoss(
         IERC1155 outcomeTokenA,
         uint256 outcomeIdA,
         IERC1155 outcomeTokenB,
         uint256 outcomeIdB,
         uint256 amount  // Profit/loss amount
     ) public onlyOwner;
     ```

This completes the cycle, realizing profits/losses for the vault and depositors.

## Important Addresses for Early Exit Vault

### Vault and Tokens
| Name | Address/Value | Network/Notes |
|------|---------------|---------------|
| Early Exit Vault | 0x69362094D0C2D8Be0818c0006e09B82c5CA59Af9 | Polygon |
| Early Exit Amount Factory Based on Fixed APY | 0xd9b4b0142da1378a86b56d96decfd383c14c811e | Polygon | 
| Opinion Conditional Token | 0xAD1a38cEc043e70E83a3eC30443dB285ED10D774 | BSC |
| Polymarket Conditional Token | 0x4d97dcd97ec945f40cf65f87097ace5ea0476045 | Polygon |
| USDC.e | 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174 | Polygon (underlying collateral) |

### Axelar Gateways and Chain Names
| Name | Address/Value | Network/Notes |
|------|---------------|---------------|
| Axelar Gateway Contract | 0x304acf330bbE08d1e512eefaa92F6a57871fD895 | BSC |
| Axelar Gateway Contract | 0x6f015F16De9fC8791b234eF68D486d2bF203FBA8 | Polygon |
| Axelar BSC Chain Name | binance | N/A |
| Axelar Polygon Chain Name | Polygon | N/A |

### Opinion ERC1155 Bridges
| Name | Address/Value | Network/Notes |
|------|---------------|---------------|
| Opinion ERC1155 Bridge Source | 0x4020b9d6d226aaed55b320e4d5795bf237238df6 | BSC |
| Opinion ERC1155 Bridge Receiver | 0x4020b9d6d226aaed55b320e4d5795bf237238df6 | Polygon |

## Usage

### Build

```shell
$ npm install
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```
