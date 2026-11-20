import SwiftUI
import UIKit

struct TextBlockView: UIViewRepresentable {
    static let searchMatchColor = UIColor.systemGray.withAlphaComponent(0.35)
    static let currentSearchMatchColor = UIColor.systemOrange

    let text: String
    let annotations: [Annotation]
    var searchRanges: [NSRange] = []
    var currentSearchRange: NSRange? = nil
    var baseFont: UIFont? = nil
    var baseFontWeight: UIFont.Weight? = nil
    var textColor: UIColor = .label
    var enableMarkdown: Bool = true
    var lineSpacingRatio: CGFloat = 0
    let onAnnotate: (NSRange) -> Void
    let onEditAnnotation: (Annotation) -> Void
    let onDeleteAnnotation: (Annotation) -> Void

    private func resolvedFont() -> UIFont {
        let base = baseFont ?? UIFont.preferredFont(forTextStyle: .body)
        guard let weight = baseFontWeight else { return base }
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: 0)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
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
        coordinator.onEditAnnotation = onEditAnnotation
        coordinator.onDeleteAnnotation = onDeleteAnnotation
        coordinator.annotations = annotations

        let highlightKeys = annotations.map(\.highlightKey)
        let annotationsChanged = highlightKeys != coordinator.lastHighlightKeys
        let searchChanged = searchRanges != coordinator.lastSearchRanges
                         || currentSearchRange != coordinator.lastCurrentSearchRange
        guard text != coordinator.lastText || annotationsChanged || searchChanged else { return }

