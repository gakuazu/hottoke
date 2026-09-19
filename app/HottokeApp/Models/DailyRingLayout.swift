import Foundation
import CoreGraphics

// 「1日の輪」（docs/22-app1-radial-redesign.md）の、描画から切り離した純粋な計算ロジック。
//
// 読み方:
//   周方向 = 24時間（0時が真上、時計回り、1周で1日。今日の途中でも常に0〜24時 = 0〜360度）
//   半径   = その時間帯の活動量（1時間ごとの歩数。歩数が出ない自転車・車移動は継続時間で歩数換算）
//   形     = 活動の種類（ActivityKind → PatternStyle）
//   色     = 時間帯の既存パレットを時刻に沿って連続的に変化させる
//
// 連続性（オーナー指示）:
//   ・半径は1時間ごとの値を「単調3次エルミート補間」でなめらかにつなぐ（段差なし・行き過ぎなし）
//   ・活動種別は境目の前後をクロスフェード（重みが滑らかに入れ替わる）
//   ・色は時刻に対して連続（0時と24時も同じ色）

/// 色（0...1）。描画側でUIColorやCGColorに変換する。
struct RingRGB: Equatable {
    var r: Double
    var g: Double
    var b: Double
}

/// 半径カーブの制御点（時刻t[時]、半径の割合v[0...1]）。
struct RingControlPoint: Equatable {
    let t: Double
    let v: Double
}

/// 1時間ぶんの集計結果。
struct HourSlot: Equatable {
    let hour: Int
    /// この1時間のうち描く対象になる割合（0...1）。今日の現在時刻を含む時間だけ1未満になる。
    let coverage: Double
    let steps: Int
    let secondsByKind: [ActivityKind: TimeInterval]
    let kind: ActivityKind
    /// 半径を決める「歩数換算の活動量」。
    let effectiveSteps: Double
    let radiusFraction: Double
}

enum DailyRingLayout {

    // MARK: - 定数

    static let hoursPerDay: Double = 24
    /// 静かな時間帯でも「空白」にならないための最小半径（最大半径を1とした割合）。
    static let minRadiusFraction: Double = 0.16
    /// 半径の飽和の速さ。1 - exp(-歩数/1800)。1800歩で約63%、3000歩で約81%、5000歩で約94%。
    static let stepsScale: Double = 1800
    /// 自転車は1分あたり何歩ぶんの活動量とみなすか（歩数計にほとんど出ないため）。
    static let cyclingStepsPerMinute: Double = 90
    /// 車移動は自分の運動量ではないので、歩行より小さめ（1分あたり30歩相当）。
    static let automotiveStepsPerMinute: Double = 30
    /// 活動種別の境目でクロスフェードする幅（時間）。境目の前後15分ずつ。
    static let blendWidthHours: Double = 0.5
    /// 「移動系の活動があった時間」とみなす最低秒数（5分）。
    static let minimumMovingSeconds: TimeInterval = 300
    /// 活動区間が検出できなくても、歩数がこれ以上あれば「歩行」とみなす。
    static let walkingFallbackSteps: Int = 300
    /// 現在時刻を含む時間が短すぎるとき（この割合未満）は、その時間の歩数を半径の制御点に使わない。
    static let minimumPartialCoverage: Double = 0.1

    /// 画像内に薄い目盛りの円として描く歩数（1時間あたり）。
    static let guideStepsMarks: [Int] = [500, 1500, 3000]

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

    // MARK: - 半径

    /// 歩数換算の活動量 → 半径の割合（最小半径〜1未満）。単調増加、0でも最小半径を持つ。
    static func radiusFraction(forEffectiveSteps steps: Double) -> Double {
        let s = max(0, steps)
        return minRadiusFraction + (1 - minRadiusFraction) * (1 - exp(-s / stepsScale))
    }

    /// その時間の活動量（歩数換算）。歩数が出ない自転車・車移動は継続時間で補う（歩数と大きいほうを採用）。
    static func effectiveSteps(steps: Int, secondsByKind: [ActivityKind: TimeInterval]) -> Double {
        let cyclingEq = (secondsByKind[.cycling] ?? 0) / 60 * cyclingStepsPerMinute
        let automotiveEq = (secondsByKind[.automotive] ?? 0) / 60 * automotiveStepsPerMinute
        return max(Double(max(0, steps)), cyclingEq, automotiveEq)
    }

