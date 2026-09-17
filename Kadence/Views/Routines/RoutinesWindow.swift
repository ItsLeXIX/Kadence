//
//  RoutinesWindow.swift
//  Kadence
//
//  layouts.md §8 / components.md §13.1 — the Routines window shell: template
//  picker, seven weekday-only columns on the same hour-grid geometry as the
//  main Week view, and a minimal read-only inspector.
//
//  Scope, deliberately narrow (task P2-T10 — the first Routines-window slice):
//  read-only rendering of one selected template's blocks. NOT built here, all
//  left for follow-up tasks:
//    - creating, moving, resizing or deleting routine blocks (interactions.md
//      §11.1) — this window has no drag or create surface at all;
//    - the Blocks/Windows mode control and Windows-mode editing
//      (components.md §13.3) — there is no `TimeWindow` model yet;
//    - the flexibility control's interactive stepper (components.md §13.2) —
//      the inspector shows flexibility as read-only text instead;
//    - detached-instance tracking and Re-sync (components.md §13.4,
//      interactions.md §11.2) — always zero right now, so per the existing
//      zero-state rule (§10.2) it is omitted entirely rather than stubbed;
//    - the background windows layer (protected / low-energy shading).
//      components.md §13.1's table says this window reuses "the same
//      background window layer" as the Week canvas, but there is no
//      `TimeWindow` model to drive it yet (windows still only exist as the
//      main calendar's `TimeWindowFixture` mock) and this task's own "what to
//      build" list never asks for it. Left for the task that builds Windows
//      mode, which is what actually needs a window to draw. Noted in
//      DEVIATIONS.md rather than silently matched or silently skipped.
//
//  What IS reused, unchanged: `DayLayoutEngine` (the same overlap-resolution
//  engine the main grid uses), `TimeGeometry`, `HourLinesLayer` /
//  `TimeGutterView` (`GridLayers.swift`) and `GridBlockView`
//  (components.md §13.1: "Anything that looks like a block in this window is
//  a block, and behaves like one"). `DayColumnView`/`TimedCanvasView`
//  themselves are not reused as SwiftUI containers — they are hard-wired to
//  `Event`/`EventStore`/`CalendarState`/drag-and-drop, none of which apply to
//  a read-only `RoutineBlock` canvas — but no grid geometry is
//  re-implemented; every measurement comes from the same engine and tokens.
//

import SwiftUI
import SwiftData

struct RoutinesWindow: View {
    @Query(sort: \RoutineTemplate.name) private var templates: [RoutineTemplate]
    @Environment(\.modelContext) private var context

    @State private var selectedTemplateID: UUID?
    @State private var selection: RoutineBlockSelection?
    @State private var didSeed = false

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
        }
        .toolbar { toolbarContent }
        .frame(
            minWidth: Tokens.Size.routineEditorMinWidth,
            minHeight: Tokens.Size.routineEditorMinHeight)
        .task {
            guard !didSeed else { return }
            didSeed = true
            MockData.seedRoutineTemplatesIfNeeded(context)
        }
        .onChange(of: selectedTemplateID) { _, _ in
            selection = nil
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        VStack(spacing: 0) {
            RoutineWeekdayHeaderRow(weekdays: orderedWeekdays)
            RoutinesCanvasView(
                weekdays: orderedWeekdays,
                template: selectedTemplate,
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
/// background windows (see this file's header) — and no create/drag surface,
/// since this task is read-only (interactions.md §11.1 is a follow-up).
private struct RoutineDayColumnView: View {
    let weekday: Int
    let template: RoutineTemplate?
    let hourHeight: CGFloat
    @Binding var selection: RoutineBlockSelection?

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
                // "clicking empty grid deselects" (interactions.md §6) — the
                // only interaction this read-only column offers besides
                // selecting a block.
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .frame(height: geometry.totalHeight)
                    .accessibilityHidden(true)
                    .onTapGesture { selection = nil }

                ForEach(layout.blocks.sorted(by: { $0.zIndex < $1.zIndex })) { laidOut in
                    if let block = blocks.first(where: { $0.id == laidOut.id }) {
                        blockView(block: block, laidOut: laidOut)
                    }
                }

                ForEach(layout.overflow) { chip in
                    overflowChip(chip)
                }
            }
            .frame(height: geometry.totalHeight, alignment: .top)
        }
        .frame(height: hourHeight * 24)
    }

    @ViewBuilder
    private func blockView(block: RoutineBlockSnapshot, laidOut: LaidOutBlock) -> some View {
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
            // Read-only in this task: interactions.md §11.1 (create/move/
            // resize/delete) is explicitly out of scope.
            isMovable: false)
        let isSelected = selection?.blockID == block.id && selection?.weekday == weekday

        GridBlockView(
            model: model,
            presentation: isSelected ? [.selected] : [],
            renderedHeight: laidOut.frame.height,
            visibleWidth: laidOut.visibleWidth)
            .frame(width: laidOut.frame.width, height: laidOut.frame.height, alignment: .topLeading)
            .contentShape(Rectangle().inset(by: laidOut.hitInset))
            .offset(x: laidOut.frame.minX, y: laidOut.frame.minY)
            .onTapGesture {
                selection = RoutineBlockSelection(blockID: block.id, weekday: weekday)
            }
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
