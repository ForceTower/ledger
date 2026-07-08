import ComposableArchitecture
import Foundation
import GRDB

func appDatabase() throws -> any DatabaseWriter {
    try FileManager.default.createDirectory(
        at: .applicationSupportDirectory,
        withIntermediateDirectories: true
    )
    let path = URL.applicationSupportDirectory.appending(path: "ledger.sqlite").path(percentEncoded: false)
    let database = try DatabaseQueue(path: path)
    try migrator().migrate(database)
    return database
}

func inMemoryDatabase() throws -> any DatabaseWriter {
    let database = try DatabaseQueue()
    try migrator().migrate(database)
    return database
}

private func migrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
    #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("v1") { db in
        try db.create(table: "purchases") { t in
            t.primaryKey("slug", .text)
            t.column("date", .text).notNull()
            t.column("time", .text).notNull()
            t.column("source", .text).notNull()
            t.column("storeName", .text).notNull()
            t.column("storeLegalName", .text)
            t.column("storeCnpj", .text)
            t.column("storeAddress", .text)
            t.column("receiptNumber", .integer)
            t.column("receiptSeries", .integer)
            t.column("receiptAccessKey", .text)
            t.column("itemCount", .integer).notNull()
            t.column("gross", .double).notNull()
            t.column("discount", .double).notNull()
            t.column("totalPaid", .double).notNull()
            t.column("taxesTotal", .double)
        }
        try db.create(table: "purchaseItems") { t in
            t.column("purchaseSlug", .text).notNull()
                .references("purchases", onDelete: .cascade)
            t.column("seq", .integer).notNull()
            t.column("itemDescription", .text).notNull()
            t.column("code", .text).notNull()
            t.column("barcode", .text)
            t.column("quantity", .double).notNull()
            t.column("unit", .text).notNull()
            t.column("unitPrice", .double).notNull()
            t.column("total", .double).notNull()
            t.column("category", .text).notNull()
            t.primaryKey(["purchaseSlug", "seq"])
        }
        try db.create(table: "payments") { t in
            t.column("purchaseSlug", .text).notNull()
                .references("purchases", onDelete: .cascade)
            t.column("seq", .integer).notNull()
            t.column("code", .integer)
            t.column("method", .text).notNull()
            t.column("amount", .double).notNull()
            t.column("change", .double)
            t.primaryKey(["purchaseSlug", "seq"])
        }
    }
    return migrator
}

private enum DatabaseKey: DependencyKey {
    static let liveValue: any DatabaseWriter = {
        do { return try appDatabase() } catch { return try! inMemoryDatabase() }
    }()

    static var testValue: any DatabaseWriter { try! inMemoryDatabase() }
    static var previewValue: any DatabaseWriter { try! inMemoryDatabase() }
}

extension DependencyValues {
    var database: any DatabaseWriter {
        get { self[DatabaseKey.self] }
        set { self[DatabaseKey.self] = newValue }
    }
}
