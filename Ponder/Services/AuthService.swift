//
//  AuthService.swift
//  Ponder
//

import Foundation
import Combine
import AuthenticationServices
import Supabase
import Auth
import CryptoKit
import SwiftData

@MainActor
final class AuthService: NSObject, ObservableObject {

    static let shared = AuthService()

    @Published var currentUser: User?    = nil
    @Published var isLoading: Bool       = false
    @Published var errorMessage: String? = nil

    /// True when the user tapped "Continue without account".
    @Published var isGuest: Bool = false

    /// Set to true when account was remotely deleted — triggers UI reset
    @Published var wasRemotelyDeleted: Bool = false

    private let supabase = SupabaseService.shared.client
    private(set) var currentNonce: String = ""

    private override init() { super.init() }

    // MARK: - Session restore

    func restoreSession() async {
        do {
            let session = try await supabase.auth.session
            // Verify the account still exists on the server.
            // If deleted from another device, getUser() throws an auth error.
            do {
                let user = try await supabase.auth.user()
                currentUser = user
                isGuest     = false
                UserDefaults.standard.set(false, forKey: "ponder.isGuest")
            } catch {
                // Session token exists locally but account is gone on server
                print("⚠️ Account no longer exists on server — forcing local logout")
                await forceLocalLogout()
            }
        } catch {
            currentUser = nil
            isGuest = UserDefaults.standard.bool(forKey: "ponder.isGuest")
        }
    }

    // MARK: - Periodic account validity check
    // Call this from SyncCoordinatorView on a timer so device B
    // discovers the deletion within ~60 seconds of it happening.

    func checkAccountStillExists(context: ModelContext) async {
        guard currentUser != nil else { return }
        do {
            _ = try await supabase.auth.user()
        } catch {
            let errStr = error.localizedDescription.lowercased()
            // Supabase returns "user not found" or 401/403 when account is deleted
            let isGone = errStr.contains("user not found")
                      || errStr.contains("not found")
                      || errStr.contains("invalid")
                      || errStr.contains("jwt")
                      || errStr.contains("unauthorized")
            if isGone {
                print("⚠️ Account deleted on another device — wiping local data")
                clearLocalData(context: context)
                clearLocalFiles()
                await forceLocalLogout()
                wasRemotelyDeleted = true
            }
        }
    }

    // MARK: - Force local logout (no server call — account may not exist)

    func forceLocalLogout() async {
        try? await supabase.auth.signOut()
        currentUser = nil
        isGuest     = false
        UserDefaults.standard.set(false, forKey: "ponder.isGuest")
    }

    // MARK: - Guest mode

    func continueAsGuest() {
        isGuest = true
        UserDefaults.standard.set(true, forKey: "ponder.isGuest")
    }

    // MARK: - Sign in with Apple (iOS path)

    #if os(iOS)
    func signInWithApple() {
        isLoading    = true
        errorMessage = nil
        currentNonce = randomNonce()

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(currentNonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate                    = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    #endif

    // MARK: - Sign in with Apple (shared)

    func prepareRequest(_ request: ASAuthorizationAppleIDRequest) {
        currentNonce            = randomNonce()
        request.requestedScopes = [.fullName, .email]
        request.nonce           = sha256(currentNonce)
    }

    func handleAuthorization(_ authorization: ASAuthorization) async {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData  = credential.identityToken,
              let idToken    = String(data: tokenData, encoding: .utf8)
        else {
            isLoading    = false
            errorMessage = "Failed to get identity token from Apple."
            return
        }

        isLoading = true
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: currentNonce)
            )
            currentUser = session.user
            isGuest     = false
            wasRemotelyDeleted = false
            UserDefaults.standard.set(false, forKey: "ponder.isGuest")

            if let fullName = credential.fullName, let given = fullName.givenName {
                let name = [given, fullName.familyName].compactMap { $0 }.joined(separator: " ")
                _ = try? await supabase
                    .from("profiles")
                    .update(["full_name": name])
                    .eq("id", value: session.user.id.uuidString)
                    .execute()
            }
        } catch {
            errorMessage = "Sign in failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func handleAuthError(_ error: Error) {
        if (error as? ASAuthorizationError)?.code != .canceled {
            errorMessage = "Sign in failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Sign out

    func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            errorMessage = "Sign out failed: \(error.localizedDescription)"
        }
        currentUser = nil
        isGuest     = false
        UserDefaults.standard.set(false, forKey: "ponder.isGuest")
    }

