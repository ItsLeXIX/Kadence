//
//  FlexibilityControl.swift
//  Kadence
//
//  components.md §13.2 (task P2-T42): "a three-segment control in the editor
//  inspector, labelled Fixed / Shiftable / Droppable, each segment showing a
//  3pt rail sample in the segment's leading edge drawn in that rail style —
//  solid, inset, dotted." `.shiftable` reveals the ± stepper: `blockMeta`
//  type, 15-minute steps, range 15–180. Value semantics live in
//  `ShiftRangeRule`; the writes (one named undo step each) in
//  `RoutineBlockStore.setFlexibility` / `setShiftRange`.
//

import SwiftUI
import AppKit

struct FlexibilityControl: View {
    let flexibility: Flexibility
    let shiftableMinutes: Int?
    let onSetFlexibility: (Flexibility) -> Void
    let onSetShiftRange: (Int) -> Void

    @Environment(\.displayScale) private var displayScale

    private static let segments: [(Flexibility, RailStyle, String)] = [
        (.fixed, .solid, "Fixed"),
        (.shiftable, .inset, "Shiftable"),
        (.droppable, .dotted, "Droppable"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            // A real `NSSegmentedControl` (see `RailSegmentedControl`): macOS
            // draws the segments, the selection and the focus ring, so none
            // of those are invented here. SwiftUI's segmented `Picker` was
            // tried first; on macOS it drops a segment's image and shows the
            // title only, which loses the rail sample §13.2 requires.
            RailSegmentedControl(
                segments: Self.segments.map { segment in
                    RailSegmentedControl.Segment(
                        value: segment.0, title: segment.2,
                        image: Self.railSample(segment.1, scale: displayScale))
                },
                selection: flexibility,
                onSelect: onSetFlexibility)
                .fixedSize()
                .accessibilityLabel("Flexibility")

            if flexibility == .shiftable {
                // "A `.shiftable` block with no ± value ... renders the
                // stepper at 30" (§13.2): `displayed` maps nil to 30, and the
                // inspector's repair writes it. `in:` makes the stepper
                // disable its own arrows at 15 and 180, so it never presents
                // a value it would not accept.
                Stepper(
                    value: Binding(
                        get: { ShiftRangeRule.displayed(shiftableMinutes) },
                        set: { onSetShiftRange($0) }),
                    in: ShiftRangeRule.range,
                    step: ShiftRangeRule.step
                ) {
                    // components.md §13.2 (amended 2026-10-05, G-032):
                    // `± 30 min`, `blockMeta`, `text.primary`, monospaced
                    // digits, no label word — the `Shiftable` segment above
                    // is the label.
                    Text(Self.stepperText(shiftableMinutes))
                        .typeStyle(.blockMeta)
                        .foregroundStyle(Tokens.Color.Text.primary)
                        .monospacedDigit()
                }
            }
        }
    }

    /// `± 30 min` — `±`, a space, the number, a space, `min` (§13.2).
    static func stepperText(_ minutes: Int?) -> String {
        "± \(ShiftRangeRule.displayed(minutes)) min"
    }

    /// The rail sample as an image, because a native segmented control can
    /// only draw an image and a title in each segment, not an arbitrary
    /// SwiftUI view. `ImageRenderer` draws `RailView` (the grid's own rail
    /// drawing) offscreen at the display's scale.
    ///
    /// components.md §13.2 (amended 2026-10-05, closes G-032):
    /// - height: the segment title's line height (the system control font),
    ///   so the sample is as tall as the word beside it;
    /// - colour: **none of its own**. It is a TEMPLATE image — AppKit uses
    ///   only its alpha and tints it exactly as it tints the segment's title,
    ///   selected or not, Increase Contrast included. It is drawn in black
    ///   only so the alpha is solid; the black never shows.
    @MainActor
    static func railSample(_ style: RailStyle, scale: CGFloat) -> NSImage {
        let renderer = ImageRenderer(content:
            RailView(style: style, color: .black)
                .frame(width: Tokens.Size.blockRailWidth, height: sampleHeight, alignment: .leading))
        renderer.scale = scale
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// The segment title's line height — see `railSample`.
    static var sampleHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return ceil(font.ascender - font.descender + font.leading)
    }
}

/// `NSSegmentedControl` wrapped for SwiftUI, because it can draw an image
/// at the leading edge of each segment's title (a segment with both an
/// image and a label draws the image first), which is exactly §13.2's "a 3pt rail sample in the
/// segment's leading edge".
///
/// Swift note (from Java/C#): `NSViewRepresentable` is the adapter between
/// SwiftUI and an AppKit view. `makeNSView` builds it once, `updateNSView`
/// pushes new SwiftUI state into it, and the `Coordinator` is the target
/// object AppKit's target/action mechanism calls back on a click.
struct RailSegmentedControl: NSViewRepresentable {
    struct Segment {
        let value: Flexibility
        let title: String
        let image: NSImage
    }

    let segments: [Segment]
    let selection: Flexibility
    let onSelect: (Flexibility) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.trackingMode = .selectOne
        control.segmentCount = segments.count
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.values = segments.map(\.value)
        for (index, segment) in segments.enumerated() {
            control.setLabel(segment.title, forSegment: index)
            control.setImage(segment.image, forSegment: index)
            control.setImageScaling(.scaleNone, forSegment: index)
            control.setWidth(0, forSegment: index)   // 0 = size to content
        }
        control.selectedSegment = segments.firstIndex { $0.value == selection } ?? -1
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: (Flexibility) -> Void
        var values: [Flexibility] = []
        init(onSelect: @escaping (Flexibility) -> Void) { self.onSelect = onSelect }

        @objc func changed(_ sender: NSSegmentedControl) {
            guard values.indices.contains(sender.selectedSegment) else { return }
            onSelect(values[sender.selectedSegment])
        }
    }
}