    // MARK: - 活動種別

    /// その1時間を代表する活動種別。
    /// 移動系（走行/自転車/車移動/歩行）のうち最長のものが5分以上あればそれを採用。
    /// なければ歩数が300歩以上で「歩行」（活動区間の検出漏れ対策。DailyActivityData.dominantMovingKindと同じ考え方）。
    /// それ以外は「静止」。
    static func dominantKind(secondsByKind: [ActivityKind: TimeInterval], steps: Int) -> ActivityKind {
        let movingPriority: [ActivityKind] = [.running, .cycling, .automotive, .walking]
        var best: ActivityKind?
        var bestSeconds: TimeInterval = 0
        for kind in movingPriority {
            let seconds = secondsByKind[kind] ?? 0
            if seconds > bestSeconds {
                best = kind
                bestSeconds = seconds
            }
        }
        if let best, bestSeconds >= minimumMovingSeconds { return best }
        if steps >= walkingFallbackSteps { return .walking }
        return .stationary
    }

    /// 活動種別 → 「形」（既存の数学模様）。PatternStyle.style(for:)を出発点に、
    /// 輪の上で見分けやすいよう車移動だけ「波」から「リサージュ」に変更
    /// （静止と車移動がどちらも波になって区別できなかったため）。
    static func patternStyle(for kind: ActivityKind) -> PatternStyle {
        switch kind {
        case .stationary, .unknown: return .waves
        case .walking: return .tiling
        case .running: return .fractal
        case .cycling: return .spirograph
        case .automotive: return .lissajous
        }
    }

    // MARK: - 集計

    /// 各活動区間のうち [start, end) と重なる秒数を種別ごとに合計する。
    static func secondsByKind(segments: [ActivitySegment], from start: Date, to end: Date) -> [ActivityKind: TimeInterval] {
        var result: [ActivityKind: TimeInterval] = [:]
        for segment in segments {
            let overlap = min(segment.end, end).timeIntervalSince(max(segment.start, start))
            if overlap > 0 {
                result[segment.kind, default: 0] += overlap
            }
        }
        return result
    }

    /// 描く対象の時間ごとの集計（0時から。今日なら現在時刻を含む時間まで）。
    static func makeSlots(data: DailyActivityData, now: Date, calendar: Calendar = .current) -> [HourSlot] {
        let dayStart = calendar.startOfDay(for: data.date)
        let drawn = drawnHours(forDayStarting: dayStart, now: now, calendar: calendar)
        let count = min(24, max(0, Int(ceil(drawn - 1e-9))))
        var slots: [HourSlot] = []
        for hour in 0..<count {
            let coverage = min(1, drawn - Double(hour))
            guard coverage > 0.001,
                  let hourStart = calendar.date(byAdding: .hour, value: hour, to: dayStart),
                  let hourEnd = calendar.date(byAdding: .hour, value: hour + 1, to: dayStart) else { continue }
            let seconds = secondsByKind(segments: data.segments, from: hourStart, to: hourEnd)
            let steps = hour < data.hourlySteps.count ? max(0, data.hourlySteps[hour]) : 0
            let kind = dominantKind(secondsByKind: seconds, steps: steps)
            let effective = effectiveSteps(steps: steps, secondsByKind: seconds)
            slots.append(HourSlot(
                hour: hour,
                coverage: coverage,
                steps: steps,
                secondsByKind: seconds,
                kind: kind,
                effectiveSteps: effective,
                radiusFraction: radiusFraction(forEffectiveSteps: effective)
            ))
        }
        return slots
    }

    static func makeProfile(data: DailyActivityData, now: Date, calendar: Calendar = .current) -> DailyRingProfile {
        let dayStart = calendar.startOfDay(for: data.date)
        let drawn = drawnHours(forDayStarting: dayStart, now: now, calendar: calendar)
        return DailyRingProfile(slots: makeSlots(data: data, now: now, calendar: calendar), drawnHours: drawn)
    }

    // MARK: - 色（時刻に沿って連続変化）

