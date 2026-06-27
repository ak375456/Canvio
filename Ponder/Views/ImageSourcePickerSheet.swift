//
//  ImageSourcePickerSheet.swift
//  Canvio
//
//  Shown on iOS/iPadOS when the user taps "Image".
//  Lets them choose between Camera and Photos Library.
//  On macOS this sheet is never shown — macOS goes straight to the file picker.
//

#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Source picker sheet

struct ImageSourcePickerSheet: View {
    let onCamera: () -> Void
    let onPhotos: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 20)

            Text("Add Image")
                .font(.headline.weight(.bold))
                .padding(.bottom, 20)

            VStack(spacing: 12) {
                sourceButton(
                    icon:    "camera.fill",
                    color:   .blue,
                    title:   "Take Photo",
                    subtitle: "Use your camera"
                ) {
                    dismiss()
                    // Small delay so sheet dismisses before camera opens
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onCamera()
                    }
                }

                sourceButton(
                    icon:    "photo.on.rectangle.angled",
                    color:   .purple,
                    title:   "Choose from Library",
                    subtitle: "Pick from Photos"
                ) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onPhotos()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    private func sourceButton(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scan source picker sheet

struct ScanSourcePickerSheet: View {
    let onPhotos: () -> Void
    let onCamera: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 18)

            Text("Scan Source")
                .font(.headline.weight(.bold))

            Text("Choose camera or photos")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .padding(.bottom, 18)

            VStack(spacing: 10) {
                sourceButton(
                    icon: "photo.on.rectangle.angled",
                    color: .purple,
                    title: "Choose Images",
                    subtitle: "Use your photo library",
                    action: onPhotos
                )

                sourceButton(
                    icon: "camera.fill",
                    color: .teal,
                    title: "Use Camera",
                    subtitle: "Scan pages with your camera",
                    action: onCamera
                )

            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private func sourceButton(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                action()
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Camera picker (UIImagePickerController wrapper)

struct CameraPickerView: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType      = .camera
        picker.allowsEditing   = false
        picker.delegate        = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (Data) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (Data) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let img = info[.originalImage] as? UIImage,
               let data = img.jpegData(compressionQuality: 0.85) {
                onImage(data)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
#endif
