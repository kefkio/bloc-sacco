// src/components/Forms/LoanDetails.tsx
import React from 'react'

export function LoanDetails() {
  return (
    <div className="space-y-4">
      <h2 className="text-xl font-semibold">Loan Details</h2>

      <div>
        <label htmlFor="amount" className="block text-sm font-medium text-gray-700">
          Loan Amount
        </label>
        <input
          type="number"
          id="amount"
          name="amount"
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:ring-indigo-500 focus:border-indigo-500"
          placeholder="Enter amount in stablecoin"
        />
      </div>

      <div>
        <label htmlFor="duration" className="block text-sm font-medium text-gray-700">
          Duration (months)
        </label>
        <input
          type="number"
          id="duration"
          name="duration"
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:ring-indigo-500 focus:border-indigo-500"
          placeholder="e.g. 12"
        />
      </div>

      <div>
        <label htmlFor="purpose" className="block text-sm font-medium text-gray-700">
          Purpose
        </label>
        <textarea
          id="purpose"
          name="purpose"
          rows={3}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:ring-indigo-500 focus:border-indigo-500"
          placeholder="Brief description of loan purpose"
        />
      </div>
    </div>
  )
}