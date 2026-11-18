import SwiftUI
import UIKit
import Testing
@testable import DailyDose

private struct RGBA: Equatable {
    var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat

    init(_ color: UIColor, in traits: UITraitCollection) {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        (self.r, self.g, self.b, self.a) = (r, g, b, a)
    }

    func isClose(to other: RGBA, tolerance: CGFloat = 0.01) -> Bool {
        abs(r - other.r) < tolerance && abs(g - other.g) < tolerance
            && abs(b - other.b) < tolerance && abs(a - other.a) < tolerance
    }
}

@MainActor
private struct Rendered {
    let window: UIWindow
    let textView: UITextView
    var coordinator: TextBlockView.Coordinator { textView.delegate as! TextBlockView.Coordinator }
    var attributed: NSAttributedString { textView.attributedText }

    func rgba(_ key: NSAttributedString.Key, at index: Int) -> RGBA? {
        guard let color = attributed.attribute(key, at: index, effectiveRange: nil) as? UIColor else { return nil }
        return RGBA(color, in: textView.traitCollection)
    }

    func font(at index: Int) -> UIFont { attributed.attribute(.font, at: index, effectiveRange: nil) as! UIFont }

    /// Center of the glyphs in `range`, in textView coordinates.
    func center(of range: NSRange) -> CGPoint {
        let start = textView.position(from: textView.beginningOfDocument, offset: range.location)!
        let end = textView.position(from: start, offset: range.length)!
        let rect = textView.firstRect(for: textView.textRange(from: start, to: end)!)
        return CGPoint(x: rect.midX, y: rect.midY)
    }
}

@MainActor
private func render(
    _ text: String,
    annotations: [Annotation] = [],
    searchRanges: [NSRange] = [],
    currentSearchRange: NSRange? = nil,
    color: (Double, Double, Double)? = nil,
    markdown: Bool = true,
    onAnnotate: @escaping (NSRange) -> Void = { _ in },
    onEdit: @escaping (Annotation) -> Void = { _ in },
    onDelete: @escaping (Annotation) -> Void = { _ in }
) async throws -> Rendered {
    var view = TextBlockView(
        text: text,
        annotations: annotations,
        searchRanges: searchRanges,
        currentSearchRange: currentSearchRange,
        enableMarkdown: markdown,
        onAnnotate: onAnnotate,
        onEditAnnotation: onEdit,
        onDeleteAnnotation: onDelete
    )
    if let color {
        view.highlightColorR = color.0
        view.highlightColorG = color.1
        view.highlightColorB = color.2
    }
    let (window, controller) = host(view)
    var found: UITextView?
    try await waitUntil {
        found = allSubviews(UITextView.self, in: controller.view).first
        return (found?.attributedText.length ?? 0) > 0
    }
    return Rendered(window: window, textView: try #require(found))
}

private let yellow = RGBA(red: 1.0, green: 0.93, blue: 0.27)

private extension RGBA {
    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        (r, g, b, a) = (red, green, blue, alpha)
    }
}

private func annotation(_ location: Int, _ length: Int, note: String = "note") -> Annotation {
    Annotation(blockIndex: 1, startIndex: location, length: length, noteText: note)
}

extension AppTests {
    @Suite struct TextBlockViewTests {

        @Test func boldMarkdownRendersBoldWithoutMarkers() async throws {
            let r = try await render("a **b** c")
            defer { r.window.isHidden = true }
            #expect(r.attributed.string == "a b c")
            #expect(r.font(at: 2).fontDescriptor.symbolicTraits.contains(.traitBold))
            #expect(!r.font(at: 0).fontDescriptor.symbolicTraits.contains(.traitBold))
        }

        @Test func italicMarkdownRendersItalic() async throws {
            let r = try await render("x *i*")
            defer { r.window.isHidden = true }
            #expect(r.attributed.string == "x i")
            #expect(r.font(at: 2).fontDescriptor.symbolicTraits.contains(.traitItalic))
            #expect(!r.font(at: 0).fontDescriptor.symbolicTraits.contains(.traitItalic))
        }

