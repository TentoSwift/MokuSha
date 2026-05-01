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
                            Text("Silent Camera へ")
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
                            tint: .yellow,
                            title: "完全無音シャッター",
                            description: "シャッター音を鳴らさずに写真撮影。寝ている赤ちゃん、ペット、静かな場所でも気を遣わずに撮れます。",
                            iconWidth: featureIconWidth
                        )
                        FeatureRow(
                            icon: "speaker.wave.2.fill",
                            tint: .blue,
                            title: "音あり / 無音をワンタップで切替",
                            description: "通常のシャッター音で撮影したいときは画面上部のボタンで切替。シーンに合わせて使い分けできます。",
                            iconWidth: featureIconWidth
                        )
                        FeatureRow(
                            icon: "camera.aperture",
                            tint: .orange,
                            title: "高解像度な写真",
                            description: "センサーのフル解像度で HEIC 保存。レンズ情報・GPS・絞り・ISO などの EXIF メタデータも自動で記録します。",
                            iconWidth: featureIconWidth
                        )
                        FeatureRow(
                            icon: "video.fill",
                            tint: .red,
                            title: "HEVC 動画録画",
                            description: "シャッター長押しで録画開始、右スライドでハンズフリーロック。色味・アスペクト比の設定もそのまま反映。",
                            iconWidth: featureIconWidth
                        )
                        FeatureRow(
                            icon: "iphone.gen3",
                            tint: .purple,
                            title: "カメラコントロール対応",
                            description: "iPhone 16 のカメラコントロールから起動 → スライドでズーム → 押し込みで撮影。長押しすれば動画録画も開始できます。",
                            iconWidth: featureIconWidth
                        )
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .opacity(appearOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { appearOpacity = 1 }
            }
        }
        // フッター（プライバシー注釈 + 続けるボタン）を画面下に固定
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("カメラ・マイク・写真ライブラリ・位置情報へのアクセスをこの後で許可してください。撮影データは端末内で処理され、外部に送信されません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)

                Button(action: onContinue) {
                    Text("続ける")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            }
            .padding(.top, 12)
            .background(.bar)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let tint: Color
    let title: String
    let description: String
    let iconWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
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
