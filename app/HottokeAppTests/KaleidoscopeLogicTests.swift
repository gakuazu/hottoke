import XCTest
@testable import HottokeApp

final class KaleidoscopeLogicTests: XCTestCase {

    func testTimeOfDayBoundaries() {
        XCTAssertEqual(TimeOfDay.of(hour: 0), .morning)
        XCTAssertEqual(TimeOfDay.of(hour: 9), .morning)
        XCTAssertEqual(TimeOfDay.of(hour: 10), .daytime)
        XCTAssertEqual(TimeOfDay.of(hour: 15), .daytime)
        XCTAssertEqual(TimeOfDay.of(hour: 16), .evening)
        XCTAssertEqual(TimeOfDay.of(hour: 18), .evening)
        XCTAssertEqual(TimeOfDay.of(hour: 19), .night)
        XCTAssertEqual(TimeOfDay.of(hour: 23), .night)
    }

    /// docs/03b-visual-prototype-learnings.md「対称性の実装」:
    /// 生成する模様の角度は必ず扇形の角度幅(2π/n)に収める、という制約の検証。
    func testWedgeShapesStayWithinWedgeAngle() {
        let symmetryCount = 10
        let pattern = KaleidoscopeShapeGenerator.generateWedge(
            symmetryCount: symmetryCount, seed: 42, density: 0.6, deformation: 0.4
        )
        let wedgeAngle = pattern.wedgeAngle
        XCTAssertEqual(Double(wedgeAngle), 2 * Double.pi / Double(symmetryCount), accuracy: 0.0001)

        for shard in pattern.facets + pattern.shards {
            XCTAssertGreaterThanOrEqual(shard.angle, 0)
            XCTAssertLessThan(shard.angle, wedgeAngle)
        }
        for ray in pattern.rays {
            XCTAssertGreaterThanOrEqual(ray.angle, 0)
            XCTAssertLessThan(ray.angle, wedgeAngle)
        }
        for spark in pattern.sparks {
            XCTAssertGreaterThanOrEqual(spark.angle, 0)
            XCTAssertLessThan(spark.angle, wedgeAngle)
        }
    }

    func testSameSeedProducesSamePattern() {
        let a = KaleidoscopeShapeGenerator.generateWedge(symmetryCount: 8, seed: 123, density: 0.5, deformation: 0.5)
        let b = KaleidoscopeShapeGenerator.generateWedge(symmetryCount: 8, seed: 123, density: 0.5, deformation: 0.5)
        XCTAssertEqual(a.shards.map(\.angle), b.shards.map(\.angle))
        XCTAssertEqual(a.shards.map(\.radius), b.shards.map(\.radius))
    }

    func testTimelineKeyframeCountMatchesRequest() {
        let now = Date()
        let data = DailyActivityData(
            date: now,
            segments: [ActivitySegment(start: now.addingTimeInterval(-3600), end: now, kind: .walking)],
            stepCount: 1000,
            distanceMeters: 700,
            floorsAscended: 2,
            floorAscendTimes: []
        )
        let frames = KaleidoscopeTimelineBuilder.buildKeyframes(from: data, frameCount: 50)
        XCTAssertEqual(frames.count, 50)
        XCTAssertEqual(frames.first?.position ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(frames.last?.position ?? -1, 1, accuracy: 0.0001)
    }

    /// docs/02-spec.md 7章の決定事項: データが少ない/ない場合も専用演出を作らず、
    /// 一貫したロジックで「静けさの模様」を生成する。
    func testEmptySegmentsStillProducesFallbackKeyframes() {
        let frames = KaleidoscopeTimelineBuilder.buildKeyframes(from: .empty, frameCount: 10)
        XCTAssertEqual(frames.count, 10)
        XCTAssertTrue(frames.allSatisfy { $0.activityKind == .stationary })
    }

    func testDominantMovingKindIgnoresStationary() {
        let now = Date()
        let data = DailyActivityData(
            date: now,
            segments: [
                ActivitySegment(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-3000), kind: .stationary),
                ActivitySegment(start: now.addingTimeInterval(-3000), end: now.addingTimeInterval(-2000), kind: .walking),
                ActivitySegment(start: now.addingTimeInterval(-2000), end: now, kind: .running)
            ],
            stepCount: 500,
            distanceMeters: 400,
            floorsAscended: 0,
            floorAscendTimes: []
        )
        XCTAssertEqual(data.dominantMovingKind, .running)
    }
}
