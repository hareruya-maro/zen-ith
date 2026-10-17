# Zen-ith 再配布・パッケージング・Sparkle 2 自動更新手順書

このドキュメントでは、macOS メニューバー常駐クリーナーアプリ **Zen-ith** をパッケージング（`.app` / `.zip` / `.dmg`）し、**GitHub Releases (`hareruya-maro/zen-ith`) ＋ Sparkle 2** で自動更新（オートアップデート）を運用する手順を解説します。

---

## 1. 配布・自動更新アーキテクチャの概要

- **配布リポジトリ**: `https://github.com/hareruya-maro/zen-ith`
- **Sparkle Feed URL (`SUFeedURL`)**:
  `https://github.com/hareruya-maro/zen-ith/releases/latest/download/appcast.xml`
- **仕組み**:
  1. GitHub Releases の最新リリースに `Zen-ith-macOS.zip`、`Zen-ith-Installer.dmg`、`appcast.xml` の3ファイルを添付して公開します。
  2. ユーザーの Mac 上で動く Zen-ith（[`SoftwareUpdaterService.swift`](../Zen-ith/Services/SoftwareUpdaterService.swift)）が `releases/latest/download/appcast.xml` を定期確認し、新バージョンがあれば Developer ID 署名と EdDSA 署名を検証した上で自動的にアプリ本体を差し替えて再起動します。
  3. まだ `SUPublicEDKey` を設定していない開発段階でも、「設定 > 今すぐアップデートを確認...」ボタンを押すと GitHub Releases API (`/repos/hareruya-maro/zen-ith/releases/latest`) を直接確認して新バージョンの有無を判定します。

---

## 2. 初回のみ必要な準備：Sparkle 2 の EdDSA 署名鍵ペア生成

Sparkle 2 で自動更新を有効にするには、初回のみ以下のコマンドで EdDSA（Ed25519）鍵ペアを生成します。

### Step 1. `generate_keys` の実行
Swift Package の解決後、`.build/SourcePackages` 内に展開された Sparkle の `generate_keys` バイナリを実行します。

```zsh
./Vendor/Sparkle/bin/generate_keys
```

- **秘密鍵**は自動的にあなたの Mac のキーチェーン（Keychain）に安全に保存されます。
- ターミナルに以下のような `SUPublicEDKey` 用の公開鍵文字列が出力されます：
  ```xml
  <key>SUPublicEDKey</key>
  <string>BASE64_ENCODED_PUBLIC_KEY_STRING==</string>
  ```

### Step 2. `Zen-ith/Info.plist` に公開鍵を設定
出力された公開鍵文字列を [`Zen-ith/Info.plist`](../Zen-ith/Info.plist) の `SUPublicEDKey` に貼り付けます。

```xml
<key>SUFeedURL</key>
<string>https://github.com/hareruya-maro/zen-ith/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>ここに公開鍵文字列を貼り付け</string>
```

---

## 3. 新バージョンのリリース手順（毎回行う手順）

新しいバージョン（例: `0.2.0`）をリリースする際は、以下の4ステップで完了します。

### Step 1. バージョン番号の更新
[`Zen-ith.xcodeproj/project.pbxproj`](../Zen-ith.xcodeproj/project.pbxproj) 内の以下の2箇所を更新します：
- `MARKETING_VERSION = 0.2.0;`（表示バージョン）
- `CURRENT_PROJECT_VERSION = 2;`（ビルド番号：前回より必ず大きい整数にする）

### Step 2. ビルド・Developer ID 署名・Apple 公証（Notarization）・`appcast.xml` の一括生成
[`scripts/package_release.sh`](../scripts/package_release.sh) を実行すると、キーチェーン内の `Developer ID Application` 証明書の自動検出、Sparkle 2 内部バイナリ（XPC / Helper）の個別署名、DMG の生成、`asc notarization submit` による **Apple 公証（Notarization）と `xcrun stapler staple`**、`appcast.xml` の生成まで全自動で完了します。

```zsh
# Releaseビルド + Developer ID署名 + Apple公証(Notarization) + Staple + ZIP/DMG/appcast.xml生成
./scripts/package_release.sh
```

> **💡 補足**: すでに Release ビルド済みのバイナリに対して署名・公証・パッケージングのみを再実行したい場合は `./scripts/package_release.sh --skip-build` が利用できます。

スクリプト完了後、`dist/` に以下の公証（Staple）済みファイルが生成されます：
- `dist/Zen-ith.app`（Developer ID 署名 ＋ Notarization Staple 済）
- `dist/Zen-ith-macOS.zip`（Sparkle 自動更新用アーカイブ・Staple 済 `.app` 収録）
- `dist/Zen-ith-Installer.dmg`（新規インストール用ディスクイメージ・Staple 済）
- `dist/appcast.xml`（EdDSA 署名済み Sparkle 更新フィード）

### Step 4. GitHub Releases (`hareruya-maro/zen-ith`) へ公開
GitHub CLI (`gh`) を使うと、1コマンドでリリース作成と3ファイルのアップロードが完了します。

```zsh
gh release create v0.2.0 \
  dist/Zen-ith-Installer.dmg \
  dist/Zen-ith-macOS.zip \
  dist/appcast.xml \
  --repo hareruya-maro/zen-ith \
  --title "Zen-ith v0.2.0" \
  --generate-notes
```

これで、既に Zen-ith を利用しているユーザーの環境にも Sparkle 2 経由で `v0.2.0` のアップデートが配信されます。
