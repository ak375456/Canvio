import SwiftUI
import SwiftData
import Auth

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var pro = ProManager.shared
    @Environment(\.modelContext) private var context
    @Query(sort: \CanvasModel.createdAt, order: .reverse) var canvases: [CanvasModel]

    @State private var showSettings = false
    @State private var isSyncing = false
    @State private var showPaywall = false
    @State private var showAuth = false

    let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                if canvases.isEmpty {
                    emptyState
                } else {
                    canvasGrid
                }
            }
            .navigationTitle("Canvio")
            .toolbar {
                // Settings / profile — left side
                ToolbarItem(placement: .cancellationAction) {
                    Button { showSettings = true } label: { avatarButton }
                        .buttonStyle(.plain)
                }

                // Right side — sync + new canvas
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        handleSyncTap()
                    } label: {
                        Image(systemName: isSyncing ? "arrow.triangle.2.circlepath" : "icloud")
                            .fontWeight(.medium)
                            .rotationEffect(.degrees(isSyncing ? 360 : 0))
                            .animation(
                                isSyncing
                                    ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                    : .default,
                                value: isSyncing
                            )
                    }
                    .disabled(isSyncing)

                    Button { handleCreateCanvasTap() } label: {
                        Image(systemName: "square.and.pencil").fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
            .sheet(isPresented: $viewModel.showCreateSheet, onDismiss: {
                viewModel.resetForm()
            }) {
                CreateCanvasSheet(
                    viewModel: viewModel,
                    canCreateCanvas: canCreateCanvas,
                    onProRequired: { showPaywall = true }
                )
                    .presentationDetents([.height(480)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
            .sheet(item: $viewModel.selectedCanvasForRename) { canvas in
                RenameCanvasSheet(viewModel: viewModel, canvas: canvas)
                    .presentationDetents([.height(200)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallSheet {
                    settingsDidUnlockPro()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
            .sheet(isPresented: $showAuth) {
                AuthView(
                    title: "Sign in for Sync",
                    subtitle: "Sign in to restore your canvases and sync Canvio Pro across all your devices."
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
            .onChange(of: auth.currentUser?.id.uuidString) { _, newValue in
                guard newValue != nil, pro.isPro else { return }
                Task { await syncAll() }
            }
        }
    }

    private var canCreateCanvas: Bool {
        pro.isPro || canvases.count < 2
    }

    private func handleCreateCanvasTap() {
        if canCreateCanvas {
            viewModel.showCreateSheet = true
        } else {
            showPaywall = true
        }
    }

    private func handleSyncTap() {
        guard pro.isPro else {
            showPaywall = true
            return
        }
        guard auth.currentUser != nil else {
            showAuth = true
            return
        }
        Task { await syncAll() }
    }

    private func settingsDidUnlockPro() {
        if auth.currentUser == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showAuth = true
            }
        }
    }

    // MARK: - Sync

    private func syncAll() async {
        guard !isSyncing, pro.isPro, auth.currentUser != nil else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Pull canvases first
        await CanvasSyncService.shared.pullAll(context: context)

        // Pull all element types for every canvas
        let allCanvases = (try? context.fetch(FetchDescriptor<CanvasModel>())) ?? []
        for canvas in allCanvases {
            await TextSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await StickyNoteSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await ShapeSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await ConnectorSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await DrawingSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await TodoSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await TableSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await ImageSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await PDFSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await AudioSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await SymbolSyncService.shared.pullAll(canvasID: canvas.id, context: context)
        }
    }

    // MARK: - Avatar button

    @ViewBuilder
    private var avatarButton: some View {
        if auth.currentUser != nil {
            ZStack {
                Circle()
                    .fill(avatarColor.gradient)
                    .frame(width: 30, height: 30)
                Text(initials)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        } else {
            Image(systemName: "person.circle")
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
    }

    private var initials: String {
        if let email = auth.currentUser?.email, !email.isEmpty {
            let prefix = email.components(separatedBy: "@").first ?? ""
            return String(prefix.prefix(2)).uppercased()
        }
        return "A"
    }

    private var avatarColor: Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red]
        let seed = initials.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[seed % colors.count]
    }

    // MARK: - Canvas Grid

    private var canvasGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(canvases) { canvas in
                    NavigationLink(destination: CanvasView(
                        canvas: canvas,
                        onDelete: { viewModel.deleteCanvas(canvas: canvas, context: context) },
                        onRename: { newName in viewModel.renameCanvas(canvas: canvas, newName: newName, context: context) }
                    )) {
                        CanvasCard(canvas: canvas, viewModel: viewModel)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            viewModel.renameText = canvas.name
                            viewModel.selectedCanvasForRename = canvas
                        } label: { Label("Rename", systemImage: "pencil") }
                        Button(role: .destructive) {
                            viewModel.deleteCanvas(canvas: canvas, context: context)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)

            Text("No Canvases")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Create your first canvas to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                handleCreateCanvasTap()
            } label: {
                Text("New Canvas")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.tint)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Canvas Card

struct CanvasCard: View {
    let canvas: CanvasModel
    let viewModel: HomeViewModel

    private var formattedDate: String {
        canvas.createdAt.formatted(date: .abbreviated, time: .omitted)
    }

    private var accentColor: Color {
        viewModel.colorFromString(canvas.iconColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let data = canvas.thumbnailData, let thumb = thumbnailImage(from: data) {
                    thumb
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.04)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                } else {
                    Rectangle()
                        .fill(accentColor.opacity(0.1))
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                    Image(systemName: canvas.iconName)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(accentColor)
                        .padding(14)
                }
            }
            .frame(height: 100)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(canvas.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }

    private func thumbnailImage(from data: Data) -> Image? {
        #if os(iOS)
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #elseif os(macOS)
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #else
        return nil
        #endif
    }
}

// MARK: - Create Canvas Sheet

struct CreateCanvasSheet: View {
    @ObservedObject var viewModel: HomeViewModel
    let canCreateCanvas: Bool
    let onProRequired: () -> Void
    @Environment(\.modelContext) private var context
    @FocusState private var nameFocused: Bool
    @FocusState private var widthFocused: Bool
    @FocusState private var heightFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("New Canvas").font(.title3.weight(.bold))
                Spacer()
                Button {
                    viewModel.showCreateSheet = false
                    viewModel.resetForm()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        label("NAME")
                        TextField("e.g. Biology Chapter 4", text: $viewModel.newCanvasName)
                            .font(.body).focused($nameFocused).submitLabel(.done)
                        Divider()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        label("CANVAS SIZE")
                        VStack(spacing: 8) {
                            ForEach(CanvasSize.allCases, id: \.self) { size in
                                canvasSizeRow(size)
                            }
                        }
                        if viewModel.selectedCanvasSize == .custom {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Width (pt)").font(.caption).foregroundStyle(.secondary)
                                    TextField("800", text: $viewModel.customWidth)
                                        .font(.body).focused($widthFocused)
                                        #if os(iOS)
                                        .keyboardType(.numberPad)
                                        #endif
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.secondary.opacity(0.08)))
                                }
                                Text("×").font(.title3).foregroundStyle(.secondary).padding(.top, 16)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Height (pt)").font(.caption).foregroundStyle(.secondary)
                                    TextField("600", text: $viewModel.customHeight)
                                        .font(.body).focused($heightFocused)
                                        #if os(iOS)
                                        .keyboardType(.numberPad)
                                        #endif
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.secondary.opacity(0.08)))
                                }
                            }.padding(.top, 4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        label("ICON")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))], spacing: 10) {
                            ForEach(viewModel.iconOptions) { icon in
                                let isSelected = viewModel.newCanvasIconName == icon.symbol
                                let iconColor  = viewModel.colorFromString(icon.color)
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(isSelected ? iconColor.opacity(0.15) : Color.clear)
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(
                                            isSelected ? iconColor : Color.secondary.opacity(0.2),
                                            lineWidth: isSelected ? 2 : 1)
                                    Image(systemName: icon.symbol)
                                        .font(.system(size: 20, weight: .light))
                                        .foregroundStyle(isSelected ? iconColor : .secondary)
                                }
                                .frame(width: 52, height: 52)
                                .onTapGesture {
                                    withAnimation(.spring(duration: 0.2)) {
                                        viewModel.newCanvasIconName  = icon.symbol
                                        viewModel.newCanvasIconColor = icon.color
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            Button {
                if canCreateCanvas {
                    viewModel.createCanvas(context: context)
                } else {
                    onProRequired()
                }
            } label: {
                Text("Create Canvas").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(viewModel.newCanvasName.isEmpty
                                ? Color.secondary.opacity(0.2) : Color.accentColor)
                    .foregroundStyle(viewModel.newCanvasName.isEmpty ? Color.secondary : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(viewModel.newCanvasName.isEmpty)
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .onAppear { nameFocused = true }
    }

    private func canvasSizeRow(_ size: CanvasSize) -> some View {
        let isSelected = viewModel.selectedCanvasSize == size
        return Button {
            withAnimation(.spring(duration: 0.2)) { viewModel.selectedCanvasSize = size }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07))
                        .frame(width: 36, height: 36)
                    Image(systemName: size.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(size.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(size.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor).font(.system(size: 18))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.06) : Color.secondary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
    }
}

// MARK: - Rename Canvas Sheet

struct RenameCanvasSheet: View {
    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.modelContext) private var context
    let canvas: CanvasModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Rename").font(.title3.weight(.bold))
                Spacer()
                Button { viewModel.selectedCanvasForRename = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("NAME")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
                TextField("Canvas name", text: $viewModel.renameText)
                    .font(.body).focused($focused).submitLabel(.done)
                    .onSubmit {
                        viewModel.renameCanvas(canvas: canvas, newName: viewModel.renameText, context: context)
                        viewModel.selectedCanvasForRename = nil
                    }
                Divider()
            }
            .padding(.horizontal, 24).padding(.top, 20)

            Spacer()

            Button {
                viewModel.renameCanvas(canvas: canvas, newName: viewModel.renameText, context: context)
                viewModel.selectedCanvasForRename = nil
            } label: {
                Text("Save").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(viewModel.renameText.isEmpty
                                ? Color.secondary.opacity(0.2) : Color.accentColor)
                    .foregroundStyle(viewModel.renameText.isEmpty ? Color.secondary : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(viewModel.renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 24).padding(.bottom, 16)
        }
        .onAppear { focused = true }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: CanvasModel.self, inMemory: true)
}
