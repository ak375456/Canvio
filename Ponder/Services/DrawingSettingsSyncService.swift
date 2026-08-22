import Foundation
import Supabase

private struct DrawingSettingsRow: Codable {
    let user_id: String
    let color_cycle_enabled: Bool
    let color_cycle_colors: [String]
    let strokes_per_color: Int
    let color_cycle_mode: String?
    let continuous_color_speed: String?
    let updated_at: String
}

@MainActor
final class DrawingSettingsSyncService {
    static let shared = DrawingSettingsSyncService()

    private let supabase = SupabaseService.shared.client
    private var pendingUpsert: Task<Void, Never>?

    private init() {}

    func scheduleUpsert(
        configuration: DrawingColorCycleConfiguration,
        updatedAt: Date
    ) {
        guard let scheduledUserID = AuthService.shared.syncUserID else { return }
        pendingUpsert?.cancel()
        pendingUpsert = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled,
                  AuthService.shared.syncUserID == scheduledUserID else { return }
            await self?.upsert(configuration: configuration, updatedAt: updatedAt)
        }
    }

    func reconcile(settings: AppSettings) async {
        guard NetworkMonitor.shared.isConnected,
              let userID = AuthService.shared.syncUserID else { return }

        do {
            let rows: [DrawingSettingsRow] = try await supabase
                .from("user_drawing_settings")
                .select()
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value

            guard let remote = rows.first else {
                let updatedAt = settings.drawingColorCycleUpdatedAt ?? Date()
                if settings.drawingColorCycleUpdatedAt == nil {
                    settings.applySyncedDrawingColorCycleConfiguration(
                        settings.drawingColorCycleConfiguration,
                        updatedAt: updatedAt
                    )
                }
                await upsert(
                    configuration: settings.drawingColorCycleConfiguration,
                    updatedAt: updatedAt
                )
                return
            }

            let remoteUpdatedAt = Self.date(from: remote.updated_at) ?? .distantPast
            let localUpdatedAt = settings.drawingColorCycleUpdatedAt ?? .distantPast
            let remoteConfiguration = DrawingColorCycleConfiguration(
                isEnabled: remote.color_cycle_enabled,
                colorHexes: remote.color_cycle_colors,
                strokesPerColor: remote.strokes_per_color,
                mode: remote.color_cycle_mode.flatMap(DrawingColorCycleMode.init(rawValue:)) ?? .byStroke,
                continuousSpeed: remote.continuous_color_speed.flatMap(
                    DrawingContinuousColorSpeed.init(rawValue:)
                ) ?? .medium
            ).normalized

            if remoteUpdatedAt > localUpdatedAt {
                settings.applySyncedDrawingColorCycleConfiguration(
                    remoteConfiguration,
                    updatedAt: remoteUpdatedAt
                )
            } else if localUpdatedAt > remoteUpdatedAt {
                await upsert(
                    configuration: settings.drawingColorCycleConfiguration,
                    updatedAt: localUpdatedAt
                )
            }
        } catch {
            print("⚠️ Drawing settings pull failed: \(error.localizedDescription)")
        }
    }

    func upsert(
        configuration: DrawingColorCycleConfiguration,
        updatedAt: Date
    ) async {
        guard NetworkMonitor.shared.isConnected,
              let userID = AuthService.shared.syncUserID else { return }

        let normalized = configuration.normalized
        let row = DrawingSettingsRow(
            user_id: userID,
            color_cycle_enabled: normalized.isEnabled,
            color_cycle_colors: normalized.colorHexes,
            strokes_per_color: normalized.strokesPerColor,
            color_cycle_mode: normalized.mode.rawValue,
            continuous_color_speed: normalized.continuousSpeed.rawValue,
            updated_at: Self.timestamp(from: updatedAt)
        )

        do {
            try await supabase
                .from("user_drawing_settings")
                .upsert(row, onConflict: "user_id")
                .execute()
        } catch {
            print("⚠️ Drawing settings upsert failed: \(error.localizedDescription)")
        }
    }

    private static func timestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}
