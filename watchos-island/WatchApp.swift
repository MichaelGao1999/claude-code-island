import SwiftUI

@main
struct ClaudeCodeIslandWatchApp: App {
    @StateObject private var session = SessionManager.shared

    var body: some Scene {
        WindowGroup {
            StatusView()
                .onAppear {
                    // WCSession 在 SessionManager.init 中自动激活
                    print("[WatchApp] Claude Code Island Watch 已启动")
                }
        }
    }
}