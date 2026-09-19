import UIKit
import CoreGraphics

/// 「1日の輪」の静止画レンダラー（docs/22-app1-radial-redesign.md「半径の意味づけを『活動の強さの山』に変更」）。
/// FlowingDataの「Cycle of Many」のような点描を、花・オーロラ・星雲のような光の絵に仕上げる:
///  ・1周が24時間（0時が真上、時計回り）。今日の途中は現在時刻までだけ描き、その先は空。
///  ・半径 = その時刻の活動の強さ。中心の小さな空洞から外側の輪郭までを点で埋める。
///  ・色 = 活動の種類（境目は割合で混ざる）。点の詰まり = その状態だった頻度。
///  ・中心付近は小さく細かい点、外縁ほど大きく明るい点。外縁には光の飛沫、内側には少数の大きな柔らかい光（ボケ）。
///  ・輪郭を白い線で縁取らない。中心は密度がなだらかに濃くなる。暗い背景に加算合成で発光させる。
/// 座標は画面座標（y下向き）。
enum DailyRingRenderer {

    static let defaultSize: CGFloat = 1080

    /// 最大半径 = 画像の一辺 × この値。外側に目盛りと文字の余白を残す。
    private static let maxRadiusRatio: CGFloat = 0.40

    static func render(density: DailyRingDensity, date: Date, size: CGFloat = defaultSize, calendar: Calendar = .current) -> UIImage {
        let side = max(64, Int(size.rounded()))
        let sideF = CGFloat(side)
        let canvas = CGSize(width: side, height: side)
        let center = CGPoint(x: sideF / 2, y: sideF / 2)
        let rMax = sideF * maxRadiusRatio
        let seed = daySeed(date: date, calendar: calendar)
        let dots = DailyRingLayout.makeDots(density: density, seed: seed)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { rc in
            let ctx = rc.cgContext
            drawBackground(ctx: ctx, side: sideF, center: center, seed: seed)
            drawGuides(ctx: ctx, center: center, rMax: rMax, side: sideF)
            drawHaze(ctx: ctx, dots: dots, center: center, rMax: rMax)
            drawDots(ctx: ctx, dots: dots, center: center, rMax: rMax)
            if density.isPartialDay {
                drawNowMarker(ctx: ctx, hour: density.drawnHours, center: center, rMax: rMax, side: sideF)
            }
            drawLabels(ctx: ctx, density: density, date: date, center: center, rMax: rMax, side: sideF, calendar: calendar)
        }
    }

