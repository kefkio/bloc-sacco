// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {SaccoLoanManager} from "../src/SaccoLoanManager.sol";

contract SaccoLoanManagerTest is Test {
    SaccoLoanManager manager;
    address admin;
    address operator;
    address borrower;
    address guarantor1;
    address guarantor2;

    address[] internal ops;
    address[] internal garr;

    

    function setUp() public {
        admin = address(0x1);
        operator = address(0x2);
        borrower = address(0x3);
        guarantor1 = address(0x4);
        guarantor2 = address(0x5);

        address[] memory localOps = new address[](1);
        localOps[0] = operator;
        manager = new SaccoLoanManager(admin, localOps);

        vm.startPrank(admin);
        manager.grantRole(manager.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        _registerAndVerify(borrower);
        _registerAndVerify(guarantor1);
        _registerAndVerify(guarantor2);

        garr = new address[](2);
        garr[0] = guarantor1;
        garr[1] = guarantor2;
    }

    function _registerAndVerify(address user) internal {
        vm.prank(user);
        manager.registerMember();
        vm.prank(operator);
        manager.updateKyc(user, SaccoLoanManager.KycStatus.Verified);
    }

    // --- ✅ BASIC LOAN TESTS ---

    function testNativeLoanRequest() public {
        vm.startPrank(borrower);
        uint256 loanId = manager.requestLoan(
            1 ether,
            SaccoLoanManager.PaymentType.Native,
            address(0),
            2,
            7 days,
            garr
        );
        vm.stopPrank();

        (
            address borrowerAddr,
            SaccoLoanManager.PaymentType payType,
            ,
            uint256 amount,
            ,
            ,
            ,
            ,
            SaccoLoanManager.LoanStatus status
        ) = manager.getLoanDetails(loanId);

        assertEq(borrowerAddr, borrower, "Borrower mismatch");
        assertEq(amount, 1 ether, "Incorrect loan amount");
        assertEq(uint256(payType), uint256(SaccoLoanManager.PaymentType.Native), "PaymentType mismatch");
        assertLoanStatusEq(status, SaccoLoanManager.LoanStatus.Requested);
    }

    // --- ✅ OPERATOR APPROVAL TEST ---

    function testLoanApprovalFlow() public {
        uint256 loanId = _requestLoan();

        vm.startPrank(operator);
        manager.approveLoan(loanId);
        vm.stopPrank();

        (, , , , , , , , SaccoLoanManager.LoanStatus status) = manager.getLoanDetails(loanId);
        assertLoanStatusEq(status, SaccoLoanManager.LoanStatus.Approved);
    }

    // --- ✅ REPAYMENT TEST ---

    function testLoanRepayment() public {
        uint256 loanId = _requestLoan();

        vm.startPrank(operator);
        manager.approveLoan(loanId);
        vm.stopPrank();

        vm.startPrank(borrower);
        manager.repayLoan{value: 1 ether}(loanId, 1 ether);
        vm.stopPrank();

        (, , , , , , , , SaccoLoanManager.LoanStatus status) = manager.getLoanDetails(loanId);
        assertLoanStatusEq(status, SaccoLoanManager.LoanStatus.Repaid);
    }

    // --- ⚠️ EDGE CASE TESTS ---

    function testFailsForUnverifiedKYC() public {
        address newUser = address(0x6);
        vm.prank(newUser);
        manager.registerMember();

        address[] memory dummyGuarantors = new address[](2);
        dummyGuarantors[0] = guarantor1;
        dummyGuarantors[1] = guarantor2;

        vm.startPrank(newUser);
        vm.expectRevert("KYC not verified");
        manager.requestLoan(1 ether, SaccoLoanManager.PaymentType.Native, address(0), 2, 1 days, dummyGuarantors);
        vm.stopPrank();
    }

function testFailsWithInsufficientGuarantors() public {
    address[] memory oneGuarantor = new address[](1);
    oneGuarantor[0] = guarantor1;

    vm.startPrank(borrower);
    vm.expectRevert("Insufficient guarantors");
    manager.requestLoan(1 ether, SaccoLoanManager.PaymentType.Native, address(0), 2, 1 days, oneGuarantor);
    vm.stopPrank();
}

function testFailsWithDuplicateGuarantors() public {
    address[] memory dup = new address[](2);
    dup[0] = guarantor1;
    dup[1] = guarantor1;

    vm.startPrank(borrower);
    vm.expectRevert("Duplicate guarantor");
    manager.requestLoan(1 ether, SaccoLoanManager.PaymentType.Native, address(0), 2, 1 days, dup);
    vm.stopPrank();
}

    function testFailsWhenGuarantorIsBorrower() public {
         address[] memory invalid = new address[](2);
        invalid[0] = borrower;
        invalid[1] = guarantor1;

        vm.startPrank(borrower);
        vm.expectRevert("Guarantor cannot be borrower");
        manager.requestLoan(1 ether, SaccoLoanManager.PaymentType.Native, address(0), 2, 1 days, invalid);
        vm.stopPrank();
    }

    // --- ⚙️ HELPERS ---

    function _requestLoan() internal returns (uint256) {
        vm.startPrank(borrower);
        uint256 loanId = manager.requestLoan(
            1 ether,
            SaccoLoanManager.PaymentType.Native,
            address(0),
            2,
            7 days,
            garr
        );
        vm.stopPrank();
        return loanId;
    }

    // --- 🧩 ENUM ASSERTION HELPER ---

    function assertLoanStatusEq(
        SaccoLoanManager.LoanStatus a,
        SaccoLoanManager.LoanStatus b
    ) pure internal {
        assertEq(uint256(a), uint256(b), "Loan status mismatch");
    }
}
