import SwiftUI
import AVKit
import AVFoundation

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    let previewView: MetalCameraPreview
    let onCameraControl: (AVCaptureEventPhase) -> Void

    func makeUIView(context: Context) -> PreviewContainerView {
        PreviewContainerView(previewLayer: previewLayer, previewView: previewView, onCameraControl: onCameraControl)
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {}

    class PreviewContainerView: UIView {
        private let hiddenLayer: AVCaptureVideoPreviewLayer
        private let metalView: MetalCameraPreview
        private let onCapture: (AVCaptureEventPhase) -> Void
        private var captureInteraction: AVCaptureEventInteraction?

        init(previewLayer: AVCaptureVideoPreviewLayer, previewView: MetalCameraPreview, onCameraControl: @escaping (AVCaptureEventPhase) -> Void) {
            self.hiddenLayer = previewLayer
            self.metalView = previewView
            self.onCapture = onCameraControl
            super.init(frame: .zero)
            backgroundColor = .black
            metalView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(metalView)
            NSLayoutConstraint.activate([
                metalView.topAnchor.constraint(equalTo: topAnchor),
                metalView.bottomAnchor.constraint(equalTo: bottomAnchor),
                metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
                metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            layer.addSublayer(hiddenLayer)
            hiddenLayer.opacity = 0
            let interaction = AVCaptureEventInteraction { [weak self] event in
                self?.onCapture(event.phase)
            }
            addInteraction(interaction)
            captureInteraction = interaction
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hiddenLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
