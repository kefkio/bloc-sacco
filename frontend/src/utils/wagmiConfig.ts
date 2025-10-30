import { createConfig, http } from 'wagmi'
import { sepolia } from 'wagmi/chains'
import { injected } from 'wagmi/connectors'

const INFURA_ID = import.meta.env.VITE_INFURA_ID

export const wagmiConfig = createConfig({
  chains: [sepolia],
  connectors: [injected()],
  transports: {
    [sepolia.id]: http(`https://rpc.metamask.io/v1/${INFURA_ID}`),
  },
})