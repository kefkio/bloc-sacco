import ConnectWallet from './components/ConnectWallet'
import LoanRequestForm from './components/Forms/LoanRequestForm'
import { useAccount } from 'wagmi'

function App() {
  const { isConnected } = useAccount()

  return (
    <div className="min-h-screen bg-gray-100 p-6">
      <h1 className="text-2xl font-bold mb-4">Sacco Loan Manager</h1>
      <ConnectWallet />
      {isConnected && <LoanRequestForm />}
    </div>
  )
}

export default App