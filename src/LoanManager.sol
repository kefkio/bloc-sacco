// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract LoanManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Constants
    uint256 public constant GRACE_PERIOD = 7 days;
    uint256 public constant MIN_LOAN_AMOUNT = 1e16; // 0.01 ETH minimum
    uint256 public constant MAX_PENALTY_PERCENT = 50; // 50% max penalty cap
    uint256 public constant MIN_INSTALLMENT_INTERVAL = 1 days;
    uint256 public constant MAX_INSTALLMENT_INTERVAL = 31 days;

    // Structs
    struct Installment {
        uint256 amount;
        uint256 dueDate;
        uint256 paidAmount;
        bool isPaid;
    }

    struct Guarantor {
        address guarantorAddress;
        uint256 guaranteeAmount;
        bool isVerified;
        bool collateralReturned;
    }

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


    enum LoanStatus { Requested, Approved, Disbursed, FullyRepaid, Defaulted, Cancelled }
    enum KycStatus { NotVerified, Pending, Verified, Rejected }

    // State variables
    uint256 private _nextId;
    mapping(uint256 => Loan) private _loans;
    mapping(address => bool) private _registeredMembers;
    mapping(address => KycStatus) private _kycStatus;
    mapping(address => uint256) private _memberLoanCount;

    // Events
    event LoanRequested(uint256 indexed id, address indexed borrower, uint256 amount, bool isFiat);
    event LoanApproved(uint256 indexed id);
    event LoanDisbursed(uint256 indexed id, address indexed borrower, uint256 amount);
    event InstallmentPaid(uint256 indexed loanId, uint256 installmentIndex, address indexed payer, uint256 amount);
    event LoanFullyRepaid(uint256 indexed id);
    event LoanDefaulted(uint256 indexed id);
    event LoanCancelled(uint256 indexed id);
    event GuarantorAdded(uint256 indexed loanId, address indexed guarantor, uint256 amount);
    event GuarantorCollateralReturned(uint256 indexed loanId, address indexed guarantor, uint256 amount);
    event MemberRegistered(address indexed member);
    event KycStatusUpdated(address indexed member, KycStatus newStatus);

    // Errors
    error LoanManager__NotRegistered();
    error LoanManager__KycNotVerified();
    error LoanManager__PendingLoansExist();
    error LoanManager__ZeroAddress();
    error LoanManager__InvalidAmount();
    error LoanManager__DuplicateGuarantor();
    error LoanManager__NotApproved();
    error LoanManager__AlreadyDisbursed();
    error LoanManager__InsufficientBalance();
    error LoanManager__TransferFailed();
    error LoanManager__NotDisbursed();
    error LoanManager__InvalidInstallmentCount();
    error LoanManager__PaymentTooSmall();
    error LoanManager__NotBorrower();
    error LoanManager__AlreadyFullyRepaid();
    error LoanManager__PenaltyExceedsCap();
    error LoanManager__CollateralAlreadyReturned();

