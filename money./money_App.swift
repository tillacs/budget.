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
    @State private var importError: String?

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
            .task {
                if router.pending != nil { showLaunch = false }
                importFromLaunchArguments()
            }
            // Der Export kommt aus dem Teilen-Menü oder aus „Dateien" hier an.
            .onOpenURL { url in
                showLaunch = false
                open(url)
            }
            .alert("Import nicht möglich", isPresented: Binding(
                get: { importError != nil }, set: { if !$0 { importError = nil } })
            ) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func open(_ url: URL) {
        do {
            try store.importTradeRepublic(try ImportFile.read(url))
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Nur für den Simulator: `-importCSV <Pfad>` liest beim Start eine Datei vom
    /// Mac ein, damit sich der Import ohne Teilen-Menü ansehen lässt.
    private func importFromLaunchArguments() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-importCSV"), index + 1 < arguments.count
        else { return }
        showLaunch = false
        open(URL(fileURLWithPath: arguments[index + 1]))
        #endif
    }
}
