SaccoLoanManager.sol — Decentralized SACCO
 Loan Management Contract
 Version: 1.0
 Solidity: ^0.8.28
 Framework: Foundry
 License: MIT


 Overview
 SaccoLoanManager.sol is a decentralized loan management smart contract built for SACCOs
 (Savings and Credit Cooperative Organizations), microfinance institutions, and decentralized
 credit unions. It enables on-chain and hybrid loan processing, collateral guarantees, structured
 repayment, and operator-based administration following OpenZeppelin security standards.
 Architecture
 Roles include Admin, Operator, Member (borrower), and Guarantor. Core structures are Loan,
 Installment, and Guarantor. Access control is enforced via OpenZeppelin’s AccessControl and
 role-based permissions.
 Security Design & Anti-Exploit Controls
 All critical functions use nonReentrant guards. Pull-payment model prevents direct transfers.
 Strict role enforcement via onlyRole modifiers ensures operational separation. Loan penalty
 caps and emergency cancellation features prevent abuse.
 Key Functions
 Member functions include registerMember(), requestLoan(), and repayOnChain(). Operators
 can approveLoan(), disburse(), and releaseCollateral(). Guarantors manage collateral pledges
 and withdrawals safely.
 Testing & Deployment
 Run tests with `forge test -vv`. Deploy using Foundry with constructor arguments for admin
 setup. Ensure ERC20 tokens used comply with SafeERC20 interfaces.
 Audit Checklist
 Before production deployment, verify constructor roles, penalty logic, ERC20 compliance, and
 collateral paths. Simulate reentrancy attacks and verify all pull-based withdrawals.


 🏦 SaccoLoanManager.sol — Decentralized SACCO Loan Management Contract

**Version:** 1.0  
**Solidity Version:** ^0.8.28  
**Framework:** Foundry  
**Libraries:** OpenZeppelin Contracts v5.x  
**License:** MIT  

---

## 📘 Overview

`SaccoLoanManager.sol` is a **multi-asset, decentralized loan management smart contract** built for SACCOs (Savings and Credit Cooperative Organizations), microfinance institutions, and decentralized credit unions.  

It enables:
- On-chain loan requests and disbursements using **ETH or ERC20 tokens**.
- Off-chain loan management for **Fiat-backed** loans.
- **Borrower-appointed guarantors** who can pledge collateral and reclaim it post-repayment.
- Structured **installment repayment** with automatic penalty management.
- Secure **operator and admin roles** for SACCO staff.

This contract is designed for **global security and compliance standards**, following OpenZeppelin’s `AccessControl`, `ReentrancyGuard`, and `SafeERC20` modules.

---

## 🧩 Architecture

### 1. Roles & Access Control
| Role | Description | Permissions |
|------|--------------|-------------|
| **DEFAULT_ADMIN_ROLE** | SACCO Administrator | Assign/revoke operator roles, approve/cancel loans, update KYC. |
| **OPERATOR_ROLE** | SACCO Officer / Loan Officer | Disburse loans, record fiat repayments, release collateral. |
| **Member (User)** | Borrower | Registers, requests loans, appoints guarantors, repays loans. |
| **Guarantor** | Third-party member | Pledges collateral and withdraws after repayment or operator release. |

