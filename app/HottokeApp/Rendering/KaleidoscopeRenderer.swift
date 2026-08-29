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
///
/// 扇形1つ分の「中身」は、ガラス片を敷き詰める旧方式（GlassShard/KaleidoscopeShapeGenerator、
/// 現在は未使用）から、「数学模様」4スタイル（幾何学タイル/スピログラフ/波の干渉/フラクタル分岐）
/// に置き換えた。実装はブラウザ上のHTML/Canvasプロトタイプ（renderTiling/renderSpirograph/
/// renderWaves/renderFractal）をCoreGraphics APIへそのまま移植したもの。移植にあたっての
/// API対応（Canvas 2D → CoreGraphics）:
///   - g.globalAlpha        → ctx.setAlpha(_:)
///   - g.globalCompositeOperation = 'lighter' → ctx.setBlendMode(.plusLighter)
///   - g.globalCompositeOperation = 'source-over' → ctx.setBlendMode(.normal)
///   - g.beginPath()/moveTo/lineTo/stroke() → CGMutablePath + ctx.addPath/strokePath()
///     （CoreGraphicsはstrokePath()の後にカレントパスが空になるため、同じパスを複数回
///     ストロークするJSコード＝グロー効果の二度塗りは、都度addPathし直す必要がある）
///   - g.arc(cx,cy,r,0,2π); g.fill() → ctx.fillEllipse(in:)
enum KaleidoscopeRenderer {

