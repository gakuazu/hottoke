import CoreGraphics

/// 扇形1つ分の模様を生成する。
///
/// docs/03b-visual-prototype-learnings.md「対称性の実装」の重要な注意点:
/// 生成する模様の角度は必ず扇形の角度幅（2π/n）に収める。全方向にランダム配置すると、
/// 対称数分の1しか実際には表示されず、残りは描画コストだけ払って画面に出ない無駄が発生するため。
enum KaleidoscopeShapeGenerator {

    static func generateWedge(symmetryCount: Int, seed: UInt64, density: Double, deformation: Double) -> WedgePattern {
        let n = max(3, symmetryCount)
        let wedgeAngle = CGFloat(2 * Double.pi / Double(n))
        var rng = SeededGenerator(seed: seed)

        let clampedDensity = min(1, max(0, density))
        let clampedDeformation = min(1, max(0, deformation))

        let facetCount = 3 + Int(clampedDensity * 4)
        let shardCount = 18 + Int(clampedDensity * 46)
        let rayCount = 4 + Int(clampedDensity * 6)
        let sparkCount = 10 + Int(clampedDensity * 30)

        func randomAngleWithinWedge() -> CGFloat {
            // 必ず [0, wedgeAngle) の範囲に収める。
            CGFloat.random(in: 0..<wedgeAngle, using: &rng)
        }

        // 大きめの「面」で色の基調を作る。
        let facets: [GlassShard] = (0..<facetCount).map { _ in
            GlassShard(
                radius: CGFloat.random(in: 0.1...0.95, using: &rng),
                angle: randomAngleWithinWedge(),
                size: CGFloat.random(in: 0.22...0.4, using: &rng) * (1 + CGFloat(clampedDeformation) * 0.3),
                rotation: CGFloat.random(in: 0...(2 * .pi), using: &rng),
                colorIndex: Int.random(in: 0..<6, using: &rng),
                shape: .diamond
            )
        }

        // 大量の小さな「シャード」で密度を出す。
        let shards: [GlassShard] = (0..<shardCount).map { _ in
            GlassShard(
                radius: CGFloat.random(in: 0.05...1.0, using: &rng),
                angle: randomAngleWithinWedge(),
                size: CGFloat.random(in: 0.03...0.12, using: &rng) * (1 + CGFloat(clampedDeformation) * 0.5),
                rotation: CGFloat.random(in: 0...(2 * .pi), using: &rng),
                colorIndex: Int.random(in: 0..<6, using: &rng),
                shape: Bool.random(using: &rng) ? .diamond : .triangle
            )
        }

        // 中心から放射する細い「光の筋」。
        let rays: [LightRay] = (0..<rayCount).map { _ in
            LightRay(
                angle: randomAngleWithinWedge(),
                length: CGFloat.random(in: 0.5...1.0, using: &rng),
                width: CGFloat.random(in: 0.004...0.014, using: &rng)
            )
        }

        // 小さな輝き。
        let sparks: [Spark] = (0..<sparkCount).map { _ in
            Spark(
                radius: CGFloat.random(in: 0.05...1.0, using: &rng),
                angle: randomAngleWithinWedge(),
                size: CGFloat.random(in: 0.006...0.02, using: &rng)
            )
        }

        return WedgePattern(wedgeAngle: wedgeAngle, facets: facets, shards: shards, rays: rays, sparks: sparks)
    }
}