    /// 時刻→色の制御点。既存の時間帯パレット（KaleidoscopePalette）の色を、空の色の移り変わりに
    /// 沿って並べたもの。最後（24時）は最初（0時）と同じ色にして、一周がつながるようにする。
    /// 括弧内はパレットの何番目の色か。
    private static let colorStopSpecs: [(hour: Double, hex: String)] = [
        (0, KaleidoscopePalette.night.hexColors[3]),     // 夜[3] 青
        (3, KaleidoscopePalette.night.hexColors[0]),     // 夜[0] 紫
        (6, KaleidoscopePalette.morning.hexColors[1]),   // 朝[1] ピンク
        (9, KaleidoscopePalette.morning.hexColors[2]),   // 朝[2] 淡い黄
        (12, KaleidoscopePalette.daytime.hexColors[0]),  // 昼[0] シアン
        (13.5, KaleidoscopePalette.daytime.hexColors[3]),// 昼[3] ミント
        (15, KaleidoscopePalette.daytime.hexColors[1]),  // 昼[1] 黄
        (17, KaleidoscopePalette.evening.hexColors[2]),  // 夕方[2] オレンジ
        (18.5, KaleidoscopePalette.evening.hexColors[1]),// 夕方[1] マゼンタ
        (21, KaleidoscopePalette.night.hexColors[0]),    // 夜[0] 紫
        (24, KaleidoscopePalette.night.hexColors[3])     // 0時と同じ
    ]

    static let colorStops: [(hour: Double, color: RingRGB)] = colorStopSpecs.map { (hour: $0.hour, color: DailyRingLayout.rgb(hex: $0.hex)) }

    /// 指定時刻（時。24以上・負でも一周で折り返す）の色。区間の中はなめらかに補間する。
    static func color(atHour hour: Double) -> RingRGB {
        var t = hour.truncatingRemainder(dividingBy: hoursPerDay)
        if t < 0 { t += hoursPerDay }
        let stops = colorStops
        for i in 0..<(stops.count - 1) {
            let a = stops[i], b = stops[i + 1]
            if t >= a.hour && t <= b.hour {
                let span = b.hour - a.hour
                let u = span > 0 ? (t - a.hour) / span : 0
                let s = u * u * (3 - 2 * u)
                return RingRGB(
                    r: a.color.r + (b.color.r - a.color.r) * s,
                    g: a.color.g + (b.color.g - a.color.g) * s,
                    b: a.color.b + (b.color.b - a.color.b) * s
                )
            }
        }
        return stops[0].color
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

    // MARK: - 補間の共通関数

    static func smoothstep(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }
}

/// その日の輪の形（半径カーブ・活動種別の重み）。時刻tは0...24の連続値。
struct DailyRingProfile {
    let slots: [HourSlot]
    let drawnHours: Double
    let slotKinds: [ActivityKind]
    let controlPoints: [RingControlPoint]

    /// 24時間すべてを描くか（過去日）。trueなら0時側と24時側をなめらかにつなぐ。
    var isPeriodic: Bool { drawnHours >= DailyRingLayout.hoursPerDay - 1e-9 && controlPoints.count == 24 }
    /// 今日の途中（現在時刻までだけ描く）か。
    var isPartialDay: Bool { drawnHours < DailyRingLayout.hoursPerDay - 1e-9 }
    var usedKinds: [ActivityKind] {
        var seen: [ActivityKind] = []
        for kind in slotKinds where !seen.contains(kind) { seen.append(kind) }
        return seen
    }

    init(slots: [HourSlot], drawnHours: Double) {
        self.slots = slots
        self.drawnHours = drawnHours
        self.slotKinds = slots.map { $0.kind }
        var points: [RingControlPoint] = []
        for slot in slots {
            if slot.coverage >= 0.999 {
                // 1時間まるごと: その時間の真ん中に制御点
                points.append(RingControlPoint(t: Double(slot.hour) + 0.5, v: slot.radiusFraction))
            } else if slot.coverage >= DailyRingLayout.minimumPartialCoverage {
                // 現在時刻を含む途中の時間: 経過した部分の真ん中に制御点（先の時刻まで盛り上がって見せない）
                points.append(RingControlPoint(t: Double(slot.hour) + slot.coverage / 2, v: slot.radiusFraction))
            }
        }
        self.controlPoints = points
    }

    // MARK: 半径（単調3次エルミート補間）

