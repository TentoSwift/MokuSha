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
        Group {
            if #available(iOS 26.0, *) {
                content.glassEffect(in: .circle)
            } else {
                // iOS 18.6–25.x: 半透明グレーの円形背景でフォールバック
                content.background(.ultraThinMaterial, in: Circle())
            }
        }
        .disabled(isRecording)
        .opacity(isRecording ? 0.4 : 1.0)
    }
}

// MARK: - Glass Prominent Button (iOS 26+ → fallback)

/// iOS 26 では `.glassProminent` ボタンスタイル、それ未満では `.borderedProminent` でフォールバック。
struct GlassProminentButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
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

    /// iOS 26 では Liquid Glass、それ未満では `.ultraThinMaterial` でフォールバック表示。
    @ViewBuilder
    func compatibleGlassEffect<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// `compatibleGlassEffect` の Capsule 用ショートカット。
    @ViewBuilder
    func compatibleGlassEffectCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// `compatibleGlassEffect` の RoundedRectangle 用ショートカット。
    @ViewBuilder
    func compatibleGlassEffectRoundedRect(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
