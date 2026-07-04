import SwiftData
import SwiftUI

enum CanvasTemplateCategory: String, CaseIterable, Identifiable {
    case planning
    case study
    case work
    case thinking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planning: return "Planning"
        case .study:    return "Study"
        case .work:     return "Work"
        case .thinking: return "Thinking"
        }
    }
}

struct CanvasTemplate: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let category: CanvasTemplateCategory
    let icon: String
    let tint: Color
    let size: CGSize
    let items: [CanvasTemplateItem]

    var tableCount: Int {
        items.reduce(0) { count, item in
            if case .table = item { return count + 1 }
            return count
        }
    }
}

enum CanvasTemplateItem {
    case text(TemplateText)
    case sticky(TemplateSticky)
    case todo(TemplateTodo)
    case shape(TemplateShape)
    case table(TemplateTable)

    var previewIcon: String {
        switch self {
        case .text:   return "textformat"
        case .sticky: return "note.text"
        case .todo:   return "checklist"
        case .shape:  return "square.on.circle"
        case .table:  return "tablecells"
        }
    }

    var previewTint: Color {
        switch self {
        case .text:   return .blue
        case .sticky: return .orange
        case .todo:   return .green
        case .shape:  return .purple
        case .table:  return .indigo
        }
    }
}

struct TemplateText {
    let text: String
    let center: CGPoint
    var fontSize: Double = 20
    var isBold: Bool = false
    var colorName: String = "primary"
    var alignmentRaw: String = "leading"
    var bgColorName: String = "none"
    var strokeColorName: String = "none"
    var strokeWidth: Double = 2
}

struct TemplateSticky {
    let text: String
    let center: CGPoint
    var size: CGSize = CGSize(width: 220, height: 180)
    var colorName: String = "yellow"
    var fontSize: Double = 16
}

struct TemplateTodo {
    let title: String
    let center: CGPoint
    let tasks: [String]
    var size: CGSize = CGSize(width: 280, height: 300)
    var colorName: String = "blue"
}

struct TemplateShape {
    let kind: ShapeKind
    let center: CGPoint
    var size: CGSize
    var rotation: Double = 0
    var strokeColorName: String = "primary"
    var fillColorName: String = "blue"
    var hasFill: Bool = false
    var strokeWidth: Double = 2.5
    var hasArrowHead: Bool = false
}

struct TemplateTable {
    let center: CGPoint
    let rows: Int
    let cols: Int
    var cellWidth: Double = 96
    var cellHeight: Double = 38
    var values: [TemplateTableCell] = []
}

struct TemplateTableCell {
    let row: Int
    let col: Int
    let value: String
    var backgroundColorName: String = "clear"
    var textColorName: String = "adaptive"
    var alignmentRaw: String = "leading"
    var isBold: Bool = false
}

