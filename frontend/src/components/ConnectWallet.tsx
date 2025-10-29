import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { injected } from 'wagmi/connectors'
import { useRole } from '../hooks/userRole'

export default function ConnectWallet() {
  const { connect } = useConnect()
  const { disconnect } = useDisconnect()
  const { address, isConnected } = useAccount()
  const { isAdmin, isOperator } = useRole()

  return (
    <div className="p-4 bg-white rounded shadow">
      {isConnected ? (
        <div>
          <p className="mb-2">Connected: {address}</p>
          {isAdmin && <p className="text-green-600">Role: Admin</p>}
          {isOperator && !isAdmin && <p className="text-purple-600">Role: Operator</p>}
          {!isAdmin && !isOperator && <p className="text-gray-600">Role: Member</p>}
          <button onClick={() => disconnect()} className="mt-4 bg-red-500 text-white px-4 py-2 rounded">
            Disconnect
          </button>
        </div>
      ) : (
        <button onClick={() => connect({ connector: injected() })} className="bg-blue-600 text-white px-4 py-2 rounded">
          Connect Wallet
        </button>
      )}
    </div>
  )
}