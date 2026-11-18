import SwiftUI
import BarcodeFrames

/// One cell per output frame: what the edit promised vs what the file shows.
public struct FrameCell: Identifiable, Equatable {
    public let id: Int
    public let expected: Int
    public let actual: Int?
    public let segment: Int
    public var ok: Bool { actual == expected }
}

/// View model for the inspector. Pure, so XCTest covers it without a window.
public struct FrameStripModel {
    public let cells: [FrameCell]

    public init(plan: EditPlan, decoded: [DecodedFrame]) {
        let want = plan.expectedSourceFrames()
        var seg: [Int] = []
        for (i, s) in plan.segments.enumerated() { seg += Array(repeating: i, count: s.outputLength) }
        cells = want.indices.map { k in
            FrameCell(id: k, expected: want[k], actual: k < decoded.count ? decoded[k].id : nil, segment: seg[k])
        }
    }

    public var mismatches: [FrameCell] { cells.filter { !$0.ok } }
    public var summary: String {
        mismatches.isEmpty ? "\(cells.count) frames, all exact"
            : "\(mismatches.count) of \(cells.count) frames wrong, first at output frame \(mismatches[0].id)"
    }
}

/// A scrollable strip of the timeline, one tile per frame, mismatches in red.
public struct FrameStripView: View {
    let model: FrameStripModel
    @State private var selected: FrameCell?

    public init(model: FrameStripModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.summary).font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 1) {
                    ForEach(model.cells) { cell in
                        Rectangle()
                            .fill(cell.ok ? tint(cell.segment) : Color.red)
                            .frame(width: 4, height: cell.ok ? 32 : 48)
                            .onTapGesture { selected = cell }
                    }
                }
            }
            if let c = selected {
                Text("output frame \(c.id): expected source \(c.expected), shows \(c.actual.map(String.init) ?? "unreadable")")
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding()
    }

    func tint(_ segment: Int) -> Color { [Color.blue, .green, .orange, .purple][segment % 4] }
}
