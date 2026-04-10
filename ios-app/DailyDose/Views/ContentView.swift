import SwiftUI

struct ContentView: View {
    @Environment(SaveNotifier.self) private var saveNotifier

    var body: some View {
        TabView {
            Tab("Daily", systemImage: "book") {
                DailyView()
            }

            Tab {
                LibraryView()
            } label: {
                Label("Library", systemImage: "books.vertical.fill")
                    .symbolEffect(.bounce, value: saveNotifier.didSave)
            }
        }
        .tint(.primary)
    }
}
