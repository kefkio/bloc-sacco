import sacco from '../abi/Sacco.json'
import nftValidator from '../abi/NftValidator.json'

export const saccoAbi = (sacco as { abi: any[] }).abi
export const saccoAddress = '0xYourContractAddressHere'

export const nftValidatorAbi = (nftValidator as { abi: any[] }).abi
export const nftValidatorAddress = '0xYourValidatorContractAddressHere'