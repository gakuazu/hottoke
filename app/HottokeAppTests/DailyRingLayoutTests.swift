import XCTest
@testable import HottokeApp

/// 「1日の輪」（点描・活動の強さの山）の角度・半径・点の数・描画範囲・連続性のテスト（docs/22-app1-radial-redesign.md）。
final class DailyRingLayoutTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func makeData(day: Date, hourlySteps: [Int] = Array(repeating: 0, count: 24), segments: [ActivitySegment] = []) -> DailyActivityData {
        DailyActivityData(
            date: calendar.startOfDay(for: day),
            segments: segments,
            stepCount: hourlySteps.reduce(0, +),
            distanceMeters: 0,
            floorsAscended: 0,
            floorAscendTimes: [],
            hourlySteps: hourlySteps
        )
    }

    private func steps(_ pairs: [Int: Int]) -> [Int] {
        var result = Array(repeating: 0, count: 24)
        for (h, s) in pairs { result[h] = s }
        return result
    }

    private func seg(_ day: Int, _ h0: Int, _ m0: Int, _ h1: Int, _ m1: Int, _ kind: ActivityKind) -> ActivitySegment {
        ActivitySegment(start: date(2026, 9, day, h0, m0), end: date(2026, 9, day, h1, m1), kind: kind)
    }

    /// 日中を (開始時, 開始分, 終了時, 終了分, 種類) の並びで指定して1日分の区間を作る。24:00は h=24 で指定する。
    private func segments(day: Int, _ blocks: [(Int, Int, Int, Int, ActivityKind)]) -> [ActivitySegment] {
        blocks.map { b in
            let start = date(2026, 9, day, b.0, b.1)
            let end = b.2 >= 24 ? date(2026, 9, day + 1, 0, 0) : date(2026, 9, day, b.2, b.3)
            return ActivitySegment(start: start, end: end, kind: b.4)
        }
    }

    // MARK: - 角度

    func testAngleZeroIsTopAndClockwise() {
        let top = DailyRingLayout.unitVector(forHour: 0)
        XCTAssertEqual(top.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(top.dy, -1, accuracy: 1e-9) // 画面座標では上が-y
        let right = DailyRingLayout.unitVector(forHour: 6)
        XCTAssertEqual(right.dx, 1, accuracy: 1e-9)
        XCTAssertEqual(right.dy, 0, accuracy: 1e-9)
        let bottom = DailyRingLayout.unitVector(forHour: 12)
        XCTAssertEqual(bottom.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(bottom.dy, 1, accuracy: 1e-9)
        let left = DailyRingLayout.unitVector(forHour: 18)
        XCTAssertEqual(left.dx, -1, accuracy: 1e-9)
        XCTAssertEqual(left.dy, 0, accuracy: 1e-9)
    }

    func testAngleDegreesIsFixedTo24HoursPer360() {
        XCTAssertEqual(DailyRingLayout.angleDegrees(forHour: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(DailyRingLayout.angleDegrees(forHour: 6), 90, accuracy: 1e-9)
        XCTAssertEqual(DailyRingLayout.angleDegrees(forHour: 9), 135, accuracy: 1e-9)
        XCTAssertEqual(DailyRingLayout.angleDegrees(forHour: 24), 360, accuracy: 1e-9)
    }

    // MARK: - 強さ → 半径

    func testRadiusIsMonotonicInIntensityWithMinimumOutsideCavity() {
        let zero = DailyRingLayout.radiusFraction(forIntensity: 0)
        XCTAssertEqual(zero, DailyRingLayout.minimumOuterRadius, accuracy: 1e-12)
        XCTAssertGreaterThan(zero, 0.2, "静止でも見える最小半径を持つ")

        var previous = zero
        for s in stride(from: 5, through: 400, by: 5) {
            let value = DailyRingLayout.radiusFraction(forIntensity: Double(s))
            XCTAssertGreaterThan(value, previous, "強さ\(s)で半径が増えていない")
            XCTAssertLessThan(value, 1)
            previous = value
        }
    }

    func testIntensityFromCyclingAndAutomotiveAndSteps() {
        let now = date(2026, 9, 19, 23, 30)
        // 自転車10:00〜10:30 → 1分90歩換算
        let cycling = DailyRingLayout.makeDensity(data: makeData(day: now, segments: [seg(19, 10, 0, 10, 30, .cycling)]), now: now, calendar: calendar)
        XCTAssertEqual(cycling.rawIntensity[10 * 12 + 2], 90, accuracy: 1e-6) // 10:10のスライス
        // 車移動 → 1分30歩換算
        let car = DailyRingLayout.makeDensity(data: makeData(day: now, segments: [seg(19, 10, 0, 10, 30, .automotive)]), now: now, calendar: calendar)
        XCTAssertEqual(car.rawIntensity[10 * 12 + 2], 30, accuracy: 1e-6)
        // 歩行: 30分で3000歩 → 100歩/分
        let walking = DailyRingLayout.makeDensity(data: makeData(day: now, hourlySteps: steps([10: 3000]), segments: [seg(19, 10, 0, 10, 30, .walking)]), now: now, calendar: calendar)
        XCTAssertEqual(walking.rawIntensity[10 * 12 + 2], 100, accuracy: 1e-6)
        // 静止は0（半径は最小）
        let still = DailyRingLayout.makeDensity(data: makeData(day: now, segments: [seg(19, 10, 0, 10, 30, .stationary)]), now: now, calendar: calendar)
        XCTAssertEqual(still.rawIntensity[10 * 12 + 2], 0, accuracy: 1e-9)
        // 歩数が多いほど遠くまで広がる
        let fast = DailyRingLayout.makeDensity(data: makeData(day: now, hourlySteps: steps([10: 4200]), segments: [seg(19, 10, 0, 10, 30, .walking)]), now: now, calendar: calendar)
        XCTAssertGreaterThan(fast.rawIntensity[10 * 12 + 2], walking.rawIntensity[10 * 12 + 2])
    }

    func testWalkingIsFilledInWhenSegmentsMissButStepsExist() {
        let now = date(2026, 9, 19, 23, 30)
        let data = makeData(day: now, hourlySteps: steps([10: 3500]), segments: [seg(19, 10, 0, 11, 0, .stationary)])
        let density = DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar)
        let i = 10 * 12 + 6
        XCTAssertGreaterThan(density.rawWeights[.walking]![i], 0.5, "検出漏れでも歩数があれば歩行の色が出る")
        XCTAssertGreaterThan(density.rawIntensity[i], 0)
    }

    // MARK: - 中心の密度勾配（空洞の縁をくっきりさせない）

    func testCenterDensityRisesSmoothlyFromZero() {
        XCTAssertEqual(DailyRingLayout.centerDensity(atRadius: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(DailyRingLayout.centerDensity(atRadius: 1), 1, accuracy: 1e-12)
        var previous = 0.0
        var maxStep = 0.0
        var r = 0.0
        while r <= 0.5 {
            let d = DailyRingLayout.centerDensity(atRadius: r)
            XCTAssertGreaterThanOrEqual(d, previous - 1e-12, "外へ向かって密度が減っている")
            maxStep = max(maxStep, d - previous)
            previous = d
            r += 0.005
        }
        XCTAssertLessThan(maxStep, 0.08, "密度が急に立ち上がっている（縁がくっきりする）")
        XCTAssertGreaterThan(DailyRingLayout.centerDensity(atRadius: 0.2), DailyRingLayout.centerDensity(atRadius: 0.08))
    }

    func testRadialMassInverseAndCapacity() {
        for r in stride(from: 0.05, through: 1.0, by: 0.05) {
            let m = DailyRingLayout.radialMass(upTo: r)
            XCTAssertEqual(DailyRingLayout.radiusForMass(m), r, accuracy: 0.002)
        }
        // 中心付近の点が薄いぶん、一様に埋めた場合より容量は少ない
        XCTAssertLessThan(DailyRingLayout.radialMass(upTo: 0.5), 0.5 * 0.5 / 2)
        XCTAssertGreaterThan(DailyRingLayout.dotCapacityPerSlice(outerRadius: 0.8), DailyRingLayout.dotCapacityPerSlice(outerRadius: 0.4))
    }

    func testFewerDotsNearCenterThanUniform() {
        let now = date(2026, 9, 19, 9, 0)
        let density = DailyRingLayout.makeDensity(data: makeData(day: date(2026, 9, 18), hourlySteps: steps([10: 6000]), segments: segments(day: 18, [(0, 0, 10, 0, .stationary), (10, 0, 11, 0, .walking), (11, 0, 24, 0, .stationary)])), now: now, calendar: calendar)
        let dots = DailyRingLayout.makeDots(density: density, seed: 5).filter { $0.role == .dot && $0.hour >= 10 && $0.hour < 11 }
        let inner = dots.filter { $0.radius < 0.10 }.count
        let uniformShare = (0.10 * 0.10) / (0.6 * 0.6) // 半径0.6まで一様に埋めた場合の、半径0.1以内の割合
        XCTAssertLessThan(Double(inner) / Double(dots.count), uniformShare)
    }

    // MARK: - 睡眠の種別

    func testSleepingIsARingKindWithDistinctColorAndZeroIntensity() {
        XCTAssertTrue(DailyRingLayout.kindOrder.contains(.sleeping))
        XCTAssertNotEqual(DailyRingLayout.ringColor(for: .sleeping), DailyRingLayout.ringColor(for: .stationary))
        XCTAssertEqual(ActivityKind.sleeping.displayName, "睡眠")
        XCTAssertEqual(ActivityKind.automotive.displayName, "乗り物")
        XCTAssertEqual(ActivityKind.running.displayName, "ランニング")

        let now = date(2026, 9, 19, 23, 30)
        let data = makeData(day: now, segments: [seg(19, 1, 0, 6, 0, .sleeping)])
        let density = DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar)
        let i = 3 * 12
        XCTAssertEqual(density.rawWeights[.sleeping]![i], 1, accuracy: 1e-9)
        XCTAssertEqual(density.rawIntensity[i], 0, accuracy: 1e-9)
        XCTAssertEqual(density.outerRadius(at: 3.5), DailyRingLayout.minimumOuterRadius, accuracy: 1e-6)
    }

    // MARK: - 描画範囲（今日の途中 / 過去日）

    func testTodayAt9amDrawsOnly0To135Degrees() {
        let now = date(2026, 9, 19, 9, 0)
        let drawn = DailyRingLayout.drawnHours(forDayStarting: now, now: now, calendar: calendar)
        XCTAssertEqual(drawn, 9, accuracy: 1e-9)
        XCTAssertEqual(DailyRingLayout.sweepDegrees(forDrawnHours: drawn), 135, accuracy: 1e-9)

        let density = DailyRingLayout.makeDensity(data: makeData(day: now, segments: [seg(19, 0, 0, 8, 0, .stationary), seg(19, 8, 0, 9, 0, .walking)]), now: now, calendar: calendar)
        XCTAssertTrue(density.isPartialDay)
        XCTAssertFalse(density.isPeriodic)
        XCTAssertEqual(density.sliceCount, 108) // 9時間 × 12スライス
    }

    func testNoDotsBeyondCurrentTime() {
        let now = date(2026, 9, 19, 9, 20)
        let data = makeData(day: now, hourlySteps: steps([8: 3000]), segments: [seg(19, 0, 0, 8, 0, .stationary), seg(19, 8, 0, 9, 20, .walking)])
        let density = DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar)
        XCTAssertEqual(density.drawnHours, 9 + 20.0 / 60, accuracy: 1e-9)
        let dots = DailyRingLayout.makeDots(density: density, seed: 20260919)
        XCTAssertFalse(dots.isEmpty)
        for dot in dots {
            XCTAssertLessThanOrEqual(dot.hour, density.drawnHours + 1e-9, "現在時刻より先に点がある")
            XCTAssertGreaterThanOrEqual(dot.hour, 0)
        }
    }

    func testPastDayDrawsFull360Degrees() {
        let now = date(2026, 9, 19, 9, 0)
        let yesterday = date(2026, 9, 18)
        XCTAssertEqual(DailyRingLayout.drawnHours(forDayStarting: yesterday, now: now, calendar: calendar), 24, accuracy: 1e-9)
        let density = DailyRingLayout.makeDensity(data: makeData(day: yesterday, segments: segments(day: 18, [(0, 0, 24, 0, .stationary)])), now: now, calendar: calendar)
        XCTAssertEqual(density.sliceCount, 288)
        XCTAssertTrue(density.isPeriodic)
        XCTAssertFalse(density.isPartialDay)
        let dots = DailyRingLayout.makeDots(density: density, seed: 1)
        XCTAssertTrue(dots.contains { $0.hour < 1 })
        XCTAssertTrue(dots.contains { $0.hour > 23 })
    }

    func testFutureDayDrawsNothing() {
        let now = date(2026, 9, 19, 9, 0)
        let density = DailyRingLayout.makeDensity(data: makeData(day: date(2026, 9, 20)), now: now, calendar: calendar)
        XCTAssertEqual(density.sliceCount, 0)
        XCTAssertTrue(DailyRingLayout.makeDots(density: density, seed: 1).isEmpty)
    }

    // MARK: - 点の位置・数・色

    private func typicalDay(day: Int = 18) -> DailyActivityData {
        let segs = segments(day: day, [
            (0, 0, 7, 0, .sleeping), (7, 0, 7, 30, .walking), (7, 30, 8, 15, .stationary), (8, 15, 8, 45, .walking),
            (8, 45, 12, 0, .stationary), (12, 0, 12, 25, .walking), (12, 25, 17, 30, .stationary),
            (17, 30, 18, 10, .walking), (18, 10, 18, 35, .running), (18, 35, 19, 20, .walking), (19, 20, 23, 15, .stationary), (23, 15, 24, 0, .sleeping)
        ])
        let hourly = steps([7: 1800, 8: 1500, 12: 2200, 17: 2000, 18: 3400, 19: 1500])
        return makeData(day: date(2026, 9, day), hourlySteps: hourly, segments: segs)
    }

    func testDotsFillFromCavityToOuterRadiusAndSprayStaysOutside() {
        let now = date(2026, 9, 19, 9, 0)
        let density = DailyRingLayout.makeDensity(data: typicalDay(), now: now, calendar: calendar)
        let dots = DailyRingLayout.makeDots(density: density, seed: 7)
        XCTAssertGreaterThan(dots.filter { $0.role == .dot }.count, 1000, "スカスカにならない")
        XCTAssertTrue(dots.contains { $0.role == .spray })
        XCTAssertTrue(dots.contains { $0.role == .bokeh })
        for dot in dots {
            let outer = density.outerRadius(at: dot.hour)
            switch dot.role {
            case .dot, .bokeh:
                XCTAssertGreaterThanOrEqual(dot.radius, 0, "半径が負")
                XCTAssertLessThanOrEqual(dot.radius, outer + 1e-9, "外側の輪郭をはみ出している")
            case .spray:
                XCTAssertGreaterThanOrEqual(dot.radius, outer - 1e-9)
            }
        }
    }

    func testOutlineRisesWhereActiveAndStaysLowWhereStill() {
        let now = date(2026, 9, 19, 9, 0)
        let density = DailyRingLayout.makeDensity(data: typicalDay(), now: now, calendar: calendar)
        let sleeping = density.outerRadius(at: 3)
        let running = density.outerRadius(at: 18 + 22.0 / 60)
        XCTAssertEqual(sleeping, DailyRingLayout.minimumOuterRadius, accuracy: 1e-6)
        XCTAssertGreaterThan(running, sleeping + 0.2, "走った時間帯は外側まで広がる")
    }

    func testDotCountIsProportionalToActiveMinutes() {
        // 同じ歩調(100歩/分)で60分歩いた日と30分歩いた日。それ以外の時間はデータなし。
        let now = date(2026, 9, 19, 23, 30)
        let long = makeData(day: now, hourlySteps: steps([10: 6000]), segments: [seg(19, 10, 0, 11, 0, .walking)])
        let short = makeData(day: now, hourlySteps: steps([14: 3000]), segments: [seg(19, 14, 0, 14, 30, .walking)])
        let longDensity = DailyRingLayout.makeDensity(data: long, now: now, calendar: calendar)
        let shortDensity = DailyRingLayout.makeDensity(data: short, now: now, calendar: calendar)
        let ratio = longDensity.expectedDotCount() / shortDensity.expectedDotCount()
        XCTAssertEqual(ratio, 2, accuracy: 0.5, "点の数が活動の分数にほぼ比例していない")

        // 5分のうち半分だけ活動していたスライスは、密度も半分
        let half = DailyRingLayout.makeDensity(data: makeData(day: now, hourlySteps: steps([10: 1200]), segments: [seg(19, 10, 0, 10, 2, .walking), seg(19, 10, 2, 10, 5, .stationary)]), now: now, calendar: calendar)
        XCTAssertLessThan(half.rawWeights[.walking]![10 * 12], 0.5)

        // 実際に置かれる点の数も、期待値に近い
        let placed = DailyRingLayout.makeDots(density: longDensity, seed: 99).filter { $0.role == .dot }.count
        XCTAssertEqual(Double(placed), longDensity.expectedDotCount(), accuracy: longDensity.expectedDotCount() * 0.05)
    }

    func testMoreStepsMakeWalkingDenserAndWider() {
        let now = date(2026, 9, 19, 23, 30)
        let dense = makeData(day: now, hourlySteps: steps([10: 6000]), segments: [seg(19, 10, 0, 11, 0, .walking)])
        let sparse = makeData(day: now, hourlySteps: steps([10: 1200]), segments: [seg(19, 10, 0, 11, 0, .walking)])
        let d = DailyRingLayout.makeDensity(data: dense, now: now, calendar: calendar)
        let s = DailyRingLayout.makeDensity(data: sparse, now: now, calendar: calendar)
        XCTAssertGreaterThan(d.rawDensity[10 * 12 + 6], s.rawDensity[10 * 12 + 6])
        XCTAssertGreaterThan(d.expectedDotCount(), s.expectedDotCount())
        XCTAssertGreaterThan(d.outerRadius(at: 10.5), s.outerRadius(at: 10.5))
    }

    func testColorWeightsMixAndSumToOne() {
        let now = date(2026, 9, 19, 23, 30)
        // 10:00〜10:30は歩行、10:30〜11:00は静止 → 境目のスライスは両方の色が混ざる
        let data = makeData(day: now, hourlySteps: steps([10: 3000]), segments: [seg(19, 10, 0, 10, 30, .walking), seg(19, 10, 30, 11, 0, .stationary)])
        let density = DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar)
        let boundary = 10 * 12 + 6
        XCTAssertGreaterThan(density.smoothedWeights[.walking]![boundary], 0.05)
        XCTAssertGreaterThan(density.smoothedWeights[.stationary]![boundary], 0.05)
        // （データのない時間との境目では平均で薄まるので、両側20分以上内側のスライスで確認）
        for i in (10 * 12 + 4)...(10 * 12 + 7) {
            let total = DailyRingLayout.kindOrder.reduce(0.0) { $0 + density.smoothedWeights[$1]![i] }
            XCTAssertEqual(total, 1, accuracy: 1e-9)
        }
        // 実際の点の色にも両方が現れる
        let kinds = Set(DailyRingLayout.makeDots(density: density, seed: 3).filter { $0.role == .dot && $0.hour > 10.3 && $0.hour < 10.7 }.map { $0.kind })
        XCTAssertTrue(kinds.contains(.walking) && kinds.contains(.stationary))
    }

    // MARK: - 決定性

    func testSameInputGivesSameDotLayout() {
        let now = date(2026, 9, 19, 15, 0)
        let data = typicalDay(day: 19)
        let a = DailyRingLayout.makeDots(density: DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar), seed: 20260919)
        let b = DailyRingLayout.makeDots(density: DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar), seed: 20260919)
        XCTAssertEqual(a, b)
        let c = DailyRingLayout.makeDots(density: DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar), seed: 20260920)
        XCTAssertNotEqual(a, c, "日付(seed)が違えば配置も変わる")
    }

    // MARK: - 連続性

    func testSmoothingLimitsJumpBetweenNeighboringSlices() {
        var step = [Double](repeating: 0, count: 60)
        for i in 30..<60 { step[i] = 1 }
        let smoothed = DailyRingLayout.smooth(step, periodic: false)
        var maxJump = 0.0
        for i in 1..<smoothed.count { maxJump = max(maxJump, abs(smoothed[i] - smoothed[i - 1])) }
        XCTAssertLessThanOrEqual(maxJump, 0.25 + 1e-9)
        XCTAssertGreaterThan(maxJump, 0)
        XCTAssertEqual(smoothed[10], 0, accuracy: 1e-9)
        XCTAssertEqual(smoothed[50], 1, accuracy: 1e-9)
    }

    func testRadiusDensityAndColorAreContinuousIncludingMidnightWrap() {
        // 過去日: 23:30〜24:00は走行、0:00〜は静止 → 0時と24時のつなぎ目でも半径・密度・色が急に変わらない。
        let now = date(2026, 9, 19, 9, 0)
        let data = makeData(day: date(2026, 9, 18), hourlySteps: steps([23: 4500, 12: 2500]), segments: segments(day: 18, [
            (0, 0, 12, 0, .stationary), (12, 0, 12, 30, .walking), (12, 30, 23, 30, .stationary), (23, 30, 24, 0, .running)
        ]))
        let density = DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar)
        XCTAssertTrue(density.isPeriodic)
        let n = density.sliceCount
        for i in 0..<n {
            let j = (i + 1) % n // 最後の次は先頭（0時と24時のつなぎ目）
            XCTAssertLessThanOrEqual(abs(density.smoothedRadius[j] - density.smoothedRadius[i]), 0.25 + 1e-9, "半径が\(i)番目付近で急に変わっている")
            XCTAssertLessThanOrEqual(abs(density.smoothedDensity[j] - density.smoothedDensity[i]), 0.25 + 1e-9)
            for kind in DailyRingLayout.kindOrder {
                XCTAssertLessThanOrEqual(abs(density.smoothedWeights[kind]![j] - density.smoothedWeights[kind]![i]), 0.25 + 1e-9, "\(kind)の色の割合が急に変わっている")
            }
        }
        // 輪郭の線は0時と24時で同じ半径でつながる
        XCTAssertEqual(density.outerRadius(at: 0), density.outerRadius(at: 24), accuracy: 1e-9)
        XCTAssertEqual(density.outerRadius(at: 24 - 0.001), density.outerRadius(at: 0.001), accuracy: 0.01)
        // 輪郭は細かく見ても段差がない
        var t = 0.0
        var previous = density.outerRadius(at: 0)
        var maxJump = 0.0
        while t < 24 {
            t += 0.002
            let r = density.outerRadius(at: t)
            maxJump = max(maxJump, abs(r - previous))
            previous = r
        }
        XCTAssertLessThan(maxJump, 0.01)
    }

    func testPartialDayHasNoSmoothingBeyondTheEnd() {
        let now = date(2026, 9, 19, 3, 0)
        let data = makeData(day: now, segments: [seg(19, 0, 0, 3, 0, .stationary)])
        let density = DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar)
        XCTAssertEqual(density.smoothedDensity.count, 36)
        XCTAssertEqual(density.smoothedDensity.last ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(density.smoothedDensity.first ?? 0, 1, accuracy: 1e-9)
    }

    // MARK: - アーカイブ（端末に残っている履歴の範囲）

    func testRetentionWindowIsLast7DaysIncludingToday() {
        let now = date(2026, 9, 19, 9, 0)
        XCTAssertTrue(DailyRingLayout.isWithinRetention(date: date(2026, 9, 19), now: now, calendar: calendar))
        XCTAssertTrue(DailyRingLayout.isWithinRetention(date: date(2026, 9, 13), now: now, calendar: calendar)) // 6日前
        XCTAssertFalse(DailyRingLayout.isWithinRetention(date: date(2026, 9, 12), now: now, calendar: calendar)) // 7日前
        XCTAssertFalse(DailyRingLayout.isWithinRetention(date: date(2026, 8, 1), now: now, calendar: calendar))
        XCTAssertFalse(DailyRingLayout.isWithinRetention(date: date(2026, 9, 20), now: now, calendar: calendar), "未来の日は対象外")
    }

    // MARK: - 画像生成（クラッシュしないこと・大きさ）

    func testRendererProducesImageOfRequestedSize() {
        let now = date(2026, 9, 19, 9, 0)
        let density = DailyRingLayout.makeDensity(data: typicalDay(), now: now, calendar: calendar)
        let image = DailyRingRenderer.render(density: density, date: date(2026, 9, 18), size: 200, calendar: calendar)
        XCTAssertEqual(image.size.width * image.scale, 200, accuracy: 0.5)
        XCTAssertEqual(image.size.height * image.scale, 200, accuracy: 0.5)

        // 今日の途中・データが空でも描ける
        let empty = DailyRingLayout.makeDensity(data: makeData(day: now), now: now, calendar: calendar)
        let todayImage = DailyRingRenderer.render(density: empty, date: now, size: 200, calendar: calendar)
        XCTAssertEqual(todayImage.size.width * todayImage.scale, 200, accuracy: 0.5)
    }

    /// 見た目の確認用: 環境変数 RING_SAMPLE_DIR が指定されているときだけ、日ごとに雰囲気の違うサンプル画像(1080px)をPNGで書き出す
    /// （GitHub Actionsで画像をArtifactとして受け取り、目視確認するため。通常のテストでは何もしない）。
    func testWriteSampleImagesWhenRequested() throws {
        guard let dir = ProcessInfo.processInfo.environment["RING_SAMPLE_DIR"], !dir.isEmpty else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let now = date(2026, 9, 19, 14, 20)

        func write(_ name: String, data: DailyActivityData, day: Int, at: Date? = nil) throws {
            let density = DailyRingLayout.makeDensity(data: data, now: at ?? now, calendar: calendar)
            let image = DailyRingRenderer.render(density: density, date: date(2026, 9, day), size: 1080, calendar: calendar)
            try image.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }

        // 普通の1日（過去日）と、その日の14:20時点（今日の途中）
        try write("ring-typical-day.png", data: typicalDay(day: 18), day: 18)
        try write("ring-today-partial.png", data: typicalDay(day: 19), day: 19)

        // ほぼ静止の日
        let still = makeData(day: date(2026, 9, 17), hourlySteps: steps([9: 700, 15: 500]), segments: segments(day: 17, [
            (0, 0, 9, 0, .stationary), (9, 0, 9, 10, .walking), (9, 10, 15, 0, .stationary), (15, 0, 15, 8, .walking), (15, 8, 24, 0, .stationary)
        ]))
        try write("ring-still-day.png", data: still, day: 17)

        // よく歩いた日
        let walker = makeData(day: date(2026, 9, 16), hourlySteps: steps([7: 3500, 8: 4200, 10: 3000, 11: 3800, 13: 4500, 14: 3900, 16: 4200, 17: 4800, 18: 3000, 20: 1800]), segments: segments(day: 16, [
            (0, 0, 7, 0, .stationary), (7, 0, 9, 0, .walking), (9, 0, 10, 0, .stationary), (10, 0, 12, 0, .walking), (12, 0, 13, 0, .stationary),
            (13, 0, 15, 0, .walking), (15, 0, 16, 0, .stationary), (16, 0, 18, 30, .walking), (18, 30, 20, 0, .stationary), (20, 0, 20, 40, .walking), (20, 40, 24, 0, .stationary)
        ]))
        try write("ring-walker-day.png", data: walker, day: 16)

        // 走った日
        let runner = makeData(day: date(2026, 9, 15), hourlySteps: steps([6: 6800, 7: 1200, 12: 1600, 19: 7600, 20: 2400]), segments: segments(day: 15, [
            (0, 0, 6, 0, .stationary), (6, 0, 7, 0, .running), (7, 0, 7, 20, .walking), (7, 20, 12, 0, .stationary), (12, 0, 12, 20, .walking),
            (12, 20, 19, 0, .stationary), (19, 0, 20, 0, .running), (20, 0, 20, 30, .walking), (20, 30, 24, 0, .stationary)
        ]))
        try write("ring-runner-day.png", data: runner, day: 15)

        // 車移動が多い日
        let driver = makeData(day: date(2026, 9, 14), hourlySteps: steps([7: 500, 8: 700, 12: 900, 17: 600, 18: 800]), segments: segments(day: 14, [
            (0, 0, 7, 30, .stationary), (7, 30, 8, 30, .automotive), (8, 30, 12, 0, .stationary), (12, 0, 12, 40, .automotive), (12, 40, 13, 30, .stationary),
            (13, 30, 14, 10, .automotive), (14, 10, 17, 30, .stationary), (17, 30, 18, 50, .automotive), (18, 50, 24, 0, .stationary)
        ]))
        try write("ring-driver-day.png", data: driver, day: 14)

        // ---- プロモード用のサンプル ----
        let base = calendar.startOfDay(for: now)
        // 直近30日ぶんの、少しずつ違う1日（平日/休日・ランニングの日・乗り物の日が混ざる）
        var pastRecords: [DailyRingSlices] = []
        for k in stride(from: 29, through: 1, by: -1) {
            let day = calendar.date(byAdding: .day, value: -k, to: base)!
            pastRecords.append(syntheticDay(day: day, index: k))
        }
        let todayRecord = DailyRingLayout.makeSlices(data: typicalDay(day: 19), now: now, calendar: calendar)
        let weekRecords = Array(pastRecords.suffix(6)) + [todayRecord]
        let monthRecords = pastRecords + [todayRecord]

        func writePNG(_ image: UIImage, _ name: String) throws {
            try image.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }

        // 積算（1週間・1ヶ月）
        for (name, records, title) in [("ring-week-aggregate.png", weekRecords, "1週間の積算"), ("ring-month-aggregate.png", monthRecords, "1ヶ月の積算")] {
            var options = RingRenderOptions(canvas: CGSize(width: 1080, height: 1080))
            options.caption = RingCaption(title: title, subtitle: "保存済み \(records.count)日分")
            try writePNG(DailyRingRenderer.render(density: DailyRingLayout.aggregate(records), date: base, options: options, calendar: calendar), name)
        }

        // 今日と普段の重ね
        var compareOptions = RingRenderOptions(canvas: CGSize(width: 1080, height: 1080))
        compareOptions.ghost = DailyRingLayout.aggregate(pastRecords)
        let todayDensity = DailyRingLayout.makeDensity(slices: todayRecord)
        try writePNG(DailyRingRenderer.render(density: todayDensity, date: base, options: compareOptions, calendar: calendar), "ring-compare-today.png")

        // 振り返りレポート（1週間・1ヶ月）
        for (name, records, period) in [("report-week.png", weekRecords, RingPeriod.week), ("report-month.png", monthRecords, RingPeriod.month)] {
            let report = PeriodReport.make(records: records, period: period, now: now, calendar: calendar)
            try writePNG(ReportRenderer.render(report: report, records: records, theme: .standard), name)
        }
        let weekReport = PeriodReport.make(records: weekRecords, period: .week, now: now, calendar: calendar)
        try writePNG(ReportRenderer.render(report: weekReport, records: weekRecords, theme: .aurora), "report-week-aurora.png")

        // 壁紙サイズ（iPhoneの画面の比率）
        var wallpaper = RingRenderOptions(canvas: CGSize(width: 1179, height: 2556))
        wallpaper.chrome = .art
        wallpaper.ringSide = 1179 * 1.35
        wallpaper.ringCenter = CGPoint(x: 1179 / 2, y: 2556 * 0.54)
        try writePNG(DailyRingRenderer.render(density: DailyRingLayout.aggregate(weekRecords), date: base, options: wallpaper, calendar: calendar), "ring-wallpaper-week.png")

        // 各配色テーマ（普通の日）
        for theme in RingTheme.allCases {
            var options = RingRenderOptions(canvas: CGSize(width: 1080, height: 1080))
            options.theme = theme
            let density = DailyRingLayout.makeDensity(slices: DailyRingLayout.makeSlices(data: typicalDay(day: 18), now: now, calendar: calendar))
            try writePNG(DailyRingRenderer.render(density: density, date: date(2026, 9, 18), options: options, calendar: calendar), "ring-theme-\(theme.rawValue).png")
        }

        // アーカイブのサムネイル（拡大して確認）
        let thumbs = pastRecords.suffix(3).map { DailyRingRenderer.renderThumbnail(slices: $0, size: 240) }
        for (i, t) in thumbs.enumerated() { try writePNG(t, "thumb-\(i).png") }

        // 自転車も走行も車も混ざった日
        let mixed = makeData(day: date(2026, 9, 13), hourlySteps: steps([7: 1500, 12: 2000, 18: 5200]), segments: segments(day: 13, [
            (0, 0, 7, 0, .stationary), (7, 0, 7, 40, .cycling), (7, 40, 12, 0, .stationary), (12, 0, 12, 30, .walking), (12, 30, 17, 30, .stationary),
            (17, 30, 18, 0, .automotive), (18, 0, 18, 50, .running), (18, 50, 24, 0, .stationary)
        ]))
        try write("ring-mixed-day.png", data: mixed, day: 13)
    }

    /// サンプル用: 日ごとに少しずつ違う1日（起床時刻・通勤の乗り物・ランニングの日など）を作る。
    private func syntheticDay(day: Date, index i: Int) -> DailyRingSlices {
        let start = calendar.startOfDay(for: day)
        let weekend = i % 7 == 0 || i % 7 == 6
        let wake = 6 * 60 + (i * 7) % 50 + (weekend ? 60 : 0)
        var blocks: [(Int, Int, ActivityKind)] = [(0, wake, .sleeping)]
        var cursor = wake
        func add(_ length: Int, _ kind: ActivityKind) { blocks.append((cursor, cursor + length, kind)); cursor += length }
        if weekend {
            add(90, .stationary); add(45 + i % 30, .walking); add(150, .stationary)
            if i % 2 == 0 { add(50, .cycling) } else { add(35, .walking) }
            add(max(30, 15 * 60 - cursor), .stationary) // 午後まで静止
        } else {
            add(50, .stationary); add(25 + i % 10, .walking)
            if i % 3 == 0 { add(40, .automotive) } else { add(30, .walking) }
            add(12 * 60 + 10 - cursor, .stationary); add(25, .walking)
            add(17 * 60 + 20 - cursor, .stationary)
            if i % 4 == 1 { add(40, .running); add(20, .walking) } else { add(30, .walking); add(30 + (i * 5) % 30, .automotive) }
        }
        let sleepStart = 23 * 60 + (i * 3) % 40
        if sleepStart > cursor { blocks.append((cursor, sleepStart, .stationary)); blocks.append((sleepStart, 24 * 60, .sleeping)) }
        var segments: [ActivitySegment] = []
        var hourly = [Int](repeating: 0, count: 24)
        for (a, b, kind) in blocks where b > a {
            segments.append(ActivitySegment(start: start.addingTimeInterval(Double(a) * 60), end: start.addingTimeInterval(Double(min(b, 1440)) * 60), kind: kind))
            let rate = kind == .walking ? 92 : (kind == .running ? 165 : 0)
            for minute in a..<min(b, 1440) { hourly[min(23, minute / 60)] += rate }
        }
        let data = DailyActivityData(date: start, segments: segments, stepCount: hourly.reduce(0, +), distanceMeters: 0, floorsAscended: 0, floorAscendTimes: [], hourlySteps: hourly)
        return DailyRingLayout.makeSlices(data: data, now: start.addingTimeInterval(36 * 3600), calendar: calendar)
    }
}
