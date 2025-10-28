// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/*
  SaccoLoanManager.sol
  - Supports Native (ETH), ERC20, and Fiat flows.
  - Borrower appoints guarantors; guarantors volunteer collateral (on-chain) or operator records fiat pledge.
  - Loan becomes GUARANTEED when pledgedCollateral >= loanAmount (threshold configurable).
  - AccessControl: ADMIN_ROLE (DEFAULT_ADMIN) & OPERATOR_ROLE.
*/
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract SaccoLoanManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Config
    uint256 public constant MIN_LOAN_AMOUNT = 1e16; // 0.01 ETH or token units
    uint256 public constant GRACE_PERIOD = 7 days;

    uint256 public maxPenaltyPercent = 50; // admin adjustable (cap)
    uint256 public defaultPenaltyPercent = 5; // default penalty percent per overdue installment

    // Enums
    enum PaymentType { Native, ERC20, Fiat }
    enum LoanStatus { Requested, PendingGuarantors, Guaranteed, Approved, Active, FullyRepaid, Defaulted, Cancelled }
    enum KycStatus { NotVerified, Pending, Verified, Rejected }

    // Structs
    struct GuarantorInfo {
        bool appointed;
        uint256 pledgedAmount; // token amount or native amount recorded/locked
        bool pledgedOnChain;   // true if collateral locked on-chain
        bool collateralIsToken;
        bool returned;
        bool agreed; // indicates pledge/agreement made
    }

    struct Installment {
        uint256 amount;
        uint256 dueDate;
        uint256 paidAmount;
        bool isPaid;
    }

    struct Loan {
        address payable borrower;
        PaymentType paymentType;
        address token; // ERC20 token address when paymentType == ERC20
        uint256 amount;
        LoanStatus status;
        uint256 disbursedAt;
        uint256 totalRepaid;
        uint256 accruedPenalty;
        uint256 threshold; // amount required from guarantors (default = amount)
        uint256 nextInstallmentIndex;
        uint256 installmentInterval;
        uint256 installmentCount;
        Installment[] installments;
        address[] appointedGuarantors;
    }

    // State
    uint256 private _nextLoanId = 1;
    mapping(uint256 => Loan) private _loans;
    mapping(uint256 => mapping(address => GuarantorInfo)) private _guarantorInfo;
    mapping(address => bool) private _registered;
    mapping(address => KycStatus) private _kyc;
    mapping(address => uint256) private _openLoanCount;
  

    // Pull-pattern withdrawable balances for returned collateral
    mapping(uint256 => mapping(address => uint256)) private _withdrawableNative; // loanId => guarantor => wei
    mapping(uint256 => mapping(address => mapping(address => uint256))) private _withdrawableTokens; // loanId => guarantor => token => amount

    // Events
    event MemberRegistered(address indexed member);
    event KycUpdated(address indexed member, KycStatus newStatus);
    event LoanRequested(uint256 indexed id, address indexed borrower, uint256 amount, PaymentType ptype);
    event GuarantorsAppointed(uint256 indexed id, address[] guarantors);
    event GuarantorVolunteered(uint256 indexed id, address indexed guarantor, uint256 amount, bool onChain, bool token);
    event GuarantorPledgeRecorded(uint256 indexed id, address indexed guarantor, uint256 amount);
    event LoanGuaranteed(uint256 indexed id, uint256 totalPledged);
    event LoanApproved(uint256 indexed id);
    event LoanDisbursed(uint256 indexed id, address indexed to, uint256 amount);
    event RepaymentRecorded(uint256 indexed id, address indexed payer, uint256 amount);
    event LoanFullyRepaid(uint256 indexed id);
    event CollateralReturned(uint256 indexed id, address indexed guarantor, uint256 amount);
    event LoanCancelled(uint256 indexed id);
    event PenaltyCharged(uint256 indexed id, uint256 amount);

    // Errors (cheaper than strings)
    error ZeroAddress();
    error NotRegistered();
    error KycNotVerified();
    error LoanNotFound();
    error NotBorrower();
    error NotGuarantor();
    error DuplicateGuarantor();
    error InvalidAmount();
    error NotOperator();
    error NotAdmin();
    error LoanNotInRightState();
    error InsufficientContractBalance();
    error TransferFailed();
    error AlreadyPledged();
    error CollateralNotFound();

    // constructor: set admin and operators
    constructor(address admin, address[] memory operators) {
        address deployer = admin == address(0) ? msg.sender : admin;
        _grantRole(DEFAULT_ADMIN_ROLE, deployer);

        // grant operators
        for (uint256 i = 0; i < operators.length; i++) {
            if (operators[i] != address(0)) {
                _grantRole(OPERATOR_ROLE, operators[i]);
            }
        }
    }

    // ----------------------------
    // Member / KYC functions
    // ----------------------------

    /// @notice Register yourself as a member
    function registerMember() external {
        if (msg.sender == address(0)) revert ZeroAddress();
        _registered[msg.sender] = true;
        _kyc[msg.sender] = KycStatus.Pending;
        emit MemberRegistered(msg.sender);
    }

    /// @notice Operator/admin helper: register member on behalf of a user
    function registerMemberFor(address member) external onlyRole(OPERATOR_ROLE) {
        require(member != address(0), "Zero address");
        _registered[member] = true;
        _kyc[member] = KycStatus.Pending;
        emit MemberRegistered(member);
    }

    /// @notice Admin updates KYC status to any (NotVerified, Pending, Verified, Rejected)
    function updateKyc(address member, KycStatus status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _kyc[member] = status;
        emit KycUpdated(member, status);
    }

    /// @notice Operator convenience to mark verified
    function verifyKyc(address member) external onlyRole(OPERATOR_ROLE) {
         require(_registered[member], "Not registered");
        _kyc[member] = KycStatus.Verified;
        emit KycUpdated(member, KycStatus.Verified);
    }

    /// @notice Query KYC
    function getKyc(address member) external view returns (KycStatus) {
        return _kyc[member];
    }

    // ----------------------------
    // Loan request / guarantors
    // ----------------------------

    /// @notice Request a loan, providing a list of appointed guarantors
    function requestLoan(
        uint256 amount,
        PaymentType ptype,
        address token,
        uint256 installmentCount,
        uint256 installmentInterval,
        address[] calldata appointedGuarantors
    ) external returns (uint256) {
        require(_registered[msg.sender], "Not registered");
        require(_kyc[msg.sender] == KycStatus.Verified, "KYC not verified");
        require(amount >= MIN_LOAN_AMOUNT, "Invalid amount");

        uint256 id = _nextLoanId++;
        Loan storage L = _loans[id];
        L.borrower = payable(msg.sender);
        L.paymentType = ptype;
        L.token = token;
        L.amount = amount;
        L.status = LoanStatus.PendingGuarantors;
        L.installmentCount = installmentCount;
        L.installmentInterval = installmentInterval;
        L.threshold = amount; // default; operator can change
        L.nextInstallmentIndex = 0;

        // record appointed guarantors
        for (uint256 i = 0; i < appointedGuarantors.length; i++) {
            address g = appointedGuarantors[i];
            if (g == address(0)) revert ZeroAddress();
            if (_guarantorInfo[id][g].appointed) revert DuplicateGuarantor();
            _guarantorInfo[id][g].appointed = true;
            _guarantorInfo[id][g].pledgedAmount = 0;
            _guarantorInfo[id][g].pledgedOnChain = false;
            _guarantorInfo[id][g].collateralIsToken = false;
            _guarantorInfo[id][g].returned = false;
            _guarantorInfo[id][g].agreed = false;
            L.appointedGuarantors.push(g);
        }

        _openLoanCount[msg.sender] += 1;
        emit LoanRequested(id, msg.sender, amount, ptype);
        emit GuarantorsAppointed(id, appointedGuarantors);
        return id;
    }

    /// @notice Guarantor volunteers collateral — tokenAmount for ERC20 (requires prior approve), or send native ETH via msg.value
    function volunteerCollateral(uint256 loanId, uint256 tokenAmount) external payable nonReentrant {
        Loan storage L = _loans[loanId];
        if (L.borrower == address(0)) revert LoanNotFound();
        if (L.status != LoanStatus.PendingGuarantors) revert LoanNotInRightState();
        if (!_guarantorInfo[loanId][msg.sender].appointed) revert NotGuarantor();
        if (_guarantorInfo[loanId][msg.sender].agreed) revert AlreadyPledged();

        if (tokenAmount > 0) {
            // pledging ERC20 token (token must be set on loan)
            if (L.token == address(0)) revert InvalidAmount();
            IERC20(L.token).safeTransferFrom(msg.sender, address(this), tokenAmount);
            _guarantorInfo[loanId][msg.sender].pledgedAmount = tokenAmount;
            _guarantorInfo[loanId][msg.sender].pledgedOnChain = true;
            _guarantorInfo[loanId][msg.sender].collateralIsToken = true;
        } else {
            // native ETH pledge
            if (msg.value == 0) revert InvalidAmount();
            _guarantorInfo[loanId][msg.sender].pledgedAmount = msg.value;
            _guarantorInfo[loanId][msg.sender].pledgedOnChain = true;
            _guarantorInfo[loanId][msg.sender].collateralIsToken = false;
        }

        _guarantorInfo[loanId][msg.sender].agreed = true;
        emit GuarantorVolunteered(loanId, msg.sender, _guarantorInfo[loanId][msg.sender].pledgedAmount, true, _guarantorInfo[loanId][msg.sender].collateralIsToken);

        // check threshold
        uint256 total = _totalPledgedOnChain(loanId) + _totalPledgedOffChain(loanId);
        if (total >= L.threshold) {
            L.status = LoanStatus.Guaranteed;
            emit LoanGuaranteed(loanId, total);
        }
    }

    /// @notice Operator records an off-chain (fiat) pledge for a guarantor
    function operatorRecordFiatPledge(uint256 loanId, address guarantor, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        Loan storage L = _loans[loanId];
        if (L.borrower == address(0)) revert LoanNotFound();
        if (!_guarantorInfo[loanId][guarantor].appointed) revert NotGuarantor();
        if (_guarantorInfo[loanId][guarantor].agreed) revert AlreadyPledged();

        _guarantorInfo[loanId][guarantor].pledgedAmount = amount;
        _guarantorInfo[loanId][guarantor].pledgedOnChain = false;
        _guarantorInfo[loanId][guarantor].collateralIsToken = false;
        _guarantorInfo[loanId][guarantor].agreed = true;

        emit GuarantorPledgeRecorded(loanId, guarantor, amount);

        uint256 total = _totalPledgedOnChain(loanId) + _totalPledgedOffChain(loanId);
        if (total >= L.threshold) {
            L.status = LoanStatus.Guaranteed;
            emit LoanGuaranteed(loanId, total);
        }
    }

    /// @notice Operator can adjust threshold before approval
    function operatorAdjustThreshold(uint256 loanId, uint256 newThreshold) external onlyRole(OPERATOR_ROLE) {
        Loan storage L = _loans[loanId];
        if (L.borrower == address(0)) revert LoanNotFound();
        if (!(L.status == LoanStatus.PendingGuarantors || L.status == LoanStatus.Guaranteed)) revert LoanNotInRightState();
        L.threshold = newThreshold;
    }

    /// @notice Approve and disburse loan — operator only. Contract must have funds for on-chain disbursement.
    function approveAndDisburse(uint256 loanId) external nonReentrant onlyRole(OPERATOR_ROLE) {
        Loan storage L = _loans[loanId];
        if (L.borrower == address(0)) revert LoanNotFound();
        if (L.status != LoanStatus.Guaranteed) revert LoanNotInRightState();

        // prepare installments
        if (L.installmentCount > 0) {
            delete L.installments;
            uint256 base = L.amount / L.installmentCount;
            uint256 rem = L.amount % L.installmentCount;
            uint256 firstDue = block.timestamp + L.installmentInterval;
            for (uint256 i = 0; i < L.installmentCount; i++) {
                uint256 a = base + (i == 0 ? rem : 0);
                L.installments.push(Installment({amount: a, dueDate: firstDue + i * L.installmentInterval, paidAmount: 0, isPaid: false}));
            }
        }

        L.status = LoanStatus.Approved;
        emit LoanApproved(loanId);

        // Disburse based on payment type
        if (L.paymentType == PaymentType.Native) {
            if (address(this).balance < L.amount) revert InsufficientContractBalance();
            (bool sent, ) = L.borrower.call{value: L.amount}("");
            if (!sent) revert TransferFailed();
            L.disbursedAt = block.timestamp;
            L.status = LoanStatus.Active;
            emit LoanDisbursed(loanId, L.borrower, L.amount);
        } else if (L.paymentType == PaymentType.ERC20) {
            if (L.token == address(0)) revert InvalidAmount();
            IERC20 t = IERC20(L.token);
            uint256 bal = t.balanceOf(address(this));
            if (bal < L.amount) revert InsufficientContractBalance();
            t.safeTransfer(L.borrower, L.amount);
            L.disbursedAt = block.timestamp;
            L.status = LoanStatus.Active;
            emit LoanDisbursed(loanId, L.borrower, L.amount);
        } else {
            // Fiat (off-chain) - mark as active
            L.disbursedAt = block.timestamp;
            L.status = LoanStatus.Active;
            emit LoanDisbursed(loanId, L.borrower, L.amount);
        }
    }

    /// @notice Borrower repays on-chain (native or ERC20). For fiat use operatorRecordFiatRepayment.
    function repayOnChain(uint256 loanId, uint256 tokenAmount) external payable nonReentrant {
        Loan storage L = _loans[loanId];
        if (L.borrower == address(0)) revert LoanNotFound();
        if (L.status != LoanStatus.Active) revert LoanNotInRightState();
        if (msg.sender != L.borrower) revert NotBorrower();

        uint256 received;
        if (L.paymentType == PaymentType.Native) {
            if (msg.value == 0) revert InvalidAmount();
            received = msg.value;
        } else if (L.paymentType == PaymentType.ERC20) {
            if (tokenAmount == 0) revert InvalidAmount();
            IERC20(L.token).safeTransferFrom(msg.sender, address(this), tokenAmount);
            received = tokenAmount;
        } else {
            revert InvalidAmount(); // fiat not repaid on-chain
        }

        // penalty check
        _applyLatePenaltyIfAny(loanId);

        // apply to penalty first
        uint256 remaining = received;
        if (L.accruedPenalty > 0) {
            uint256 toPenalty = remaining <= L.accruedPenalty ? remaining : L.accruedPenalty;
            L.accruedPenalty -= toPenalty;
            remaining -= toPenalty;
            emit PenaltyCharged(loanId, toPenalty);
        }

        // apply to installments/principal
        uint256 idx = L.nextInstallmentIndex;
        while (remaining > 0 && idx < L.installments.length) {
            Installment storage inst = L.installments[idx];
            if (inst.isPaid) {
                idx++;
                continue;
            }
            uint256 need = inst.amount - inst.paidAmount;
            uint256 pay = remaining >= need ? need : remaining;
            inst.paidAmount += pay;
            L.totalRepaid += pay;
            remaining -= pay;
            if (inst.paidAmount >= inst.amount) {
                inst.isPaid = true;
                idx++;
            }
        }
        L.nextInstallmentIndex = idx;

        // check fully repaid
        if (L.totalRepaid >= L.amount && L.accruedPenalty == 0) {
            L.status = LoanStatus.FullyRepaid;
            emit LoanFullyRepaid(loanId);
            _releaseAllOnChainCollateral(loanId);
            _openLoanCount[L.borrower] = _openLoanCount[L.borrower] > 0 ? _openLoanCount[L.borrower] - 1 : 0;
        }

        uint256 applied = received - remaining;
        emit RepaymentRecorded(loanId, msg.sender, applied);

        // refund leftover if any
        if (remaining > 0) {
            if (L.paymentType == PaymentType.Native) {
                (bool s, ) = msg.sender.call{value: remaining}("");
                if (!s) revert TransferFailed();
            } else {
                IERC20(L.token).safeTransfer(msg.sender, remaining);
            }
        }
    }

    /// @notice Operator records fiat repayment (off-chain)
    function operatorRecordFiatRepayment(uint256 loanId, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        Loan storage L = _loans[loanId];
        if (L.borrower == address(0)) revert LoanNotFound();
        if (L.paymentType != PaymentType.Fiat) revert InvalidAmount();
        if (L.status != LoanStatus.Active) revert LoanNotInRightState();

        _applyLatePenaltyIfAny(loanId);

        uint256 remaining = amount;
        if (L.accruedPenalty > 0) {
            uint256 toPenalty = remaining <= L.accruedPenalty ? remaining : L.accruedPenalty;
            L.accruedPenalty -= toPenalty;
            remaining -= toPenalty;
            emit PenaltyCharged(loanId, toPenalty);
        }

        uint256 idx = L.nextInstallmentIndex;
        while (remaining > 0 && idx < L.installments.length) {
            Installment storage inst = L.installments[idx];
            if (inst.isPaid) {
                idx++;
                continue;
            }
            uint256 need = inst.amount - inst.paidAmount;
            uint256 pay = remaining >= need ? need : remaining;
            inst.paidAmount += pay;
            L.totalRepaid += pay;
            remaining -= pay;
            if (inst.paidAmount >= inst.amount) {
                inst.isPaid = true;
                idx++;
            }
        }
        L.nextInstallmentIndex = idx;

        if (L.totalRepaid >= L.amount && L.accruedPenalty == 0) {
            L.status = LoanStatus.FullyRepaid;
            emit LoanFullyRepaid(loanId);
            _releaseAllOnChainCollateral(loanId);
            _openLoanCount[L.borrower] = _openLoanCount[L.borrower] > 0 ? _openLoanCount[L.borrower] - 1 : 0;
        }

        emit RepaymentRecorded(loanId, msg.sender, amount);
    }

    /// @notice Operator returns collateral (pulls credit to withdrawable balances)
    function operatorReturnCollateral(uint256 loanId, address guarantor) external nonReentrant onlyRole(OPERATOR_ROLE) {
        GuarantorInfo storage g = _guarantorInfo[loanId][guarantor];
        if (!g.agreed) revert CollateralNotFound();
        if (g.returned) revert CollateralNotFound();
        uint256 amt = g.pledgedAmount;
        if (amt == 0) revert CollateralNotFound();

        g.returned = true;
        // credit withdrawable balances (pull pattern)
        if (g.pledgedOnChain) {
            if (g.collateralIsToken) {
                _withdrawableTokens[loanId][guarantor][_loans[loanId].token] += amt;
            } else {
                _withdrawableNative[loanId][guarantor] += amt;
            }
        } else {
            // recorded fiat pledge: just emit returned
            // no transfer needed
        }

        emit CollateralReturned(loanId, guarantor, amt);
    }

    /// @notice Admin adjust penalty percentages
    function adminSetPenaltyPercents(uint256 newDefault, uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        defaultPenaltyPercent = newDefault;
        maxPenaltyPercent = newMax;
    }

    // ----------------------------
    // Internal helpers
    // ----------------------------

    function _totalPledgedOnChain(uint256 loanId) internal view returns (uint256 total) {
        address[] storage arr = _loans[loanId].appointedGuarantors;
        for (uint256 i = 0; i < arr.length; i++) {
            GuarantorInfo storage g = _guarantorInfo[loanId][arr[i]];
            if (g.agreed && g.pledgedOnChain) total += g.pledgedAmount;
        }
    }

    function _totalPledgedOffChain(uint256 loanId) internal view returns (uint256 total) {
        address[] storage arr = _loans[loanId].appointedGuarantors;
        for (uint256 i = 0; i < arr.length; i++) {
            GuarantorInfo storage g = _guarantorInfo[loanId][arr[i]];
            if (g.agreed && !g.pledgedOnChain) total += g.pledgedAmount;
        }
    }

    function _applyLatePenaltyIfAny(uint256 loanId) internal {
        Loan storage L = _loans[loanId];
        if (L.nextInstallmentIndex < L.installments.length) {
            Installment storage cur = L.installments[L.nextInstallmentIndex];
            if (block.timestamp > cur.dueDate + GRACE_PERIOD && !cur.isPaid) {
                uint256 pen = (cur.amount * defaultPenaltyPercent) / 100;
                uint256 newPenalty = L.accruedPenalty + pen;
                uint256 cap = (L.amount * maxPenaltyPercent) / 100;
                if (newPenalty > cap) L.accruedPenalty = cap;
                else L.accruedPenalty = newPenalty;
                emit PenaltyCharged(loanId, pen);
            }
        }
    }

    /// @notice Internal: release all on-chain collateral by crediting withdrawable balances (pull)
    function _releaseAllOnChainCollateral(uint256 loanId) internal {
        Loan storage loan = _loans[loanId];
        address[] storage guarantors = loan.appointedGuarantors;
        uint256 len = guarantors.length;
        if (len == 0) {
            return;
        }
        for (uint256 i = 0; i < len; i++) {
            address guarantorAddr = guarantors[i];
            GuarantorInfo storage g = _guarantorInfo[loanId][guarantorAddr];
            if (g.agreed && g.pledgedOnChain && !g.returned && g.pledgedAmount > 0) {
                uint256 pledgedAmount = g.pledgedAmount;
                // mark returned and zero pledged to avoid reentrancy issues
                g.returned = true;
                g.pledgedAmount = 0;
                if (g.collateralIsToken) {
                    address tokenAddr = loan.token;
                    _withdrawableTokens[loanId][guarantorAddr][tokenAddr] += pledgedAmount;
                } else {
                    _withdrawableNative[loanId][guarantorAddr] += pledgedAmount;
                }
                emit CollateralReturned(loanId, guarantorAddr, pledgedAmount);
            }
        }
    }

    // ----------------------------
    // Withdraw (pull pattern)
    // ----------------------------

    function withdrawCollateral(uint256 loanId) external nonReentrant {
        uint256 amt = _withdrawableNative[loanId][msg.sender];
        if (amt == 0) revert CollateralNotFound();
        _withdrawableNative[loanId][msg.sender] = 0;
        (bool sent, ) = msg.sender.call{value: amt}("");
        if (!sent) revert TransferFailed();
    }

    function withdrawTokenCollateral(uint256 loanId, address token) external nonReentrant {
        uint256 amt = _withdrawableTokens[loanId][msg.sender][token];
        if (amt == 0) revert CollateralNotFound();
        _withdrawableTokens[loanId][msg.sender][token] = 0;
        IERC20(token).safeTransfer(msg.sender, amt);
    }

    // ----------------------------
    // Views / getters
    // ----------------------------

    /// @notice Return a compact loan tuple (matches what your tests expect)
    function getLoan(uint256 id) external view returns (
        address borrower,
        PaymentType ptype,
        address token,
        uint256 amount,
        LoanStatus status,
        uint256 disbursedAt,
        uint256 totalRepaid,
        uint256 accruedPenalty,
        uint256 threshold,
        uint256 installmentCount,
        uint256 nextInstallmentIndex
    ) {
        Loan storage L = _loans[id];
        return (
            L.borrower,
            L.paymentType,
            L.token,
            L.amount,
            L.status,
            L.disbursedAt,
            L.totalRepaid,
            L.accruedPenalty,
            L.threshold,
            L.installmentCount,
            L.nextInstallmentIndex
        );
    }

    function getAppointedGuarantors(uint256 id) external view returns (address[] memory) {
        return _loans[id].appointedGuarantors;
    }

    function getGuarantorInfo(uint256 loanId, address guarantor) external view returns (
        bool appointed,
        uint256 pledgedAmount,
        bool pledgedOnChain,
        bool collateralIsToken,
        bool returned,
        bool agreed
    ) {
        GuarantorInfo storage g = _guarantorInfo[loanId][guarantor];
        return (g.appointed, g.pledgedAmount, g.pledgedOnChain, g.collateralIsToken, g.returned, g.agreed);
    }

    function withdrawableNative(uint256 loanId, address guarantor) external view returns (uint256) {
        return _withdrawableNative[loanId][guarantor];
    }

    function withdrawableToken(uint256 loanId, address guarantor, address token) external view returns (uint256) {
        return _withdrawableTokens[loanId][guarantor][token];
    }

    function getLoanDetails(uint256 loanId)
    external
    view
    returns (
        address borrower,
        SaccoLoanManager.PaymentType paymentType,
        address tokenAddress,
        uint256 guarantorCount,
        uint256 amount,
        uint256 interestRate,
        uint256 duration,
        uint256 dueDate,
        bool isRepaid
    )
{
    Loan storage loan = _loans[loanId];

    return (
        loan.borrower,
        loan.paymentType,
        loan.token,        // <-- fix here
        loan.appointedGuarantors.length, // replace guarantorCount
        loan.amount,
        0, // interestRate is not stored yet
        0, // duration is not stored yet
        0, // dueDate is not stored yet
        loan.status == LoanStatus.FullyRepaid
    );
}


    // Accept ETH transfers (used to fund contract)
    receive() external payable {}
}
