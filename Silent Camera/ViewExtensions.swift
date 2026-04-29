import SwiftUI

// MARK: - Top Bar Icon

struct TopBarIconModifier: ViewModifier {
    let rotation: Angle
    let uiRotation: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .rotationEffect(rotation)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.3), value: uiRotation)
    }
}

// MARK: - Top Bar Button

struct TopBarButtonModifier: ViewModifier {
    let isRecording: Bool

    func body(content: Content) -> some View {
        content
            .glassEffect(in: .circle)
            .disabled(isRecording)
            .opacity(isRecording ? 0.4 : 1.0)
    }
}

// MARK: - View Extensions

extension View {
    func topBarIcon(rotation: Angle, uiRotation: Double) -> some View {
        modifier(TopBarIconModifier(rotation: rotation, uiRotation: uiRotation))
    }

    func topBarButton(isRecording: Bool) -> some View {
        modifier(TopBarButtonModifier(isRecording: isRecording))
    }
}
