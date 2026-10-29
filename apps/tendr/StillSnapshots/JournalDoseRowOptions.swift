import SwiftUI
import XCTest
@testable import Still

/// APP-6: Journal → Doses row options A-D, four stacked rows each, from the synthetic screenshot
/// fixture (latest three doses, plus an older dose logged before injection sides existed).
@MainActor
final class JournalDoseRowOptions: XCTestCase {
    func testJournalDoseRowOptions() throws {
        let doses = Array(Store.screenshotJournal().doses.sorted { $0.date > $1.date }.prefix(4))
        var rows = doses
        rows[3].side = nil
        rows[3].note = ""
        let options = [("A", "Leading glass L/R badge"), ("B", "\"Left side · time\" line"), ("C", "Body-side glyph"), ("D", "Trailing Left/Right chip")]
        try ComponentGallery.render("journal-dose-row", width: 390, test: self) {
            for (style, title) in options {
                ComponentGallery.Variant("Option \(style): \(title)") { list(rows, style: style) }
            }
        }
    }

    private func list(_ rows: [DoseEntry], style: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { dose in
                Text(dose.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 16).padding(.top, 6)
                JournalDoseRow(entry: dose, style: style)
                    .padding(.vertical, 8).padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }
}
