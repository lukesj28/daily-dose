import SwiftUI
import UIKit

enum DisplayMode: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("displayMode") private var displayMode: Int = 0
    @AppStorage("highlightColorR") private var highlightR: Double = 1.0
    @AppStorage("highlightColorG") private var highlightG: Double = 0.93
    @AppStorage("highlightColorB") private var highlightB: Double = 0.27

    private var highlightColor: Binding<Color> {
        Binding(
            get: { Color(red: highlightR, green: highlightG, blue: highlightB) },
            set: { newColor in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                if UIColor(newColor).getRed(&r, green: &g, blue: &b, alpha: nil) {
                    highlightR = Double(r)
                    highlightG = Double(g)
                    highlightB = Double(b)
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Display Mode", selection: $displayMode) {
                        ForEach(DisplayMode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                }

                Section("Annotations") {
                    ColorPicker("Highlight Color", selection: highlightColor, supportsOpacity: false)
                }

                Section("About") {
                    NavigationLink("About Daily Dose") {
                        AboutView()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
