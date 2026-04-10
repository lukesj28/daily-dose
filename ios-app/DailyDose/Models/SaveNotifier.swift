import Observation
import CoreGraphics

@Observable
final class SaveNotifier {
    var didSave: Bool = false
    var dragLocation: CGPoint? = nil
    var animationStart: CGPoint? = nil
}
