import SwiftUI

/// 感触調整用の隠し設定（3本指タップで開く）
struct SettingsView: View {
    @ObservedObject var engine: FogEngine
    @ObservedObject private var s: FogSettings

    init(engine: FogEngine) {
        self.engine = engine
        _s = ObservedObject(wrappedValue: engine.settings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("息の検知（確認用メーター）") {
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        let b = engine.breath
                        VStack(alignment: .leading, spacing: 6) {
                            if b.permissionDenied {
                                Text("マイクが許可されていません。設定アプリで許可してください。").foregroundStyle(.red)
                            } else if !b.running {
                                Text("マイク停止中（シミュレーターでは使えません）").foregroundStyle(.secondary)
                            }
                            Text("音量 \(String(format: "%.3f", b.level))  低音の割合 \(String(format: "%.2f", b.lowRatio))")
                                .font(.footnote.monospacedDigit())
                            ProgressView(value: min(1, b.level * 6))
                            Text(b.isBreathing ? "息を検知中" : "検知なし")
                                .foregroundStyle(b.isBreathing ? .green : .secondary)
                        }
                    }
                    slider("息の感度", $s.breathSensitivity, 0...1, "%.2f")
                    slider("息で曇る速さ", $s.breathGain, 0.3...4, "%.1f")
                }
                Section("曇りと水滴") {
                    slider("再び曇る速さ", $s.refogRate, 0.01...0.5, "%.2f")
                    slider("水滴の出やすさ", $s.dropFrequency, 0...1, "%.2f")
                    slider("拭く太さ", $s.wipeRadius, 14...60, "%.0f")
                    Toggle("触覚（キュッキュッ）", isOn: $s.haptics)
                }
                Section {
                    Button("全体をいま曇らせる") { engine.requestFullFog() }
                    Button("初期値に戻す", role: .destructive) { s.reset() }
                }
            }
            .navigationTitle("くもり窓 調整")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { engine.showSettings = false } } }
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ fmt: String) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(String(format: fmt, value.wrappedValue)).foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: range)
        }
    }
}
