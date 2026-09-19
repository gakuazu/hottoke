import Foundation
import CoreGraphics

// 「1日の輪」（docs/22-app1-radial-redesign.md「表現方式の変更」）の、描画から切り離した純粋な計算ロジック。
// FlowingDataの「Cycle of Many」型の点描リング。
//
// 読み方:
//   周方向 = 24時間（0時が真上、時計回り、1周で1日。今日の途中でも常に0〜24時 = 0〜360度）
//   半径   = 活動の種類ごとに決まった輪（同心円の帯）。外側から 静止 → 車移動 → 自転車 → 歩行 → 走行
//   点の数 = その時刻にその活動をしていた分数に比例（歩行・走行は歩数も反映）
//   色     = 活動の種類ごとに固定
//
// 密度は時間方向にスライド平均（三角形の重み）して、隣り合う時刻で急に変わらないようにする。

/// 色（0...1）。
struct RingRGB: Equatable {
    var r: Double
    var g: Double
    var b: Double
}

/// 輪の帯（最大半径を1とした割合）。
struct RingBand: Equatable {
    let inner: Double
    let outer: Double
}

/// 描く点1つ。
struct RingDot: Equatable {
    /// 時刻（0...24時）。角度に変換して使う。
    let hour: Double
    /// 中心からの距離（最大半径を1とした割合）。その活動の帯の中に収まる。
    let radius: Double
    let kind: ActivityKind
    /// 大きさのばらつき（0.75〜1.25倍）。
    let size: Double
    /// 明るさのばらつき（0.45〜1.0）。
    let brightness: Double
}

enum DailyRingLayout {

    // MARK: - 定数

    static let hoursPerDay: Double = 24
    /// 点の数を数える時間スライスの長さ（分）。
    static let sliceMinutes: Double = 5
    static let sliceHours: Double = sliceMinutes / 60
    static let slicesPerDay: Int = 288
    /// 密度をなめらかにする幅。前後4スライス（20分）まで三角形の重みで混ぜる。
    static let smoothingHalfWidthSlices: Int = 4
    /// 点の半径（最大半径を1とした割合）。1080px画像で約1.9px。
    static let dotRadiusFraction: Double = 0.0045
    /// 密度1（その時間ずっとその活動）のとき、帯をどれだけ点で埋めるか（1で面積いっぱい。重なりで光の帯になる）。
    static let packingFill: Double = 1.1

    /// 輪の順序（外側 → 内側）。
    static let ringOrder: [ActivityKind] = [.stationary, .automotive, .cycling, .walking, .running]

    /// 歩数を加味する係数の下限（歩数が少ない歩行・走行でも、この割合の濃さは出す）。
    static let minimumStepFactor: Double = 0.6
    /// 歩行1分あたりの標準的な歩数（歩数が多いほど濃くするための基準）。
    static let referenceStepsPerMinute: Double = 100
    /// 活動区間が検出できなくても、その時間に歩数がこれ以上あれば「歩行」の点を出す。
    static let walkingFallbackSteps: Int = 300
    /// 上記の場合に、歩数が何歩で密度1になるか。
    static let walkingFallbackFullSteps: Double = 3000

    // MARK: - 輪の配置と色

    /// 静止だけ広い帯にして、長い時間（睡眠など）が背景として面で見えるようにする。中心は空ける。
    static func band(for kind: ActivityKind) -> RingBand {
        switch ringKind(for: kind) {
        case .stationary: return RingBand(inner: 0.80, outer: 1.00)
        case .automotive: return RingBand(inner: 0.66, outer: 0.78)
        case .cycling: return RingBand(inner: 0.52, outer: 0.64)
        case .walking: return RingBand(inner: 0.32, outer: 0.50)
        default: return RingBand(inner: 0.18, outer: 0.30) // running
        }
    }

    /// 活動ごとの色（暗い背景で光って見える色。輪同士が見分けやすいように離した）。
    static func ringColor(for kind: ActivityKind) -> RingRGB {
        switch ringKind(for: kind) {
        case .stationary: return rgb(hex: "#6f86ff") // 青
        case .automotive: return rgb(hex: "#c08cff") // 紫
        case .cycling: return rgb(hex: "#ffb43e")    // 琥珀
        case .walking: return rgb(hex: "#4fe8b0")    // ミント
        default: return rgb(hex: "#ff5f8a")          // 走行: ピンク赤
        }
    }

    /// 輪として扱う種別（不明は静止に含める）。
    static func ringKind(for kind: ActivityKind) -> ActivityKind {
        kind == .unknown ? .stationary : kind
    }

    static func rgb(hex: String) -> RingRGB {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        return RingRGB(
            r: Double((value & 0xFF0000) >> 16) / 255.0,
            g: Double((value & 0x00FF00) >> 8) / 255.0,
            b: Double(value & 0x0000FF) / 255.0
        )
    }

    // MARK: - 角度（0時が真上、時計回り）

