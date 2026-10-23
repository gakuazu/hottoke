import SwiftUI
import UIKit
import Combine

struct FogViewRepresentable: UIViewRepresentable {
    let engine: FogEngine
    func makeUIView(context: Context) -> FogUIView { FogUIView(engine: engine) }
    func updateUIView(_ uiView: FogUIView, context: Context) {}
}

/// 描画の本体。CALayerで「くっきり背景 → ぼかし＋白の曇り（マスクで拭う） → 水滴」を重ね、
/// 毎フレーム更新するのは小さなマスク画像と水滴の形だけなので軽い。
final class FogUIView: UIView {
    private let engine: FogEngine
    private let bgLayer = CALayer()
    private let fogLayer = CALayer()
    private let tintLayer = CALayer()
    private let maskLayer = CALayer()
    private let dropLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()

    private var field: FogField?
    private var cellSize: CGFloat = 4
    private var lastSize: CGSize = .zero
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var holdFog = false
    private var cancellables = Set<AnyCancellable>()

    private var lastTouch: [ObjectIdentifier: CGPoint] = [:]
    private var hapticDistance: CGFloat = 0
    private var lastHaptic: CFTimeInterval = 0
    private let haptic = UIImpactFeedbackGenerator(style: .soft)

    init(engine: FogEngine) {
        self.engine = engine
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .black
        clipsToBounds = true

        bgLayer.contentsGravity = .resizeAspectFill
        bgLayer.masksToBounds = true
        fogLayer.contentsGravity = .resizeAspectFill
        fogLayer.masksToBounds = true
        tintLayer.backgroundColor = UIColor(white: 1, alpha: 0.42).cgColor
        maskLayer.magnificationFilter = .linear
        dropLayer.fillColor = UIColor(white: 1, alpha: 0.16).cgColor
        dropLayer.strokeColor = UIColor(white: 1, alpha: 0.55).cgColor
        dropLayer.lineWidth = 1
        dropLayer.shadowColor = UIColor.black.cgColor
        dropLayer.shadowOpacity = 0.4
        dropLayer.shadowRadius = 1.5
        dropLayer.shadowOffset = CGSize(width: 0, height: 1.5)
        highlightLayer.fillColor = UIColor(white: 1, alpha: 0.85).cgColor
        highlightLayer.strokeColor = nil

        layer.addSublayer(bgLayer)
        layer.addSublayer(fogLayer)
        fogLayer.addSublayer(tintLayer)
        fogLayer.mask = maskLayer
        layer.addSublayer(dropLayer)
        layer.addSublayer(highlightLayer)

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(onHold(_:)))
        hold.numberOfTouchesRequired = 2
        hold.minimumPressDuration = 0.35
        hold.allowableMovement = 40
        hold.cancelsTouchesInView = false
        addGestureRecognizer(hold)

        let tap3 = UITapGestureRecognizer(target: self, action: #selector(onTap3))
        tap3.numberOfTouchesRequired = 3
        tap3.cancelsTouchesInView = false
        addGestureRecognizer(tap3)

        engine.$images.receive(on: DispatchQueue.main).sink { [weak self] imgs in
            guard let imgs else { return }
            self?.bgLayer.contents = imgs.sharp
            self?.fogLayer.contents = imgs.blurred
        }.store(in: &cancellables)

        engine.fogRequests.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.field?.addFog(1)
        }.store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        if window != nil {
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
            l.add(to: .main, forMode: .common)
            link = l
            lastTimestamp = 0
            haptic.prepare()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [bgLayer, fogLayer, tintLayer, maskLayer] { l.frame = bounds }
        dropLayer.frame = bounds
        highlightLayer.frame = bounds
        CATransaction.commit()
        if bounds.size != lastSize, bounds.width > 0 {
            lastSize = bounds.size
            let cols = 150
            cellSize = bounds.width / CGFloat(cols)
            let rows = max(1, Int((bounds.height / cellSize).rounded()))
            field = FogField(cols: cols, rows: rows)
        }
    }

    // MARK: - ジェスチャー

