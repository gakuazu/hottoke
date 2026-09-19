import UIKit
import CoreGraphics

// 「1日の輪」の表現スタイルの描画（docs/23-radial-art-concepts.md のブラウザ試作をCoreGraphicsへ移植）。
//
// 共通の考え方:
//  ・座標は画面座標（y下向き）。時刻hの方向は (sin, -cos)、0時が真上・時計回り。
//  ・絵は透明な「光の層」に加算合成(.plusLighter)で描く。暗い背景の上に重ねると発光して見える。
//  ・層に描くときは、光の強さを「露出」(0.62倍)で控えめにしておき、最後に色相を保つトーンマッピングで戻す。
//    明るい部分が白飛びせず、色が残る（リングの縁や花びらの根元が白く縁取られない）。
//  ・光のにじみ（ブルーム）は、層を縮小→拡大して控えめに重ねる。
//  ・光の粒は、小さな画像（スプライト）を1枚ずつ焼いて使い回す。

// MARK: - 幾何

struct ArtGeom {
    let side: CGFloat
    let cx: CGFloat
    let cy: CGFloat
    /// 絵の最大半径（時刻の文字が画面の端で切れないよう、正方形の一辺の0.395倍）
    var R: CGFloat { side * 0.395 }
    var u: CGFloat { side / 1000 }

    func point(angle a: Double, radius r: CGFloat) -> CGPoint {
        CGPoint(x: cx + CGFloat(sin(a)) * r, y: cy - CGFloat(cos(a)) * r)
    }
    func point(hour h: Double, radius r: CGFloat) -> CGPoint {
        point(angle: RingArtRenderer.angle(hour: h), radius: r)
    }
}

// MARK: - 1日ぶんの描画用データ

/// 密度から、描画に必要な値（強さ・色・エピソード）を引きやすくしたもの。
final class ArtDay {
    let density: DailyRingDensity
    let episodes: [RingEpisode]
    /// スライスごとの色（活動の色を割合で混ぜたもの）
    let sliceColors: [RingRGB]
    let strengths: [Double]
    let sleepWeight: [Double]
    let averageColor: RingRGB
    private let rs: [Double], gs: [Double], bs: [Double]
    var drawn: Double { density.drawnHours }
    var count: Int { density.sliceCount }
    var isPeriodic: Bool { density.isPeriodic }

    init(_ density: DailyRingDensity) {
        self.density = density
        episodes = DailyRingLayout.episodes(from: density)
        let colors = (0..<density.sliceCount).map { density.blendedColor(slice: $0) }
        sliceColors = colors
        rs = colors.map { $0.r }; gs = colors.map { $0.g }; bs = colors.map { $0.b }
        strengths = density.smoothedIntensity.map { 1 - exp(-$0 / DailyRingLayout.intensityScale) }
        sleepWeight = density.smoothedWeights[.sleeping] ?? [Double](repeating: 0, count: density.sliceCount)
        var r = 0.0, g = 0.0, b = 0.0, total = 0.0
        for kind in DailyRingLayout.kindOrder {
            let c = DailyRingLayout.ringColor(for: kind)
            let w = (density.smoothedWeights[kind] ?? []).reduce(0, +)
            r += c.r * w; g += c.g * w; b += c.b * w; total += w
        }
        averageColor = total > 0 ? RingRGB(r: r / total, g: g / total, b: b / total) : DailyRingLayout.ringColor(for: .stationary)
    }

    /// 時刻tでの値（スライスの中心どうしを直線でつなぐ）。
    func sample(_ values: [Double], at t: Double) -> Double {
        let n = values.count
        guard n > 0 else { return 0 }
        let pos = t / DailyRingLayout.sliceHours - 0.5
        var i0 = Int(floor(pos))
        let f = min(1, max(0, pos - Double(i0)))
        var i1 = i0 + 1
        if isPeriodic {
            i0 = ((i0 % n) + n) % n
            i1 = ((i1 % n) + n) % n
        } else {
            i0 = min(max(i0, 0), n - 1)
            i1 = min(max(i1, 0), n - 1)
        }
        return values[i0] + (values[i1] - values[i0]) * f
    }

