import SwiftUI
import SwiftData

@main
struct DailyDoseApp: App {
    @State private var cacheManager = CacheManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(cacheManager)
        }
        .modelContainer(for: [Article.self, Annotation.self])
    }
}
