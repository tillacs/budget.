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

    /// Startanimation der Wortmarke — läuft einmal pro Kaltstart.
    @State private var showLaunch = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(store: store)

                if showLaunch {
                    LaunchWordmark(stem: "budget") { showLaunch = false }
                        .transition(.opacity)
                }
            }
        }
    }
}
