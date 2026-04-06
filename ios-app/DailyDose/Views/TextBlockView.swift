import SwiftUI
import UIKit

struct TextBlockView: UIViewRepresentable {
    let text: String
    let annotations: [Annotation]
    let onAnnotate: (NSRange) -> Void
    let onViewAnnotation: (Annotation) -> Void
    let onEditAnnotation: (Annotation) -> Void
    let onDeleteAnnotation: (Annotation) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        textView.addGestureRecognizer(tap)

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onAnnotate = onAnnotate
        coordinator.onViewAnnotation = onViewAnnotation
        coordinator.onEditAnnotation = onEditAnnotation
        coordinator.onDeleteAnnotation = onDeleteAnnotation

        let annotationsChanged = annotations.map(\.id) != coordinator.annotations.map(\.id)
        guard text != coordinator.lastText || annotationsChanged else {
            coordinator.annotations = annotations
            return
        }

        let attributedText = parseMarkdown(text)
        let mutableAttr = NSMutableAttributedString(attributedString: attributedText)
        let highlightColor = UIColor(red: 1.0, green: 0.98, blue: 0.8, alpha: 0.6)

        for annotation in annotations {
            let range = annotation.range
            if range.location + range.length <= mutableAttr.length {
                mutableAttr.addAttribute(.backgroundColor, value: highlightColor, range: range)
            }
        }

        textView.attributedText = mutableAttr
        coordinator.annotations = annotations
        coordinator.lastText = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 40
        let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fittingSize.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onAnnotate: onAnnotate, onViewAnnotation: onViewAnnotation, onEditAnnotation: onEditAnnotation, onDeleteAnnotation: onDeleteAnnotation, annotations: annotations)
    }

    // MARK: - Markdown Parser

    private func parseMarkdown(_ input: String) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let boldFont = UIFont.boldSystemFont(ofSize: bodyFont.pointSize)
        let italicFont = UIFont.italicSystemFont(ofSize: bodyFont.pointSize)

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.label,
        ]

        var remaining = input

        while !remaining.isEmpty {
            if let boldRange = remaining.range(of: #"\*\*(.+?)\*\*"#, options: .regularExpression) {
                let before = String(remaining[remaining.startIndex..<boldRange.lowerBound])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: baseAttributes))
                }
                let matched = String(remaining[boldRange])
                let boldText = String(matched.dropFirst(2).dropLast(2))
                var attrs = baseAttributes
                attrs[.font] = boldFont
                result.append(NSAttributedString(string: boldText, attributes: attrs))
                remaining = String(remaining[boldRange.upperBound...])
                continue
            }

            if let italicRange = remaining.range(of: #"\*(.+?)\*"#, options: .regularExpression) {
                let before = String(remaining[remaining.startIndex..<italicRange.lowerBound])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: baseAttributes))
                }
                let matched = String(remaining[italicRange])
                let italicText = String(matched.dropFirst(1).dropLast(1))
                var attrs = baseAttributes
                attrs[.font] = italicFont
                result.append(NSAttributedString(string: italicText, attributes: attrs))
                remaining = String(remaining[italicRange.upperBound...])
                continue
            }

            if let supRange = remaining.range(of: #"\^\((.+?)\)"#, options: .regularExpression) {
                let before = String(remaining[remaining.startIndex..<supRange.lowerBound])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: baseAttributes))
                }
                let matched = String(remaining[supRange])
                let supText = String(matched.dropFirst(2).dropLast(1))
                var attrs = baseAttributes
                attrs[.font] = UIFont.systemFont(ofSize: bodyFont.pointSize * 0.7)
                attrs[.baselineOffset] = bodyFont.pointSize * 0.35
                result.append(NSAttributedString(string: supText, attributes: attrs))
                remaining = String(remaining[supRange.upperBound...])
                continue
            }

            if let subRange = remaining.range(of: #"_\((.+?)\)"#, options: .regularExpression) {
                let before = String(remaining[remaining.startIndex..<subRange.lowerBound])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: baseAttributes))
                }
                let matched = String(remaining[subRange])
                let subText = String(matched.dropFirst(2).dropLast(1))
                var attrs = baseAttributes
                attrs[.font] = UIFont.systemFont(ofSize: bodyFont.pointSize * 0.7)
                attrs[.baselineOffset] = -(bodyFont.pointSize * 0.15)
                result.append(NSAttributedString(string: subText, attributes: attrs))
                remaining = String(remaining[subRange.upperBound...])
                continue
            }

            result.append(NSAttributedString(string: remaining, attributes: baseAttributes))
            break
        }

        return result
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var textView: UITextView?
        var onAnnotate: (NSRange) -> Void
        var onViewAnnotation: (Annotation) -> Void
        var onEditAnnotation: (Annotation) -> Void
        var onDeleteAnnotation: (Annotation) -> Void
        var annotations: [Annotation]
        var lastText: String = ""

        init(
            onAnnotate: @escaping (NSRange) -> Void,
            onViewAnnotation: @escaping (Annotation) -> Void,
            onEditAnnotation: @escaping (Annotation) -> Void,
            onDeleteAnnotation: @escaping (Annotation) -> Void,
            annotations: [Annotation]
        ) {
            self.onAnnotate = onAnnotate
            self.onViewAnnotation = onViewAnnotation
            self.onEditAnnotation = onEditAnnotation
            self.onDeleteAnnotation = onDeleteAnnotation
            self.annotations = annotations
        }

        // Without this guard the gesture swallows all taps, breaking text selection.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let textView = textView else { return false }
            let point = gestureRecognizer.location(in: textView)
            let offset = characterOffset(in: textView, at: point)
            return annotationAtRange(NSRange(location: offset, length: 1)) != nil
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = textView else { return }
            let point = gesture.location(in: textView)
            let offset = characterOffset(in: textView, at: point)
            if let annotation = annotationAtRange(NSRange(location: offset, length: 1)) {
                onViewAnnotation(annotation)
            }
        }

        private func characterOffset(in textView: UITextView, at point: CGPoint) -> Int {
            guard let position = textView.closestPosition(to: point) else { return 0 }
            return textView.offset(from: textView.beginningOfDocument, to: position)
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            if let annotation = annotationAtRange(range) {
                let editAction = UIAction(title: "Edit Note", image: UIImage(systemName: "pencil")) { [weak self] _ in
                    self?.onEditAnnotation(annotation)
                }
                let deleteAction = UIAction(
                    title: "Delete Note",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.onDeleteAnnotation(annotation)
                }
                return UIMenu(children: [editAction, deleteAction] + suggestedActions)
            }

            if range.length > 0 {
                let annotateAction = UIAction(
                    title: "Annotate",
                    image: UIImage(systemName: "note.text.badge.plus")
                ) { [weak self] _ in
                    self?.onAnnotate(range)
                }
                return UIMenu(children: [annotateAction] + suggestedActions)
            }

            return UIMenu(children: suggestedActions)
        }

        private func annotationAtRange(_ range: NSRange) -> Annotation? {
            for annotation in annotations {
                let intersection = NSIntersectionRange(range, annotation.range)
                if intersection.length > 0 {
                    return annotation
                }
            }
            return nil
        }
    }
}
