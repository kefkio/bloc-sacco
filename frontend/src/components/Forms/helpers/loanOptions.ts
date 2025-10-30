// src/components/forms/helpers/loanOptions.ts

export const loanOptions = {
  short: { intervals: { Emergency: 24, Express: 36, Jisort: 48 } },
  long: { intervals: { Normal: 72, Jumbo: 96, Jijenge: 60 } },
}

/** Returns repayment interval based on loan type and category */
export const getRepaymentInterval = (type: 'short' | 'long', category: string): number | undefined => {
  return loanOptions[type]?.intervals?.[category as keyof typeof loanOptions['short']['intervals']]
}