        @Test func superscriptIsRaisedAndSmaller() async throws {
            let r = try await render("10^(5)")
            defer { r.window.isHidden = true }
            #expect(r.attributed.string == "105")
            #expect((r.attributed.attribute(.baselineOffset, at: 2, effectiveRange: nil) as! CGFloat) > 0)
            #expect(r.font(at: 2).pointSize < r.font(at: 0).pointSize)
        }

        @Test func subscriptIsLowered() async throws {
            let r = try await render("CO_(2)")
            defer { r.window.isHidden = true }
            #expect(r.attributed.string == "CO2")
            #expect((r.attributed.attribute(.baselineOffset, at: 2, effectiveRange: nil) as! CGFloat) < 0)
        }

        @Test func mixedItalicAndBoldRenderWithoutLiteralAsterisks() async throws {
            let r = try await render("*a* and **b**")
            defer { r.window.isHidden = true }
            #expect(r.attributed.string == "a and b")
        }

        @Test func nestedBoldItalicRendersBoth() async throws {
            let r = try await render("***x***")
            defer { r.window.isHidden = true }
            #expect(r.attributed.string == "x")
            let traits = r.font(at: 0).fontDescriptor.symbolicTraits
            #expect(traits.contains(.traitBold) && traits.contains(.traitItalic))
        }

        @Test func markdownDisabledKeepsLiteralText() async throws {
            let r = try await render("**x**", markdown: false)
            defer { r.window.isHidden = true }
            #expect(r.attributed.string == "**x**")
        }


        @Test func textAnnotationIsHighlightedWithDefaultColor() async throws {
            let r = try await render("hello world", annotations: [annotation(0, 3)])
            defer { r.window.isHidden = true }
            #expect(try #require(r.rgba(.backgroundColor, at: 0)).isClose(to: yellow))
            #expect(try #require(r.rgba(.backgroundColor, at: 2)).isClose(to: yellow))
            #expect(r.rgba(.backgroundColor, at: 3) == nil)
            #expect(try #require(r.rgba(.foregroundColor, at: 0)).isClose(to: RGBA(red: 0, green: 0, blue: 0)))
        }

        @Test func customHighlightColorIsApplied() async throws {
            let r = try await render("hello world", annotations: [annotation(0, 3)], color: (0.2, 0.4, 0.6))
            defer { r.window.isHidden = true }
            #expect(try #require(r.rgba(.backgroundColor, at: 0)).isClose(to: RGBA(red: 0.2, green: 0.4, blue: 0.6)))
        }

        @Test func outOfBoundsAnnotationIsIgnored() async throws {
            let r = try await render("hello world", annotations: [annotation(100, 3)])
            defer { r.window.isHidden = true }
            #expect(r.attributed.string == "hello world")
            #expect(r.rgba(.backgroundColor, at: 0) == nil)
        }

        @Test func cellAndEquationAnnotationsAreNotHighlightedInText() async throws {
            let cell = makeAnnotation(.cell(index: 1, row: 1, col: 0))
            let equation = makeAnnotation(.equation(index: 1))
            let r = try await render("hello world", annotations: [cell, equation])
            defer { r.window.isHidden = true }
            #expect(r.rgba(.backgroundColor, at: 0) == nil)
        }


        @Test func searchRangesUseYellowAndCurrentUsesOrange() async throws {
            let r = try await render(
                "hello world",
                searchRanges: [NSRange(location: 0, length: 5), NSRange(location: 6, length: 5)],
                currentSearchRange: NSRange(location: 6, length: 5)
            )
            defer { r.window.isHidden = true }
            let search = RGBA(.systemYellow.withAlphaComponent(0.35), in: r.textView.traitCollection)
            let current = RGBA(.systemOrange, in: r.textView.traitCollection)
            #expect(try #require(r.rgba(.backgroundColor, at: 0)).isClose(to: search))
            #expect(try #require(r.rgba(.backgroundColor, at: 6)).isClose(to: current))
            #expect(try #require(r.rgba(.foregroundColor, at: 6)).isClose(to: RGBA(red: 0, green: 0, blue: 0)))
            #expect(r.rgba(.backgroundColor, at: 5) == nil)
        }