    static func render(into context: CGContext, size: CGSize, parameters: KaleidoscopeParameters) {
        guard size.width > 0, size.height > 0 else { return }

        let n = max(3, parameters.symmetryCount)
        let wedgeAngle = CGFloat(2 * Double.pi / Double(n))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2

        // 背景: ベタ塗りグラデーションではなく暗い下地のみ（動画書き出しに透過チャンネルの
        // ないmp4を使うため塗りつぶし自体は必要）。
        context.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        // ルール1: 扇形は1回だけオフスクリーンに描画する。
        guard let wedgeImage = renderWedgeBitmap(
            style: parameters.patternStyle,
            symmetryCount: n,
            radius: radius,
            palette: parameters.palette,
            time: parameters.time,
            detail: parameters.detail
        ) else {
            // 何らかの理由で描画できなくても、描画ループ自体は止めない（docs/03b 安全設計）。
            return
        }

        // 「振る」操作の変位は模様全体をまとめて動かす（個々の扇形ごとに別方向へずらさない）。
        let shiftedCenter = CGPoint(x: center.x + parameters.flowOffset.dx, y: center.y + parameters.flowOffset.dy)
        // ゆっくりとしたズームイン・アウトの呼吸（プロトタイプstampAllのpulse/breathEnvelopeを移植。
        // KaleidoscopeDynamics参照）。
        let pulseScale = CGFloat(KaleidoscopeDynamics.zoomPulse(time: parameters.time))

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

    private static func renderWedgeBitmap(style: PatternStyle, symmetryCount: Int, radius: CGFloat, palette: KaleidoscopePalette, time: Double, detail: Double) -> CGImage? {
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

        let colors = palette.cgColors
        guard !colors.isEmpty else { return ctx.makeImage() }

        let tip = CGFloat(dimension) / 2
        let wedgeAngle = CGFloat(2 * Double.pi / Double(symmetryCount))

        ctx.saveGState()
        ctx.translateBy(x: tip, y: tip)

        // 扇形の角度範囲だけをクリップする。プロトタイプのrenderTiling/renderSpirograph/
        // renderWaves/renderFractalはいずれも円全体を対象に自由に描く実装のため（モチーフの
        // 格子・波の輪・フラクタルの枝が扇形の外にもはみ出す）、旧GlassShard方式のように
        // 「生成する座標そのものを扇形内に収める」やり方ではなく、プロトタイプと同じく
        // 「扇形の二等分パイ形にクリップしてから描く」方式にする必要がある。
        let clipPath = CGMutablePath()
        clipPath.move(to: .zero)
        clipPath.addArc(center: .zero, radius: radius, startAngle: 0, endAngle: wedgeAngle, clockwise: false)
        clipPath.closeSubpath()
        ctx.saveGState()
        ctx.addPath(clipPath)
        ctx.clip()

        // 密度・複雑さ(detail)を基準値からゆっくり揺らす（プロトタイプrenderWedgeのdetailDrift）。
        let effectiveDetail = KaleidoscopeDynamics.effectiveDetail(base: detail, time: time)
        let R = Double(radius)

        switch style {
        case .tiling:
            renderTiling(ctx: ctx, R: R, palette: colors, t: time, detail: effectiveDetail)
        case .spirograph:
            renderSpirograph(ctx: ctx, R: R, palette: colors, t: time, detail: effectiveDetail, n: symmetryCount)
        case .waves:
            renderWaves(ctx: ctx, R: R, palette: colors, t: time, detail: effectiveDetail, n: symmetryCount)
        case .fractal:
            renderFractal(ctx: ctx, R: R, palette: colors, t: time, detail: effectiveDetail, n: symmetryCount)
        }

        ctx.restoreGState() // クリップを解除
        ctx.restoreGState() // 平行移動を解除
        return ctx.makeImage()
    }

    // MARK: - 幾何学タイル（プロトタイプ renderTiling / drawTileMotif の移植）

    /// (row,col)から常に同じ値を返す簡易ハッシュ。乱数ではなくこれを使うことで、
    /// 「同じ格子点は毎フレーム同じモチーフ・色になる」を保ちつつ見た目にはバラつきを出せる。
    private static func hashRC(_ a: Double, _ b: Double) -> Double {
        let x = sin(a * 127.1 + b * 311.7) * 43758.5453
        return x - floor(x)
    }

    private static func tileLatticePos(row: Int, col: Int, cell: Double) -> (x: Double, y: Double) {
        let offsetX = (row % 2 == 0) ? 0.0 : cell / 2
        return (Double(col) * cell + offsetX, Double(row) * cell * 0.866)
    }

    private static func polygonPath(size: Double, sides: Int, rotationOffset: Double) -> CGPath {
        let path = CGMutablePath()
        for i in 0...sides {
            let a = rotationOffset + Double(i) * (2 * Double.pi / Double(sides))
            let point = CGPoint(x: CGFloat(cos(a) * size), y: CGFloat(sin(a) * size))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// 単調にならないよう5種類のモチーフを用意し、格子点ごとに振り分ける。
    private static func drawTileMotif(ctx: CGContext, kind: Int, s: Double, color: CGColor) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(1.3)
        ctx.setAlpha(0.82)
        ctx.setBlendMode(.normal)
        switch kind {
        case 0: // 八芒星
            ctx.addPath(polygonPath(size: s, sides: 4, rotationOffset: 0)); ctx.strokePath()
            ctx.addPath(polygonPath(size: s, sides: 4, rotationOffset: .pi / 4)); ctx.strokePath()
        case 1: // 六芒星
            ctx.addPath(polygonPath(size: s, sides: 3, rotationOffset: 0)); ctx.strokePath()
            ctx.addPath(polygonPath(size: s, sides: 3, rotationOffset: .pi)); ctx.strokePath()
        case 2: // 六角の二重輪
            ctx.addPath(polygonPath(size: s, sides: 6, rotationOffset: 0)); ctx.strokePath()
            ctx.addPath(polygonPath(size: s * 0.55, sides: 6, rotationOffset: .pi / 6)); ctx.strokePath()
        case 3: // 正方形+円
            ctx.addPath(polygonPath(size: s, sides: 4, rotationOffset: .pi / 4)); ctx.strokePath()
            let circle = CGMutablePath()
            circle.addEllipse(in: CGRect(x: -s * 0.6, y: -s * 0.6, width: s * 1.2, height: s * 1.2))
            ctx.addPath(circle); ctx.strokePath()
        default: // 花びら(ロゼット)
            for i in 0..<6 {
                let a = Double(i) * (2 * Double.pi / 6)
                let cx = cos(a) * s * 0.4, cy = sin(a) * s * 0.4
                let petal = CGMutablePath()
                petal.addEllipse(in: CGRect(x: cx - s * 0.3, y: cy - s * 0.3, width: s * 0.6, height: s * 0.6))
                ctx.addPath(petal); ctx.strokePath()
            }
        }
        ctx.setBlendMode(.plusLighter)
        ctx.setAlpha(0.5)
        ctx.setFillColor(color)
        let dot = CGMutablePath()
        dot.addEllipse(in: CGRect(x: -s * 0.1, y: -s * 0.1, width: s * 0.2, height: s * 0.2))
        ctx.addPath(dot)
        ctx.fillPath()
        ctx.setBlendMode(.normal)
    }

    private static func renderTiling(ctx: CGContext, R: Double, palette: [CGColor], t: Double, detail: Double) {
        let cell = R / (3 + detail * 5.5)
        let span = Int((R * 1.1 / cell).rounded(.up)) + 2
        ctx.setLineCap(.round)

        // モチーフ同士を編み込むような細い地紋線（三角格子の辺の一部）。
        // これがないと「同じシールが並んでいるだけ」に見えやすいため。
        ctx.saveGState()
        ctx.setAlpha(0.16)
        ctx.setLineWidth(1)
        for row in -span...span {
            for col in -span...span {
                let c = tileLatticePos(row: row, col: col, cell: cell)
                if hypot(c.x, c.y) > R * 1.15 { continue }
                let r = tileLatticePos(row: row, col: col + 1, cell: cell)
                let d = tileLatticePos(row: row + 1, col: col, cell: cell)
                ctx.setStrokeColor(palette[abs(row + col) % palette.count])

                let toRight = CGMutablePath()
                toRight.move(to: CGPoint(x: c.x, y: c.y))
                toRight.addLine(to: CGPoint(x: r.x, y: r.y))
                ctx.addPath(toRight); ctx.strokePath()

                let toDown = CGMutablePath()
                toDown.move(to: CGPoint(x: c.x, y: c.y))
                toDown.addLine(to: CGPoint(x: d.x, y: d.y))
                ctx.addPath(toDown); ctx.strokePath()
            }
        }
        ctx.restoreGState()

        for row in -span...span {
            for col in -span...span {
                let c = tileLatticePos(row: row, col: col, cell: cell)
                let dist = hypot(c.x, c.y)
                if dist > R * 1.08 { continue }

                let h1 = hashRC(Double(row), Double(col))
                let h2 = hashRC(Double(row + 91), Double(col - 17))
                let h3 = hashRC(Double(row - 33), Double(col + 58))
                let motif = Int(h1 * 5)
                let color = palette[Int(h2 * Double(palette.count))]
                let sizeScale = 0.30 + h3 * 0.22 // 0.30〜0.52でばらつかせ、粒の大小もつける。
                let s = cell * sizeScale * (0.9 + 0.1 * sin(t * 1.1 + dist * 0.045))

                ctx.saveGState()
                ctx.translateBy(x: CGFloat(c.x), y: CGFloat(c.y))
                ctx.rotate(by: t * 0.12 + h2 * 2 * .pi + dist * 0.0025)
                drawTileMotif(ctx: ctx, kind: motif, s: s, color: color)
                ctx.restoreGState()
            }
        }
    }

    // MARK: - スピログラフ（プロトタイプ renderSpirograph の移植）

    private static func renderSpirograph(ctx: CGContext, R: Double, palette: [CGColor], t: Double, detail: Double, n: Int) {
        // 層のRbを中心寄り〜外周まで広く分散させ、さらに中心にコアの発光を足して空洞を埋める
        // （層のRbが外周寄りの狭い帯に集まると中心付近ががら空きになっていた反省）。
        //
        // カクつき対策: layers（層数）はdetailの変化で整数がジャンプするが、各層のRbを
        // 「その時点のlayers」で割ってしまうと、層が1本増減するたびに既存の層すべての
        // 位置が同時にズレて見える。そこでspanTの分母は固定のmaxLayersにし、実際に
        // 描く層数だけをdetailから連続的に決める（floor層は通常濃度、境界の1層は
        // アルファでフェード、それ以降は描かない）。
        let maxLayers = 6 // detail 0〜1で層数が3〜6まで変化する従来仕様の最大値に合わせる
        let layersF = 3 + detail * 3
        let layersFloor = min(Int(floor(layersF)), maxLayers)
        let layerFrac = layersF - Double(layersFloor)
        let layersToDraw = min(layersFloor + (layerFrac > 0.0001 ? 1 : 0), maxLayers)

        for layerIndex in 0..<layersToDraw {
            // 境界の1層（ちょうど整数を跨ぐ層）だけはlayerFracをアルファに掛けてフェードさせる。
            let alphaMul = layerIndex < layersFloor ? 1.0 : layerFrac
            let spanT = Double(layerIndex) / Double(maxLayers - 1)
            let Rb = R * (0.15 + 0.79 * spanT) // 中心近くから外周まで層を配置
            let rb = R / Double(n + 1 + layerIndex)
            let d = rb * (0.55 + 0.3 * detail)
            let color = palette[layerIndex % palette.count]
            let k = (Rb - rb) / rb
            let revolutions = n + 1 + layerIndex
            let steps = 360 * min(revolutions, 10)

            let path = CGMutablePath()
            for i in 0...steps {
                let tt = (Double(i) / Double(steps)) * 2 * Double.pi * Double(revolutions) + t * (0.05 + Double(layerIndex) * 0.008)
                let x = (Rb - rb) * cos(tt) + d * cos(k * tt)
                let y = (Rb - rb) * sin(tt) - d * sin(k * tt)
                let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }

            ctx.setStrokeColor(color)
            ctx.setLineWidth(1.5)
            ctx.setAlpha(0.82 * alphaMul)
            ctx.setBlendMode(.normal)
            ctx.addPath(path)
            ctx.strokePath()

            ctx.saveGState()
            ctx.setBlendMode(.plusLighter)
            ctx.setAlpha(0.30 * alphaMul)
            ctx.setLineWidth(5)
            ctx.setStrokeColor(color)
            ctx.addPath(path) // strokePath()後はカレントパスが空になるため再度addPathする
            ctx.strokePath()
            ctx.restoreGState()
        }

        // 最内層のさらに内側が寂しくならないよう、中心に小さな発光コアを添える。
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        let coreColor = palette[0]
        let clearCoreColor = coreColor.copy(alpha: 0) ?? coreColor
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [coreColor, clearCoreColor] as CFArray, locations: [0, 1]) {
            ctx.setAlpha(0.55)
            ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: CGFloat(R * 0.13), options: [])
        }
        ctx.restoreGState()
    }

