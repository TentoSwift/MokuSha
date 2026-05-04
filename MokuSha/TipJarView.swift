//
//  TipJarView.swift
//  Silent Camera
//
//  開発者へのチップ送信画面（IAP）
//

import SwiftUI
import StoreKit

struct TipJarView: View {
    @StateObject private var manager = TipJarManager()
    @Environment(\.dismiss) private var dismiss
    @State private var thanksOpacity: Double = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 32)

                    // ヘッダー
                    VStack(spacing: 16) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 64, weight: .regular))
                            .foregroundStyle(.pink)
                            .symbolEffect(.bounce, value: manager.purchaseState == .success)

                        Text("開発者を応援")
                            .font(.system(size: 28, weight: .bold))

                        Text("チップによる支援は完全に任意で、機能は変わりません。")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.bottom, 32)

                    // チップ選択
                    Group {
                        switch manager.purchaseState {
                        case .loading:
                            ProgressView().padding(.vertical, 40)
                        default:
                            if manager.products.isEmpty {
                                Text("商品を読み込んでいます…")
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 40)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(manager.products, id: \.id) { product in
                                        TipButton(product: product, manager: manager)
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }

                    Spacer()

                    // ステータス
                    if manager.purchaseState == .success {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.green)
                            Text("ありがとうございます！")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .opacity(thanksOpacity)
                        .onAppear {
                            withAnimation(.easeIn(duration: 0.3)) { thanksOpacity = 1 }
                        }
                    } else if case .failed(let message) = manager.purchaseState {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 24)
                            .multilineTextAlignment(.center)
                    }

                    Spacer(minLength: 24)
                }
            }
            .navigationTitle("チップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .task {
            if manager.products.isEmpty {
                await manager.loadProducts()
            }
        }
    }
}

private struct TipButton: View {
    let product: Product
    let manager: TipJarManager

    var body: some View {
        Button {
            Task { await manager.purchase(product) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: emoji(for: product.id))
                    .font(.system(size: 20))
                    .foregroundStyle(.pink)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(manager.purchaseState == .purchasing)
    }

    private func emoji(for productID: String) -> String {
        if productID.contains("small")  { return "cup.and.saucer.fill" }
        if productID.contains("medium") { return "fork.knife" }
        return "heart.fill"
    }
}

#Preview {
    TipJarView()
}
