import AppIntents
import CoreSpotlight
import LedgerKit

/// Donates the mirrored purchases to the system index, making them visible to
/// Spotlight, Siri suggestions, and Shortcuts automations. Best effort: the
/// donation is rebuilt from the mirror on every pass, so a missed one only
/// delays freshness.
enum SpotlightIndexer {
    static func reindex() async {
        guard let summaries = try? await PurchaseMirror.summaries(), !summaries.isEmpty else { return }
        try? await CSSearchableIndex.default().indexAppEntities(summaries.map(PurchaseEntity.init))
    }
}