    // MARK: - 波の干渉（プロトタイプ renderWaves の移植）

    private static func renderWaves(ctx: CGContext, R: Double, palette: [CGColor], t: Double, detail: Double, n: Int) {
        // 線だけだと寂しく見えるため、(1) 隣り合う輪の間を半透明で塗って帯にする、
        // (2) 波の頂点に小さなきらめきを添える、(3) グローを強めにする、の3つで満たす。
        //
        // カクつき対策: 輪の本数(ringCount)はdetailの変化に応じて整数でジャンプするが、
        // 各輪の半径を「その時点のringCount」で割ってしまうと、輪が1本増減するたびに
        // 既存の輪すべての半径が同時にズレて見える。そこで半径の分母は固定の
        // maxRingSlotsにし、実際に描く本数だけをdetailから連続的に決める
        // （floor本は通常濃度、境界の1本はアルファでフェード、それ以降は描かない）。
        let maxRingSlots = 14 // detail 0〜1で本数が6〜14まで変化する従来仕様の最大値に合わせる
        let ringCountF = 6 + detail * 8
        let ringCountFloor = min(Int(floor(ringCountF)), maxRingSlots)
        let ringFrac = ringCountF - Double(ringCountFloor)
        let ringsToDraw = min(ringCountFloor + (ringFrac > 0.0001 ? 1 : 0), maxRingSlots)

        let k1 = Double(n), k2 = Double(n) * 2, k3 = max(3.0, Double(n) - 2)
        let steps = 220
        var prevPts: [(x: Double, y: Double, mod: Double)]?

        for ri in 0..<ringsToDraw {
            // 境界の1本（ちょうど整数を跨ぐ輪）だけはringFracをアルファに掛けてフェードさせる。
            let alphaMul = ri < ringCountFloor ? 1.0 : ringFrac
            let baseR = R * Double(ri + 1) / Double(maxRingSlots)
            let amp = R * 0.05 * (1 - Double(ri) / Double(maxRingSlots) * 0.35)
            let color = palette[ri % palette.count]
            var pts: [(x: Double, y: Double, mod: Double)] = []
            pts.reserveCapacity(steps + 1)
            for i in 0...steps {
                let theta = (Double(i) / Double(steps)) * 2 * Double.pi
                let mod = sin(k1 * theta + t * 0.6) * amp
                    + sin(k2 * theta - t * 0.9) * amp * 0.5
                    + sin(k3 * theta + t * 0.3) * amp * 0.3
                let r = baseR + mod
                pts.append((cos(theta) * r, sin(theta) * r, mod))
            }

            if let prevPts {
                ctx.setBlendMode(.normal)
                ctx.setAlpha(0.11 * alphaMul)
                ctx.setFillColor(color)
                let band = CGMutablePath()
                band.move(to: CGPoint(x: prevPts[0].x, y: prevPts[0].y))
                for i in 1..<prevPts.count { band.addLine(to: CGPoint(x: prevPts[i].x, y: prevPts[i].y)) }
                for i in stride(from: pts.count - 1, through: 0, by: -1) { band.addLine(to: CGPoint(x: pts[i].x, y: pts[i].y)) }
                band.closeSubpath()
                ctx.addPath(band)
                ctx.fillPath()
            }

            let ring = CGMutablePath()
            ring.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
            for i in 1..<pts.count { ring.addLine(to: CGPoint(x: pts[i].x, y: pts[i].y)) }
            ring.closeSubpath()

            ctx.setStrokeColor(color)
            ctx.setLineWidth(1.3)
            ctx.setAlpha(0.68 * alphaMul)
            ctx.setBlendMode(.normal)
            ctx.addPath(ring)
            ctx.strokePath()

            ctx.saveGState()
            ctx.setBlendMode(.plusLighter)
            ctx.setAlpha(0.26 * alphaMul)
            ctx.setLineWidth(4.5)
            ctx.setStrokeColor(color)
            ctx.addPath(ring)
            ctx.strokePath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.setBlendMode(.plusLighter)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            var i = 0
            while i < pts.count {
                let point = pts[i]
                if point.mod > amp * 0.5 {
                    ctx.setAlpha(0.55 * alphaMul)
                    let sparkSize = R * 0.014
                    ctx.fillEllipse(in: CGRect(x: point.x - sparkSize / 2, y: point.y - sparkSize / 2, width: sparkSize, height: sparkSize))
                }
                i += 11
            }
            ctx.restoreGState()

            prevPts = pts
        }

        // 一番内側もただの黒にならないよう、うっすら塗って埋める。
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.setAlpha(0.14)
        ctx.setFillColor(palette[0])
        let innerRadius = R / Double(maxRingSlots) * 0.85
        ctx.fillEllipse(in: CGRect(x: -innerRadius, y: -innerRadius, width: innerRadius * 2, height: innerRadius * 2))
        ctx.restoreGState()
    }

