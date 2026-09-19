import Foundation
import CoreGraphics

// 「1日の輪」（docs/22-app1-radial-redesign.md「半径の意味づけを『活動の強さの山』に変更」）の、
// 描画から切り離した純粋な計算ロジック。FlowingDataの「Cycle of Many」型の点描。
//
// 読み方:
//   周方向 = 24時間（0時が真上、時計回り、1周で1日。今日の途中でも常に0〜24時 = 0〜360度）
//   半径   = その時刻の活動の強さ（1分あたりの歩数換算）。中心の小さな空洞から、強さに応じた半径までを点で埋める。
//            外側の輪郭が1日の起伏になる。静かな時間も最小半径を持つ。
//   色     = 活動の種類（静止=青、車移動=紫、自転車=琥珀、歩行=ミント、走行=ピンク赤）。境目は連続的に混ざる。
//   点の詰まり = その時刻にその状態だった頻度（分数）。歩行・走行は歩数が多いほど濃い。
//
// 強さ・密度・色の割合は、時間方向に三角形の重みで平均して、隣り合う時刻で急に変わらないようにする。

/// 色（0...1）。
struct RingRGB: Equatable {
    var r: Double
    var g: Double
    var b: Double
}

/// 点の種類。
enum RingDotRole: Equatable {
    /// 山の内側を埋める通常の点。
    case dot
    /// 山の外側の縁にこぼれる細かい光の粒（飛沫）。
    case spray
    /// 柔らかく大きな光の粒（ボケ）。奥行きを出す。
    case bokeh
}

/// 描く点1つ。
struct RingDot: Equatable {
    /// 時刻（0...24時）。角度に変換して使う。
    let hour: Double
    /// 中心からの距離（最大半径を1とした割合）。
    let radius: Double
    let kind: ActivityKind
    /// 大きさの倍率（中心付近は小さく、外縁ほど大きい。ばらつきあり）。
    let size: Double
    /// 明るさ（0.2〜1.0）。外縁ほど明るい傾向。
    let brightness: Double
    /// 空洞〜外縁の間のどのあたりか（0=空洞側、1=外縁）。色の深みの計算に使う。
    let depth: Double
    let role: RingDotRole
}

enum DailyRingLayout {

    // MARK: - 定数

    static let hoursPerDay: Double = 24
    /// 点の数を数える時間スライスの長さ（分）。
    static let sliceMinutes: Double = 5
    static let sliceHours: Double = sliceMinutes / 60
    static let slicesPerDay: Int = 288
    /// 強さ・密度・色の割合をなめらかにする幅。前後4スライス（20分）まで三角形の重みで混ぜる。
    static let smoothingHalfWidthSlices: Int = 4
    /// 点の半径（最大半径を1とした割合）。1080px画像で約1.6px（基準。実際は中心ほど小さく外縁ほど大きい）。
    static let dotRadiusFraction: Double = 0.0038
    /// 密度1（その時間ずっと何かをしていた）のとき、面積をどれだけ点で埋めるか。
    static let packingFill: Double = 1.0

    /// 活動の種類（凡例・色の割り当ての順序）。
    static let kindOrder: [ActivityKind] = [.stationary, .walking, .running, .cycling, .automotive]

    /// 中心の空洞の半径（最大半径を1とした割合）。点はこの外側から始まる。
    static let cavityRadius: Double = 0.14
    /// 強さ0（静止）のときの外側の半径。空洞のすぐ外に薄く見える程度。
    static let minimumOuterRadius: Double = 0.30
    /// 強さ→半径の飽和の速さ（歩/分）。1 - exp(-強さ/100)。30歩/分で約26%、100歩/分で約63%、160歩/分で約80%。
    static let intensityScale: Double = 100
    /// 自転車は1分あたり何歩ぶんの強さとみなすか（歩数計にほとんど出ないため）。
    static let cyclingStepsPerMinute: Double = 90
    /// 車移動は自分の運動量ではないので、歩行より小さめ（1分あたり30歩相当）。
    static let automotiveStepsPerMinute: Double = 30
    /// 歩数が取れなかった（0歩の）歩行・走行の時間に仮に使う歩/分。
    static let defaultCadence: Double = 60
    /// 1分あたり歩数の上限（走行でもこれ以上は同じ強さとみなす）。
    static let maximumCadence: Double = 200
    /// 強さの目安の円（弱・中・強）の歩/分。
    static let guideIntensities: [(label: String, stepsPerMinute: Double)] = [("弱", 30), ("中", 90), ("強", 160)]

