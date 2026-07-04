import SwiftUI
import SwiftData

struct StickyNoteView: View {
    @Environment(\.modelContext) private var context
    let note: StickyNoteModel
    let canvasScale: CGFloat
    let canvasBoundary: CGSize
    @ObservedObject var vm: StickyNoteViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect: Bool = false
    var onExternalTap: (() -> Void)? = nil
    var isCanvasGestureActive: Bool = false

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var resizeDelta: CGSize = .zero
    @State private var tapTimer: Timer? = nil
    @State private var tapCount = 0
    @StateObject private var textEditing = EditableTextBehavior()
    @FocusState private var textFocused: Bool

    private var isSelected: Bool { vm.editingID == note.id }
    private var isWriting: Bool { vm.writingID == note.id && !note.isCollapsed && !isMultiSelectMode }
    private var palette: StickyNoteColor { StickyNoteColor.color(named: note.colorName) }
    private var currentSize: CGSize {
        note.isCollapsed
        ? CGSize(width: min(max(CGFloat(note.width), 118), 180), height: 48)
        : CGSize(width: max(96, note.width + resizeDelta.width),
                 height: max(72, note.height + resizeDelta.height))
    }
    private let foldSize: CGFloat = 26
    private let handleSize: CGFloat = 26
    private var activeFoldSize: CGFloat { note.isCollapsed ? 16 : foldSize }

    var body: some View {
        ZStack {
            noteBody
            foldedCorner
            selectionRing
            collapseButton
            if isSelected && !isMultiSelectMode && !note.isCollapsed { toolbar; cornerHandles }
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .rotationEffect(.degrees(note.rotation))
        .position(x: note.x + dragOffset.width, y: note.y + dragOffset.height)
        .gesture(canMove ? moveDragGesture : nil)
        .onAppear { textEditing.load(note.text) }
        .onChange(of: vm.editingID) { _, newID in
            if newID != note.id {
                commitLocalTextIfNeeded()
                textFocused = false
            }
        }
        .onChange(of: vm.writingID) { _, newID in
            if newID == note.id {
                textEditing.load(note.text, force: true)
                textFocused = true
            } else {
                commitLocalTextIfNeeded()
                textFocused = false
            }
        }
        .onChange(of: note.text) { _, newText in
            if !isWriting {
                textEditing.load(newText)
            }
        }
        .onDisappear {
            commitLocalTextIfNeeded()
        }
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isMultiSelectMode {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isSelectedInMultiSelect ? Color.blue : Color.white.opacity(0.3),
                    lineWidth: isSelectedInMultiSelect ? 2.5 : 1
                )
                .frame(width: currentSize.width, height: currentSize.height)
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

    private var noteBody: some View {
        ZStack(alignment: .topLeading) {
            FoldedRectangle(foldSize: activeFoldSize).fill(palette.background)
            stickyTextEditor
                .padding(note.isCollapsed
                         ? EdgeInsets(top: 10, leading: 12, bottom: 8, trailing: activeFoldSize + 10)
                         : EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: activeFoldSize + 8))
        }
        .overlay(
            FoldedRectangle(foldSize: activeFoldSize)
                .stroke(
                    isSelected && !isMultiSelectMode ? Color.accentColor.opacity(0.6) : Color.clear,
                    lineWidth: 2
                )
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            isMultiSelectMode ? nil :
            TapGesture(count: 1).onEnded { handleTap() }
        )
    }

    private var stickyTextEditor: some View {
        Group {
            if isWriting {
                TextEditor(text: $textEditing.draft)
                    .focused($textFocused)
                    .font(stickyFont)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .onChange(of: textEditing.draft) { old, new in
                        if applyListContinuation(old: old, new: new) {
                            textEditing.handleDraftChange(
                                localSave: saveStickyText,
                                remoteSync: syncStickyNote
                            )
                            return
                        }
                        textEditing.handleDraftChange(
                            localSave: saveStickyText,
                            remoteSync: syncStickyNote
                        )
                    }
            } else {
                Text(previewText)
                    .font(stickyFont)
                    .foregroundStyle(textEditing.draft.isEmpty
                                     ? Color.black.opacity(0.35)
                                     : Color.black.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .multilineTextAlignment(.leading)
                    .lineLimit(note.isCollapsed ? 1 : nil)
            }
        }
    }

    private var previewText: String {
        let draft = textEditing.draft
        if draft.isEmpty { return note.isCollapsed ? "Sticky Note" : "Write something..." }
        if note.isCollapsed {
            return draft.components(separatedBy: .newlines)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "Sticky Note"
        }
        return draft
    }

    private func applyListContinuation(old: String, new: String) -> Bool {
        guard note.listStyle != .none else { return false }
        guard new.count > old.count, let lastChar = new.last, lastChar == "\n" else { return false }
        let lines = new.components(separatedBy: "\n")
        if lines.count >= 2 {
            let prev = lines[lines.count - 2]
            let trimmed = prev.trimmingCharacters(in: .whitespaces)
            if trimmed == "•" || trimmed.range(of: #"^\d+\.$"#, options: .regularExpression) != nil {
                var rebuilt = lines.dropLast(2).joined(separator: "\n")
                if !rebuilt.isEmpty { rebuilt += "\n" }
                textEditing.draft = rebuilt
                return true
            }
        }
        switch note.listStyle {
        case .bullets:
            textEditing.draft = new + "• "
            return true
        case .numbers:
            textEditing.draft = new + "\(numberedLineCount(in: new) + 1). "
            return true
        case .none:
            return false
        }
    }

    private func numberedLineCount(in text: String) -> Int {
        text.components(separatedBy: "\n")
            .filter { $0.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil }.count
    }

    private func applyListStyle(_ style: StickyListStyle) {
        let styleChanged = note.listStyle != style
        note.listStyle = style
        var lines = textEditing.draft.components(separatedBy: "\n").map { stripPrefix($0) }
        switch style {
        case .none: break
        case .bullets: lines = lines.map { $0.isEmpty ? "" : "• \($0)" }
        case .numbers:
            var idx = 0
            lines = lines.map { l in if l.isEmpty { return "" }; idx += 1; return "\(idx). \(l)" }
        }
        textEditing.draft = lines.joined(separator: "\n")
        let textChanged = saveStickyText(textEditing.draft)

        guard styleChanged || textChanged else { return }
        if !textChanged {
            note.updatedAt = Date()
            try? context.save()
        }
        textEditing.scheduleRemoteSync(syncStickyNote)
    }

    private func stripPrefix(_ line: String) -> String {
        var s = line
        if s.hasPrefix("• ") { s.removeFirst(2) }
        if let m = s.range(of: #"^\d+\.\s"#, options: .regularExpression) { s.removeSubrange(m) }
        return s
    }

    private var foldedCorner: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                path.move(to: CGPoint(x: w - activeFoldSize, y: 0))
                path.addLine(to: CGPoint(x: w, y: activeFoldSize))
                path.addLine(to: CGPoint(x: w - activeFoldSize, y: activeFoldSize))
                path.closeSubpath()
            }
            .fill(palette.foldShadow)
        }.allowsHitTesting(false)
    }

