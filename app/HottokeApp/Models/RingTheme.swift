import Foundation

/// 「1日の輪」の配色テーマ（種類ごとの色と背景色）。標準のほか、プロモードで切り替えられる。
enum RingTheme: String, CaseIterable, Identifiable {
    case standard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "標準"
        }
    }

    /// 活動の種類ごとの色。
    func color(for kind: ActivityKind) -> RingRGB {
        DailyRingLayout.ringColor(for: kind)
    }
}
