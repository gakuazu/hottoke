import Foundation

/// 背景の色（暗い色）。
struct RingBackground: Equatable {
    /// 画面の外側の色
    var base: RingRGB
    /// 中心付近のわずかに明るい色
    var center: RingRGB
    /// 左下・右上にほんのりにじむ星雲の色
    var nebulaA: RingRGB
    var nebulaB: RingRGB
    /// 星屑の色味
    var star: RingRGB
}

/// 「1日の輪」の配色テーマ（種類ごとの色と背景色）。標準のほか、プロモードで切り替えられる。
enum RingTheme: String, CaseIterable, Identifiable {
    case standard
    case nightSky
    case aurora
    case summerFestival
    case moonlight

    var id: String { rawValue }

    /// 設定を保存するキー（@AppStorageで使う）。
    static let storageKey = "ringTheme"

    var displayName: String {
        switch self {
        case .standard: return "標準"
        case .nightSky: return "夜空"
        case .aurora: return "オーロラ"
        case .summerFestival: return "夏祭り"
        case .moonlight: return "月光"
        }
    }

    /// 保存された文字列と、プロモードの状態から、実際に使うテーマを決める（ロック中は標準）。
    static func effective(rawValue: String, proEnabled: Bool) -> RingTheme {
        let theme = RingTheme(rawValue: rawValue) ?? .standard
        return ProAccess.isUnlocked(.colorThemes, enabled: proEnabled) ? theme : .standard
    }

    /// 活動の種類ごとの色。
    func color(for kind: ActivityKind) -> RingRGB {
        let hex: String
        switch (self, DailyRingLayout.ringKind(for: kind)) {
        case (.standard, _): return DailyRingLayout.ringColor(for: kind)

        case (.nightSky, .stationary): hex = "#7a9cff"
        case (.nightSky, .sleeping): hex = "#3346b8"
        case (.nightSky, .walking): hex = "#9fe3ff"
        case (.nightSky, .running): hex = "#ffe08a"
        case (.nightSky, .cycling): hex = "#c9b6ff"
        case (.nightSky, _): hex = "#e6eeff"

        case (.aurora, .stationary): hex = "#3aa6ff"
        case (.aurora, .sleeping): hex = "#4a34b8"
        case (.aurora, .walking): hex = "#3dffb0"
        case (.aurora, .running): hex = "#ff6fd8"
        case (.aurora, .cycling): hex = "#eaff7a"
        case (.aurora, _): hex = "#a878ff"

        case (.summerFestival, .stationary): hex = "#ff8a5c"
        case (.summerFestival, .sleeping): hex = "#9a2f78"
        case (.summerFestival, .walking): hex = "#ffd24a"
        case (.summerFestival, .running): hex = "#ff4f6a"
        case (.summerFestival, .cycling): hex = "#ffa02e"
        case (.summerFestival, _): hex = "#5fd8ff"

        case (.moonlight, .stationary): hex = "#9aa6d0"
        case (.moonlight, .sleeping): hex = "#525c88"
        case (.moonlight, .walking): hex = "#eef0ff"
        case (.moonlight, .running): hex = "#ffe7b0"
        case (.moonlight, .cycling): hex = "#b9c6ec"
        case (.moonlight, _): hex = "#7d86ad"
        }
        return DailyRingLayout.rgb(hex: hex)
    }

    var background: RingBackground {
        func c(_ r: Double, _ g: Double, _ b: Double) -> RingRGB { RingRGB(r: r, g: g, b: b) }
        switch self {
        case .standard:
            return RingBackground(base: c(0.010, 0.012, 0.034), center: c(0.055, 0.06, 0.16), nebulaA: c(0.35, 0.20, 0.75), nebulaB: c(0.10, 0.45, 0.60), star: c(0.9, 0.92, 1.0))
        case .nightSky:
            return RingBackground(base: c(0.004, 0.008, 0.030), center: c(0.020, 0.050, 0.140), nebulaA: c(0.10, 0.25, 0.60), nebulaB: c(0.30, 0.20, 0.55), star: c(0.85, 0.92, 1.0))
        case .aurora:
            return RingBackground(base: c(0.004, 0.016, 0.026), center: c(0.020, 0.095, 0.115), nebulaA: c(0.10, 0.70, 0.50), nebulaB: c(0.50, 0.20, 0.80), star: c(0.85, 1.0, 0.95))
        case .summerFestival:
            return RingBackground(base: c(0.026, 0.008, 0.016), center: c(0.130, 0.035, 0.070), nebulaA: c(0.80, 0.30, 0.10), nebulaB: c(0.70, 0.10, 0.40), star: c(1.0, 0.92, 0.80))
        case .moonlight:
            return RingBackground(base: c(0.012, 0.012, 0.020), center: c(0.070, 0.070, 0.105), nebulaA: c(0.45, 0.48, 0.60), nebulaB: c(0.35, 0.38, 0.52), star: c(0.95, 0.95, 1.0))
        }
    }

    /// 「普段」の形を重ねるときの、淡い点の色（灰青）。
    var ghostColor: RingRGB {
        switch self {
        case .summerFestival: return RingRGB(r: 0.78, g: 0.70, b: 0.66)
        default: return RingRGB(r: 0.62, g: 0.72, b: 0.90)
        }
    }
}
