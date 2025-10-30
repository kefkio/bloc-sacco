// src/components/forms/LoanTypeSelector.tsx
import React from 'react'

interface LoanTypeSelectorProps {
  loanType: string
  category: string
  setLoanType: (type: string) => void
  setCategory: (category: string) => void
}

export function LoanTypeSelector({
  loanType,
  category,
  setLoanType,
  setCategory,
}: LoanTypeSelectorProps) {
  return (
    <div className="space-y-4">
      <div>
        <label htmlFor="loanType" className="block text-sm font-medium text-gray-700">
          Loan Type
        </label>
        <select
          id="loanType"
          value={loanType}
          onChange={(e) => setLoanType(e.target.value)}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:ring-indigo-500 focus:border-indigo-500"
        >
          <option value="">Select type</option>
          <option value="personal">Personal</option>
          <option value="business">Business</option>
          <option value="emergency">Emergency</option>
        </select>
      </div>

      <div>
        <label htmlFor="category" className="block text-sm font-medium text-gray-700">
          Category
        </label>
        <input
          type="text"
          id="category"
          value={category}
          onChange={(e) => setCategory(e.target.value)}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:ring-indigo-500 focus:border-indigo-500"
          placeholder="e.g. school fees, farming, etc."
        />
      </div>
    </div>
  )
}