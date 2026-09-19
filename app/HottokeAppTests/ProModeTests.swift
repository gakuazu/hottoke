import XCTest
@testable import HottokeApp

/// プロモード（ProAccess）、配色テーマ、積算、振り返りレポート、書き出しサイズのテスト。
final class ProModeTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func date(_ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))!
    }

    /// 分の区切りで指定して1日分の記録を作る。歩行=95歩/分、ランニング=160歩/分で歩数を割り当てる。
    private func dayRecord(_ d: Int, _ blocks: [(Int, Int, ActivityKind)], now: Date? = nil) -> DailyRingSlices {
        let start = date(d)
        var segments: [ActivitySegment] = []
        var hourly = [Int](repeating: 0, count: 24)
        for (a, b, kind) in blocks {
            segments.append(ActivitySegment(start: start.addingTimeInterval(Double(a) * 60), end: start.addingTimeInterval(Double(b) * 60), kind: kind))
            let rate = kind == .walking ? 95 : (kind == .running ? 160 : 0)
            for minute in a..<b { hourly[min(23, minute / 60)] += rate }
        }
        let data = DailyActivityData(date: start, segments: segments, stepCount: hourly.reduce(0, +), distanceMeters: 0, floorsAscended: 0, floorAscendTimes: [], hourlySteps: hourly)
        return DailyRingLayout.makeSlices(data: data, now: now ?? date(d + 1, 9), calendar: calendar)
    }

    // MARK: - ProAccess

    func testProModeDefaultsToOnAndCanBeToggled() {
        let suite = UserDefaults(suiteName: "hottoke-test-\(UUID().uuidString)")!
        XCTAssertTrue(ProAccess.defaultEnabled, "このビルド（家族用）の既定はオン")
        XCTAssertTrue(ProAccess.isEnabled(defaults: suite))
        suite.set(false, forKey: ProAccess.storageKey)
        XCTAssertFalse(ProAccess.isEnabled(defaults: suite))
        suite.set(true, forKey: ProAccess.storageKey)
        XCTAssertTrue(ProAccess.isEnabled(defaults: suite))
    }

    func testEveryFeatureFollowsTheSwitchAndLockedMessageNamesTheFeature() {
        for feature in ProFeature.allCases {
            XCTAssertTrue(ProAccess.isUnlocked(feature, enabled: true))
            XCTAssertFalse(ProAccess.isUnlocked(feature, enabled: false))
            XCTAssertTrue(ProAccess.lockedMessage(for: feature).contains(feature.displayName))
            XCTAssertFalse(feature.summary.isEmpty)
        }
        XCTAssertEqual(ProFeature.allCases.count, 5)
    }

    // MARK: - 配色テーマ

    func testEveryThemeHasSixDistinctKindColorsAndABackground() {
        XCTAssertGreaterThanOrEqual(RingTheme.allCases.count, 5)
        for theme in RingTheme.allCases {
            let kinds = DailyRingLayout.kindOrder
            for i in 0..<kinds.count {
                for j in (i + 1)..<kinds.count {
                    XCTAssertNotEqual(theme.color(for: kinds[i]), theme.color(for: kinds[j]), "\(theme.displayName)で\(kinds[i])と\(kinds[j])が同じ色")
                }
            }
            let bg = theme.background
            XCTAssertLessThan(bg.base.r + bg.base.g + bg.base.b, 0.2, "背景は暗い色")
            XCTAssertFalse(theme.displayName.isEmpty)
        }
        XCTAssertEqual(RingTheme.standard.color(for: .walking), DailyRingLayout.ringColor(for: .walking))
        // テーマどうしで色が違う
        XCTAssertNotEqual(RingTheme.aurora.color(for: .walking), RingTheme.standard.color(for: .walking))
    }

    /// 活動ごとの色は、どのテーマでも互いに十分離れている（同色系にならない）。
    func testKindColorsAreFarApartInEveryTheme() {
        for theme in RingTheme.allCases {
            let kinds = DailyRingLayout.kindOrder
            var minDistance = Double.infinity
            for i in 0..<kinds.count {
                for j in (i + 1)..<kinds.count {
                    let d = theme.color(for: kinds[i]).perceptualDistance(to: theme.color(for: kinds[j]))
                    minDistance = min(minDistance, d)
                    XCTAssertGreaterThanOrEqual(d, 30, "\(theme.displayName)の\(kinds[i].displayName)と\(kinds[j].displayName)の色が近い(ΔE=\(d))")
                }
            }
            XCTAssertGreaterThanOrEqual(minDistance, 30)
            // 睡眠は静止より十分に暗い（明度差でも区別できる）
            XCTAssertGreaterThan(theme.color(for: .stationary).lab.l - theme.color(for: .sleeping).lab.l, 20, "\(theme.displayName)で睡眠が暗くない")
        }
    }

    func testPerceptualDistanceBasics() {
        let white = RingRGB(r: 1, g: 1, b: 1), black = RingRGB(r: 0, g: 0, b: 0)
        XCTAssertEqual(white.lab.l, 100, accuracy: 0.5)
        XCTAssertEqual(black.lab.l, 0, accuracy: 0.5)
        XCTAssertEqual(white.perceptualDistance(to: white), 0, accuracy: 1e-9)
        XCTAssertEqual(white.perceptualDistance(to: black), 100, accuracy: 1)
        XCTAssertEqual(white.perceptualDistance(to: black), black.perceptualDistance(to: white), accuracy: 1e-9)
    }

    func testThemeIsLockedToStandardWhenProIsOff() {
        XCTAssertEqual(RingTheme.effective(rawValue: "aurora", proEnabled: true), .aurora)
        XCTAssertEqual(RingTheme.effective(rawValue: "aurora", proEnabled: false), .standard)
        XCTAssertEqual(RingTheme.effective(rawValue: "unknown-theme", proEnabled: true), .standard)
    }

    // MARK: - 積算

    func testAggregateAveragesIntensityAndMixesColorsByDayShare() {
        // 4日のうち、10:00〜11:00に歩いたのは1日だけ。あとの3日は静止。
        var records = [dayRecord(10, [(600, 660, .walking), (0, 600, .stationary), (660, 1440, .stationary)])]
        for d in 11...13 { records.append(dayRecord(d, [(0, 1440, .stationary)])) }
        let single = DailyRingLayout.makeDensity(slices: records[0])
        let agg = DailyRingLayout.aggregate(records)
        XCTAssertEqual(agg.sliceCount, 288)
        XCTAssertTrue(agg.isPeriodic)
        let i = 10 * 12 + 6 // 10:30
        XCTAssertEqual(agg.rawIntensity[i], single.rawIntensity[i] / 4, accuracy: 1e-9, "強さは日数で平均")
        XCTAssertEqual(agg.rawWeights[.walking]![i], 0.25, accuracy: 1e-9, "歩いた日の割合が色の割合")
        XCTAssertEqual(agg.rawWeights[.stationary]![i], 0.75, accuracy: 1e-9)
        // よく歩く時刻ほど半径が大きい
        let allWalk = (10...13).map { dayRecord($0, [(0, 600, .stationary), (600, 660, .walking), (660, 1440, .stationary)]) }
        XCTAssertGreaterThan(DailyRingLayout.aggregate(allWalk).outerRadius(at: 10.5), agg.outerRadius(at: 10.5))
    }

    func testAggregateOfOneDayEqualsThatDayAndHandlesPartialToday() {
        let day = dayRecord(12, [(0, 360, .sleeping), (360, 400, .walking), (400, 1440, .stationary)])
        let one = DailyRingLayout.aggregate([day])
        let direct = DailyRingLayout.makeDensity(slices: day)
        XCTAssertEqual(one.rawIntensity, direct.rawIntensity)
        XCTAssertEqual(one.smoothedDensity, direct.smoothedDensity)

        // 今日の途中(9時まで)の記録が混ざっても、9時より先は他の日だけで平均する
        let partial = dayRecord(13, [(0, 360, .sleeping), (360, 540, .walking)], now: date(13, 9))
        XCTAssertFalse(partial.isComplete)
        let mixed = DailyRingLayout.aggregate([day, partial])
        XCTAssertEqual(mixed.sliceCount, 288)
        XCTAssertEqual(mixed.rawDensity[20 * 12], direct.rawDensity[20 * 12], accuracy: 1e-9)
        XCTAssertTrue(DailyRingLayout.aggregate([]).smoothedRadius.isEmpty)
    }

    func testAggregateIsContinuousAcrossMidnight() {
        let records = (10...16).map { d in dayRecord(d, [(0, 420, .sleeping), (420, 460 + d, .walking), (460 + d, 1380, .stationary), (1380, 1440, .sleeping)]) }
        let agg = DailyRingLayout.aggregate(records)
        let n = agg.sliceCount
        for i in 0..<n {
            let j = (i + 1) % n
            XCTAssertLessThanOrEqual(abs(agg.smoothedRadius[j] - agg.smoothedRadius[i]), 0.25 + 1e-9)
            XCTAssertLessThanOrEqual(abs(agg.smoothedDensity[j] - agg.smoothedDensity[i]), 0.25 + 1e-9)
        }
    }

    // MARK: - 振り返りレポート

    func testPeriodReportTotalsAndBusiest() {
        let now = date(19, 20)
        let records = [
            dayRecord(15, [(0, 420, .sleeping), (420, 450, .walking), (450, 1440, .stationary)]),                       // 7:00台 30分
            dayRecord(17, [(0, 420, .sleeping), (1080, 1140, .running), (1140, 1440, .stationary), (420, 1080, .stationary)]), // 18:00台 ランニング60分
            dayRecord(19, [(0, 400, .sleeping), (400, 1200, .stationary)], now: now)
        ]
        let week = PeriodReport.make(records: records, period: .week, now: now, calendar: calendar)
        XCTAssertEqual(week.startKey, "2026-09-13")
        XCTAssertEqual(week.endKey, "2026-09-19")
        XCTAssertEqual(week.savedDays, 3)
        XCTAssertEqual(week.totalSteps, records.reduce(0) { $0 + $1.totalSteps })
        XCTAssertEqual(week.busiestDayKey, "2026-09-17")
        XCTAssertEqual(week.busiestHour, 18)
        XCTAssertEqual(week.minutes(.running), 60, accuracy: 0.1)
        XCTAssertEqual(week.minutes(.walking), 30, accuracy: 0.1)
        XCTAssertGreaterThan(week.minutes(.sleeping), 1000)
        XCTAssertEqual(week.averageStepsPerSavedDay, week.totalSteps / 3)

        // 週に入らない古い日は含めない
        let old = [dayRecord(1, [(0, 1440, .stationary)])]
        XCTAssertEqual(PeriodReport.make(records: old, period: .week, now: now, calendar: calendar).savedDays, 0)
        XCTAssertNil(PeriodReport.make(records: old, period: .week, now: now, calendar: calendar).busiestDayKey)
        // 1ヶ月には入る
        XCTAssertEqual(PeriodReport.make(records: old + records, period: .month, now: now, calendar: calendar).savedDays, 4)
    }

    func testReportFormattingHelpers() {
        XCTAssertEqual(ReportRenderer.formatMinutes(0), "0分")
        XCTAssertEqual(ReportRenderer.formatMinutes(45), "45分")
        XCTAssertEqual(ReportRenderer.formatMinutes(120), "2時間")
        XCTAssertEqual(ReportRenderer.formatMinutes(200), "3時間20分")
        XCTAssertEqual(ReportRenderer.formatNumber(12345), "12,345")
        XCTAssertEqual(RingPeriod.week.days, 7)
        XCTAssertEqual(RingPeriod.month.days, 30)
        XCTAssertEqual(RingPeriod.today.days, 1)
    }

    func testReportRendersWithAggregateRingAtRequestedScale() {
        let now = date(19, 20)
        let records = (13...18).map { d in dayRecord(d, [(0, 420, .sleeping), (420, 460, .walking), (460, 1440, .stationary)]) }
        let report = PeriodReport.make(records: records, period: .week, now: now, calendar: calendar)
        let image = ReportRenderer.render(report: report, records: records, theme: .aurora, scale: 0.25)
        XCTAssertEqual(image.size.width * image.scale, ReportRenderer.canvasSize.width * 0.25, accuracy: 1)
        XCTAssertEqual(image.size.height * image.scale, ReportRenderer.canvasSize.height * 0.25, accuracy: 1)
    }

    // MARK: - 書き出しサイズ

    func testExportSizes() {
        let screen = CGSize(width: 1290, height: 2796)
        XCTAssertEqual(RingExportSize.standard.canvas(screenPixels: screen), CGSize(width: 1080, height: 1080))
        XCTAssertEqual(RingExportSize.high.canvas(screenPixels: screen), CGSize(width: 2160, height: 2160))
        let wall = RingExportSize.wallpaper.canvas(screenPixels: screen)
        XCTAssertEqual(wall, screen)
        // 横向きの値が渡されても縦長にする
        XCTAssertEqual(RingExportSize.wallpaper.canvas(screenPixels: CGSize(width: 2796, height: 1290)), screen)
        XCTAssertEqual(wall.width / wall.height, 1290.0 / 2796.0, accuracy: 1e-6, "画面の比率のまま")
        XCTAssertFalse(RingExportSize.standard.requiresPro)
        XCTAssertTrue(RingExportSize.high.requiresPro)
        XCTAssertTrue(RingExportSize.wallpaper.requiresPro)
    }

    func testRendererSupportsNonSquareCanvasThemesAndGhost() {
        let records = (10...12).map { dayRecord($0, [(0, 420, .sleeping), (420, 480, .walking), (480, 1440, .stationary)]) }
        let density = DailyRingLayout.makeDensity(slices: records[0])
        var options = RingRenderOptions(canvas: CGSize(width: 180, height: 390))
        options.chrome = .art
        options.theme = .nightSky
        options.ghost = DailyRingLayout.aggregate(records)
        options.ringCenter = CGPoint(x: 90, y: 210)
        let image = DailyRingRenderer.render(density: density, date: date(10), options: options, calendar: calendar)
        XCTAssertEqual(image.size.width * image.scale, 180, accuracy: 0.5)
        XCTAssertEqual(image.size.height * image.scale, 390, accuracy: 0.5)
        for theme in RingTheme.allCases {
            let thumb = DailyRingRenderer.renderThumbnail(slices: records[0], size: 60, theme: theme)
            XCTAssertEqual(thumb.size.width, 60, accuracy: 0.5)
        }
    }
}
