import Foundation

struct PendingAnnotation {
    let blockSection: String
    let blockIndex: Int
    let range: NSRange
    let cellRow: Int
    let cellColumn: Int

    static func text(section: String, index: Int, range: NSRange) -> PendingAnnotation {
        PendingAnnotation(blockSection: section, blockIndex: index, range: range, cellRow: -1, cellColumn: -1)
    }

    static func cell(index: Int, row: Int, col: Int) -> PendingAnnotation {
        PendingAnnotation(blockSection: BlockSection.content, blockIndex: index, range: NSRange(location: 0, length: 0), cellRow: row, cellColumn: col)
    }

    static func equation(index: Int) -> PendingAnnotation {
        PendingAnnotation(blockSection: BlockSection.content, blockIndex: index, range: NSRange(location: -1, length: 0), cellRow: -1, cellColumn: -1)
    }
}
