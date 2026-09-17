//
//  RoutinesWindow.swift
//  Kadence
//
//  layouts.md §8 / components.md §13.1 — the Routines window shell: template
//  picker, seven weekday-only columns on the same hour-grid geometry as the
//  main Week view, and an inspector.
//
//  Task P2-T10 built this window read-only. Task P2-T11 (this pass) adds
//  interactions.md §11.1's move / resize / delete — "Creating, moving and
//  resizing routine blocks uses §3 and §4 unchanged ... same handles, same
//  drop preview. `⌫` deletes. `⌘Z` undoes, with names." Still explicitly out
//  of scope, left for follow-up tasks:
//    - creating new routine blocks (drag-to-create, double-click) —
//      interactions.md §11.1 groups this with move/resize ("Creating, moving
//      and resizing ... uses §3 and §4 unchanged"), but this task's own brief
//      carves it out separately; this window still has no create surface;
//    - the Blocks/Windows mode control and Windows-mode editing
//      (components.md §13.3) — there is no `TimeWindow` model yet;
//    - the flexibility control's interactive stepper (components.md §13.2) —
//      the inspector still shows flexibility as read-only text;
//    - detached-instance tracking and Re-sync (components.md §13.4,
//      interactions.md §11.2) — always zero right now, so per the existing
//      zero-state rule (§10.2) it is omitted entirely rather than stubbed;
//    - the background windows layer (protected / low-energy shading), for the
//      same reason P2-T10 left it out — no `TimeWindow` model to draw yet.
//
//  Move/resize/delete go through `RoutineBlockStore`
//  (`Kadence/State/RoutineEngine.swift`) — the Routines-window sibling of
//  `EventStore`, same id-addressed/undo-named shape, written over
//  `startMinutes`/`duration` instead of `Date` since a `RoutineBlock` has
//  none of its own. One store instance, one `UndoStack` (the same one
//  `MainWindow` shares — `KadenceApp.swift` now injects it into this window's
//  `WindowGroup` too, which it did not before this task), so `⌘Z` in either
//  window means the same thing and the Edit menu names the step correctly no
//  matter which window is key.
//
//  A single edit to any one weekday's copy of a block changes the
//  `RoutineBlock`'s own `startMinutes`/`duration` once — there is no
//  per-weekday instance to keep in sync, so the change reflects on every
//  other active-weekday column immediately, for free, the same way
//  `RoutineWeekLayout`'s header already describes for read-only rendering.
//
//  What IS reused, unchanged: `DayLayoutEngine` (the same overlap-resolution
//  engine the main grid uses), `TimeGeometry` (including its `snap` — same
//  15-minute/5-minute-with-⌃ rule as `DayColumnView.blockGesture`),
//  `HourLinesLayer` / `TimeGutterView` (`GridLayers.swift`) and `GridBlockView`
//  (components.md §13.1: "Anything that looks like a block in this window is
//  a block, and behaves like one" — including its built-in hover resize
//  handles, now that `isMovable` is `true`). `DayColumnView`/`TimedCanvasView`
//  themselves are still not reused as SwiftUI containers — they are
//  hard-wired to `Event`/`EventStore`/`CalendarState`/drag-and-drop, none of
//  which apply to a `RoutineBlock` canvas — but the drag gesture below
//  mirrors `DayColumnView.blockGesture`'s shape (mode classification by
//  handle-height, snap, drop preview) rather than re-deriving it.
//

import SwiftUI
import SwiftData

struct RoutinesWindow: View {
    @Query(sort: \RoutineTemplate.name) private var templates: [RoutineTemplate]
    @Environment(\.modelContext) private var context
    /// KadenceApp.swift now injects the same instance MainWindow uses, so
    /// `⌘Z`/`⌘⇧Z` (wired once, app-wide, in `KadenceCommands`) undo/redo
    /// routine edits exactly like event edits — one stack for the whole app.
    @Environment(UndoStack.self) private var undoStack

    @State private var selectedTemplateID: UUID?
    @State private var selection: RoutineBlockSelection?
    @State private var didSeed = false
    /// So `⌫` (below) has somewhere to land. Requested whenever a block is
    /// selected — including the very first tap — since nothing else in this
    /// window claims keyboard focus by default.
    @FocusState private var canvasFocused: Bool

