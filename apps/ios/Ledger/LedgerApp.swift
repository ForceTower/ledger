//
//  LedgerApp.swift
//  Ledger
//
//  Created by João Paulo Santos Sena on 29/06/26.
//

import LedgerKit
import SwiftUI

@main
struct LedgerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // All feature code lives in the LedgerKit package; the app target
            // is just a shell that hosts the package's root view plus the
            // system-facing App Intents glue.
            RootView()
                .task { await SpotlightIndexer.reindex() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Re-donate on backgrounding so purchases scanned this session
            // reach the system index too.
            if phase == .background {
                Task { await SpotlightIndexer.reindex() }
            }
        }
    }
}