        let font = resolvedFont()
        let attributedText = enableMarkdown ? parseMarkdown(text, font: font) : plainText(text, font: font)
        let mutableAttr = NSMutableAttributedString(attributedString: attributedText)
        if lineSpacingRatio > 0 {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = font.pointSize * lineSpacingRatio
            mutableAttr.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: mutableAttr.length))
        }
        for annotation in annotations where annotation.isTextAnnotation {
            let range = annotation.range
            if range.location + range.length <= mutableAttr.length {
                mutableAttr.addAttribute(.backgroundColor, value: annotation.highlightColor.uiColor, range: range)
            }
        }

        for range in searchRanges {
            if range.location + range.length <= mutableAttr.length {
                mutableAttr.addAttribute(.backgroundColor, value: Self.searchMatchColor, range: range)
            }
        }
        if let current = currentSearchRange,
           current.location + current.length <= mutableAttr.length {
            mutableAttr.addAttribute(.backgroundColor, value: Self.currentSearchMatchColor, range: current)
            mutableAttr.addAttribute(.foregroundColor, value: UIColor.black, range: current)
        }

        textView.attributedText = mutableAttr
        coordinator.lastText = text
        coordinator.lastHighlightKeys = highlightKeys
        coordinator.lastSearchRanges = searchRanges
        coordinator.lastCurrentSearchRange = currentSearchRange
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? (uiView.window?.windowScene?.screen.bounds.width ?? 390) - 40
        let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fittingSize.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onAnnotate: onAnnotate, onEditAnnotation: onEditAnnotation, onDeleteAnnotation: onDeleteAnnotation, annotations: annotations)
    }

    // MARK: - Text Building

    private func plainText(_ input: String, font: UIFont) -> NSAttributedString {
        NSAttributedString(string: input, attributes: [
            .font: font,
            .foregroundColor: textColor
        ])
    }

    // MARK: - Markdown Parser

    private func parseMarkdown(_ input: String, font: UIFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in InlineMarkdown.runs(input) {
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
            var traits: UIFontDescriptor.SymbolicTraits = []
            if run.bold { traits.insert(.traitBold) }
            if run.italic { traits.insert(.traitItalic) }
            if traits.isEmpty && run.baseline == 0 {
                attrs[.font] = font
            } else {
                let size = run.baseline == 0 ? font.pointSize : font.pointSize * 0.7
                let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits)) ?? font.fontDescriptor
                attrs[.font] = UIFont(descriptor: descriptor, size: size)
            }
            if run.baseline > 0 { attrs[.baselineOffset] = font.pointSize * 0.35 }
            if run.baseline < 0 { attrs[.baselineOffset] = -(font.pointSize * 0.15) }
            result.append(NSAttributedString(string: run.text, attributes: attrs))
        }
        return result
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, UIPopoverPresentationControllerDelegate {
        var textView: UITextView?
        var onAnnotate: (NSRange) -> Void
        var onEditAnnotation: (Annotation) -> Void
        var onDeleteAnnotation: (Annotation) -> Void
        var annotations: [Annotation]
        var lastText: String = ""
        var lastHighlightKeys: [HighlightKey] = []
        var lastSearchRanges: [NSRange] = []
        var lastCurrentSearchRange: NSRange? = nil
        weak var presentedPopover: UIViewController?

        init(
            onAnnotate: @escaping (NSRange) -> Void,
            onEditAnnotation: @escaping (Annotation) -> Void,
            onDeleteAnnotation: @escaping (Annotation) -> Void,
            annotations: [Annotation]
        ) {
            self.onAnnotate = onAnnotate
            self.onEditAnnotation = onEditAnnotation
            self.onDeleteAnnotation = onDeleteAnnotation
            self.annotations = annotations
        }

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
            guard let annotation = annotationAtRange(NSRange(location: offset, length: 1)) else { return }
            presentAnnotationPopover(annotation, in: textView)
        }

        private func presentAnnotationPopover(_ annotation: Annotation, in textView: UITextView) {
            let range = annotation.range
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length),
                  let textRange = textView.textRange(from: start, to: end) else { return }

            let rects = textView.selectionRects(for: textRange)
                .map { $0.rect }
                .filter { $0.width > 0 && $0.height > 0 }
            let sourceRect = rects.first ?? textView.firstRect(for: textRange)

            let content = AnnotationPopoverView(
                noteText: annotation.noteText,
                onEdit: { [weak self] in
                    self?.presentedPopover?.dismiss(animated: true)
                    self?.presentedPopover = nil
                    self?.onEditAnnotation(annotation)
                },
                onDelete: { [weak self] in
                    self?.presentedPopover?.dismiss(animated: true)
                    self?.presentedPopover = nil
                    self?.onDeleteAnnotation(annotation)
                }
            )

            let host = UIHostingController(rootView: content)
            host.modalPresentationStyle = .popover
            host.view.backgroundColor = .clear
            let targetSize = host.sizeThatFits(in: CGSize(width: 280, height: CGFloat.greatestFiniteMagnitude))
            host.preferredContentSize = CGSize(
                width: 280,
                height: min(max(targetSize.height, 60), 400)
            )

            if let popover = host.popoverPresentationController {
                popover.sourceView = textView
                popover.sourceRect = sourceRect
                popover.permittedArrowDirections = [.up, .down]
                popover.delegate = self
            }

            guard let vc = sequence(first: textView as UIResponder, next: \.next)
                .first(where: { $0 is UIViewController }) as? UIViewController else { return }
            (vc.presentedViewController ?? vc).present(host, animated: true)
            presentedPopover = host
        }

        func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
            .none
        }

        private func characterOffset(in textView: UITextView, at point: CGPoint) -> Int {
            guard let position = textView.closestPosition(to: point) else { return 0 }
            return textView.offset(from: textView.beginningOfDocument, to: position)
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            if range.length > 0 {
                let exists = annotations.contains { $0.isTextAnnotation && $0.range == range }
                let annotateAction = UIAction(
                    title: exists ? "Edit Note" : "Add Note",
                    image: UIImage(systemName: exists ? "pencil" : "note.text.badge.plus")
                ) { [weak self] _ in
                    self?.onAnnotate(range)
                }
                return UIMenu(children: [annotateAction] + suggestedActions)
            }

            return UIMenu(children: suggestedActions)
        }

        private func annotationAtRange(_ range: NSRange) -> Annotation? {
            for annotation in annotations where annotation.isTextAnnotation {
                let intersection = NSIntersectionRange(range, annotation.range)
                if intersection.length > 0 {
                    return annotation
                }
            }
            return nil
        }
    }
}

struct AnnotationPopoverView: View {
    let noteText: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(noteText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Spacer()
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.borderless)
        }
        .padding(16)
    }
}
