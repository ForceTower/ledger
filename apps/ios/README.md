# ledger iOS

Native iOS app (Swift + SwiftUI, **The Composable Architecture**). Scans the NFC-e QR, posts it to
the API, shows what was saved, and browses spending history.

## Architecture

The app is built with [TCA](https://github.com/pointfreeco/swift-composable-architecture) and the
**Swift 6 language mode with complete strict concurrency**.

```
apps/ios/
  Ledger.xcodeproj        thin app shell (Swift 6 + complete concurrency, MainActor default isolation)
  Ledger/LedgerApp.swift  @main App — imports LedgerKit and hosts RootView()
  LedgerKit/              local Swift package — all feature code lives here
    Package.swift          swiftLanguageModes: [.v6], depends on swift-composable-architecture
    Sources/LedgerKit/
      AppFeature.swift     root @Reducer (currently a minimal scaffold)
      AppView.swift        the feature's SwiftUI view (store-driven)
      RootView.swift       public entry the app embeds; owns the root Store
    Tests/LedgerKitTests/  TestStore-based tests
```

**Why a local package?** Feature code + tests live in `LedgerKit` so the app target never imports TCA
directly (it's linked exactly once, in the package). This also lets the package compile with plain
(nonisolated) default isolation, which avoids a `@Reducer` + default-MainActor compiler issue
([#3714](https://github.com/pointfreeco/swift-composable-architecture/discussions/3714)) and keeps
reducers idiomatic (`var body: some ReducerOf<Self>`). The app shell keeps `MainActor` default
isolation for its SwiftUI code. Both build under Swift 6 / complete concurrency.

## Build & test

```sh
# Build the app for a simulator
xcodebuild build -scheme Ledger -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run the feature tests (fastest — runs natively on the macOS host)
cd LedgerKit && swift test
```

In Xcode, the package's tests run with ⌘U from the auto-generated **LedgerKit** scheme.

## Before you build

- The wire contract is `docs/api-contract.md` (source of truth) and `packages/shared-types/src/index.ts`.
  Mirror those types in Swift `Codable` models. All field names are English; user-facing copy is pt-BR.
- The backend (`apps/api`) returns mock data shaped exactly like the contract, so you can run the app
  against a real local server immediately, or against an in-app mock client, then flip via Settings
  (server URL + bearer token).

See the repo `CLAUDE.md` for iOS conventions (Swift 6, native feel, BRL formatting).