        @Test func searchMatchInMarkdownParagraphHighlightsRenderedText() async throws {
            let block = ContentBlock(type: .paragraph, text: "The **cat** sat", url: nil, caption: nil, html: nil, mathml: nil)
            let matches = SearchMatch.compute(query: "sat", blocks: [block])
            let r = try await render("The **cat** sat", searchRanges: matches.map(\.range))
            defer { r.window.isHidden = true }
            #expect(r.attributed.string == "The cat sat")
            let search = RGBA(.systemYellow.withAlphaComponent(0.35), in: r.textView.traitCollection)
            #expect(r.rgba(.backgroundColor, at: 8)?.isClose(to: search) == true)
        }


        @Test func editMenuOffersAnnotateForSelectionOnly() async throws {
            let box = Box<NSRange>()
            let r = try await render("hello world", onAnnotate: { box.value = $0 })
            defer { r.window.isHidden = true }
            let copy = UIAction(title: "Copy") { _ in }

            let withSelection = try #require(r.coordinator.textView(
                r.textView, editMenuForTextIn: NSRange(location: 0, length: 2), suggestedActions: [copy]))
            let annotate = try #require(withSelection.children.first as? UIAction)
            #expect(annotate.title == "Annotate")
            #expect(withSelection.children.count == 2)
            annotate.performWithSender(nil, target: nil)
            #expect(box.value == NSRange(location: 0, length: 2))

            let caretOnly = try #require(r.coordinator.textView(
                r.textView, editMenuForTextIn: NSRange(location: 3, length: 0), suggestedActions: [copy]))
            #expect(caretOnly.children.count == 1)
            #expect((caretOnly.children.first as? UIAction)?.title == "Copy")
        }

        @Test func tapOnlyBeginsOverAnnotatedText() async throws {
            let r = try await render("hello world", annotations: [annotation(0, 5)])
            defer { r.window.isHidden = true }
            let tap = FakeTap()
            tap.point = r.center(of: NSRange(location: 1, length: 3))
            #expect(r.coordinator.gestureRecognizerShouldBegin(tap) == true)
            tap.point = r.center(of: NSRange(location: 7, length: 3))
            #expect(r.coordinator.gestureRecognizerShouldBegin(tap) == false)

            r.coordinator.handleTap(tap)
            #expect(r.coordinator.presentedPopover == nil)
        }

        @Test func tapOnAnnotationShowsNotePopoverWithEditAndDelete() async throws {
            let note = annotation(0, 5, note: "My note")
            let edited = Box<Annotation>()
            let deleted = Box<Annotation>()
            let r = try await render("hello world", annotations: [note],
                                     onEdit: { edited.value = $0 }, onDelete: { deleted.value = $0 })
            defer { r.window.isHidden = true }
            let tap = FakeTap()
            tap.point = r.center(of: NSRange(location: 1, length: 3))

            r.coordinator.handleTap(tap)
            var popover = try #require(r.coordinator.presentedPopover as? UIHostingController<AnnotationPopoverView>)
            #expect(popover.rootView.noteText == "My note")
            let style = r.coordinator.adaptivePresentationStyle(
                for: try #require(popover.presentationController), traitCollection: UITraitCollection())
            #expect(style == .none)

            popover.rootView.onEdit()
            #expect(edited.value?.id == note.id)
            #expect(r.coordinator.presentedPopover == nil)
            try await waitUntil { popover.presentingViewController == nil }

            r.coordinator.handleTap(tap)
            popover = try #require(r.coordinator.presentedPopover as? UIHostingController<AnnotationPopoverView>)
            popover.rootView.onDelete()
            #expect(deleted.value?.id == note.id)
            #expect(r.coordinator.presentedPopover == nil)
            try await waitUntil { popover.presentingViewController == nil }
        }

        @Test func coordinatorWithoutTextViewNeverBegins() {
            let coordinator = TextBlockView.Coordinator(
                onAnnotate: { _ in }, onEditAnnotation: { _ in }, onDeleteAnnotation: { _ in }, annotations: [])
            #expect(coordinator.gestureRecognizerShouldBegin(FakeTap()) == false)
            coordinator.handleTap(FakeTap())
            #expect(coordinator.presentedPopover == nil)
        }
    }
}