    /// 歩数を加味する係数の下限（歩数が少ない歩行・走行でも、この割合の濃さは出す）。
    static let minimumStepFactor: Double = 0.6
    /// 歩行1分あたりの標準的な歩数（歩数が多いほど濃くするための基準）。
    static let referenceStepsPerMinute: Double = 100
    /// 活動区間が検出できなくても、その時間に歩数がこれ以上あれば「歩行」として扱う。
    static let walkingFallbackSteps: Int = 300
    /// 上記の場合に、歩数が何歩で「ずっと歩いていた」扱いになるか。
    static let walkingFallbackFullSteps: Double = 3000

    /// 山の外側にこぼれる飛沫の量（通常の点の数に対する割合）。
    static let sprayRatio: Double = 0.06
    /// 飛沫が縁からどこまで離れるか（最大半径に対する割合の目安）。
    static let sprayReach: Double = 0.07
    /// ボケ（大きな柔らかい光の粒）の量（通常の点の数に対する割合）。
    static let bokehRatio: Double = 0.004

    // MARK: - 色

    /// 活動ごとの色（暗い背景で光って見える色）。
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

    // MARK: - 端末に残っている履歴の範囲

    /// 端末（CMMotionActivityManager / CMPedometer）が保持する履歴の目安の日数（今日を含む）。
    static let retentionDays: Int = 7

    /// その日のデータが端末にまだ残っていそうか（未来の日は含まない）。
    static func isWithinRetention(date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        guard target <= today,
              let oldest = calendar.date(byAdding: .day, value: -(retentionDays - 1), to: today) else { return false }
        return target >= oldest
    }

    // MARK: - 強さ → 半径

    /// 強さ（1分あたりの歩数換算）→ 外側の半径の割合。単調増加。強さ0でも最小半径を持ち、1には届かない。
    static func radiusFraction(forIntensity stepsPerMinute: Double) -> Double {
        let s = max(0, stepsPerMinute)
        return minimumOuterRadius + (1 - minimumOuterRadius) * (1 - exp(-s / intensityScale))
    }

    /// 半径の割合の範囲内の面積を埋めるのに必要な点の数（密度1のとき、1スライスあたり）。
    static func dotCapacityPerSlice(outerRadius: Double) -> Double {
        let sliceAngle = 2 * Double.pi * sliceHours / hoursPerDay
        let area = 0.5 * max(0, outerRadius * outerRadius - cavityRadius * cavityRadius) * sliceAngle
        let dotArea = Double.pi * dotRadiusFraction * dotRadiusFraction
        return packingFill * area / dotArea
    }

    // MARK: - 集計（時間スライスごと）

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

        // 1時間ごとの補正: 歩行・走行の1分あたり歩数、歩数の多さによる濃さ、活動区間の検出漏れの補い。
        var cadence = [Double](repeating: defaultCadence, count: 24)
        var stepFactor = [Double](repeating: 1, count: 24)
        var walkingFallback = [Double](repeating: 0, count: 24)
        for hour in 0..<24 {
            let hourStart = dayStart.addingTimeInterval(Double(hour) * 3600)
            let seconds = secondsByKind(segments: data.segments, from: hourStart, to: hourStart.addingTimeInterval(3600))
            let movingMinutes = ((seconds[.walking] ?? 0) + (seconds[.running] ?? 0)) / 60
            let steps = hour < data.hourlySteps.count ? max(0, data.hourlySteps[hour]) : 0
            if movingMinutes >= 5 {
                if steps > 0 { cadence[hour] = min(maximumCadence, Double(steps) / movingMinutes) }
                let ratio = Double(steps) / (movingMinutes * referenceStepsPerMinute)
                stepFactor[hour] = minimumStepFactor + (1 - minimumStepFactor) * min(1, ratio)
            } else if movingMinutes >= 1 && steps > 0 {
                cadence[hour] = min(maximumCadence, Double(steps) / movingMinutes)
                let ratio = Double(steps) / (movingMinutes * referenceStepsPerMinute)
                stepFactor[hour] = minimumStepFactor + (1 - minimumStepFactor) * min(1, ratio)
            }
            if movingMinutes < 5 && steps >= walkingFallbackSteps {
                let fbw = min(1, Double(steps) / walkingFallbackFullSteps)
                walkingFallback[hour] = fbw
                cadence[hour] = min(maximumCadence, Double(steps) / (60 * fbw))
            }
        }

