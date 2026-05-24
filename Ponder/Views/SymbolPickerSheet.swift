//
//  SymbolPickerSheet.swift
//  Ponder
//

import SwiftUI

struct SymbolPickerSheet: View {
    let onAdd: (String, String, Double) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var search:           String = ""
    @State private var selectedSymbol:   String = "star.fill"
    @State private var selectedColor:    String = "primary"
    @State private var fontSize:         Double = 48
    @State private var selectedCategory: String = "Favorites"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            categoryPicker
            Divider()
            searchBar
            symbolGrid
            Divider()
            previewAndAdd
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Add Symbol").font(.title3.weight(.bold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Category picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SymbolCategory.all, id: \.name) { cat in
                    Button {
                        selectedCategory = cat.name
                        search = ""
                    } label: {
                        Text(cat.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedCategory == cat.name ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    selectedCategory == cat.name
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.12)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search symbols…", text: $search)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Symbol grid

    private var filteredSymbols: [String] {
        if search.isEmpty {
            return SymbolCategory.all.first { $0.name == selectedCategory }?.symbols ?? []
        }
        return SymbolCategory.all
            .flatMap { $0.symbols }
            .filter { $0.localizedCaseInsensitiveContains(search) }
    }

    private var symbolGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(filteredSymbols, id: \.self) { name in
                    Button {
                        selectedSymbol = name
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 24))
                            .foregroundStyle(
                                selectedSymbol == name ? Color.accentColor : Color.primary
                            )
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        selectedSymbol == name
                                        ? Color.accentColor.opacity(0.12)
                                        : Color.clear
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 260)
    }

    // MARK: - Preview + controls + add

    private var previewAndAdd: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Live preview
                Image(systemName: selectedSymbol)
                    .font(.system(size: CGFloat(fontSize)))
                    .foregroundStyle(colorFromName(selectedColor))
                    .frame(width: 80, height: 80)
                    .background(
                        Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                VStack(alignment: .leading, spacing: 10) {
                    // Size controls
                    HStack(spacing: 8) {
                        Text("Size")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34)
                        Button {
                            fontSize = max(16, fontSize - 8)
                        } label: {
                            Image(systemName: "minus.circle").font(.title3)
                        }
                        .buttonStyle(.plain)
                        Text("\(Int(fontSize))")
                            .font(.caption.weight(.semibold))
                            .frame(width: 28)
                        Button {
                            fontSize = min(200, fontSize + 8)
                        } label: {
                            Image(systemName: "plus.circle").font(.title3)
                        }
                        .buttonStyle(.plain)
                    }

                    // Color picker
                    HStack(spacing: 6) {
                        Text("Color")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(colorOptions, id: \.name) { opt in
                                    Button {
                                        selectedColor = opt.name
                                    } label: {
                                        let active = selectedColor == opt.name
                                        Circle()
                                            .fill(opt.name == "primary" ? Color.primary : opt.color)
                                            .frame(width: active ? 22 : 18,
                                                   height: active ? 22 : 18)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                                                    .opacity(active ? 1 : 0)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            // Add button
            Button {
                onAdd(selectedSymbol, selectedColor, fontSize)
                dismiss()
            } label: {
                Text("Add to Canvas")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .padding(.top, 12)
    }

    // MARK: - Helpers

    private func colorFromName(_ name: String) -> Color {
        colorOptions.first { $0.name == name }?.color ?? .primary
    }

    private let colorOptions: [(name: String, color: Color)] = [
        ("primary", .primary), ("blue",   .blue),    ("red",    .red),
        ("green",   .green),   ("orange", .orange),  ("purple", .purple),
        ("pink",    .pink),    ("teal",   .teal),     ("yellow", .yellow),
        ("indigo",  .indigo),  ("mint",   .mint),     ("cyan",   .cyan),
    ]
}

// MARK: - Symbol categories

private struct SymbolCategory {
    let name: String
    let symbols: [String]

    static let all: [SymbolCategory] = [
        SymbolCategory(name: "Favorites", symbols: [
            "star.fill", "heart.fill", "bolt.fill", "flame.fill",
            "checkmark.circle.fill", "xmark.circle.fill", "plus.circle.fill",
            "arrow.right.circle.fill", "info.circle.fill", "exclamationmark.circle.fill",
            "lightbulb.fill", "bookmark.fill", "tag.fill", "flag.fill", "bell.fill",
            "pin.fill", "location.fill", "magnifyingglass", "pencil", "trash.fill",
            "folder.fill", "doc.fill", "calendar", "clock.fill", "alarm.fill",
            "moon.fill", "sun.max.fill", "cloud.fill", "snowflake", "drop.fill"
        ]),
        SymbolCategory(name: "Arrows", symbols: [
            "arrow.right", "arrow.left", "arrow.up", "arrow.down",
            "arrow.right.circle.fill", "arrow.left.circle.fill",
            "arrow.up.circle.fill", "arrow.down.circle.fill",
            "arrow.turn.right.up", "arrow.turn.right.down",
            "arrow.uturn.right", "arrow.uturn.left",
            "arrow.2.circlepath", "arrow.clockwise", "arrow.counterclockwise",
            "chevron.right", "chevron.left", "chevron.up", "chevron.down",
            "chevron.right.circle.fill", "chevron.left.circle.fill",
            "arrow.right.arrow.left", "arrow.up.arrow.down",
            "arrow.up.left.and.arrow.down.right",
            "arrow.down.left.and.arrow.up.right"
        ]),
        SymbolCategory(name: "Nature", symbols: [
            "sun.max.fill", "sun.min.fill", "moon.fill", "moon.stars.fill",
            "cloud.fill", "cloud.rain.fill", "cloud.snow.fill", "cloud.bolt.fill",
            "wind", "snowflake", "drop.fill", "flame.fill",
            "leaf.fill", "tree.fill",
            "bird.fill", "cat.fill", "dog.fill", "ant.fill",
            "tortoise.fill", "fish.fill", "lizard.fill",
            "pawprint.fill", "hare.fill", "ladybug.fill"
        ]),
        SymbolCategory(name: "People", symbols: [
            "person.fill", "person.2.fill", "person.3.fill",
            "person.crop.circle.fill", "person.crop.square.fill",
            "figure.walk", "figure.run", "figure.stand",
            "hand.raised.fill", "hand.thumbsup.fill", "hand.thumbsdown.fill",
            "hands.clap.fill", "hand.wave.fill", "hand.point.right.fill",
            "brain.fill", "heart.fill", "eye.fill",
            "face.smiling.fill",
            "person.fill.checkmark", "person.fill.xmark",
            "person.fill.badge.plus"
        ]),
        SymbolCategory(name: "Objects", symbols: [
            "house.fill", "building.fill", "building.2.fill",
            "car.fill", "airplane", "bicycle",
            "phone.fill", "iphone", "laptopcomputer", "desktopcomputer",
            "tv.fill", "gamecontroller.fill", "headphones",
            "camera.fill", "video.fill", "music.note",
            "book.fill", "books.vertical.fill", "newspaper.fill",
            "bag.fill", "cart.fill", "creditcard.fill",
            "key.fill", "lock.fill", "lock.open.fill"
        ]),
        SymbolCategory(name: "Symbols", symbols: [
            "star.fill", "star.circle.fill",
            "circle.fill", "square.fill", "triangle.fill",
            "diamond.fill", "hexagon.fill", "pentagon.fill",
            "checkmark", "xmark", "plus", "minus",
            "equal", "multiply", "divide",
            "at", "number", "percent",
            "infinity", "questionmark", "exclamationmark",
            "dollarsign.circle.fill", "eurosign.circle.fill",
            "bitcoinsign.circle.fill"
        ]),
        SymbolCategory(name: "Communication", symbols: [
            "message.fill", "bubble.left.fill", "bubble.right.fill",
            "envelope.fill", "envelope.open.fill",
            "phone.fill", "phone.arrow.up.right.fill",
            "video.fill", "mic.fill", "mic.slash.fill",
            "speaker.wave.3.fill", "speaker.slash.fill",
            "bell.fill", "bell.slash.fill", "bell.badge.fill",
            "wifi", "wifi.slash",
            "megaphone.fill", "link"
        ]),
        SymbolCategory(name: "Health", symbols: [
            "heart.fill", "heart.circle.fill", "heart.slash.fill",
            "lungs.fill", "brain.fill", "eye.fill",
            "pills.fill", "cross.fill", "cross.circle.fill",
            "stethoscope", "bandage.fill", "syringe.fill",
            "thermometer.medium",
            "figure.walk.circle.fill", "figure.run.circle.fill",
            "fork.knife", "cup.and.saucer.fill",
            "bed.double.fill", "moon.zzz.fill"
        ]),
        SymbolCategory(name: "Education", symbols: [
            "book.fill", "books.vertical.fill", "text.book.closed.fill",
            "graduationcap.fill", "pencil", "pencil.circle.fill",
            "pencil.and.ruler.fill", "ruler.fill",
            "paperclip", "pin.fill", "bookmark.fill",
            "doc.fill", "doc.text.fill", "newspaper.fill",
            "square.and.pencil",
            "list.bullet", "checklist", "chart.bar.fill",
            "chart.pie.fill", "function", "sum",
            "globe", "globe.americas.fill", "map.fill"
        ]),
    ]
}
