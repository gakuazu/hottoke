import SwiftUI

/// タブ構成（今日 / アーカイブ / 設定）。
/// 2026-09-19の方針変更で、「今日」は点描リング「1日の輪」に置き換え、数学模様（万華鏡）の手動モードと
/// 動画の「今日の模様」（TodayView）はタブから外した。TodayView / ManualModeView と
/// 万華鏡・動画書き出しのコードは、復活しやすいよう削除せず残してある。
struct RootTabView: View {
    var body: some View {
        TabView {
            DailyRingView()
                .tabItem { Label("今日", systemImage: "circle.dotted") }
            CalendarArchiveView()
                .tabItem { Label("アーカイブ", systemImage: "calendar") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
        // 起動時、設定に合わせて「GPS自動日記」の位置情報監視を開始する（オフなら何もしない）。
        .task {
            LocationDiaryService.shared.applySetting(enabled: LocationDiarySettings.isEnabled())
        }
    }
}
