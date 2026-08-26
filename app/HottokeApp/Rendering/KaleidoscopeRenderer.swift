import CoreGraphics

/// 万華鏡模様のCoreGraphicsレンダラー。
///
/// 手動モードのライブプレビュー（KaleidoscopeCanvasView）と、「今日の模様」動画の
/// フレーム書き出し（KaleidoscopeVideoExporter）の両方から呼ばれる共通のコア実装。
///
/// docs/03b-visual-prototype-learnings.md「対称性の実装」の2つの重要ルールを実装する:
///  1. 扇形（wedge）の中身は毎フレーム1回だけオフスクリーンのビットマップに描画し、
///     それを画像として対称数の回数だけ「スタンプ」する（個々の形状を対称数×形状数ぶん
///     毎回描き直すと重くなるため）。
///  2. 偶数番目・奇数番目の扇形は、単純な上下反転ではなく「扇形自身の中心線（二等分線）を
///     軸にした反転」にする。軸を間違えると隣の扇形の範囲にずれて重なり、対称数の半分しか
///     埋まらない不具合になる。
enum KaleidoscopeRenderer {

    static func render(into context: CGContext, size: CGSize, parameters: KaleidoscopeParameters) {
        guard size.width > 0, size.height > 0 else { return }

        let n = max(3, parameters.symmetryCount)
        let wedgeAngle = CGFloat(2 * Double.pi / Double(n))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2

        // 背景: ベタ塗りグラデーションではなく暗い下地のみ（動画書き出しに透過チャンネルの
        // ないmp4を使うため塗りつぶし自体は必要）。ガラス片は通常合成で描画するため、
        // この暗い下地の上でも本来の鮮やかな色がそのまま乗る（乗算合成だと黒背景と
        // 掛け合わさって色が潰れてしまうため使わない。詳細はrenderWedgeBitmap内コメント参照）。
        context.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        let pattern = KaleidoscopeShapeGenerator.generateWedge(
            symmetryCount: n,
            seed: parameters.seed,
            density: parameters.shardDensity,
            deformation: parameters.deformationIntensity
        )

        // ルール1: 扇形は1回だけオフスクリーンに描画する。
        guard let wedgeImage = renderWedgeBitmap(pattern: pattern, radius: radius, palette: parameters.palette, time: parameters.time, noiseAmount: parameters.noiseAmount) else {
            // 何らかの理由で描画できなくても、描画ループ自体は止めない（docs/03b 安全設計）。
            return
        }

        // 「振る」操作の変位は模様全体をまとめて動かす（個々の扇形ごとに別方向へずらさない）。
        let shiftedCenter = CGPoint(x: center.x + parameters.flowOffset.dx, y: center.y + parameters.flowOffset.dy)
        // アイドル時の呼吸するような拍動。
        let pulseScale = 1.0 + (CGFloat(parameters.pulsePhase) - 0.5) * 0.04

        context.saveGState()
        context.translateBy(x: shiftedCenter.x, y: shiftedCenter.y)
        context.scaleBy(x: pulseScale, y: pulseScale)

        let stampRect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)

        for i in 0..<n {
            context.saveGState()
            context.rotate(by: Double(wedgeAngle) * Double(i) + parameters.rotation)

            if i % 2 == 1 {
                // ルール2: 「扇形自身の中心線（角度 wedgeAngle/2 の二等分線）」を軸にした反転。
                // rotate(φ) -> flip y -> rotate(-φ) の順で合成すると、角度θがコード上
                // 「2φ - θ」に写像される反射になる（φ = wedgeAngle/2）。
                // これにより角度範囲 [0, wedgeAngle) 自身の中で閉じた反転になり、
                // 単純な上下反転のように隣の扇形へずれて重なることがない。
                context.rotate(by: Double(wedgeAngle) / 2)
                context.scaleBy(x: 1, y: -1)
                context.rotate(by: -Double(wedgeAngle) / 2)
            }

            context.draw(wedgeImage, in: stampRect)
            context.restoreGState()
        }
        context.restoreGState()