    /// 時刻t（時）での半径の割合。制御点を必ず通り、間をなめらかにつなぐ（行き過ぎなし）。
    func radiusFraction(at t: Double) -> Double {
        let n = controlPoints.count
        guard n > 0 else { return DailyRingLayout.minRadiusFraction }
        if n == 1 { return controlPoints[0].v }

        if isPeriodic {
            var tt = t.truncatingRemainder(dividingBy: DailyRingLayout.hoursPerDay)
            if tt < 0 { tt += DailyRingLayout.hoursPerDay }
            let k = Int(floor(tt - 0.5))
            return hermite(k, tt)
        }

        if t <= controlPoints[0].t { return controlPoints[0].v }
        if t >= controlPoints[n - 1].t { return controlPoints[n - 1].v }
        var k = 0
        while k < n - 2 && controlPoints[k + 1].t <= t { k += 1 }
        return hermite(k, t)
    }

    private func point(_ i: Int) -> (x: Double, y: Double) {
        let n = controlPoints.count
        if isPeriodic {
            let wraps = Int(floor(Double(i) / Double(n)))
            let j = i - wraps * n
            return (controlPoints[j].t + DailyRingLayout.hoursPerDay * Double(wraps), controlPoints[j].v)
        }
        let j = min(max(i, 0), n - 1)
        return (controlPoints[j].t, controlPoints[j].v)
    }

    /// 制御点iでの傾き（Fritsch–Carlson。前後で上り下りが変わる点は傾き0にして行き過ぎを防ぐ）。
    private func tangent(_ i: Int) -> Double {
        let n = controlPoints.count
        if !isPeriodic && (i <= 0 || i >= n - 1) { return 0 }
        let p0 = point(i - 1), p1 = point(i), p2 = point(i + 1)
        let h0 = p1.x - p0.x, h1 = p2.x - p1.x
        guard h0 > 0, h1 > 0 else { return 0 }
        let d0 = (p1.y - p0.y) / h0
        let d1 = (p2.y - p1.y) / h1
        if d0 * d1 <= 0 { return 0 }
        let w1 = 2 * h1 + h0
        let w2 = h1 + 2 * h0
        return (w1 + w2) / (w1 / d0 + w2 / d1)
    }

    private func hermite(_ k: Int, _ t: Double) -> Double {
        let p0 = point(k), p1 = point(k + 1)
        let h = p1.x - p0.x
        guard h > 0 else { return p0.y }
        let s = min(1, max(0, (t - p0.x) / h))
        let m0 = tangent(k) * h
        let m1 = tangent(k + 1) * h
        let s2 = s * s, s3 = s2 * s
        let value = (2 * s3 - 3 * s2 + 1) * p0.y
            + (s3 - 2 * s2 + s) * m0
            + (-2 * s3 + 3 * s2) * p1.y
            + (s3 - s2) * m1
        return value
    }

    // MARK: 活動種別の重み（境目でクロスフェード）

    /// 時刻t（時）での活動種別の重み（合計1）。時間の境目の前後 blendWidthHours/2 ずつで
    /// 隣の時間の種別と滑らかに入れ替わる。描く範囲の外（今日のこれから）では空。
    func kindWeights(at t: Double) -> [(kind: ActivityKind, weight: Double)] {
        let n = slotKinds.count
        guard n > 0 else { return [] }
        var tt = t
        if isPeriodic {
            tt = t.truncatingRemainder(dividingBy: DailyRingLayout.hoursPerDay)
            if tt < 0 { tt += DailyRingLayout.hoursPerDay }
        } else if tt < 0 || tt > drawnHours + 1e-9 {
            return []
        }
        let idx = min(max(Int(floor(tt)), 0), n - 1)
        let u = min(1, max(0, tt - Double(idx)))
        let current = slotKinds[idx]
        let blend = DailyRingLayout.blendWidthHours
        let half = blend / 2

        func neighbor(_ i: Int) -> ActivityKind? {
            if isPeriodic { return slotKinds[((i % n) + n) % n] }
            return (i >= 0 && i < n) ? slotKinds[i] : nil
        }

        var other: ActivityKind?
        var share = 1.0
        if u < half, let prev = neighbor(idx - 1) {
            share = DailyRingLayout.smoothstep(0.5 + u / blend)
            other = prev
        } else if u > 1 - half, let next = neighbor(idx + 1) {
            share = DailyRingLayout.smoothstep(0.5 + (1 - u) / blend)
            other = next
        }

        guard let other, other != current else { return [(current, 1)] }
        return [(current, share), (other, 1 - share)]
    }
}