    static func angleRadians(forHour hour: Double) -> Double {
        hour / hoursPerDay * 2 * Double.pi
    }

    static func angleDegrees(forHour hour: Double) -> Double {
        hour / hoursPerDay * 360
    }

    /// 画面座標（右が+x、下が+y）での単位方向ベクトル。
    /// 0時=真上(0,-1)、6時=右(1,0)、12時=真下(0,1)、18時=左(-1,0)。
    static func unitVector(forHour hour: Double) -> (dx: Double, dy: Double) {
        let a = angleRadians(forHour: hour)
        return (sin(a), -cos(a))
    }

    // MARK: - 描画範囲

    /// 描く時間の長さ（時間）。今日は0時から現在時刻まで、過去日は24、未来日は0。
    /// 角度のスケールは常に24時間=360度で固定（現在時刻までを引き伸ばさない）。
    static func drawnHours(forDayStarting dayStart: Date, now: Date, calendar: Calendar = .current) -> Double {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: dayStart)
        if day > today { return 0 }
        if day < today { return hoursPerDay }
        let hours = now.timeIntervalSince(day) / 3600
        return min(hoursPerDay, max(0, hours))
    }

    /// 描く範囲の角度（度）。
    static func sweepDegrees(forDrawnHours drawn: Double) -> Double {
        angleDegrees(forHour: min(hoursPerDay, max(0, drawn)))
    }

    // MARK: - 点の数

    /// 密度1（そのスライドの間ずっとその活動）のときに、1スライス・1つの輪に置く点の数。
    /// 帯の面積（幅×スライスの角度）÷ 点1つの面積 × 詰め具合。内側の輪ほど狭いので点は少ない。
    static func dotCapacityPerSlice(for kind: ActivityKind) -> Double {
        let ringBand = band(for: kind)
        let sliceAngle = 2 * Double.pi * sliceHours / hoursPerDay
        let area = 0.5 * (ringBand.outer * ringBand.outer - ringBand.inner * ringBand.inner) * sliceAngle
        let dotArea = Double.pi * dotRadiusFraction * dotRadiusFraction
        return packingFill * area / dotArea
    }

    // MARK: - 集計（時間スライスごとの密度）

    /// 各活動区間のうち [start, end) と重なる秒数を種別ごとに合計する（不明は静止に含める）。
    static func secondsByKind(segments: [ActivitySegment], from start: Date, to end: Date) -> [ActivityKind: TimeInterval] {
        var result: [ActivityKind: TimeInterval] = [:]
        for segment in segments {
            let overlap = min(segment.end, end).timeIntervalSince(max(segment.start, start))
            if overlap > 0 {
                result[ringKind(for: segment.kind), default: 0] += overlap
            }
        }
        return result
    }

    /// 三角形の重みで前後の値を混ぜる（なめらかにする）。
    /// periodic=trueなら0時側と24時側をつなぐ。falseなら端は存在する範囲だけで平均する。
    static func smooth(_ values: [Double], periodic: Bool, halfWidth: Int = DailyRingLayout.smoothingHalfWidthSlices) -> [Double] {
        let n = values.count
        guard n > 0, halfWidth > 0 else { return values }
        var result = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var sum = 0.0, weightSum = 0.0
            for j in -halfWidth...halfWidth {
                var idx = i + j
                if periodic {
                    idx = ((idx % n) + n) % n
                } else if idx < 0 || idx >= n {
                    continue
                }
                let w = Double(halfWidth + 1 - abs(j))
                sum += values[idx] * w
                weightSum += w
            }
            result[i] = weightSum > 0 ? sum / weightSum : 0
        }
        return result
    }

    static func makeDensity(data: DailyActivityData, now: Date, calendar: Calendar = .current) -> DailyRingDensity {
        let dayStart = calendar.startOfDay(for: data.date)
        let drawn = drawnHours(forDayStarting: dayStart, now: now, calendar: calendar)
        let sliceCount = min(slicesPerDay, max(0, Int(ceil(drawn / sliceHours - 1e-9))))

        // 1時間ごとの補正: 歩行・走行の歩数の多さ（濃さ）と、活動区間の検出漏れ時の歩行の補い。
        var stepFactor = [Double](repeating: 1, count: 24)
        var walkingFallback = [Double](repeating: 0, count: 24)
        for hour in 0..<24 {
            let hourStart = dayStart.addingTimeInterval(Double(hour) * 3600)
            let seconds = secondsByKind(segments: data.segments, from: hourStart, to: hourStart.addingTimeInterval(3600))
            let movingMinutes = ((seconds[.walking] ?? 0) + (seconds[.running] ?? 0)) / 60
            let steps = hour < data.hourlySteps.count ? max(0, data.hourlySteps[hour]) : 0
            if movingMinutes >= 1 {
                let ratio = Double(steps) / (movingMinutes * referenceStepsPerMinute)
                stepFactor[hour] = minimumStepFactor + (1 - minimumStepFactor) * min(1, ratio)
            }
            if movingMinutes < 5 && steps >= walkingFallbackSteps {
                walkingFallback[hour] = min(1, Double(steps) / walkingFallbackFullSteps)
            }
        }

        var raw: [ActivityKind: [Double]] = [:]
        for kind in ringOrder { raw[kind] = [Double](repeating: 0, count: sliceCount) }

        for i in 0..<sliceCount {
            let t0 = Double(i) * sliceHours
            let t1 = min(drawn, t0 + sliceHours)
            let coveredSeconds = (t1 - t0) * 3600
            guard coveredSeconds > 1 else { continue }
            let start = dayStart.addingTimeInterval(t0 * 3600)
            let end = dayStart.addingTimeInterval(t1 * 3600)
            let seconds = secondsByKind(segments: data.segments, from: start, to: end)
            let hour = min(23, Int((t0 + t1) / 2))
            for kind in ringOrder {
                var density = min(1, (seconds[kind] ?? 0) / coveredSeconds)
                if kind == .walking || kind == .running {
                    density *= stepFactor[hour]
                }
                if kind == .walking {
                    density = max(density, walkingFallback[hour])
                }
                raw[kind]?[i] = density
            }
        }

        let periodic = sliceCount == slicesPerDay
        var smoothed: [ActivityKind: [Double]] = [:]
        for kind in ringOrder {
            smoothed[kind] = smooth(raw[kind] ?? [], periodic: periodic)
        }
        return DailyRingDensity(drawnHours: drawn, sliceCount: sliceCount, raw: raw, smoothed: smoothed)
    }

    // MARK: - 点の配置

    /// 点の配置を作る。同じ密度・同じseedなら毎回まったく同じ配置になる。
    /// 点の数 = 密度 × 帯の容量（小数部分は乱数で切り上げ・切り捨てして、平均が正確に密度に比例するようにする）。
    /// 角度は時間スライスの中でばらつかせ、半径は帯の中で面積が均等になるようにばらつかせる。
    static func makeDots(density: DailyRingDensity, seed: UInt64) -> [RingDot] {
        var generator = SeededGenerator(seed: seed &* 0x9E3779B97F4A7C15 &+ 0x1234567)
        var dots: [RingDot] = []
        for kind in ringOrder {
            guard let values = density.smoothed[kind] else { continue }
            let ringBand = band(for: kind)
            let capacity = dotCapacityPerSlice(for: kind)
            let innerSq = ringBand.inner * ringBand.inner
            let outerSq = ringBand.outer * ringBand.outer
            for i in 0..<values.count {
                let t0 = Double(i) * sliceHours
                let t1 = min(density.drawnHours, t0 + sliceHours)
                guard t1 > t0 else { continue }
                let expected = values[i] * capacity * (t1 - t0) / sliceHours
                var count = Int(expected.rounded(.down))
                let fraction = expected - Double(count)
                if Double.random(in: 0..<1, using: &generator) < fraction { count += 1 }
                for _ in 0..<count {
                    let hour = t0 + Double.random(in: 0..<1, using: &generator) * (t1 - t0)
                    let u = Double.random(in: 0..<1, using: &generator)
                    let radius = (innerSq + (outerSq - innerSq) * u).squareRoot()
                    let size = 0.75 + 0.5 * Double.random(in: 0..<1, using: &generator)
                    let brightness = 0.45 + 0.55 * Double.random(in: 0..<1, using: &generator)
                    dots.append(RingDot(hour: hour, radius: radius, kind: kind, size: size, brightness: brightness))
                }
            }
        }
        return dots
    }
}

