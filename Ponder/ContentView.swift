//
//  ContentView.swift
//  Ponder
//

import SwiftUI
import Auth

struct ContentView: View {
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        Group {
            if auth.currentUser != nil || auth.isGuest {
                HomeView()
            } else {
                AuthView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.currentUser?.id.uuidString)
        .animation(.easeInOut(duration: 0.3), value: auth.isGuest)
    }
}

#Preview {
    ContentView()
}
