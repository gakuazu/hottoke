import SwiftUI
import CoreMotion
import CoreLocation
import Photos

/// 設定画面（簡易版）。docs/02-spec.md 2章 #7 / docs/03-design.md 画面6に対応。
/// v1では権限状態の確認とプライバシー表示に絞る。課金の実装はv2（Apple Developer Program登録後）。
struct SettingsView: View {
    @State private var motionStatusText: String = "未確認"
    @State private var locationStatusText: String = "未確認"
    @State private var photoStatusText: String = "未確認"
    @AppStorage(ProAccess.storageKey) private var proEnabled = ProAccess.defaultEnabled
    @AppStorage(RingArtStyle.storageKey) private var styleRaw = RingArtStyle.defaultStyle.rawValue
    @AppStorage(LocationDiarySettings.storageKey) private var locationDiaryEnabled = LocationDiarySettings.defaultEnabled
    @AppStorage(DiaryPhotoLinkSettings.storageKey) private var photoLinkEnabled = DiaryPhotoLinkSettings.defaultEnabled

    var body: some View {
        NavigationStack {
            Form {
                Section("権限") {
                    LabeledContent("モーション & フィットネス", value: motionStatusText)
                    LabeledContent("位置情報（GPS自動日記）", value: locationStatusText)
                    LabeledContent("写真（写真リンク）", value: photoStatusText)
                }
                Section("ひとこと日記を助ける機能") {
                    Toggle("GPS自動日記", isOn: $locationDiaryEnabled)
                    Text("その日いた場所から、ひとこと日記の下書きを自動で作ります。常に細かく追跡するのではなく、大きく場所が変わったときだけ記録する省電力な方法を使います。よく居る場所（自宅と思われる場所）は地名を出さず「自宅で過ごした」と表示します。位置情報は端末の外へは送信しません。オフにすると、これまでに貯めた位置情報も削除します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("写真リンク", isOn: $photoLinkEnabled)
                    Text("その日撮った写真のサムネイルを、ひとこと日記のそばに小さく表示します。写真はその場で読み込むだけで、アプリの中にコピー・保存はしません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                    Picker("表現スタイル", selection: $styleRaw) {
                        ForEach(RingArtStyle.allCases) { style in
                            Text(style.displayName).tag(style.rawValue)
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
            .onAppear {
                refreshMotionStatus()
                refreshLocationStatus()
                refreshPhotoStatus()
            }
            .onChange(of: locationDiaryEnabled) { _, newValue in
                LocationDiaryService.shared.applySetting(enabled: newValue)
                refreshLocationStatus()
            }
            .onChange(of: photoLinkEnabled) { _, _ in refreshPhotoStatus() }
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

    private func refreshLocationStatus() {
        guard locationDiaryEnabled else {
            locationStatusText = "オフ"
            return
        }
        switch LocationDiaryService.shared.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: locationStatusText = "許可済み"
        case .denied: locationStatusText = "拒否（設定アプリから変更できます）"
        case .restricted: locationStatusText = "制限あり"
        case .notDetermined: locationStatusText = "未確認"
        @unknown default: locationStatusText = "不明"
        }
    }

    private func refreshPhotoStatus() {
        guard photoLinkEnabled else {
            photoStatusText = "オフ"
            return
        }
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: photoStatusText = "許可済み"
        case .limited: photoStatusText = "一部の写真のみ許可"
        case .denied: photoStatusText = "拒否（設定アプリから変更できます）"
        case .restricted: photoStatusText = "制限あり"
        case .notDetermined: photoStatusText = "未確認（「今日」タブを開くと確認されます）"
        @unknown default: photoStatusText = "不明"
        }
    }
}
