//
//  SettingsView.swift
//  Canvio
//

import SwiftUI
import SwiftData
import Auth
import StoreKit

struct SettingsView: View {
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var pro = ProManager.shared
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    @State private var displayName: String = ""
    @State private var isEditingName: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showSignOutConfirm: Bool = false
    @State private var showPaywall: Bool = false
    @State private var showAuth: Bool = false
    @State private var showFeedback: Bool = false
    @State private var requestReviewAfterFeedback: Bool = false
    @State private var isSigningOut: Bool = false
    @State private var isDeleting: Bool = false
    @State private var deleteError: String? = nil
    @FocusState private var nameFocused: Bool

    private var user = AuthService.shared.currentUser

    private var initials: String {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            let parts = name.split(separator: " ")
            if parts.count >= 2 {
                return String((parts[0].first ?? "?")).uppercased()
                     + String((parts[1].first ?? "?")).uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
        if let email = user?.email, !email.isEmpty {
            return String(email.prefix(2)).uppercased()
        }
        return "?"
    }

    private var avatarColor: Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red]
        let seed = initials.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[seed % colors.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.title3.weight(.bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)

            Divider()

            ScrollView {
                VStack(spacing: 0) {

                    if auth.currentUser != nil {
                        // MARK: - Profile section
                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .fill(avatarColor.gradient)
                                    .frame(width: 80, height: 80)
                                Text(initials)
                                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .padding(.top, 24)

                            VStack(spacing: 6) {
                                if isEditingName {
                                    HStack(spacing: 8) {
                                        TextField("Your name", text: $displayName)
                                            .font(.title3.weight(.semibold))
                                            .multilineTextAlignment(.center)
                                            .focused($nameFocused)
                                            .submitLabel(.done)
                                            .onSubmit { saveName() }
                                        Button { saveName() } label: {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .font(.title3)
                                        }.buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 24)
                                } else {
                                    Button {
                                        isEditingName = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            nameFocused = true
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(displayName.isEmpty ? "Add your name" : displayName)
                                                .font(.title3.weight(.semibold))
                                                .foregroundStyle(displayName.isEmpty ? .secondary : .primary)
                                            Image(systemName: "pencil")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }

                                Text("Signed in with Apple")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 28)

                        Divider().padding(.horizontal, 24)

                    } else {
                        // MARK: - Guest section
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.secondary.opacity(0.12))
                                    .frame(width: 80, height: 80)
                                Image(systemName: "person")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 24)

                            Text("Not signed in")
                                .font(.title3.weight(.semibold))
                            Text("Sign in to restore your canvases and sync them across all your devices with Canvio Pro.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)

                            Button {
                                handleSignInTap()
                            } label: {
                                Text("Sign In to Restore Canvases")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 10)
                                    .background(Color.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                            .padding(.top, 4).padding(.bottom, 24)
                        }
                        .frame(maxWidth: .infinity)

                        Divider().padding(.horizontal, 24)
                    }

                    // MARK: - General section
                    VStack(spacing: 0) {
                        sectionHeader("GENERAL")

                        settingsRow(icon: "lock.shield", iconColor: .blue, title: "Privacy Policy") {
                            openURL("https://ak375456.github.io/canvio-site/privacy.html")
                        }

                        settingsRow(icon: "doc.text", iconColor: .purple, title: "Terms of Service") {
                            openURL("https://ak375456.github.io/canvio-site/terms.html")
                        }

                        settingsRow(icon: "bubble.left.and.text.bubble.right", iconColor: .teal, title: "Send Feedback") {
                            showFeedback = true
                        }

                        settingsRow(icon: "envelope", iconColor: .orange, title: "Contact Support") {
                            openURL("mailto:ak375456@gmail.com")
                        }

                        settingsRow(icon: "star.bubble", iconColor: .yellow, title: "Rate Canvio") {
                            openURL("https://apps.apple.com/app/id6771719475?action=write-review")
                        }

                        settingsRow(
                            icon: pro.isPro ? "checkmark.seal.fill" : "star.fill",
                            iconColor: pro.isPro ? .green : .yellow,
                            title: purchaseStatusTitle
                        ) {
                            if !pro.canUseCloudSync { showPaywall = true }
                        }
                    }
                    .padding(.top, 8)

                    if auth.currentUser != nil {
                        // MARK: - Account section
                        VStack(spacing: 0) {
                            sectionHeader("ACCOUNT")

                            settingsRow(
                                icon: "rectangle.portrait.and.arrow.right",
                                iconColor: .secondary,
                                title: "Sign Out"
                            ) {
                                showSignOutConfirm = true
                            }

                            settingsRow(
                                icon: "person.crop.circle.badge.minus",
                                iconColor: .red,
                                title: "Delete Account",
                                isDestructive: true
                            ) {
                                showDeleteConfirm = true
                            }
                        }
                        .padding(.top, 8)
                    }

                    if let err = deleteError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    }

                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("Canvio \(version)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
            }
        }
        .task { await loadProfile() }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet {
                if pro.canUseCloudSync, auth.currentUser == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showAuth = true
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
        .sheet(isPresented: $showAuth) {
            AuthView(
                title: "Sign in for Sync",
                subtitle: "Sign in to restore your canvases and sync Canvio Pro across all your devices.",
                onSignedIn: {
                    showAuth = false
                    Task { await loadProfile() }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
        .sheet(isPresented: $showFeedback, onDismiss: requestPendingReviewIfNeeded) {
            FeedbackSheet {
                requestReviewAfterFeedback = true
            }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
        .alert("Sign Out", isPresented: $showSignOutConfirm) {
            Button("Sign Out", role: .destructive) {
                Task { await performSignOut() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll be signed out on this device. Your data stays in the cloud.")
        }
        .alert("Delete Account", isPresented: $showDeleteConfirm) {
            Button("Delete Everything", role: .destructive) {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes your account and all canvases across all devices. This cannot be undone.")
        }
        .overlay {
            if isSigningOut || isDeleting {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(.white)
                        Text(isSigningOut ? "Signing out..." : "Deleting account...")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }

    // MARK: - Helpers

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    private func requestPendingReviewIfNeeded() {
        guard requestReviewAfterFeedback else { return }
        requestReviewAfterFeedback = false

        Task { @MainActor in
            // Give SwiftUI time to finish removing the feedback sheet so the
            // StoreKit rating sheet has a clear presentation context.
            try? await Task.sleep(for: .milliseconds(700))

            #if os(iOS)
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) {
                AppStore.requestReview(in: scene)
            } else {
                requestReview()
            }
            #else
            requestReview()
            #endif
        }
    }

    private func loadProfile() async {
        if let name = await AuthService.shared.fetchDisplayName() {
            displayName = name
        } else if let email = auth.currentUser?.email {
            displayName = email.components(separatedBy: "@").first ?? ""
        }
    }

    private func saveName() {
        isEditingName = false
        nameFocused   = false
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        displayName = trimmed
        Task { await AuthService.shared.updateDisplayName(trimmed) }
    }

    private func handleSignInTap() {
        if pro.canUseCloudSync {
            showAuth = true
        } else {
            showPaywall = true
        }
    }

    private var purchaseStatusTitle: String {
        if pro.canUseCloudSync {
            return "Canvio Cloud Pro Active"
        }
        if pro.isPro {
            return "Local Pro Active · Upgrade for Sync"
        }
        return "Unlock Canvio Pro"
    }

    private func performSignOut() async {
        isSigningOut = true
        await AuthService.shared.signOut()
        isSigningOut = false
        dismiss()
    }

    private func performDelete() async {
        isDeleting = true
        let error = await AuthService.shared.deleteAccount(context: context)
        isDeleting = false
        if let error {
            deleteError = error
        } else {
            dismiss()
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func settingsRow(
        icon: String,
        iconColor: Color,
        title: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor == .secondary
                              ? Color.secondary.opacity(0.12)
                              : iconColor.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(iconColor == .secondary ? .secondary : iconColor)
                }
                Text(title)
                    .font(.body)
                    .foregroundStyle(isDestructive ? .red : .primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
