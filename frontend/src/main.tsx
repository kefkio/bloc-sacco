import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import { WagmiProvider } from 'wagmi'
import { config } from './utils/wagmiConfig'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

const queryClient = new QueryClient()

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <WagmiProvider config={config}>
        <App />
      </WagmiProvider>
    </QueryClientProvider>
  </React.StrictMode>
)