enum CanvasTemplateService {
    static let templates: [CanvasTemplate] = [
        CanvasTemplate(
            id: "weekly-planner",
            title: "Weekly Planner",
            subtitle: "Plan days, priorities, and tasks",
            category: .planning,
            icon: "calendar",
            tint: .indigo,
            size: CGSize(width: 920, height: 620),
            items: [
                .text(TemplateText(text: "Weekly Planner", center: CGPoint(x: 460, y: 56), fontSize: 34, isBold: true)),
                .sticky(TemplateSticky(text: "Top priorities\n- \n- \n-", center: CGPoint(x: 170, y: 210), size: CGSize(width: 250, height: 190), colorName: "yellow")),
                .todo(TemplateTodo(title: "Tasks", center: CGPoint(x: 176, y: 462), tasks: ["Review goals", "Block focus time", "Wrap up"], size: CGSize(width: 280, height: 250), colorName: "green")),
                .table(TemplateTable(
                    center: CGPoint(x: 600, y: 330),
                    rows: 5,
                    cols: 3,
                    values: [
                        TemplateTableCell(row: 0, col: 0, value: "Monday", isBold: true),
                        TemplateTableCell(row: 1, col: 0, value: "Tuesday", isBold: true),
                        TemplateTableCell(row: 2, col: 0, value: "Wednesday", isBold: true),
                        TemplateTableCell(row: 3, col: 0, value: "Thursday", isBold: true),
                        TemplateTableCell(row: 4, col: 0, value: "Friday", isBold: true),
                        TemplateTableCell(row: 0, col: 1, value: "Focus"),
                        TemplateTableCell(row: 0, col: 2, value: "Notes")
                    ]
                ))
            ]
        ),
        CanvasTemplate(
            id: "study-plan",
            title: "Study Plan",
            subtitle: "Break a topic into goals and review",
            category: .study,
            icon: "book.closed",
            tint: .blue,
            size: CGSize(width: 900, height: 620),
            items: [
                .text(TemplateText(text: "Study Plan", center: CGPoint(x: 450, y: 56), fontSize: 34, isBold: true)),
                .sticky(TemplateSticky(text: "Topic\n\nWhat am I learning?", center: CGPoint(x: 160, y: 202), size: CGSize(width: 250, height: 190), colorName: "blue")),
                .sticky(TemplateSticky(text: "Key ideas\n- \n- \n-", center: CGPoint(x: 450, y: 202), size: CGSize(width: 250, height: 190), colorName: "yellow")),
                .sticky(TemplateSticky(text: "Questions\n- \n- \n-", center: CGPoint(x: 740, y: 202), size: CGSize(width: 250, height: 190), colorName: "pink")),
                .todo(TemplateTodo(title: "Review checklist", center: CGPoint(x: 230, y: 470), tasks: ["Read", "Practice", "Summarize", "Review tomorrow"], size: CGSize(width: 330, height: 260), colorName: "blue")),
                .table(TemplateTable(
                    center: CGPoint(x: 640, y: 470),
                    rows: 3,
                    cols: 3,
                    values: [
                        TemplateTableCell(row: 0, col: 0, value: "Concept", isBold: true),
                        TemplateTableCell(row: 0, col: 1, value: "Example", isBold: true),
                        TemplateTableCell(row: 0, col: 2, value: "Status", isBold: true)
                    ]
                ))
            ]
        ),
        CanvasTemplate(
            id: "meeting-notes",
            title: "Meeting Notes",
            subtitle: "Capture agenda, decisions, and actions",
            category: .work,
            icon: "person.2",
            tint: .teal,
            size: CGSize(width: 860, height: 560),
            items: [
                .text(TemplateText(text: "Meeting Notes", center: CGPoint(x: 430, y: 56), fontSize: 32, isBold: true)),
                .sticky(TemplateSticky(text: "Agenda\n- \n- \n-", center: CGPoint(x: 160, y: 235), size: CGSize(width: 260, height: 260), colorName: "yellow")),
                .sticky(TemplateSticky(text: "Decisions\n- \n- \n-", center: CGPoint(x: 430, y: 235), size: CGSize(width: 260, height: 260), colorName: "green")),
                .todo(TemplateTodo(title: "Action items", center: CGPoint(x: 710, y: 285), tasks: ["Owner + next step", "Follow up", "Share notes"], size: CGSize(width: 280, height: 330), colorName: "blue"))
            ]
        ),
        CanvasTemplate(
            id: "mind-map",
            title: "Mind Map",
            subtitle: "Start from one idea and branch out",
            category: .thinking,
            icon: "point.topleft.down.to.point.bottomright.curvepath",
            tint: .purple,
            size: CGSize(width: 860, height: 600),
            items: [
                .shape(TemplateShape(kind: .line, center: CGPoint(x: 310, y: 220), size: CGSize(width: 260, height: 4), rotation: -25, strokeColorName: "gray")),
                .shape(TemplateShape(kind: .line, center: CGPoint(x: 550, y: 220), size: CGSize(width: 260, height: 4), rotation: 25, strokeColorName: "gray")),
                .shape(TemplateShape(kind: .line, center: CGPoint(x: 310, y: 380), size: CGSize(width: 260, height: 4), rotation: 25, strokeColorName: "gray")),
                .shape(TemplateShape(kind: .line, center: CGPoint(x: 550, y: 380), size: CGSize(width: 260, height: 4), rotation: -25, strokeColorName: "gray")),
                .shape(TemplateShape(kind: .circle, center: CGPoint(x: 430, y: 300), size: CGSize(width: 170, height: 170), strokeColorName: "purple", fillColorName: "#E9D5FF", hasFill: true, strokeWidth: 3)),
                .text(TemplateText(text: "Main idea", center: CGPoint(x: 430, y: 300), fontSize: 22, isBold: true, alignmentRaw: "center")),
                .shape(TemplateShape(kind: .rectangle, center: CGPoint(x: 170, y: 150), size: CGSize(width: 210, height: 90), strokeColorName: "blue", fillColorName: "#DBEAFE", hasFill: true)),
                .text(TemplateText(text: "Branch 1", center: CGPoint(x: 170, y: 150), fontSize: 18, isBold: true, alignmentRaw: "center")),
                .shape(TemplateShape(kind: .rectangle, center: CGPoint(x: 690, y: 150), size: CGSize(width: 210, height: 90), strokeColorName: "green", fillColorName: "#DCFCE7", hasFill: true)),
                .text(TemplateText(text: "Branch 2", center: CGPoint(x: 690, y: 150), fontSize: 18, isBold: true, alignmentRaw: "center")),
                .shape(TemplateShape(kind: .rectangle, center: CGPoint(x: 170, y: 450), size: CGSize(width: 210, height: 90), strokeColorName: "orange", fillColorName: "#FED7AA", hasFill: true)),
                .text(TemplateText(text: "Branch 3", center: CGPoint(x: 170, y: 450), fontSize: 18, isBold: true, alignmentRaw: "center")),
                .shape(TemplateShape(kind: .rectangle, center: CGPoint(x: 690, y: 450), size: CGSize(width: 210, height: 90), strokeColorName: "pink", fillColorName: "#FCE7F3", hasFill: true)),
                .text(TemplateText(text: "Branch 4", center: CGPoint(x: 690, y: 450), fontSize: 18, isBold: true, alignmentRaw: "center"))
            ]
        ),
        CanvasTemplate(
            id: "project-board",
            title: "Project Board",
            subtitle: "Organize work by stage",
            category: .work,
            icon: "rectangle.3.group",
            tint: .orange,
            size: CGSize(width: 920, height: 600),
            items: [
                .text(TemplateText(text: "Project Board", center: CGPoint(x: 460, y: 54), fontSize: 32, isBold: true)),
                .shape(TemplateShape(kind: .rectangle, center: CGPoint(x: 170, y: 330), size: CGSize(width: 260, height: 420), strokeColorName: "gray", fillColorName: "#F1F5F9", hasFill: true)),
                .shape(TemplateShape(kind: .rectangle, center: CGPoint(x: 460, y: 330), size: CGSize(width: 260, height: 420), strokeColorName: "gray", fillColorName: "#F1F5F9", hasFill: true)),
                .shape(TemplateShape(kind: .rectangle, center: CGPoint(x: 750, y: 330), size: CGSize(width: 260, height: 420), strokeColorName: "gray", fillColorName: "#F1F5F9", hasFill: true)),
                .text(TemplateText(text: "To Do", center: CGPoint(x: 170, y: 150), fontSize: 20, isBold: true, alignmentRaw: "center")),
                .text(TemplateText(text: "Doing", center: CGPoint(x: 460, y: 150), fontSize: 20, isBold: true, alignmentRaw: "center")),
                .text(TemplateText(text: "Done", center: CGPoint(x: 750, y: 150), fontSize: 20, isBold: true, alignmentRaw: "center")),
                .sticky(TemplateSticky(text: "Task idea", center: CGPoint(x: 170, y: 255), size: CGSize(width: 200, height: 130), colorName: "yellow")),
                .sticky(TemplateSticky(text: "In progress", center: CGPoint(x: 460, y: 255), size: CGSize(width: 200, height: 130), colorName: "blue")),
                .todo(TemplateTodo(title: "Next steps", center: CGPoint(x: 750, y: 340), tasks: ["Ship", "Review", "Archive"], size: CGSize(width: 210, height: 250), colorName: "green"))
            ]
        ),
        CanvasTemplate(
            id: "comparison",
            title: "Comparison",
            subtitle: "Compare options and tradeoffs",
            category: .thinking,
            icon: "tablecells",
            tint: .pink,
            size: CGSize(width: 860, height: 560),
            items: [
                .text(TemplateText(text: "Comparison", center: CGPoint(x: 430, y: 56), fontSize: 32, isBold: true)),
                .table(TemplateTable(
                    center: CGPoint(x: 430, y: 245),
                    rows: 4,
                    cols: 3,
                    values: [
                        TemplateTableCell(row: 0, col: 0, value: "Option", isBold: true),
                        TemplateTableCell(row: 0, col: 1, value: "Pros", isBold: true),
                        TemplateTableCell(row: 0, col: 2, value: "Cons", isBold: true)
                    ]
                )),
                .sticky(TemplateSticky(text: "Decision notes\n\n", center: CGPoint(x: 250, y: 455), size: CGSize(width: 260, height: 150), colorName: "yellow")),
                .todo(TemplateTodo(title: "Follow up", center: CGPoint(x: 610, y: 455), tasks: ["Check missing info", "Pick best option"], size: CGSize(width: 270, height: 170), colorName: "pink"))
            ]
        )
    ]

