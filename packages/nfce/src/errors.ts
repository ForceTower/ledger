/** Failure modes the NFC-e pipeline can surface. These mirror the API's wire `ScanErrorCode` so the
 * HTTP layer can map them without string matching, while this package stays HTTP-agnostic. */
export type NfceErrorCode = "invalid_url" | "expired" | "unavailable" | "parse_failed";

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
