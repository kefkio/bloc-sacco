import { useContractRead } from 'wagmi'
import { useAccount } from 'wagmi'
import { keccak256, toHex } from 'viem'
import { saccoAbi, saccoAddress } from '../utils/contracts.ts'

const getRoleHash = (role: string) => keccak256(toHex(role))

export function useRole() {
  const { address } = useAccount()

  const { data: isAdmin } = useContractRead({
    address: saccoAddress,
    abi: saccoAbi,
    functionName: 'hasRole',
    args: ['0x00', address], // DEFAULT_ADMIN_ROLE
    enabled: !!address,
  })

  const { data: isOperator } = useContractRead({
    address: saccoAddress,
    abi: saccoAbi,
    functionName: 'hasRole',
    args: [getRoleHash('OPERATOR_ROLE'), address],
    enabled: !!address,
  })

  return {
    isAdmin: Boolean(isAdmin),
    isOperator: Boolean(isOperator),
  }
}