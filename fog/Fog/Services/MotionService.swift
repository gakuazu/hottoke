import Foundation
import CoreMotion

/// 端末の傾き（重力方向）。シミュレーターなど取得できない環境では真下方向を返す。
final class MotionService {
    private let manager = CMMotionManager()
    private(set) var gravity: (dx: Float, dy: Float, strength: Float) = (0, 1, 1)
    private var smoothed: (x: Double, y: Double) = (0, -1)

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            self.smoothed.x += (g.x - self.smoothed.x) * 0.25
            self.smoothed.y += (g.y - self.smoothed.y) * 0.25
            self.gravity = FogMath.screenGravity(x: self.smoothed.x, y: self.smoothed.y)
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}
