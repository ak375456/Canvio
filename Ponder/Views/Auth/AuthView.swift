//
//  AuthView.swift
//  Ponder
//

import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @ObservedObject var auth = AuthService.shared

    @Environment(\.authorizationController) private var authorizationController

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App icon + name
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.8), Color.accentColor],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 96, height: 96)
                            .shadow(color: Color.accentColor.opacity(0.4), radius: 20, x: 0, y: 8)

                        Image(systemName: "square.on.square.dashed")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 6) {
                        Text("Canvio")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Your ideas, beautifully organised")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, 64)

                Spacer()

                // Sign in section
                VStack(spacing: 16) {
                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .transition(.opacity)
                    }

                    #if os(macOS)
                    SignInWithAppleButton(.signIn) { request in
                        guard let appleRequest = request as? ASAuthorizationAppleIDRequest else { return }
                        auth.prepareRequest(appleRequest)
                    } onCompletion: { result in
                        Task { @MainActor in
                            switch result {
                            case .success(let authorization):
                                await auth.handleAuthorization(authorization)
                            case .failure(let error):
                                auth.handleAuthError(error)
                            }
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 54)
                    .cornerRadius(14)
                    .padding(.horizontal, 32)
                    .opacity(auth.isLoading ? 0.5 : 1)
                    .disabled(auth.isLoading)
                    .overlay {
                        if auth.isLoading { ProgressView().tint(.white) }
                    }

                    #else
                    SignInWithAppleButton(.signIn) { _ in
                        auth.signInWithApple()
                    } onCompletion: { _ in }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 54)
                    .cornerRadius(14)
                    .padding(.horizontal, 32)
                    .opacity(auth.isLoading ? 0.5 : 1)
                    .disabled(auth.isLoading)
                    .overlay {
                        if auth.isLoading { ProgressView().tint(.white) }
                    }
                    #endif

                    // Guest option
                    Button {
                        auth.continueAsGuest()
                    } label: {
                        Text("Continue without account")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .disabled(auth.isLoading)

                    Text("Sign in to sync across devices. Guest data stays on this device only.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 48)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.errorMessage)
    }
}

#Preview {
    AuthView()
}
