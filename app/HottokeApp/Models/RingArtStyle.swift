import Foundation

/// 「1日の輪」の表現スタイル（docs/23-radial-art-concepts.md）。
/// 標準は「従来の点描の山」。スタイルの切り替えはプロ機能（ロック中は標準に固定）。
/// 背景は暗い夜空、活動の色は標準の1セットに固定（配色テーマの選択は廃止）。
enum RingArtStyle: String, CaseIterable, Identifiable {
    /// A+B 花のコロナ: 時間のリングから今日の活動が花びらとして外へ開き、内側に過去6日の花びらが重なる。標準。
    case flowerCorona
    /// A コロナ: 時間のリングが主役で、活動は外へ噴き出すアーチ。
    case corona
    /// B 多重の花: 活動1回を1枚の花びらに。背後に過去日の花びらが重なる。
    case multiFlower
    /// D 週の年輪: 半径=何日前か。外側が今日。
    case yearRings
    /// C オーロラ: 強さの曲線を位相をずらして重ねた光のカーテン。
    case aurora
    /// E 渦巻き: 従来の点描に、外へ行くほど角度をねじる渦をかけたもの。
    case spiral
    /// 従来の点描の山。
    case classic

    var id: String { rawValue }

    static let storageKey = "ringArtStyle"
    static let defaultStyle: RingArtStyle = .classic

    var displayName: String {
        switch self {
        case .flowerCorona: return "花のコロナ"
        case .corona: return "コロナ"
        case .multiFlower: return "多重の花"
        case .yearRings: return "週の年輪"
        case .aurora: return "オーロラ"
        case .spiral: return "渦巻き"
        case .classic: return "従来の点描の山"
        }
    }

    var summary: String {
        switch self {
        case .flowerCorona: return "時間のリングから、その日の活動が花びらとして外へ開きます。花びらの長さ=強さ、幅=続いた時間、色=活動の種類。"
        case .corona: return "時間のリングが主役で、活動は外へ噴き出すアーチになります。"
        case .multiFlower: return "活動1回が1枚の花びら。背後に過去の日の花びらが重なります。"
        case .yearRings: return "半径が「何日前か」。外側が今日、内側へ過去の日が年輪のように並びます。"
        case .aurora: return "強さの曲線を重ねた光のカーテン。壁紙におすすめです。"
        case .spiral: return "従来の点描に渦のねじれを加えた表現です。"
        case .classic: return "これまでの、強さを外側の輪郭にした点描の山です。"
        }
    }

    /// 画像の右下に添える、読み方のひとこと（見出し・補足）。
    var hint: (title: String, detail: String) {
        switch self {
        case .flowerCorona, .corona, .multiFlower: return ("花びら", "長さ = 活動の強さ  ·  幅 = 続いた時間")
        case .yearRings: return ("年輪", "外側が今日  ·  内側ほど過去")
        case .aurora: return ("光のカーテン", "高さ = 活動の強さ")
        case .spiral: return ("渦", "外へ行くほど活発  ·  渦に沿って時刻")
        case .classic: return ("半径 = 活動の強さ", "外へ行くほど活発")
        }
    }

    /// 過去の日を重ねて描く（「普段と比べる」と統合）スタイルか。
    var usesPastDays: Bool {
        switch self {
        case .flowerCorona, .multiFlower, .yearRings: return true
        default: return false
        }
    }

    /// 壁紙のおすすめ。
    var isRecommendedForWallpaper: Bool { self == .aurora }

    /// 1週間・1ヶ月の積算・レポートで実際に使うスタイル。渦巻きは時刻の読み取りが落ちるので、花のコロナにする。
    var forAggregate: RingArtStyle { self == .spiral ? .flowerCorona : self }

    /// 保存された文字列と、プロモードの状態から、実際に使うスタイルを決める（ロック中・不明なら標準）。
    static func effective(rawValue: String, proEnabled: Bool) -> RingArtStyle {
        guard ProAccess.isUnlocked(.artStyles, enabled: proEnabled) else { return defaultStyle }
        return RingArtStyle(rawValue: rawValue) ?? defaultStyle
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
