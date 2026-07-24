//
//  AuthView.swift
//  Ponder
//

import SwiftUI
import AuthenticationServices
import Auth

struct AuthView: View {
    var title: String = "Canvio"
    var subtitle: String = "Sign in to sync across devices. Local canvases stay on this device until sync is enabled."
    var showsGuestButton: Bool = false
    var onSignedIn: () -> Void = { }

    @ObservedObject var auth = AuthService.shared

    @Environment(\.authorizationController) private var authorizationController
    @Environment(\.dismiss) private var dismiss
    @State private var didCompleteSignIn = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 28)

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
                                Text(title)
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)

                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                        }
                        .padding(.bottom, 36)

                        Spacer(minLength: 20)

                        // Sign in section
                        VStack(spacing: 14) {
                            if let error = auth.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                                    .transition(.opacity)
                            }

                            Button {
                                Task { await auth.signInWithGoogle() }
                            } label: {
                                HStack(spacing: 12) {
                                    Text("G")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                                    Text("Continue with Google")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(.background, in: RoundedRectangle(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(.secondary.opacity(0.35), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 32)
                            .disabled(auth.isLoading)

                            #if os(macOS)
                            SignInWithAppleButton(.signIn) { request in
                                auth.prepareRequest(request)
                            } onCompletion: { result in
                                Task { @MainActor in
                                    switch result {
                                    case .success(let authorization):
                                        await auth.handleAuthorization(authorization)
                                        completeSignInPresentationIfNeeded()
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

                            if showsGuestButton {
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
                            }

                            Text("Your local canvases stay on this device. Sign in after Pro to turn on sync.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .padding(.bottom, 28)
                    }
                    .frame(minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.errorMessage)
        .onChange(of: auth.currentUser?.id.uuidString) { _, userID in
            guard userID != nil else { return }
            completeSignInPresentationIfNeeded()
        }
    }

    private func completeSignInPresentationIfNeeded() {
        guard auth.currentUser != nil, !didCompleteSignIn else { return }
        didCompleteSignIn = true
        onSignedIn()
        dismiss()
    }
}

#Preview {
    AuthView()
}
