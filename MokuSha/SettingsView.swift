//
//  SettingsView.swift
//  Silent Camera
//
//  撮影アシスト・触覚フィードバック・チップ・アプリ情報など、
//  撮影中ではない設定をまとめる画面。
//

import SwiftUI
import UIKit

/// ⚠️ 開発者の連絡先メールアドレス。実運用前に必ず置き換えること。
private let developerSupportEmail = "support@mokusha.app"

/// App Store のアプリ ID（公開時に決定）。レビュー誘導 URL に使う。
/// ID 未取得時はレビューボタンは表示しない。
private let appStoreAppID: String? = nil  // 例："1234567890"

struct SettingsView: View {
    @AppStorage("showCompositionGuides") private var showCompositionGuides = false
    @AppStorage("showHorizonLevel") private var showHorizonLevel = false
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var showTipJar = false
    @State private var showMailUnavailableAlert = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $showCompositionGuides) {
                        Label {
                            Text("グリッド")
                        } icon: {
                            SettingsIcon(systemName: "rectangle.split.3x3", background: .yellow)
                        }
                    }
                    .tint(.accent)

                    Toggle(isOn: $showHorizonLevel) {
                        Label {
                            Text("水平")
                        } icon: {
                            SettingsIcon(systemName: "level.fill", background: .teal)
                        }
                    }
                    .tint(.accent)
                } header: {
                    Text("撮影アシスト")
                }

                Section {
                    Toggle(isOn: $hapticFeedbackEnabled) {
                        Label {
                            Text("触覚フィードバック")
                        } icon: {
                            SettingsIcon(systemName: "iphone.gen3.radiowaves.left.and.right", background: .purple)
                        }
                    }
                    .tint(.accent)
                } header: {
                    Text("フィードバック")
                }

                Section {
                    Button(action: sendFeedback) {
                        Label {
                                Text("フィードバックを送る")
                                    .foregroundStyle(.primary)
                        } icon: {
                            SettingsIcon(systemName: "envelope.fill", background: .blue)
                        }
                    }

                    if let reviewURL = appStoreReviewURL {
                        Link(destination: reviewURL) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("App Store でレビュー")
                                        .foregroundStyle(.primary)
                                    Text("☆ で応援していただけると嬉しいです")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                SettingsIcon(systemName: "star.fill", background: .yellow)
                            }
                        }
                    }
                } header: {
                    Text("サポート")
                }

                Section {
                    Button {
                        showTipJar = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("開発者にチップを送る")
                                    .foregroundStyle(.primary)
                                Text("MokuSha の開発を応援")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            SettingsIcon(systemName: "heart.fill", background: .pink)
                        }
                    }
                } header: {
                    Text("開発者を応援")
                }

                Section {
                    Button(action: openSystemSettings) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("iPhone のシステム設定を開く")
                                    .foregroundStyle(.primary)
                                Text("カメラ・マイク・写真ライブラリ等の権限を変更")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            SettingsIcon(systemName: "gear", background: .gray)
                        }
                    }
                } header: {
                    Text("権限")
                }

                Section {
                    LabeledContent("バージョン", value: appVersion)

                    Button {
                        // オンボーディングを再表示するためフラグを倒し、
                        // 設定画面を閉じると WindowGroup の分岐でオンボーディング画面が表示される
                        hasCompletedOnboarding = false
                        dismiss()
                    } label: {
                        Label {
                            Text("オンボーディングをもう一度見る")
                                .foregroundStyle(.primary)
                        } icon: {
                            SettingsIcon(systemName: "info.circle.fill", background: .gray)
                        }
                    }
                } header: {
                    Text("アプリ情報")
                } footer: {
                    Text("MokuSha は完全無料・広告なしで提供されています。")
                        .font(.caption2)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .accessibilityLabel("設定を閉じる")
                }
            }
            .sheet(isPresented: $showTipJar) {
                TipJarView()
            }
            .alert("メールアプリが利用できません", isPresented: $showMailUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("メールアプリが設定されていません。\(developerSupportEmail) まで直接メールをお送りください。")
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    /// iOS の「設定 > MokuSha」を直接開く
    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// `mailto:` で開発者宛のメール下書きを起動する。本文にデバイス情報を自動付与。
    private func sendFeedback() {
        let subject = "MokuSha フィードバック"
        let body = """


        ---
        ↑ ここから上にご意見をご記入ください ↑

        アプリバージョン: \(appVersion)
        iOS: \(UIDevice.current.systemVersion)
        端末: \(UIDevice.current.model)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = developerSupportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        guard let url = components.url else {
            showMailUnavailableAlert = true
            return
        }
        UIApplication.shared.open(url) { success in
            if !success {
                showMailUnavailableAlert = true
            }
        }
    }

    /// App Store レビューページへのディープリンク。`appStoreAppID` が未設定なら nil。
    private var appStoreReviewURL: URL? {
        guard let id = appStoreAppID else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }
}

/// iOS のシステム設定アプリの行アイコンを模した、角丸の色付き背景に白いシンボルを乗せた View。
/// `Label` の `icon:` ブロックに渡して使う。
private struct SettingsIcon: View {
    let systemName: String
    let background: Color

    /// アイコン枠の固定サイズ（pt）。Dynamic Type / アクセシビリティサイズが大きくても変わらない。
    let size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(background.gradient)
                .frame(width: size, height: size)
                // 左上と右下のエッジを白く光らせ、ガラス質感のハイライトを与える
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.5),  // 左上
                                    .white.opacity(0.0),
                                    .white.opacity(0.0),
                                    .white.opacity(0.4), // 右下
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.55
                        )
                        .frame(width: size, height: size)
                        .brightness(0.01)
                }
            Image(systemName: systemName)
                .resizable()
                .scaledToFit()
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: size * 0.7, height: size * 0.7)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    SettingsView()
}
