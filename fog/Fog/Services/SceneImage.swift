import UIKit
import CoreImage

/// 背景の景色。写真を同梱しないため、夕暮れの街をコードで描く。
enum SceneImage {
    static let defaultSize = CGSize(width: 786, height: 1704)

    static func makeDefault() -> UIImage {
        let size = defaultSize
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let cs = CGColorSpaceCreateDeviceRGB()
            func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
                CGColor(red: r, green: g, blue: b, alpha: a)
            }
            // 空
            let sky = CGGradient(colorsSpace: cs, colors: [
                color(0.10, 0.12, 0.35), color(0.45, 0.28, 0.55), color(0.98, 0.55, 0.35), color(1.0, 0.82, 0.5)
            ] as CFArray, locations: [0, 0.35, 0.65, 0.8])!
            c.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: size.height * 0.75), options: [])
            // 星
            var seed: UInt64 = 12345
            func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 10000) / 10000 }
            c.setFillColor(color(1, 1, 1, 0.8))
            for _ in 0..<70 {
                let r = 1 + rnd() * 2.2
                c.fillEllipse(in: CGRect(x: rnd() * size.width, y: rnd() * size.height * 0.4, width: r, height: r))
            }
            // 太陽
            let sunC = CGPoint(x: size.width * 0.68, y: size.height * 0.60)
            let glow = CGGradient(colorsSpace: cs, colors: [color(1, 0.95, 0.7, 1), color(1, 0.7, 0.4, 0.5), color(1, 0.6, 0.3, 0)] as CFArray, locations: [0, 0.3, 1])!
            c.drawRadialGradient(glow, startCenter: sunC, startRadius: 0, endCenter: sunC, endRadius: 420, options: [])
            c.setFillColor(color(1, 0.97, 0.8))
            c.fillEllipse(in: CGRect(x: sunC.x - 70, y: sunC.y - 70, width: 140, height: 140))
            // 丘
            func hill(_ base: CGFloat, _ amp: CGFloat, _ freq: CGFloat, _ phase: CGFloat, _ col: CGColor) {
                c.setFillColor(col)
                c.move(to: CGPoint(x: 0, y: size.height))
                var x: CGFloat = 0
                while x <= size.width + 8 {
                    c.addLine(to: CGPoint(x: x, y: size.height * base + sin(x * freq + phase) * amp + sin(x * freq * 2.3) * amp * 0.3))
                    x += 8
                }
                c.addLine(to: CGPoint(x: size.width, y: size.height))
                c.closePath()
                c.fillPath()
            }
            hill(0.70, 40, 0.006, 1.0, color(0.35, 0.25, 0.45))
            hill(0.76, 50, 0.005, 3.0, color(0.18, 0.28, 0.32))
            // 街のシルエットと窓の明かり
            var x: CGFloat = -10
            while x < size.width {
                let w = 50 + rnd() * 70, h = 120 + rnd() * 260
                let top = size.height * 0.84 - h
                c.setFillColor(color(0.07, 0.08, 0.14))
                c.fill(CGRect(x: x, y: top, width: w, height: size.height - top))
                var wy = top + 16
                while wy < size.height * 0.84 - 8 {
                    var wx = x + 8
                    while wx < x + w - 14 {
                        if rnd() < 0.45 {
                            c.setFillColor(color(1, 0.85, 0.45, 0.9))
                            c.fill(CGRect(x: wx, y: wy, width: 8, height: 11))
                        }
                        wx += 18
                    }
                    wy += 26
                }
                x += w + 6
            }
            // 手前の地面と木
            c.setFillColor(color(0.05, 0.10, 0.08))
            c.fill(CGRect(x: 0, y: size.height * 0.84, width: size.width, height: size.height * 0.16))
            for i in 0..<5 {
                let tx = CGFloat(i) * size.width / 4.5 + 20
                c.setFillColor(color(0.04, 0.12, 0.08))
                c.fillEllipse(in: CGRect(x: tx - 55, y: size.height * 0.84 - 90, width: 110, height: 130))
            }
            // ぼけた街灯
            for _ in 0..<14 {
                let r = 8 + rnd() * 16
                c.setFillColor(color(1, 0.9, 0.6, 0.35))
                c.fillEllipse(in: CGRect(x: rnd() * size.width, y: size.height * (0.86 + rnd() * 0.12), width: r, height: r))
            }
        }
    }

    /// 長辺を maxDimension に縮小
    static func downscaled(_ image: UIImage, maxDimension: CGFloat = 1800) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let k = maxDimension / longest
        let size = CGSize(width: image.size.width * k, height: image.size.height * k)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// ぼかした画像（曇りガラスの下地）
    static func blurred(_ image: UIImage) -> CGImage? {
        guard let cg = image.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        let radius = max(12, Double(max(cg.width, cg.height)) / 70)
        guard let f = CIFilter(name: "CIGaussianBlur") else { return nil }
        f.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        f.setValue(radius, forKey: kCIInputRadiusKey)
        guard let out = f.outputImage?.cropped(to: input.extent) else { return nil }
        return CIContext().createCGImage(out, from: input.extent)
    }
}
