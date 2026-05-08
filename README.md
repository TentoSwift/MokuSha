# MokuSha

シャッター音の「あり」「なし」をワンタップで切り替えできる、シンプルな iPhone 用カメラアプリです。

[App Store からダウンロード](https://apps.apple.com/jp/app/mokusha/id6766134966)

## 特徴

- **シャッター音の切り替え**：シーンに合わせて音のあり／なしをワンタップで変更
- **キャプチャ拡張**：ロック画面のカメラコントロールから起動
- **写真ライブラリ**：撮影した写真をアプリ内で確認
- **メタデータ表示**：撮影情報を確認可能
- **オンボーディング**：初回起動時のガイド
- **アシスティブアクセス対応**：簡単操作モードでも利用可能
- **チップ（投げ銭）機能**：開発支援用の課金

## 使い方

寝ている赤ちゃんを起こしたくない時、警戒心の強いペットを驚かせたくない時、図書館や美術館など静かな場所で撮影したい時に最適です。

## アクセシビリティ

- **視差効果を減らす**: アニメーションを減らす。
- **アシスティブアクセス**: 写真を撮る、動画を撮るを選んでから撮影画面に遷移することで認知支援が必要な方も使いやす区設計しました。

## 動作環境

- iOS 18.0以降

## プロジェクト構成

```
MokuSha/
├── MokuSha/                       # メインアプリ
│   ├── MokuShaApp.swift           # エントリーポイント
│   ├── ContentView.swift          # メイン画面
│   ├── CameraManager.swift        # カメラ制御
│   ├── CameraPreviewView.swift    # プレビュー
│   ├── CaptureIntent.swift        # アクションボタン Intent
│   ├── PhotoLibraryView.swift     # 写真ライブラリ
│   ├── SettingsView.swift         # 設定
│   ├── OnboardingView.swift       # オンボーディング
│   ├── TipJarManager.swift        # チップ機能
│   └── AssistiveAccessContentView.swift
├── MokuSha Capture Extension/     # カメラコントロール拡張
└── MokuSha.xcodeproj
```

## ライセンス

© 2026 Tento Ishino. All rights reserved.
