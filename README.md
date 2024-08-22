# Decentralized Stablecoin (DSC) System

## Introduction

This project is a decentralized stablecoin protocol built on the Ethereum blockchain, designed to maintain a stable value pegged to assets like the USD. It allows users to mint DSC tokens by depositing collateral assets such as WETH and WBTC. The system ensures that it remains over-collateralized through mechanisms for minting, redeeming, and liquidating DSC.

## Features

- **Minting DSC**: Users can deposit collateral and mint DSC tokens.
- **Collateral Management**: Supports WETH and WBTC as collateral.
- **Over-collateralization**: The system is designed to always be over-collateralized, ensuring stability and security.
- **Liquidation**: If a user’s collateral falls below a certain health factor, their position can be liquidated.
- **Oracle Integration**: Uses Chainlink oracles to securely fetch the latest collateral prices.
- **No Governance**: This protocol operates without a governance system and does not charge fees.

## Smart Contract Architecture

1. **DSCEngine.sol**: The core of the system that handles minting, collateral management, and liquidations.
2. **DecentralizedStableCoin.sol**: The ERC20 token representing the stablecoin.
3. **PriceFeed Integration**: Uses Chainlink price feeds for fetching collateral prices.

## How It Works

1. **Deposit Collateral**: Users deposit supported collateral tokens (e.g., WETH, WBTC) into the system.
2. **Minting**: Based on the value of their collateral, users can mint DSC tokens while maintaining an over-collateralized position.
3. **Liquidation**: When a user’s collateral value drops below the required health factor, their position becomes eligible for liquidation.
4. **Redemption**: Users can redeem their DSC by burning it in exchange for their collateral.

## Installation and Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/meitedaf/Decentralized-Stablecoin-System.git
   ```
2. Install dependencies:
   ```bash
   forge install
   ```
3. Compile contracts:
   ```bash
   forge build
   ```
4. Run tests:
   ```bash
   forge test
   ```

## Usage

After deploying the contracts, users can interact with the protocol by depositing collateral, minting DSC, and redeeming their collateral.

## Security Considerations

The DSC system utilizes Chainlink oracles for price data, ensuring reliable and tamper-proof price feeds. The protocol is designed with security in mind, using nonReentrant guards to prevent reentrancy attacks, and it is structured to maintain over-collateralization at all times.

## License

This project is licensed under the MIT License.