    @objc private func onHold(_ g: UILongPressGestureRecognizer) {
        holdFog = (g.state == .began || g.state == .changed)
    }

    @objc private func onTap3() { engine.showSettings = true }

    // MARK: - 拭く

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            lastTouch[ObjectIdentifier(t)] = p
            wipe(from: p, to: p)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            let points = (event?.coalescedTouches(for: t) ?? [t]).map { $0.location(in: self) }
            var prev = lastTouch[id] ?? t.location(in: self)
            for p in points {
                wipe(from: prev, to: p)
                prev = p
            }
            lastTouch[id] = prev
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { lastTouch[ObjectIdentifier(t)] = nil }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { lastTouch[ObjectIdentifier(t)] = nil }
    }

    private func wipe(from a: CGPoint, to b: CGPoint) {
        guard let field else { return }
        let radius = Float(engine.settings.wipeRadius / cellSize)
        let k = Float(1 / cellSize)
        let (ax, ay, bx, by) = (Float(a.x) * k, Float(a.y) * k, Float(b.x) * k, Float(b.y) * k)
        field.wipe(fromX: ax, fromY: ay, toX: bx, toY: by, radius: radius)
        let dist = hypot(bx - ax, by - ay)
        field.maybeSpawnDrop(atX: bx, y: by, distance: dist, wipeRadius: radius,
                             frequency: Float(engine.settings.dropFrequency)) { Float.random(in: 0..<1) }

        // 触覚：一定距離動くたびに細かく
        let d = hypot(b.x - a.x, b.y - a.y)
        hapticDistance += d
        let now = CACurrentMediaTime()
        if engine.settings.haptics, hapticDistance > 10, now - lastHaptic > 0.03 {
            haptic.impactOccurred(intensity: min(1, 0.35 + d / 40))
            haptic.prepare()
            hapticDistance = 0
            lastHaptic = now
        }
    }

    // MARK: - 毎フレーム

    @objc private func tick(_ link: CADisplayLink) {
        guard let field else { return }
        let dt = lastTimestamp == 0 ? 1.0 / 60 : min(link.timestamp - lastTimestamp, 1.0 / 20)
        lastTimestamp = link.timestamp
        let fdt = Float(dt)
        let s = engine.settings

        engine.breath.setSensitivity(s.breathSensitivity)
        let breath = Float(engine.breath.intensity)
        let add = max(breath, holdFog ? 1 : 0)
        if add > 0 { field.addFog(Float(s.breathGain) * add * fdt) }

        field.refog(dt: fdt, rate: Float(s.refogRate))
        let g = engine.motion.gravity
        field.stepDrops(dt: fdt, gx: g.dx, gy: g.dy, strength: g.strength) { Float.random(in: 0..<1) }

        let hadDrops = !(dropLayer.path?.isEmpty ?? true)
        guard field.dirty || hadDrops else { return }
        field.dirty = false

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.contents = makeMask(field)
        updateDrops(field)
        CATransaction.commit()
    }

    private func makeMask(_ f: FogField) -> CGImage? {
        let n = f.cols * f.rows
        var bytes = [UInt8](repeating: 0, count: n * 4)
        for i in 0..<n {
            let a = UInt8(max(0, min(1, f.fog[i])) * 255)
            bytes[i * 4] = a
            bytes[i * 4 + 1] = a
            bytes[i * 4 + 2] = a
            bytes[i * 4 + 3] = a
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: f.cols, height: f.rows, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: f.cols * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private func updateDrops(_ f: FogField) {
        let path = CGMutablePath()
        let hl = CGMutablePath()
        for d in f.drops {
            let r = CGFloat(d.radius) * cellSize
            let c = CGPoint(x: CGFloat(d.x) * cellSize, y: CGFloat(d.y) * cellSize)
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r * 1.15, width: r * 2, height: r * 2.3))
            let h = max(1, r * 0.3)
            hl.addEllipse(in: CGRect(x: c.x - r * 0.45, y: c.y - r * 0.6, width: h, height: h))
        }
        dropLayer.path = path
        highlightLayer.path = hl
    }
}
