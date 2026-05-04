//
//  TipJarManager.swift
//  Silent Camera
//
//  StoreKit 2 を使った開発者チップ（消費型 IAP）
//  App Store Connect で以下の Product ID を消費型で登録：
//    - com.tento.MokuSha.tip.small  (¥120)
//    - com.tento.MokuSha.tip.medium (¥480)
//

import Foundation
import StoreKit
internal import Combine

@MainActor
final class TipJarManager: ObservableObject {
    @Published var products: [Product] = []
    @Published var purchaseState: PurchaseState = .idle

    enum PurchaseState: Equatable {
        case idle
        case loading
        case purchasing
        case success
        case failed(String)
    }

    static let productIDs: [String] = [
        "com.tento.MokuSha.tip.small",
        "com.tento.MokuSha.tip.medium",
    ]

    func loadProducts() async {
        purchaseState = .loading
        do {
            let storeProducts = try await Product.products(for: Self.productIDs)
            // 価格の安い順
            products = storeProducts.sorted { $0.price < $1.price }
            purchaseState = .idle
        } catch {
            purchaseState = .failed("商品情報の取得に失敗しました：\(error.localizedDescription)")
        }
    }

    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    // 消費型 IAP は finish() で完了
                    await transaction.finish()
                    purchaseState = .success
                case .unverified:
                    purchaseState = .failed("購入の検証に失敗しました")
                }
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }
}
