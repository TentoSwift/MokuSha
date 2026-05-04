import SwiftUI
import AVFoundation
internal import _LocationEssentials

// MARK: - Metadata View

struct MetadataView: View {
    let metadata: CameraManager.CaptureMetadata
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("撮影情報") {
                    row("日時",       value: formatDate(metadata.timestamp))
                    row("解像度",     value: "\(Int(metadata.imageSize.width)) × \(Int(metadata.imageSize.height))")
                    row("フォーマット", value: "HEIC")
                    row("デバイス",   value: metadata.deviceModel)
                }
                Section("レンズ") {
                    row("種類",   value: metadata.lensType)
                    row("ズーム", value: String(format: "%.2fx", metadata.zoomFactor))
                    row("画角",   value: String(format: "%.1f°", metadata.fieldOfView))
                    row("絞り",   value: String(format: "f/%.1f", metadata.lensAperture))
                }
                Section("露出") {
                    row("ISO",              value: String(format: "%.0f", metadata.iso))
                    row("シャッタースピード", value: formatExposure(metadata.exposureDuration))
                }
                Section("手ぶれ補正") {
                    row("モード", value: metadata.stabilizationMode)
                }
                if let location = metadata.location {
                    Section("GPS") {
                        row("緯度", value: String(format: "%.6f°", location.coordinate.latitude))
                        row("経度", value: String(format: "%.6f°", location.coordinate.longitude))
                        row("高度", value: String(format: "%.1f m", location.altitude))
                        row("精度", value: String(format: "±%.0f m", location.horizontalAccuracy))
                    }
                } else {
                    Section("GPS") {
                        Text("位置情報なし").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("メタデータ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return f.string(from: date)
    }

    private func formatExposure(_ time: CMTime) -> String {
        guard time.timescale > 0 else { return "—" }
        let seconds = Double(time.value) / Double(time.timescale)
        if seconds >= 1 { return String(format: "%.1f s", seconds) }
        return "1/\(Int(1.0 / seconds)) s"
    }
}
