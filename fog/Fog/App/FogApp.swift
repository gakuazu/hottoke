import SwiftUI

@main
struct FogApp: App {
    @StateObject private var engine = FogEngine()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView(engine: engine)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .onChange(of: phase) { _, p in
                    if p == .active { engine.start() } else { engine.stop() }
                }
                .onAppear { engine.start() }
        }
    }
}
