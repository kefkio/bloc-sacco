// src/components/forms/utils/validations.ts

/** Validates Ethereum-style address */
export const validateAddress = (address: string): boolean => /^0x[a-fA-F0-9]{40}$/.test(address)

/** Validates numeric amount greater than zero */
export const validateAmount = (amount: string): boolean => !isNaN(Number(amount)) && Number(amount) > 0
