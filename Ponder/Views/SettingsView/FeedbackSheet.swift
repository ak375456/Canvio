//
//  FeedbackSheet.swift
//  Canvio
//

import SwiftUI
import PhotosUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSubmitted: () -> Void

    @State private var category: AppFeedbackCategory = .improvement
    @State private var message = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var attachment: AppFeedbackAttachment?
    @State private var isPreparingImage = false
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var errorMessage: String?
    @FocusState private var messageFocused: Bool

    private let characterLimit = 4_000

    var body: some View {
        NavigationStack {
            Group {
                if didSubmit {
                    successView
                } else {
                    formView
                }
            }
            .navigationTitle(didSubmit ? "Thank You" : "Help & Feedback")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
        .alert(
            "Couldn’t Send Feedback",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 650)
        #endif
    }

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                anonymityCard

                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("WHAT WOULD YOU LIKE TO SHARE?")
                    HStack(spacing: 8) {
                        ForEach(AppFeedbackCategory.allCases) { option in
                            categoryButton(option)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("DETAILS")
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.secondary.opacity(0.08))

                        if message.isEmpty {
                            Text(placeholder)
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $message)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .focused($messageFocused)
                            .padding(10)
                            .frame(minHeight: 150)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                    }

                    Text("\(message.count)/\(characterLimit)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("IMAGE (OPTIONAL)")

                    if let attachment {
                        attachmentRow(attachment)
                    } else {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            HStack(spacing: 12) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isPreparingImage ? "Preparing image…" : "Add a screenshot or image")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("PNG or JPEG · up to 8 MB")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isPreparingImage {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(14)
                            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(isPreparingImage || isSubmitting)
                    }

                    Text("Only share images you’re comfortable sending, and remove any personal information you don’t want included.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    submit()
                } label: {
                    HStack(spacing: 10) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(isSubmitting ? "Sending…" : "Send Feedback")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(
                        isFormValid ? Color.accentColor : Color.secondary.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isFormValid || isSubmitting || isPreparingImage)
            }
            .padding(22)
        }
        .onChange(of: message) { _, newValue in
            if newValue.count > characterLimit {
                message = String(newValue.prefix(characterLimit))
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            prepareAttachment(from: newItem)
        }
    }

    private var anonymityCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sent without your identity")
                    .font(.subheadline.weight(.semibold))
                Text("Canvio does not attach your name, email, or account ID. The report includes the app version, device type, and operating system so I can investigate issues.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private var successView: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.13))
                    .frame(width: 92, height: 92)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.green)
            }
            Text("Feedback sent")
                .font(.title2.weight(.bold))
            Text("Thank you for helping make Canvio better. Canvio did not attach your name, email, or account ID to this report.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Done") { dismiss() }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func categoryButton(_ option: AppFeedbackCategory) -> some View {
        let isSelected = category == option
        return Button {
            category = option
        } label: {
            VStack(spacing: 7) {
                Image(systemName: option.icon)
                    .font(.body.weight(.semibold))
                Text(option.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }

    private func attachmentRow(_ attachment: AppFeedbackAttachment) -> some View {
        HStack(spacing: 12) {
            attachmentPreview(attachment.data)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text("Image attached")
                    .font(.subheadline.weight(.semibold))
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                self.attachment = nil
                selectedPhoto = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func attachmentPreview(_ data: Data) -> some View {
        #if canImport(UIKit)
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color.secondary.opacity(0.15)
        }
        #elseif canImport(AppKit)
        if let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color.secondary.opacity(0.15)
        }
        #endif
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }

    private var placeholder: String {
        switch category {
        case .improvement:
            return "What would make Canvio better for you?"
        case .bug:
            return "What happened, and what did you expect to happen?"
        case .other:
            return "Tell me what’s on your mind…"
        }
    }

    private var isFormValid: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
    }

    private func prepareAttachment(from item: PhotosPickerItem) {
        isPreparingImage = true
        errorMessage = nil

        Task {
            do {
                guard let originalData = try await item.loadTransferable(type: Data.self) else {
                    throw FeedbackSubmissionError.uploadFailed
                }

                let prepared = ImageStorageService.prepareForStorage(data: originalData)

                guard let prepared else {
                    throw FeedbackSubmissionError.uploadFailed
                }
                guard prepared.data.count <= FeedbackService.maximumImageBytes else {
                    throw FeedbackSubmissionError.imageTooLarge
                }

                attachment = AppFeedbackAttachment(
                    data: prepared.data,
                    contentType: prepared.fileExtension == "png" ? "image/png" : "image/jpeg",
                    fileExtension: prepared.fileExtension
                )
            } catch {
                selectedPhoto = nil
                attachment = nil
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "The selected image could not be prepared."
            }
            isPreparingImage = false
        }
    }

    private func submit() {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMessage.count >= 5 else { return }

        messageFocused = false
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                try await FeedbackService.shared.submit(
                    category: category,
                    message: trimmedMessage,
                    attachment: attachment
                )
                isSubmitting = false
                didSubmit = true
                onSubmitted()

                // Close this modal before Settings asks StoreKit for its own modal.
                // Keeping both requests in the same presentation stack can suppress
                // the native rating sheet on a real device.
                try? await Task.sleep(for: .milliseconds(1_200))
                dismiss()
            } catch {
                isSubmitting = false
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Your feedback could not be sent. Please try again."
            }
        }
    }
}
