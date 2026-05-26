//
//  ContentView.swift
//  Ponder
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            if settings.hasSeenOnboarding {
                HomeView()
            } else {
                OnboardingView {
                    settings.hasSeenOnboarding = true
                    AuthService.shared.continueAsGuest()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: settings.hasSeenOnboarding)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
}
