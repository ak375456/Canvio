import SwiftUI
import SwiftData

struct ImageFreeformCutoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Bindable var element: ImageElementModel
    @ObservedObject var vm: ImageElementViewModel
    let undoManager: CanvasUndoManager?

    @State private var sourceImage: PlatformImage?
    @State private var points: [CGPoint] = []
    @State private var normalizedSelection: [CGPoint] = []
    @State private var isLoopClosed = false
    @State private var isTracing = false
    @State private var isApplying = false
    @State private var feedback = "Draw around the part you want to keep"
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                instructionBar
                Divider()

                GeometryReader { geometry in
                    if let sourceImage {
                        let imageRect = aspectFitRect(
                            imageSize: sourceImage.size,
                            containerSize: geometry.size
                        )

                        ZStack {
                            Color.black.opacity(0.88)

                            checkerboard
                                .frame(width: imageRect.width, height: imageRect.height)
                                .position(x: imageRect.midX, y: imageRect.midY)

                            platformImage(sourceImage)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: imageRect.width, height: imageRect.height)
                                .position(x: imageRect.midX, y: imageRect.midY)

                            lassoOverlay
                                .allowsHitTesting(false)

                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(traceGesture(in: imageRect))
                                .allowsHitTesting(!isApplying)
                        }
                        .clipped()
                    } else {
                        ContentUnavailableView(
                            "Image unavailable",
                            systemImage: "photo.badge.exclamationmark",
                            description: Text("Wait for the image to finish downloading, then try again.")
                        )
                    }
                }

                Divider()
                actionBar
            }
            .navigationTitle("Freeform Cutout")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isApplying)
                }
            }
            .interactiveDismissDisabled(isApplying)
            .onAppear {
                sourceImage = ImageStorageService.load(fileName: element.imageFileName)
            }
            .alert("Couldn’t Create Cutout", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private var instructionBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isLoopClosed ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: isLoopClosed ? "checkmark" : "pencil.tip.crop.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isLoopClosed ? Color.green : Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(feedback)
                    .font(.subheadline.weight(.semibold))
                Text("Make one complete loop and return to the starting dot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                resetSelection()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(points.isEmpty || isApplying)

            Button {
                applyCutout()
            } label: {
                HStack(spacing: 8) {
                    if isApplying {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "scissors")
                    }
                    Text(isApplying ? "Cutting…" : "Cut Out")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isLoopClosed || normalizedSelection.count < 3 || isApplying)
        }
        .padding(16)
    }

    private var checkerboard: some View {
        Canvas { context, size in
            let tile: CGFloat = 12
            let columns = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(CGRect(
                            x: CGFloat(column) * tile,
                            y: CGFloat(row) * tile,
                            width: tile,
                            height: tile
                        )),
                        with: .color(.white.opacity(0.10))
                    )
                }
            }
        }
        .background(Color.white.opacity(0.04))
    }

    private var lassoOverlay: some View {
        Canvas { context, _ in
            guard let first = points.first else { return }

            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }

            if isLoopClosed {
                path.closeSubpath()
                context.fill(path, with: .color(Color.accentColor.opacity(0.18)))
            }

            context.stroke(
                path,
                with: .color(isLoopClosed ? .green : Color.accentColor),
                style: StrokeStyle(
                    lineWidth: 3,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: isLoopClosed ? [] : [8, 5]
                )
            )

            let startDot = CGRect(x: first.x - 7, y: first.y - 7, width: 14, height: 14)
            context.fill(Path(ellipseIn: startDot), with: .color(isLoopClosed ? .green : .white))
            context.stroke(
                Path(ellipseIn: startDot.insetBy(dx: -4, dy: -4)),
                with: .color(isLoopClosed ? .green.opacity(0.8) : Color.accentColor.opacity(0.9)),
                lineWidth: 2
            )
        }
    }

    private func traceGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isLoopClosed else { return }

                if !isTracing {
                    isTracing = true
                    points = []
                    normalizedSelection = []
                    feedback = "Keep drawing until you reach the starting dot"
                }

                guard imageRect.contains(value.startLocation) else { return }
                let point = clamped(value.location, to: imageRect)
                append(point, in: imageRect)
            }
            .onEnded { _ in
                guard isTracing else { return }
                isTracing = false
                finishTrace(in: imageRect)
            }
    }

    private func append(_ point: CGPoint, in imageRect: CGRect) {
        if let last = points.last, distance(from: last, to: point) < 2.5 { return }
        points.append(point)

        guard points.count >= 12,
              traceLength >= max(60, min(imageRect.width, imageRect.height) * 0.28),
              let first = points.first,
              distance(from: first, to: point) <= closureThreshold(for: imageRect) else { return }

        closeLoop(in: imageRect)
    }

    private func finishTrace(in imageRect: CGRect) {
        guard points.count >= 12,
              traceLength >= max(60, min(imageRect.width, imageRect.height) * 0.28),
              let first = points.first,
              let last = points.last else {
            feedback = "Draw a larger loop"
            return
        }

        if distance(from: first, to: last) <= closureThreshold(for: imageRect) * 1.35 {
            closeLoop(in: imageRect)
        } else {
            feedback = "The loop is open — try again and finish at the dot"
        }
    }

    private func closeLoop(in imageRect: CGRect) {
        guard !isLoopClosed, points.count >= 3 else { return }
        isLoopClosed = true
        normalizedSelection = points.map { point in
            CGPoint(
                x: (point.x - imageRect.minX) / imageRect.width,
                y: (point.y - imageRect.minY) / imageRect.height
            )
        }
        feedback = "Loop closed — the inside will be kept"
    }

    private func resetSelection() {
        points = []
        normalizedSelection = []
        isLoopClosed = false
        isTracing = false
        feedback = "Draw around the part you want to keep"
    }

    private func applyCutout() {
        guard isLoopClosed, normalizedSelection.count >= 3 else { return }
        isApplying = true

        Task {
            do {
                try await vm.applyFreeformCutout(
                    element: element,
                    normalizedPolygon: normalizedSelection,
                    context: context,
                    undoManager: undoManager
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isApplying = false
            }
        }
    }

    private var traceLength: CGFloat {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) {
            $0 + distance(from: $1.0, to: $1.1)
        }
    }

    private func aspectFitRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        let availableSize = CGSize(
            width: max(1, containerSize.width - 24),
            height: max(1, containerSize.height - 24)
        )
        let scale = min(
            availableSize.width / max(1, imageSize.width),
            availableSize.height / max(1, imageSize.height)
        )
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private func closureThreshold(for rect: CGRect) -> CGFloat {
        min(34, max(20, min(rect.width, rect.height) * 0.06))
    }

    private func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(rhs.x - lhs.x, rhs.y - lhs.y)
    }

    #if canImport(UIKit)
    private func platformImage(_ image: PlatformImage) -> Image {
        Image(uiImage: image)
    }
    #elseif canImport(AppKit)
    private func platformImage(_ image: PlatformImage) -> Image {
        Image(nsImage: image)
    }
    #endif
}
