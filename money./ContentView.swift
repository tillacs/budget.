//
//  ContentView.swift
//  money.
//
//  Created by Till Kokemoor on 15.08.26.
//

import SwiftUI

struct ContentView: View {
    let store: AppStore

    var body: some View {
        RootScreen(store: store)
    }
}

#Preview {
    ContentView(store: .preview)
}
