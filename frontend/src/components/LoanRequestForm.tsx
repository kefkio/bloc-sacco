import { useState } from 'react'
import { useAccount, useContractWrite, useWaitForTransactionReceipt } from 'wagmi'
import { saccoAbi, saccoAddress } from '../utils/contracts'
import { parseEther } from 'viem'

export default function LoanRequestForm() {
  const { address } = useAccount()
  const [amount, setAmount] = useState('')
  const [token, setToken] = useState('')
  const [interval, setInterval] = useState('')
  const [submitted, setSubmitted] = useState(false)

  const { data: txHash, writeContract } = useContractWrite()
  const { isLoading, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  const handleSubmit = () => {
    if (!amount || !token || !interval) return

    writeContract({
      address: saccoAddress,
      abi: saccoAbi,
      functionName: 'requestLoan',
      args: [parseEther(amount), token, BigInt(interval)],
      account: address,
    })

    setSubmitted(true)
  }

  return (
    <div className="p-4 bg-white rounded shadow mt-6">
      <h2 className="text-xl font-semibold mb-4">Request a Loan</h2>
      <div className="space-y-4">
        <input
          type="text"
          placeholder="Amount (ETH)"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="w-full p-2 border rounded"
        />
        <input
          type="text"
          placeholder="Token address"
          value={token}
          onChange={(e) => setToken(e.target.value)}
          className="w-full p-2 border rounded"
        />
        <input
          type="number"
          placeholder="Repayment interval (days)"
          value={interval}
          onChange={(e) => setInterval(e.target.value)}
          className="w-full p-2 border rounded"
        />
        <button
          onClick={handleSubmit}
          className="bg-green-600 text-white px-4 py-2 rounded"
          disabled={isLoading}
        >
          {isLoading ? 'Submitting...' : 'Submit Loan Request'}
        </button>
        {submitted && isSuccess && <p className="text-green-600 mt-2">Loan request submitted successfully!</p>}
      </div>
    </div>
  )
}