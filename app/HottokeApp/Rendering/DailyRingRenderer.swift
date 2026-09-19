import UIKit
import CoreGraphics

/// 「1日の輪」の静止画レンダラー（docs/22-app1-radial-redesign.md「表現方式の変更」）。
/// FlowingDataの「Cycle of Many」のような点描リング:
///  ・1周が24時間（0時が真上、時計回り）
///  ・活動ごとに決まった輪（外側から 静止 → 車移動 → 自転車 → 歩行 → 走行）
///  ・点の数がその時刻にその活動をしていた量。密なところは点が連なって光の帯に、疎なところはぱらぱら散る
///  ・暗い背景に、加算合成で発光感を出す
/// 座標は画面座標（y下向き）。今日の途中は現在時刻までしか点がなく、その先の輪は空のまま残る。
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
            drawTracks(ctx: ctx, center: center, rMax: rMax)
            drawDots(ctx: ctx, dots: dots, center: center, rMax: rMax)
            if density.isPartialDay {
                drawNowMarker(ctx: ctx, hour: density.drawnHours, center: center, rMax: rMax, side: sideF)
            }
            drawLabels(ctx: ctx, density: density, date: date, center: center, rMax: rMax, side: sideF, calendar: calendar)
        }
    }

    private static func daySeed(date: Date, calendar: Calendar) -> UInt64 {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return UInt64((c.year ?? 2026) * 10_000 + (c.month ?? 1) * 100 + (c.day ?? 1))
    }

    // MARK: - 座標

    private static func point(hour: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let v = DailyRingLayout.unitVector(forHour: hour)
        return CGPoint(x: center.x + CGFloat(v.dx) * radius, y: center.y + CGFloat(v.dy) * radius)
    }

    // MARK: - 背景・輪のレール

    private static func drawBackground(ctx: CGContext, side: CGFloat, center: CGPoint, seed: UInt64) {
        ctx.setFillColor(CGColor(red: 0.015, green: 0.015, blue: 0.04, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

        let colors = [
            CGColor(red: 0.07, green: 0.07, blue: 0.16, alpha: 1),
            CGColor(red: 0.015, green: 0.015, blue: 0.04, alpha: 1)
        ]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: side * 0.72, options: [.drawsAfterEndLocation])
        }

        // ごく淡い星のような点（日付から決まるので同じ日は同じ絵になる）。
        var generator = SeededGenerator(seed: seed &* 2654435761 &+ 17)
        for _ in 0..<60 {
            let x = CGFloat.random(in: 0...side, using: &generator)
            let y = CGFloat.random(in: 0...side, using: &generator)
            let r = CGFloat.random(in: 0.5...1.3, using: &generator)
            let a = CGFloat.random(in: 0.06...0.22, using: &generator)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: a))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }

    /// 各輪のうっすらしたレール（まだ点がない範囲でも輪の位置が分かるように）と、1時間ごとの目盛り。
    private static func drawTracks(ctx: CGContext, center: CGPoint, rMax: CGFloat) {
        ctx.saveGState()
        for kind in DailyRingLayout.ringOrder {
            let band = DailyRingLayout.band(for: kind)
            let outer = rMax * CGFloat(band.outer)
            let inner = rMax * CGFloat(band.inner)
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
            path.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
            let c = DailyRingLayout.ringColor(for: kind)
            ctx.setFillColor(CGColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 0.045))
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
        }

        // 1時間ごとの目盛り（0/6/12/18時は長く太く）
        for hour in 0..<24 {
            let major = hour % 6 == 0
            let p0 = point(hour: Double(hour), radius: rMax * 1.03, center: center)
            let p1 = point(hour: Double(hour), radius: rMax * (major ? 1.09 : 1.06), center: center)
            ctx.setLineWidth(major ? 2.5 : 1.2)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: major ? 0.7 : 0.25))
            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: - 点

    private static func drawDots(ctx: CGContext, dots: [RingDot], center: CGPoint, rMax: CGFloat) {
        let baseRadius = rMax * CGFloat(DailyRingLayout.dotRadiusFraction)
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        for kind in DailyRingLayout.ringOrder {
            let c = DailyRingLayout.ringColor(for: kind)
            let r = CGFloat(c.r), g = CGFloat(c.g), b = CGFloat(c.b)
            let kindDots = dots.filter { $0.kind == kind }
            guard !kindDots.isEmpty else { continue }

            // やわらかい光のにじみ（大きく薄い円）
            ctx.setFillColor(red: r, green: g, blue: b, alpha: 0.05)
            for dot in kindDots {
                let p = point(hour: dot.hour, radius: rMax * CGFloat(dot.radius), center: center)
                let rad = baseRadius * CGFloat(dot.size) * 2.6
                ctx.fillEllipse(in: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2))
            }
            // 点の本体
            for dot in kindDots {
                let p = point(hour: dot.hour, radius: rMax * CGFloat(dot.radius), center: center)
                let rad = baseRadius * CGFloat(dot.size)
                ctx.setFillColor(red: r, green: g, blue: b, alpha: CGFloat(dot.brightness) * 0.85)
                ctx.fillEllipse(in: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2))
            }
        }
        ctx.restoreGState()
    }

    /// 現在時刻の位置の目印（細い点線と、外周の小さな点）。
    private static func drawNowMarker(ctx: CGContext, hour: Double, center: CGPoint, rMax: CGFloat, side: CGFloat) {
        let inner = point(hour: hour, radius: rMax * 0.14, center: center)
        let outer = point(hour: hour, radius: rMax * 1.03, center: center)
        ctx.saveGState()
        ctx.setLineWidth(1.4)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
        ctx.setLineDash(phase: 0, lengths: [5, 6])
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

    // MARK: - 文字（0/6/12/18時、日付、輪の凡例）

    private static func drawText(_ text: String, at anchor: CGPoint, fontSize: CGFloat, weight: UIFont.Weight, alpha: CGFloat, leftAligned: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: UIColor(white: 1, alpha: alpha)
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let x = leftAligned ? anchor.x : anchor.x - size.width / 2
        string.draw(at: CGPoint(x: x, y: anchor.y - size.height / 2))
    }

    private static func drawLabels(ctx: CGContext, density: DailyRingDensity, date: Date, center: CGPoint, rMax: CGFloat, side: CGFloat, calendar: Calendar) {
        for hour in [0, 6, 12, 18] {
            let p = point(hour: Double(hour), radius: rMax * 1.16, center: center)
            drawText("\(hour)", at: p, fontSize: side * 0.030, weight: .semibold, alpha: 0.75)
        }

        // 日付は左上の角に。
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        drawText(String(format: "%04d.%d.%d", c.year ?? 0, c.month ?? 0, c.day ?? 0),
                 at: CGPoint(x: side * 0.045, y: side * 0.05), fontSize: side * 0.030, weight: .medium, alpha: 0.7, leftAligned: true)
        if density.isPartialDay {
            let totalMinutes = Int(density.drawnHours * 60)
            drawText(String(format: "%d:%02d 時点", totalMinutes / 60, totalMinutes % 60),
                     at: CGPoint(x: side * 0.045, y: side * 0.09), fontSize: side * 0.024, weight: .regular, alpha: 0.5, leftAligned: true)
        }

        // 輪の凡例（左下の角）。外側の輪から順に、色の点と活動名。
        let lineHeight = side * 0.036
        let top = side * 0.955 - lineHeight * CGFloat(DailyRingLayout.ringOrder.count - 1)
        for (i, kind) in DailyRingLayout.ringOrder.enumerated() {
            let y = top + lineHeight * CGFloat(i)
            let color = DailyRingLayout.ringColor(for: kind)
            let dotR = side * 0.0065
            ctx.setFillColor(red: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: 0.95)
            ctx.fillEllipse(in: CGRect(x: side * 0.05 - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2))
            drawText(kind.displayName, at: CGPoint(x: side * 0.068, y: y), fontSize: side * 0.022, weight: .regular, alpha: 0.6, leftAligned: true)
        }
        drawText("外側の輪から", at: CGPoint(x: side * 0.045, y: top - lineHeight * 0.95), fontSize: side * 0.018, weight: .regular, alpha: 0.35, leftAligned: true)
    }
}
