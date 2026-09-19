import UIKit
import CoreGraphics

/// 「1日の輪」の静止画レンダラー（docs/22-app1-radial-redesign.md）。
///
/// 描き方の流れ:
///  1. 使う活動種別ごとに、既存の数学模様（KaleidoscopeRenderer.renderPatternDiskImage）を
///     「白い円盤状の模様」として1枚ずつ描く（回転コピー・鏡映はしない）。
///  2. 画像の全ピクセルについて「角度→時刻」「中心からの距離」を求め、
///       ・距離が、その時刻の半径カーブ（DailyRingProfile.radiusFraction）の内側なら描く
///       ・その時刻の活動種別の重み（クロスフェード）で、各種別の模様を混ぜる
///       ・色は時刻に沿った連続グラデーション（DailyRingLayout.color）
///     として色付けする。今日の途中なら現在時刻までの角度しか描かず、その先は空白のまま。
///  3. 背景・目盛り・輪郭の発光・現在時刻の目印・文字をUIKitで重ねてUIImageにする。
///
/// 座標は画面座標（y下向き）。時刻tの方向は (sin, -cos) で、0時が真上・時計回り。
enum DailyRingRenderer {

    static let defaultSize: CGFloat = 1080

    /// 最大半径 = 画像の一辺 × この値。外側に目盛りと文字の余白を残す。
    private static let maxRadiusRatio: CGFloat = 0.40

    private static let whitePalette = KaleidoscopePalette(
        id: "ring-white", name: "",
        hexColors: Array(repeating: "#ffffff", count: 6),
        isLocked: false
    )

    /// 活動種別ごとの模様の細かさ・周期パラメータ。
    private static func patternSettings(for style: PatternStyle) -> (detail: Double, symmetryCount: Int) {
        switch style {
        case .fractal: return (0.85, 1)      // 円全体に幹を広げるため周期1
        case .spirograph: return (0.8, 3)
        case .waves: return (0.7, 3)
        case .tiling: return (0.6, 3)
        case .lissajous: return (0.8, 3)
        default: return (0.6, 3)
        }
    }

    // MARK: - 公開API

    static func render(profile: DailyRingProfile, date: Date, size: CGFloat = defaultSize, calendar: Calendar = .current) -> UIImage {
        let side = max(64, Int(size.rounded()))
        let canvas = CGSize(width: side, height: side)
        let center = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        let rMax = CGFloat(side) * maxRadiusRatio
        let seed = daySeed(date: date, calendar: calendar)

        let body = renderBody(profile: profile, side: side, rMax: rMax, seed: seed)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { rc in
            let ctx = rc.cgContext
            drawBackground(ctx: ctx, side: CGFloat(side), center: center, seed: seed)
            drawGuides(ctx: ctx, center: center, rMax: rMax)

            if let body {
                let image = UIImage(cgImage: body)
                let rect = CGRect(origin: .zero, size: canvas)
                image.draw(in: rect)
                // 発光感を出すため、加算合成でもう一度うっすら重ねる。
                image.draw(in: rect, blendMode: .plusLighter, alpha: 0.5)
            }

            drawOutline(ctx: ctx, profile: profile, center: center, rMax: rMax)
            if profile.isPartialDay {
                drawNowMarker(ctx: ctx, hour: profile.drawnHours, center: center, rMax: rMax, side: CGFloat(side))
            }
            drawCenterGlow(ctx: ctx, center: center, radius: rMax * 0.16)
            drawLabels(ctx: ctx, profile: profile, date: date, center: center, rMax: rMax, side: CGFloat(side), calendar: calendar)
        }
    }

    // MARK: - 本体（模様 × 半径 × 色 × 種別のクロスフェード）

    private static func daySeed(date: Date, calendar: Calendar) -> UInt64 {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return UInt64((c.year ?? 2026) * 10_000 + (c.month ?? 1) * 100 + (c.day ?? 1))
    }