    @discardableResult
    static func insert(
        _ template: CanvasTemplate,
        canvasID: UUID,
        at canvasPoint: CGPoint,
        startZIndex: Int,
        context: ModelContext,
        undoManager: CanvasUndoManager? = nil
    ) -> [UUID] {
        var currentIDs = insertRaw(
            template,
            canvasID: canvasID,
            at: canvasPoint,
            startZIndex: startZIndex,
            context: context
        )

        undoManager?.push(CanvasAction(
            undo: {
                delete(ids: currentIDs, context: context)
                currentIDs = []
            },
            redo: {
                currentIDs = insertRaw(
                    template,
                    canvasID: canvasID,
                    at: canvasPoint,
                    startZIndex: startZIndex,
                    context: context
                )
            }
        ))

        return currentIDs
    }

    private static func insertRaw(
        _ template: CanvasTemplate,
        canvasID: UUID,
        at canvasPoint: CGPoint,
        startZIndex: Int,
        context: ModelContext
    ) -> [UUID] {
        let origin = CGPoint(
            x: canvasPoint.x - template.size.width / 2,
            y: canvasPoint.y - template.size.height / 2
        )
        var zIndex = startZIndex
        var insertedIDs: [UUID] = []
        var texts: [TextElementModel] = []
        var notes: [StickyNoteModel] = []
        var lists: [TodoListModel] = []
        var tasks: [TodoTaskModel] = []
        var shapes: [ShapeElementModel] = []
        var tables: [TableElementModel] = []
        var cells: [TableCellModel] = []

        for item in template.items {
            switch item {
            case .text(let spec):
                let element = TextElementModel(
                    canvasID: canvasID,
                    text: spec.text,
                    x: Double(origin.x + spec.center.x),
                    y: Double(origin.y + spec.center.y)
                )
                element.fontSize = spec.fontSize
                element.isBold = spec.isBold
                element.colorName = spec.colorName
                element.alignmentRaw = spec.alignmentRaw
                element.bgColorName = spec.bgColorName
                element.strokeColorName = spec.strokeColorName
                element.strokeWidth = spec.strokeWidth
                element.zIndex = zIndex
                element.rebuildRichTextFromLegacyStyle()
                zIndex += 1
                context.insert(element)
                texts.append(element)
                insertedIDs.append(element.id)

            case .sticky(let spec):
                let note = StickyNoteModel(
                    canvasID: canvasID,
                    x: Double(origin.x + spec.center.x),
                    y: Double(origin.y + spec.center.y)
                )
                note.text = spec.text
                note.width = Double(spec.size.width)
                note.height = Double(spec.size.height)
                note.colorName = spec.colorName
                note.fontSize = spec.fontSize
                note.zIndex = zIndex
                zIndex += 1
                context.insert(note)
                notes.append(note)
                insertedIDs.append(note.id)

            case .todo(let spec):
                let list = TodoListModel(
                    canvasID: canvasID,
                    x: Double(origin.x + spec.center.x),
                    y: Double(origin.y + spec.center.y)
                )
                list.title = spec.title
                list.width = Double(spec.size.width)
                list.height = Double(spec.size.height)
                list.colorName = spec.colorName
                list.zIndex = zIndex
                zIndex += 1
                context.insert(list)
                lists.append(list)
                insertedIDs.append(list.id)

                for (index, title) in spec.tasks.enumerated() {
                    let task = TodoTaskModel(listID: list.id, title: title, order: index)
                    context.insert(task)
                    tasks.append(task)
                }

            case .shape(let spec):
                let shape = ShapeElementModel(
                    canvasID: canvasID,
                    kind: spec.kind,
                    x: Double(origin.x + spec.center.x),
                    y: Double(origin.y + spec.center.y)
                )
                shape.width = Double(spec.size.width)
                shape.height = Double(spec.size.height)
                shape.rotation = spec.rotation
                shape.strokeColorName = spec.strokeColorName
                shape.fillColorName = spec.fillColorName
                shape.hasFill = spec.hasFill
                shape.strokeWidth = spec.strokeWidth
                shape.hasArrowHead = spec.hasArrowHead
                shape.zIndex = zIndex
                zIndex += 1
                context.insert(shape)
                shapes.append(shape)
                insertedIDs.append(shape.id)

            case .table(let spec):
                let table = TableElementModel(
                    canvasID: canvasID,
                    rows: spec.rows,
                    cols: spec.cols,
                    x: Double(origin.x + spec.center.x),
                    y: Double(origin.y + spec.center.y)
                )
                table.cellWidth = spec.cellWidth
                table.cellHeight = spec.cellHeight
                table.zIndex = zIndex
                zIndex += 1
                context.insert(table)
                tables.append(table)
                insertedIDs.append(table.id)

                let valueMap = Dictionary(
                    uniqueKeysWithValues: spec.values.map { ("\($0.row)-\($0.col)", $0) }
                )
                for row in 0..<spec.rows {
                    for col in 0..<spec.cols {
                        let cell = TableCellModel(tableID: table.id, row: row, col: col)
                        if let value = valueMap["\(row)-\(col)"] {
                            cell.value = value.value
                            cell.backgroundColorName = value.backgroundColorName
                            cell.textColorName = value.textColorName
                            cell.alignmentRaw = value.alignmentRaw
                            cell.isBold = value.isBold
                        }
                        context.insert(cell)
                        cells.append(cell)
                    }
                }
            }
        }

        try? context.save()

        for element in texts { Task { await TextSyncService.shared.upsert(element) } }
        for note in notes { Task { await StickyNoteSyncService.shared.upsert(note) } }
        for list in lists { Task { await TodoSyncService.shared.upsertList(list) } }
        for task in tasks { Task { await TodoSyncService.shared.upsertTask(task) } }
        for shape in shapes { Task { await ShapeSyncService.shared.upsert(shape) } }
        for table in tables { Task { await TableSyncService.shared.upsertTable(table) } }
        if !cells.isEmpty { Task { await TableSyncService.shared.upsertCells(cells) } }

        return insertedIDs
    }

