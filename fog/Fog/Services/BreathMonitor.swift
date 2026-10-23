import Foundation
import AVFoundation

/// マイクの音量と低音域の割合から息を検知する。音は保存・送信せず、その場で大きさを計算するだけ。
final class BreathMonitor {
    private let engine = AVAudioEngine()
    private(set) var detector = BreathDetector()
    private(set) var level: Double = 0
    private(set) var lowRatio: Double = 0
    private(set) var permissionDenied = false
    private(set) var running = false
    private var lowState: Float = 0

    var intensity: Double { detector.intensity }
    var isBreathing: Bool { detector.isBreathing }

    func setSensitivity(_ s: Double) { detector.sensitivity = s }

    func start() {
        guard !running else { return }
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted { self.startEngine() } else { self.permissionDenied = true }
            }
        }
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        detector = BreathDetector(sensitivity: detector.sensitivity)
    }

    private func startEngine() {
        guard !running else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
            // 録音中でも触覚(キュッキュッ)を鳴らすために必要
            try s.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try s.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { return }
            let sr = Float(format.sampleRate)
            // 約500Hz以下を「低音域」とみなす1次ローパス
            let alpha = 1 - exp(-2 * Float.pi * 500 / sr)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
                guard let self, let ch = buf.floatChannelData?[0] else { return }
                let n = Int(buf.frameLength)
                if n == 0 { return }
                var total: Float = 0, low: Float = 0
                var st = self.lowState
                for i in 0..<n {
                    let x = ch[i]
                    st += alpha * (x - st)
                    total += x * x
                    low += st * st
                }
                self.lowState = st
                let rms = Double((total / Float(n)).squareRoot())
                let ratio = total > 1e-9 ? Double(min(1, low / total)) : 0
                let dt = Double(n) / Double(sr)
                DispatchQueue.main.async { self.feed(rms: rms, lowRatio: ratio, dt: dt) }
            }
            try engine.start()
            running = true
        } catch {
            running = false
        }
    }

    private func feed(rms: Double, lowRatio: Double, dt: Double) {
        guard running else { return }
        level = rms
        self.lowRatio = lowRatio
        detector.feed(rms: rms, lowRatio: lowRatio, dt: dt)
    }
}