    /// 白い円盤状の模様を、画像全体と同じ大きさ・同じ座標のRGBA配列に描き込んで返す。
    private static func patternLayer(style: PatternStyle, side: Int, rMax: CGFloat, seed: UInt64) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let settings = patternSettings(for: style)
        guard let disk = KaleidoscopeRenderer.renderPatternDiskImage(
            style: style, radius: rMax, palette: whitePalette,
            detail: settings.detail, seed: seed, time: 3.0, symmetryCount: settings.symmetryCount
        ) else { return nil }
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            let dim = CGFloat(disk.width)
            let origin = (CGFloat(side) - dim) / 2
            ctx.draw(disk, in: CGRect(x: origin, y: origin, width: dim, height: dim))
            return true
        }
        return drawn ? pixels : nil
    }

    private static func renderBody(profile: DailyRingProfile, side: Int, rMax: CGFloat, seed: UInt64) -> CGImage? {
        let drawn = min(DailyRingLayout.hoursPerDay, profile.drawnHours)
        guard drawn > 0, !profile.slots.isEmpty else { return nil }

        // 使う活動種別ごとの模様レイヤー（同じ形のスタイルは1回だけ描く）。
        let kinds = profile.usedKinds
        var styleCache: [PatternStyle: [UInt8]] = [:]
        var layers: [[UInt8]] = []
        for kind in kinds {
            let style = DailyRingLayout.patternStyle(for: kind)
            if styleCache[style] == nil {
                styleCache[style] = patternLayer(style: style, side: side, rMax: rMax, seed: seed) ?? [UInt8](repeating: 0, count: side * side * 4)
            }
            layers.append(styleCache[style] ?? [])
        }
        var kindIndex: [ActivityKind: Int] = [:]
        for (i, kind) in kinds.enumerated() { kindIndex[kind] = i }

        // 時刻ごとの半径・色・種別の重みを、細かい表(LUT)にしておく（ピクセルごとに再計算しない）。
        let lutCount = 7200
        let rMaxD = Double(rMax)
        var radiusLUT = [Double](repeating: 0, count: lutCount + 1)
        var colorLUT = [RingRGB](repeating: RingRGB(r: 0, g: 0, b: 0), count: lutCount + 1)
        var weightLUT = [[Double]](repeating: [Double](repeating: 0, count: lutCount + 1), count: kinds.count)
        for i in 0...lutCount {
            let t = Double(i) / Double(lutCount) * DailyRingLayout.hoursPerDay
            let tClamped = min(t, drawn)
            radiusLUT[i] = profile.radiusFraction(at: tClamped) * rMaxD
            colorLUT[i] = DailyRingLayout.color(atHour: t)
            for (kind, weight) in profile.kindWeights(at: min(t, drawn - 1e-9)) {
                if let ki = kindIndex[kind] { weightLUT[ki][i] += weight }
            }
        }

        let twoPi = 2 * Double.pi
        let drawnRadians = drawn / DailyRingLayout.hoursPerDay * twoPi
        let isPartial = profile.isPartialDay
        let cx = Double(side) / 2, cy = Double(side) / 2
        let limit = (rMaxD + 2) * (rMaxD + 2)
        let patternGain = 1.4

        var out = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            let dy = Double(y) + 0.5 - cy
            for x in 0..<side {
                let dx = Double(x) + 0.5 - cx
                let d2 = dx * dx + dy * dy
                if d2 > limit { continue }
                let dist = d2.squareRoot()

                var theta = atan2(dx, -dy)
                if theta < 0 { theta += twoPi }

                // 今日の途中: 現在時刻より先は空白。境目は1ピクセルほどぼかす。
                var angularCoverage = 1.0
                if isPartial {
                    if theta > drawnRadians + 0.02 { continue }
                    angularCoverage = min(1, max(0, (drawnRadians - theta) * dist + 0.5))
                    angularCoverage *= min(1, max(0, theta * dist + 0.5))
                    if angularCoverage <= 0 { continue }
                }

                let li = min(lutCount, Int(theta / twoPi * Double(lutCount) + 0.5))
                let rOut = radiusLUT[li]
                let radialCoverage = min(1, max(0, rOut - dist + 0.5))
                if radialCoverage <= 0 { continue }

                // 面の薄い塗り: 外側ほど濃い（活動量が多いところほど明るく見える）。
                let bodyAlpha = 0.06 + 0.30 * (dist / rMaxD)

                let pixelIndex = (y * side + x) * 4
                var total = 0.0
                for ki in 0..<kinds.count {
                    let w = weightLUT[ki][li]
                    if w < 0.002 { continue }
                    let patternAlpha = min(1, Double(layers[ki][pixelIndex + 3]) / 255 * patternGain)
                    let a = 1 - (1 - patternAlpha) * (1 - bodyAlpha)
                    total += w * a
                }
                total = min(1, total) * radialCoverage * angularCoverage
                if total <= 0 { continue }

                let c = colorLUT[li]
                out[pixelIndex] = UInt8(min(255, max(0, c.r * total * 255 + 0.5)))
                out[pixelIndex + 1] = UInt8(min(255, max(0, c.g * total * 255 + 0.5)))
                out[pixelIndex + 2] = UInt8(min(255, max(0, c.b * total * 255 + 0.5)))
                out[pixelIndex + 3] = UInt8(min(255, max(0, total * 255 + 0.5)))
            }
        }

        guard let provider = CGDataProvider(data: Data(out) as CFData) else { return nil }
        return CGImage(
            width: side, height: side,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    // MARK: - 座標

    private static func point(hour: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let v = DailyRingLayout.unitVector(forHour: hour)
        return CGPoint(x: center.x + CGFloat(v.dx) * radius, y: center.y + CGFloat(v.dy) * radius)
    }

    private static func uiColor(_ c: RingRGB, whiten: Double = 0, alpha: CGFloat = 1) -> CGColor {
        let w = min(1, max(0, whiten))
        return CGColor(
            red: CGFloat(c.r + (1 - c.r) * w),
            green: CGFloat(c.g + (1 - c.g) * w),
            blue: CGFloat(c.b + (1 - c.b) * w),
            alpha: alpha
        )
    }

    // MARK: - 背景・目盛り

    private static func drawBackground(ctx: CGContext, side: CGFloat, center: CGPoint, seed: UInt64) {
        ctx.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

        let colors = [
            CGColor(red: 0.10, green: 0.09, blue: 0.20, alpha: 1),
            CGColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1)
        ]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: side * 0.72, options: [.drawsAfterEndLocation])
        }

        // ごく淡い星のような点（日付から決まるので同じ日は同じ絵になる）。
        var generator = SeededGenerator(seed: seed &* 2654435761 &+ 17)
        for _ in 0..<70 {
            let x = CGFloat.random(in: 0...side, using: &generator)
            let y = CGFloat.random(in: 0...side, using: &generator)
            let r = CGFloat.random(in: 0.6...1.6, using: &generator)
            let a = CGFloat.random(in: 0.08...0.30, using: &generator)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: a))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }

    /// うっすらした目盛りの円（500/1500/3000歩）と、1時間ごとの目盛り。
    private static func drawGuides(ctx: CGContext, center: CGPoint, rMax: CGFloat) {
        ctx.saveGState()
        ctx.setLineWidth(1)

        // 最小半径の円と、歩数の目盛りの円
        var fractions = [DailyRingLayout.minRadiusFraction]
        fractions += DailyRingLayout.guideStepsMarks.map { DailyRingLayout.radiusFraction(forEffectiveSteps: Double($0)) }
        for (i, f) in fractions.enumerated() {
            let r = rMax * CGFloat(f)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: i == 0 ? 0.05 : 0.09))
            ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
        // 最大半径の外周
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
        ctx.strokeEllipse(in: CGRect(x: center.x - rMax, y: center.y - rMax, width: rMax * 2, height: rMax * 2))

        // 1時間ごとの目盛り（0/6/12/18時は長く太く）
        for hour in 0..<24 {
            let major = hour % 6 == 0
            let inner = rMax * (major ? 1.03 : 1.03)
            let outer = rMax * (major ? 1.09 : 1.06)
            let p0 = point(hour: Double(hour), radius: inner, center: center)
            let p1 = point(hour: Double(hour), radius: outer, center: center)
            ctx.setLineWidth(major ? 2.5 : 1.2)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: major ? 0.7 : 0.28))
            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: - 輪郭の発光

    private static func drawOutline(ctx: CGContext, profile: DailyRingProfile, center: CGPoint, rMax: CGFloat) {
        let drawn = min(DailyRingLayout.hoursPerDay, profile.drawnHours)
        guard drawn > 0, !profile.slots.isEmpty else { return }
        let steps = max(2, Int(drawn * 60))
        var points: [CGPoint] = []
        points.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = drawn * Double(i) / Double(steps)
            points.append(point(hour: t, radius: rMax * CGFloat(profile.radiusFraction(at: t)), center: center))
        }

        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let passes: [(width: CGFloat, alpha: CGFloat, whiten: Double, additive: Bool)] = [
            (16, 0.10, 0.0, true),
            (7, 0.22, 0.1, true),
            (2.6, 0.95, 0.35, false)
        ]
        for pass in passes {
            ctx.setBlendMode(pass.additive ? .plusLighter : .normal)
            ctx.setLineWidth(pass.width)
            for i in 0..<steps {
                let tMid = drawn * (Double(i) + 0.5) / Double(steps)
                ctx.setStrokeColor(uiColor(DailyRingLayout.color(atHour: tMid), whiten: pass.whiten, alpha: pass.alpha))
                ctx.move(to: points[i])
                ctx.addLine(to: points[i + 1])
                ctx.strokePath()
            }
        }

        // 今日の途中: 0時側と現在時刻側の、中心へ向かう縁を細い線で閉じる。
        if profile.isPartialDay {
            ctx.setBlendMode(.plusLighter)
            ctx.setLineWidth(1.6)
            for t in [0.0, drawn] {
                ctx.setStrokeColor(uiColor(DailyRingLayout.color(atHour: t), whiten: 0.2, alpha: 0.35))
                ctx.move(to: center)
                ctx.addLine(to: point(hour: t, radius: rMax * CGFloat(profile.radiusFraction(at: t)), center: center))
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }

    /// 現在時刻の位置の目印（細い線と、外周の小さな点）。
    private static func drawNowMarker(ctx: CGContext, hour: Double, center: CGPoint, rMax: CGFloat, side: CGFloat) {
        let inner = point(hour: hour, radius: rMax * 0.12, center: center)
        let outer = point(hour: hour, radius: rMax * 1.03, center: center)
        ctx.saveGState()
        ctx.setLineWidth(1.6)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
        ctx.setLineDash(phase: 0, lengths: [6, 6])
        ctx.move(to: inner)
        ctx.addLine(to: outer)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        let dotRadius = side * 0.008
        ctx.setBlendMode(.plusLighter)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.25))
        ctx.fillEllipse(in: CGRect(x: outer.x - dotRadius * 2.4, y: outer.y - dotRadius * 2.4, width: dotRadius * 4.8, height: dotRadius * 4.8))
        ctx.setBlendMode(.normal)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.fillEllipse(in: CGRect(x: outer.x - dotRadius, y: outer.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        ctx.restoreGState()
    }

    private static func drawCenterGlow(ctx: CGContext, center: CGPoint, radius: CGFloat) {
        let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 0.5), CGColor(red: 1, green: 1, blue: 1, alpha: 0)]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        ctx.restoreGState()
    }

    // MARK: - 文字（0/6/12/18時、日付）

    private static func drawText(_ text: String, at center: CGPoint, fontSize: CGFloat, weight: UIFont.Weight, alpha: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: UIColor(white: 1, alpha: alpha)
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }

    private static func drawLabels(ctx: CGContext, profile: DailyRingProfile, date: Date, center: CGPoint, rMax: CGFloat, side: CGFloat, calendar: Calendar) {
        for hour in [0, 6, 12, 18] {
            let p = point(hour: Double(hour), radius: rMax * 1.16, center: center)
            drawText("\(hour)", at: p, fontSize: side * 0.030, weight: .semibold, alpha: 0.75)
        }

        let c = calendar.dateComponents([.year, .month, .day], from: date)
        var label = String(format: "%04d.%d.%d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        if profile.isPartialDay {
            let totalMinutes = Int(profile.drawnHours * 60)
            label += String(format: "  %d:%02d時点", totalMinutes / 60, totalMinutes % 60)
        }
        drawText(label, at: CGPoint(x: center.x, y: side * 0.955), fontSize: side * 0.026, weight: .regular, alpha: 0.55)
    }
}