    func strength(at t: Double) -> Double { sample(strengths, at: t) }

    func color(at t: Double) -> RingRGB {
        guard count > 0 else { return DailyRingLayout.ringColor(for: .stationary) }
        return RingRGB(r: sample(rs, at: t), g: sample(gs, at: t), b: sample(bs, at: t))
    }
}

// MARK: - 描画の道具

final class ArtPainter {
    let ctx: CGContext
    let g: ArtGeom
    /// 層に描く光の強さの倍率（最後にトーンマッピングで戻す）
    static let exposure: CGFloat = 0.62
    private var sprites: [UInt32: CGImage] = [:]
    private let space = CGColorSpaceCreateDeviceRGB()

    init(ctx: CGContext, geom: ArtGeom) {
        self.ctx = ctx
        self.g = geom
    }

    func cg(_ c: RingRGB, _ alpha: Double) -> CGColor {
        CGColor(red: CGFloat(min(1, max(0, c.r))), green: CGFloat(min(1, max(0, c.g))), blue: CGFloat(min(1, max(0, c.b))),
                alpha: CGFloat(max(0, alpha)) * Self.exposure)
    }

    /// 色を白に近づける（tが大きいほど白）。
    func hot(_ c: RingRGB, _ t: Double) -> RingRGB {
        RingRGB(r: c.r + (1 - c.r) * t, g: c.g + (1 - c.g) * t, b: c.b + (1 - c.b) * t)
    }

    private func sprite(for c: RingRGB) -> CGImage? {
        func q(_ v: Double) -> Int { min(255, Int((v * 255 / 17).rounded()) * 17) }
        let qr = q(c.r), qg = q(c.g), qb = q(c.b)
        let key = UInt32(qr << 16 | qg << 8 | qb)
        if let s = sprites[key] { return s }
        let base = RingRGB(r: Double(qr) / 255, g: Double(qg) / 255, b: Double(qb) / 255)
        let core = hot(base, 0.35)
        guard let sctx = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        func col(_ c: RingRGB, _ a: CGFloat) -> CGColor { CGColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: a) }
        guard let gradient = CGGradient(colorsSpace: space, colors: [col(core, 1), col(base, 0.85), col(base, 0.25), col(base, 0)] as CFArray,
                                        locations: [0, 0.28, 0.62, 1]) else { return nil }
        sctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 24, y: 24), startRadius: 0, endCenter: CGPoint(x: 24, y: 24), endRadius: 24, options: [])
        let image = sctx.makeImage()
        if let image { sprites[key] = image }
        return image
    }

    /// 柔らかい光の粒（スプライトを使い回す）。
    func dot(_ p: CGPoint, radius r: CGFloat, color: RingRGB, alpha: Double) {
        guard r > 0.05, alpha > 0.004, let s = sprite(for: color) else { return }
        ctx.setAlpha(CGFloat(min(1, alpha)) * Self.exposure)
        ctx.draw(s, in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.setAlpha(1)
    }

    func line(_ a: CGPoint, _ b: CGPoint, width: CGFloat, color: RingRGB, alpha: Double, cap: CGLineCap = .round) {
        ctx.setLineCap(cap)
        ctx.setLineWidth(width)
        ctx.setStrokeColor(cg(color, alpha))
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
    }
}

// MARK: - 描画の入口

enum RingArtRenderer {

    static func angle(hour: Double) -> Double { hour / 24 * 2 * Double.pi }

