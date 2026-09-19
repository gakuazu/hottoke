import XCTest
@testable import HottokeApp

/// 日ごとの要約の保存・読み出し、サムネイルのキャッシュのテスト。
final class DailyHistoryTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func date(_ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))!
    }

    private func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hottoke-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func slices(day: Int, now: Date? = nil, walkingMinutes: Int = 30, steps: Int = 3000) -> DailyRingSlices {
        let start = date(day, 10)
        let data = DailyActivityData(
            date: date(day), segments: [
                ActivitySegment(start: date(day), end: start, kind: .sleeping),
                ActivitySegment(start: start, end: start.addingTimeInterval(Double(walkingMinutes) * 60), kind: .walking)
            ],
            stepCount: steps, distanceMeters: 0, floorsAscended: 0, floorAscendTimes: [],
            hourlySteps: { var h = Array(repeating: 0, count: 24); h[10] = steps; return h }()
        )
        return DailyRingLayout.makeSlices(data: data, now: now ?? date(day + 1, 9), calendar: calendar)
    }

    func testSlicesSummarizeMinutesAndSteps() {
        let s = slices(day: 18)
        XCTAssertEqual(s.dateKey, "2026-09-18")
        XCTAssertEqual(s.sliceCount, 288)
        XCTAssertTrue(s.isComplete)
        XCTAssertEqual(s.minutes(.walking), 30, accuracy: 0.1)
        XCTAssertEqual(s.minutes(.sleeping), 600, accuracy: 0.1)
        XCTAssertEqual(s.totalSteps, 3000)
        XCTAssertEqual(s.hourlySteps.count, 24)
        XCTAssertTrue(s.hasAnyData)
    }

    func testPartialDayIsNotComplete() {
        let s = slices(day: 19, now: date(19, 14, 20))
        XCTAssertFalse(s.isComplete)
        XCTAssertEqual(s.drawnHours, 14 + 20.0 / 60, accuracy: 1e-9)
        XCTAssertEqual(s.sliceCount, Int(ceil((14 + 20.0 / 60) * 12)))
    }

    func testSaveAndLoadRoundTrip() throws {
        let dir = tempDirectory()
        let store = DailyHistoryStore(directory: dir)
        let a = slices(day: 17), b = slices(day: 18)
        store.save(a)
        store.save(b)
        XCTAssertEqual(store.savedDayCount, 2)
        XCTAssertEqual(store.oldestDateKey, "2026-09-17")

        let reopened = DailyHistoryStore(directory: dir)
        XCTAssertEqual(reopened.record(forKey: "2026-09-17"), a)
        XCTAssertEqual(reopened.record(for: date(18), calendar: calendar), b)
        // 保存し直した記録から作った密度は、元と同じ
        let d1 = DailyRingLayout.makeDensity(slices: a)
        let d2 = DailyRingLayout.makeDensity(slices: reopened.record(forKey: "2026-09-17")!)
        XCTAssertEqual(d1.smoothedIntensity, d2.smoothedIntensity)
        XCTAssertEqual(d1.smoothedDensity, d2.smoothedDensity)
    }

    func testEmptyRecordDoesNotOverwriteGoodRecord() {
        let store = DailyHistoryStore(directory: tempDirectory())
        let good = slices(day: 18)
        store.save(good)
        let empty = DailyRingLayout.makeSlices(
            data: DailyActivityData(date: date(18), segments: [], stepCount: 0, distanceMeters: 0, floorsAscended: 0, floorAscendTimes: []),
            now: date(19, 9), calendar: calendar
        )
        XCTAssertFalse(empty.hasAnyData)
        store.save(empty)
        XCTAssertEqual(store.record(forKey: "2026-09-18"), good)
    }

    func testRecentRecordsAndRefreshRules() {
        let store = DailyHistoryStore(directory: tempDirectory())
        for d in 10...19 { store.save(slices(day: d, now: d == 19 ? date(19, 12) : date(d + 1, 9))) }
        let now = date(19, 12)
        let week = store.recentRecords(days: 7, endingAt: now, calendar: calendar)
        XCTAssertEqual(week.map { $0.dateKey }.first, "2026-09-13")
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(store.recentRecords(days: 30, endingAt: now, calendar: calendar).count, 10, "保存がある日だけ")

        // 今日・昨日は毎回取り直し。それ以前は、完全な保存があれば取り直さない。
        XCTAssertTrue(store.needsRefresh(offset: 0, day: date(19), calendar: calendar))
        XCTAssertTrue(store.needsRefresh(offset: 1, day: date(18), calendar: calendar))
        XCTAssertFalse(store.needsRefresh(offset: 3, day: date(16), calendar: calendar))
        XCTAssertTrue(store.needsRefresh(offset: 5, day: date(1), calendar: calendar), "保存がない日は取得する")
    }

    func testThumbnailIsCachedAndRebuiltWhenContentChanges() throws {
        let dir = tempDirectory()
        let store = RingThumbnailStore(directory: dir)
        let a = slices(day: 18)
        let image = store.thumbnail(themeKey: "standard", slices: a)
        XCTAssertEqual(image.size.width * image.scale, RingThumbnailStore.thumbnailSize, accuracy: 0.5)
        var files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.count, 1)
        // 同じ内容ならキャッシュを使う（ファイルが増えない）
        _ = store.thumbnail(themeKey: "standard", slices: a)
        files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.count, 1)
        // 内容が変わったら作り直し、古いキャッシュは消える
        let changed = slices(day: 18, walkingMinutes: 45, steps: 4500)
        XCTAssertNotEqual(changed.signature, a.signature)
        _ = store.thumbnail(themeKey: "standard", slices: changed)
        files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].contains(changed.signature))
    }
}
