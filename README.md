# Bloc-SACCO 🏦

A modular, Ethereum-based SACCO (Savings and Credit Cooperative) smart contract system built with [Foundry](https://book.getfoundry.sh/) and [OpenZeppelin](https://docs.openzeppelin.com/contracts/). Designed for transparency, auditability, and seamless frontend integration.

---

## 🧱 Project Structure
bloc-sacco/ ├── src/                # Core smart contracts (LoanManager, Counter, etc.) ├── script/             # Deployment and interaction scripts ├── test/               # Foundry test suite ├── lib/                # External libraries (forge-std, OpenZeppelin) ├── .github/            # CI workflows ├── .vscode/            # Editor settings ├── foundry.toml        # Foundry config └── README.md

---

## 🚀 Getting Started

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js (for frontend integration)
- Git (with submodule support)

### Install Dependencies

```bash
git clone --recurse-submodules https://github.com/kefkio/bloc-sacco.git
cd bloc-sacco
forge install
forge build
forge test -vv