    private static func delete(ids: [UUID], context: ModelContext) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)

        let allCells = (try? context.fetch(FetchDescriptor<TableCellModel>())) ?? []
        for table in ((try? context.fetch(FetchDescriptor<TableElementModel>())) ?? []).filter({ idSet.contains($0.id) }) {
            let tableCells = allCells.filter { $0.tableID == table.id }
            Task { await TableSyncService.shared.deleteTable(table, cells: tableCells) }
            tableCells.forEach { context.delete($0) }
            context.delete(table)
        }

        let allTasks = (try? context.fetch(FetchDescriptor<TodoTaskModel>())) ?? []
        for list in ((try? context.fetch(FetchDescriptor<TodoListModel>())) ?? []).filter({ idSet.contains($0.id) }) {
            let listTasks = allTasks.filter { $0.listID == list.id }
            Task { await TodoSyncService.shared.deleteList(list, tasks: listTasks) }
            listTasks.forEach { context.delete($0) }
            context.delete(list)
        }

        for text in ((try? context.fetch(FetchDescriptor<TextElementModel>())) ?? []).filter({ idSet.contains($0.id) }) {
            Task { await TextSyncService.shared.delete(text) }
            context.delete(text)
        }

        for note in ((try? context.fetch(FetchDescriptor<StickyNoteModel>())) ?? []).filter({ idSet.contains($0.id) }) {
            Task { await StickyNoteSyncService.shared.delete(note) }
            context.delete(note)
        }

        for shape in ((try? context.fetch(FetchDescriptor<ShapeElementModel>())) ?? []).filter({ idSet.contains($0.id) }) {
            Task { await ShapeSyncService.shared.delete(shape) }
            context.delete(shape)
        }

        try? context.save()
    }
}
