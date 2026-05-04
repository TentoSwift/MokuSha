//
//  OnboardingView.swift
//  Silent Camera
//
//  Apple 純正アプリ（ヘルスケア／フィットネス／カメラ／マップなど）に倣った
//  ウェルカム → 機能紹介 → 続けるボタン、という標準的なオンボーディング。
//  Dynamic Type / アクセシビリティサイズに対応し、内容が画面外に出ればスクロール。
//

import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void

    // Dynamic Type で拡大されるアイコン（ヘッダーのアパーチャ）
    @ScaledMetric(relativeTo: .largeTitle) private var headerIconSize: CGFloat = 60
    // FeatureRow のアイコン枠サイズ
    @ScaledMetric(relativeTo: .title2) private var featureIconWidth: CGFloat = 38

    @State private var appearOpacity: Double = 0

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // ヘッダー
                    VStack(spacing: 12) {
                        Image(systemName: "camera.aperture")
                            .font(.system(size: headerIconSize, weight: .light))
                            .foregroundStyle(.tint)
                            .symbolEffect(.pulse, options: .repeat(1))

                        VStack(spacing: 4) {
                            Text("ようこそ")
                                .font(.largeTitle.weight(.bold))
                            Text("MokuSha へ")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(.tint)
                        }
                        .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 24)

                    // 機能リスト
                    VStack(alignment: .leading, spacing: 22) {
                        FeatureRow(
                            icon: "speaker.slash.fill",
                            title: "完全無音シャッター",
                            description: "シャッター音を鳴らさずに写真撮影。寝ている赤ちゃん、ペット、静かな場所でも気を遣わずに撮れます。",
                            iconWidth: featureIconWidth
                        )
                        FeatureRow(
                            icon: "speaker.wave.2.fill",
                            title: "音あり / 無音をワンタップで切替",
                            description: "通常のシャッター音で撮影したいときは画面上部のボタンで切替。シーンに合わせて使い分けできます。",
                            iconWidth: featureIconWidth
                        )
                        
                        FeatureCustomSymbolRow(
                            icon: "iphone.camera.button",
                            title: "カメラコントロールボタン対応",
                            description: "カメラコントロールボタンから起動しスライドでズームしたり、押し込みで撮影したりすることができます。長押しすれば動画録画も開始できます。",
                            iconWidth: featureIconWidth
                        )
                        
                        FeatureRow(
                            icon: "video.fill",
                            title: "動画録画",
                            description: "シャッター長押しで録画開始、右スライドでハンズフリーロック。",
                            iconWidth: featureIconWidth
                        )
                        HStack(spacing: 8) {
                            Image(systemName: "hand.raised.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("カメラ・マイク・写真ライブラリ・位置情報へのアクセスをこの後で許可してください。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            // 上下端を gradient mask でフェードアウト
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.06),
                        .init(color: .black, location: 0.94),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(appearOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { appearOpacity = 1 }
            }
        }
        // フッター（プライバシー注釈 + 続けるボタン）を画面下に固定
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button(action: onContinue) {
                    Text("はじめる")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white.opacity(0.7))
                        .brightness(0.1)
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let iconWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FeatureCustomSymbolRow: View {
    let icon: String
    let title: String
    let description: String
    let iconWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingView(onContinue: {})
}

#Preview("Accessibility XXXL") {
    OnboardingView(onContinue: {})
        .environment(\.dynamicTypeSize, .accessibility3)
}
