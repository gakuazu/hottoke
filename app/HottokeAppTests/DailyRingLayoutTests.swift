import XCTest
@testable import HottokeApp

/// 「1日の輪」の角度・半径・描画範囲・連続性のテスト（docs/22-app1-radial-redesign.md）。
final class DailyRingLayoutTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// テスト用データ: 各時間の歩数と、必要なら活動区間を指定して1日分のデータを作る。
    private func makeData(day: Date, hourlySteps: [Int], segments: [ActivitySegment] = []) -> DailyActivityData {
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

    // MARK: - 半径

    func testRadiusFractionIsMonotonicAndHasMinimum() {
        XCTAssertEqual(DailyRingLayout.radiusFraction(forEffectiveSteps: 0), DailyRingLayout.minRadiusFraction, accuracy: 1e-12)
        XCTAssertGreaterThan(DailyRingLayout.radiusFraction(forEffectiveSteps: 0), 0)

        var previous = DailyRingLayout.radiusFraction(forEffectiveSteps: 0)
        for s in stride(from: 100, through: 10_000, by: 100) {
            let value = DailyRingLayout.radiusFraction(forEffectiveSteps: Double(s))
            XCTAssertGreaterThan(value, previous, "歩数\(s)で半径が増えていない")
            XCTAssertLessThan(value, 1)
            previous = value
        }
    }

    func testEffectiveStepsCompensatesCyclingAndAutomotive() {
        // 歩数0でも、自転車30分・車移動30分なら静止(最小半径)より大きい活動量になる。
        let cycling = DailyRingLayout.effectiveSteps(steps: 0, secondsByKind: [.cycling: 1800])
        let car = DailyRingLayout.effectiveSteps(steps: 0, secondsByKind: [.automotive: 1800])
        XCTAssertEqual(cycling, 2700, accuracy: 1e-9)
        XCTAssertEqual(car, 900, accuracy: 1e-9)
        XCTAssertGreaterThan(cycling, car)
        // 歩数のほうが大きければ歩数を優先
        XCTAssertEqual(DailyRingLayout.effectiveSteps(steps: 4000, secondsByKind: [.automotive: 600]), 4000, accuracy: 1e-9)
    }

    // MARK: - 活動種別

    func testDominantKindRules() {
        XCTAssertEqual(DailyRingLayout.dominantKind(secondsByKind: [:], steps: 0), .stationary)
        XCTAssertEqual(DailyRingLayout.dominantKind(secondsByKind: [.stationary: 3000], steps: 100), .stationary)
        XCTAssertEqual(DailyRingLayout.dominantKind(secondsByKind: [.walking: 1200, .stationary: 2000], steps: 1500), .walking)
        XCTAssertEqual(DailyRingLayout.dominantKind(secondsByKind: [.automotive: 1800], steps: 0), .automotive)
        XCTAssertEqual(DailyRingLayout.dominantKind(secondsByKind: [.cycling: 2400, .walking: 300], steps: 200), .cycling)
        // 活動区間の検出漏れ: 区間は静止だが歩数が多い → 歩行
        XCTAssertEqual(DailyRingLayout.dominantKind(secondsByKind: [.stationary: 3600], steps: 2500), .walking)
        // 移動が5分未満で歩数も少ない → 静止
        XCTAssertEqual(DailyRingLayout.dominantKind(secondsByKind: [.walking: 120], steps: 100), .stationary)
    }

    func testPatternStylesAreDistinctPerKind() {
        let kinds: [ActivityKind] = [.stationary, .walking, .running, .cycling, .automotive]
        let styles = Set(kinds.map { DailyRingLayout.patternStyle(for: $0) })
        XCTAssertEqual(styles.count, kinds.count, "輪の上で見分けられるよう、5つの活動は別々の形にする")
    }

    // MARK: - 描画範囲（今日の途中 / 過去日）

    func testTodayAt9amDrawsOnly0To135Degrees() {
        let now = date(2026, 9, 19, 9, 0)
        let drawn = DailyRingLayout.drawnHours(forDayStarting: now, now: now, calendar: calendar)
        XCTAssertEqual(drawn, 9, accuracy: 1e-9)
        XCTAssertEqual(DailyRingLayout.sweepDegrees(forDrawnHours: drawn), 135, accuracy: 1e-9)

        let data = makeData(day: now, hourlySteps: steps([7: 800, 8: 2500]))
        let profile = DailyRingLayout.makeProfile(data: data, now: now, calendar: calendar)
        XCTAssertEqual(profile.slots.count, 9) // 0時台〜8時台
        XCTAssertTrue(profile.isPartialDay)
        XCTAssertFalse(profile.isPeriodic)
        XCTAssertEqual(profile.drawnHours, 9, accuracy: 1e-9)

        // 9時以降は描かれない（種別の重みが空）。9時より前は描かれる。
        XCTAssertTrue(profile.kindWeights(at: 9.5).isEmpty)
        XCTAssertTrue(profile.kindWeights(at: 15).isEmpty)
        XCTAssertTrue(profile.kindWeights(at: 23.9).isEmpty)
        XCTAssertFalse(profile.kindWeights(at: 8.5).isEmpty)
        XCTAssertFalse(profile.kindWeights(at: 0.1).isEmpty)
    }

    func testTodayWithinAnHourIncludesPartialSlot() {
        let now = date(2026, 9, 19, 9, 30)
        let data = makeData(day: now, hourlySteps: steps([9: 1200]))
        let profile = DailyRingLayout.makeProfile(data: data, now: now, calendar: calendar)
        XCTAssertEqual(profile.drawnHours, 9.5, accuracy: 1e-9)
        XCTAssertEqual(profile.slots.count, 10)
        XCTAssertEqual(profile.slots.last?.coverage ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(DailyRingLayout.sweepDegrees(forDrawnHours: profile.drawnHours), 142.5, accuracy: 1e-9)
    }

    func testPastDayDrawsFull360Degrees() {
        let now = date(2026, 9, 19, 9, 0)
        let yesterday = date(2026, 9, 18)
        let drawn = DailyRingLayout.drawnHours(forDayStarting: yesterday, now: now, calendar: calendar)
        XCTAssertEqual(drawn, 24, accuracy: 1e-9)
        XCTAssertEqual(DailyRingLayout.sweepDegrees(forDrawnHours: drawn), 360, accuracy: 1e-9)

        let profile = DailyRingLayout.makeProfile(data: makeData(day: yesterday, hourlySteps: Array(repeating: 500, count: 24)), now: now, calendar: calendar)
        XCTAssertEqual(profile.slots.count, 24)
        XCTAssertTrue(profile.isPeriodic)
        XCTAssertFalse(profile.isPartialDay)
        XCTAssertFalse(profile.kindWeights(at: 23.9).isEmpty)
    }

    func testFutureDayDrawsNothing() {
        let now = date(2026, 9, 19, 9, 0)
        let drawn = DailyRingLayout.drawnHours(forDayStarting: date(2026, 9, 20), now: now, calendar: calendar)
        XCTAssertEqual(drawn, 0, accuracy: 1e-9)
    }

    func testSegmentsAreSplitPerHour() {
        let now = date(2026, 9, 19, 12, 0)
        // 7:30〜8:30 歩行 → 7時台30分・8時台30分
        let segment = ActivitySegment(start: date(2026, 9, 19, 7, 30), end: date(2026, 9, 19, 8, 30), kind: .walking)
        let data = makeData(day: now, hourlySteps: steps([7: 1500, 8: 1500]), segments: [segment])
        let slots = DailyRingLayout.makeSlots(data: data, now: now, calendar: calendar)
        XCTAssertEqual(slots[7].secondsByKind[.walking] ?? 0, 1800, accuracy: 1)
        XCTAssertEqual(slots[8].secondsByKind[.walking] ?? 0, 1800, accuracy: 1)
        XCTAssertEqual(slots[7].kind, .walking)
        XCTAssertEqual(slots[6].kind, .stationary)
        XCTAssertGreaterThan(slots[7].radiusFraction, slots[6].radiusFraction)
    }

    // MARK: - 連続性: 半径

    private func sampleProfile() -> DailyRingProfile {
        // 静か→歩く→走る→車→静か…と極端に変化する1日（過去日として24時間）。
        let hourly = [0, 0, 0, 0, 0, 0, 200, 3500, 4200, 300, 0, 0, 1500, 800, 0, 0, 0, 6000, 2500, 0, 0, 0, 0, 0]
        let segments = [
            ActivitySegment(start: date(2026, 9, 18, 7), end: date(2026, 9, 18, 9), kind: .walking),
            ActivitySegment(start: date(2026, 9, 18, 9), end: date(2026, 9, 18, 9, 40), kind: .automotive),
            ActivitySegment(start: date(2026, 9, 18, 17), end: date(2026, 9, 18, 18), kind: .running),
            ActivitySegment(start: date(2026, 9, 18, 18), end: date(2026, 9, 18, 19), kind: .cycling)
        ]
        let data = makeData(day: date(2026, 9, 18), hourlySteps: hourly, segments: segments)
        return DailyRingLayout.makeProfile(data: data, now: date(2026, 9, 19, 9), calendar: calendar)
    }

    func testRadiusCurvePassesThroughHourValuesAndNeverOvershoots() {
        let profile = sampleProfile()
        XCTAssertTrue(profile.isPeriodic)
        let values = profile.slots.map { $0.radiusFraction }
        let lo = values.min()!, hi = values.max()!
        for slot in profile.slots {
            XCTAssertEqual(profile.radiusFraction(at: Double(slot.hour) + 0.5), slot.radiusFraction, accuracy: 1e-9)
        }
        var t = 0.0
        while t < 24 {
            let r = profile.radiusFraction(at: t)
            XCTAssertGreaterThanOrEqual(r, lo - 1e-9)
            XCTAssertLessThanOrEqual(r, hi + 1e-9)
            XCTAssertGreaterThanOrEqual(r, DailyRingLayout.minRadiusFraction - 1e-9)
            t += 0.01
        }
    }

    func testRadiusCurveIsContinuousWithoutSteps() {
        let profile = sampleProfile()
        var t = 0.0
        var previous = profile.radiusFraction(at: 0)
        var maxJump = 0.0
        while t < 24 {
            t += 0.002
            let r = profile.radiusFraction(at: t)
            maxJump = max(maxJump, abs(r - previous))
            previous = r
        }
        // 1時間ごとに最大で約0.7動く極端なデータでも、0.002時間（7秒）で飛ぶ量は十分小さい。
        XCTAssertLessThan(maxJump, 0.01, "半径が階段状に飛んでいる")
    }

    func testRadiusCurveWrapsSmoothlyForFullDay() {
        let profile = sampleProfile()
        // 0時側と24時側が同じ値でつながる
        XCTAssertEqual(profile.radiusFraction(at: 0), profile.radiusFraction(at: 24), accuracy: 1e-9)
        let before = profile.radiusFraction(at: 24 - 0.001)
        let after = profile.radiusFraction(at: 0.001)
        XCTAssertEqual(before, after, accuracy: 0.005)
    }

    func testRadiusCurveOnPartialDayUsesPartialHourMidpoint() {
        let now = date(2026, 9, 19, 9, 30)
        let data = makeData(day: now, hourlySteps: steps([8: 3000, 9: 3000]))
        let profile = DailyRingLayout.makeProfile(data: data, now: now, calendar: calendar)
        XCTAssertFalse(profile.isPeriodic)
        // 途中の時間の制御点は、経過した部分(9:00〜9:30)の真ん中 = 9.25時
        XCTAssertEqual(profile.radiusFraction(at: 9.25), profile.slots.last!.radiusFraction, accuracy: 1e-9)
        // 範囲の端でも連続（現在時刻の少し手前と、その先の値が飛ばない）
        XCTAssertEqual(profile.radiusFraction(at: 9.5), profile.radiusFraction(at: 9.499), accuracy: 0.01)
    }

    // MARK: - 連続性: 活動種別の重み

    func testKindWeightsSumToOneAndAreContinuousAcrossBoundaries() {
        let profile = sampleProfile()
        let eps = 1e-4
        var boundary = 1.0
        while boundary < 24 {
            let before = profile.kindWeights(at: boundary - eps)
            let after = profile.kindWeights(at: boundary + eps)
            XCTAssertEqual(before.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
            XCTAssertEqual(after.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
            for kind in ActivityKind.allCases {
                let wb = before.filter { $0.kind == kind }.reduce(0) { $0 + $1.weight }
                let wa = after.filter { $0.kind == kind }.reduce(0) { $0 + $1.weight }
                XCTAssertEqual(wb, wa, accuracy: 0.01, "\(boundary)時の境目で\(kind)の重みが飛んでいる")
            }
            boundary += 1
        }
    }

    func testKindWeightsChangeGraduallyAndBlendWidthIsNarrow() {
        let profile = sampleProfile()
        // 7時台(歩行)と6時台(静止)の境目 = 7時。ちょうど境目は半々、15分以上離れれば完全に片方。
        func weight(_ kind: ActivityKind, at t: Double) -> Double {
            profile.kindWeights(at: t).filter { $0.kind == kind }.reduce(0) { $0 + $1.weight }
        }
        XCTAssertEqual(weight(.walking, at: 7.0), 0.5, accuracy: 1e-6)
        XCTAssertEqual(weight(.stationary, at: 7.0), 0.5, accuracy: 1e-6)
        XCTAssertEqual(weight(.walking, at: 7.3), 1, accuracy: 1e-9)
        XCTAssertEqual(weight(.stationary, at: 6.7), 1, accuracy: 1e-9)
        // 途中は単調に入れ替わる
        var previous = weight(.walking, at: 6.75)
        var t = 6.75
        while t <= 7.25 {
            let w = weight(.walking, at: t)
            XCTAssertGreaterThanOrEqual(w, previous - 1e-9)
            previous = w
            t += 0.005
        }
    }

    func testKindWeightsWrapAroundForFullDay() {
        let profile = sampleProfile()
        // 0時台も23時台も静止 → 0時の前後で重みは変わらず静止
        let a = profile.kindWeights(at: 24 - 0.001)
        let b = profile.kindWeights(at: 0.001)
        XCTAssertEqual(a.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
        XCTAssertEqual(b.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
        XCTAssertEqual(a.first(where: { $0.kind == .stationary })?.weight ?? 0, 1, accuracy: 1e-9)
    }

    func testKindWeightsWrapBlendsAcrossMidnightWhenKindsDiffer() {
        // 23時台が歩行、0時台が静止の過去日: 24時(=0時)の境目でクロスフェードしてつながる。
        var hourly = Array(repeating: 0, count: 24)
        hourly[23] = 2000
        let data = makeData(day: date(2026, 9, 18), hourlySteps: hourly)
        let profile = DailyRingLayout.makeProfile(data: data, now: date(2026, 9, 19, 9), calendar: calendar)
        let before = profile.kindWeights(at: 24 - 1e-4)
        let after = profile.kindWeights(at: 1e-4)
        func w(_ list: [(kind: ActivityKind, weight: Double)], _ k: ActivityKind) -> Double {
            list.filter { $0.kind == k }.reduce(0) { $0 + $1.weight }
        }
        XCTAssertEqual(w(before, .walking), w(after, .walking), accuracy: 0.01)
        XCTAssertEqual(w(before, .walking), 0.5, accuracy: 0.01)
    }

    // MARK: - 連続性: 色

    func testColorIsContinuousAndWrapsAtMidnight() {
        XCTAssertEqual(DailyRingLayout.color(atHour: 0), DailyRingLayout.color(atHour: 24))
        var t = 0.0
        var previous = DailyRingLayout.color(atHour: 0)
        var maxJump = 0.0
        while t < 24 {
            t += 0.005
            let c = DailyRingLayout.color(atHour: t)
            maxJump = max(maxJump, abs(c.r - previous.r), abs(c.g - previous.g), abs(c.b - previous.b))
            previous = c
        }
        XCTAssertLessThan(maxJump, 0.02, "色が時間帯の境目で飛んでいる")
        // 一周がつながる: 24時の直前と0時の直後もほぼ同じ色
        let a = DailyRingLayout.color(atHour: 24 - 0.001)
        let b = DailyRingLayout.color(atHour: 0.001)
        XCTAssertEqual(a.r, b.r, accuracy: 0.01)
        XCTAssertEqual(a.g, b.g, accuracy: 0.01)
        XCTAssertEqual(a.b, b.b, accuracy: 0.01)
    }

    // MARK: - 画像生成（クラッシュしないこと・大きさ）

    func testRendererProducesImageOfRequestedSize() {
        let profile = sampleProfile()
        let image = DailyRingRenderer.render(profile: profile, date: date(2026, 9, 18), size: 160, calendar: calendar)
        XCTAssertEqual(image.size.width * image.scale, 160, accuracy: 0.5)
        XCTAssertEqual(image.size.height * image.scale, 160, accuracy: 0.5)

        // 今日の途中（データが空でも描ける）
        let now = date(2026, 9, 19, 9, 0)
        let todayProfile = DailyRingLayout.makeProfile(data: makeData(day: now, hourlySteps: steps([8: 2000])), now: now, calendar: calendar)
        let todayImage = DailyRingRenderer.render(profile: todayProfile, date: now, size: 160, calendar: calendar)
        XCTAssertEqual(todayImage.size.width * todayImage.scale, 160, accuracy: 0.5)
    }
}