/// その日の時間スライスごとの活動密度（0...1）。
struct DailyRingDensity {
    /// 描く時間の長さ（時間）。今日は現在時刻まで、過去日は24。
    let drawnHours: Double
    let sliceCount: Int
    /// 平均する前の密度（その5分のうちその活動だった割合。歩行・走行は歩数で補正）。
    let raw: [ActivityKind: [Double]]
    /// 時間方向になめらかにした密度。点の数はこちらから決める。
    let smoothed: [ActivityKind: [Double]]

    /// 24時間すべてを描くか（過去日）。trueなら0時側と24時側をなめらかにつなぐ。
    var isPeriodic: Bool { sliceCount == DailyRingLayout.slicesPerDay }
    /// 今日の途中（現在時刻までだけ描く）か。
    var isPartialDay: Bool { drawnHours < DailyRingLayout.hoursPerDay - 1e-9 }

    /// 1つの輪の、点の期待数の合計。
    func expectedDotCount(for kind: ActivityKind) -> Double {
        guard let values = smoothed[kind] else { return 0 }
        let capacity = DailyRingLayout.dotCapacityPerSlice(for: kind)
        var total = 0.0
        for i in 0..<values.count {
            let t0 = Double(i) * DailyRingLayout.sliceHours
            let t1 = min(drawnHours, t0 + DailyRingLayout.sliceHours)
            total += values[i] * capacity * max(0, t1 - t0) / DailyRingLayout.sliceHours
        }
        return total
    }
}
