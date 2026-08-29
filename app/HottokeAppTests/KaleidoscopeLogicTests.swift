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

    /// 実機フィードバック対応: 動画終盤で模様が震えるようにガタガタする不具合の再発防止テスト。
    /// 活動区間が頻繁に切り替わる（短い区間が10個以上連続する）ダミーデータを与えても、
    /// KaleidoscopeVideoExporter.buildParametersTimeline が返すフレームごとのパラメータ
    /// （回転速度・density系パラメータ・回転角）がフレーム間で滑らかに変化することを確認する。
    func testVideoParametersStaySmoothAcrossFrequentActivitySwitches() {
        let calendar = Calendar(identifier: .gregorian)
        var startOfDay = calendar.startOfDay(for: Date())
        // 一応、活動データの開始を少し朝側にずらしておく（0時ちょうど固有の丸め誤差を避ける）。
        startOfDay = startOfDay.addingTimeInterval(6 * 3600)

        // 「静止」と「走行」を10分刻みで14回、交互に切り替える短い区間を作る。
        // rotationSpeedはstationary(0.06)とrunning(0.5)で約8倍差があり、これが動画の
        // 各所（タイムライン圧縮の都合で動画終盤に集中しやすい）でフレームごとに切り替わる。
        var segments: [ActivitySegment] = []
        var cursor = startOfDay
        for i in 0..<14 {
            let kind: ActivityKind = i % 2 == 0 ? .stationary : .running
            let next = cursor.addingTimeInterval(10 * 60)
            segments.append(ActivitySegment(start: cursor, end: next, kind: kind))
            cursor = next
        }

        let data = DailyActivityData(
            date: startOfDay,
            segments: segments,
            stepCount: 8000,
            distanceMeters: 5000,
            floorsAscended: 5,
            floorAscendTimes: []
        )

        let fps: Int32 = 24
        let duration: Double = 28
        let frameCount = Int(duration * Double(fps))
        let keyframes = KaleidoscopeTimelineBuilder.buildKeyframes(from: data, frameCount: frameCount)
        XCTAssertEqual(keyframes.count, frameCount)

        // 区間境界が実際にフレーム単位で複数回切り替わっていることを確認しておく
        // （このテストが意味のある入力になっているかの前提チェック）。
        var switchCount = 0
        for index in 1..<keyframes.count where keyframes[index].activityKind != keyframes[index - 1].activityKind {
            switchCount += 1
        }
        XCTAssertGreaterThanOrEqual(switchCount, 10, "テストデータの活動区間の切り替わりが少なすぎます")

        let timeline = KaleidoscopeVideoExporter.buildParametersTimeline(
            keyframes: keyframes,
            data: data,
            seed: 1,
            duration: duration,
            fps: fps,
            patternStyle: .fractal
        )
        XCTAssertEqual(timeline.count, frameCount)

        // 平滑化前（生の活動区間由来の値）なら、区間境界の前後1フレームだけで
        // rotationSpeedが0.06→0.5（差0.44）のように瞬時にジャンプしうる。
        // 平滑化後はどの隣接フレーム間でもその何分の1かに収まっているはず。
        let rawRotationSpeeds = keyframes.map { ActivityStyle.style(for: $0.activityKind).rotationSpeed }
        let maxRawJump = maxAdjacentAbsoluteDifference(rawRotationSpeeds)
        XCTAssertGreaterThan(maxRawJump, 0.3, "テストデータ自体に急激なrotationSpeedの変化がない")

        let smoothedRotationSpeeds = timeline.map(\.rotationSpeed)
        let maxSmoothedJump = maxAdjacentAbsoluteDifference(smoothedRotationSpeeds)
        XCTAssertLessThan(maxSmoothedJump, maxRawJump / 4, "rotationSpeedが平滑化されずフレーム間で急変している")

        let deformations = timeline.map(\.deformationIntensity)
        XCTAssertLessThan(maxAdjacentAbsoluteDifference(deformations), 0.15, "deformationIntensity(密度)がフレーム間で急変している")

        let noiseAmounts = timeline.map(\.noiseAmount)
        XCTAssertLessThan(maxAdjacentAbsoluteDifference(noiseAmounts), 0.05, "noiseAmountがフレーム間で急変している")

        // 回転角そのものも、隣接フレーム間の増分（＝そのフレームでの実質的な角速度）が
        // さらにその前の増分から急激にジャンプしないことを確認する。
        // 角速度が一定という前提の閉じた式をそのまま使っていた旧実装では、activityKindが
        // 切り替わった瞬間にこの増分が数倍〜十数倍ジャンプしうる。
        let rotations = timeline.map(\.rotation)
        var steps: [Double] = []
        steps.reserveCapacity(rotations.count - 1)
        for index in 1..<rotations.count {
            steps.append(rotations[index] - rotations[index - 1])
        }
        let maxStepJump = maxAdjacentAbsoluteDifference(steps)
        XCTAssertLessThan(maxStepJump, 0.02, "回転角の増分（フレームごとの実質角速度）が急変しており、震えの原因になりうる")
    }

    /// 隣接する要素同士の絶対差の最大値（フレーム間の急変=ジャンプがないかを見るのに使う）。
    private func maxAdjacentAbsoluteDifference(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        var maxDiff = 0.0
        for index in 1..<values.count {
            maxDiff = max(maxDiff, abs(values[index] - values[index - 1]))
        }
        return maxDiff
    }

    /// 実機フィードバック対応: 「同じスタイルだとほぼ同じ動画になる」不具合の再発防止テスト。
    /// 以前はKaleidoscopeParameters.seedがどの描画関数にも渡されておらず、模様の形は
    /// (R, t, detail, symmetryCount)だけで決まっていた。そのため同じ活動データ・同じ時刻
    /// なら日をまたいでもピクセル単位でほぼ同じ模様になっていた。
    /// ここでは同一の(size, symmetryCount, palette, time, detail, patternStyle)のまま
    /// seedだけを変えて描画し、生成されるビットマップのピクセルデータが異なることを
    /// 4スタイルすべてで確認する。
    func testDifferentSeedProducesDifferentPatternForEachStyle() {
        let size = CGSize(width: 240, height: 240)

        for style in [PatternStyle.tiling, .spirograph, .waves, .fractal] {
            var parametersA = KaleidoscopeParameters()
            parametersA.symmetryCount = 8
            parametersA.patternStyle = style
            parametersA.time = 3.0
            parametersA.detail = 0.6
            parametersA.seed = 111

            var parametersB = parametersA
            parametersB.seed = 999

            let pixelsA = renderedPixelData(size: size, parameters: parametersA)
            let pixelsB = renderedPixelData(size: size, parameters: parametersB)

            XCTAssertNotNil(pixelsA, "\(style): 描画に失敗しました")
            XCTAssertNotNil(pixelsB, "\(style): 描画に失敗しました")
            XCTAssertNotEqual(pixelsA, pixelsB, "\(style): seedを変えても模様のピクセルが変化しませんでした")
        }
    }

    /// KaleidoscopeRenderer.renderを実行し、結果のCGContextからピクセルデータ(Data)を取り出す。
    private func renderedPixelData(size: CGSize, parameters: KaleidoscopeParameters) -> Data? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        KaleidoscopeRenderer.render(into: context, size: size, parameters: parameters)

        guard let data = context.data else { return nil }
        return Data(bytes: data, count: context.bytesPerRow * context.height)
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
