// src/components/forms/GuarantorSelector.tsx
import React from 'react'

export function GuarantorSelector({
  guarantors,
  setGuarantors,
}: {
  guarantors: string[]
  setGuarantors: (guarantors: string[]) => void
}) {
  const handleChange = (index: number, value: string) => {
    const updated = [...guarantors]
    updated[index] = value
    setGuarantors(updated)
  }

  const addGuarantor = () => {
    setGuarantors([...guarantors, ''])
  }

  const removeGuarantor = (index: number) => {
    const updated = guarantors.filter((_, i) => i !== index)
    setGuarantors(updated)
  }

  return (
    <div className="space-y-4">
      <h3 className="text-lg font-medium">Guarantors</h3>
      {guarantors.map((address, index) => (
        <div key={index} className="flex items-center gap-2">
          <input
            type="text"
            value={address}
            onChange={(e) => handleChange(index, e.target.value)}
            placeholder="Guarantor wallet address"
            className="flex-1 rounded-md border-gray-300 shadow-sm focus:ring-indigo-500 focus:border-indigo-500"
          />
          <button
            type="button"
            onClick={() => removeGuarantor(index)}
            className="text-red-600 hover:underline"
          >
            Remove
          </button>
        </div>
      ))}
      <button
        type="button"
        onClick={addGuarantor}
        className="bg-indigo-600 text-white px-3 py-1 rounded"
      >
        Add Guarantor
      </button>
    </div>
  )
}