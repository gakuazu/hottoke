import XCTest
@testable import HottokeApp

/// 睡眠の推定（夜間の長い静止 → 睡眠）のテスト。
final class SleepEstimatorTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    /// 9月`d`日の h:m
    private func t(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))!
    }

    private func seg(_ a: Date, _ b: Date, _ kind: ActivityKind) -> ActivitySegment {
        ActivitySegment(start: a, end: b, kind: kind)
    }

    private func run(_ segments: [ActivitySegment], from: Date, to: Date, steps: @escaping (Date) -> Int = { _ in 0 }) -> [ActivitySegment] {
        SleepEstimator.estimate(segments: segments, windowStart: from, windowEnd: to, stepsInHour: steps, calendar: calendar)
    }

    private func sleepingSeconds(_ segments: [ActivitySegment]) -> TimeInterval {
        segments.filter { $0.kind == .sleeping }.reduce(0) { $0 + $1.duration }
    }

    func testNightStationaryAcrossMidnightBecomesSleeping() {
        // 22:30〜翌6:30 静止（8時間）
        let segments = [seg(t(18, 12), t(18, 22, 30), .walking), seg(t(18, 22, 30), t(19, 6, 30), .stationary), seg(t(19, 6, 30), t(19, 9), .walking)]
        let result = run(segments, from: t(18, 12), to: t(19, 9))
        XCTAssertEqual(sleepingSeconds(result), 8 * 3600, accuracy: 1)
        XCTAssertEqual(result.filter { $0.kind == .walking }.count, 2, "睡眠以外の区間はそのまま残る")
    }

    func testShortNapOrDaytimeStationaryIsNotSleeping() {
        // 2時間だけ（3時間未満）
        XCTAssertEqual(sleepingSeconds(run([seg(t(18, 23), t(19, 1), .stationary)], from: t(18, 20), to: t(19, 3))), 0)
        // 昼間の長い静止（開始が14時）は対象外
        XCTAssertEqual(sleepingSeconds(run([seg(t(18, 14), t(18, 19), .stationary)], from: t(18, 12), to: t(18, 20))), 0)
    }

    func testStartAndEndTimeWindows() {
        // 開始が19:00（20時より前）→ 対象外
        XCTAssertEqual(sleepingSeconds(run([seg(t(18, 19), t(18, 23, 30), .stationary)], from: t(18, 18), to: t(18, 23, 59))), 0)
        // 開始が20:00ちょうど・6時間 → 睡眠
        XCTAssertEqual(sleepingSeconds(run([seg(t(18, 20), t(19, 2), .stationary)], from: t(18, 19), to: t(19, 3))), 6 * 3600, accuracy: 1)
        // 夜更かし（1:00〜9:00）でも睡眠扱い
        XCTAssertEqual(sleepingSeconds(run([seg(t(19, 1), t(19, 9), .stationary)], from: t(19, 0), to: t(19, 10))), 8 * 3600, accuracy: 1)
        // 終了が正午を過ぎる（22:00〜翌14:00）→ 対象外
        XCTAssertEqual(sleepingSeconds(run([seg(t(18, 22), t(19, 14), .stationary)], from: t(18, 21), to: t(19, 15))), 0)
    }

    func testShortInterruptionKeepsSleepAndKeepsTheInterruptionsKind() {
        // 23:00〜7:00 静止の途中、3:00〜3:10 に歩行（トイレ）
        let segments = [
            seg(t(18, 23), t(19, 3), .stationary), seg(t(19, 3), t(19, 3, 10), .walking), seg(t(19, 3, 10), t(19, 7), .stationary)
        ]
        let result = run(segments, from: t(18, 22), to: t(19, 8))
        XCTAssertEqual(sleepingSeconds(result), 8 * 3600 - 600, accuracy: 1)
        XCTAssertEqual(result.filter { $0.kind == .walking }.reduce(0) { $0 + $1.duration }, 600, accuracy: 1)
    }

    func testLongInterruptionSplitsTheSleep() {
        // 23:00〜1:00 静止、1:00〜2:00 歩行、2:00〜6:00 静止 → 前半2時間は短すぎて対象外、後半4時間のみ睡眠
        let segments = [seg(t(18, 23), t(19, 1), .stationary), seg(t(19, 1), t(19, 2), .walking), seg(t(19, 2), t(19, 6), .stationary)]
        let result = run(segments, from: t(18, 22), to: t(19, 7))
        XCTAssertEqual(sleepingSeconds(result), 4 * 3600, accuracy: 1)
    }

    func testHoursWithManyStepsAreExcluded() {
        // 23:00〜7:00 静止だが、2時台に600歩（動いていた）→ その1時間は対象外になり、前後に分割される
        let segments = [seg(t(18, 23), t(19, 7), .stationary)]
        let result = run(segments, from: t(18, 22), to: t(19, 8), steps: { hour in
            hour == self.t(19, 2) ? 600 : 0
        })
        // 23:00〜2:00（3時間）と 3:00〜7:00（4時間）が睡眠（2時台は対象外）。中断が1時間あるので、ひと続きにはならない。
        XCTAssertEqual(sleepingSeconds(result), 7 * 3600, accuracy: 1)
        XCTAssertTrue(result.contains { $0.kind == .stationary && $0.start == self.t(19, 2) })
    }

    func testOngoingSleepAtWindowEndAndIdempotence() {
        // 今が朝5時で、23:00からずっと静止 → 6時間が睡眠
        let segments = [seg(t(18, 23), t(19, 5), .stationary)]
        let result = run(segments, from: t(18, 20), to: t(19, 5))
        XCTAssertEqual(sleepingSeconds(result), 6 * 3600, accuracy: 1)
        // もう一度かけても同じ
        XCTAssertEqual(sleepingSeconds(run(result, from: t(18, 20), to: t(19, 5))), 6 * 3600, accuracy: 1)
        // 起きている間（歩行）は絶対に睡眠にならない
        XCTAssertEqual(sleepingSeconds(run([seg(t(18, 23), t(19, 7), .walking)], from: t(18, 22), to: t(19, 8))), 0)
    }

    func testClipKeepsOnlyTheDay() {
        let segments = [seg(t(18, 22), t(19, 6), .sleeping)]
        let clipped = SleepEstimator.clip(segments, from: t(19, 0), to: t(20, 0))
        XCTAssertEqual(clipped.count, 1)
        XCTAssertEqual(clipped[0].start, t(19, 0))
        XCTAssertEqual(clipped[0].end, t(19, 6))
    }
}
