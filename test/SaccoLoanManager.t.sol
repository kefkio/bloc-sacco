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

    // Correct dynamic array initialization
    ops = new address[](1);
    ops[0] = operator;

    manager = new SaccoLoanManager(admin, ops);

    vm.startPrank(admin);
    manager.grantRole(manager.OPERATOR_ROLE(), operator);
    vm.stopPrank();

    // Register members and verify KYC
    vm.prank(borrower);
    manager.registerMember();
    manager.updateKyc(borrower, SaccoLoanManager.KycStatus.Verified);

    vm.prank(guarantor1);
    manager.registerMember();
    manager.updateKyc(guarantor1, SaccoLoanManager.KycStatus.Verified);

    vm.prank(guarantor2);
    manager.registerMember();
    manager.updateKyc(guarantor2, SaccoLoanManager.KycStatus.Verified);

    garr = new address[](2);

    garr[0] = guarantor1;
    garr[1] = guarantor2;
}
    function testNativeLoanRequest() public {
        vm.startPrank(borrower);
        uint256 loanId = manager.requestLoan(
            1 ether,
            SaccoLoanManager.PaymentType.Native,
            address(0),
            2,
            1 days,
            garr
        );
        vm.stopPrank();

        (
            address borrowerAddr,
            SaccoLoanManager.PaymentType paymentType,
            , // tokenAddress unused
            , // guarantorCount unused
            uint256 amount,
            , // interestRate unused
            , // duration unused
            , // dueDate unused
            bool isRepaid
        ) = manager.getLoanDetails(loanId);

        assertEq(borrowerAddr, borrower, "Borrower mismatch");
        assertEq(amount, 1 ether, "Loan amount mismatch");
        assertEq(uint256(paymentType), uint256(SaccoLoanManager.PaymentType.Native), "Payment type mismatch");
        assertEq(isRepaid, false, "Loan should not be repaid yet");
    }

    function testFiatLoanRequest() public {
        vm.startPrank(borrower);
        uint256 loanId = manager.requestLoan(
            1000,
            SaccoLoanManager.PaymentType.Fiat,
            address(0),
            2,
            1 days,
            garr
        );
        vm.stopPrank();

        (
            , // borrower unused
            , // paymentType unused
            , // tokenAddress unused
            , // guarantorCount unused
            uint256 amount,
            , // interestRate unused
            , // duration unused
            , // dueDate unused
            bool isRepaid
        ) = manager.getLoanDetails(loanId);

        assertEq(amount, 1000, "Loan amount mismatch");
        assertEq(isRepaid, false, "Loan should not be repaid yet");
    }
}