    // MARK: - フラクタル分岐（プロトタイプ renderFractal の移植）

    /// エルミート補間によるなめらかな0→1の立ち上がり（Swiftにsmoothstepがないため自前定義）。
    /// detailなどの連続値から「境界の1つだけをじわっとフェードさせる」係数を作るのに使う。
    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 != edge0 else { return x < edge0 ? 0 : 1 }
        let tt = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return tt * tt * (3 - 2 * tt)
    }

    private static func renderFractal(ctx: CGContext, R: Double, palette: [CGColor], t: Double, detail: Double, n: Int) {
        let wedgeAngle = (2 * Double.pi) / Double(n)
        // 密度を上げても「なんとなく長くなるだけ」にならないよう、分岐角は深さで割って
        // 縮めない（固定角）。かわりに: 幹の本数・分岐数・深さの3つを密度に応じて増やし、
        // 込み入り方そのものが変わるようにする。
        //
        // カクつき対策: 以前はchildCount(2→3)・maxDepth・trunkCountがdetailの閾値／四捨五入で
        // フレーム間に整数として突然切り替わり、特に枝分かれ構造が丸ごと変わるchildCountの
        // 切り替えが目立つカクつきの原因だった。そこで「表示スロット数は固定にし、実際に
        // 見せるか・どれだけ濃く見せるかをdetailから連続値で決める」方式に統一する:
        //   - 子枝は常に3本ぶんの角度を計算するが、3本目はdetailからなめらかに
        //     立ち上がるfadeT(0〜1)をアルファに掛けてフェードイン/アウトさせる。
        //   - 深さはfloor本まで通常描画し、境界の1層だけアルファをフェードさせてから
        //     それ以上は描かない。
        //   - 幹の本数も同様（角度は固定本数ぶん常に計算し、実際に使う本数だけを
        //     floor本+境界1本のフェードで決める）。
        let branchSpread = 0.30 + detail * 0.22 // ラジアン。深さに関係なく毎回この角度で開く。
        let fadeT = smoothstep(0.45, 0.8, detail) // 3本目の子枝の濃さ（0=見えない〜1=通常濃度）

        let maxDepthF = 4 + detail * 6
        let maxDepthFloor = Int(floor(maxDepthF))
        let depthFrac = maxDepthF - Double(maxDepthFloor)
        // 実際に線を引く最大の深さ（境界のフェード層を含む）。線幅の基準にも使う。
        let effectiveMaxDepth = maxDepthFloor + 1

        ctx.setLineCap(.round)

        func drawLeafGlow(x: Double, y: Double, depth: Int, alphaMul: Double) {
            guard alphaMul > 0.0001 else { return }
            // 枝先に小さな輝きを添えて、伸びた先が単に途切れるのではなく
            // 「芽吹いている」ように見せる（キラキラ感の継続）。
            ctx.saveGState()
            ctx.setBlendMode(.plusLighter)
            ctx.setAlpha(0.5 * alphaMul)
            ctx.setFillColor(palette[depth % palette.count])
            let glowSize = R * 0.012
            ctx.fillEllipse(in: CGRect(x: x - glowSize / 2, y: y - glowSize / 2, width: glowSize, height: glowSize))
            ctx.restoreGState()
        }

        func branch(x: Double, y: Double, angle: Double, len: Double, depth: Int, seed: Double, alphaMul: Double) {
            if len < R * 0.011 {
                drawLeafGlow(x: x, y: y, depth: depth, alphaMul: alphaMul)
                return
            }
            // 境界の1層（floor+1階層目）だけはdepthFracをアルファに掛けてフェードさせ、
            // その先へは分岐させない（それ以上のdepthに到達することはない）。
            let depthAlphaMul = depth == maxDepthFloor + 1 ? depthFrac : 1.0
            let totalAlphaMul = alphaMul * depthAlphaMul
            guard totalAlphaMul > 0.0001 else { return }

            let wig = sin(t * 0.8 + Double(depth) * 1.3 + seed) * 0.05
            let nx = x + cos(angle + wig) * len
            let ny = y + sin(angle + wig) * len
            let color = palette[depth % palette.count]

            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: nx, y: ny))
            ctx.setStrokeColor(color)
            ctx.setLineWidth(max(0.5, Double(effectiveMaxDepth - depth) * 0.42))
            ctx.setAlpha(0.78 * totalAlphaMul)
            ctx.setBlendMode(.normal)
            ctx.addPath(path)
            ctx.strokePath()

            if depth == maxDepthFloor + 1 {
                // ここが今回描く最後の階層。これ以上は分岐させず、先端の輝きだけ添えて打ち切る。
                drawLeafGlow(x: nx, y: ny, depth: depth, alphaMul: totalAlphaMul)
                return
            }

            // depth 0（幹の根元）だけは次の枝を長く伸ばし直す。中心から最初の分岐点までの
            // 「幹」を短くすることで、中央がまばらにならず、根元近くからすぐ枝分かれが
            // 始まるようにする（幹を長くしたまま縮小率だけ掛けると中心付近に空白ができる）。
            let nextLen = depth == 0 ? R * 0.32 : len * (0.68 + 0.06 * sin(seed * 3))
            // 子枝は常に3本ぶんの角度を計算する（spreadFactorの分母を固定することで、
            // 本数が変わっても既存の2本の角度は動かない）。3本目だけfadeTでフェードさせる。
            for c in 0..<3 {
                let spreadFactor = Double(c) - 1.0 // -1, 0, 1
                let childAngle = angle + spreadFactor * branchSpread + sin(seed + Double(c)) * 0.05
                let childAlphaMul = c == 2 ? totalAlphaMul * fadeT : totalAlphaMul
                guard childAlphaMul > 0.0001 else { continue }
                branch(x: nx, y: ny, angle: childAngle, len: nextLen, depth: depth + 1, seed: seed * 1.618 + Double(c) + 1, alphaMul: childAlphaMul)
            }
        }

        let maxTrunkCount = 4
        let trunkCountF = 1 + detail * 3
        let trunkCountFloor = min(Int(floor(trunkCountF)), maxTrunkCount)
        let trunkFrac = trunkCountF - Double(trunkCountFloor)
        let trunksToDraw = min(trunkCountFloor + (trunkFrac > 0.0001 ? 1 : 0), maxTrunkCount)

        for i in 0..<trunksToDraw {
            // 境界の1本（ちょうど整数を跨ぐ幹）だけはtrunkFracをアルファに掛けてフェードさせる。
            let alphaMul = i < trunkCountFloor ? 1.0 : trunkFrac
            // 角度はmaxTrunkCount（固定）で割ることで、幹の本数が変わっても既存の幹の
            // 角度が動かないようにする。
            let trunkAngle = wedgeAngle * (Double(i) + 0.5) / Double(maxTrunkCount)
            // 根元の幹を短く(中心からすぐ分岐させる)。これが中心付近の疎さの直接の原因だった。
            branch(x: 0, y: 0, angle: trunkAngle, len: R * (0.10 - Double(i) * 0.006), depth: 0, seed: Double(i) * 7.31 + 1, alphaMul: alphaMul)
        }
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
