import { NfceError } from "@ledger/nfce";
import type { NfceErrorCode } from "@ledger/nfce";

export class LedgerError extends Error {
  constructor(
    public readonly statusCode: number,
    message: string,
    public readonly errorCode?: string,
  ) {
    super(message);
    this.name = "LedgerError";
  }
}

const NFCE_STATUS: Record<NfceErrorCode, number> = {
  invalid_url: 400,
  expired: 502,
  unavailable: 502,
  parse_failed: 422,
};

/** Translate a pipeline error into the HTTP envelope the contract documents for `/scan`. */
export function ledgerErrorFromNfce(error: NfceError): LedgerError {
  return new LedgerError(NFCE_STATUS[error.code], error.message, error.code);
}