    private var store: RoutineBlockStore {
        RoutineBlockStore(context: context, undo: undoStack)
    }

    private var selectedTemplate: RoutineTemplate? {
        if let selectedTemplateID, let match = templates.first(where: { $0.id == selectedTemplateID }) {
            return match
        }
        return templates.first
    }

    private var selectedBlockSnapshot: RoutineBlockSnapshot? {
        guard let selection, let template = selectedTemplate,
              let block = template.blocks.first(where: { $0.id == selection.blockID })
        else { return nil }
        return block.snapshot
    }

    private var orderedWeekdays: [Int] {
        RoutineWeekLayout.orderedWeekdays(firstWeekday: Calendar.current.firstWeekday)
    }

    var body: some View {
        GeometryReader { proxy in
            // layouts.md §8: "the editor inspector collapses below 1040pt and
            // returns as an overlay, exactly as §1.1 does for the main
            // window. The canvas never collapses." 1040 is a literal from
            // that prose, the same way MainWindow hardcodes its own 1200/900
            // collapse widths rather than a token — there is no
            // `size.*` token for this particular width.
            let isSplit = proxy.size.width >= 1040

            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    canvas
                        .frame(minWidth: 0, maxWidth: .infinity)
                    if isSplit {
                        Rectangle()
                            .fill(Tokens.Color.Separator.region)
                            .frame(width: Tokens.Size.hairline)
                        inspector
                            .frame(width: Tokens.Size.editorInspectorWidth)
                    }
                }

                if !isSplit {
                    inspector
                        .frame(width: Tokens.Size.editorInspectorWidth)
                        .elevation(.level2)
                }
            }
            // interactions.md §11.1/§5 — `⌫` deletes the selected block
            // immediately, no confirmation. Attached at this level (rather
            // than per-block) so it fires regardless of which weekday column
            // the block was last clicked in.
            .focusable()
            .focused($canvasFocused)
            .onKeyPress(keys: [.delete]) { _ in handleDelete() }
        }
        .toolbar { toolbarContent }
        .frame(
            minWidth: Tokens.Size.routineEditorMinWidth,
            minHeight: Tokens.Size.routineEditorMinHeight)
        .task {
            guard !didSeed else { return }
            didSeed = true
            MockData.seedRoutineTemplatesIfNeeded(context)
            canvasFocused = true
        }
        .onChange(of: selectedTemplateID) { _, _ in
            selection = nil
        }
        .onChange(of: selection) { _, newValue in
            if newValue != nil { canvasFocused = true }
        }
    }

    /// `⌫` — no confirmation, matching interactions.md §5's rule for events
    /// ("`⌫` deletes immediately. No confirmation sheet."). `⌘Z` restores it.
    private func handleDelete() -> KeyPress.Result {
        guard let selection, let template = selectedTemplate,
              let block = template.blocks.first(where: { $0.id == selection.blockID })
        else { return .ignored }
        self.selection = nil
        store.delete(block, from: template)
        return .handled
    }

    // MARK: Canvas

    private var canvas: some View {
        VStack(spacing: 0) {
            RoutineWeekdayHeaderRow(weekdays: orderedWeekdays)
            RoutinesCanvasView(
                weekdays: orderedWeekdays,
                template: selectedTemplate,
                store: store,
                selection: $selection)
        }
    }

    // MARK: Inspector (layouts.md §8.1)

    private var inspector: some View {
        RoutineInspectorView(template: selectedTemplate, selectedBlock: selectedBlockSnapshot)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            // The task's own scope note: "a Picker or menu is fine — do not
            // build the [Blocks | Windows] segmented control or the + new-
            // template action yet." Just the picker, nothing else.
            Picker("Template", selection: Binding(
                get: { selectedTemplateID ?? templates.first?.id },
                set: { selectedTemplateID = $0 })) {
                    ForEach(templates, id: \.id) { template in
                        Text(template.name).tag(template.id as UUID?)
                    }
                }
                .labelsHidden()
                .disabled(templates.isEmpty)
        }
    }
}

