import SwiftUI
import Testing
@testable import DailyDose

private func block(_ index: Int, _ type: ContentBlockType, text: String? = nil) -> ContentBlock {
    var b = ContentBlock(type: type, text: text, url: nil, caption: nil, html: nil, mathml: nil)
    b.index = index
    return b
}

extension AppTests {
    @Suite struct ViewLogicTests {
        @Test func searchIgnoresBlankQuery() {
            #expect(SearchMatch.compute(query: "  ", blocks: [block(0, .paragraph, text: "cat")]).isEmpty)
        }

        @Test func searchTrimsAndIgnoresCase() {
            let m = SearchMatch.compute(query: " CAT ", blocks: [block(0, .paragraph, text: "a cat")])
            #expect(m == [SearchMatch(blockIndex: 0, range: NSRange(location: 2, length: 3))])
        }

        @Test func searchFindsEveryOccurrenceInOrder() {
            let m = SearchMatch.compute(query: "ab", blocks: [block(3, .paragraph, text: "ab xx ab")])
            #expect(m.map(\.range.location) == [0, 6])
            #expect(m.allSatisfy { $0.blockIndex == 3 })
        }

        @Test func searchCoversHeadingsAndParagraphsOnly() {
            let blocks = [
                block(0, .heading, text: "cat"),
                block(1, .paragraph, text: "cat"),
                block(2, .image, text: "cat"),
                block(3, .table, text: "cat"),
                block(4, .math, text: "cat"),
                block(5, .paragraph),
            ]
            #expect(SearchMatch.compute(query: "cat", blocks: blocks).map(\.blockIndex) == [0, 1])
        }

        @Test func searchHighlightsRenderedCharactersNotMarkdown() {
            let blocks = [block(0, .paragraph, text: "The **cat** sat")]
            #expect(SearchMatch.compute(query: "sat", blocks: blocks).first?.range.location == 8)
            #expect(SearchMatch.compute(query: "cat sat", blocks: blocks).count == 1)
        }

        @Test func inlineMarkdownResolvesNestedAndAdjacentMarkers() {
            func styled(_ s: String) -> String {
                InlineMarkdown.runs(s).map { run in
                    run.text + "|" + (run.bold ? "B" : "") + (run.italic ? "I" : "")
                        + (run.baseline > 0 ? "^" : run.baseline < 0 ? "_" : "")
                }.joined(separator: "/")
            }
            #expect(styled("***a** b*") == "a|BI/ b|I")
            #expect(styled("**bold *it***") == "bold |B/it|BI")
            #expect(styled("*K*_(d)") == "K|I/d|_")
            #expect(styled("^(*a*)") == "a|I^")
            #expect(styled("^(a (b) c)") == "a (b) c|^")
            #expect(InlineMarkdown.plain("2 * 3 * 4") == "2 * 3 * 4")
            #expect(InlineMarkdown.plain("n = 5*, then *x*") == "n = 5*, then x")
        }

        @Test func groupedAndCurrentRange() {
            let a = SearchMatch(blockIndex: 1, range: NSRange(location: 0, length: 1))
            let b = SearchMatch(blockIndex: 1, range: NSRange(location: 5, length: 1))
            let c = SearchMatch(blockIndex: 4, range: NSRange(location: 2, length: 1))
            let all = [a, b, c]
            #expect(all.grouped() == [1: [a.range, b.range], 4: [c.range]])
            #expect(all.currentRange(at: 2, forBlock: 4) == c.range)
            #expect(all.currentRange(at: 2, forBlock: 1) == nil)
            #expect(all.currentRange(at: 3, forBlock: 4) == nil)
            #expect(all.currentRange(at: -1, forBlock: 1) == nil)
            #expect([SearchMatch]().currentRange(at: 0, forBlock: 0) == nil)
        }

        @Test func fabPositionCornersAreConsistent() {
            let cases: [(FABPosition, Bool, Bool)] = [
                (.topLeft, true, true), (.topRight, true, false),
                (.bottomLeft, false, true), (.bottomRight, false, false),
            ]
            for (position, top, leading) in cases {
                let insets = position.edgeInsets
                #expect((insets.top != 0) == top)
                #expect((insets.bottom != 0) == !top)
                #expect((insets.leading != 0) == leading)
                #expect((insets.trailing != 0) == !leading)
                #expect(position.isTopAligned == top)

                let v: VerticalAlignment = top ? .top : .bottom
                let h: HorizontalAlignment = leading ? .leading : .trailing
                #expect(position.alignment == Alignment(horizontal: h, vertical: v))
                #expect(position.vStackAlignment == h)
                #expect(position.transitionAnchor == UnitPoint(x: leading ? 0 : 1, y: top ? 0 : 1))
            }
        }

        @Test func fabPositionRawValuesMatchPersistedStrings() {
            #expect(FABPosition(rawValue: "topLeft") == .topLeft)
            #expect(FABPosition(rawValue: "topRight") == .topRight)
            #expect(FABPosition(rawValue: "bottomLeft") == .bottomLeft)
            #expect(FABPosition(rawValue: "bottomRight") == .bottomRight)
        }

        @Test func displayModes() {
            #expect(DisplayMode(rawValue: 0)?.colorScheme == nil)
            #expect(DisplayMode(rawValue: 1)?.colorScheme == .light)
            #expect(DisplayMode(rawValue: 2)?.colorScheme == .dark)
            #expect(DisplayMode.allCases.map(\.label) == ["System", "Light", "Dark"])
            #expect(DisplayMode(rawValue: 7) == nil)
        }
    }
}
