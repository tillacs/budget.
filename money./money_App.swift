//
//  money_App.swift
//  money.
//
//  Created by Till Kokemoor on 15.08.26.
//

import SwiftUI

@main
struct money_App: App {
    @State private var store = AppStore.loadFromDisk()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
