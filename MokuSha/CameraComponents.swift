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

// MARK: - Composition Guides

/// 三分割法のグリッドライン（rule of thirds）
struct GridLinesOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                // 縦線 2 本（width の 1/3, 2/3 位置）
                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: 2 * w / 3, y: 0))
                path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                // 横線 2 本（height の 1/3, 2/3 位置）
                path.move(to: CGPoint(x: 0, y: h / 3))
                path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: 2 * h / 3))
                path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
            }
            .stroke(.white.opacity(0.4), lineWidth: 0.5)
        }
    }
}

/// 水平線インジケータ：iOS 純正カメラの水平器と同じパターン。
/// 画面中央高さに、3 分割された短い線を配置:
///   - 左 1/3 と右 1/3 = 動かない固定の参照線
///   - 中央 1/3 = デバイスのロールに合わせて回転する可動線
/// 中央線が水平（左右と一直線）になった瞬間 = 水平が取れた瞬間に accent カラーで強調。
struct LevelIndicator: View {
    let rollDegrees: Double
    let uiRotationDegrees: Double

    /// 現在の向きに対する実効ロール（縦持ち時の rollDegrees に相当）。
    /// rollDegrees + uiRotationDegrees をしてから [-180, 180] に正規化。
    private var effectiveRoll: Double {
        var diff = rollDegrees + uiRotationDegrees
        while diff > 180 { diff -= 360 }
        while diff < -180 { diff += 360 }
        return diff
    }

    private var isLevel: Bool { abs(effectiveRoll) < 1.5 }

    /// 横持ち（landscape）かどうか。uiRotationDegrees が ±90° 周辺で true。
    private var isLandscapeOrientation: Bool {
        let normalized = (uiRotationDegrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return (normalized > 45 && normalized < 135) || (normalized > 225 && normalized < 315)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let stub: CGFloat = 24 // 左右（上下）の固定参照線の長さ
            let gap: CGFloat = 6   // 通常時にグリッドラインから離す距離
            let color: Color = isLevel ? Color.accentColor : Color.white.opacity(0.55)
            let thickness: CGFloat = isLevel ? 1.5 : 0.6

            ZStack {
                if isLandscapeOrientation {
                    // 横持ち：縦レイアウトで横グリッドライン (h/3, 2h/3) に揃える
                    let third = h / 3
                    let centerLength: CGFloat = isLevel ? third : max(third - 2 * gap, 0)
                    let topY: CGFloat    = isLevel ? (third - stub / 2)     : (third - gap - stub / 2)
                    let bottomY: CGFloat = isLevel ? (2 * third + stub / 2) : (2 * third + gap + stub / 2)

                    // 上の固定参照線（縦向きの短い線）
                    Rectangle()
                        .fill(color)
                        .frame(width: thickness, height: stub)
                        .position(x: w / 2, y: topY)

                    // 下の固定参照線（縦向きの短い線）
                    Rectangle()
                        .fill(color)
                        .frame(width: thickness, height: stub)
                        .position(x: w / 2, y: bottomY)

                    // 中央の可動線（縦向き、デバイス傾きで微回転）
                    Rectangle()
                        .fill(color)
                        .frame(width: thickness, height: centerLength)
                        .rotationEffect(.degrees(-effectiveRoll))
                        .position(x: w / 2, y: h / 2)
                } else {
                    // 縦持ち（または上下逆）：横レイアウトで縦グリッドライン (w/3, 2w/3) に揃える
                    let third = w / 3
                    let centerWidth: CGFloat = isLevel ? third : max(third - 2 * gap, 0)
                    let leftX: CGFloat  = isLevel ? (third - stub / 2)     : (third - gap - stub / 2)
                    let rightX: CGFloat = isLevel ? (2 * third + stub / 2) : (2 * third + gap + stub / 2)

                    // 左の固定参照線
                    Rectangle()
                        .fill(color)
                        .frame(width: stub, height: thickness)
                        .position(x: leftX, y: h / 2)

                    // 右の固定参照線
                    Rectangle()
                        .fill(color)
                        .frame(width: stub, height: thickness)
                        .position(x: rightX, y: h / 2)

                    // 中央の可動線（横向き、デバイス傾きで微回転）
                    Rectangle()
                        .fill(color)
                        .frame(width: centerWidth, height: thickness)
                        .rotationEffect(.degrees(-effectiveRoll))
                        .position(x: w / 2, y: h / 2)
                }
            }
            .frame(width: w, height: h)
        }
        .allowsHitTesting(false)
        .animation(.linear(duration: 0.05), value: effectiveRoll)
        .animation(.easeInOut(duration: 0.3), value: uiRotationDegrees)
        .animation(.easeInOut(duration: 0.2), value: isLevel)
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

// MARK: - Zoom Preset Glass Modifier

/// iOS 26: 選択時に黄色 tint の interactive glass、非選択は透明 glass。
/// iOS 25 以下: 選択時に黄色塗り、非選択は半透明 material でフォールバック。
private struct ZoomPresetGlassModifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive().tint(isSelected ? .yellow : .clear), in: .circle)
        } else {
            content
                .background(
                    Group {
                        if isSelected {
                            Circle().fill(.yellow)
                        } else {
                            Circle().fill(.ultraThinMaterial)
                        }
                    }
                )
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
        .modifier(ZoomPresetGlassModifier(isSelected: isSelected))
        .opacity(isSelected ? 1 : 0.85)
    }
}