    @ViewBuilder
    private var collapseButton: some View {
        if !isMultiSelectMode && (isSelected || note.isCollapsed) {
            Button {
                commitLocalTextIfNeeded()
                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                    vm.setCollapsed(note: note, collapsed: !note.isCollapsed, context: context)
                }
            } label: {
                Image(systemName: note.isCollapsed ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .frame(width: 24, height: 24)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help(note.isCollapsed ? "Expand" : "Collapse")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .offset(x: 10, y: -10)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            listButton(.none, icon: "text.alignleft")
            listButton(.bullets, icon: "list.bullet")
            listButton(.numbers, icon: "list.number")
            Divider().frame(height: 18)
            formatButton(icon: "bold", active: note.isBold) {
                note.isBold.toggle()
                markStickyChanged()
            }
            formatButton(icon: "italic", active: note.isItalic) {
                note.isItalic.toggle()
                markStickyChanged()
            }
            Divider().frame(height: 18)
            colorMenu
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .frame(maxHeight: .infinity, alignment: .top).offset(y: -32)
    }

    private func listButton(_ style: StickyListStyle, icon: String) -> some View {
        Button { applyListStyle(style) } label: {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(note.listStyle == style ? Color.accentColor : Color.primary.opacity(0.7))
                .frame(width: 26, height: 26)
        }.buttonStyle(.plain)
    }

    private func formatButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : Color.primary.opacity(0.7))
                .frame(width: 26, height: 26)
        }.buttonStyle(.plain)
    }

    private var colorMenu: some View {
        Menu {
            ForEach(StickyNoteColor.allColors) { c in
                Button {
                    note.colorName = c.name
                    markStickyChanged()
                } label: {
                    HStack {
                        Circle().fill(c.background).frame(width: 14, height: 14)
                        Text(c.name.capitalized)
                    }
                }
            }
        } label: {
            Circle().fill(palette.background).frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1))
        }
    }

    private var cornerHandles: some View {
        ZStack {
            Button { vm.delete(note: note, context: context) } label: {
                handleCircle(icon: "trash", color: .red)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .offset(x: -handleSize / 2, y: -handleSize / 2)

            handleCircle(icon: "arrow.up.left.and.arrow.down.right", color: .green)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: handleSize / 2, y: handleSize / 2)
                .gesture(
                    DragGesture()
                        .onChanged { resizeDelta = $0.translation }
                        .onEnded { value in
                            let t = value.translation; resizeDelta = .zero
                            vm.updateSize(note: note, width: note.width + t.width,
                                         height: note.height + t.height, context: context)
                        }
                )
        }
    }

    private func handleCircle(icon: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color).frame(width: handleSize, height: handleSize)
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        }
    }

    private func handleTap() {
        guard !isDragging, !isCanvasGestureActive else { return }

        tapCount += 1
        if tapCount == 1 {
            tapTimer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: false) { _ in
                DispatchQueue.main.async {
                    if tapCount == 1 {
                        selectNote()
                    }
                    tapCount = 0
                    tapTimer = nil
                }
            }
        } else if tapCount >= 2 {
            tapTimer?.invalidate()
            tapTimer = nil
            tapCount = 0
            startWriting()
        }
    }

    private func selectNote() {
        if !isSelected {
            onExternalTap?()
            vm.editingID = note.id
        }
    }

    private func startWriting() {
        if !isSelected {
            onExternalTap?()
        }
        if note.isCollapsed {
            vm.setCollapsed(note: note, collapsed: false, context: context)
        }
        vm.startWriting(noteID: note.id)
    }

    private func commitLocalTextIfNeeded() {
        textEditing.commitDraft(
            localSave: saveStickyText,
            remoteSync: syncStickyNote
        )
    }

    private func saveStickyText(_ text: String) -> Bool {
        guard note.text != text else { return false }
        note.text = text
        note.updatedAt = Date()
        try? context.save()
        return true
    }

    private func markStickyChanged() {
        note.updatedAt = Date()
        try? context.save()
        textEditing.scheduleRemoteSync(syncStickyNote)
    }

    private func syncStickyNote() async {
        await StickyNoteSyncService.shared.upsert(note)
    }

    // MARK: - Move drag gesture
    // minimumDistance: 8 ensures taps don't accidentally trigger moves.
    // isDragging flag prevents the tap handler firing after a drag ends.

    private var moveDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard canMove else {
                    isDragging = false
                    dragOffset = .zero
                    return
                }
                isDragging = true
                dragOffset = value.translation
                // Dismiss keyboard while dragging so it doesn't fight the gesture
                if textFocused { textFocused = false }
            }
            .onEnded { value in
                guard canMove else {
                    dragOffset = .zero
                    isDragging = false
                    return
                }
                let t = value.translation
                dragOffset = .zero
                vm.updatePosition(note: note, translation: t,
                                  scale: canvasScale, boundary: canvasBoundary, context: context)
                // Small delay so the tap handler sees isDragging = true and skips
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isDragging = false
                }
            }
    }

    private var canMove: Bool {
        isSelected && !isMultiSelectMode && !isCanvasGestureActive
    }

    private var stickyFont: Font {
        var f: Font = note.fontName == "system"
            ? .system(size: note.fontSize)
            : .custom(note.fontName, size: note.fontSize)
        if note.isBold { f = f.bold() }
        if note.isItalic { f = f.italic() }
        return f
    }
}

struct FoldedRectangle: InsettableShape {
    let foldSize: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        let c: CGFloat = 4
        path.move(to: CGPoint(x: r.minX + c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - foldSize, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + foldSize))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        path.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY),
                          control: CGPoint(x: r.maxX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        path.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c),
                          control: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        path.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY),
                          control: CGPoint(x: r.minX, y: r.minY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var s = self; s.insetAmount += amount; return s
    }
}