constructor() {} // Ownable automatically sets msg.sender as owner

    // Modifiers
    modifier onlyRegistered() {
        if (!_registeredMembers[msg.sender]) revert LoanManager__NotRegistered();
        _;
    }

    modifier kycVerified() {
        if (_kycStatus[msg.sender] != KycStatus.Verified) revert LoanManager__KycNotVerified();
        _;
    }

    modifier noPendingLoans() {
        if (_memberLoanCount[msg.sender] > 0) revert LoanManager__PendingLoansExist();
        _;
    }

    // Core functions
    function registerMember() external noPendingLoans {
        if (_registeredMembers[msg.sender]) revert();
        if (msg.sender == address(0)) revert LoanManager__ZeroAddress();

        _registeredMembers[msg.sender] = true;
        _kycStatus[msg.sender] = KycStatus.Pending;
        emit MemberRegistered(msg.sender);
    }

    function updateKycStatus(address member, KycStatus newStatus) external onlyOwner {
        if (member == address(0)) revert LoanManager__ZeroAddress();
        _kycStatus[member] = newStatus;
        emit KycStatusUpdated(member, newStatus);
    }

    function requestLoan(
        uint256 amount,
        bool isFiat,
        address erc20Token,
        uint256 installmentCount,
        uint256 installmentInterval
    )
        external
        nonReentrant
        onlyRegistered
        kycVerified
        returns (uint256)
    {
        if (amount < MIN_LOAN_AMOUNT) revert LoanManager__InvalidAmount();
        if (installmentCount == 0) revert LoanManager__InvalidInstallmentCount();
        if (installmentInterval < MIN_INSTALLMENT_INTERVAL ||
            installmentInterval > MAX_INSTALLMENT_INTERVAL) revert LoanManager__InvalidAmount();
        if (!isFiat && erc20Token == address(0)) revert LoanManager__ZeroAddress();

uint256 id = _nextId++;
_loans[id] = Loan({
    borrower: payable(msg.sender),
    erc20Token: erc20Token,
    totalAmount: amount,
    status: LoanStatus.Requested,
    disbursedAt: 0,
    totalRepaid: 0,
    accruedPenalty: 0,
    installments: new Installment[](installmentCount),  
    guarantors: new Guarantor[](0),                     
    nextInstallmentIndex: 0,
    installmentInterval: installmentInterval,
    installmentCount: installmentCount,               
    isFiat: isFiat
});


        _memberLoanCount[msg.sender]++;
        emit LoanRequested(id, msg.sender, amount, isFiat);
        return id;
    }

    function addGuarantor(uint256 id, address guarantor, uint256 guaranteeAmount)
        external
        onlyOwner
    {
        Loan storage loan = _loans[id];
        if (loan.status != LoanStatus.Requested) revert LoanManager__NotApproved();
        if (guarantor == address(0)) revert LoanManager__ZeroAddress();

        for (uint256 i = 0; i < loan.guarantors.length; i++) {
            if (loan.guarantors[i].guarantorAddress == guarantor) {
                revert LoanManager__DuplicateGuarantor();
            }
        }

        loan.guarantors.push(Guarantor({
            guarantorAddress: guarantor,
            guaranteeAmount: guaranteeAmount,
            isVerified: false,
            collateralReturned: false
        }));

        emit GuarantorAdded(id, guarantor, guaranteeAmount);
    }

