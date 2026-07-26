/** Failure modes the NFC-e pipeline can surface. These mirror the API's wire `ScanErrorCode` so the
 * HTTP layer can map them without string matching, while this package stays HTTP-agnostic. */
export type NfceErrorCode =
  | "invalid_url"
  | "expired"
  | "unavailable"
  | "parse_failed"
  /** SEFAZ validated the QR payload and refused it (e.g. the store signs with a revoked CSC). The
   * receipt usually still exists — the access-key consultation is the way in. */
  | "qr_rejected"
  /** The owner's answer to the access-key consultation captcha was wrong. */
  | "captcha_rejected";

export class NfceError extends Error {
  constructor(
    readonly code: NfceErrorCode,
    message: string,
    cause?: unknown,
  ) {
    super(message, cause === undefined ? undefined : { cause });
    this.name = "NfceError";
  }
}