/// One selected `RoutineBlock` instance, identified by the block itself plus
/// which weekday column it was clicked in — the same block recurs in every
/// one of the template's active weekday columns, so the id alone is
/// ambiguous. Window-scoped state, not `CalendarState` (interactions.md's
/// selection model belongs to the main-grid window; this is a separate
/// window with its own selection).
struct RoutineBlockSelection: Equatable {
    var blockID: UUID
    var weekday: Int
}

// MARK: - Weekday header (components.md §13.1: "no dates, dayHeaderWeekday only")

private struct RoutineWeekdayHeaderRow: View {
    let weekdays: [Int]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: Tokens.Size.timeGutterWidth)
            ForEach(weekdays, id: \.self) { weekday in
                Text(weekdaySymbol(weekday))
                    .typeStyle(.dayHeaderWeekday)
                    .foregroundStyle(Tokens.Color.Text.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Tokens.Size.dayHeaderHeight)
        .background(Tokens.Color.Surface.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Tokens.Color.Separator.region)
                .frame(height: Tokens.Size.hairline)
        }
    }

    private func weekdaySymbol(_ weekday: Int) -> String {
        Calendar.current.shortWeekdaySymbols[weekday - 1]
    }
}

// MARK: - The seven-column canvas

private struct RoutinesCanvasView: View {
    let weekdays: [Int]
    let template: RoutineTemplate?
    let store: RoutineBlockStore
    @Binding var selection: RoutineBlockSelection?

    private let hourHeight = Tokens.Size.hourHeightWeek

    var body: some View {
        GeometryReader { proxy in
            // Same column-floor rule as the main Week view (layouts.md §3.1),
            // just with the Routines window's own floor
            // (`size.routineEditorColumnMin`, 84) rather than
            // `size.dayColumnMin` — components.md §13.1 gives this window a
            // narrower minimum column than the calendar's Week view.
            let available = proxy.size.width - Tokens.Size.timeGutterWidth
            let naturalWidth = available / CGFloat(weekdays.count)
            let columnWidth = max(naturalWidth, Tokens.Size.routineEditorColumnMin)
            let needsHorizontalScroll = columnWidth > naturalWidth

            ScrollView(.vertical) {
                gridBody(columnWidth: columnWidth)
                    .frame(
                        width: needsHorizontalScroll
                            ? Tokens.Size.timeGutterWidth + columnWidth * CGFloat(weekdays.count)
                            : nil,
                        alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .modifier(HorizontalScrollIfNeeded(isEnabled: needsHorizontalScroll))
        }
        .background(Tokens.Color.Surface.canvas)
    }

    private func gridBody(columnWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            TimeGutterView(
                geometry: TimeGeometry(dayStart: Date(), hourHeight: hourHeight),
                now: Date(),
                showsNow: false)
                .frame(width: Tokens.Size.timeGutterWidth)

            ForEach(weekdays, id: \.self) { weekday in
                RoutineDayColumnView(
                    weekday: weekday,
                    template: template,
                    store: store,
                    hourHeight: hourHeight,
                    selection: $selection)
                    .frame(width: columnWidth)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Tokens.Color.Separator.dayDivider)
                            .frame(width: Tokens.Size.hairline)
                    }
            }
        }
    }
}

/// One weekday column: the hour grid plus whichever of the template's blocks
/// land on this weekday. No now-line, no all-day row, no travel bands, no
/// background windows (see this file's header).
///
/// Move/resize (task P2-T11) mirror `DayColumnView.blockGesture`'s shape —
/// same handle-height mode classification, same snap, same drop preview — but
/// write through `RoutineBlockStore` in minutes instead of `EventStore` in
/// `Date`s. Because a block dragged from *any* one of the template's active
/// weekday columns changes the one underlying `RoutineBlock`, the edit is
/// still correct even though this view only ever sees a single column's worth
/// of geometry.
private struct RoutineDayColumnView: View {
    let weekday: Int
    let template: RoutineTemplate?
    let store: RoutineBlockStore
    let hourHeight: CGFloat
    @Binding var selection: RoutineBlockSelection?

    /// In-flight drag, kept local so the model is only written on drop — same
    /// rule as `DayColumnView.DragSession`.
    @State private var drag: RoutineDragSession?
    @State private var hoveredID: UUID?

