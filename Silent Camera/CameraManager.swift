import AVFoundation
import SwiftUI
import AudioToolbox
import CoreHaptics
import CoreLocation
import CoreMotion
import MetalKit
import Photos
import UIKit
import UniformTypeIdentifiers
internal import Combine

/// AVCaptureSession の .playAndRecord 環境下では UIFeedbackGenerator が抑制されるため、
/// Core Haptics を直接使ってハプティック専用エンジンとして起動する。
@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private init() {
        prepareEngine()
        // バックグラウンド → フォアグラウンド復帰時にもエンジン再起動 & ウォームアップ
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleForeground() }
        }
    }

    private func handleForeground() {
        guard supportsHaptics else { return }
        if engine == nil {
            prepareEngine()
        } else {
            do { try engine?.start() } catch {
                NSLog("HapticManager: foreground restart failed: \(error)")
                engine = nil
                prepareEngine()
                return
            }
            warmup()
        }
    }

    private func prepareEngine() {
        guard supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false
            engine.stoppedHandler = { [weak self] reason in
                NSLog("HapticManager: engine stopped reason=\(reason.rawValue)")
                Task { @MainActor [weak self] in
                    self?.engine = nil
                    self?.prepareEngine()
                }
            }
            engine.resetHandler = { [weak self] in
                NSLog("HapticManager: engine reset")
                Task { @MainActor [weak self] in
                    do { try self?.engine?.start() } catch {
                        NSLog("HapticManager: restart failed: \(error)")
                    }
                }
            }
            try engine.start()
            self.engine = engine
            warmup()
        } catch {
            NSLog("HapticManager: prepare failed: \(error)")
            engine = nil
        }
    }

    /// Taptic Engine の「冷えた状態」での初回ピーク出力を抑えるためのウォームアップ。
    /// intensity 0.001 はほぼ知覚不能だが、内部の再生パスを一度通すことで初回が設定値通りに揃う。
    private func warmup() {
        guard let engine else { return }
        let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.001)
        let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0)
        if let pattern = try? CHHapticPattern(events: [event], parameters: []),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: CHHapticTimeImmediate)
        }
    }

    enum FeedbackType {
        /// 写真撮影：鋭い 1 クリック（カシャッ）
        case photo
        /// 録画開始：低→高 に立ち上がる 2 連打
        case recordingStart
        /// 録画停止：重い 1 発で終止符
        case recordingStop
        /// 録画ロック成立：軽快な 2 連打
        case recordingLock
        /// ズームのプリセット通過：ごく軽いティック
        case zoomTick
    }

    func play(_ type: FeedbackType) {
        guard supportsHaptics else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        let events: [CHHapticEvent]
        switch type {
        case .photo:
            let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.25)
            let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
            events = [CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0)]
        case .recordingStart:
            let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.25)
            let lowS  = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            let highS = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [i, lowS],  relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [i, highS], relativeTime: 0.10),
            ]
        case .recordingStop:
            let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.25)
            let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
            events = [CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0)]
        case .recordingLock:
            let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.18)
            let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
            events = [CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0)]
        case .zoomTick:
            // 「コツン」：低めシャープネスで重みのある単発（木やプラスチックを軽く叩く感触）
            let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.2)
            let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            events = [CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0)]
        }
        play(events: events)
    }

    private func play(events: [CHHapticEvent]) {
        guard let engine else {
            NSLog("HapticManager: engine nil, fallback")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            NSLog("HapticManager: play failed: \(error)")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

enum VideoQuality: String, CaseIterable {
    case q4K   = "4K"
    case q1080 = "HD"
    case q720  = "SD"

    var maxShortSide: Int {
        switch self {
        case .q4K:   return Int.max
        case .q1080: return 1080
        case .q720:  return 720
        }
    }

    var bitRate: Int {
        switch self {
        case .q4K:   return 25_000_000
        case .q1080: return 8_000_000
        case .q720:  return 4_000_000
        }
    }

    var exportPreset: String {
        switch self {
        case .q4K:   return AVAssetExportPresetHEVCHighestQuality
        case .q1080: return AVAssetExportPreset1920x1080
        case .q720:  return AVAssetExportPreset1280x720
        }
    }

    var next: VideoQuality {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

enum CaptureAspectRatio: String, CaseIterable {
    case fourThree   = "4:3"
    case oneOne      = "1:1"
    case sixteenNine = "16:9"

    var previewRatio: CGFloat {
        switch self {
        case .fourThree:   return 3.0 / 4.0
        case .oneOne:      return 1.0
        case .sixteenNine: return 9.0 / 16.0
        }
    }

    var next: CaptureAspectRatio {
        let all = Self.allCases
        let idx = all.firstIndex(of: self)!
        return all[(idx + 1) % all.count]
    }
}

@MainActor
class CameraManager: NSObject, ObservableObject {

    let session = AVCaptureSession()
    let previewLayer = AVCaptureVideoPreviewLayer()

    @Published var latestThumbnail: UIImage?
    @Published var savedMetadata: CaptureMetadata?
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    @Published var zoomFactor: CGFloat = 1.0
    @Published var isStabilizationEnabled: Bool = true
    @Published var captureResolution: CGSize = .zero
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var isFrontCamera: Bool = false
    @Published var videoQuality: VideoQuality = .q4K
    /// マナーモード ON（直近の検知結果）
    @Published var isSilentSwitchOn: Bool = false

    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var photoProcessor: PhotoCaptureProcessor?
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let captureQueue = DispatchQueue(label: "camera.capture")
    private let locationManager = CLLocationManager()

    let previewView = MetalCameraPreview()

    nonisolated(unsafe) private var currentColorStyle: Int = 0
    nonisolated(unsafe) private var currentUIRotation: Double = 0
    nonisolated(unsafe) private var currentAspectRatio: CaptureAspectRatio = .fourThree
    nonisolated(unsafe) private var recordingAspectRatio: CaptureAspectRatio = .fourThree
    nonisolated(unsafe) private var discardNextRecording = false
    nonisolated(unsafe) private var currentVideoQuality: VideoQuality = .q4K
    nonisolated(unsafe) private var recordingColorStyle: Int = 0
    nonisolated(unsafe) private var isRecordingUnsafe = false
    nonisolated(unsafe) private var currentLocation: CLLocation?
    nonisolated(unsafe) private var currentDevice: AVCaptureDevice?
    nonisolated(unsafe) private var currentWideAngleZoom: CGFloat = 1.0
    @available(iOS 18.0, *)
    nonisolated(unsafe) private var captureSlider: AVCaptureSlider? = nil
    nonisolated(unsafe) private var videoConnection: AVCaptureConnection?
    nonisolated(unsafe) private let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.displayP3) as Any,
    ])

    func feedback(_ type: HapticManager.FeedbackType) {
        HapticManager.shared.play(type)
    }

    /// マナーモード状態を検知して `isSilentSwitchOn` を更新する。
    /// `.playAndRecord` のままだと AudioServicesPlaySystemSound が silent switch を無視するため、
    /// 一時的に `.ambient` に切り替える。検知が終わったら元の `.playAndRecord` に戻す。
    func detectSilentSwitchState() async {
        // 録画中／検知実行中は同時実行しない（音声セッション衝突防止）
        guard !isRecording, !isDetectingMute else { return }
        isDetectingMute = true
        defer { isDetectingMute = false }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            return
        }
        let isMuted: Bool = await withCheckedContinuation { continuation in
            MuteChecker.shared.check { result in
                continuation.resume(returning: result)
            }
        }
        isSilentSwitchOn = isMuted
        try? session.setCategory(
            .playAndRecord,
            mode: .videoRecording,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try? session.setActive(true)
    }

    private static let zoomPresets: [CGFloat] = [1.0, 2.0, 3.0, 5.0, 10.0, 25.0]
    private static let zoomTickMinInterval: TimeInterval = 0.15
    private var lastZoomTickTime: TimeInterval = 0
    private var isAnimatingZoom = false

    private var _currentZoom: CGFloat = 1.0 {
        didSet {
            // アニメーション中は途中の発火を抑制（animateZoom 終点で 1 回だけ鳴らす）
            guard !isAnimatingZoom else { return }
            let w = currentWideAngleZoom
            guard w > 0, oldValue != _currentZoom else { return }
            let oldUser = oldValue / w
            let newUser = _currentZoom / w
            for preset in Self.zoomPresets {
                if (oldUser < preset && newUser >= preset) ||
                   (oldUser > preset && newUser <= preset) {
                    fireZoomTickIfAllowed()
                    return
                }
            }
        }
    }

    /// 直近 150ms 以内に鳴らしていなければズームティックを再生（ピンチの指ブレで連続発火するのを防ぐ）
    private func fireZoomTickIfAllowed() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastZoomTickTime > Self.zoomTickMinInterval else { return }
        lastZoomTickTime = now
        feedback(.zoomTick)
    }

    func commitZoom() {
        zoomFactor = _currentZoom
    }

    struct CaptureMetadata {
        let timestamp: Date
        let location: CLLocation?
        let iso: Float
        let exposureDuration: CMTime
        let lensAperture: Float
        let zoomFactor: CGFloat
        let fieldOfView: Float
        let lensType: String
        let deviceModel: String
        let imageSize: CGSize
        let stabilizationMode: String
    }

    override init() {
        super.init()
        previewLayer.videoGravity = .resizeAspectFill
        locationManager.delegate = self
    }

    // MARK: - Public API

    func startSession() {
        // 音声セッションを起動する前にハプティックエンジンを初期化
        _ = HapticManager.shared
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status
        switch status {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.authorizationStatus = granted ? .authorized : .denied
                    if granted { self?.setupSession() }
                }
            }
        default:
            break
        }
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        startMotionDetection()
        PHPhotoLibrary.shared().register(self)
        fetchLatestPhoto()
        registerCaptureSessionObservers()
        // セッション安定化のため少し待ってから初回マナーモード検知（1 回のみ）
        muteCheckTask?.cancel()
        muteCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            await self?.detectSilentSwitchState()
        }
    }

    /// 音声セッションの切替や他アプリへの切替などで AVCaptureSession が中断された場合に
    /// preview が止まることがある。各種復帰イベントで startRunning を呼んで preview を復活させる。
    private func registerCaptureSessionObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: session,
            queue: .main
        ) { notification in
            let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int) ?? -1
            print("[Session] interrupted reason=\(reason)")
        }
        center.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: session,
            queue: .main
        ) { [weak self] _ in
            print("[Session] interruption ended")
            self?.restartCaptureSessionIfNeeded()
        }
        center.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let err = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            print("[Session] runtime error: \(err?.localizedDescription ?? "unknown")")
            self?.restartCaptureSessionIfNeeded()
        }
        // バックグラウンド復帰時：他アプリ（写真など）から戻ったときに preview を確実に復帰させる
        center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("[Session] app did become active → restart capture session if needed")
            self?.restartCaptureSessionIfNeeded()
        }
    }

    /// セッションが停止していれば startRunning で復帰させる（sessionQueue で実行）
    private func restartCaptureSessionIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stopSession() {
        if isRecording { stopRecording() }
        muteCheckTask?.cancel()
        muteCheckTask = nil
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
        motionManager.stopAccelerometerUpdates()
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func fetchLatestPhoto() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            guard status == .authorized || status == .limited else { return }
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 1
            let result = PHAsset.fetchAssets(with: .image, options: options)
            guard let asset = result.firstObject else { return }
            let imgOptions = PHImageRequestOptions()
            imgOptions.deliveryMode = .opportunistic
            imgOptions.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 112, height: 112),
                contentMode: .aspectFill,
                options: imgOptions
            ) { [weak self] image, _ in
                guard let image else { return }
                Task { @MainActor [weak self] in self?.latestThumbnail = image }
            }
        }
    }

    func capturePhoto() {
        // 撮影瞬間のデバイス向きを写真ファイルの回転メタデータに焼き込む
        let rotationAngle = videoRotationAngle(for: currentUIRotation)
        if let conn = photoOutput.connection(with: .video),
           conn.isVideoRotationAngleSupported(rotationAngle) {
            conn.videoRotationAngle = rotationAngle
        }
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        // photoOutput が許可している最大寸法でリクエスト（48MP など）
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        // 画質優先：これがないと iOS は速度優先で 12MP に pixel-bin する
        settings.photoQualityPrioritization = .quality
        print("[Capture] photoOutput.maxPhotoDimensions=\(photoOutput.maxPhotoDimensions.width)x\(photoOutput.maxPhotoDimensions.height) settings.maxPhotoDimensions=\(settings.maxPhotoDimensions.width)x\(settings.maxPhotoDimensions.height)")
        let processor = PhotoCaptureProcessor(manager: self)
        photoProcessor = processor  // delegate を retain
        photoOutput.capturePhoto(with: settings, delegate: processor)
    }

    /// AVCapturePhotoCaptureDelegate からの撮影完了コールバック。
    /// AVFoundation が photo.metadata に書いた EXIF（レンズ・焦点距離・絞り・ISO 等）を
    /// 全て保持したまま、色味／クロップ／ダウンスケール後の HEIC を生成する。
    nonisolated func processCapturedPhoto(_ photo: AVCapturePhoto) {
        // cgImageRepresentation() はメモリ節約のためダウンスケール版を返すことがある。
        // フル解像度を得るには fileDataRepresentation() の HEIC バイト列をデコードする。
        guard let fileData = photo.fileDataRepresentation(),
              let source = CGImageSourceCreateWithData(fileData as CFData, nil) else { return }
        // HEIC 内部の構造を診断
        let count = CGImageSourceGetCount(source)
        let primary = CGImageSourceGetPrimaryImageIndex(source)
        print("[Capture] HEIC images count=\(count) primaryIdx=\(primary) fileData=\(fileData.count) bytes")
        for i in 0..<count {
            if let img = CGImageSourceCreateImageAtIndex(source, i, nil) {
                print("[Capture]   image[\(i)]: \(img.width)x\(img.height)")
            }
        }
        // primary 画像（フル解像度想定）を採用
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, primary, nil) else { return }
        print("[Capture] received cgImage \(cgImage.width)x\(cgImage.height)")
        let orientationRaw = (photo.metadata[kCGImagePropertyOrientation as String] as? UInt32) ?? 1
        let cgOrientation = CGImagePropertyOrientation(rawValue: orientationRaw) ?? .up
        var ci = CIImage(cgImage: cgImage).oriented(cgOrientation)
        ci = applyColorStyle(ci, style: currentColorStyle)
        let cropped = cropToAspectRatio(ci)
        guard let processedCG = ciContext.createCGImage(cropped, from: cropped.extent) else { return }
        let saveCG = downscaledIfNeeded(processedCG)
        let timestamp = Date()
        let location = currentLocation

        // 生メタデータを基準にして保存：レンズ情報・絞り・焦点距離など Apple が自動付与した EXIF を温存
        guard let imageData = buildImageDataFromPhotoMetadata(
            cgImage: saveCG,
            photoMetadata: photo.metadata,
            location: location,
            timestamp: timestamp
        ) else { return }

        // 画面表示用の構造体（EXIF とは別の in-app 表示パス）
        let device = currentDevice
        let zoom = device?.videoZoomFactor ?? 1.0
        let effectiveFOV = (device?.activeFormat.videoFieldOfView ?? 0) / Float(zoom)
        let stabLabel: String
        switch videoConnection?.activeVideoStabilizationMode {
        case .standard:          stabLabel = "スタンダード"
        case .cinematic:         stabLabel = "シネマティック"
        case .cinematicExtended: stabLabel = "シネマティック拡張"
        case .previewOptimized:  stabLabel = "プレビュー最適化"
        default:                 stabLabel = "オフ"
        }
        let inAppMetadata = CaptureMetadata(
            timestamp: timestamp,
            location: location,
            iso: device?.iso ?? 0,
            exposureDuration: device?.exposureDuration ?? .zero,
            lensAperture: device?.lensAperture ?? 0,
            zoomFactor: zoom,
            fieldOfView: effectiveFOV,
            lensType: "広角",
            deviceModel: UIDevice.current.model,
            imageSize: CGSize(width: saveCG.width, height: saveCG.height),
            stabilizationMode: stabLabel
        )
        Task { @MainActor [weak self] in
            self?.saveToPhotoLibrary(data: imageData, metadata: inAppMetadata)
        }
    }

    /// 写真の AVFoundation 生メタデータを基準に HEIC を生成。
    /// レンズ情報（LensModel／LensSpecification）、焦点距離、絞り、ISO、露出時間など
    /// Apple が自動付与する EXIF を全て保持し、向き・寸法・GPS だけ上書きする。
    nonisolated private func buildImageDataFromPhotoMetadata(
        cgImage: CGImage,
        photoMetadata: [String: Any],
        location: CLLocation?,
        timestamp: Date
    ) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.heic.identifier as CFString, 1, nil
        ) else { return nil }

        var props = photoMetadata
        props[kCGImageDestinationLossyCompressionQuality as String] = 0.95
        // ピクセル空間で既に回転済みなので EXIF / TIFF orientation は 1（Up）に固定
        props[kCGImagePropertyOrientation as String] = 1

        // EXIF：寸法をクロップ後・ダウンスケール後の値に上書き、その他のレンズ情報等は温存
        var exif = (props[kCGImagePropertyExifDictionary as String] as? [String: Any]) ?? [:]
        exif[kCGImagePropertyExifPixelXDimension as String] = cgImage.width
        exif[kCGImagePropertyExifPixelYDimension as String] = cgImage.height
        props[kCGImagePropertyExifDictionary as String] = exif

        // TIFF：orientation を 1 に、Software をアプリ名に
        var tiff = (props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]) ?? [:]
        tiff[kCGImagePropertyTIFFOrientation as String] = 1
        tiff[kCGImagePropertyTIFFSoftware as String] = "Silent Camera"
        props[kCGImagePropertyTIFFDictionary as String] = tiff

        // GPS：位置情報があれば付与
        if let loc = location {
            let c = loc.coordinate
            props[kCGImagePropertyGPSDictionary as String] = [
                kCGImagePropertyGPSLatitude as String:          abs(c.latitude),
                kCGImagePropertyGPSLatitudeRef as String:       c.latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude as String:         abs(c.longitude),
                kCGImagePropertyGPSLongitudeRef as String:      c.longitude >= 0 ? "E" : "W",
                kCGImagePropertyGPSAltitude as String:          loc.altitude,
                kCGImagePropertyGPSAltitudeRef as String:       loc.altitude < 0 ? 1 : 0,
                kCGImagePropertyGPSTimeStamp as String:         gpsTime(timestamp),
                kCGImagePropertyGPSDateStamp as String:         gpsDate(timestamp),
                kCGImagePropertyGPSHPositioningError as String: loc.horizontalAccuracy,
            ]
        }

        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    func startRecording() {
        guard !isRecording else { return }
        recordingAspectRatio = currentAspectRatio
        recordingColorStyle = currentColorStyle
        isRecordingUnsafe = true
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        // 録画開始の瞬間のデバイスの向きを動画ファイルの回転メタデータに焼き込む
        let rotationAngle = videoRotationAngle(for: currentUIRotation)
        let videoMetadata = buildMovieMetadata()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let conn = self.movieOutput.connection(with: .video),
               conn.isVideoRotationAngleSupported(rotationAngle) {
                conn.videoRotationAngle = rotationAngle
            }
            self.movieOutput.metadata = videoMetadata
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
        isRecording = true
        recordingDuration = 0
        recordingTimerTask?.cancel()
        recordingTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.recordingDuration += 1
            }
        }
    }

    /// 動画ファイルに埋め込む QuickTime メタデータを構築
    private func buildMovieMetadata() -> [AVMetadataItem] {
        let device = currentDevice
        let lensName = device?.localizedName ?? "iPhone Camera"
        let make = AVMutableMetadataItem()
        make.identifier = .quickTimeMetadataMake
        make.value = "Apple" as NSString
        make.dataType = kCMMetadataBaseDataType_UTF8 as String
        let model = AVMutableMetadataItem()
        model.identifier = .quickTimeMetadataModel
        model.value = UIDevice.current.model as NSString
        model.dataType = kCMMetadataBaseDataType_UTF8 as String
        let software = AVMutableMetadataItem()
        software.identifier = .quickTimeMetadataSoftware
        software.value = "Silent Camera" as NSString
        software.dataType = kCMMetadataBaseDataType_UTF8 as String
        // レンズ名（例：Back Triple Camera）
        let lens = AVMutableMetadataItem()
        lens.identifier = AVMetadataIdentifier(rawValue: "mdta/com.apple.quicktime.camera.lens.model")
        lens.value = lensName as NSString
        lens.dataType = kCMMetadataBaseDataType_UTF8 as String
        // 撮影日時
        let creationDate = AVMutableMetadataItem()
        creationDate.identifier = .quickTimeMetadataCreationDate
        creationDate.value = ISO8601DateFormatter().string(from: Date()) as NSString
        creationDate.dataType = kCMMetadataBaseDataType_UTF8 as String
        return [make, model, software, lens, creationDate]
    }

    /// `currentUIRotation` (0 / 90 / -90 / 180) を AVCaptureConnection.videoRotationAngle に変換
    nonisolated private func videoRotationAngle(for uiRotation: Double) -> CGFloat {
        switch uiRotation {
        case 90:   return 0
        case -90:  return 180
        case 180:  return 270
        default:   return 90
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        feedback(.recordingStop)
        isRecordingUnsafe = false
        sessionQueue.async { [weak self] in self?.movieOutput.stopRecording() }
        recordingTimerTask?.cancel()
        isRecording = false
    }

    func cancelRecording() {
        guard isRecording else { return }
        feedback(.recordingStop)
        isRecordingUnsafe = false
        discardNextRecording = true
        sessionQueue.async { [weak self] in self?.movieOutput.stopRecording() }
        recordingTimerTask?.cancel()
        isRecording = false
    }

    func setVideoQuality(_ quality: VideoQuality) {
        guard !isRecording else { return }
        videoQuality = quality
        currentVideoQuality = quality
        // フォーマットは常に最大のまま。録画ビットレートと保存時の export preset だけ更新
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let conn = self.movieOutput.connection(with: .video) {
                self.movieOutput.setOutputSettings(
                    [AVVideoCodecKey: AVVideoCodecType.hevc,
                     AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: quality.bitRate] as [String: Any]],
                    for: conn
                )
            }
        }
    }

    func switchCamera() {
        guard !isRecording else { return }
        isFrontCamera.toggle()
        let useFront = isFrontCamera

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()

            for input in self.session.inputs {
                if let di = input as? AVCaptureDeviceInput, di.device.hasMediaType(.video) {
                    self.session.removeInput(di)
                }
            }

            let position: AVCaptureDevice.Position = useFront ? .front : .back
            let types: [AVCaptureDevice.DeviceType] = useFront
                ? [.builtInWideAngleCamera]
                : [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: types, mediaType: .video, position: position)

            guard let device = discovery.devices.first,
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                Task { @MainActor [weak self] in self?.isFrontCamera = !useFront }
                return
            }

            self.session.addInput(input)
            self.currentDevice = device
            self.selectBestFormat(for: device)

            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {}

            if let conn = self.videoOutput.connection(with: .video) {
                if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
                if conn.isVideoMirroringSupported { conn.isVideoMirrored = useFront }
                if conn.isVideoStabilizationSupported {
                    conn.preferredVideoStabilizationMode = .cinematic
                }
                self.videoConnection = conn
            }

            if let conn = self.movieOutput.connection(with: .video) {
                if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
                self.movieOutput.setOutputSettings(
                    [AVVideoCodecKey: AVVideoCodecType.hevc,
                     AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: self.currentVideoQuality.bitRate] as [String: Any]],
                    for: conn
                )
            }

            if let conn = self.photoOutput.connection(with: .video) {
                if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
                if conn.isVideoMirroringSupported { conn.isVideoMirrored = useFront }
            }
            // カメラ切替後も新しいフォーマットの最大解像度に追従
            if let maxDims = device.activeFormat.supportedMaxPhotoDimensions.last {
                self.photoOutput.maxPhotoDimensions = maxDims
            }

            if #available(iOS 18.0, *), self.session.supportsControls {
                for control in self.session.controls { self.session.removeControl(control) }
                self.captureSlider = nil

                let w = self.currentWideAngleZoom
                let minUserZoom = Float(device.minAvailableVideoZoomFactor / w)
                let maxUserZoom = Float(min(device.maxAvailableVideoZoomFactor, useFront ? device.maxAvailableVideoZoomFactor : 25.0) / w)
                let slider = AVCaptureSlider("ズーム", symbolName: "plus.magnifyingglass", in: minUserZoom...maxUserZoom)
                slider.value = Float(device.videoZoomFactor / w)
                slider.setActionQueue(self.sessionQueue) { [weak self] value in
                    guard let self, let dev = self.currentDevice else { return }
                    let deviceTarget = CGFloat(value) * self.currentWideAngleZoom
                    let target = max(dev.minAvailableVideoZoomFactor, min(deviceTarget, dev.maxAvailableVideoZoomFactor))
                    do {
                        try dev.lockForConfiguration()
                        dev.videoZoomFactor = target
                        dev.unlockForConfiguration()
                    } catch {}
                    let actual = dev.videoZoomFactor
                    Task { @MainActor [weak self] in
                        self?._currentZoom = actual
                        self?.zoomFactor = actual
                    }
                }
                self.captureSlider = slider
                self.session.addControl(slider)

                let colorPicker = AVCaptureIndexPicker(
                    "色味", symbolName: "paintpalette",
                    localizedIndexTitles: ["標準", "ウォーム", "クール", "鮮やか"])
                colorPicker.setActionQueue(self.sessionQueue) { [weak self] index in
                    guard let self, !self.isRecordingUnsafe else { return }
                    self.currentColorStyle = index
                }
                self.session.addControl(colorPicker)
                self.session.setControlsDelegate(self, queue: self.sessionQueue)
            }

            self.session.commitConfiguration()
        }
    }

    private func startMotionDetection() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.3
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let acc = data?.acceleration else { return }
            let threshold = 0.5
            if abs(acc.x) > abs(acc.y) && abs(acc.x) > threshold {
                let rot = acc.x > 0 ? -90.0 : 90.0
                self.uiRotationDegrees = rot
                self.currentUIRotation = rot
            } else if abs(acc.y) > threshold {
                let rot = acc.y > 0 ? 180.0 : 0.0
                self.uiRotationDegrees = rot
                self.currentUIRotation = rot
            }
        }
    }

    func toggleStabilization() {
        let next = !isStabilizationEnabled
        isStabilizationEnabled = next
        if next {
            applyStabilizationForZoom(zoomFactor)
        } else {
            sessionQueue.async { [weak self] in
                guard let conn = self?.videoConnection, conn.isVideoStabilizationSupported else { return }
                conn.preferredVideoStabilizationMode = .off
            }
        }
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        let target = max(device.minAvailableVideoZoomFactor, min(factor, 25.0))
        applyStabilizationForZoom(target)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = min(target, device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        } catch {}
        let actual = device.videoZoomFactor
        _currentZoom = actual
        if #available(iOS 18.0, *) {
            let v = Float(actual / currentWideAngleZoom)
            sessionQueue.async { [weak self] in self?.captureSlider?.value = v }
        }
    }

    /// ズーム倍率に応じてスタビライゼーションモードを切り替える
    /// 10x超: off（cinematicExtendedはmaxAvailableVideoZoomFactorを大幅に下げるため）
    /// 2x〜10x: cinematicExtended / 2x未満: cinematic
    private func applyStabilizationForZoom(_ zoom: CGFloat) {
        guard isStabilizationEnabled else { return }
        let mode: AVCaptureVideoStabilizationMode
        if zoom >= 10.0 {
            mode = .off
        } else if zoom >= 2.0 {
            mode = .cinematicExtended
        } else {
            mode = .cinematic
        }
        sessionQueue.async { [weak self] in
            guard let conn = self?.videoConnection, conn.isVideoStabilizationSupported else { return }
            conn.preferredVideoStabilizationMode = mode
        }
    }

    func animateZoom(to target: CGFloat, duration: Double = 0.25) {
        let start = _currentZoom
        guard abs(target - start) > 0.05 else { setZoom(target); commitZoom(); return }
        let steps = 20
        let stepNanos = UInt64(duration / Double(steps) * 1_000_000_000)
        Task { @MainActor in
            self.isAnimatingZoom = true
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                self.setZoom(start + (target - start) * eased)
                try? await Task.sleep(nanoseconds: stepNanos)
            }
            self.setZoom(target)
            self.isAnimatingZoom = false
            // 終点がプリセット相当なら 1 回だけティック
            let w = self.currentWideAngleZoom
            if w > 0 {
                let userTarget = target / w
                for preset in Self.zoomPresets where abs(userTarget - preset) < 0.05 {
                    self.fireZoomTickIfAllowed()
                    break
                }
            }
            self.commitZoom()
        }
    }

    @Published var captureAspectRatio: CaptureAspectRatio = .fourThree {
        didSet { currentAspectRatio = captureAspectRatio }
    }
    @Published var minZoomFactor: CGFloat = 1.0
    /// メイン広角レンズに対応するデバイスズーム倍率（ユーザー視点の「1x」）
    @Published var wideAngleZoomFactor: CGFloat = 1.0
    @Published var uiRotationDegrees: Double = 0

    private let motionManager = CMMotionManager()
    private var recordingTimerTask: Task<Void, Never>?
    private var muteCheckTask: Task<Void, Never>?
    private var isDetectingMute = false

    var maxZoomFactor: CGFloat {
        min(currentDevice?.maxAvailableVideoZoomFactor ?? 1.0, 25.0)
    }

    private var focusResetTask: Task<Void, Never>?

    /// タップ位置（プレビューレイヤー座標系）でフォーカス・露出を合わせ、3秒後に連続AFへ戻る
    func focus(at layerPoint: CGPoint) {
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {}
        }
        focusResetTask?.cancel()
        focusResetTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { resetToContinuousAutoFocus() }
        }
    }

    private func resetToContinuousAutoFocus() {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    // MARK: - Session Setup

    private func setupSession() {
        previewLayer.session = session
        session.automaticallyConfiguresApplicationAudioSession = false
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(
            .playAndRecord,
            mode: .videoRecording,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        // 録画中もハプティック／システム音を鳴らす許可（これが無いと .playAndRecord 中は全ハプティックが抑制される）
        try? audio.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try? audio.setActive(true)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .inputPriority

            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
                mediaType: .video, position: .back)
            guard
                let device = discovery.devices.first,
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)
            self.currentDevice = device
            self.selectBestFormat(for: device)
            if let mic = AVCaptureDevice.default(for: .audio),
               let micInput = try? AVCaptureDeviceInput(device: mic),
               self.session.canAddInput(micInput) {
                self.session.addInput(micInput)
            }

            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {}

            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.setSampleBufferDelegate(self, queue: self.captureQueue)

            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            if let conn = self.videoOutput.connection(with: .video) {
                if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
                if conn.isVideoStabilizationSupported {
                    conn.preferredVideoStabilizationMode = .cinematic
                }
                self.videoConnection = conn
            }

            if self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
                if let conn = self.movieOutput.connection(with: .video) {
                    if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
                    // HEVC + 8 Mbps でファイルサイズを抑制（デフォルト 4K H.264 より大幅に小さくなる）
                    self.movieOutput.setOutputSettings(
                        [AVVideoCodecKey: AVVideoCodecType.hevc,
                         AVVideoCompressionPropertiesKey: [
                             AVVideoAverageBitRateKey: 8_000_000
                         ] as [String: Any]],
                        for: conn
                    )
                }
            }

            // フル解像度の写真を AVCapturePhotoOutput で撮影（シャッター音は delegate で破棄）
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                if let conn = self.photoOutput.connection(with: .video),
                   conn.isVideoRotationAngleSupported(90) {
                    conn.videoRotationAngle = 90
                }
                // 画質優先（48MP 等の高解像度を取得するために必要）
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                // iOS 17+: 速度優先機能を切って画質優先（24MP 取得のために必要）
                if #available(iOS 17.0, *) {
                    if self.photoOutput.isResponsiveCaptureSupported {
                        self.photoOutput.isResponsiveCaptureEnabled = false
                    }
                    if self.photoOutput.isAutoDeferredPhotoDeliverySupported {
                        self.photoOutput.isAutoDeferredPhotoDeliveryEnabled = false
                    }
                }
                // センサー最大解像度（48MP など）まで許可
                if let maxDims = device.activeFormat.supportedMaxPhotoDimensions.last {
                    self.photoOutput.maxPhotoDimensions = maxDims
                }
            }

            self.session.commitConfiguration()
            self.session.startRunning()

            if #available(iOS 18.0, *), self.session.supportsControls {
                let w = self.currentWideAngleZoom  // ユーザー向けズーム基準（広角 = 1x）
                let minUserZoom = Float(device.minAvailableVideoZoomFactor / w)
                let maxUserZoom = Float(25.0 / w)
                let slider = AVCaptureSlider("ズーム", symbolName: "plus.magnifyingglass", in: minUserZoom...maxUserZoom)
                slider.value = Float(device.videoZoomFactor / w)
                slider.setActionQueue(self.sessionQueue) { [weak self] value in
                    guard let self, let dev = self.currentDevice else { return }
                    // value はユーザー向けズーム → デバイスズームに変換
                    let deviceTarget = CGFloat(value) * self.currentWideAngleZoom
                    let target = max(dev.minAvailableVideoZoomFactor, min(deviceTarget, 25.0))
                    do {
                        try dev.lockForConfiguration()
                        dev.videoZoomFactor = min(target, dev.maxAvailableVideoZoomFactor)
                        dev.unlockForConfiguration()
                    } catch {}
                    let actual = dev.videoZoomFactor
                    Task { @MainActor [weak self] in
                        self?._currentZoom = actual
                        self?.zoomFactor = actual
                    }
                }
                self.captureSlider = slider
                self.session.addControl(slider)

                let colorPicker = AVCaptureIndexPicker(
                    "色味", symbolName: "paintpalette",
                    localizedIndexTitles: ["標準", "ウォーム", "クール", "鮮やか"])
                colorPicker.setActionQueue(self.sessionQueue) { [weak self] index in
                    guard let self, !self.isRecordingUnsafe else { return }
                    self.currentColorStyle = index
                }
                self.session.addControl(colorPicker)

                self.session.setControlsDelegate(self, queue: self.sessionQueue)
            }
        }
    }

    private func selectBestFormat(for device: AVCaptureDevice) {
        // preview / センサー出力は常にデバイス最大フォーマット
        // 写真側はフォーマットの supportedMaxPhotoDimensions を最優先、
        // 同じ写真上限なら動画側の解像度が大きいほうを選ぶ。
        let best = device.formats
            .filter { $0.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 } }
            .max { a, b in
                let photoA = a.supportedMaxPhotoDimensions.last.map { Int($0.width) * Int($0.height) } ?? 0
                let photoB = b.supportedMaxPhotoDimensions.last.map { Int($0.width) * Int($0.height) } ?? 0
                if photoA != photoB { return photoA < photoB }
                let dA = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
                let dB = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
                return Int(dA.width) * Int(dA.height) < Int(dB.width) * Int(dB.height)
            }
        guard let fmt = best, let _ = try? device.lockForConfiguration() else { return }
        device.activeFormat = fmt
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        device.unlockForConfiguration()
        let dim = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
        let minZoom = device.minAvailableVideoZoomFactor
        // switchOverVideoZoomFactors の最初の値がメイン広角レンズの開始点
        let wideZoom = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 1.0
        self.currentWideAngleZoom = wideZoom
        // 初期ズームをメイン広角（ユーザー視点 1x）に設定
        if let _ = try? device.lockForConfiguration() {
            device.videoZoomFactor = wideZoom
            device.unlockForConfiguration()
        }
        Task { @MainActor [weak self] in
            self?.captureResolution = CGSize(width: CGFloat(dim.width), height: CGFloat(dim.height))
            self?.minZoomFactor = minZoom
            self?.wideAngleZoomFactor = wideZoom
            self?._currentZoom = wideZoom
            self?.zoomFactor = wideZoom
        }

    }

    // MARK: - Photo Library

    @MainActor
    private func saveToPhotoLibrary(data: Data, metadata: CaptureMetadata) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self, status == .authorized else { return }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                request.addResource(with: .photo, data: data, options: options)
                if let loc = metadata.location { request.location = loc }
                request.creationDate = metadata.timestamp
            } completionHandler: { [weak self] success, error in
                Task { @MainActor [weak self] in
                    if success {
                        self?.savedMetadata = metadata
                        self?.fetchLatestPhoto()
                    } else if let error {
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: - HEIC Build

    /// 現在の保存品質設定に従って短辺を上限以下に縮小する。原寸で良ければそのまま返す。
    nonisolated private func downscaledIfNeeded(_ cgImage: CGImage) -> CGImage {
        let maxShort = currentVideoQuality.maxShortSide
        let w = cgImage.width
        let h = cgImage.height
        let short = min(w, h)
        guard short > maxShort else { return cgImage }
        let scale = CGFloat(maxShort) / CGFloat(short)
        let newW = max(1, Int((CGFloat(w) * scale).rounded()))
        let newH = max(1, Int((CGFloat(h) * scale).rounded()))
        guard let cs = cgImage.colorSpace,
              let ctx = CGContext(
                  data: nil, width: newW, height: newH,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: cs, bitmapInfo: cgImage.bitmapInfo.rawValue
              ) else { return cgImage }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? cgImage
    }

    nonisolated private func buildImageData(cgImage: CGImage, metadata: CaptureMetadata, orientation: Int) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else { return nil }
        var props = commonProps(metadata: metadata)
        props[kCGImageDestinationLossyCompressionQuality] = 0.95
        // EXIF/TIFF orientation：写真ビューワが向きを補正する
        props[kCGImagePropertyOrientation] = orientation
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = orientation
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// `currentUIRotation` (0 / 90 / -90 / 180) を CGImagePropertyOrientation 値に変換
    nonisolated private func exifOrientation(for uiRotation: Double) -> Int {
        switch uiRotation {
        case 180: return 3
        case 90:  return 8
        case -90: return 6
        default:  return 1
        }
    }

    nonisolated private func commonProps(metadata: CaptureMetadata) -> [CFString: Any] {
        let exposure: Double = metadata.exposureDuration == .zero ? 0
            : Double(metadata.exposureDuration.value) / Double(metadata.exposureDuration.timescale)
        var props: [CFString: Any] = [:]
        props[kCGImagePropertyExifDictionary] = [
            kCGImagePropertyExifDateTimeOriginal:  exifDate(metadata.timestamp),
            kCGImagePropertyExifDateTimeDigitized: exifDate(metadata.timestamp),
            kCGImagePropertyExifISOSpeedRatings:   [Int(metadata.iso)],
            kCGImagePropertyExifExposureTime:      exposure,
            kCGImagePropertyExifFNumber:           metadata.lensAperture,
            kCGImagePropertyExifDigitalZoomRatio:  Double(metadata.zoomFactor),
            kCGImagePropertyExifPixelXDimension:   Int(metadata.imageSize.width),
            kCGImagePropertyExifPixelYDimension:   Int(metadata.imageSize.height),
        ] as [CFString: Any]
        props[kCGImagePropertyTIFFDictionary] = [
            kCGImagePropertyTIFFMake:     "Apple",
            kCGImagePropertyTIFFModel:    metadata.deviceModel,
            kCGImagePropertyTIFFDateTime: exifDate(metadata.timestamp),
            kCGImagePropertyTIFFSoftware: "Silent Camera",
        ] as [CFString: Any]
        if let loc = metadata.location {
            let c = loc.coordinate
            props[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude:          abs(c.latitude),
                kCGImagePropertyGPSLatitudeRef:       c.latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude:         abs(c.longitude),
                kCGImagePropertyGPSLongitudeRef:      c.longitude >= 0 ? "E" : "W",
                kCGImagePropertyGPSAltitude:          loc.altitude,
                kCGImagePropertyGPSAltitudeRef:       loc.altitude < 0 ? 1 : 0,
                kCGImagePropertyGPSTimeStamp:         gpsTime(metadata.timestamp),
                kCGImagePropertyGPSDateStamp:         gpsDate(metadata.timestamp),
                kCGImagePropertyGPSHPositioningError: loc.horizontalAccuracy,
            ] as [CFString: Any]
        }
        return props
    }

    nonisolated private func exifDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"; return f.string(from: d)
    }
    nonisolated private func gpsTime(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }
    nonisolated private func gpsDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy:MM:dd"; return f.string(from: d)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // preview だけのために動画フレームを CIImage 化して Metal に渡す（写真は AVCapturePhotoOutput 側で別取得）
        let ci = applyColorStyle(CIImage(cvPixelBuffer: buf), style: currentColorStyle)
        previewView.display(ci)
    }

    nonisolated private func cropToAspectRatio(_ image: CIImage) -> CIImage {
        let ext = image.extent
        let currentWH = ext.width / ext.height
        // 入力が縦か横かで適用するアスペクト比のターゲットを切替
        let portraitTarget = currentAspectRatio.previewRatio
        let landscapeTarget: CGFloat = portraitTarget == 0 ? 1.0 : 1.0 / portraitTarget
        let targetWH = currentWH >= 1.0 ? landscapeTarget : portraitTarget
        guard abs(currentWH - targetWH) > 0.01 else { return image }
        if currentWH > targetWH {
            let newW = ext.height * targetWH
            let cropX = ext.origin.x + (ext.width - newW) / 2
            return image.cropped(to: CGRect(x: cropX, y: ext.origin.y, width: newW, height: ext.height))
        } else {
            let newH = ext.width / targetWH
            let cropY = ext.origin.y + (ext.height - newH) / 2
            return image.cropped(to: CGRect(x: ext.origin.x, y: cropY, width: ext.width, height: newH))
        }
    }


    nonisolated private func applyColorStyle(_ image: CIImage, style: Int) -> CIImage {
        switch style {
        case 1: // ウォーム
            guard let f = CIFilter(name: "CIColorMatrix") else { return image }
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 1.15, y: 0, z: 0, w: 0), forKey: "inputRVector")
            f.setValue(CIVector(x: 0, y: 1.05, z: 0, w: 0), forKey: "inputGVector")
            f.setValue(CIVector(x: 0, y: 0, z: 0.75, w: 0), forKey: "inputBVector")
            return f.outputImage ?? image
        case 2: // クール
            guard let f = CIFilter(name: "CIColorMatrix") else { return image }
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 0.82, y: 0, z: 0, w: 0), forKey: "inputRVector")
            f.setValue(CIVector(x: 0, y: 1.0,  z: 0, w: 0), forKey: "inputGVector")
            f.setValue(CIVector(x: 0, y: 0, z: 1.18, w: 0), forKey: "inputBVector")
            return f.outputImage ?? image
        case 3: // 鮮やか
            guard let f = CIFilter(name: "CIColorControls") else { return image }
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(1.4,  forKey: kCIInputSaturationKey)
            f.setValue(1.05, forKey: kCIInputContrastKey)
            return f.outputImage ?? image
        default:
            return image
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension CameraManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension CameraManager: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in self?.fetchLatestPhoto() }
    }
}

