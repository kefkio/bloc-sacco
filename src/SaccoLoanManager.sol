// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";



contract SaccoLoanManager is AccessControl, ReentrancyGuard {

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    enum KycStatus {
        Pending,
        Verified,
        Rejected
    }



    enum PaymentType {
        Native,
        Fiat,
        Token
    }

    enum LoanStatus {
        Requested,
        Guaranteed,
        Approved,
        Disbursed,
        PartiallyRepaid,
        FullyRepaid,
        Repaid,
        Defaulted
    }

    struct Loan {
        address borrower;
        PaymentType paymentType;
        address tokenAddress;
        uint256 amount;
        uint256 interestRate;
        uint256 duration;
        uint256 dueDate;
        LoanStatus status;
        address[] guarantors;
    }

    mapping(uint256 => Loan) private _loans;
    mapping(address => bool) private _registered;
    mapping(address => KycStatus) private _kyc;
    mapping(address => uint256) private _activeLoanId;
    mapping(address => bool) private _guarantorUsed;

    uint256 private _loanCounter;

    event MemberRegistered(address member);
    event KycUpdated(address member, KycStatus status);
    event LoanRequested(uint256 indexed loanId, address borrower, uint256 amount);
    event LoanApproved(uint256 indexed loanId);
    event LoanDisbursed(uint256 indexed loanId);
    event LoanRepaid(uint256 indexed loanId, uint256 amount);
    event LoanDefaulted(uint256 indexed loanId);

    constructor(address admin, address[] memory operators) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        for (uint256 i = 0; i < operators.length; i++) {
            _grantRole(OPERATOR_ROLE, operators[i]);
        }
    }

    // -----------------------------
    // Member Registration and KYC
    // -----------------------------
    function registerMember() external {
        require(!_registered[msg.sender], "Already registered");
        _registered[msg.sender] = true;
        _kyc[msg.sender] = KycStatus.Pending;
        emit MemberRegistered(msg.sender);
    }

    function registerMemberFor(address member) external onlyRole(OPERATOR_ROLE) {
        require(member != address(0), "Zero address");
        _registered[member] = true;
        _kyc[member] = KycStatus.Pending;
        emit MemberRegistered(member);
    }

    function updateKyc(address member, KycStatus status) external onlyRole(OPERATOR_ROLE) {
        require(_registered[member], "Not registered");
        _kyc[member] = status;
        emit KycUpdated(member, status);
    }

    // -----------------------------
    // Loan Lifecycle
    // -----------------------------
    function requestLoan(
        uint256 amount,
        PaymentType paymentType,
        address tokenAddress,
        uint256 guarantorCount,
        uint256 duration,
        address[] memory guarantors
    ) external returns (uint256) {
        require(_registered[msg.sender], "Not registered");
        require(_kyc[msg.sender] == KycStatus.Verified, "KYC not verified");
        require(amount > 0, "Invalid loan amount");
        require(duration > 0, "Invalid duration");
        require(_activeLoanId[msg.sender] == 0, "Active loan already exists");
        require(guarantors.length >= guarantorCount, "Insufficient guarantors");

        // Validate guarantors
        for (uint256 i = 0; i < guarantors.length; i++) {
            require(guarantors[i] != msg.sender, "Borrower cannot be guarantor");
            require(_kyc[guarantors[i]] == KycStatus.Verified, "Guarantor not verified");
            require(!_guarantorUsed[guarantors[i]], "Duplicate guarantor");
            _guarantorUsed[guarantors[i]] = true;
        }

        _loanCounter++;
        uint256 loanId = _loanCounter;

        Loan storage loan = _loans[loanId];
        loan.borrower = msg.sender;
        loan.paymentType = paymentType;
        loan.tokenAddress = tokenAddress;
        loan.amount = amount;
        loan.duration = duration;
        loan.dueDate = block.timestamp + duration;
        loan.status = LoanStatus.Requested;
        loan.guarantors = guarantors;

        _activeLoanId[msg.sender] = loanId;

        emit LoanRequested(loanId, msg.sender, amount);
        return loanId;
    }

    function approveLoan(uint256 loanId) external onlyRole(OPERATOR_ROLE) {
        Loan storage loan = _loans[loanId];
        require(loan.borrower != address(0), "Invalid loan");
        require(loan.status == LoanStatus.Requested, "Loan not in requested state");

        loan.status = LoanStatus.Approved;
        emit LoanApproved(loanId);
    }

    function disburseLoan(uint256 loanId) external onlyRole(OPERATOR_ROLE) {
        Loan storage loan = _loans[loanId];
        require(loan.status == LoanStatus.Approved, "Loan not approved");

        loan.status = LoanStatus.Disbursed;
        emit LoanDisbursed(loanId);
    }

    function repayLoan(uint256 loanId, uint256 amount) external payable nonReentrant {
        Loan storage loan = _loans[loanId];
        require(loan.status == LoanStatus.Disbursed, "Loan not active");
        require(amount > 0, "Invalid repayment amount");
        require(msg.sender == loan.borrower, "Not loan owner");

        if (loan.paymentType == PaymentType.Native) {
            require(msg.value == amount, "Incorrect repayment amount");
        } else if (loan.paymentType == PaymentType.Token) {

            require( IERC20(loan.tokenAddress).transferFrom(msg.sender, address(this), amount),
    "ERC20 transferFrom failed"
    );


        }

        loan.amount -= amount;
        if (loan.amount == 0) {
            loan.status = LoanStatus.FullyRepaid;
        } else {
            loan.status = LoanStatus.PartiallyRepaid;
        }

        emit LoanRepaid(loanId, amount);
    }

    function markDefault(uint256 loanId) external onlyRole(OPERATOR_ROLE) {
        Loan storage loan = _loans[loanId];
        require(block.timestamp > loan.dueDate, "Loan not overdue");
        require(loan.status != LoanStatus.FullyRepaid, "Loan already repaid");
        loan.status = LoanStatus.Defaulted;
        emit LoanDefaulted(loanId);
    }

    // -----------------------------
    // View Functions
    // -----------------------------
    function getLoanDetails(uint256 loanId)
        external
        view
        returns (
            address borrower,
            PaymentType paymentType,
            address tokenAddress,
            uint256 guarantorCount,
            uint256 amount,
            uint256 interestRate,
            uint256 duration,
            uint256 dueDate,
            LoanStatus status
        )
    {
        Loan storage loan = _loans[loanId];
        return (
            loan.borrower,
            loan.paymentType,
            loan.tokenAddress,
            loan.guarantors.length,
            loan.amount,
            loan.interestRate,
            loan.duration,
            loan.dueDate,
            loan.status
        );
    }

    function getKycStatus(address member) external view returns (KycStatus) {
        return _kyc[member];
    }

    function isRegistered(address member) external view returns (bool) {
        return _registered[member];
    }

    function getActiveLoanId(address borrower) external view returns (uint256) {
        return _activeLoanId[borrower];
    }
}
