/// Layout depends only on the current window's traits, including during live resize.
/// Kept independent of SwiftUI so the complete trait matrix is testable on Linux.
struct TendrLayout: Equatable {
    enum SizeClass: Equatable { case compact, regular }
    enum Navigation: Equatable { case tabs, sidebar }

    let horizontal: SizeClass?
    let vertical: SizeClass?

    var navigation: Navigation { horizontal == .regular ? .sidebar : .tabs }
    var maximumContentWidth: Double? { horizontal == .regular ? 760 : nil }
    var weightChartHeight: Double {
        vertical == .compact ? 180 : horizontal == .regular ? 300 : 220
    }
}