// MARK: - AVCaptureSessionControlsDelegate

@available(iOS 18.0, *)
extension CameraManager: AVCaptureSessionControlsDelegate {
    nonisolated func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {}
    nonisolated func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {}
    nonisolated func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {}
    nonisolated func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {}
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didStartRecordingTo fileURL: URL,
                                from connections: [AVCaptureConnection]) {}

    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        if discardNextRecording {
            discardNextRecording = false
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }
        guard error == nil else {
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }
        let ratio = recordingAspectRatio
        let colorStyle = recordingColorStyle
        Task { [weak self] in
            guard let self else { return }
            let saveURL = await self.cropVideo(at: outputFileURL, to: ratio, colorStyle: colorStyle)
            defer {
                try? FileManager.default.removeItem(at: outputFileURL)
                if saveURL != outputFileURL { try? FileManager.default.removeItem(at: saveURL) }
            }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { return }
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: saveURL)
            }
            await MainActor.run { [weak self] in
                self?.fetchLatestPhoto()
            }
        }
    }

    nonisolated private func cropVideo(at url: URL, to aspectRatio: CaptureAspectRatio, colorStyle: Int) async -> URL {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform),
              let duration = try? await asset.load(.duration) else { return url }

        let transformed = naturalSize.applying(transform)
        let displayW = abs(transformed.width)
        let displayH = abs(transformed.height)
        let currentRatio = displayW / displayH
        // 動画の向き（縦／横）に応じてターゲットアスペクトを切り替える
        // previewRatio は常に縦向き想定（< 1）なので、横向き動画ならその逆数を使う
        let portraitTarget = aspectRatio.previewRatio
        let landscapeTarget: CGFloat = portraitTarget == 0 ? 1.0 : 1.0 / portraitTarget
        let targetRatio = currentRatio >= 1.0 ? landscapeTarget : portraitTarget
        guard abs(currentRatio - targetRatio) > 0.02 else {
            // クロップ不要：色味と画質ダウンスケールだけ判定
            // applyColorFilter は currentVideoQuality.exportPreset を使うので、色味ありなら自動で縮小される
            if colorStyle > 0 {
                return await applyColorFilter(to: url, style: colorStyle)
            }
            // 色味なし＆4K 設定なら原寸のまま（最速）
            if currentVideoQuality == .q4K {
                return url
            }
            // 色味なし＆HD/SD 設定：export preset でダウンスケールだけ実施
            return await transcode(at: url)
        }

        let renderW: CGFloat
        let renderH: CGFloat
        let tx: CGFloat
        let ty: CGFloat
        if currentRatio > targetRatio {
            renderH = displayH
            renderW = (displayH * targetRatio).rounded()
            tx = -((displayW - renderW) / 2).rounded()
            ty = 0
        } else {
            renderW = displayW
            renderH = (displayW / targetRatio).rounded()
            tx = 0
            ty = -((displayH - renderH) / 2).rounded()
        }

        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              (try? compTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)) != nil
        else { return url }
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compAudio = composition.addMutableTrack(
               withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compAudio.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: .zero)
        }

        let videoComp = AVMutableVideoComposition()
        videoComp.renderSize = CGSize(width: renderW, height: renderH)
        videoComp.frameDuration = CMTime(value: 1, timescale: 30)

        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
        layerInstr.setTransform(
            transform.concatenating(CGAffineTransform(translationX: tx, y: ty)), at: .zero)
        instr.layerInstructions = [layerInstr]
        videoComp.instructions = [instr]

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        guard let exporter = AVAssetExportSession(
            asset: composition, presetName: currentVideoQuality.exportPreset) else { return url }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        exporter.videoComposition = videoComp
        await exporter.export()
        guard exporter.status == .completed else { return url }
        guard colorStyle > 0 else { return outputURL }
        let coloredURL = await applyColorFilter(to: outputURL, style: colorStyle)
        try? FileManager.default.removeItem(at: outputURL)
        return coloredURL
    }

    /// クロップも色味も不要だが画質設定だけ下げたい場合のシンプルな再エンコード
    nonisolated private func transcode(at url: URL) async -> URL {
        let asset = AVURLAsset(url: url)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        guard let exporter = AVAssetExportSession(
            asset: asset, presetName: currentVideoQuality.exportPreset) else { return url }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        await exporter.export()
        return exporter.status == .completed ? outputURL : url
    }

    nonisolated private func applyColorFilter(to url: URL, style: Int) async -> URL {
        let asset = AVURLAsset(url: url)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        let composition = AVVideoComposition(asset: asset) { [self] request in
            let filtered = applyColorStyle(request.sourceImage, style: style)
            request.finish(with: filtered, context: nil)
        }
        guard let exporter = AVAssetExportSession(
            asset: asset, presetName: currentVideoQuality.exportPreset) else { return url }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        exporter.videoComposition = composition
        await exporter.export()
        return exporter.status == .completed ? outputURL : url
    }
}

