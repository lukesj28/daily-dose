import UIKit
import Testing
@testable import DailyDose

@MainActor
private func keyWindow() -> UIWindow {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    return window
}

extension AppTests {
    @Suite struct SaveIconAnimatorTests {
        let animator = SaveIconAnimator.shared

        @Test func iconAppearsSixtyPointsAboveFinger() {
            let window = keyWindow()
            defer { animator.hide(); window.isHidden = true }
            let before = window.subviews.count
            animator.show(at: CGPoint(x: 100, y: 300))
            #expect(window.subviews.count == before + 1)
            #expect(window.subviews.last?.center == CGPoint(x: 100, y: 240))
        }

        @Test func secondShowReplacesFirst() {
            let window = keyWindow()
            defer { animator.hide(); window.isHidden = true }
            animator.show(at: CGPoint(x: 100, y: 300))
            let count = window.subviews.count
            animator.show(at: CGPoint(x: 50, y: 200))
            #expect(window.subviews.count == count)
            #expect(window.subviews.last?.center == CGPoint(x: 50, y: 140))
        }

        @Test func moveFollowsFingerWithoutAnimation() {
            let window = keyWindow()
            defer { animator.hide(); window.isHidden = true }
            animator.show(at: CGPoint(x: 100, y: 300))
            animator.move(to: CGPoint(x: 200, y: 400))
            #expect(window.subviews.last?.layer.position == CGPoint(x: 200, y: 340))
        }

        @Test func hideRemovesIcon() {
            let window = keyWindow()
            defer { window.isHidden = true }
            let before = window.subviews.count
            animator.show(at: CGPoint(x: 100, y: 300))
            animator.hide()
            #expect(window.subviews.count == before)
        }

        @Test func flyToLibraryCompletesAndRemovesIcon() async throws {
            let window = keyWindow()
            defer { animator.hide(); window.isHidden = true }
            let before = window.subviews.count
            animator.show(at: CGPoint(x: 100, y: 300))
            let done = Box<Bool>()
            animator.flyToLibrary { done.value = true }
            try await waitUntil(timeout: .seconds(2)) { done.value == true }
            #expect(window.subviews.count == before)
        }

        @Test func flyToLibraryWithoutIconDoesNothing() async throws {
            let window = keyWindow()
            defer { window.isHidden = true }
            animator.hide()
            let before = window.subviews.count
            let done = Box<Bool>()
            animator.flyToLibrary { done.value = true }
            try await Task.sleep(for: .milliseconds(200))
            #expect(done.value == nil)
            #expect(window.subviews.count == before)
        }
    }
}
