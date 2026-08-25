import SwiftUI
import SwiftData
import Auth
import StoreKit

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var pro = ProManager.shared
    @Environment(\.modelContext) private var context
    @Environment(\.requestReview) private var requestReview
    @Query(sort: \CanvasModel.createdAt, order: .reverse) var canvases: [CanvasModel]

    @State private var showSettings = false
    @State private var showFeedback = false
    @State private var requestReviewAfterFeedback = false
    @State private var isSyncing = false
    @State private var showPaywall = false
    @State private var showAuth = false
    @State private var searchText = ""
    @State private var sortOrder: CanvasLibrarySort = .newest

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 18)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.secondary.opacity(0.035)
                    .ignoresSafeArea()

                homeContent
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
            .sheet(isPresented: $showFeedback, onDismiss: requestPendingReviewIfNeeded) {
                FeedbackSheet {
                    requestReviewAfterFeedback = true
                }
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
                    subtitle: "Sign in to restore your canvases and sync Canvio Pro across all your devices.",
                    onSignedIn: {
                        showAuth = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
        }
    }

    private var canCreateCanvas: Bool {
        pro.isPro || canvases.count < 2
    }

    private func handleCreateCanvasTap() {
        if canCreateCanvas {
            viewModel.prepareToCreateCanvas(existingCanvases: canvases)
        } else {
            showPaywall = true
        }
    }

    private func handleSyncTap() {
        guard pro.canUseCloudSync else {
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
        if pro.canUseCloudSync, auth.currentUser == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showAuth = true
            }
        }
    }

    // MARK: - Sync

    private func syncAll() async {
        guard !isSyncing, pro.canUseCloudSync, auth.currentUser != nil else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Pull canvases first
        await CanvasSyncService.shared.pullAll(context: context)

        // Pull all element types for every canvas
        let allCanvases = (try? context.fetch(FetchDescriptor<CanvasModel>())) ?? []
        for canvas in allCanvases {
            await CanvasPageSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            for contentCanvasID in pageContentCanvasIDs(for: canvas.id) {
                await pullElements(canvasID: contentCanvasID)
            }
        }
    }

    private func pageContentCanvasIDs(for canvasID: UUID) -> [UUID] {
        let pages = (try? context.fetch(FetchDescriptor<CanvasPageModel>())) ?? []
        let ids = pages
            .filter { $0.canvasID == canvasID }
            .map(\.resolvedContentCanvasID)
        return ids.isEmpty ? [canvasID] : Array(Set(ids))
    }

    private func pullElements(canvasID: UUID) async {
        await ElementGroupSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await TextSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await StickyNoteSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await ShapeSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await ConnectorSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await DrawingSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await TodoSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await TableSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await ImageSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await PDFSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await AudioSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await YouTubeSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await SymbolSyncService.shared.pullAll(canvasID: canvasID, context: context)
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

    // MARK: - Canvas Library

    private var homeContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                libraryHero
                feedbackSupportBanner

                if canvases.isEmpty {
                    emptyState
                } else {
                    libraryControls

                    if filteredCanvases.isEmpty {
                        noSearchResults
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(filteredCanvases) { canvas in
                                canvasTile(canvas)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
    }

    private var filteredCanvases: [CanvasModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = query.isEmpty
            ? canvases
            : canvases.filter { $0.name.localizedCaseInsensitiveContains(query) }

        switch sortOrder {
        case .newest:
            return matches.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return matches.sorted { $0.createdAt < $1.createdAt }
        case .name:
            return matches.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    private var libraryHero: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.18),
                            Color.purple.opacity(0.09),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(Color.accentColor.opacity(0.10), lineWidth: 28)
                .frame(width: 180, height: 180)
                .offset(x: 58, y: -82)

            Circle()
                .fill(Color.purple.opacity(0.08))
                .frame(width: 82, height: 82)
                .offset(x: -42, y: 76)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    heroCopy
                    Spacer(minLength: 20)
                    newCanvasButton
                }

                VStack(alignment: .leading, spacing: 18) {
                    heroCopy
                    newCanvasButton
                }
            }
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.14), lineWidth: 1)
        }
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("YOUR WORKSPACE", systemImage: "sparkles")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Color.accentColor)

            Text("Make room for your next idea.")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            Text(heroSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var heroSubtitle: String {
        if canvases.isEmpty {
            return "Start with a blank canvas and shape it as you think."
        }
        let noun = canvases.count == 1 ? "canvas" : "canvases"
        return "You have \(canvases.count) \(noun) ready to continue."
    }

    private var newCanvasButton: some View {
        Button(action: handleCreateCanvasTap) {
            Label("New Canvas", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(Color.accentColor.gradient)
                .clipShape(Capsule())
                .shadow(color: Color.accentColor.opacity(0.22), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var feedbackSupportBanner: some View {
        Button {
            showFeedback = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.teal.opacity(0.13))
                        .frame(width: 44, height: 44)
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.teal)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Feedback & Support")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Report a bug · Request a feature · Share an opinion")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.teal.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Feedback and Support")
        .accessibilityHint("Report a bug, request a feature, or share an opinion")
    }

    private func requestPendingReviewIfNeeded() {
        guard requestReviewAfterFeedback else { return }
        requestReviewAfterFeedback = false

        Task { @MainActor in
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

    private var libraryControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(searchText.isEmpty ? "Recent canvases" : "Search results")
                        .font(.title3.weight(.bold))
                    Text("\(filteredCanvases.count) \(filteredCanvases.count == 1 ? "canvas" : "canvases")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search canvases", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(.background.opacity(0.92), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
                }

                Menu {
                    Picker("Sort canvases", selection: $sortOrder) {
                        ForEach(CanvasLibrarySort.allCases) { option in
                            Label(option.title, systemImage: option.icon)
                                .tag(option)
                        }
                    }
                } label: {
                    Label(sortOrder.title, systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 15)
                        .frame(height: 44)
                        .background(.background.opacity(0.92), in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func canvasTile(_ canvas: CanvasModel) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(destination: CanvasView(
                canvas: canvas,
                onDelete: { viewModel.deleteCanvas(canvas: canvas, context: context) },
                onRename: { newName in
                    viewModel.renameCanvas(canvas: canvas, newName: newName, context: context)
                }
            )) {
                CanvasCard(canvas: canvas, viewModel: viewModel)
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    beginRenaming(canvas)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    viewModel.deleteCanvas(canvas: canvas, context: context)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("More options for \(canvas.name)")
        }
        .contextMenu {
            Button {
                beginRenaming(canvas)
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                viewModel.deleteCanvas(canvas: canvas, context: context)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func beginRenaming(_ canvas: CanvasModel) {
        viewModel.renameText = canvas.name
        viewModel.selectedCanvasForRename = canvas
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 132, height: 92)
                    .rotationEffect(.degrees(-7))
                    .offset(x: -16, y: 3)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.purple.opacity(0.09))
                    .frame(width: 132, height: 92)
                    .rotationEffect(.degrees(6))
                    .offset(x: 16, y: 3)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.background)
                    .frame(width: 132, height: 92)
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 6)

                Image(systemName: "scribble.variable")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 7) {
                Text("Your first idea starts here")
                    .font(.title3.weight(.bold))

                Text("Create a canvas for notes, diagrams, planning, or anything that needs more room.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            Button(action: handleCreateCanvasTap) {
                Label("Create Canvas 1", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.vertical, 46)
        .background(.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.10), lineWidth: 1)
        }
    }

    private var noSearchResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No matching canvases")
                .font(.headline)
            Text("Try a different canvas name.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }
}

private enum CanvasLibrarySort: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case name

    var id: Self { self }

    var title: String {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .name: return "Name"
        }
    }

    var icon: String {
        switch self {
        case .newest: return "clock.arrow.circlepath"
        case .oldest: return "clock"
        case .name: return "textformat"
        }
    }
}

// MARK: - Canvas Card

struct CanvasCard: View {
    let canvas: CanvasModel
    let viewModel: HomeViewModel

    private var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(canvas.createdAt) { return "Today" }
        if calendar.isDateInYesterday(canvas.createdAt) { return "Yesterday" }
        return canvas.createdAt.formatted(.dateTime.month(.abbreviated).day())
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
                        .frame(height: 132)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.08)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                } else {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.16), accentColor.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 132)

                    Circle()
                        .stroke(accentColor.opacity(0.10), lineWidth: 18)
                        .frame(width: 112, height: 112)
                        .offset(x: 100, y: -46)

                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.background.opacity(0.82))
                            .frame(width: 54, height: 54)
                        Image(systemName: canvas.iconName)
                            .font(.system(size: 24, weight: .medium))
                    }
                        .foregroundStyle(accentColor)
                        .padding(16)
                }
            }
            .frame(height: 132)
            .clipped()

            VStack(alignment: .leading, spacing: 7) {
                Text(canvas.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label(canvas.canvasSize.displayName, systemImage: canvas.canvasSize.icon)
                        .lineLimit(1)
                    Text("•")
                    Text(formattedDate)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .background(.background.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
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
