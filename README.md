# 📦 Smart Contract Audit Repo (Private)

This repository contains the smart contracts intended for an upcoming audit.  
🔒 **The repository is private** — please let me know which email addresses need access, and I’ll add them as collaborators.

---

## 📁 Contract Overview

All in-scope contracts are located in the `contracts/` folder. The following five contracts are included for audit:

| Contract                | Description                                                                |
|-------------------------|----------------------------------------------------------------------------|
| `ABDKMath64x64.sol`     | Mathematical helper library                                                |
| `CTHelpers.sol`         | Additional mathematical helper functions                                   |
| `FakeDai.sol`           | Standard ERC-20 test token used for development                           |
| `ConditionalTokens.sol` | Manages ERC-1155 outcome tokens and conditional logic                      |
| `NoBOverround.sol`      | Handles market making operations                                           |

> ⚠️ `TestDai.sol` is currently used for testing, but **USDC** will replace it in the final deployment.

---

## 🛠️ Network & Tooling

- **Target Deployment Network:** Base  
- **RPC Provider:** [ThirdWeb RPC](https://thirdweb.com/) is used to execute contract functions and interact with on-chain data.

---

## 🚧 Development Notes

- 🐞 Some **debugging functions** are still present in the code. These will be retained temporarily for development and testing.
- 🧪 **Test cases** are still in progress and will be submitted before the formal audit.

---

Feel free to reach out for access or further information.
