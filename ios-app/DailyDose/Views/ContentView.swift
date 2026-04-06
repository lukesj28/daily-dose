import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Daily", systemImage: "book") {
                DailyView()
            }

            Tab("Library", systemImage: "books.vertical.fill") {
                LibraryView()
            }
        }
        .tint(.primary)
    }
}
