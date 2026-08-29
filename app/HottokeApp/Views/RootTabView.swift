import SwiftUI

/// docs/03-design.md の4タブ構成（今日/手動/アーカイブ/設定）。
/// アーカイブタブはdocs/02-spec.md 2章#6として当初v2見送りだったが、オーナーの明示的な
/// 依頼によりMVPに組み込んだ（docs/04-build-log.md参照）。
struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("今日", systemImage: "sparkles") }
            ManualModeView()
                .tabItem { Label("手動", systemImage: "hand.draw") }
            CalendarArchiveView()
                .tabItem { Label("アーカイブ", systemImage: "calendar") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