    /// アーカイブ用のサムネイル（文字・目盛りなしの簡易描画）。小さくても点が見えるよう、点は大きめに描く。
    static func renderThumbnail(slices: DailyRingSlices, size: CGFloat = 240, theme: RingTheme = .standard) -> UIImage {
        let side = max(32, size)
        let center = CGPoint(x: side / 2, y: side / 2)
        let rMax = side * 0.47
        let density = DailyRingLayout.makeDensity(slices: slices)
        let digits = slices.dateKey.filter { $0.isNumber }
        let dots = DailyRingLayout.makeDots(density: density, seed: UInt64(digits) ?? 1)
        let dotScale: CGFloat = 2.6

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { rc in
            let ctx = rc.cgContext
            ctx.setFillColor(CGColor(red: 0.012, green: 0.014, blue: 0.04, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            if let g = gradient(0.10, 0.11, 0.26, 0.9) {
                ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: side * 0.6, options: [])
            }
            ctx.setBlendMode(.plusLighter)
            let baseRadius = rMax * CGFloat(DailyRingLayout.dotRadiusFraction) * dotScale
            for dot in dots where dot.role != .bokeh {
                let base = theme.color(for: dot.kind)
                let c = lighten(base, 0.04 + 0.30 * pow(dot.depth, 2.4) * dot.brightness)
                let alphaScale: CGFloat = (dot.kind == .stationary || dot.kind == .sleeping) ? 0.55 : 1.0
                let p = point(hour: dot.hour, radius: rMax * CGFloat(dot.radius), center: center)
                let rad = baseRadius * CGFloat(dot.size)
                ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: CGFloat(dot.brightness) * 0.85 * alphaScale)
                ctx.fillEllipse(in: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2))
            }
        }
    }

    private static func daySeed(date: Date, calendar: Calendar) -> UInt64 {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return UInt64((c.year ?? 2026) * 10_000 + (c.month ?? 1) * 100 + (c.day ?? 1))
    }

    // MARK: - 座標・色

    private static func point(hour: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let v = DailyRingLayout.unitVector(forHour: hour)
        return CGPoint(x: center.x + CGFloat(v.dx) * radius, y: center.y + CGFloat(v.dy) * radius)
    }

    /// 色を白に近づける（w=0で元の色、1で白）。
    private static func lighten(_ c: RingRGB, _ w: Double) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let k = min(1, max(0, w))
        return (CGFloat(c.r + (1 - c.r) * k), CGFloat(c.g + (1 - c.g) * k), CGFloat(c.b + (1 - c.b) * k))
    }

    private static func gradient(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGGradient? {
        CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: r, green: g, blue: b, alpha: a), CGColor(red: r, green: g, blue: b, alpha: 0)] as CFArray,
            locations: [0, 1]
        )
    }

    // MARK: - 背景

    private static func drawBackground(ctx: CGContext, side: CGFloat, center: CGPoint, seed: UInt64) {
        ctx.setFillColor(CGColor(red: 0.010, green: 0.012, blue: 0.034, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

        // 深い紺のグラデーション（中心がわずかに明るい）
        if let g = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: 0.055, green: 0.06, blue: 0.16, alpha: 1), CGColor(red: 0.010, green: 0.012, blue: 0.034, alpha: 1)] as CFArray,
            locations: [0, 1]
        ) {
            ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: side * 0.72, options: [.drawsAfterEndLocation])
        }

        // ほんのり色味のある星雲のにじみ（位置は固定）
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        if let g = gradient(0.35, 0.20, 0.75, 0.11) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: side * 0.22, y: side * 0.80), startRadius: 0, endCenter: CGPoint(x: side * 0.22, y: side * 0.80), endRadius: side * 0.42, options: [])
        }
        if let g = gradient(0.10, 0.45, 0.60, 0.09) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: side * 0.82, y: side * 0.20), startRadius: 0, endCenter: CGPoint(x: side * 0.82, y: side * 0.20), endRadius: side * 0.40, options: [])
        }
        ctx.restoreGState()

        // 星屑（日付から決まるので同じ日は同じ絵になる）
        var generator = SeededGenerator(seed: seed &* 2654435761 &+ 17)
        for i in 0..<180 {
            let x = CGFloat.random(in: 0...side, using: &generator)
            let y = CGFloat.random(in: 0...side, using: &generator)
            let big = i % 14 == 0
            let r = big ? CGFloat.random(in: 1.0...1.9, using: &generator) : CGFloat.random(in: 0.4...1.1, using: &generator)
            let a = CGFloat.random(in: 0.08...(big ? 0.55 : 0.28), using: &generator)
            let tint = CGFloat.random(in: 0...1, using: &generator)
            ctx.setFillColor(CGColor(red: 0.85 + 0.15 * tint, green: 0.88, blue: 1.0 - 0.2 * tint, alpha: a))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            if big, let g = gradient(0.8, 0.85, 1, a * 0.4) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r * 5, options: [])
            }
        }

        // ゆるいビネット
        if let g = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: 0, green: 0, blue: 0, alpha: 0), CGColor(red: 0, green: 0, blue: 0, alpha: 0.55)] as CFArray,
            locations: [0, 1]
        ) {
            ctx.drawRadialGradient(g, startCenter: center, startRadius: side * 0.45, endCenter: center, endRadius: side * 0.78, options: [.drawsAfterEndLocation])
        }
    }

    // MARK: - 目盛り（控えめに）

    private static func drawGuides(ctx: CGContext, center: CGPoint, rMax: CGFloat, side: CGFloat) {
        ctx.saveGState()
        ctx.setLineWidth(1)

        // 強さの目安の円（弱・中・強）。ごく薄い点線（中心の縁取りや輪郭の白い線は描かない）。
        ctx.setLineDash(phase: 0, lengths: [2, 6])
        for guide in DailyRingLayout.guideIntensities {
            let r = rMax * CGFloat(DailyRingLayout.radiusFraction(forIntensity: guide.stepsPerMinute))
            ctx.setStrokeColor(CGColor(red: 0.8, green: 0.85, blue: 1, alpha: 0.14))
            ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
        ctx.setLineDash(phase: 0, lengths: [])

        // 時計のような1時間ごとの目盛り（0/6/12/18時は少し長く）
        for hour in 0..<24 {
            let major = hour % 6 == 0
            let p0 = point(hour: Double(hour), radius: rMax * 1.04, center: center)
            let p1 = point(hour: Double(hour), radius: rMax * (major ? 1.09 : 1.065), center: center)
            ctx.setLineWidth(major ? 1.6 : 1.0)
            ctx.setStrokeColor(CGColor(red: 0.85, green: 0.9, blue: 1, alpha: major ? 0.5 : 0.2))
            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.strokePath()
        }
        ctx.restoreGState()

        // 目安の円のラベル（0時の軸のすぐ右に、ごく小さく）
        for guide in DailyRingLayout.guideIntensities {
            let r = rMax * CGFloat(DailyRingLayout.radiusFraction(forIntensity: guide.stepsPerMinute))
            drawText(guide.label, at: CGPoint(x: center.x + 7, y: center.y - r - side * 0.010), fontSize: side * 0.016, weight: .regular, alpha: 0.32, leftAligned: true)
        }
    }

    // MARK: - 光のにじみ（星雲のような霞）

    private static func drawHaze(ctx: CGContext, dots: [RingDot], center: CGPoint, rMax: CGFloat) {
        let baseRadius = rMax * CGFloat(DailyRingLayout.dotRadiusFraction)
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        var gradients: [ActivityKind: CGGradient] = [:]
        for kind in DailyRingLayout.kindOrder {
            let c = DailyRingLayout.ringColor(for: kind)
            let alpha: CGFloat = (kind == .stationary || kind == .sleeping) ? 0.07 : 0.13
            if let g = gradient(CGFloat(c.r), CGFloat(c.g), CGFloat(c.b), alpha) { gradients[kind] = g }
        }
        var n = 0
        for dot in dots where dot.role == .dot {
            n += 1
            if n % 11 != 0 { continue }
            guard let g = gradients[dot.kind] else { continue }
            let p = point(hour: dot.hour, radius: rMax * CGFloat(dot.radius), center: center)
            let rad = baseRadius * (7 + 6 * CGFloat(dot.depth))
            ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: rad, options: [])
        }
        ctx.restoreGState()
    }

    // MARK: - 点

    private static func drawDots(ctx: CGContext, dots: [RingDot], center: CGPoint, rMax: CGFloat) {
        let baseRadius = rMax * CGFloat(DailyRingLayout.dotRadiusFraction)
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)

        for dot in dots where dot.role != .bokeh {
            let base = DailyRingLayout.ringColor(for: dot.kind)
            // 中心に近いほど濃く深い色、外縁ほど白に近づく（発光の芯）。
            let whiten = 0.04 + 0.34 * pow(dot.depth, 2.4) * dot.brightness
            let c = lighten(base, whiten)
            let alphaScale: CGFloat = (dot.kind == .stationary || dot.kind == .sleeping) ? 0.5 : 1.0
            let p = point(hour: dot.hour, radius: rMax * CGFloat(dot.radius), center: center)
            let rad = baseRadius * CGFloat(dot.size)

            // 大きめの点だけ、やわらかい光のにじみを添える
            if dot.size > 1.0 || dot.role == .spray {
                let haloRad = rad * 2.6
                ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: 0.06 * alphaScale * CGFloat(dot.brightness))
                ctx.fillEllipse(in: CGRect(x: p.x - haloRad, y: p.y - haloRad, width: haloRad * 2, height: haloRad * 2))
            }
            ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: CGFloat(dot.brightness) * 0.82 * alphaScale)
            ctx.fillEllipse(in: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2))
        }

        // ボケ: 大きくやわらかい光の粒（奥行き）
        var gradients: [ActivityKind: CGGradient] = [:]
        for kind in DailyRingLayout.kindOrder {
            let c = lighten(DailyRingLayout.ringColor(for: kind), 0.25)
            if let g = gradient(c.r, c.g, c.b, 1) { gradients[kind] = g }
        }
        for dot in dots where dot.role == .bokeh {
            guard let g = gradients[dot.kind] else { continue }
            let p = point(hour: dot.hour, radius: rMax * CGFloat(dot.radius), center: center)
            let rad = baseRadius * CGFloat(dot.size)
            ctx.saveGState()
            ctx.setAlpha(CGFloat(dot.brightness) * 0.28)
            ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: rad, options: [])
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    /// 現在時刻の位置の目印（細い点線と、外周の小さな点）。
    private static func drawNowMarker(ctx: CGContext, hour: Double, center: CGPoint, rMax: CGFloat, side: CGFloat) {
        let inner = point(hour: hour, radius: rMax * 0.05, center: center)
        let outer = point(hour: hour, radius: rMax * 1.04, center: center)
        ctx.saveGState()
        ctx.setLineWidth(1.2)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.42))
        ctx.setLineDash(phase: 0, lengths: [4, 6])
        ctx.move(to: inner)
        ctx.addLine(to: outer)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        let dotRadius = side * 0.007
        ctx.setBlendMode(.plusLighter)
        if let g = gradient(1, 1, 1, 0.5) {
            ctx.drawRadialGradient(g, startCenter: outer, startRadius: 0, endCenter: outer, endRadius: dotRadius * 4, options: [])
        }
        ctx.setBlendMode(.normal)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.fillEllipse(in: CGRect(x: outer.x - dotRadius, y: outer.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        ctx.restoreGState()
    }

    // MARK: - 文字（小さく上品に）

    private static func drawText(_ text: String, at anchor: CGPoint, fontSize: CGFloat, weight: UIFont.Weight, alpha: CGFloat, leftAligned: Bool = false, rightAligned: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: UIColor(white: 1, alpha: alpha),
            .kern: fontSize * 0.04
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let x = leftAligned ? anchor.x : (rightAligned ? anchor.x - size.width : anchor.x - size.width / 2)
        string.draw(at: CGPoint(x: x, y: anchor.y - size.height / 2))
    }

    private static func drawLabels(ctx: CGContext, density: DailyRingDensity, date: Date, center: CGPoint, rMax: CGFloat, side: CGFloat, calendar: Calendar) {
        for hour in [0, 6, 12, 18] {
            let p = point(hour: Double(hour), radius: rMax * 1.17, center: center)
            drawText("\(hour)", at: p, fontSize: side * 0.026, weight: .regular, alpha: 0.6)
        }

        // 日付は左上、今日は「時点」も
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        drawText(String(format: "%04d.%d.%d", c.year ?? 0, c.month ?? 0, c.day ?? 0),
                 at: CGPoint(x: side * 0.045, y: side * 0.05), fontSize: side * 0.028, weight: .light, alpha: 0.7, leftAligned: true)
        if density.isPartialDay {
            let totalMinutes = Int(density.drawnHours * 60)
            drawText(String(format: "%d:%02d 時点", totalMinutes / 60, totalMinutes % 60),
                     at: CGPoint(x: side * 0.045, y: side * 0.086), fontSize: side * 0.021, weight: .light, alpha: 0.45, leftAligned: true)
        }

        // 凡例（左下）: 色 = 活動の種類
        let lineHeight = side * 0.033
        let top = side * 0.955 - lineHeight * CGFloat(DailyRingLayout.kindOrder.count - 1)
        for (i, kind) in DailyRingLayout.kindOrder.enumerated() {
            let y = top + lineHeight * CGFloat(i)
            let color = DailyRingLayout.ringColor(for: kind)
            let dotR = side * 0.0055
            ctx.setFillColor(red: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: 0.95)
            ctx.fillEllipse(in: CGRect(x: side * 0.05 - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2))
            drawText(kind.displayName, at: CGPoint(x: side * 0.066, y: y), fontSize: side * 0.019, weight: .light, alpha: 0.6, leftAligned: true)
        }
        drawText("色 = 活動", at: CGPoint(x: side * 0.045, y: top - lineHeight * 0.95), fontSize: side * 0.016, weight: .light, alpha: 0.38, leftAligned: true)

        // 半径の読み方（右下）
        drawText("外へ行くほど活発", at: CGPoint(x: side * 0.955, y: side * 0.955), fontSize: side * 0.019, weight: .light, alpha: 0.5, rightAligned: true)
        drawText("半径 = 活動の強さ", at: CGPoint(x: side * 0.955, y: side * 0.955 - lineHeight), fontSize: side * 0.016, weight: .light, alpha: 0.38, rightAligned: true)
    }
}
