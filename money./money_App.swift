//
//  money_App.swift
//  money.
//
//  Created by Till Kokemoor on 15.08.26.
//

import SwiftUI

@main
struct money_App: App {
    @State private var store = AppStore.shared

    /// Startanimation der Wortmarke — läuft einmal pro Kaltstart.
    @State private var showLaunch = true

    private let router = QuickEntryRouter.shared

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeScreen(store: store)

                if showLaunch {
                    LaunchWordmark(stem: "budget") { showLaunch = false }
                        .transition(.opacity)
                }
            }
            // Wer über den Doppeltipp kommt, will tippen und nicht zusehen: Sobald ein
            // Kurzbefehl etwas anfordert, entfällt die Startanimation.
            .onChange(of: router.token) { showLaunch = false }
            .task { if router.pending != nil { showLaunch = false } }
        }
    }
}
