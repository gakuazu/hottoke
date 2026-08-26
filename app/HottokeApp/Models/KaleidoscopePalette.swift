import SwiftUI
import CoreGraphics

/// 色パレット。docs/02-spec.md 3.3節 / docs/03b-visual-prototype-learnings.md 末尾の参考カラーコードをそのまま採用。
struct KaleidoscopePalette: Identifiable, Equatable {
    let id: String
    let name: String
    let hexColors: [String]
    let isLocked: Bool

    var colors: [Color] { hexColors.map { Color(hex: $0) } }

    var cgColors: [CGColor] {
        hexColors.map { hex in
            let (r, g, b) = KaleidoscopePalette.rgbComponents(hex: hex)
            return CGColor(red: r, green: g, blue: b, alpha: 1)
        }
    }

    private static func rgbComponents(hex: String) -> (CGFloat, CGFloat, CGFloat) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        return (r, g, b)
    }

    static let morning = KaleidoscopePalette(
        id: "morning", name: "朝",
        hexColors: ["#ffb199", "#ff8fc0", "#ffdd8a", "#ff6fa6", "#ffe9b8", "#ff7a5c"],
        isLocked: false
    )
    static let daytime = KaleidoscopePalette(
        id: "daytime", name: "昼",
        hexColors: ["#33d0e8", "#ffd23e", "#3f7dff", "#5fe8b0", "#ff5fa6", "#ffffff"],
        isLocked: false
    )
    static let evening = KaleidoscopePalette(
        id: "evening", name: "夕方",
        hexColors: ["#ff6f45", "#e23f9c", "#ff9d2f", "#c23fce", "#ffd166", "#ff3f6b"],
        isLocked: false
    )
    static let night = KaleidoscopePalette(
        id: "night", name: "夜",
        hexColors: ["#7a5cff", "#ff5cd6", "#2fd6c2", "#5c7cff", "#c9a8ff", "#ff8fd6"],
        isLocked: false
    )
    /// v2でサブスク解放予定の追加パレットのプレースホルダー（手動モード画面のロック表示用）。
    static let seasonalLocked = KaleidoscopePalette(
        id: "seasonal-pro", name: "季節限定 (PRO)",
        hexColors: ["#e8e8e8", "#bfbfbf"],
        isLocked: true
    )

    /// 手動モード画面のパレットスウォッチ表示順。無料4種 + ロック済み1種。
    static let all: [KaleidoscopePalette] = [.morning, .daytime, .evening, .night, .seasonalLocked]

    static func forTimeOfDay(_ timeOfDay: TimeOfDay) -> KaleidoscopePalette {
        switch timeOfDay {
        case .morning: return .morning
        case .daytime: return .daytime
        case .evening: return .evening
        case .night: return .night
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
