import SwiftUI
import SwiftData

@main
struct DailyDoseApp: App {
    @State private var cacheManager = CacheManager()
    @State private var saveNotifier = SaveNotifier()
    @AppStorage("hasAcceptedDisclaimer") private var hasAccepted = false
    @AppStorage("displayMode") private var displayMode: Int = 0

    var body: some Scene {
        WindowGroup {
            Group {
                if hasAccepted {
                    ContentView()
                        .environment(cacheManager)
                        .environment(saveNotifier)
                } else {
                    DisclaimerView()
                }
            }
            .preferredColorScheme(DisplayMode(rawValue: displayMode)?.colorScheme)
        }
        .modelContainer(for: [Article.self, Annotation.self])
    }
}
