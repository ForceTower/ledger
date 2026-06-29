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
    var body: some Scene {
        WindowGroup {
            // All feature code lives in the LedgerKit package; the app target
            // is just a shell that hosts the package's root view.
            RootView()
        }
    }
}
