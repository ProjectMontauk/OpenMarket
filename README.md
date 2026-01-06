# 📦 Smart Contract Audit Repo (Public)

**OpenMarket** is the first Open-Source continuous trading prediction market AMM that allows users to buy and sell shares however they'd like until the market expiration date. Unlike traditional prediction markets with discrete rounds, **OpenMarket** enables seamless, continuous trading throughout the entire market lifecycle.

---

## 🚀 What Makes OpenMarket Unique

- **🔄 Continuous Trading**: Buy and sell shares at any time until market expiration
- **📈 AMM-Based**: Uses Automated Market Maker mechanics for price discovery
- **⚡ Real-Time Pricing**: Dynamic pricing based on current market sentiment
- **🎯 Flexible Participation**: No fixed trading windows or rounds
- **🛠️ Easy Liquidity**: Market owner only needs to provide market liquidity once during market creation, and market maker downside is capped to liquidity provided * ln(2)
- **🎯 Flexible Resolution**: Market owner can resolve the market at current market odds

---

## 📚 Technical Foundation

This codebase is an built on top of Gnosis's Prediction Market AMM, which can be found at: **[https://docs.just.win](https://docs.just.win)**. 

The implementation builds upon the Just Win framework but enables continuous trading, partial resolution, and a fixed liquidity parameter so that potential market maker losses are easy to calculate. 

---

## 📁 Contract Architecture

The core contracts powering OpenMarket's continuous trading AMM:

| Contract                | Description                                                                |
|-------------------------|----------------------------------------------------------------------------|
| `Nash.sol`              | ERC-20 token used for trading (replaces USDC in development)               |
| `ConditionalTokens.sol` | Manages ERC-1155 outcome tokens and conditional logic                      |
| `NoBOverround.sol`      | Core AMM engine handling continuous market making operations               |
| `ABDKMath64x64.sol`     | Mathematical helper library for precise calculations                      |
| `CTHelpers.sol`         | Additional mathematical helper functions                                   |

> ⚠️ **Note**: `Nash.sol` is used for development testing. **USDC** will be the primary trading token in production.

---

## 🛠️ Development Stack

- **Target Network:** Base
- **Development Framework:** Hardhat 3.0 with Viem
- **Testing:** Comprehensive test suite for continuous trading scenarios
- **Deployment:** Automated scripts for contract deployment and market setup

---

## 🎯 Key Features

### Market Management
- **Flexible market creation** with customizable parameters
- **Seamless buy/sell orders** at any time

### User Experience
- **Seamless buy/sell orders** at any time
- **Real-time balance updates** and portfolio tracking
- **Gas-optimized transactions** for efficient trading

---

## 🚧 Development Status

- ✅ **Core AMM Logic**: Implemented and tested
- ✅ **Continuous Trading**: Fully functional
- ✅ **Market Setup**: Automated deployment scripts
- 🧪 **Testing**: Comprehensive test coverage in progress
- 🧪 **Audit**: In progress
- 🔧 **Optimization**: Gas optimization and final refinements

---

## 🔒 Repository Access

This repository is open to all.
