
import LedgerKit
import SwiftUI

@main
struct LedgerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { await SpotlightIndexer.reindex() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await SpotlightIndexer.reindex() }
            }
        }
    }
}