Implemented with:
```solidity
_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
_grantRole(OPERATOR_ROLE, msg.sender);

Loan

struct Loan {
    address payable borrower;
    address erc20Token;
    uint256 totalAmount;
    LoanStatus status;
    uint256 disbursedAt;
    uint256 totalRepaid;
    uint256 accruedPenalty;
    Installment[] installments;
    Guarantor[] guarantors;
    uint256 nextInstallmentIndex;
    uint256 installmentInterval;
    uint256 installmentCount;
    bool isFiat;
}


Installment

struct Installment {
    uint256 amount;
    uint256 dueDate;
    uint256 paidAmount;
    bool isPaid;
}

Guarantor

Tracks collateral and verification:

struct Guarantor {
    address guarantorAddress;
    uint256 guaranteeAmount;
    bool isVerified;
    bool collateralReturned;
}

3. Enums

| Enum         | Description                | Values                                                            |
| ------------ | -------------------------- | ----------------------------------------------------------------- |
| `LoanStatus` | Lifecycle state of a loan  | Requested, Approved, Disbursed, FullyRepaid, Defaulted, Cancelled |
| `KycStatus`  | KYC/AML verification stage | NotVerified, Pending, Verified, Rejected                          |


Security Design & Anti-Exploit Controls
✅ Reentrancy Protection

All sensitive functions (repay, disburse, releaseCollateral) use nonReentrant.

No external calls are made before state updates.

✅ Pull Payment Model

All ETH/ERC20 collateral returns are credited to internal mappings.

Guarantors must actively withdraw via withdrawCollateral() or withdrawTokenCollateral().

This eliminates all reentrancy vulnerabilities detected by static analyzers.

✅ Access Control Isolation

onlyRole(OPERATOR_ROLE) guards operator functions.

onlyRole(DEFAULT_ADMIN_ROLE) controls administrative actions.

Borrower-only modifiers prevent impersonation.

✅ Loan & Penalty Logic

Grace period: 7 days

Penalty: 5% per missed installment, capped at 50% of total loan.

Overpayment refund logic returns excess ETH after full repayment.

✅ Emergency Safety

cancelLoan() allows operator/admin to cancel unapproved or pending loans.

ownerReturnGuarantorCollateral() ensures collateral can always be returned safely.


| Asset Type | Description                                 | Mode     |
| ---------- | ------------------------------------------- | -------- |
| **ETH**    | Fully on-chain, disbursed and repaid in ETH | On-chain |
| **ERC20**  | Tokenized loan using `SafeERC20`            | On-chain |
| **Fiat**   | Off-chain, managed by operators             | Hybrid   |
ey Functions
👤 Member Actions
Function	Description
registerMember()	Registers a new SACCO member.
requestLoan(amount, isFiat, erc20Token, installmentCount, installmentInterval)	Creates a loan request.
appointGuarantor(loanId, guarantor, amount)	Adds a guarantor pre-approval.
repayOnChain(loanId)	Repay ETH loans.
repayToken(loanId, amount)	Repay ERC20 loans.
🧱 Operator/Admin Actions
Function	Description
approveLoan(loanId)	Approves requested loan and initializes installments.
disburse(loanId)	Transfers loan to borrower (ETH/ERC20).
operatorRecordFiatRepayment(loanId, amount)	Records off-chain fiat repayment.
releaseAllOnChainCollateral(loanId)	Releases guarantor collateral (credits withdrawable balance).
💎 Guarantor Actions
Function	Description
pledgeCollateralETH(loanId)	Guarantor pledges ETH collateral.
pledgeCollateralToken(loanId, token, amount)	Guarantor pledges ERC20 collateral.
withdrawCollateral(loanId)	Withdraw ETH collateral after release.
withdrawTokenCollateral(loanId)	Withdraw ERC20 collateral after release.
🧠 Events
Event	Purpose
LoanRequested(uint256 id, address borrower, uint256 amount, bool isFiat)	Emitted when a loan is requested.
LoanApproved(uint256 id)	Loan approved by admin.
LoanDisbursed(uint256 id, address borrower, uint256 amount)	Funds disbursed.
InstallmentPaid(uint256 loanId, uint256 index, address payer, uint256 amount)	Installment payment recorded.
LoanFullyRepaid(uint256 id)	Loan cleared.
LoanDefaulted(uint256 id)	Borrower defaulted.
GuarantorAdded(uint256 loanId, address guarantor, uint256 amount)	Guarantor added.
CollateralReleased(uint256 loanId, address guarantor, uint256 amount)	Collateral released for withdrawal.
CollateralWithdrawn(uint256 loanId, address guarantor, uint256 amount)	Guarantor withdrew collateral.
MemberRegistered(address member)	New member joined.
KycStatusUpdated(address member, KycStatus status)	KYC status changed.
⚗️ Foundry Testing Guide
Prerequisites

Foundry

Node.js (for script runners)

OpenZeppelin Contracts v5.x installed via forge install

Run Tests
forge clean
forge build
forge test -vv

Example Deployment
forge create src/SaccoLoanManager.sol:SaccoLoanManager --constructor-args 0xAdminAddress

Environment Setup

Your foundry.toml might include:

[profile.default]
src = 'src'
out = 'out'
libs = ['lib']

🧾 Audit Checklist

Before production deployment:

 Verify constructor _grantRole() assignments.

 Check that penalty and grace period constants align with SACCO policy.

 Ensure ERC20 tokens used comply with standard decimals and safeTransfer.

 Validate access roles in deployment script.

 Simulate reentrancy with Foundry fuzz tests.

 Confirm all collateral withdraw paths are pull-based.

📈 Future Extensions

Integrate Chainlink price feeds for multi-currency loan conversions.

Add credit score or reputation module for members.

Support multi-collateral guarantees (mix of ETH + ERC20).

Create an on-chain loan marketplace for SACCO investors.

License

SPDX-License-Identifier: MIT
© 2025 BlockChain Solutions (East Africa) Ltd.
. All rights reserved.


 Author & Maintainer
 Kefa Waweru Kioge
    Blockchain Solutions Architect
Founder, BlockChain Solutions (East Africa) Ltd
 kefa@rawlinzdesigns.com
 Nairobi, Keny