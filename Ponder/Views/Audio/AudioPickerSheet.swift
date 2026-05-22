//
//  AudioPickerSheet.swift
//  Ponder
//

import SwiftUI
import UniformTypeIdentifiers

struct AudioPickerSheet: View {
    @Binding var showRecorder: Bool
    @Binding var showImporter: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)

            Text("Add Audio")
                .font(.title3.weight(.bold))
                .padding(.bottom, 24)

            VStack(spacing: 12) {
                // Record
                Button {
                    dismiss()
                    // Small delay so sheet dismiss animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showRecorder = true
                    }
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.12))
                                .frame(width: 52, height: 52)
                            Image(systemName: "mic.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.red)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Record Audio")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Use your microphone")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.secondary.opacity(0.07))
                    )
                }
                .buttonStyle(.plain)

                // Import — dismiss first, then open importer after delay
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showImporter = true
                    }
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 52, height: 52)
                            Image(systemName: "folder.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.blue)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Import from Files")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("MP3, M4A, WAV, AIFF supported")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.secondary.opacity(0.07))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            Spacer().frame(height: 32)
        }
    }
}
