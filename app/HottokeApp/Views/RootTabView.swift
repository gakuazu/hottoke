import SwiftUI

/// docs/03-design.md の3タブ構成（今日/手動/設定）。
struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("今日", systemImage: "sparkles") }
            ManualModeView()
                .tabItem { Label("手動", systemImage: "hand.draw") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
