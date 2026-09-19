import XCTest
@testable import HottokeApp

/// 「1日の輪」（点描リング）の角度・輪・点の数・描画範囲・連続性のテスト（docs/22-app1-radial-redesign.md）。
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

    // MARK: - 輪の割り当て

    func testRingsAreOrderedOuterToInnerWithoutOverlapAndLeaveCenterOpen() {
        XCTAssertEqual(DailyRingLayout.ringOrder, [.stationary, .automotive, .cycling, .walking, .running])
        var previousInner = Double.infinity
        for kind in DailyRingLayout.ringOrder {
            let band = DailyRingLayout.band(for: kind)
            XCTAssertLessThan(band.inner, band.outer)
            XCTAssertLessThanOrEqual(band.outer, previousInner, "\(kind)の輪が外側の輪と重なっている")
            XCTAssertGreaterThan(band.inner, 0.1, "中心は空ける")
            previousInner = band.inner
        }
        XCTAssertLessThanOrEqual(DailyRingLayout.band(for: .stationary).outer, 1.0)
        // 静止は最も広い帯
        let widths = DailyRingLayout.ringOrder.map { DailyRingLayout.band(for: $0).outer - DailyRingLayout.band(for: $0).inner }
        XCTAssertEqual(widths.max(), widths[0])
        // 不明は静止の輪に含める
        XCTAssertEqual(DailyRingLayout.band(for: .unknown), DailyRingLayout.band(for: .stationary))
    }

    func testRingColorsAreDistinct() {
        let colors = DailyRingLayout.ringOrder.map { DailyRingLayout.ringColor(for: $0) }
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                XCTAssertNotEqual(colors[i], colors[j])
            }
        }
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
        // 今日の9:20。0時から現在までずっと静止、8時台は歩行。
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
        let density = DailyRingLayout.makeDensity(data: makeData(day: yesterday, segments: [seg(18, 0, 0, 23, 59, .stationary)]), now: now, calendar: calendar)
        XCTAssertEqual(density.sliceCount, 288)
        XCTAssertTrue(density.isPeriodic)
        XCTAssertFalse(density.isPartialDay)
        let dots = DailyRingLayout.makeDots(density: density, seed: 1)
        // 24時間ぶんのどこにも点がある（0〜6時、18〜24時にも）
        XCTAssertTrue(dots.contains { $0.hour < 1 })
        XCTAssertTrue(dots.contains { $0.hour > 23 })
    }

    func testFutureDayDrawsNothing() {
        let now = date(2026, 9, 19, 9, 0)
        let density = DailyRingLayout.makeDensity(data: makeData(day: date(2026, 9, 20)), now: now, calendar: calendar)
        XCTAssertEqual(density.drawnHours, 0, accuracy: 1e-9)
        XCTAssertEqual(density.sliceCount, 0)
        XCTAssertTrue(DailyRingLayout.makeDots(density: density, seed: 1).isEmpty)
    }

    // MARK: - 点の数（分数に比例）・輪の中に収まる

    func testDotsStayInsideTheirRingBand() {
        let now = date(2026, 9, 19, 12, 0)
        let data = makeData(day: now, hourlySteps: steps([9: 4000, 10: 3000]), segments: [
            seg(19, 0, 0, 9, 0, .stationary), seg(19, 9, 0, 10, 0, .walking), seg(19, 10, 0, 10, 30, .running),
            seg(19, 10, 30, 11, 0, .cycling), seg(19, 11, 0, 12, 0, .automotive)
        ])
        let dots = DailyRingLayout.makeDots(density: DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar), seed: 7)
        XCTAssertEqual(Set(dots.map { $0.kind }).count, 5)
        for dot in dots {
            let band = DailyRingLayout.band(for: dot.kind)
            XCTAssertGreaterThanOrEqual(dot.radius, band.inner - 1e-9)
            XCTAssertLessThanOrEqual(dot.radius, band.outer + 1e-9)
        }
    }

    func testDotCountIsProportionalToMinutes() {
        // 60分ずっと歩いた日と、30分だけ歩いた日（歩数は同じペースで、濃さの補正が同じになるようにする）。
        let now = date(2026, 9, 19, 23, 30)
        let long = makeData(day: now, hourlySteps: steps([10: 6000]), segments: [seg(19, 10, 0, 11, 0, .walking)])
        let short = makeData(day: now, hourlySteps: steps([14: 3000]), segments: [seg(19, 14, 0, 14, 30, .walking)])
        let longDensity = DailyRingLayout.makeDensity(data: long, now: now, calendar: calendar)
        let shortDensity = DailyRingLayout.makeDensity(data: short, now: now, calendar: calendar)
        let longExpected = longDensity.expectedDotCount(for: .walking)
        let shortExpected = shortDensity.expectedDotCount(for: .walking)
        XCTAssertGreaterThan(shortExpected, 0)
        XCTAssertEqual(longExpected / shortExpected, 2, accuracy: 0.05, "点の数が活動の分数に比例していない")

        // 実際に置かれる点の数も、期待値に近い（小数部分は乱数で丸めるため平均で一致）
        let dots = DailyRingLayout.makeDots(density: longDensity, seed: 99).filter { $0.kind == .walking }.count
        XCTAssertEqual(Double(dots), longExpected, accuracy: longExpected * 0.05)
    }

    func testMoreStepsMakeWalkingDenser() {
        let now = date(2026, 9, 19, 23, 30)
        let dense = makeData(day: now, hourlySteps: steps([10: 6000]), segments: [seg(19, 10, 0, 11, 0, .walking)])
        let sparse = makeData(day: now, hourlySteps: steps([10: 1200]), segments: [seg(19, 10, 0, 11, 0, .walking)])
        let d = DailyRingLayout.makeDensity(data: dense, now: now, calendar: calendar).expectedDotCount(for: .walking)
        let s = DailyRingLayout.makeDensity(data: sparse, now: now, calendar: calendar).expectedDotCount(for: .walking)
        XCTAssertGreaterThan(d, s)
    }

    func testWalkingIsFilledInWhenSegmentsMissButStepsExist() {
        // 活動区間は静止だけだが歩数が多い（検出漏れ）→ 歩行の輪にも点が出る
        let now = date(2026, 9, 19, 23, 30)
        let data = makeData(day: now, hourlySteps: steps([10: 3500]), segments: [seg(19, 10, 0, 11, 0, .stationary)])
        let density = DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar)
        XCTAssertGreaterThan(density.expectedDotCount(for: .walking), 0)
    }

    func testCapacityIsSmallerForInnerRings() {
        XCTAssertGreaterThan(DailyRingLayout.dotCapacityPerSlice(for: .stationary), DailyRingLayout.dotCapacityPerSlice(for: .walking))
        XCTAssertGreaterThan(DailyRingLayout.dotCapacityPerSlice(for: .walking), DailyRingLayout.dotCapacityPerSlice(for: .running))
        XCTAssertGreaterThan(DailyRingLayout.dotCapacityPerSlice(for: .running), 1)
    }

    // MARK: - 決定性

    func testSameInputGivesSameDotLayout() {
        let now = date(2026, 9, 19, 15, 0)
        let data = makeData(day: now, hourlySteps: steps([8: 3000]), segments: [seg(19, 0, 0, 8, 0, .stationary), seg(19, 8, 0, 9, 0, .walking), seg(19, 9, 0, 15, 0, .stationary)])
        let a = DailyRingLayout.makeDots(density: DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar), seed: 20260919)
        let b = DailyRingLayout.makeDots(density: DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar), seed: 20260919)
        XCTAssertEqual(a, b)
        let c = DailyRingLayout.makeDots(density: DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar), seed: 20260920)
        XCTAssertNotEqual(a, c, "日付(seed)が違えば配置も変わる")
    }

    // MARK: - 連続性（密度が急に変わらない）

    func testSmoothingLimitsJumpBetweenNeighboringSlices() {
        // 0→1に急変する段差でも、隣り合うスライス間の差は0.25以下になる。
        var step = [Double](repeating: 0, count: 60)
        for i in 30..<60 { step[i] = 1 }
        let smoothed = DailyRingLayout.smooth(step, periodic: false)
        var maxJump = 0.0
        for i in 1..<smoothed.count { maxJump = max(maxJump, abs(smoothed[i] - smoothed[i - 1])) }
        XCTAssertLessThanOrEqual(maxJump, 0.25 + 1e-9)
        XCTAssertGreaterThan(maxJump, 0)
        // 値の範囲は保たれる
        XCTAssertGreaterThanOrEqual(smoothed.min()!, 0)
        XCTAssertLessThanOrEqual(smoothed.max()!, 1 + 1e-9)
        // 段差から遠い所は元の値のまま（にじみは前後20分に限る）
        XCTAssertEqual(smoothed[10], 0, accuracy: 1e-9)
        XCTAssertEqual(smoothed[50], 1, accuracy: 1e-9)
    }

    func testDensityIsContinuousAcrossActivityChangesAndMidnight() {
        // 過去日: 23:30〜24:00は歩行、0:00〜は静止 → 0時と24時のつなぎ目でも密度が急に変わらない。
        let now = date(2026, 9, 19, 9, 0)
        let day = date(2026, 9, 18)
        let data = makeData(day: day, hourlySteps: steps([23: 3000]), segments: [
            seg(18, 0, 0, 12, 0, .stationary), seg(18, 12, 0, 12, 30, .automotive), seg(18, 12, 30, 23, 30, .stationary),
            ActivitySegment(start: date(2026, 9, 18, 23, 30), end: date(2026, 9, 19, 0, 0), kind: .walking)
        ])
        let density = DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar)
        XCTAssertTrue(density.isPeriodic)
        for kind in DailyRingLayout.ringOrder {
            let values = density.smoothed[kind]!
            XCTAssertEqual(values.count, 288)
            for i in 0..<values.count {
                let next = values[(i + 1) % values.count] // 最後の次は先頭（0時と24時のつなぎ目）
                XCTAssertLessThanOrEqual(abs(next - values[i]), 0.25 + 1e-9, "\(kind)の密度が\(i)番目のスライス付近で急に変わっている")
            }
        }
    }

    func testPartialDayHasNoSmoothingBeyondTheEnd() {
        let now = date(2026, 9, 19, 3, 0)
        let data = makeData(day: now, segments: [seg(19, 0, 0, 3, 0, .stationary)])
        let density = DailyRingLayout.makeDensity(data: data, now: now, calendar: calendar)
        XCTAssertEqual(density.smoothed[.stationary]?.count, 36)
        // 最後のスライスまで密度1のまま（端で薄れて欠けない）
        XCTAssertEqual(density.smoothed[.stationary]?.last ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(density.smoothed[.stationary]?.first ?? 0, 1, accuracy: 1e-9)
    }

    // MARK: - 画像生成（クラッシュしないこと・大きさ）

    private func sampleDensity() -> DailyRingDensity {
        let now = date(2026, 9, 19, 9, 0)
        let day = date(2026, 9, 18)
        let hourly = [0, 0, 0, 0, 0, 0, 200, 3500, 4200, 300, 0, 0, 1500, 800, 0, 0, 0, 6000, 2500, 0, 0, 0, 0, 0]
        let segments = [
            seg(18, 0, 0, 7, 0, .stationary),
            seg(18, 7, 0, 9, 0, .walking),
            seg(18, 9, 0, 9, 40, .automotive),
            seg(18, 9, 40, 12, 0, .stationary),
            seg(18, 12, 0, 12, 40, .walking),
            seg(18, 12, 40, 17, 0, .stationary),
            seg(18, 17, 0, 18, 0, .running),
            seg(18, 18, 0, 19, 0, .cycling),
            seg(18, 19, 0, 23, 59, .stationary)
        ]
        return DailyRingLayout.makeDensity(data: makeData(day: day, hourlySteps: hourly, segments: segments), now: now, calendar: calendar)
    }

    func testRendererProducesImageOfRequestedSize() {
        let image = DailyRingRenderer.render(density: sampleDensity(), date: date(2026, 9, 18), size: 160, calendar: calendar)
        XCTAssertEqual(image.size.width * image.scale, 160, accuracy: 0.5)
        XCTAssertEqual(image.size.height * image.scale, 160, accuracy: 0.5)

        // 今日の途中・データが空でも描ける
        let now = date(2026, 9, 19, 9, 0)
        let empty = DailyRingLayout.makeDensity(data: makeData(day: now), now: now, calendar: calendar)
        let todayImage = DailyRingRenderer.render(density: empty, date: now, size: 160, calendar: calendar)
        XCTAssertEqual(todayImage.size.width * todayImage.scale, 160, accuracy: 0.5)
    }

    /// 見た目の確認用: 環境変数 RING_SAMPLE_DIR が指定されているときだけ、サンプル画像(1080px)をPNGで書き出す
    /// （GitHub Actionsで画像をArtifactとして受け取り、目視確認するため。通常のテストでは何もしない）。
    func testWriteSampleImagesWhenRequested() throws {
        guard let dir = ProcessInfo.processInfo.environment["RING_SAMPLE_DIR"], !dir.isEmpty else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let pastImage = DailyRingRenderer.render(density: sampleDensity(), date: date(2026, 9, 18), size: 1080, calendar: calendar)
        try pastImage.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ring-past-full-day.png"))

        let now = date(2026, 9, 19, 14, 20)
        let hourly = [0, 0, 0, 0, 0, 0, 150, 3200, 4300, 600, 0, 0, 1800, 900, 200, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let segments = [
            seg(19, 0, 0, 6, 45, .stationary),
            seg(19, 6, 45, 7, 0, .walking),
            seg(19, 7, 0, 9, 0, .walking),
            seg(19, 9, 0, 9, 45, .automotive),
            seg(19, 9, 45, 12, 0, .stationary),
            seg(19, 12, 0, 13, 0, .running),
            seg(19, 13, 0, 13, 30, .walking),
            seg(19, 13, 30, 14, 20, .stationary)
        ]
        let density = DailyRingLayout.makeDensity(data: makeData(day: now, hourlySteps: hourly, segments: segments), now: now, calendar: calendar)
        let todayImage = DailyRingRenderer.render(density: density, date: now, size: 1080, calendar: calendar)
        try todayImage.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ring-today-partial.png"))
    }
}