    // MARK: - Delete account

    func deleteAccount(context: ModelContext) async -> String? {
        guard let user = currentUser else { return "No user signed in." }
        let uid = user.id.uuidString.lowercased()

        isLoading = true
        defer { isLoading = false }

        await deleteStorageFolder(userID: uid)

        do {
            try await supabase
                .rpc("delete_own_user")
                .execute()
        } catch {
            print("⚠️ RPC delete_own_user failed: \(error.localizedDescription)")
        }

        clearLocalData(context: context)
        clearLocalFiles()

        try? await supabase.auth.signOut()
        currentUser = nil
        isGuest     = false
        UserDefaults.standard.set(false, forKey: "ponder.isGuest")

        return nil
    }

    // MARK: - Storage cleanup

    private func deleteStorageFolder(userID: String) async {
        let bucket     = "ponder-files"
        let subfolders = ["images", "pdfs", "pdfthumbs", "audio"]

        for folder in subfolders {
            do {
                let files = try await supabase.storage
                    .from(bucket)
                    .list(path: "\(userID)/\(folder)")

                guard !files.isEmpty else { continue }

                let paths = files.map { "\(userID)/\(folder)/\($0.name)" }
                try await supabase.storage
                    .from(bucket)
                    .remove(paths: paths)
            } catch {
                print("⚠️ Storage cleanup failed [\(folder)]: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Local data cleanup

    func clearLocalData(context: ModelContext) {
        try? context.delete(model: CanvasModel.self)
        try? context.delete(model: TextElementModel.self)
        try? context.delete(model: StickyNoteModel.self)
        try? context.delete(model: TodoListModel.self)
        try? context.delete(model: TodoTaskModel.self)
        try? context.delete(model: ShapeElementModel.self)
        try? context.delete(model: ImageElementModel.self)
        try? context.delete(model: PDFElementModel.self)
        try? context.delete(model: TableElementModel.self)
        try? context.delete(model: TableCellModel.self)
        try? context.delete(model: AudioElementModel.self)
        try? context.delete(model: DrawingElementModel.self)
        try? context.delete(model: ConnectorModel.self)
        try? context.save()
    }

    func clearLocalFiles() {
        let dirs: [URL] = [
            ImageStorageService.imagesDirectory,
            PDFStorageService.pdfsDirectory,
            PDFStorageService.thumbnailsDirectory,
            AudioStorageService.audioDirectory
        ]
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
    }

    // MARK: - Profile

    func fetchDisplayName() async -> String? {
        guard let user = currentUser else { return nil }
        do {
            let response = try await supabase
                .from("profiles")
                .select("full_name")
                .eq("id", value: user.id.uuidString)
                .single()
                .execute()
            if let dict = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
               let name = dict["full_name"] as? String, !name.isEmpty {
                return name
            }
        } catch { }
        return nil
    }

    func updateDisplayName(_ name: String) async {
        guard let user = currentUser else { return }
        _ = try? await supabase
            .from("profiles")
            .update(["full_name": name])
            .eq("id", value: user.id.uuidString)
            .execute()
    }

    // MARK: - Auth state listener

    func listenToAuthChanges() {
        Task {
            for await (event, session) in supabase.auth.authStateChanges {
                await MainActor.run {
                    switch event {
                    case .signedIn, .tokenRefreshed, .userUpdated:
                        self.currentUser       = session?.user
                        self.isGuest           = false
                        self.wasRemotelyDeleted = false
                        UserDefaults.standard.set(false, forKey: "ponder.isGuest")
                    case .signedOut:
                        self.currentUser = nil
                    default:
                        break
                    }
                }
            }
        }
    }

    // MARK: - Nonce helpers

    func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        )
        return String(randomBytes.map { byte in charset[Int(byte) % charset.count] })
    }

    func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - iOS presentation context + delegate

#if os(iOS)
extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow })
        else { return UIWindow() }
        return window
    }
}

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            await AuthService.shared.handleAuthorization(authorization)
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            AuthService.shared.handleAuthError(error)
        }
    }
}
#endif