    static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(hi, max(lo, v)) }

    /// 表現スタイルの「光の層」を描いて、ブルーム・トーンマッピングまで済ませた画像を返す。
    /// 背景は含まない（呼び出し側が背景の上に加算合成で重ねる）。
    static func renderLayer(density: DailyRingDensity, options: RingRenderOptions, seed: UInt64, side: CGFloat, center: CGPoint) -> CGImage? {
        let w = Int(options.canvas.width), h = Int(options.canvas.height)
        guard w > 8, h > 8 else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 画面座標（y下向き）で描けるよう反転する。
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .high

        let geom = ArtGeom(side: side, cx: center.x, cy: center.y)
        let painter = ArtPainter(ctx: ctx, geom: geom)
        var rng = SeededGenerator(seed: seed &* 0x9E3779B97F4A7C15 &+ 0xC0FFEE)
        let day = ArtDay(density)
        let past = options.pastDays.map { ArtDay($0) }

        switch options.style {
        case .flowerCorona, .corona, .multiFlower, .yearRings, .aurora, .spiral, .classic:
            RingArtStyles.drawFlowerCorona(painter, day: day, past: past, rng: &rng)
        }

        return finish(ctx: ctx, width: w, height: h, bloom: options.bloom)
    }

    // MARK: 仕上げ（ブルーム + 色相を保つトーンマッピング）

    /// 層を「不透明な光の画像」にして、控えめなブルームを足し、色相を保ったまま白飛びを抑えて仕上げる。
    private static func finish(ctx: CGContext, width w: Int, height h: Int, bloom: Bool) -> CGImage? {
        guard let data = ctx.data else { return nil }
        let count = w * h
        let px = data.bindMemory(to: UInt8.self, capacity: count * 4)
        // 透明度は光の量に含まれているので、色（premultiplied）だけを取り出して不透明にする
        for i in 0..<count { px[i * 4 + 3] = 255 }
        guard let base = ctx.makeImage() else { return nil }

        let space = CGColorSpaceCreateDeviceRGB()
        guard let out = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        out.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        out.fill(CGRect(x: 0, y: 0, width: w, height: h))
        out.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))

        if bloom {
            out.setBlendMode(.plusLighter)
            out.interpolationQuality = .high
            for (divisor, weight) in [(4, 0.16), (12, 0.20), (30, 0.16)] as [(Int, CGFloat)] {
                if let small = downscale(base, toWidth: max(8, w / divisor), height: max(8, h / divisor)) {
                    out.setAlpha(weight)
                    out.draw(small, in: CGRect(x: 0, y: 0, width: w, height: h))
                }
            }
            out.setAlpha(1)
            out.setBlendMode(.normal)
        }

        // トーンマッピング: 最大の色成分で明るさを測り、明るい部分をなだらかに圧縮する（色の比率は変えない）。
        if let outData = out.data {
            let o = outData.bindMemory(to: UInt8.self, capacity: count * 4)
            let exposure = Double(ArtPainter.exposure)
            let knee = 0.66
            for i in 0..<count {
                let r = Double(o[i * 4]), g = Double(o[i * 4 + 1]), b = Double(o[i * 4 + 2])
                let maxc = max(r, g, b)
                if maxc < 1 { continue }
                let light = maxc / 255 / exposure // 光の量（露出を戻した値）
                let mapped: Double = light <= knee ? light : knee + (1 - knee) * (1 - exp(-(light - knee) / (1 - knee)))
                let f = min(mapped, 1) * 255 / maxc
                o[i * 4] = UInt8(min(255, r * f + 0.5))
                o[i * 4 + 1] = UInt8(min(255, g * f + 0.5))
                o[i * 4 + 2] = UInt8(min(255, b * f + 0.5))
                o[i * 4 + 3] = 255
            }
        }
        return out.makeImage()
    }

    /// 半分ずつ縮めながら目標の大きさまで縮小する（大きく縮めても粗くならない）。
    private static func downscale(_ image: CGImage, toWidth tw: Int, height th: Int) -> CGImage? {
        var current = image
        var cw = image.width, ch = image.height
        let space = CGColorSpaceCreateDeviceRGB()
        while cw > tw || ch > th {
            let nw = max(tw, cw / 2), nh = max(th, ch / 2)
            guard let c = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            c.interpolationQuality = .high
            c.draw(current, in: CGRect(x: 0, y: 0, width: nw, height: nh))
            guard let next = c.makeImage() else { return nil }
            current = next
            cw = nw; ch = nh
        }
        return current
    }
}

// MARK: - 各スタイルの描画

enum RingArtStyles {

    /// 花びらの形（0...1の位置での幅の割合）。根元と先端が細く、中ほどが太い滴形。
    static func petalShape(_ u: Double) -> Double {
        pow(sin(Double.pi * pow(u, 0.62)), 0.8)
    }

    // MARK: 時間のリング

