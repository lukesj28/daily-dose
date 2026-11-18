import CoreGraphics

struct SaveSwipe {
    static let showDistance: CGFloat = 50
    static let saveDistance: CGFloat = 100

    struct Change: Equatable { var showIcon = false; var moveIcon = false; var haptic = false }
    enum End: Equatable { case ignore, hide, save }

    private(set) var iconVisible = false
    private var aboveThreshold = false
    private var cancelledByTable = false

    mutating func changed(translation: CGSize, tableScrolling: Bool) -> Change {
        var change = Change()
        let horizontal = translation.width
        if iconVisible {
            change.moveIcon = true
            change.haptic = updateThreshold(horizontal)
            return change
        }
        guard abs(horizontal) > abs(translation.height) else { return change }
        if tableScrolling { cancelledByTable = true; return change }
        if horizontal > Self.showDistance { iconVisible = true; change.showIcon = true }
        change.haptic = updateThreshold(horizontal)
        return change
    }

    mutating func ended(translation: CGSize, tableScrolling: Bool) -> End {
        defer { iconVisible = false; aboveThreshold = false; cancelledByTable = false }
        guard iconVisible else { return .ignore }
        if cancelledByTable || tableScrolling { return .hide }
        return translation.width > Self.saveDistance ? .save : .hide
    }

    private mutating func updateThreshold(_ horizontal: CGFloat) -> Bool {
        let isAbove = horizontal > Self.saveDistance
        guard isAbove != aboveThreshold else { return false }
        aboveThreshold = isAbove
        return true
    }
}
