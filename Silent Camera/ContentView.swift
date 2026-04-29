import SwiftUI
import AVFoundation
internal import _LocationEssentials

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var showFlash = false
    @State private var showMetadata = false
    @State private var lastZoom: CGFloat = 1.0
    @State private var showZoomLabel = false
    @State private var zoomLabelTask: Task<Void, Never>?
    @State private var focusPoint: CGPoint? = nil
    @State private var showFocusIndicator = false
    @State private var focusTask: Task<Void, Never>?
    @State private var showZoomSlider = false
    @State private var zoomSliderTask: Task<Void, Never>?
    @State private var showCircularZoom = false
    @State private var circularZoomTask: Task<Void, Never>?
    @State private var zoomWheelPrevTranslation: CGFloat = 0
    @State private var shutterIsLongPress = false
    @State private var isRecordingLocked = false
    @State private var shutterDragOffset: CGFloat = 0
    @State private var shutterScale: CGFloat = 1.0
    @State private var isSliding = false
    @State private var longPressTask: Task<Void, Never>? = nil
    @State private var zoomInertiaTask: Task<Void, Never>?
    @State private var cameraFlipDegrees: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let slideThreshold: CGFloat = 60
    
    private let fbGenerator = UINotificationFeedbackGenerator()
    
    private var rotAngle: Angle { .degrees(camera.uiRotationDegrees) }
    private func anim(_ a: Animation) -> Animation { reduceMotion ? .easeInOut(duration: 0.2) : a }

    /// ユーザー視点のズームプリセット（wideAngleZoomFactor を「1x」基準として計算）
    private var zoomPresets: [(label: String, factor: CGFloat)] {
        let w = camera.wideAngleZoomFactor
        var presets: [(String, CGFloat)] = []
        if camera.minZoomFactor < w - 0.1 {
            presets.append((".5x", camera.minZoomFactor))
        }
        for (label, mult) in [("1x", 1.0), ("2x", 2.0), ("3x", 3.0), ("5x", 5.0), ("10x", 10.0), ("25x", 25.0)] {
            let factor = w * CGFloat(mult)
            if factor <= camera.maxZoomFactor { presets.append((label, factor)) }
        }
        return presets
    }

    private var zoomBinding: Binding<Double> {
        Binding(
            get: { Double(camera.zoomFactor) },
            set: { val in
                camera.setZoom(CGFloat(val))
                lastZoom = CGFloat(val)
                flashZoomLabel()
                resetZoomSliderTimer()
            }
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            previewArea
                .rotation3DEffect(.degrees(cameraFlipDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.4)

            VStack {
                topBar
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                Spacer()
                bottomBar
            }

        }
        .onAppear { camera.startSession() }
        .onChange(of: camera.wideAngleZoomFactor) { lastZoom = camera.wideAngleZoomFactor }
        .onDisappear { camera.stopSession() }
        .onReceive(NotificationCenter.default.publisher(for: .cameraControlDidActivate)) { _ in
            camera.startSession()
        }
.sheet(isPresented: $showMetadata) {
            if let metadata = camera.savedMetadata {
                MetadataView(metadata: metadata)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                switchCameraWithFlip()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 16, weight: .semibold))
                    .topBarIcon(rotation: rotAngle, uiRotation: camera.uiRotationDegrees)
            }
            .topBarButton(isRecording: camera.isRecording)

            if camera.isRecording {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(formatDuration(camera.recordingDuration))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .animation(anim(.default), value: camera.recordingDuration)
                    if isRecordingLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.yellow)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .glassEffect(in: .capsule)
                .transition(.opacity)
            }

            Spacer()

            Button {
                camera.setVideoQuality(camera.videoQuality.next)
            } label: {
                Text(camera.videoQuality.rawValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .topBarIcon(rotation: rotAngle, uiRotation: camera.uiRotationDegrees)
            }
            .topBarButton(isRecording: camera.isRecording)

            Button {
                camera.captureAspectRatio = camera.captureAspectRatio.next
            } label: {
                Text(camera.captureAspectRatio.rawValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .topBarIcon(rotation: rotAngle, uiRotation: camera.uiRotationDegrees)
            }
            .topBarButton(isRecording: camera.isRecording)
        }
        .animation(anim(.easeInOut(duration: 0.2)), value: camera.isRecording)
    }

    // MARK: - Preview Area

    private var previewArea: some View {
        ZStack {
            if camera.authorizationStatus == .authorized {
                CameraPreviewView(
                    previewLayer: camera.previewLayer,
                    previewView: camera.previewView,
                    onCameraControl: triggerCapture
                )
                .gesture(pinchGesture)
                .onTapGesture { location in
                    camera.focus(at: location)
                    showFocusAt(location)
                }
            } else if camera.authorizationStatus == .denied {
                VStack(spacing: 16) {
                    Image(systemName: "camera.slash")
                        .font(.system(size: 60))
                        .foregroundStyle(.white)
                    Text("カメラへのアクセスが許可されていません")
                        .foregroundStyle(.white)
                    Text("設定 > Silent Camera でカメラを許可してください")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding()
            }

            if showFocusIndicator, let pt = focusPoint {
                FocusIndicator().position(pt).allowsHitTesting(false)
            }

            Color.white.opacity(showFlash ? 0.7 : 0).allowsHitTesting(false)

            if let error = camera.errorMessage {
                VStack {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.red.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .rotationEffect(rotAngle)
                        .animation(.easeInOut(duration: 0.3), value: camera.uiRotationDegrees)
                    Spacer()
                }
                .padding(.top, 10)
            }

         

        }
        .aspectRatio(camera.captureAspectRatio.previewRatio, contentMode: .fit)
        .animation(anim(.easeInOut(duration: 0.3)), value: camera.captureAspectRatio)
        .clipped()
        .onLongPressGesture(minimumDuration: 0.4) {
            withAnimation(anim(.spring(duration: 0.25))) { showZoomSlider = true }
            resetZoomSliderTimer()
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 18) {
            if showZoomLabel {
                ZStack {
                    Capsule()
                        .frame(width: 100, height: 40)
                        .glassEffect(.regular.tint(.clear))
                    Text(String(format: "%.1fx", lastZoom / camera.wideAngleZoomFactor))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .rotationEffect(rotAngle)
                }
                .transition(.opacity)
                .animation(anim(.default), value: lastZoom)
                .animation(.easeInOut(duration: 0.3), value: camera.uiRotationDegrees)
            }
            
            ZStack {
                if showCircularZoom {
                    CircularZoomSlider(
                        rotAngle: rotAngle,
                        zoomFactor: lastZoom,
                        minZoom: camera.minZoomFactor,
                        maxZoom: camera.maxZoomFactor,
                        presets: zoomPresets
                    )
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                } else {
                    HStack(spacing: 8) {
                        ForEach(zoomPresets, id: \.factor) { preset in
                            ZoomPresetButton(
                                label: preset.label,
                                isSelected: abs(camera.zoomFactor - preset.factor) < 0.15,
                                rotationDegrees: camera.uiRotationDegrees
                            ) {
                              
                                camera.animateZoom(to: preset.factor)
                                lastZoom = preset.factor
                                flashZoomLabel()
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(height: 72)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        zoomInertiaTask?.cancel()
                        if !showCircularZoom {
                            withAnimation(anim(.spring(duration: 0.25))) { showCircularZoom = true }
                            zoomWheelPrevTranslation = value.translation.width
                        }
                        let dx = value.translation.width - zoomWheelPrevTranslation
                        zoomWheelPrevTranslation = value.translation.width
                        let speed = abs(value.velocity.width)
                        let speedFactor = max(1.0, speed / 300.0)
                        let pxPerLog = 40.0 / speedFactor
                        let logChange = -Double(dx) / pxPerLog
                        let raw = Double(lastZoom) * Foundation.exp(logChange)
                        let newZoom = CGFloat(max(Double(camera.minZoomFactor), min(Double(camera.maxZoomFactor), raw)))
                        camera.setZoom(newZoom)
                        lastZoom = newZoom
                        flashZoomLabel()
                        resetCircularZoomTimer()
                    }
                    .onEnded { value in
                        zoomWheelPrevTranslation = 0
                        camera.commitZoom()
                        let vel = value.velocity.width
                        guard abs(vel) > 80 && !reduceMotion else { return }
                        zoomInertiaTask = Task { @MainActor in
                            var v = vel
                            while abs(v) > 20 && !Task.isCancelled {
                                let dx = v / 60.0
                                let logChange = -Double(dx) / 220.0
                                let raw = Double(lastZoom) * Foundation.exp(logChange)
                                let newZoom = CGFloat(max(Double(camera.minZoomFactor), min(Double(camera.maxZoomFactor), raw)))
                                camera.setZoom(newZoom)
                                lastZoom = newZoom
                                flashZoomLabel()
                                resetCircularZoomTimer()
                                v *= 0.90
                                try? await Task.sleep(nanoseconds: 16_666_667)
                            }
                            camera.commitZoom()
                        }
                    }
            )

            GeometryReader { geo in
                // 右ボタン中心までのオフセット：画面中央 → 右ボタン中心（trailing 28 + radius 35）
                let targetOffset = geo.size.width / 2 - 63

                ZStack(alignment: .center) {
                    // 左：サムネイル（最背面）
                    HStack {
                        thumbnailView.padding(.leading, 28)
                        Spacer()
                    }

                    // 右：ガラス円のみ（白い円は中央ZStackが担う）
                    HStack {
                        Spacer()
                        ZStack {
                            if isRecordingLocked {
                                Button {
                                    triggerCapture()
                                   
                                } label: {
                                    Circle()
                                        .frame(width: 70, height: 70)
                                        .glassEffect(.regular)
                                }
                                .buttonStyle(.plain)
                            } else if camera.isRecording {
                                let progress = targetOffset > 0 ? 0.25 + 0.75 * Double(shutterDragOffset / targetOffset) : 0.25
                                Circle()
                                    .frame(width: 70, height: 70)
                                    .glassEffect(.regular)
                                    .opacity(progress)
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .opacity(progress)
                            }
                        }
                        .frame(width: 70, height: 70)
                        .padding(.trailing, 28)
                    }

                    // 中央：録画中は赤く、スライドで白い円が分裂して右へ
                    ZStack {
                        Circle()
                            .frame(width: 78, height: 78)
                            .glassEffect(.regular)

                        if isRecordingLocked {
                            // ロック中：停止アイコン（スケールなし）
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.red)
                                .frame(width: 30, height: 30)
                            // 白い円は右側オフセット位置に
                            Circle()
                                .fill(.white)
                                .frame(width: 64, height: 64)
                                .offset(x: shutterDragOffset)
                        } else {
                            // 通常・アーム・録画中：スケールアニメーション付き内側コンテンツ
                            ZStack {
                                if shutterIsLongPress || camera.isRecording {
                                    Circle().fill(.red).frame(width: 64, height: 64)
                                }
                                if !shutterIsLongPress && !camera.isRecording || shutterDragOffset > 1 {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 64, height: 64)
                                        .offset(x: shutterDragOffset)
                                }
                            }
                            .scaleEffect(shutterScale)
                        }
                    }
                    .contentShape(Circle())
                    .allowsHitTesting(camera.authorizationStatus == .authorized)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let dx = val.translation.width
                                if dx > 5 {
                                    if !isSliding {
                                        isSliding = true
                                        longPressTask?.cancel()
                                        longPressTask = nil
                                    }
                                    // 録画中かつ未ロック：スライド量を追跡
                                    if camera.isRecording && !isRecordingLocked {
                                        shutterDragOffset = min(dx, targetOffset)
                                    }
                                } else if !isSliding && longPressTask == nil && !camera.isRecording && !shutterIsLongPress {
                                    // 押し込み：白い円を縮小
                                    withAnimation(anim(.easeOut(duration: 0.12))) { shutterScale = 0.82 }
                                    // 長押しタイマー開始
                                    longPressTask = Task { @MainActor in
                                        try? await Task.sleep(for: .seconds(0.5))
                                        guard !Task.isCancelled else { return }
                                        shutterIsLongPress = true
                                        camera.successFeedback()
                                        camera.startRecording()
                                        // 縮小状態から赤く膨らみ、元のサイズへバウンス
                                        withAnimation(anim(.spring(duration: 0.45, bounce: 0.55))) {
                                            shutterScale = 1.0
                                        }
                                    }
                                }
                            }
                            .onEnded { val in
                                longPressTask?.cancel()
                                longPressTask = nil
                                let dx = val.translation.width

                                if camera.isRecording && isRecordingLocked {
                                    if abs(dx) < 10 {
                                        // タップで停止：円を右からセンターへスライドバック
                                        camera.stopRecording()
                                        isRecordingLocked = false
                                        withAnimation(anim(.spring(duration: 0.5, bounce: 0.15))) {
                                            shutterDragOffset = 0
                                        }
                                    }
                                } else if camera.isRecording {
                                    // 録画中（未ロック）に離した：閾値以上ならロック、未満はキャンセル
                                    if dx >= slideThreshold {
                                        camera.successFeedback()
                                        isRecordingLocked = true
                                        withAnimation(anim(.spring(duration: 0.4, bounce: 0.25))) {
                                            shutterDragOffset = targetOffset
                                        }
                                    } else if camera.recordingDuration >= 1 {
                                        camera.stopRecording()
                                        withAnimation(anim(.spring())) { shutterDragOffset = 0 }
                                    } else {
                                        withAnimation(anim(.spring())) {
                                            camera.cancelRecording()
                                            shutterDragOffset = 0
                                        }
                                    }
                                } else if !isSliding && abs(dx) < 10 {
                                    // 短タップ：写真
                                    triggerCapture()
                                } else {
                                    withAnimation(anim(.spring())) { shutterDragOffset = 0 }
                                }
                                isSliding = false
                                shutterIsLongPress = false
                                if shutterScale != 1.0 {
                                    withAnimation(anim(.spring(duration: 0.3))) { shutterScale = 1.0 }
                                }
                            }
                    )
                }
                .frame(width: geo.size.width, height: 78)
            }
            .frame(height: 78)
        }
        .padding(.vertical)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private var thumbnailView: some View {
        Button {
            UIApplication.shared.open(URL(string: "photos-redirect://")!)
        } label: {
            Group {
                if let image = camera.latestThumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.5), lineWidth: 1))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                        .frame(width: 56, height: 56)
                }
            }
            .rotationEffect(.degrees(camera.uiRotationDegrees))
            .animation(.easeInOut(duration: 0.3), value: camera.uiRotationDegrees)
        }
    }

    // MARK: - Gestures & Actions

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                camera.setZoom(lastZoom * value)
                flashZoomLabel()
            }
            .onEnded { _ in camera.commitZoom(); lastZoom = camera.zoomFactor }
    }

    private func showFocusAt(_ point: CGPoint) {
        focusPoint = point
        withAnimation(anim(.easeIn(duration: 0.1))) { showFocusIndicator = true }
        focusTask?.cancel()
        focusTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled {
                withAnimation(anim(.easeOut(duration: 0.3))) { showFocusIndicator = false }
            }
        }
    }

    private func flashZoomLabel() {
        withAnimation(anim(.easeIn(duration: 0.1))) { showZoomLabel = true }
        zoomLabelTask?.cancel()
        zoomLabelTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled {
                withAnimation(anim(.easeOut(duration: 0.3))) { showZoomLabel = false }
            }
        }
    }

    private func resetCircularZoomTimer() {
        circularZoomTask?.cancel()
        circularZoomTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                withAnimation(anim(.easeOut(duration: 0.3))) { showCircularZoom = false }
            }
        }
    }

    private func resetZoomSliderTimer() {
        zoomSliderTask?.cancel()
        zoomSliderTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                withAnimation(anim(.easeOut(duration: 0.3))) { showZoomSlider = false }
            }
        }
    }

    private func switchCameraWithFlip() {
        guard !camera.isRecording else { return }
        if reduceMotion {
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.25)) { cameraFlipDegrees = 90 }
                try? await Task.sleep(for: .milliseconds(125))
                camera.switchCamera()
                cameraFlipDegrees = -90
                withAnimation(.easeInOut(duration: 0.25)) { cameraFlipDegrees = 0 }
            }
            return
        }
        Task { @MainActor in
            withAnimation(.easeIn(duration: 0.18)) { cameraFlipDegrees = 90 }
            try? await Task.sleep(for: .milliseconds(180))
            camera.switchCamera()
            cameraFlipDegrees = -90
            withAnimation(.easeOut(duration: 0.18)) { cameraFlipDegrees = 0 }
        }
    }

    private func triggerCapture() {
        fbGenerator.notificationOccurred(.success)
        camera.capturePhoto()
        withAnimation(.easeIn(duration: 0.05)) { showFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.15)) { showFlash = false }
        }
    }
}

#Preview {
    ContentView()
}
