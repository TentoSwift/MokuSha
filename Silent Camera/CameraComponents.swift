import SwiftUI

// MARK: - Circular Zoom Slider (Apple Camera-style scroll wheel)

struct CircularZoomSlider: View {
    let rotAngle: Angle
    let zoomFactor: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    let presets: [(label: String, factor: CGFloat)]

    // pixels per unit of ln(zoom) — controls drag sensitivity and label spacing
    private let pxPerLog: CGFloat = 160
    // large radius → very gentle parabolic curvature
    private let wheelRadius: CGFloat = 900

    // horizontal pixel offset of zoom z from center (current zoom = 0)
    private func xOff(_ z: CGFloat) -> CGFloat {
        CGFloat(log(Double(z / zoomFactor))) * pxPerLog
    }

    // upward y deflection for arc curvature (parabolic approximation of circle)
    private func yDrop(_ x: CGFloat) -> CGFloat {
        (x * x) / (2 * wheelRadius)   // positive = downward from arc top
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let cx = W / 2
            let arcTop: CGFloat = 8   // y of arc at center (topmost point)

            ZStack {
                Canvas { ctx, size in
                    // Tick marks along arc
                    var logZ = log(Double(minZoom) * 0.8)
                    let logEnd = log(Double(maxZoom) * 1.2)
                    while logZ <= logEnd {
                        let z = CGFloat(exp(logZ))
                        let xo = xOff(z)
                        let x = cx + xo
                        let y = arcTop + yDrop(xo)
                        guard x > -10 && x < W + 10 else { logZ += 0.055; continue }
                        let isMajor = presets.contains { abs(log(Double($0.factor / z))) < 0.04 }
                        let h: CGFloat = isMajor ? 18 : 8
                        ctx.stroke(
                            Path { p in
                                p.move(to: CGPoint(x: x, y: y))
                                p.addLine(to: CGPoint(x: x, y: y + h))
                            },
                            with: .color(.white.opacity(isMajor ? 0.9 : 0.35)),
                            style: StrokeStyle(lineWidth: isMajor ? 1.5 : 1, lineCap: .round)
                        )
                        logZ += 0.055
                    }
                    // Yellow center indicator
                    ctx.stroke(
                        Path { p in
                            p.move(to: CGPoint(x: cx, y: arcTop - 1))
                            p.addLine(to: CGPoint(x: cx, y: H - 4))
                        },
                        with: .color(.yellow),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                }

                // Preset labels above their tick marks
                ForEach(presets, id: \.factor) { preset in
                    let xo = xOff(preset.factor)
                    let x = cx + xo
                    let y = arcTop + yDrop(xo)
                    let active = abs(log(Double(zoomFactor / preset.factor))) < 0.15
                    Text(preset.label)
                        .font(.system(size: 12, weight: active ? .bold : .regular, design: .rounded))
                        .foregroundStyle(active ? Color.yellow : Color.white.opacity(0.8))
                        .rotationEffect(rotAngle)
                        .animation(.easeInOut(duration: 0.3), value: rotAngle)
                        .position(x: x, y: y + 34)
                        .opacity(x > -30 && x < W + 30 ? 1 : 0)
                }
            }
        }
        .frame(height: 72)
        .clipShape(Capsule())
        .background(.black.opacity(0.5), in: Capsule())
    }
}

// MARK: - Focus Indicator

struct FocusIndicator: View {
    @State private var scale: CGFloat = 1.3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(.yellow, lineWidth: 1.5)
            .frame(width: 72, height: 72)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.2)) { scale = 1.0 }
            }
    }
}

// MARK: - Zoom Preset Button

struct ZoomPresetButton: View {
    let label: String
    let isSelected: Bool
    var rotationDegrees: Double = 0
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .black : .white)
                .rotationEffect(.degrees(rotationDegrees))
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.3), value: rotationDegrees)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        }
        .glassEffect(.regular.interactive().tint(isSelected ? .yellow : .clear), in: .circle)
        .opacity(isSelected ? 1 : 0.85)
    }
}
