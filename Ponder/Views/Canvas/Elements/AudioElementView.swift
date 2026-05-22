//
//  AudioElementView.swift
//  Ponder
//

import SwiftUI
import SwiftData

struct AudioElementView: View {
    @Environment(\.modelContext) private var context
    @Bindable var element: AudioElementModel
    let canvasScale: CGFloat
    let canvasBoundary: CGSize
    @ObservedObject var vm: AudioElementViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect: Bool = false
    var onExternalTap: (() -> Void)? = nil

    @StateObject private var player = AudioPlayerViewModel()
    @State private var dragOffset: CGSize = .zero
    @State private var rotationAngle: Double = 0
    @State private var hasLoadedRotation = false

    private var isSelected: Bool { vm.editingID == element.id }
    private let handleSize: CGFloat = 26

    var body: some View {
        ZStack {
            card
            selectionRing
            if isSelected && !isMultiSelectMode {
                Button { vm.delete(element: element, context: context) } label: { handleCircle(icon: "trash", color: .red) }
                    .buttonStyle(.plain).offset(x: -(element.width / 2), y: -(element.height / 2))
            }
        }
        .frame(width: element.width, height: element.height)
        .rotationEffect(.degrees(rotationAngle), anchor: .center)
        .position(x: element.x + dragOffset.width, y: element.y + dragOffset.height)
        .gesture(isMultiSelectMode ? nil : moveDragGesture)
        .onAppear {
            if !hasLoadedRotation { rotationAngle = element.rotation; hasLoadedRotation = true }
            player.load(fileName: element.audioFileName, elementID: element.id)
        }
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isMultiSelectMode {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelectedInMultiSelect ? Color.blue : Color.white.opacity(0.3),
                    lineWidth: isSelectedInMultiSelect ? 2.5 : 1
                )
                .frame(width: element.width, height: element.height)
                .overlay(alignment: .topTrailing) {
                    if isSelectedInMultiSelect {
                        ZStack {
                            Circle().fill(Color.blue).frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        }.offset(x: 8, y: -8)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isSelectedInMultiSelect)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.pink.opacity(0.15)).frame(width: 34, height: 34)
                    Image(systemName: "waveform").font(.system(size: 16, weight: .medium)).foregroundStyle(.pink)
                        .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(element.originalName.isEmpty ? "Audio" : element.originalName)
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1).foregroundStyle(.primary)
                    Text(player.formattedTime(element.duration))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            VStack(spacing: 2) {
                Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                       in: 0...max(1, player.duration))
                    .tint(.pink).padding(.horizontal, 12)
                HStack {
                    Text(player.formattedTime(player.currentTime))
                    Spacer()
                    Text(player.formattedTime(player.duration))
                }
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary).padding(.horizontal, 14)
            }

            HStack(spacing: 24) {
                Button { player.skipBackward() } label: {
                    Image(systemName: "gobackward.10").font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
                Button { player.togglePlayPause() } label: {
                    ZStack {
                        Circle().fill(Color.pink).frame(width: 34, height: 34)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .offset(x: player.isPlaying ? 0 : 1)
                    }
                }.buttonStyle(.plain)
                Button { player.skipForward() } label: {
                    Image(systemName: "goforward.10").font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.top, 4).padding(.bottom, 10)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
            isSelected && !isMultiSelectMode ? Color.pink.opacity(0.6) : Color.secondary.opacity(0.2),
            lineWidth: isSelected && !isMultiSelectMode ? 2 : 1))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isMultiSelectMode { onExternalTap?(); vm.editingID = isSelected ? nil : element.id }
        }
    }

    private func handleCircle(icon: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color).frame(width: handleSize, height: handleSize)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        }
    }

    private var moveDragGesture: some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                let t = value.translation; dragOffset = .zero
                vm.updatePosition(element: element, translation: t, scale: canvasScale, boundary: canvasBoundary, context: context)
            }
    }
}
