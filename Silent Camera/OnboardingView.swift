//
//  OnboardingView.swift
//  Silent Camera
//
//  Apple 純正アプリ（ヘルスケア／フィットネス／カメラ／マップなど）に倣った
//  ウェルカム → 機能紹介 → 続けるボタン、という標準的なオンボーディング。
//

import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void

    @State private var appearOffset: CGFloat = 24
    @State private var appearOpacity: Double = 0

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 60)

                // ヘッダー
                VStack(spacing: 16) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse, options: .repeat(1))

                    VStack(spacing: 4) {
                        Text("ようこそ")
                            .font(.system(size: 38, weight: .bold))
                        Text("Silent Camera へ")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(.tint)
                    }
                    .multilineTextAlignment(.center)
                }
                .padding(.bottom, 60)

                // 機能リスト
                VStack(alignment: .leading, spacing: 28) {
                    FeatureRow(
                        icon: "wand.and.stars",
                        tint: .blue,
                        title: "ベストフレーム抽出",
                        description: "連写したフレームから最も鮮明な 1 枚を自動で選び、HEIC で保存します。"
                    )
                    FeatureRow(
                        icon: "slider.horizontal.3",
                        tint: .orange,
                        title: "プロ仕様のコントロール",
                        description: "ズーム、焦点、露出、色味、アスペクト比、画質を自在に切り替え。"
                    )
                    FeatureRow(
                        icon: "video.fill",
                        tint: .red,
                        title: "高品質ビデオ録画",
                        description: "HEVC 4K まで対応。シャッター長押しまたはカメラコントロールで開始。"
                    )
                    FeatureRow(
                        icon: "lock.shield.fill",
                        tint: .green,
                        title: "プライバシー尊重",
                        description: "撮影データはすべて端末内で処理され、外部に送信されません。"
                    )
                }
                .padding(.horizontal, 32)

                Spacer()

                // フッター（プライバシー注釈 + Continue）
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("位置情報・写真ライブラリへのアクセスを後ほど許可していただきます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 32)

                    Button(action: onContinue) {
                        Text("続ける")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .foregroundStyle(.white)
                            .background(.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
                }
            }
            .opacity(appearOpacity)
            .offset(y: appearOffset)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    appearOpacity = 1
                    appearOffset = 0
                }
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let tint: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    OnboardingView(onContinue: {})
}
