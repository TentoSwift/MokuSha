//
//  AssistiveAccessContentView.swift
//  Silent Camera
//
//  Assistive Access モード専用 UI。WWDC 2025 セッション 238 ガイドラインに基づく：
//   - 段階的フロー（選択 → 撮影 の 2 ステップ）
//   - 1 画面 1 機能（写真画面では写真のみ、動画画面では動画のみ）
//   - 大きく明確なコントロール、アイコン＋ラベル併用
//   - 隠れたジェスチャー禁止
//   - 時間制限なし
//

import SwiftUI
import AVFoundation

// MARK: - Root: 選択画面

struct AssistiveAccessContentView: View {
    var body: some View {
        NavigationStack {
            AssistiveAccessSelectionView()
        }
    }
}

private struct AssistiveAccessSelectionView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("何を撮りますか？")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)

            NavigationLink {
                AssistiveAccessPhotoCaptureView()
            } label: {
                AABigChoiceLabel(
                    icon: "camera.fill",
                    title: "写真を撮る",
                    tint: .blue
                )
            }
            .accessibilityLabel("写真を撮る")
            .accessibilityHint("写真撮影画面に進みます")

            NavigationLink {
                AssistiveAccessVideoCaptureView()
            } label: {
                AABigChoiceLabel(
                    icon: "video.fill",
                    title: "動画を撮る",
                    tint: .red
                )
            }
            .accessibilityLabel("動画を撮る")
            .accessibilityHint("動画録画画面に進みます")

            Spacer()
        }
        .padding(.horizontal, 24)
        .navigationTitle("撮影")
        .assistiveAccessNavigationIcon(systemImage: "camera.aperture")
    }
}

// MARK: - 写真撮影画面

private struct AssistiveAccessPhotoCaptureView: View {
    @StateObject private var camera = CameraManager()
    @State private var showFlash = false
    @State private var savedMessage = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            previewArea

            Color.black
                .opacity(showFlash ? 0.7 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                Spacer()
                Button(action: capture) {
                    AABigActionLabel(
                        icon: "camera.fill",
                        title: "写真をとる",
                        tint: .blue
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .accessibilityLabel("写真をとる")
                .accessibilityHint("タップで 1 枚撮影します")
                .disabled(camera.authorizationStatus != .authorized)
            }

            if !savedMessage.isEmpty {
                AAConfirmationToast(message: savedMessage)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .navigationTitle("写真")
        .assistiveAccessNavigationIcon(systemImage: "camera.fill")
        .onAppear {
            camera.isSilentMode = true
            camera.startSession()
        }
        .onDisappear {
            camera.stopSession()
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        if camera.authorizationStatus == .authorized {
            CameraPreviewView(
                previewLayer: camera.previewLayer,
                previewView: camera.previewView,
                onCameraControl: { _ in }
            )
            .accessibilityLabel("カメラのプレビュー")
        } else {
            AAUnauthorizedView()
        }
    }

    private func capture() {
        camera.feedback(.photo)
        camera.capturePhoto()
        withAnimation(.easeIn(duration: 0.05)) { showFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.15)) { showFlash = false }
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            savedMessage = "写真を保存しました"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.4)) { savedMessage = "" }
        }
    }
}

// MARK: - 動画録画画面

private struct AssistiveAccessVideoCaptureView: View {
    @StateObject private var camera = CameraManager()
    @State private var savedMessage = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            previewArea

            // 録画中の時間表示（画面上部、大きく）
            if camera.isRecording {
                VStack {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(.red)
                            .frame(width: 14, height: 14)
                        Text(formatDuration(camera.recordingDuration))
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.default, value: camera.recordingDuration)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.black.opacity(0.7), in: Capsule())
                    .padding(.top, 16)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("録画中、\(formatDuration(camera.recordingDuration))")
                    Spacer()
                }
            }

            VStack {
                Spacer()
                Button(action: toggleRecording) {
                    if camera.isRecording {
                        AABigActionLabel(
                            icon: "stop.fill",
                            title: "停止する",
                            tint: .red
                        )
                    } else {
                        AABigActionLabel(
                            icon: "video.fill",
                            title: "録画する",
                            tint: .red
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .accessibilityLabel(camera.isRecording ? "停止する" : "録画する")
                .accessibilityHint(camera.isRecording
                    ? "タップで録画を止めて保存します"
                    : "タップで動画録画を開始します")
                .disabled(camera.authorizationStatus != .authorized)
            }

            if !savedMessage.isEmpty {
                AAConfirmationToast(message: savedMessage)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .navigationTitle(camera.isRecording ? "録画中" : "動画")
        .assistiveAccessNavigationIcon(systemImage: "video.fill")
        .onAppear {
            camera.isSilentMode = true
            camera.startSession()
        }
        .onDisappear {
            if camera.isRecording { camera.cancelRecording() }
            camera.stopSession()
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        if camera.authorizationStatus == .authorized {
            CameraPreviewView(
                previewLayer: camera.previewLayer,
                previewView: camera.previewView,
                onCameraControl: { _ in }
            )
            .accessibilityLabel("カメラのプレビュー")
        } else {
            AAUnauthorizedView()
        }
    }

    private func toggleRecording() {
        if camera.isRecording {
            camera.stopRecording()
            withAnimation(.easeInOut(duration: 0.3)) {
                savedMessage = "動画を保存しました"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                withAnimation(.easeOut(duration: 0.4)) { savedMessage = "" }
            }
        } else {
            camera.startRecording()
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - 共通ラベル/トーストコンポーネント

private struct AABigChoiceLabel: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .semibold))
            Text(title)
                .font(.system(size: 26, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
}

private struct AABigActionLabel: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .semibold))
            Text(title)
                .font(.system(size: 28, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
}

private struct AAConfirmationToast: View {
    let message: String

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(.black.opacity(0.75), in: Capsule())
            .padding(.top, 80)
            Spacer()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .allowsHitTesting(false)
    }
}

private struct AAUnauthorizedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 80))
                .foregroundStyle(.white)
            Text("カメラを使うには許可が必要です。")
                .font(.title2)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

#Preview(traits: .assistiveAccess) {
    AssistiveAccessContentView()
}
