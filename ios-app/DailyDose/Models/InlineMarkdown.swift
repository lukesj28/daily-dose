import Foundation

enum InlineMarkdown {
    struct Run {
        var text: String
        var bold = false
        var italic = false
        var baseline = 0
    }

    static func runs(_ input: String) -> [Run] {
        var parser = Parser(Array(input))
        parser.parse()
        return parser.flatten()
    }

    static func plain(_ input: String) -> String {
        runs(input).map(\.text).joined()
    }

    private enum Marker {
        case bold, italic, superscript, `subscript`
    }

    private struct Node {
        var text: String
        var closes: [Marker] = []
        var opens: [Marker] = []
    }

    private struct Delimiter {
        let node: Int
        let length: Int
        var remaining: Int
        let canOpen: Bool
        let canClose: Bool
    }

    private struct Bracket {
        let node: Int
        let marker: Marker
        let delimiterBottom: Int
    }

    private struct Parser {
        let chars: [Character]
        var nodes: [Node] = []
        var delimiters: [Delimiter] = []
        var brackets: [Bracket?] = []
        var text = ""

        init(_ chars: [Character]) { self.chars = chars }

        mutating func parse() {
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c == "*" {
                    var end = i
                    while end < chars.count, chars[end] == "*" { end += 1 }
                    let before = char(at: i - 1), after = char(at: end)
                    delimiters.append(Delimiter(
                        node: push(String(chars[i..<end])),
                        length: end - i,
                        remaining: end - i,
                        canOpen: Self.isLeftFlanking(before: before, after: after),
                        canClose: Self.isLeftFlanking(before: after, after: before)
                    ))
                    i = end
                } else if c == "^" || c == "_", char(at: i + 1) == "(", let next = char(at: i + 2), next != ")" {
                    let marker: Marker = c == "^" ? .superscript : .subscript
                    brackets.append(Bracket(node: push(String(chars[i...i + 1])), marker: marker, delimiterBottom: delimiters.count))
                    i += 2
                } else if c == ")", let top = brackets.last {
                    brackets.removeLast()
                    if let bracket = top {
                        processEmphasis(above: bracket.delimiterBottom)
                        nodes[bracket.node].text = ""
                        nodes[bracket.node].opens = [bracket.marker]
                        nodes[push("")].closes = [bracket.marker]
                    } else {
                        text.append(c)
                    }
                    i += 1
                } else {
                    if c == "(" { brackets.append(nil) }
                    text.append(c)
                    i += 1
                }
            }
            flushText()
            processEmphasis(above: 0)
        }

        func flatten() -> [Run] {
            var runs: [Run] = []
            var open: [Marker] = []
            for node in nodes {
                open.removeLast(node.closes.count)
                if !node.text.isEmpty {
                    var run = Run(text: node.text)
                    for marker in open {
                        switch marker {
                        case .bold: run.bold = true
                        case .italic: run.italic = true
                        case .superscript: run.baseline = 1
                        case .subscript: run.baseline = -1
                        }
                    }
                    runs.append(run)
                }
                open.append(contentsOf: node.opens.reversed())
            }
            return runs
        }

        private mutating func processEmphasis(above bottom: Int) {
            var current = bottom
            while current < delimiters.count {
                let closer = delimiters[current]
                guard closer.canClose else { current += 1; continue }
                guard let index = (bottom..<current).last(where: { Self.matches(delimiters[$0], closer) }) else {
                    if closer.canOpen { current += 1 } else { delimiters.remove(at: current) }
                    continue
                }
                let opener = delimiters[index]
                let use = opener.remaining >= 2 && closer.remaining >= 2 ? 2 : 1
                let marker: Marker = use == 2 ? .bold : .italic
                nodes[opener.node].text.removeLast(use)
                nodes[opener.node].opens.append(marker)
                nodes[closer.node].text.removeFirst(use)
                nodes[closer.node].closes.append(marker)
                delimiters[index].remaining -= use
                delimiters[current].remaining -= use
                delimiters.removeSubrange(index + 1..<current)
                current = index + 1
                if delimiters[index].remaining == 0 { delimiters.remove(at: index); current -= 1 }
                if delimiters[current].remaining == 0 { delimiters.remove(at: current) }
            }
            delimiters.removeSubrange(bottom...)
        }

        private mutating func push(_ token: String) -> Int {
            flushText()
            nodes.append(Node(text: token))
            return nodes.count - 1
        }

        private mutating func flushText() {
            guard !text.isEmpty else { return }
            nodes.append(Node(text: text))
            text = ""
        }

        private func char(at i: Int) -> Character? {
            chars.indices.contains(i) ? chars[i] : nil
        }

        private static func matches(_ opener: Delimiter, _ closer: Delimiter) -> Bool {
            guard opener.canOpen else { return false }
            let sum = opener.length + closer.length
            let ruleOfThree = (opener.canClose || closer.canOpen) && sum % 3 == 0
                && !(opener.length % 3 == 0 && closer.length % 3 == 0)
            return !ruleOfThree
        }

        private static func isLeftFlanking(before: Character?, after: Character?) -> Bool {
            guard let after, !after.isWhitespace else { return false }
            guard after.isPunctuation || after.isSymbol, let before else { return true }
            return before.isWhitespace || before.isPunctuation || before.isSymbol
        }
    }
}
