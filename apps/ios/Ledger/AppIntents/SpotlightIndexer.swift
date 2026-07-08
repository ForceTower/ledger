import AppIntents
import CoreSpotlight
import LedgerKit

enum SpotlightIndexer {
    static func reindex() async {
        guard let summaries = try? await PurchaseMirror.summaries(), !summaries.isEmpty else { return }
        try? await CSSearchableIndex.default().indexAppEntities(summaries.map(PurchaseEntity.init))
    }
}
