import SwiftUI
import AVFoundation
import AVKit
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
    @State private var cameraControlLongPressTask: Task<Void, Never>? = nil
    @State private var cameraControlIsLongPress = false
    @State private var showSettings = false
    @AppStorage("showCompositionGuides") private var showCompositionGuides = false
    @AppStorage("showHorizonLevel") private var showHorizonLevel = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let slideThreshold: CGFloat = 60

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
            // ロック画面／ホーム長押し等からカメラコントロールが起動された場合：
            // 設定シートが開いていたら閉じてカメラに戻る
            if showSettings { showSettings = false }
            camera.startSession()
        }
.sheet(isPresented: $showMetadata) {
            if let metadata = camera.savedMetadata {
                MetadataView(metadata: metadata)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
            .accessibilityLabel("カメラ切替")
            .accessibilityHint(camera.isFrontCamera ? "現在は前面カメラ。タップで背面に切替" : "現在は背面カメラ。タップで前面に切替")

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
                .compatibleGlassEffectCapsule()
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(isRecordingLocked
                    ? "録画中、ロック済み、\(formatDuration(camera.recordingDuration))"
                    : "録画中、\(formatDuration(camera.recordingDuration))")
            }

            Button {
                camera.isSilentMode.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: camera.isSilentMode ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(camera.isSilentMode ? "無音" : "音あり")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(camera.isSilentMode ? .yellow : .white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .compatibleGlassEffectCapsule()
            }
            .animation(.easeInOut(duration: 0.2), value: camera.isSilentMode)
            .accessibilityLabel(camera.isSilentMode ? "無音モード、シャッター音は鳴りません" : "音ありモード、シャッター音が鳴ります")
            .accessibilityHint("タップで切替")

            Spacer()

            Button {
                camera.setVideoQuality(camera.videoQuality.next)
            } label: {
                Text(camera.videoQuality.rawValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .topBarIcon(rotation: rotAngle, uiRotation: camera.uiRotationDegrees)
            }
            .topBarButton(isRecording: camera.isRecording)
            .accessibilityLabel("動画画質、\(camera.videoQuality.rawValue)")
            .accessibilityHint("タップで切替")

            Button {
                camera.captureAspectRatio = camera.captureAspectRatio.next
            } label: {
                Text(camera.captureAspectRatio.rawValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .topBarIcon(rotation: rotAngle, uiRotation: camera.uiRotationDegrees)
            }
            .topBarButton(isRecording: camera.isRecording)
            .accessibilityLabel("アスペクト比、\(camera.captureAspectRatio.rawValue)")
            .accessibilityHint("タップで切替")

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .topBarIcon(rotation: rotAngle, uiRotation: camera.uiRotationDegrees)
            }
            .topBarButton(isRecording: camera.isRecording)
            .accessibilityLabel("設定")
            .accessibilityHint("構図ガイド、触覚フィードバック、チップなどの設定")
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
                    onCameraControl: handleCameraControl
                )
                .gesture(pinchGesture)
                .onTapGesture { location in
                    camera.focus(at: location)
                    showFocusAt(location)
                }
            } else if camera.authorizationStatus == .denied {
                VStack(spacing: 20) {
                    Image(systemName: "camera.slash")
                        .font(.system(size: 60))
                        .foregroundStyle(.white)
                    Text("カメラへのアクセスが許可されていません")
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("システム設定を開く", systemImage: "gear")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                    .modifier(GlassProminentButtonModifier())
                }
                .padding()
            }

            if showCompositionGuides {
                GridLinesOverlay()
                    .allowsHitTesting(false)
            }

            if showHorizonLevel {
                Group {
                    if camera.isScreenRoughlyVertical {
                        LevelIndicator(
                            rollDegrees: camera.deviceRollDegrees,
                            uiRotationDegrees: camera.uiRotationDegrees
                        )
                        .allowsHitTesting(false)
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: camera.isScreenRoughlyVertical)
            }

            if showFocusIndicator, let pt = focusPoint {
                FocusIndicator().position(pt).allowsHitTesting(false)
            }

            Color.black.opacity(showFlash ? 0.7 : 0).allowsHitTesting(false)

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
                        .compatibleGlassEffectCapsule()
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
                                        .compatibleGlassEffect(in: Circle())
                                }
                                .buttonStyle(.plain)
                            } else if camera.isRecording {
                                let progress = targetOffset > 0 ? 0.25 + 0.75 * Double(shutterDragOffset / targetOffset) : 0.25
                                Circle()
                                    .frame(width: 70, height: 70)
                                    .compatibleGlassEffect(in: Circle())
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
                            .compatibleGlassEffect(in: Circle())

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
                    .accessibilityElement()
                    .accessibilityLabel(camera.isRecording
                        ? (isRecordingLocked ? "録画停止" : "録画停止または右にスライドしてロック")
                        : "シャッター")
                    .accessibilityHint(camera.isRecording
                        ? "タップで録画停止"
                        : "タップで写真撮影、長押しで動画録画開始")
                    .accessibilityAddTraits(.isButton)
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
                                        camera.feedback(.recordingStart)
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
                                        camera.feedback(.recordingLock)
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
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                        .accessibilityLabel("最後に撮った写真")
                        .accessibilityHint("タップで写真ライブラリを開く")
                } else {
                    Circle()
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                        .frame(width: 56, height: 56)
                        .accessibilityLabel("写真ライブラリ")
                        .accessibilityHint("タップで写真ライブラリを開く")
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

    /// カメラコントロール（iPhone 16 のハードウェアボタン）の押下フェーズを
    /// 画面シャッターと同じ「短押し→写真／長押し→録画→離す→停止」に対応付ける
    private func handleCameraControl(phase: AVCaptureEventPhase) {
        // 設定シートが開いている時は、シートを閉じてカメラ画面に戻る挙動だけ行う
        // （写真撮影や録画は発火させない）
        if showSettings {
            if phase == .began {
                showSettings = false
            }
            cameraControlIsLongPress = false
            cameraControlLongPressTask?.cancel()
            cameraControlLongPressTask = nil
            return
        }
        switch phase {
        case .began:
            // すでに録画中なら長押しタイマーは動かさない（.ended で停止判定する）
            guard !camera.isRecording else {
                cameraControlIsLongPress = false
                return
            }
            cameraControlIsLongPress = false
            cameraControlLongPressTask?.cancel()
            cameraControlLongPressTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                cameraControlIsLongPress = true
                camera.feedback(.recordingStart)
                camera.startRecording()
            }
        case .ended:
            cameraControlLongPressTask?.cancel()
            cameraControlLongPressTask = nil
            if camera.isRecording {
                // 自分の長押しで録画開始 → 画面でロックされている状態で離した：そのまま続行
                if isRecordingLocked && cameraControlIsLongPress {
                    cameraControlIsLongPress = false
                    return
                }
                // それ以外（未ロックで離した／ロック録画中に押して停止）：停止
                if camera.recordingDuration >= 1 {
                    camera.stopRecording()
                } else {
                    camera.cancelRecording()
                }
                if isRecordingLocked {
                    isRecordingLocked = false
                    withAnimation(anim(.spring(duration: 0.5, bounce: 0.15))) {
                        shutterDragOffset = 0
                    }
                }
            } else if !cameraControlIsLongPress {
                triggerCapture()
            }
            cameraControlIsLongPress = false
        case .cancelled:
            cameraControlLongPressTask?.cancel()
            cameraControlLongPressTask = nil
            if camera.isRecording && cameraControlIsLongPress {
                camera.cancelRecording()
            }
            cameraControlIsLongPress = false
        @unknown default:
            break
        }
    }

    private func triggerCapture() {
        camera.feedback(.photo)
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
