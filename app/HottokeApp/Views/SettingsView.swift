import SwiftUI
import CoreMotion

/// 設定画面（簡易版）。docs/02-spec.md 2章 #7 / docs/03-design.md 画面6に対応。
/// v1では権限状態の確認とプライバシー表示に絞る。課金の実装はv2（Apple Developer Program登録後）。
struct SettingsView: View {
    @State private var motionStatusText: String = "未確認"

    var body: some View {
        NavigationStack {
            Form {
                Section("権限") {
                    LabeledContent("モーション & フィットネス", value: motionStatusText)
                }
                Section("サブスクリプション") {
                    Text("PROプラン（アーカイブ・追加パレット・4K書き出し）は準備中です。実際の購入はまだできません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent("現在のプラン", value: "無料プラン")
                }
                Section("サポート") {
                    Text("プライバシーポリシー")
                    Text("利用規約")
                    LabeledContent("バージョン", value: appVersion)
                }
                Section {
                    Text("活動データは模様の生成のためだけに端末内で使われ、外部へ送信されることはありません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .onAppear { refreshMotionStatus() }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func refreshMotionStatus() {
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized: motionStatusText = "許可済み"
        case .denied: motionStatusText = "拒否"
        case .restricted: motionStatusText = "制限あり"
        case .notDetermined: motionStatusText = "未確認（今日の模様を生成すると確認されます）"
        @unknown default: motionStatusText = "不明"
        }
    }
}