        var rawIntensity = [Double](repeating: 0, count: sliceCount)
        var rawDensity = [Double](repeating: 0, count: sliceCount)
        var rawWeights: [ActivityKind: [Double]] = [:]
        for kind in kindOrder { rawWeights[kind] = [Double](repeating: 0, count: sliceCount) }

        for i in 0..<sliceCount {
            let t0 = Double(i) * sliceHours
            let t1 = min(drawn, t0 + sliceHours)
            let coveredSeconds = (t1 - t0) * 3600
            guard coveredSeconds > 1 else { continue }
            let start = dayStart.addingTimeInterval(t0 * 3600)
            let end = dayStart.addingTimeInterval(t1 * 3600)
            let seconds = secondsByKind(segments: data.segments, from: start, to: end)
            let hour = min(23, Int((t0 + t1) / 2))

            var fractions: [ActivityKind: Double] = [:]
            var total = 0.0
            for kind in kindOrder {
                let f = min(1, (seconds[kind] ?? 0) / coveredSeconds)
                fractions[kind] = f
                total += f
            }
            var coverage = min(1, total)

            // 活動区間の検出漏れ: 歩数があるのに移動の活動区間がない時間は、歩行として扱う。
            let fbw = walkingFallback[hour]
            if fbw > 0 {
                fractions[.walking] = max(fractions[.walking] ?? 0, fbw)
                var others = 0.0
                for kind in kindOrder where kind != .stationary {
                    others += fractions[kind] ?? 0
                }
                fractions[.stationary] = max(0, 1 - others)
                coverage = 1
            }

            var sum = 0.0
            for kind in kindOrder { sum += fractions[kind] ?? 0 }
            guard sum > 0 else { continue }

            var densityFactor = 0.0
            var intensity = 0.0
            for kind in kindOrder {
                let f = fractions[kind] ?? 0
                let w = f / sum
                rawWeights[kind]?[i] = w
                let kf = (kind == .walking || kind == .running) ? stepFactor[hour] : 1
                densityFactor += w * kf
                let rate: Double
                switch kind {
                case .walking, .running: rate = cadence[hour]
                case .cycling: rate = cyclingStepsPerMinute
                case .automotive: rate = automotiveStepsPerMinute
                default: rate = 0
                }
                intensity += min(1, f / max(1, sum)) * rate
            }
            rawDensity[i] = coverage * densityFactor
            rawIntensity[i] = intensity
        }

