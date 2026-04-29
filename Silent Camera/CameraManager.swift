import AVFoundation
import SwiftUI
import CoreLocation
import CoreMotion
import MetalKit
import Photos
import UIKit
import UniformTypeIdentifiers
internal import Combine

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

    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let captureQueue = DispatchQueue(label: "camera.capture")
    private let locationManager = CLLocationManager()

    let previewView = MetalCameraPreview()

    nonisolated(unsafe) private var burstRemaining = 0
    nonisolated(unsafe) private var burstBestCG: CGImage? = nil
    nonisolated(unsafe) private var burstBestScore: CGFloat = -1
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

    private let notificationFeedback = UINotificationFeedbackGenerator()

    func successFeedback() {
        notificationFeedback.notificationOccurred(.success)
    }

    private var _currentZoom: CGFloat = 1.0

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
    }

    func stopSession() {
        if isRecording { stopRecording() }
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
        burstBestCG = nil
        burstBestScore = -1
        burstRemaining = min(20, max(4, Int(zoomFactor * 3)))
    }

    func startRecording() {
        guard !isRecording else { return }
        recordingAspectRatio = currentAspectRatio
        recordingColorStyle = currentColorStyle
        isRecordingUnsafe = true
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        sessionQueue.async { [weak self] in
            guard let self else { return }
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

    func stopRecording() {
        guard isRecording else { return }
        isRecordingUnsafe = false
        sessionQueue.async { [weak self] in self?.movieOutput.stopRecording() }
        recordingTimerTask?.cancel()
        isRecording = false
    }

    func cancelRecording() {
        guard isRecording else { return }
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
        guard let device = currentDevice else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.selectBestFormat(for: device)
            if let conn = self.movieOutput.connection(with: .video) {
                self.movieOutput.setOutputSettings(
                    [AVVideoCodecKey: AVVideoCodecType.hevc,
                     AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: quality.bitRate] as [String: Any]],
                    for: conn
                )
            }
            self.session.commitConfiguration()
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
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                self.setZoom(start + (target - start) * eased)
                try? await Task.sleep(nanoseconds: stepNanos)
            }
            self.setZoom(target)
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
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord,
            mode: .videoRecording,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)

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
        let maxShort = currentVideoQuality.maxShortSide
        let best = device.formats
            .filter {
                let dim = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                let short = Int(min(dim.width, dim.height))
                return short <= maxShort &&
                       $0.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
            }
            .max {
                let dA = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                let dB = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
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

    // MARK: - Capture Processing

    nonisolated private func processFrame(_ cgImage: CGImage) {
        let timestamp = Date()
        let zoom = currentDevice?.videoZoomFactor ?? 1.0
        let effectiveFOV = (currentDevice?.activeFormat.videoFieldOfView ?? 0) / Float(zoom)

        let stabilizationLabel: String
        switch videoConnection?.activeVideoStabilizationMode {
        case .standard:          stabilizationLabel = "スタンダード"
        case .cinematic:         stabilizationLabel = "シネマティック"
        case .cinematicExtended: stabilizationLabel = "シネマティック拡張"
        case .previewOptimized:  stabilizationLabel = "プレビュー最適化"
        default:                 stabilizationLabel = "オフ"
        }

        let metadata = CaptureMetadata(
            timestamp: timestamp,
            location: currentLocation,
            iso: currentDevice?.iso ?? 0,
            exposureDuration: currentDevice?.exposureDuration ?? .zero,
            lensAperture: currentDevice?.lensAperture ?? 0,
            zoomFactor: zoom,
            fieldOfView: effectiveFOV,
            lensType: "広角",
            deviceModel: UIDevice.current.model,
            imageSize: CGSize(width: cgImage.width, height: cgImage.height),
            stabilizationMode: stabilizationLabel
        )

        guard let imageData = buildImageData(cgImage: cgImage, metadata: metadata) else { return }

        Task { @MainActor [weak self] in
            self?.saveToPhotoLibrary(data: imageData, metadata: metadata)
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

    nonisolated private func buildImageData(cgImage: CGImage, metadata: CaptureMetadata) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else { return nil }
        var props = commonProps(metadata: metadata)
        props[kCGImageDestinationLossyCompressionQuality] = 0.95
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
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
        let ci = applyColorStyle(CIImage(cvPixelBuffer: buf), style: currentColorStyle)
        previewView.display(ci)
        guard burstRemaining > 0 else { return }
        burstRemaining -= 1
        let score = sharpnessScore(ci)
        if score > burstBestScore {
            let radians = CGFloat(currentUIRotation * .pi / 180)
            var saveCI = ci
            if radians != 0 {
                var rotated = ci.transformed(by: CGAffineTransform(rotationAngle: radians))
                let tx = -rotated.extent.origin.x
                let ty = -rotated.extent.origin.y
                rotated = rotated.transformed(by: CGAffineTransform(translationX: tx, y: ty))
                saveCI = rotated
            }
            let cropped = cropToAspectRatio(saveCI)
            burstBestCG = ciContext.createCGImage(cropped, from: cropped.extent)
            burstBestScore = score
        }
        if burstRemaining == 0, let bestCG = burstBestCG {
            processFrame(bestCG)
            burstBestCG = nil
        }
    }

    nonisolated private func cropToAspectRatio(_ image: CIImage) -> CIImage {
        let ext = image.extent
        let currentWH = ext.width / ext.height
        let targetWH = currentAspectRatio.previewRatio
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

    /// Laplacian variance を使った鮮鋭度スコア（高いほどシャープ）
    nonisolated private func sharpnessScore(_ image: CIImage) -> CGFloat {
        let scale = 100.0 / max(image.extent.width, 1)
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let weights = CIVector(values: [0, -1, 0, -1, 4, -1, 0, -1, 0], count: 9)
        guard let lap = CIFilter(name: "CIConvolution3X3",
                                  parameters: [kCIInputImageKey: small,
                                               "inputWeights": weights,
                                               "inputBias": 0.0])?.outputImage,
              let avg = CIFilter(name: "CIAreaAverage",
                                  parameters: [kCIInputImageKey: lap,
                                               kCIInputExtentKey: CIVector(cgRect: lap.extent)])?.outputImage
        else { return 0 }
        var pixel = [Float](repeating: 0, count: 4)
        ciContext.render(avg, toBitmap: &pixel, rowBytes: 16,
                         bounds: CGRect(x: avg.extent.minX, y: avg.extent.minY, width: 1, height: 1),
                         format: .RGBAf, colorSpace: nil)
        return CGFloat(pixel[0] + pixel[1] + pixel[2])
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
        let targetRatio = aspectRatio.previewRatio  // width/height
        let currentRatio = displayW / displayH
        guard abs(currentRatio - targetRatio) > 0.02 else {
            guard colorStyle > 0 else { return url }
            return await applyColorFilter(to: url, style: colorStyle)
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