// MARK: - Metal Camera Preview

final class MetalCameraPreview: MTKView, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let ciCtx: CIContext
    nonisolated(unsafe) private var latestImage: CIImage?

    init() {
        let dev = MTLCreateSystemDefaultDevice()!
        commandQueue = dev.makeCommandQueue()!
        ciCtx = CIContext(mtlDevice: dev, options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.displayP3) as Any
        ])
        super.init(frame: .zero, device: dev)
        delegate = self
        isPaused = true
        enableSetNeedsDisplay = false
        framebufferOnly = false
        backgroundColor = .black
    }

    required init(coder: NSCoder) { fatalError() }

    func display(_ image: CIImage) {
        latestImage = image
        DispatchQueue.main.async { self.draw() }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let image = latestImage,
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let drawable = currentDrawable else { return }
        let size = drawableSize
        guard size.width > 0, size.height > 0 else { return }
        let scale = max(size.width / image.extent.width, size.height / image.extent.height)
        var img = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        img = img.transformed(by: CGAffineTransform(
            translationX: (size.width - img.extent.width) / 2,
            y: (size.height - img.extent.height) / 2))
        ciCtx.render(img, to: drawable.texture, commandBuffer: cmdBuf,
                    bounds: CGRect(origin: .zero, size: size),
                    colorSpace: CGColorSpaceCreateDeviceRGB())
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }
}


// MARK: - Photo Capture Delegate

/// AVCapturePhotoOutput のキャプチャイベントを受け取り、シャッター音を破棄して
/// 撮影完了時に CameraManager.processCapturedPhoto に渡す。
final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private weak var manager: CameraManager?

    init(manager: CameraManager) {
        self.manager = manager
    }

    /// シャッター音が再生される直前にシステムサウンド ID 1108 を破棄して無音化。
    func photoOutput(_ output: AVCapturePhotoOutput,
                     willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        AudioServicesDisposeSystemSoundID(1108)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil else { return }
        manager?.processCapturedPhoto(photo)
    }
}
