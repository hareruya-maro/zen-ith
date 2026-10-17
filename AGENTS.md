# AGENTS.md — Zen-ith リポジトリ開発ガイドライン

このドキュメントは、本リポジトリ（**Zen-ith**）でコード変更・機能追加・修正を行う AI エージェント向けの必須ルールを定義します。

---

## 1. ドキュメント同期ルール（必須）

- **機能の追加・変更・削除を行った際は、必ず [`README.md`](README.md) を最新の状態に更新してください。**
  - 新しいスキャン対象カテゴリ・キャッシュパスを追加した場合は、`README.md` の「✨ 特徴 (Features)」および「📂 スキャン対象カテゴリ一覧」テーブルに反映すること。
  - UI 操作・フィルタ・クリーンアップ方式・設定項目などを追加・変更した場合は、`README.md` の機能説明を更新すること。
  - ビルド手順・配布手順・自動更新（Sparkle 2）に関する変更を行った場合は、[`README.md`](README.md) と [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) の両方を更新すること。

---

## 2. 言語・コミュニケーション規約

- チャットでの回答、実装計画（Plan）、タスクリスト（Tasks）はすべて **日本語** で作成してください。
- Git のコミットメッセージも **日本語** で記述してください。

---

## 3. ビルド・テスト検証ルール

コードを変更した際は、完了報告の前に必ずビルドと単体テストが通ることを確認してください。

```zsh
xcodebuild -project Zen-ith.xcodeproj \
  -scheme Zen-ith \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  OTHER_SWIFT_FLAGS="-disable-sandbox" \
  build-for-testing && \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xctest \
  .build/DerivedData/Build/Products/Debug/Zen-ith.app/Contents/PlugIns/Zen-ithTests.xctest
```
