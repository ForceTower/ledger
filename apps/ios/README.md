# ledger iOS

Native iOS app (Swift + SwiftUI). Scans the NFC-e QR, posts it to the API, shows what was saved, and
browses spending history.

This folder will hold a standard Xcode project. It is intentionally empty until the iOS work starts.

## Before you build

- The wire contract is `docs/api-contract.md` (source of truth) and `packages/shared-types/src/index.ts`.
  Mirror those types in Swift `Codable` models. All field names are English; user-facing copy is pt-BR.
- The backend (`apps/api`) returns mock data shaped exactly like the contract, so you can run the app
  against a real local server immediately, or against an in-app mock client, then flip via Settings
  (server URL + bearer token).

See the repo `CLAUDE.md` for iOS conventions (Swift 6, native feel, BRL formatting).
