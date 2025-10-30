import { useState } from 'react'
import {
  useAccount,
  useContractWrite,
  useWaitForTransactionReceipt,
} from 'wagmi'
import { parseEther } from 'viem'
import { readContract } from '@wagmi/core' // ✅ readContract import

// Smart contract details
import {
  saccoAbi,
  saccoAddress,
  nftValidatorAbi,
  nftValidatorAddress,
} from '../../../utils/contracts'

// Local helpers
import { wagmiConfig } from '../../../utils/wagmiConfig'
import { mainnet } from 'viem/chains'

// ✅ Add this helper function at the top (before export)
function getRepaymentInterval(loanType: string, category: string): number {
  if (loanType === 'short') {
    return category === 'emergency' ? 30 : 60 // short-term loans
  } else {
    return category === 'business' ? 180 : 365 // long-term loans
  }
}

// (Optional) You may also later define validateAddress() and validateAmount()
// below if needed to avoid further ReferenceErrors
// ✅ Helper function to validate Ethereum address
function validateAddress(address: string): boolean {
  return /^0x[a-fA-F0-9]{40}$/.test(address.trim())
}

// ✅ Helper function to validate loan amount
function validateAmount(amount: string): boolean {
  const value = parseFloat(amount)
  return !isNaN(value) && value > 0
}

export function useLoanRequest() {
  const { address } = useAccount()

  // Form state
  const [loanType, setLoanType] = useState<'short' | 'long'>('short')
  const [category, setCategory] = useState('')
  const [amount, setAmount] = useState('')
  const [token, setToken] = useState('')
  const [guarantors, setGuarantors] = useState<string[]>([])
  const [nftContract, setNftContract] = useState('')
  const [tokenId, setTokenId] = useState('')
  const [nftValid, setNftValid] = useState<boolean | null>(null)
  const [submitted, setSubmitted] = useState(false)
  const [nftChecking, setNftChecking] = useState(false)

  // Wagmi contract write + receipt tracking
  const { data: txHash, writeContract } = useContractWrite()
  const { isLoading, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  // Derived state
  const interval = getRepaymentInterval(loanType, category)
  const isValidAddress = validateAddress(token)
  const isValidAmount = validateAmount(amount)
  const isValidGuarantors = guarantors.length > 0

  // Validate NFT ownership
  const validateNftOwnership = async () => {
    if (!address || !nftContract || !tokenId || !/^\d+$/.test(tokenId)) {
      setNftValid(false)
      return
    }

    try {
      setNftChecking(true)
      const result = await readContract(wagmiConfig, {
        address: nftValidatorAddress as `0x${string}`,
        abi: nftValidatorAbi,
        functionName: 'isOwner',
        args: [address as `0x${string}`, nftContract as `0x${string}`, BigInt(tokenId)],
      })
      setNftValid(Boolean(result))
    } catch (error) {
      console.error('NFT validation failed:', error)
      setNftValid(false)
    } finally {
      setNftChecking(false)
    }
  }

  // Submit loan request
  const handleSubmit = async () => {
    if (!address) {
      console.error('No connected wallet address.')
      return
    }

    if (!isValidAmount || !isValidAddress || !interval || !category || !isValidGuarantors) {
      console.error('Form validation failed.')
      return
    }

    if (nftContract && tokenId && nftValid === false) {
      console.error('Invalid NFT collateral.')
      return
    }

    try {
      await writeContract({
        address: saccoAddress,
        abi: saccoAbi,
        functionName: 'requestLoan',
        args: [
          parseEther(amount),
          token,
          BigInt(interval),
          guarantors,
          nftContract || '0x0000000000000000000000000000000000000000',
          nftContract ? BigInt(tokenId) : BigInt(0),
        ],
        account: address,
      })
      setSubmitted(true)
    } catch (error) {
      console.error('Loan request failed:', error)
    }
  }

  return {
    // State
    address,
    loanType,
    setLoanType,
    category,
    setCategory,
    amount,
    setAmount,
    token,
    setToken,
    guarantors,
    setGuarantors,
    nftContract,
    setNftContract,
    tokenId,
    setTokenId,
    nftValid,
    nftChecking,
    validateNftOwnership,
    submitted,
    isLoading,
    isSuccess,

    // Derived
    interval,
    isValidAddress,
    isValidAmount,
    isValidGuarantors,

    // Actions
    handleSubmit,
  }
}