function approveLoan(uint256 id) external onlyOwner {
    Loan storage loan = _loans[id];
    if (loan.status != LoanStatus.Requested) revert LoanManager__NotApproved();

    uint256 installmentCount = loan.installmentCount;
    if (installmentCount == 0) revert LoanManager__InvalidInstallmentCount();

    uint256 installmentBaseAmount = loan.totalAmount / installmentCount;
    uint256 remainder = loan.totalAmount % installmentCount;
    uint256 firstDueDate = block.timestamp + loan.installmentInterval;

    // Clear any previous installments just in case
    delete loan.installments;

    for (uint256 i = 0; i < installmentCount; i++) {
        uint256 thisAmount = installmentBaseAmount + (i < remainder ? 1 : 0);
        loan.installments.push(Installment({
            amount: thisAmount,
            dueDate: firstDueDate + (i * loan.installmentInterval),
            paidAmount: 0,
            isPaid: false
        }));
    }

    loan.status = LoanStatus.Approved;
    emit LoanApproved(id);
}


    function disburse(uint256 id) external payable nonReentrant onlyOwner {
        Loan storage loan = _loans[id];
        if (loan.status != LoanStatus.Approved) revert LoanManager__NotApproved();
        if (loan.status == LoanStatus.Disbursed) revert LoanManager__AlreadyDisbursed();

        if (loan.isFiat) {
            if (address(this).balance < loan.totalAmount) revert LoanManager__InsufficientBalance();
            (bool sent, ) = loan.borrower.call{value: loan.totalAmount}("");
            if (!sent) revert LoanManager__TransferFailed();
        } else {
            SafeERC20.safeTransfer(IERC20(loan.erc20Token), loan.borrower, loan.totalAmount);
        }

        loan.status = LoanStatus.Disbursed;
        loan.disbursedAt = block.timestamp;
        emit LoanDisbursed(id, loan.borrower, loan.totalAmount);
    }

    function repay(uint256 id) external payable nonReentrant onlyRegistered {
        Loan storage loan = _loans[id];
        if (loan.status != LoanStatus.Disbursed) revert LoanManager__NotDisbursed();
        if (msg.sender != loan.borrower) revert LoanManager__NotBorrower();
        if (loan.totalRepaid + msg.value > loan.totalAmount + loan.accruedPenalty) {
            revert LoanManager__AlreadyFullyRepaid();
        }

        // Check for late payments and apply penalty
        if (loan.nextInstallmentIndex < loan.installments.length) {
            Installment storage current = loan.installments[loan.nextInstallmentIndex];
            if (block.timestamp > current.dueDate + GRACE_PERIOD && !current.isPaid) {
                uint256 penalty = (current.amount * 5) / 100; // 5% penalty
                uint256 newPenalty = loan.accruedPenalty + penalty;
                uint256 penaltyCap = (loan.totalAmount * MAX_PENALTY_PERCENT) / 100;

                if (newPenalty > penaltyCap) {
                    loan.accruedPenalty = penaltyCap;
                } else {
                    loan.accruedPenalty = newPenalty;
                }
            }
        }

        // Apply payment to installments
        uint256 remainingPayment = msg.value;
        uint256 currentIndex = loan.nextInstallmentIndex;

        while (remainingPayment > 0 && currentIndex < loan.installments.length) {
            Installment storage installment = loan.installments[currentIndex];
            if (installment.isPaid) {
                currentIndex++;
                continue;
            }

            uint256 needed = installment.amount - installment.paidAmount;
            uint256 payment = remainingPayment >= needed ? needed : remainingPayment;
            installment.paidAmount += payment;
            loan.totalRepaid += payment;
            remainingPayment -= payment;

            if (installment.paidAmount >= installment.amount) {
                installment.isPaid = true;
                currentIndex++;
            }
        }

        loan.nextInstallmentIndex = currentIndex;

        // Check if fully repaid (including penalties)
        if (loan.totalRepaid >= loan.totalAmount + loan.accruedPenalty) {
            loan.status = LoanStatus.FullyRepaid;
            emit LoanFullyRepaid(id);

            // Refund any overpayment
            if (remainingPayment > 0) {
                payable(msg.sender).transfer(remainingPayment);
            }

            _memberLoanCount[loan.borrower]--;
        } else {
            emit InstallmentPaid(id, currentIndex - 1, msg.sender, msg.value - remainingPayment);
        }
    }

    function cancelLoan(uint256 id) external nonReentrant onlyOwner {
        Loan storage loan = _loans[id];
        if (loan.status != LoanStatus.Requested && loan.status != LoanStatus.Approved) {
            revert();
        }

        loan.status = LoanStatus.Cancelled;
        _memberLoanCount[loan.borrower]--;
        emit LoanCancelled(id);
    }

    function ownerReturnGuarantorCollateral(uint256 id, address guarantor)
        external
        nonReentrant
        onlyOwner
    {
        Loan storage loan = _loans[id];
        if (loan.status != LoanStatus.Cancelled && loan.status != LoanStatus.FullyRepaid) {
            revert();
        }

        for (uint256 i = 0; i < loan.guarantors.length; i++) {
            if (loan.guarantors[i].guarantorAddress == guarantor) {
                if (loan.guarantors[i].collateralReturned) {
                    revert LoanManager__CollateralAlreadyReturned();
                }

                loan.guarantors[i].collateralReturned = true;
                payable(guarantor).transfer(loan.guarantors[i].guaranteeAmount);
                emit GuarantorCollateralReturned(id, guarantor, loan.guarantors[i].guaranteeAmount);
                return;
            }
        }

        revert LoanManager__ZeroAddress();
    }

    // View functions
    function getLoan(uint256 id) external view returns (Loan memory) {
        return _loans[id];
    }

    function getMemberStatus(address member)
        external
        view
        returns (bool isRegistered, KycStatus kycStatus, uint256 loanCount)
    {
        return (_registeredMembers[member], _kycStatus[member], _memberLoanCount[member]);
    }

    function hasPendingLoans(address borrower) public view returns (bool) {
        return _memberLoanCount[borrower] > 0;
    }
}