    struct RoutineDragSession: Equatable {
        enum Mode: Equatable { case move, resizeTop, resizeBottom }
        var mode: Mode
        var blockID: UUID
        var origin: Date
        var current: Date
    }

    private var referenceDayStart: Date {
        RoutineWeekLayout.referenceDayStart(weekday: weekday, now: Date())
    }

    private var blocks: [RoutineBlockSnapshot] {
        template?.blocks.map(\.snapshot) ?? []
    }

    private var layoutItems: [LayoutItem] {
        RoutineWeekLayout.layoutItems(
            blocks: blocks,
            activeWeekdays: template?.activeWeekdays ?? [],
            weekday: weekday,
            referenceDayStart: referenceDayStart)
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = TimeGeometry(dayStart: referenceDayStart, hourHeight: hourHeight)
            let layout = DayLayoutEngine.layout(
                items: layoutItems, columnWidth: proxy.size.width, geometry: geometry)

            ZStack(alignment: .topLeading) {
                HourLinesLayer(geometry: geometry)

                // Empty-grid tap deselects, matching the main grid's
                // "clicking empty grid deselects" (interactions.md §6). Still
                // no create surface here — drag-to-create is out of scope.
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .frame(height: geometry.totalHeight)
                    .accessibilityHidden(true)
                    .onTapGesture { selection = nil }

                ForEach(layout.blocks.sorted(by: { $0.zIndex < $1.zIndex })) { laidOut in
                    if let block = blocks.first(where: { $0.id == laidOut.id }) {
                        blockView(block: block, laidOut: laidOut, geometry: geometry)
                    }
                }

                ForEach(layout.overflow) { chip in
                    overflowChip(chip)
                }

                // interactions.md §4 — "same drop preview" as the main grid's
                // move/resize (the outline only; the main grid itself has no
                // time badge yet — DEVIATIONS.md A15 — so there is nothing
                // extra to mirror here). No protected-window shading exists
                // in this window yet (this file's header), so the outline
                // never turns alert the way `DayColumnView.dropPreview` can.
                if let previewRect = dropPreviewFrame(in: proxy.size.width, geometry: geometry) {
                    dropPreview(previewRect)
                }
            }
            .frame(height: geometry.totalHeight, alignment: .top)
        }
        .frame(height: hourHeight * 24)
    }

    @ViewBuilder
    private func blockView(block: RoutineBlockSnapshot, laidOut: LaidOutBlock, geometry: TimeGeometry) -> some View {
        let start = referenceDayStart.addingTimeInterval(TimeInterval(block.startMinutes * 60))
        let model = GridBlockModel(
            id: block.id,
            title: block.title,
            start: start,
            end: start.addingTimeInterval(block.duration),
            locationName: nil,
            kind: .routineTimed,
            flexibility: block.flexibility,
            // No "now" concept applies to an abstract weekly template, so
            // every block reads as plainly `.scheduled` — none of
            // done/skipped/in-progress make sense without a real date.
            status: .scheduled,
            source: template?.sourceKey ?? .graphite,
            // components.md §13.1: "the routine's own palette slot, one hue
            // for the whole template" — the template's own name stands in for
            // `sourceName` (there is no separate source-catalogue entry for a
            // routine template), so the meta line and hover help read
            // "<Template name>" rather than a per-source name.
            sourceName: template?.name ?? "Routine",
            glyphOverride: nil,
            // task P2-T11: move/resize now reuse §3/§4 unchanged, so a
            // routine block is movable exactly like an ordinary event.
            // `GridBlockView` already draws its hover resize handles once
            // `isMovable` is true — no new chrome needed here.
            isMovable: true)
        let isSelected = selection?.blockID == block.id && selection?.weekday == weekday

        GridBlockView(
            model: model,
            presentation: presentation(for: block, isSelected: isSelected),
            renderedHeight: laidOut.frame.height,
            visibleWidth: laidOut.visibleWidth)
            .frame(width: laidOut.frame.width, height: laidOut.frame.height, alignment: .topLeading)
            .contentShape(Rectangle().inset(by: laidOut.hitInset))
            .offset(x: laidOut.frame.minX, y: laidOut.frame.minY)
            .opacity(drag?.blockID == block.id ? Tokens.Opacity.blockDragOrigin : 1)
            // interactions.md §8 — open-hand cursor for a draggable block.
            .cursor(.openHand)
            .onHover { hovering in
                hoveredID = hovering ? block.id : (hoveredID == block.id ? nil : hoveredID)
            }
            .onTapGesture {
                selection = RoutineBlockSelection(blockID: block.id, weekday: weekday)
            }
            .gesture(blockGesture(block: block, laidOut: laidOut, geometry: geometry))
    }

    /// Plain (non-`@ViewBuilder`) helper, same reason `DayColumnView.presentation(for:laidOut:)`
    /// is one: `if` statements that only mutate a value, not build a view,
    /// cannot live inside a `@ViewBuilder`-attributed function body.
    private func presentation(for block: RoutineBlockSnapshot, isSelected: Bool) -> Presentation {
        var presentation: Presentation = isSelected ? [.selected] : []
        if hoveredID == block.id { presentation.insert(.hovered) }
        if drag?.blockID == block.id { presentation.insert(.dragging) }
        return presentation
    }

    // MARK: Gesture (mirrors DayColumnView.blockGesture's shape)

    private func blockGesture(block: RoutineBlockSnapshot, laidOut: LaidOutBlock, geometry: TimeGeometry) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let handle = Tokens.Size.blockResizeHandleHeight
                let localY = value.startLocation.y - laidOut.frame.minY
                let mode: RoutineDragSession.Mode =
                    localY <= handle ? .resizeTop
                    : localY >= laidOut.frame.height - handle ? .resizeBottom
                    : .move

                let snap = NSEvent.modifierFlags.contains(.control) ? 5 : 15
                let delta = value.translation.height
                let deltaTime = TimeInterval(delta / hourHeight) * 3600
                let blockStart = referenceDayStart.addingTimeInterval(TimeInterval(block.startMinutes * 60))

                if drag == nil {
                    drag = RoutineDragSession(mode: mode, blockID: block.id, origin: blockStart, current: blockStart)
                }
                drag?.current = TimeGeometry.snap(blockStart.addingTimeInterval(deltaTime), toMinutes: snap)
            }
            .onEnded { _ in
                defer { drag = nil }
                guard let session = drag, session.blockID == block.id,
                      let template, let liveBlock = template.blocks.first(where: { $0.id == block.id })
                else { return }

                let currentMinutes = minutes(for: session.current)
                switch session.mode {
                case .move:
                    store.move(liveBlock, toStartMinutes: currentMinutes)
                case .resizeTop:
                    store.resize(liveBlock, newStartMinutes: currentMinutes)
                case .resizeBottom:
                    let deltaMinutes = currentMinutes - minutes(for: session.origin)
                    let oldEndMinutes = liveBlock.startMinutes + Int(liveBlock.duration / 60)
                    store.resize(liveBlock, newEndMinutes: oldEndMinutes + deltaMinutes)
                }
                selection = RoutineBlockSelection(blockID: block.id, weekday: weekday)
            }
    }

    private func minutes(for date: Date) -> Int {
        Int(date.timeIntervalSince(referenceDayStart) / 60)
    }

    // MARK: Drop preview

    private func dropPreviewFrame(in width: CGFloat, geometry: TimeGeometry) -> CGRect? {
        guard let session = drag,
              let block = blocks.first(where: { $0.id == session.blockID })
        else { return nil }
        let inset = Tokens.Spacing.xxs
        let originalStart = referenceDayStart.addingTimeInterval(TimeInterval(block.startMinutes * 60))
        let originalEnd = originalStart.addingTimeInterval(block.duration)

        let start: Date
        let end: Date
        switch session.mode {
        case .resizeTop:
            start = min(session.current, originalEnd.addingTimeInterval(-15 * 60))
            end = originalEnd
        case .resizeBottom:
            start = originalStart
            let delta = session.current.timeIntervalSince(session.origin)
            end = max(originalEnd.addingTimeInterval(delta), start.addingTimeInterval(15 * 60))
        case .move:
            start = session.current
            end = session.current.addingTimeInterval(block.duration)
        }
        return CGRect(
            x: inset, y: geometry.y(for: start),
            width: width - 2 * inset,
            height: max(geometry.height(from: start, to: end), Tokens.Size.blockMinRenderedHeight))
    }

    private func dropPreview(_ rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.block, style: .continuous)
            .strokeBorder(
                Tokens.Color.Interactive.accent,
                style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func overflowChip(_ chip: OverflowChip) -> some View {
        Text("+\(chip.hiddenCount)")
            .typeStyle(.countdownChip)
            .foregroundStyle(Tokens.Color.Text.secondary)
            .padding(.horizontal, Tokens.Spacing.xs)
            .frame(height: 14)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                    .fill(Tokens.Color.Surface.canvasSunken))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .offset(y: chip.anchor.y)
            .padding(.trailing, Tokens.Spacing.xxs)
            .allowsHitTesting(false)
    }
}

