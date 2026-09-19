import SwiftUI
import CoreMotion

/// 設定画面（簡易版）。docs/02-spec.md 2章 #7 / docs/03-design.md 画面6に対応。
/// v1では権限状態の確認とプライバシー表示に絞る。課金の実装はv2（Apple Developer Program登録後）。
struct SettingsView: View {
    @State private var motionStatusText: String = "未確認"
    @AppStorage(ProAccess.storageKey) private var proEnabled = ProAccess.defaultEnabled
    @AppStorage(RingTheme.storageKey) private var themeRaw = RingTheme.standard.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("権限") {
                    LabeledContent("モーション & フィットネス", value: motionStatusText)
                }
                Section("プロモード") {
                    Toggle("プロモード", isOn: $proEnabled)
                    Text("このビルド（家族用）では、既定でオンです。オフにすると、下の機能がロック表示になります。課金の仕組みはまだありません（将来、購入で切り替えられるように作ってあります）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(ProFeature.allCases) { feature in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(feature.displayName, systemImage: proEnabled ? "checkmark.circle" : "lock")
                                .font(.subheadline)
                            Text(feature.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker("配色テーマ", selection: $themeRaw) {
                        ForEach(RingTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme.rawValue)
                        }
                    }
                    .disabled(!proEnabled)
                }
                Section("「1日の輪」について") {
                    Text("「乗り物」は電車・バス・車です。iPhoneの動き検出（CoreMotion）は電車と車を区別できないため、まとめて表示します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("「睡眠」は、夜間（20時〜翌4時ごろに始まり、正午までに終わる）に3時間以上動かなかった時間から推定しています。夜更かしで動かずにスマホを見ていた時間も、睡眠として表示されることがあります。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("サブスクリプション") {
                    Text("PROプラン（追加機能）は準備中です。実際の購入はまだできません。")
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
                    Text("活動データは「1日の輪」を作るためだけに端末内で使われ、外部へ送信されることはありません。")
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
        case .notDetermined: motionStatusText = "未確認（「今日」タブを開くと確認されます）"
        @unknown default: motionStatusText = "不明"
        }
    }
}