        let periodic = sliceCount == slicesPerDay
        var smoothedWeights: [ActivityKind: [Double]] = [:]
        for kind in kindOrder {
            smoothedWeights[kind] = smooth(rawWeights[kind] ?? [], periodic: periodic)
        }
        let smoothedIntensity = smooth(rawIntensity, periodic: periodic)
        let smoothedDensity = smooth(rawDensity, periodic: periodic)
        return DailyRingDensity(
            drawnHours: drawn, sliceCount: sliceCount,
            rawIntensity: rawIntensity, rawDensity: rawDensity, rawWeights: rawWeights,
            smoothedIntensity: smoothedIntensity, smoothedDensity: smoothedDensity, smoothedWeights: smoothedWeights,
            smoothedRadius: smoothedIntensity.map { radiusFraction(forIntensity: $0) }
        )
    }

    // MARK: - 点の配置

    /// 点の配置を作る。同じ密度・同じseedなら毎回まったく同じ配置になる。
    /// ・通常の点: 空洞〜その時刻の外側の半径の間を、面積が均等になるように埋める。数 = 密度 × 面積に応じた容量
    ///   （小数部分は乱数で切り上げ・切り捨てして、平均が正確に密度に比例するようにする）。
    ///   中心付近は小さく暗め、外縁ほど大きく明るい。
    /// ・飛沫: 山の外側の縁にこぼれる細かい光の粒。
    /// ・ボケ: ごく少数の大きく柔らかい光の粒。
    /// 色（活動の種類）はその時刻の割合で確率的に選ぶ。割合は時間方向に滑らかに変わるので、境目で混ざる。
    static func makeDots(density: DailyRingDensity, seed: UInt64) -> [RingDot] {
        var generator = SeededGenerator(seed: seed &* 0x9E3779B97F4A7C15 &+ 0x1234567)
        var dots: [RingDot] = []
        let cavitySq = cavityRadius * cavityRadius

        func rand() -> Double { Double.random(in: 0..<1, using: &generator) }

        func pickKind(slice i: Int) -> ActivityKind {
            var total = 0.0
            for kind in kindOrder { total += density.smoothedWeights[kind]?[i] ?? 0 }
            guard total > 0 else { return .stationary }
            var target = rand() * total
            for kind in kindOrder {
                target -= density.smoothedWeights[kind]?[i] ?? 0
                if target <= 0 { return kind }
            }
            return .stationary
        }

        for i in 0..<density.sliceCount {
            let t0 = Double(i) * sliceHours
            let t1 = min(density.drawnHours, t0 + sliceHours)
            guard t1 > t0 else { continue }
            let d = density.smoothedDensity[i]
            guard d > 0 else { continue }
            let covered = (t1 - t0) / sliceHours
            let expected = d * dotCapacityPerSlice(outerRadius: density.smoothedRadius[i]) * covered
            var count = Int(expected.rounded(.down))
            if rand() < expected - Double(count) { count += 1 }
            for _ in 0..<count {
                let hour = t0 + rand() * (t1 - t0)
                let outer = density.outerRadius(at: hour)
                let outerSq = outer * outer
                let u = rand()
                let radius = (cavitySq + (outerSq - cavitySq) * u).squareRoot()
                let depth = (radius - cavityRadius) / max(0.0001, outer - cavityRadius)
                // 中心付近は小さく暗め、外縁は大きく明るい。
                let size = (0.55 + 0.75 * pow(depth, 1.3)) * (0.8 + 0.4 * rand())
                let brightness = min(1, 0.30 + 0.45 * depth + 0.25 * rand())
                dots.append(RingDot(hour: hour, radius: radius, kind: pickKind(slice: i), size: size, brightness: brightness, depth: depth, role: .dot))
            }

            // 飛沫: 縁のすぐ外に、離れるほど少なく細かく。
            let sprayExpected = expected * sprayRatio
            var sprayCount = Int(sprayExpected.rounded(.down))
            if rand() < sprayExpected - Double(sprayCount) { sprayCount += 1 }
            for _ in 0..<sprayCount {
                let hour = t0 + rand() * (t1 - t0)
                let outer = density.outerRadius(at: hour)
                let offset = -log(1 - rand() * 0.95) * sprayReach * 0.45
                let radius = min(1.06, outer + offset)
                let fade = max(0, 1 - offset / (sprayReach * 1.6))
                dots.append(RingDot(hour: hour, radius: radius, kind: pickKind(slice: i), size: 0.6 + 0.5 * rand(), brightness: min(1, 0.25 + 0.6 * fade * rand() + 0.15), depth: 1, role: .spray))
            }

            // ボケ: 山の内側に、ごく少数の大きくやわらかい光。
            let bokehExpected = expected * bokehRatio
            var bokehCount = Int(bokehExpected.rounded(.down))
            if rand() < bokehExpected - Double(bokehCount) { bokehCount += 1 }
            for _ in 0..<bokehCount {
                let hour = t0 + rand() * (t1 - t0)
                let outer = density.outerRadius(at: hour)
                let u = rand()
                let radius = (cavitySq + (outer * outer - cavitySq) * u).squareRoot()
                let depth = (radius - cavityRadius) / max(0.0001, outer - cavityRadius)
                dots.append(RingDot(hour: hour, radius: radius, kind: pickKind(slice: i), size: 5 + 9 * rand(), brightness: 0.35 + 0.4 * rand(), depth: depth, role: .bokeh))
            }
        }
        return dots
    }
}

