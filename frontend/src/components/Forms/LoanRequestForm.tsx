// src/components/forms/LoanRequestForm.tsx
import { useLoanRequest } from './hooks/useLoanRequest'
import { LoanTypeSelector } from './LoanTypeSelector'
import { LoanDetails } from './LoanDetails'
import { GuarantorSelector } from './GuarantorSelector'
import { NftCollateral } from './NftCollateral'



export default function LoanRequestForm() {
  const loan = useLoanRequest()

  return (
    <div className="p-6 bg-white rounded shadow mt-6 max-w-2xl mx-auto space-y-6">
      <h2 className="text-xl font-semibold">SACCO Loan Request</h2>

      {/* Loan type and category */}
      <LoanTypeSelector
        loanType={loan.loanType}
        category={loan.category}
        setLoanType={loan.setLoanType}
        setCategory={loan.setCategory}
      />

      {/* Loan details */}
      <LoanDetails
        amount={loan.amount}
        token={loan.token}
        setAmount={loan.setAmount}
        setToken={loan.setToken}
        interval={loan.interval}
      />

      {/* Guarantors */}
      <GuarantorSelector
        guarantors={loan.guarantors}
        setGuarantors={loan.setGuarantors}
      />

      {/* Optional NFT collateral */}
      <NftCollateral
        nftContract={loan.nftContract}
        tokenId={loan.tokenId}
        setNftContract={loan.setNftContract}
        setTokenId={loan.setTokenId}
        validateNftOwnership={loan.validateNftOwnership}
        nftValid={loan.nftValid}
      />

      {/* Submit */}
      <button
        onClick={loan.handleSubmit}
        className="bg-green-600 text-white px-4 py-2 rounded disabled:opacity-50"
        disabled={
          loan.isLoading ||
          !loan.isValidAmount ||
          !loan.isValidAddress ||
          !loan.interval ||
          !loan.category ||
          !loan.isValidGuarantors
        }
      >
        {loan.isLoading ? 'Submitting...' : 'Submit Loan Request'}
      </button>

      {/* Feedback */}
      {loan.submitted && loan.isSuccess && (
        <p className="text-green-600 mt-2">Loan request submitted successfully!</p>
      )}
    </div>
  )
}