        if parameters.radialBurst > 0 {
            drawRadialBurstOverlay(context: context, center: shiftedCenter, radius: radius, strength: parameters.radialBurst, phase: parameters.pulsePhase)
        }
        drawCenterGlow(context: context, center: shiftedCenter, radius: radius * 0.06)
    }

    // MARK: - 扇形1つ分をオフスクリーンビットマップに描画

    private static func renderWedgeBitmap(pattern: WedgePattern, radius: CGFloat, palette: KaleidoscopePalette, time: Double, noiseAmount: Double) -> CGImage? {
        let dimension = max(2, Int(radius.rounded(.up)) * 2)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let tip = CGPoint(x: CGFloat(dimension) / 2, y: CGFloat(dimension) / 2)
        let colors = palette.cgColors

        func point(radiusFraction: CGFloat, angle: CGFloat) -> CGPoint {
            let r = radiusFraction * radius
            return CGPoint(x: tip.x + r * cos(angle), y: tip.y + r * sin(angle))
        }

        func path(for shape: GlassShardShape, size: CGFloat) -> CGPath {
            let path = CGMutablePath()
            switch shape {
            case .diamond:
                path.move(to: CGPoint(x: 0, y: -size))
                path.addLine(to: CGPoint(x: size * 0.6, y: 0))
                path.addLine(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: -size * 0.6, y: 0))
                path.closeSubpath()
            case .triangle:
                path.move(to: CGPoint(x: 0, y: -size))
                path.addLine(to: CGPoint(x: size * 0.86, y: size * 0.5))
                path.addLine(to: CGPoint(x: -size * 0.86, y: size * 0.5))
                path.closeSubpath()
            }
            return path
        }

        // 個体ごとの揺らぎの強さ。noiseAmount（アクティビティ種別ごとに変わる係数）で全体スケールを
        // 調整しつつ、wobbleAmount/wobblePhaseは形状ごとに生成時に1回だけ決まった値を使うため、
        // 各ガラス片が互いにズレたタイミングで独立して呼吸するように見える。
        let noiseScale = 1 + CGFloat(noiseAmount) * 4
        func wobbledRadius(base: CGFloat, phase: CGFloat, amount: CGFloat) -> CGFloat {
            let wobble = sin(time * 1.7 + Double(phase)) * Double(amount * noiseScale)
            return base * CGFloat(1 + wobble)
        }

        func drawShard(_ shard: GlassShard, alpha: CGFloat) {
            guard !colors.isEmpty else { return }
            let effectiveRadius = wobbledRadius(base: shard.radius, phase: shard.wobblePhase, amount: shard.wobbleAmount)
            let p = point(radiusFraction: effectiveRadius, angle: shard.angle)
            let s = shard.size * radius
            let shapePath = path(for: shard.shape, size: s)

            ctx.saveGState()
            ctx.translateBy(x: p.x, y: p.y)
            ctx.rotate(by: shard.rotation)

            // multiply（乗算）合成は、docs/03bのブラウザ版のように背景が透明な場合にのみ
            // 「重なった部分だけ濃くなる」効果になる。このSwift実装では背景に暗い下地を
            // 塗っているため、multiplyのままだと黒×色でほぼ黒に潰れてしまっていた
            // （実機で「キラキラしない・色が死んでいる」と指摘された根本原因）。
            // 通常合成にして、ガラス片本来の鮮やかな色がそのまま乗るようにする。
            ctx.setBlendMode(.normal)
            let color = colors[shard.colorIndex % colors.count]
            ctx.setFillColor(color.copy(alpha: alpha) ?? color)
            ctx.addPath(shapePath)
            ctx.fillPath()

            // 角に軽いハイライトのストローク（lighten合成）で硬質感を出す。
            ctx.setBlendMode(.lighten)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
            ctx.setLineWidth(max(0.5, s * 0.05))
            ctx.addPath(shapePath)
            ctx.strokePath()

            ctx.restoreGState()
        }

        // レイヤー構成: 面(facet) → シャード(shard) → 光の筋(ray) → 輝き(spark)
        // 通常合成に変更したため、透け感を保ちつつくっきり見えるようアルファ値も引き上げる。
        for facet in pattern.facets { drawShard(facet, alpha: 0.85) }
        for shard in pattern.shards { drawShard(shard, alpha: 0.9) }

        for ray in pattern.rays {
            ctx.saveGState()
            ctx.setBlendMode(.screen)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
            ctx.setLineWidth(ray.width * radius)
            ctx.move(to: tip)
            ctx.addLine(to: point(radiusFraction: ray.length, angle: ray.angle))
            ctx.strokePath()
            ctx.restoreGState()
        }

        // 輝き(spark): 平らな白丸ではなく、白(中心)→パレット色→透明の放射グラデーションで
        // キラキラした光の粒に見えるようにする。
        for spark in pattern.sparks {
            guard !colors.isEmpty else { break }
            let effectiveRadius = wobbledRadius(base: spark.radius, phase: spark.wobblePhase, amount: spark.wobbleAmount)
            let p = point(radiusFraction: effectiveRadius, angle: spark.angle)
            let s = spark.size * radius
            let tint = colors[spark.colorIndex % colors.count]
            guard let tintComponents = tint.components, tintComponents.count >= 3 else { continue }
            let sparkColors: [CGColor] = [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
                CGColor(red: tintComponents[0], green: tintComponents[1], blue: tintComponents[2], alpha: 0.7),
                CGColor(red: tintComponents[0], green: tintComponents[1], blue: tintComponents[2], alpha: 0)
            ]
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: sparkColors as CFArray, locations: [0, 0.4, 1]) else { continue }
            ctx.saveGState()
            ctx.setBlendMode(.screen)
            ctx.drawRadialGradient(gradient, startCenter: p, startRadius: 0, endCenter: p, endRadius: s / 2, options: [])
            ctx.restoreGState()
        }

        return ctx.makeImage()
    }

    // MARK: - 装飾オーバーレイ

    /// docs/02-spec.md 3.2節「floorsAscended → 中心から外側・上方向への広がり」の簡易実装。
    /// MVPでは正確な発生タイミングまでは扱わず、その日の合計階数に応じた一定の強さの
    /// リング演出として重ねる（正確な時系列反映はv2の改善候補）。
    private static func drawRadialBurstOverlay(context: CGContext, center: CGPoint, radius: CGFloat, strength: Double, phase: Double) {
        let ringRadius = radius * CGFloat(0.3 + 0.6 * phase)
        context.saveGState()
        context.setBlendMode(.screen)
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: CGFloat(0.25 * strength)))
        context.setLineWidth(max(1, radius * 0.01))
        context.strokeEllipse(in: CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2))
        context.restoreGState()
    }

    private static func drawCenterGlow(context: CGContext, center: CGPoint, radius: CGFloat) {
        guard radius > 0 else { return }
        let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 0.5), CGColor(red: 1, green: 1, blue: 1, alpha: 0)]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) else { return }
        context.saveGState()
        context.setBlendMode(.screen)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        context.restoreGState()
    }
}
