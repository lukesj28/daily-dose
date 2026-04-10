import SwiftUI
import SwiftData

@main
struct DailyDoseApp: App {
    @State private var cacheManager = CacheManager()
    @State private var saveNotifier = SaveNotifier()
    @AppStorage("hasAcceptedDisclaimer") private var hasAccepted = false

    var body: some Scene {
        WindowGroup {
            if hasAccepted {
                ContentView()
                    .environment(cacheManager)
                    .environment(saveNotifier)
            } else {
                DisclaimerView()
            }
        }
        .modelContainer(for: [Article.self, Annotation.self])
    }
}