    /// 24時間を5分ごとの短い帯にしたリング。色は活動の割合の混色、睡眠は暗め。
    static func drawRing(_ p: ArtPainter, day: ArtDay, rIn: CGFloat, rOut: CGFloat, rng: inout SeededGenerator) {
        let g = p.g
        let wid = rOut - rIn
        let rm = (rIn + rOut) / 2
        let n = day.count
        guard n > 0 else { return }

        // 内側のほんのりした霞（描いた範囲だけ。今日の途中は、これからの時間に霞をかけない）
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [p.cg(day.averageColor, 0), p.cg(day.averageColor, 0.13)] as CFArray, locations: [0, 1]) {
            p.ctx.saveGState()
            let sector = CGMutablePath()
            sector.move(to: CGPoint(x: g.cx, y: g.cy))
            let steps = max(2, Int(day.drawn * 4))
            for k in 0...steps {
                sector.addLine(to: g.point(hour: day.drawn * Double(k) / Double(steps), radius: rIn))
            }
            sector.closeSubpath()
            p.ctx.addPath(sector)
            p.ctx.clip()
            p.ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: g.cx, y: g.cy), startRadius: rIn * 0.35, endCenter: CGPoint(x: g.cx, y: g.cy), endRadius: rIn, options: [])
            p.ctx.restoreGState()
        }

        func strokeRing(radius: CGFloat, width: CGFloat, hot: Double, alpha: (Int) -> Double) {
            p.ctx.setLineCap(.butt)
            p.ctx.setLineWidth(width)
            for i in 0..<n {
                let t0 = Double(i) * DailyRingLayout.sliceHours
                let t1 = min(day.drawn, t0 + DailyRingLayout.sliceHours)
                let a0 = RingArtRenderer.angle(hour: t0) - 0.0006, a1 = RingArtRenderer.angle(hour: t1) + 0.0006
                let c = p.hot(day.sliceColors[i], hot)
                p.ctx.setStrokeColor(p.cg(c, alpha(i)))
                p.ctx.move(to: g.point(angle: a0, radius: radius))
                p.ctx.addLine(to: g.point(angle: a1, radius: radius))
                p.ctx.strokePath()
            }
        }

        // 幅の違う淡い帯を何枚も重ねて、なめらかな光のにじみにする（段差が見えないよう枚数を多めに）
        for m in [1.4, 1.75, 2.1, 2.5, 2.95, 3.5] as [CGFloat] { strokeRing(radius: rm, width: wid * m, hot: 0) { _ in 0.011 } }
        strokeRing(radius: rm, width: wid, hot: 0) { 0.5 - 0.2 * day.sleepWeight[$0] }
        strokeRing(radius: rOut - wid * 0.12, width: wid * 0.24, hot: 0.04) { 0.34 - 0.1 * day.sleepWeight[$0] }
        strokeRing(radius: rIn + wid * 0.1, width: wid * 0.14, hot: 0.02) { _ in 0.2 }

        // リングの中の光の粒
        let count = Int(520 * day.drawn / 24)
        for _ in 0..<count {
            let t = Double.random(in: 0..<1, using: &rng) * day.drawn
            let r = rIn + wid * CGFloat(Double.random(in: 0..<1, using: &rng))
            let radius = (1.1 + 1.6 * CGFloat(Double.random(in: 0..<1, using: &rng))) * g.u
            let a = 0.5 + 0.4 * Double.random(in: 0..<1, using: &rng)
            p.dot(g.point(hour: t, radius: r), radius: radius, color: p.hot(day.color(at: t), 0.12), alpha: a * 0.7)
        }
    }

    // MARK: 外縁の毛（スピキュール）

    static func drawFur(_ p: ArtPainter, day: ArtDay, rBase: CGFloat, count: Int, maxLen: CGFloat, rng: inout SeededGenerator) {
        let g = p.g
        p.ctx.setLineCap(.round)
        for _ in 0..<count {
            let t = Double.random(in: 0..<1, using: &rng) * day.drawn
            let e = CGFloat(day.strength(at: t))
            let len = g.R * (0.03 + maxLen * e * CGFloat(pow(Double.random(in: 0..<1, using: &rng), 0.9))) + g.R * 0.02 * CGFloat(Double.random(in: 0..<1, using: &rng))
            let a = RingArtRenderer.angle(hour: t)
            let bend = CGFloat(Double.random(in: 0..<1, using: &rng) - 0.5) * len * 0.55
            let p0 = g.point(angle: a, radius: rBase)
            let cp = g.point(angle: a + Double(bend / (rBase + len * 0.5)), radius: rBase + len * 0.55)
            let p1 = g.point(angle: a + Double(bend * 1.5 / (rBase + len)), radius: rBase + len)
            let c = p.hot(day.color(at: t), 0.08 + 0.22 * Double.random(in: 0..<1, using: &rng))
            p.ctx.setStrokeColor(p.cg(c, 0.14 + 0.3 * Double.random(in: 0..<1, using: &rng)))
            p.ctx.setLineWidth((0.5 + 0.8 * CGFloat(Double.random(in: 0..<1, using: &rng))) * g.u)
            p.ctx.move(to: p0)
            p.ctx.addQuadCurve(to: p1, control: cp)
            p.ctx.strokePath()
        }
    }

    // MARK: 花びら

    struct PetalOptions {
        var fillMul: Double = 1
        var strokeMul: Double = 1
        var vein = false
        var stipple = 0
    }

    /// 花びら1枚。角度aの方向に、baseRからlen（負なら内向き）まで伸びる滴形。幅はwid。
    static func drawPetal(_ p: ArtPainter, angle a: Double, baseR: CGFloat, len: CGFloat, wid: CGFloat, color col: RingRGB, alpha: Double, options o: PetalOptions, rng: inout SeededGenerator) {
        let g = p.g
        let dx = CGFloat(sin(a)), dy = CGFloat(-cos(a)), nx = CGFloat(cos(a)), ny = CGFloat(sin(a))
        let n = 26
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...n {
            let uu = Double(i) / Double(n)
            let w = wid / 2 * CGFloat(petalShape(uu))
            let r = baseR + len * CGFloat(uu)
            let bx = g.cx + dx * r, by = g.cy + dy * r
            left.append(CGPoint(x: bx - nx * w, y: by - ny * w))
            right.append(CGPoint(x: bx + nx * w, y: by + ny * w))
        }
        let path = CGMutablePath()
        path.move(to: left[0])
        for i in 1...n { path.addLine(to: left[i]) }
        for i in stride(from: n, through: 0, by: -1) { path.addLine(to: right[i]) }
        path.closeSubpath()

        let base = CGPoint(x: g.cx + dx * baseR, y: g.cy + dy * baseR)
        let tip = CGPoint(x: g.cx + dx * (baseR + len), y: g.cy + dy * (baseR + len))
        let fm = o.fillMul
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [p.cg(col, alpha * 0.15 * fm), p.cg(col, alpha * 0.7 * fm), p.cg(p.hot(col, 0.22), alpha * fm)] as CFArray,
                                     locations: [0, 0.45, 1]) {
            p.ctx.saveGState()
            p.ctx.addPath(path)
            p.ctx.clip()
            p.ctx.drawLinearGradient(gradient, start: base, end: tip, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            p.ctx.restoreGState()
        }
        p.ctx.setLineWidth(1.1 * g.u)
        p.ctx.setLineJoin(.round)
        p.ctx.setStrokeColor(p.cg(p.hot(col, 0.15), alpha * 0.8 * o.strokeMul))
        p.ctx.addPath(path)
        p.ctx.strokePath()

        if o.vein {
            let v0 = CGPoint(x: g.cx + dx * (baseR + len * 0.08), y: g.cy + dy * (baseR + len * 0.08))
            let v1 = CGPoint(x: g.cx + dx * (baseR + len * 0.85), y: g.cy + dy * (baseR + len * 0.85))
            p.line(v0, v1, width: 0.8 * g.u, color: p.hot(col, 0.3), alpha: alpha * 0.5)
        }
        for _ in 0..<o.stipple {
            let uu = 0.1 + 0.85 * Double.random(in: 0..<1, using: &rng)
            let w = wid / 2 * CGFloat(petalShape(uu)) * 0.85
            let off = CGFloat(Double.random(in: 0..<1, using: &rng) * 2 - 1) * w
            let r = baseR + len * CGFloat(uu)
            let pt = CGPoint(x: g.cx + dx * r + nx * off, y: g.cy + dy * r + ny * off)
            p.dot(pt, radius: (1 + 1.3 * CGFloat(Double.random(in: 0..<1, using: &rng))) * g.u, color: p.hot(col, 0.25), alpha: 0.6 * alpha + 0.2)
        }
    }

    /// 花びらの幅: 続いた時間の角度に応じて。
    static func petalWidth(g: ArtGeom, baseR: CGFloat, len: CGFloat, duration: Double, multiplier: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        let an = duration / 24 * 2 * Double.pi
        let rw = abs(baseR + len * 0.33)
        let w = 2 * rw * CGFloat(tan(min(1.1, an * 0.9) / 2)) * multiplier
        return RingArtRenderer.clamp(w, minimum, maximum)
    }

    // MARK: 中心のめしべ

    /// 24時間の色を小さな点にして、中心に散らす。
    static func drawPistil(_ p: ArtPainter, day: ArtDay, scale: CGFloat, rng: inout SeededGenerator) {
        let g = p.g
        p.dot(CGPoint(x: g.cx, y: g.cy), radius: g.R * 0.14 * scale, color: day.averageColor, alpha: 0.28)
        for i in 0..<day.count {
            for _ in 0..<3 {
                let t = (Double(i) + Double.random(in: 0..<1, using: &rng)) * DailyRingLayout.sliceHours
                let r = g.R * scale * CGFloat(0.02 + 0.075 * Double.random(in: 0..<1, using: &rng))
                p.dot(g.point(hour: t, radius: r), radius: (1.4 + 1.4 * CGFloat(Double.random(in: 0..<1, using: &rng))) * g.u, color: day.color(at: t), alpha: 0.55)
            }
        }
    }

    // MARK: A+B 花のコロナ

    static func drawFlowerCorona(_ p: ArtPainter, day: ArtDay, past: [ArtDay], rng: inout SeededGenerator) {
        let g = p.g
        let R = g.R
        let rIn = R * 0.45, rOut = R * 0.57

        // 内側に、過去の日の花びら（内向き・薄い）。古い日を先に描く。
        for j in stride(from: past.count - 1, through: 0, by: -1) {
            for e in past[j].episodes {
                let len = -(rIn * CGFloat(0.22 + 0.70 * e.strength)) * CGFloat(1 - 0.06 * Double(j))
                let wd = petalWidth(g: g, baseR: rIn, len: len, duration: e.duration, multiplier: 1.6, minimum: R * 0.06, maximum: R * 0.3)
                drawPetal(p, angle: RingArtRenderer.angle(hour: e.mid), baseR: rIn * 0.99, len: len, wid: wd,
                          color: DailyRingLayout.ringColor(for: e.kind), alpha: 0.22 - 0.02 * Double(j),
                          options: PetalOptions(fillMul: 0.3, strokeMul: 1.1), rng: &rng)
            }
        }

        drawRing(p, day: day, rIn: rIn, rOut: rOut, rng: &rng)
        drawFur(p, day: day, rBase: rOut - R * 0.012, count: Int(1800 * day.drawn / 24), maxLen: 0.16, rng: &rng)

        for e in day.episodes {
            let col = DailyRingLayout.ringColor(for: e.kind)
            let len = R * CGFloat(0.10 + 0.32 * e.strength)
            let wd = petalWidth(g: g, baseR: rOut, len: len, duration: e.duration, multiplier: 1.5, minimum: R * 0.09, maximum: R * 0.32)
            let a = RingArtRenderer.angle(hour: e.mid)
            drawPetal(p, angle: a, baseR: rOut * 0.985, len: len, wid: wd, color: col, alpha: 0.5,
                      options: PetalOptions(vein: true, stipple: Int(30 + e.duration * 80)), rng: &rng)
            drawPetal(p, angle: a, baseR: rOut * 0.985, len: len * 0.7, wid: wd * 0.6, color: p.hot(col, 0.12), alpha: 0.36, options: PetalOptions(), rng: &rng)
        }
        drawPistil(p, day: day, scale: 0.7, rng: &rng)
    }
}
