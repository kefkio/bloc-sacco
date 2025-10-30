// src/utils/wagmiConfig.ts
import { createConfig, http } from 'wagmi'
import { mainnet } from 'wagmi/chains'

export const wagmiConfig = createConfig({
  chains: [mainnet],
  transports: {
    [mainnet.id]: http('https://mainnet.infura.io/v3/YOUR_INFURA_ID'),
  },
})
