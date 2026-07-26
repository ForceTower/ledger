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

// Never 502/504 here: the production Cloudflare Tunnel replaces those bodies with its own error
// stub, so the JSON envelope (and its errorCode) would never reach the client. Upstream failures
// ride on 4xx instead — clients key off errorCode, not the status.
const NFCE_STATUS: Record<NfceErrorCode, number> = {
  invalid_url: 400,
  expired: 404,
  unavailable: 424,
  parse_failed: 422,
  qr_rejected: 422,
  captcha_rejected: 422,
};

/** Translate a pipeline error into the HTTP envelope the contract documents for `/scan`. */
export function ledgerErrorFromNfce(error: NfceError): LedgerError {
  return new LedgerError(NFCE_STATUS[error.code], error.message, error.code);
}