/// その日の時間スライスごとの強さ・密度・色の割合。
struct DailyRingDensity {
    /// 描く時間の長さ（時間）。今日は現在時刻まで、過去日は24。
    let drawnHours: Double
    let sliceCount: Int
    /// 平均する前の値。
    let rawIntensity: [Double]      // 1分あたり歩数換算（歩/分）
    let rawDensity: [Double]        // 点の詰まり（0...1）。何かをしていた割合 × 歩数による濃さ
    let rawWeights: [ActivityKind: [Double]] // 色の割合（活動の種類ごと、合計1）
    /// 時間方向になめらかにした値。半径・点の数・色はこちらから決める。
    let smoothedIntensity: [Double]
    let smoothedDensity: [Double]
    let smoothedWeights: [ActivityKind: [Double]]
    /// スライスごとの外側の半径の割合（なめらかにした強さから）。
    let smoothedRadius: [Double]

    /// 24時間すべてを描くか（過去日）。trueなら0時側と24時側をなめらかにつなぐ。
    var isPeriodic: Bool { sliceCount == DailyRingLayout.slicesPerDay }
    /// 今日の途中（現在時刻までだけ描く）か。
    var isPartialDay: Bool { drawnHours < DailyRingLayout.hoursPerDay - 1e-9 }

    /// 時刻t（時）での外側の半径の割合。スライスの中心どうしを直線でつないで、段差のない輪郭にする。
    func outerRadius(at t: Double) -> Double {
        let radii = smoothedRadius
        let n = radii.count
        guard n > 0 else { return DailyRingLayout.minimumOuterRadius }
        // スライスiの中心は (i + 0.5) スライス目
        let pos = t / DailyRingLayout.sliceHours - 0.5
        var i0 = Int(floor(pos))
        let frac = pos - Double(i0)
        var i1 = i0 + 1
        if isPeriodic {
            i0 = ((i0 % n) + n) % n
            i1 = ((i1 % n) + n) % n
        } else {
            i0 = min(max(i0, 0), n - 1)
            i1 = min(max(i1, 0), n - 1)
        }
        return radii[i0] + (radii[i1] - radii[i0]) * min(1, max(0, frac))
    }

    /// スライスの色（活動の種類の色を割合で混ぜたもの）。輪郭の光の色に使う。
    func blendedColor(slice i: Int) -> RingRGB {
        var r = 0.0, g = 0.0, b = 0.0, total = 0.0
        for kind in DailyRingLayout.kindOrder {
            let w = smoothedWeights[kind]?[i] ?? 0
            let c = DailyRingLayout.ringColor(for: kind)
            r += c.r * w; g += c.g * w; b += c.b * w
            total += w
        }
        guard total > 0 else { return DailyRingLayout.ringColor(for: .stationary) }
        return RingRGB(r: r / total, g: g / total, b: b / total)
    }

    /// 点の期待数の合計（通常の点）。
    func expectedDotCount() -> Double {
        let radii = smoothedRadius
        var total = 0.0
        for i in 0..<sliceCount {
            let t0 = Double(i) * DailyRingLayout.sliceHours
            let t1 = min(drawnHours, t0 + DailyRingLayout.sliceHours)
            total += smoothedDensity[i] * DailyRingLayout.dotCapacityPerSlice(outerRadius: radii[i]) * max(0, t1 - t0) / DailyRingLayout.sliceHours
        }
        return total
    }
}
