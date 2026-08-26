import CoreMotion
import CoreGraphics
import Foundation

/// 手動クリエイティブモードの「振る/傾ける」操作を扱う。
/// docs/03b-visual-prototype-learnings.md「操作・モーション」節の仕様に対応:
///  - 傾き(tilt) → 模様の回転にゆっくり反映
///  - 振った方向 → 模様全体が一時的に「流れ」、バネで元の配置に戻る（変位量は控えめにする）
///  - 強い振り → 模様の配色・配置そのものを再生成（pulseTriggerの増加で通知）
@MainActor
final class MotionInputService: ObservableObject {
    @Published private(set) var tiltRotation: Double = 0
    @Published private(set) var flowOffset: CGVector = .zero
    @Published private(set) var pulseTrigger: Int = 0

    private let motionManager = CMMotionManager()
    private var velocity: CGVector = .zero
    private var lastShakeTime = Date.distantPast
    private var updateTimer: Timer?

    // 変位量は控えめにする: 大きすぎると模様が描画範囲外まで押し出されて消えてしまうため
    // （docs/03b-visual-prototype-learnings.md「操作・モーション」節）。
    private let maxFlowDisplacement: CGFloat = 18
    private let springStiffness: CGFloat = 40
    private let springDamping: CGFloat = 9
    private let shakeThreshold: Double = 2.2
    private let shakeCooldown: TimeInterval = 0.4

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.handle(motion: motion)
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.stepSpring() }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func handle(motion: CMDeviceMotion) {
        // 傾き: ゆっくり回転に反映（急に動くとチープに見えるため指数移動平均で滑らかにする）
        let targetTiltRotation = motion.attitude.roll
        tiltRotation += (targetTiltRotation - tiltRotation) * 0.02

        // 振り: 加速度に応じてバネの初速を与える（模様全体が一時的に「流れる」演出）
        let acc = motion.userAcceleration
        let magnitude = sqrt(acc.x * acc.x + acc.y * acc.y)
        if magnitude > 0.35 {
            velocity.dx += CGFloat(acc.x) * 6
            velocity.dy += CGFloat(-acc.y) * 6
        }

        // 強い振り: 配色・配置そのものを再生成するトリガー（クールダウンつき）
        if magnitude > shakeThreshold, Date().timeIntervalSince(lastShakeTime) > shakeCooldown {
            lastShakeTime = Date()
            pulseTrigger += 1
        }
    }

    /// バネで元の位置に戻す。控えめな最大変位でクランプすることで、
    /// 模様が描画範囲外に出て消えてしまうことを防ぐ。
    private func stepSpring() {
        let dt: CGFloat = 1.0 / 60.0
        let displacement = flowOffset
        let accelX = -springStiffness * displacement.dx - springDamping * velocity.dx
        let accelY = -springStiffness * displacement.dy - springDamping * velocity.dy
        velocity.dx += accelX * dt
        velocity.dy += accelY * dt

        var next = CGVector(dx: displacement.dx + velocity.dx * dt, dy: displacement.dy + velocity.dy * dt)
        let distance = sqrt(next.dx * next.dx + next.dy * next.dy)
        if distance > maxFlowDisplacement {
            let scale = maxFlowDisplacement / distance
            next = CGVector(dx: next.dx * scale, dy: next.dy * scale)
        }
        flowOffset = next
    }
}