// MARK: - Inspector (layouts.md §8.1)

private struct RoutineInspectorView: View {
    let template: RoutineTemplate?
    let selectedBlock: RoutineBlockSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {
                if let selectedBlock {
                    blockDetails(selectedBlock)
                } else if let template {
                    templateSummary(template)
                } else {
                    // No template exists at all (seeding failed or the store
                    // was cleared). A summary sentence, not a placeholder
                    // graphic — the same rule §6/§8.1 give the day/template
                    // empty state.
                    Text("No routine templates yet.")
                        .typeStyle(.inspectorValue)
                        .foregroundStyle(Tokens.Color.Text.secondary)
                }
            }
            .padding(Tokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Color.Surface.inspector)
    }

    // MARK: Selected block

    @ViewBuilder
    private func blockDetails(_ block: RoutineBlockSnapshot) -> some View {
        Text(block.title)
            .typeStyle(.inspectorTitle)
            .foregroundStyle(Tokens.Color.Text.primary)

        field("Start", timeOfDay(block.startMinutes))
        field("Duration", durationText(block.duration))
        // components.md §13.2's interactive three-segment flexibility control
        // (Fixed / Shiftable / Droppable with a rail-style sample and, for
        // `.shiftable`, a ± minutes stepper) is explicitly out of scope for
        // this task. Read-only text stands in for it, per the task's own
        // "your call" — this is the value it reads, not a design decision.
        field("Flexibility", block.flexibility.rawValue.capitalized)
    }

    // MARK: Nothing selected — the template summary (§8.1)

    @ViewBuilder
    private func templateSummary(_ template: RoutineTemplate) -> some View {
        Text(template.name)
            .typeStyle(.inspectorTitle)
            .foregroundStyle(Tokens.Color.Text.primary)

        field("Weekdays", weekdayList(template.activeWeekdays))
        field("Blocks", "\(template.blocks.count)")
        field("Total", String(format: "%.1f h", totalHours(template)))
        // §13.4 — detached-instance count and its Re-sync button belong here
        // too, but there is no main-grid edit-command path yet that can tell
        // an instance apart from an untouched one (RoutineEngine.swift's own
        // header), so the count is always zero. Same zero-state rule this
        // window otherwise follows (§10.2 — "hidden entirely at zero"): the
        // row is omitted, not stubbed at "0 instances edited this week".
    }

    // MARK: Building blocks (mirrors InspectorView.swift's own)

    private func field(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            label(name)
            Text(value)
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.primary)
            Spacer(minLength: 0)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .typeStyle(.inspectorLabel)
            .foregroundStyle(Tokens.Color.Text.secondary)
            .frame(width: 84, alignment: .leading)
    }

    private func timeOfDay(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) min" }
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }

    private func weekdayList(_ weekdays: Set<Int>) -> String {
        guard !weekdays.isEmpty else { return "None" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    /// Hours per *week*, not just the sum of the block set: every block
    /// repeats on every active weekday (`RoutineWeekLayout`'s own header
    /// comment), so the total time this template actually occupies across a
    /// week is `sum(block durations) × active weekday count`. layouts.md §8.1
    /// asks for "total hours" without a formula; this is the one reading that
    /// is consistent with what the rest of the window already shows — a
    /// per-block-set total would silently disagree with what "3 active
    /// weekdays" beside it implies.
    private func totalHours(_ template: RoutineTemplate) -> Double {
        let perOccurrence = template.blocks.reduce(0) { $0 + $1.duration } / 3600
        return perOccurrence * Double(template.activeWeekdays.count)
    }
}
