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
    /// テーマで変えるのは「背景・明るさ・彩度・質感」で、活動ごとの色相はどのテーマでも互いに十分離す
    /// （おおむね 黄〜橙 / 緑 / 青 / 紫 / 赤〜ピンク に散らし、睡眠は暗い藍にして静止の明るい青と明度差で区別する）。
    /// どのテーマでも6色のどの2色も、知覚的な色差（CIE76のΔE）が30以上になるようにしてある（テストで確認）。
    func color(for kind: ActivityKind) -> RingRGB {
        let hex: String
        switch (self, DailyRingLayout.ringKind(for: kind)) {
        case (.standard, _): return DailyRingLayout.ringColor(for: kind)

        // 夜空: 淡く冷たいパステル寄り
        case (.nightSky, .stationary): hex = "#84b0ff"
        case (.nightSky, .sleeping): hex = "#3238a0"
        case (.nightSky, .walking): hex = "#6fe6d2"
        case (.nightSky, .running): hex = "#ff8fb4"
        case (.nightSky, .cycling): hex = "#ffdc8a"
        case (.nightSky, _): hex = "#e2a4ff"

        // オーロラ: 彩度の高いネオン
        case (.aurora, .stationary): hex = "#2fa8ff"
        case (.aurora, .sleeping): hex = "#4a2ab8"
        case (.aurora, .walking): hex = "#3dffa0"
        case (.aurora, .running): hex = "#ff4fd0"
        case (.aurora, .cycling): hex = "#eaff5a"
        case (.aurora, _): hex = "#c08cff"

        // 夏祭り: 提灯のような暖かく濃い色（暖色を広めに使いつつ、青・緑・紫で色相を離す）
        case (.summerFestival, .stationary): hex = "#ff8a3d"
        case (.summerFestival, .sleeping): hex = "#7a1f6b"
        case (.summerFestival, .walking): hex = "#3de0c8"
        case (.summerFestival, .running): hex = "#ff3d6e"
        case (.summerFestival, .cycling): hex = "#ffe14a"
        case (.summerFestival, _): hex = "#6a8dff"

        // 月光: 彩度を抑えた落ち着いた色（色相は離したまま）
        case (.moonlight, .stationary): hex = "#5f8ae8"
        case (.moonlight, .sleeping): hex = "#3a3c78"
        case (.moonlight, .walking): hex = "#7fd6b4"
        case (.moonlight, .running): hex = "#e88fa8"
        case (.moonlight, .cycling): hex = "#e6c27a"
        case (.moonlight, _): hex = "#d8a0f0"
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

extension RingRGB {
    /// CIE L*a*b*（D65）。知覚的な色の違いを測るのに使う。
    var lab: (l: Double, a: Double, b: Double) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let rl = linear(r), gl = linear(g), bl = linear(b)
        let x = (0.4124 * rl + 0.3576 * gl + 0.1805 * bl) / 0.95047
        let y = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
        let z = (0.0193 * rl + 0.1192 * gl + 0.9505 * bl) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? pow(t, 1.0 / 3.0) : 7.787 * t + 16.0 / 116.0 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    /// 知覚的な色差（CIE76のΔE）。30以上なら、並べてはっきり別の色と分かる目安。
    func perceptualDistance(to other: RingRGB) -> Double {
        let p = lab, q = other.lab
        let dl = p.l - q.l, da = p.a - q.a, db = p.b - q.b
        return (dl * dl + da * da + db * db).squareRoot()
    }
}
