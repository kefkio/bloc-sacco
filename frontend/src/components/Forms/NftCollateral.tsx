export function NftCollateral({
  nftContract,
  tokenId,
  setNftContract,
  setTokenId,
  validateNftOwnership,
  nftValid,
}: {
  nftContract: string
  tokenId: string
  setNftContract: (address: string) => void
  setTokenId: (id: string) => void
  validateNftOwnership: () => void
  nftValid: boolean | null
}) {
  // JSX here
}