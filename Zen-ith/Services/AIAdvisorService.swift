import Foundation

nonisolated enum AIAdvisorService {
    // MARK: - 1. 即時スマート診断（0msでフォルダ実態と知識ベースから解説を生成）

    static func generateInstantAnalysis(for item: ScanItem) -> AIItemAnalysis {
        let path = item.url.path
        let lowerPath = path.lowercased()
        let days = item.ageInDays()
        let details = inspectFilesystemContext(for: item)

        // 1. ダウンロード整理カテゴリ
        if item.category == .downloads {
            switch item.smartBadge {
            case .installedApp(let appName):
                return AIItemAnalysis(
                    safetyLevel: .safe,
                    whatIsThis: "アプリケーション「\(appName)」のインストーラー / ディスクイメージです。",
                    impactIfDeleted: "すでに /Applications に本体がインストールされているため、削除してもアプリの動作には一切影響しません。",
                    howToRestore: "万が一再インストールが必要になった場合は公式サイトから再ダウンロード、またはゴミ箱から戻せます。",
                    detectedDetails: details,
                    sourceLabel: "スマート解析"
                )
            case .extractedArchive(let folderName):
                return AIItemAnalysis(
                    safetyLevel: .safe,
                    whatIsThis: "展開（解凍）済みの圧縮アーカイブファイルです。",
                    impactIfDeleted: "同じフォルダ内に展開後の「\(folderName)/」が存在するため、元アーカイブを消しても展開済みファイルはそのまま残ります。",
                    howToRestore: "ゴミ箱移動モードならゴミ箱から復元可能です。",
                    detectedDetails: details,
                    sourceLabel: "スマート解析"
                )
            case .exactDuplicate(let originalName):
                return AIItemAnalysis(
                    safetyLevel: .safe,
                    whatIsThis: "「\(originalName)」とバイトサイズ・SHA-256ハッシュが100%完全一致する重複ファイルです。",
                    impactIfDeleted: "オリジナルの「\(originalName)」は保護されて残るため、このコピーを消してもデータは一切失われません。",
                    howToRestore: "同一フォルダ内の「\(originalName)」がそのまま利用できます。",
                    detectedDetails: details,
                    sourceLabel: "スマート解析"
                )
            default:
                return AIItemAnalysis(
                    safetyLevel: .recreatable,
                    whatIsThis: "ダウンロードフォルダ内に\(days)日間放置されているインストーラーまたはアーカイブです。",
                    impactIfDeleted: "現在使用していなければ削除して問題ありません（ハイブリッド設定ではゴミ箱へ移動します）。",
                    howToRestore: "必要な場合はFinderのゴミ箱から「戻す」で即座に復元できます。",
                    detectedDetails: details,
                    sourceLabel: "スマート解析"
                )
            }
        }

        // 2. Docker カテゴリ
        if case .dockerPrune(let resourceType) = item.targetKind {
            switch resourceType {
            case .images:
                return AIItemAnalysis(
                    safetyLevel: .recreatable,
                    whatIsThis: "どのコンテナからも参照されていない未使用のDockerイメージです。",
                    impactIfDeleted: "稼働中のコンテナには影響しません。次回同じイメージを使う際に `docker pull` または再ビルドが走ります。",
                    howToRestore: "`docker pull <イメージ名>` または `docker compose build` で再取得できます。",
                    detectedDetails: details,
                    sourceLabel: "スマート解析"
                )
            case .containers:
                return AIItemAnalysis(
                    safetyLevel: .safe,
                    whatIsThis: "現在停止しているDockerコンテナの一時レイヤーです。",
                    impactIfDeleted: "稼働中のコンテナや永続化Volumeには影響しません。",
                    howToRestore: "`docker compose up` や `docker run` でいつでも再作成できます。",
                    detectedDetails: details,
                    sourceLabel: "スマート解析"
                )
            case .buildCache:
                return AIItemAnalysis(
                    safetyLevel: .safe,
                    whatIsThis: "Docker BuildKit がイメージビルド高速化のために保持しているレイヤーキャッシュです。",
                    impactIfDeleted: "最も肥大化しやすい領域です。削除してもコンテナやイメージは消えず、次回ビルド時のみ少し時間がかかります。",
                    howToRestore: "次回の `docker build` 実行時に必要な分だけ自動生成されます。",
                    detectedDetails: details,
                    sourceLabel: "スマート解析"
                )
            case .localVolumes:
                return AIItemAnalysis(
                    safetyLevel: .critical,
                    whatIsThis: "Dockerの永続化ボリューム（PostgreSQL / MySQL等のローカルDBデータなど）です。",
                    impactIfDeleted: "⚠️ 未使用ボリューム内のデータベースの中身や永続データが完全に消去されます。大切なローカルDBデータがないか確認してください。",
                    howToRestore: "削除すると復元できません（マイグレーション・シードの再実行が必要になります）。",
                    detectedDetails: details,
                    sourceLabel: "スマート解析"
                )
            }
        }

        // 3. ワークスペース (node_modules / Pods / .venv 等)
        if item.category == .workspace {
            let folderName = item.url.lastPathComponent
            if folderName == "node_modules" {
                return AIItemAnalysis(
                    safetyLevel: .recreatable,
                    whatIsThis: "Node.js プロジェクトの依存パッケージフォルダ (`node_modules`) です。",
                    impactIfDeleted: "ソースコードや `package.json` は一切消えません。現在開発していないプロジェクトなら削除して大幅に容量を空けられます。",
                    howToRestore: "そのプロジェクトで再び開発する時に `npm install` / `pnpm install` / `yarn` / `bun install` を実行するだけで完全復元されます。",
                    detectedDetails: details,
                    sourceLabel: "スマート解析"
                )
            } else if folderName == "Pods" {
                return AIItemAnalysis(
                    safetyLevel: .recreatable,
                    whatIsThis: "iOS / macOS プロジェクトの CocoaPods 依存ライブラリフォルダです。",
                    impactIfDeleted: "ソースコードや `Podfile.lock` は残るため、安全に削除できます。",
                    howToRestore: "開発再開時に `pod install`（または `bundle exec pod install`）を実行すると再生成されます。",
                    detectedDetails: details,
                    sourceLabel: "スマート解析"
                )
            } else if folderName == ".venv" || folderName == "venv" {
                return AIItemAnalysis(
                    safetyLevel: .recreatable,
                    whatIsThis: "Python プロジェクトの仮想環境（インストール済みパッケージ群）です。",
                    impactIfDeleted: "Pythonコードや `pyproject.toml` / `requirements.txt` は消えません。",
                    howToRestore: "`uv sync`、`poetry install`、または `python -m venv .venv && pip install -r requirements.txt` で再構築できます。",
                    detectedDetails: details,
                    sourceLabel: "スマート解析"
                )
            } else if folderName == ".terraform" {
                return AIItemAnalysis(
                    safetyLevel: .recreatable,
                    whatIsThis: "Terraform がローカルにダウンロードしたプロバイダプラグインのバイナリです。",
                    impactIfDeleted: "`.tf` 定義ファイルや `terraform.tfstate` は消えません。",
                    howToRestore: "`terraform init` を実行すれば自動的に再ダウンロードされます。",
                    detectedDetails: details,
                    sourceLabel: "スマート解析"
                )
            } else {
                return AIItemAnalysis(
                    safetyLevel: .recreatable,
                    whatIsThis: "プロジェクトのローカルビルドキャッシュ / 中間生成物 (`\(folderName)`) です。",
                    impactIfDeleted: "ソースコードには影響せず、次回ビルド時に再生成されます。",
                    howToRestore: "プロジェクトのビルドコマンド（`npm run build`, `cargo build`, `./gradlew build` 等）で自動生成されます。",
                    detectedDetails: details,
                    sourceLabel: "スマート解析"
                )
            }
        }

        // 4. Xcode / Simulator 関連
        if lowerPath.contains("/deriveddata/") {
            return AIItemAnalysis(
                safetyLevel: .safe,
                whatIsThis: "Xcodeがビルド時に生成する中間ファイル・インデックス・ビルド成果物のキャッシュ（DerivedData）です。",
                impactIfDeleted: "最も安全に削除できる代表的なキャッシュです。Xcodeのビルド不調の解消にも有効で、次回ビルド時に少し時間がかかるだけです。",
                howToRestore: "Xcodeでプロジェクトを開いてビルド（⌘B）すると自動生成されます。",
                detectedDetails: details,
                sourceLabel: "スマート解析"
            )
        } else if lowerPath.contains("/archives/") || path.hasSuffix(".xcarchive") {
            return AIItemAnalysis(
                safetyLevel: .caution,
                whatIsThis: "App Store Connectへの提出や配布用に作成された Xcode Archive (`.xcarchive`) です。",
                impactIfDeleted: "⚠️ 本番リリースしたバージョンのクラッシュログ解析（dSYMシンボル復元）に必要な場合があります。不要な古いテストビルドのみ削除してください。",
                howToRestore: "同じコミットから再アーカイブは可能ですが、当時のビルドUUIDと同一のdSYMは再生成できません。",
                detectedDetails: details,
                sourceLabel: "スマート解析"
            )
        } else if lowerPath.contains("/ios devicesupport/") {
            return AIItemAnalysis(
                safetyLevel: .recreatable,
                whatIsThis: "実機iPhone/iPadをMacに接続してデバッグした際に展開されたOS別シンボルファイルです。",
                impactIfDeleted: "すでに使っていない古いiOSバージョンのフォルダは完全に不要です。",
                howToRestore: "現在使用中の実機をXcodeに接続すれば、必要なバージョンだけ自動的に再作成されます。",
                detectedDetails: details,
                sourceLabel: "スマート解析"
            )
        } else if lowerPath.contains("/coresimulator/caches") {
            return AIItemAnalysis(
                safetyLevel: .safe,
                whatIsThis: "iOS等のシミュレータ起動を高速化するための dyld 共有キャッシュです。",
                impactIfDeleted: "古いOSランタイム用のキャッシュは安全に削除できます。現在使っているOSの分も、次回シミュレータ起動時に自動再生成されます。",
                howToRestore: "シミュレータ起動時にバックグラウンドで自動再構築されます。",
                detectedDetails: details,
                sourceLabel: "スマート解析"
            )
        } else if lowerPath.contains("/coresimulator/devices/") {
            return AIItemAnalysis(
                safetyLevel: .caution,
                whatIsThis: "Xcode シミュレータの仮想端末インスタンス（端末内のインストール済み開発アプリやデータを含む）です。",
                impactIfDeleted: "そのシミュレータ端末内に保存していたローカル確認用データやログイン状態がリセットされます。使っていない古いOSの端末なら削除して問題ありません。",
                howToRestore: "Xcode の Window > Devices and Simulators からいつでも新しいシミュレータ端末を追加できます。",
                detectedDetails: details,
                sourceLabel: "スマート解析"
            )
        } else if lowerPath.contains("/org.swift.swiftpm") {
            return AIItemAnalysis(
                safetyLevel: .safe,
                whatIsThis: "Swift Package Manager (SPM) がグローバルに保持しているパッケージリポジトリ・バイナリ成果物（XCFramework等）のキャッシュです。",
                impactIfDeleted: "プロジェクトのコードや `Package.resolved` は消えません。古いバージョンの依存パッケージが蓄積しやすいため、安全に削除できます。",
                howToRestore: "Xcode の File > Packages > Resolve Package Versions または `swift package resolve` で必要な分だけ自動再取得されます。",
                detectedDetails: details,
                sourceLabel: "スマート解析"
            )
        }

        // 5. E2Eテストブラウザキャッシュ (Playwright / Cypress / Puppeteer)
        if lowerPath.contains("/ms-playwright") || lowerPath.contains("/cypress") || lowerPath.contains("/puppeteer") {
            return AIItemAnalysis(
                safetyLevel: .recreatable,
                whatIsThis: "Playwright / Cypress / Puppeteer がE2Eテスト実行用にダウンロードしたヘッドレスブラウザ（Chromium / Firefox / WebKit）バイナリです。",
                impactIfDeleted: "パッケージ更新のたびに旧リビジョンのブラウザが数GB単位で残ります。削除してもテストコードには影響しません。",
                howToRestore: "次回E2Eテストを実行する際、または `npx playwright install` / `npx cypress install` で現在必要なバージョンのみ再取得できます。",
                detectedDetails: details,
                sourceLabel: "スマート解析"
            )
        }

        // 6. Ollama / LM Studio / HuggingFace / PyTorch / Whisper AIモデル
        if lowerPath.contains("/.ollama/models") || lowerPath.contains("/.lmstudio/models") {
            return AIItemAnalysis(
                safetyLevel: .caution,
                whatIsThis: "Ollama / LM Studio でダウンロードしたローカルLLMのモデル重みファイルです。",
                impactIfDeleted: "⚠️ 削除するとローカルLLMモデルが消えるため、再度使う際に数GB〜数十GBの再ダウンロードが必要になります。",
                howToRestore: "`ollama pull <モデル名>` または LM Studio のモデル検索画面から再ダウンロードできます。",
                detectedDetails: details,
                sourceLabel: "スマート解析"
            )
        } else if lowerPath.contains("/huggingface/") || lowerPath.contains("/.cache/torch") || lowerPath.contains("/.cache/whisper") {
            return AIItemAnalysis(
                safetyLevel: .caution,
                whatIsThis: "Hugging Face / PyTorch / Whisper がダウンロードしたAIモデル重み・データセットのキャッシュです。",
                impactIfDeleted: "⚠️ 大容量（数GB〜数十GB）になりやすい領域です。もう使っていないモデルなら安全に削除できますが、使用中のモデルを消すと次回実行時に再ダウンロードが走ります。",
                howToRestore: "Pythonスクリプト実行時（`from_pretrained` 等）に自動で再ダウンロードされます。",
                detectedDetails: details,
                sourceLabel: "スマート解析"
            )
        }

        // 7. JetBrains / Android Studio IDE キャッシュ・ログ
        if lowerPath.contains("/caches/jetbrains") || lowerPath.contains("/logs/jetbrains")
            || lowerPath.contains("/caches/google") || lowerPath.contains("/logs/google") {
            return AIItemAnalysis(
                safetyLevel: .safe,
                whatIsThis: "JetBrains系IDE（IntelliJ / WebStorm / PyCharm）または Android Studio のインデックスキャッシュ・ログです。",
                impactIfDeleted: "特にアンインストール済みの旧バージョン（2023.x 等）のフォルダは完全に不要です。現在使用中のバージョンも削除可能ですが、次回起動時にインデックス再構築（Indexing）が走ります。",
                howToRestore: "IDE起動時に必要なインデックスのみ自動的に再構築されます。",
                detectedDetails: details,
                sourceLabel: "スマート解析"
            )
        }

        // 8. Android AVD / System Images
        if lowerPath.contains("/.android/avd/") {
            return AIItemAnalysis(
                safetyLevel: .caution,
                whatIsThis: "Android Studio のエミュレータ仮想端末（AVD）本体データです。",
                impactIfDeleted: "エミュレータ端末自体とその内部データが削除されます。",
                howToRestore: "Android Studio の Virtual Device Manager から再作成が必要です。",
                detectedDetails: details,
                sourceLabel: "スマート解析"
            )
        } else if lowerPath.contains("/android/sdk/system-images") {
            return AIItemAnalysis(
                safetyLevel: .recreatable,
                whatIsThis: "Androidエミュレータ用のOSシステムイメージ（APIレベル別）です。",
                impactIfDeleted: "現在使っていない古いAPIレベルのイメージは削除して数GB節約できます。",
                howToRestore: "Android Studio の SDK Manager からいつでも再ダウンロード可能です。",
                detectedDetails: details,
                sourceLabel: "スマート解析"
            )
        }

        // 9. その他の一般的なパッケージマネージャ・IDEキャッシュ
        return AIItemAnalysis(
            safetyLevel: item.isCaution ? .caution : .safe,
            whatIsThis: "\(item.category.title) が高速化のために保存しているダウンロード・ビルドキャッシュ（\(item.name)）です。",
            impactIfDeleted: "ソースコードや設定ファイルは消えません。次回パッケージ取得やビルド時に必要な分だけ再取得されます。",
            howToRestore: "ツールの通常実行時に自動で再作成されます。",
            detectedDetails: details,
            sourceLabel: "スマート解析"
        )
    }

    // MARK: - 2. 実ファイルシステムのコンテキスト読み取り

    static func inspectFilesystemContext(for item: ScanItem) -> String {
        guard item.isFileSystemItem else {
            return "\(item.subtitle) • サイズ: \(ByteFormatter.string(fromBytes: item.sizeBytes))"
        }

        let fm = FileManager.default
        let url = item.url
        let ageDays = item.ageInDays()
        var notes: [String] = [
            "サイズ: \(ByteFormatter.string(fromBytes: item.sizeBytes))",
            "最終更新: \(ageDays == 0 ? "今日" : "\(ageDays)日前")"
        ]

        // 親フォルダの package.json があればプロジェクト名と依存数を取得
        let parentURL = url.deletingLastPathComponent()
        let pkgJSON = parentURL.appendingPathComponent("package.json")
        if url.lastPathComponent == "node_modules",
           let data = try? Data(contentsOf: pkgJSON),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let pkgName = json["name"] as? String {
                notes.append("package.json名: \(pkgName)")
            }
            let depCount = (json["dependencies"] as? [String: Any])?.count ?? 0
            let devDepCount = (json["devDependencies"] as? [String: Any])?.count ?? 0
            if depCount + devDepCount > 0 {
                notes.append("依存定義: \(depCount + devDepCount)パッケージ")
            }
        }

        // Simulator Device の場合は device.plist の詳細を取得
        let devicePlist = url.appendingPathComponent("device.plist")
        if let dict = NSDictionary(contentsOf: devicePlist) {
            if let name = dict["name"] as? String {
                notes.append("端末: \(name)")
            }
            if let runtime = dict["runtime"] as? String,
               let os = GlobalCacheScanner.parseSimulatorRuntimeIdentifier(runtime) {
                notes.append("Simulator OS: \(os)")
            }
        }

        // ディレクトリ直下の主要サブアイテム（最大5件）を取得
        if let children = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ), !children.isEmpty {
            let sampleNames = children.prefix(5).map(\.lastPathComponent).joined(separator: ", ")
            let suffix = children.count > 5 ? " ほか計\(children.count)項目" : " (計\(children.count)項目)"
            notes.append("内容例: \(sampleNames)\(suffix)")
        }

        return notes.joined(separator: " • ")
    }

    // MARK: - 3. AIへの質問応答（ハイブリッド / ローカルCLI / Ollama / Gemini API / スマート解析）

    @concurrent
    static func askAdvisor(
        item: ScanItem,
        question: String,
        provider: AIProviderOption,
        localCLI: LocalCLITool,
        ollamaModel: String,
        geminiAPIKey: String
    ) async -> AIChatMessage {
        let instant = generateInstantAnalysis(for: item)
        let prompt = buildPrompt(for: item, instantAnalysis: instant, userQuestion: question)

        switch provider {
        case .offlineSmart:
            let reply = generateSmartRuleReply(for: item, instant: instant, question: question)
            return AIChatMessage(isUser: false, text: reply, sourceLabel: "スマート解析")

        case .geminiAPI:
            let key = resolvedGeminiKey(from: geminiAPIKey)
            guard !key.isEmpty else {
                return AIChatMessage(
                    isUser: false,
                    text: "⚠️ 設定画面で Gemini API キーが未設定のため、スマート解析から回答します：\n" + generateSmartRuleReply(for: item, instant: instant, question: question),
                    sourceLabel: "スマート解析 (APIキー未設定)"
                )
            }
            if let text = await callGeminiAPI(prompt: prompt, apiKey: key) {
                return AIChatMessage(isUser: false, text: text, sourceLabel: "Gemini API")
            }
            return AIChatMessage(
                isUser: false,
                text: generateSmartRuleReply(for: item, instant: instant, question: question),
                sourceLabel: "スマート解析 (フォールバック)"
            )

        case .ollama:
            if let (text, modelUsed) = await callOllamaAPI(prompt: prompt, preferredModel: ollamaModel) {
                return AIChatMessage(isUser: false, text: text, sourceLabel: "Ollama (\(modelUsed))")
            }
            return AIChatMessage(
                isUser: false,
                text: "⚠️ Ollama (`http://localhost:11434`) に接続できなかったため、内蔵スマート解析から回答します：\n" + generateSmartRuleReply(for: item, instant: instant, question: question),
                sourceLabel: "スマート解析 (Ollama未起動)"
            )

        case .localCLI:
            if let (text, toolName) = await callLocalCLI(prompt: prompt, preferredTool: localCLI) {
                return AIChatMessage(isUser: false, text: text, sourceLabel: toolName)
            }
            return AIChatMessage(
                isUser: false,
                text: "⚠️ ローカルの `\(localCLI.rawValue)` CLI が見つからないか応答しなかったため、内蔵スマート解析から回答します：\n" + generateSmartRuleReply(for: item, instant: instant, question: question),
                sourceLabel: "スマート解析 (CLI未検出)"
            )

        case .auto:
            // 1. Gemini API キーがあれば最優先で高速呼び出し
            let key = resolvedGeminiKey(from: geminiAPIKey)
            if !key.isEmpty, let text = await callGeminiAPI(prompt: prompt, apiKey: key) {
                return AIChatMessage(isUser: false, text: text, sourceLabel: "Gemini API")
            }
            // 2. ローカルの Ollama が起動していれば利用
            if let (text, modelUsed) = await callOllamaAPI(prompt: prompt, preferredModel: ollamaModel) {
                return AIChatMessage(isUser: false, text: text, sourceLabel: "Ollama (\(modelUsed))")
            }
            // 3. ローカルCLI (claude / gemini) が利用可能なら呼び出し
            if let (text, toolName) = await callLocalCLI(prompt: prompt, preferredTool: localCLI) {
                return AIChatMessage(isUser: false, text: text, sourceLabel: toolName)
            }
            // 4. オフラインスマート解析で即座に回答
            return AIChatMessage(
                isUser: false,
                text: generateSmartRuleReply(for: item, instant: instant, question: question),
                sourceLabel: "スマート解析"
            )
        }
    }

    private static func buildPrompt(
        for item: ScanItem,
        instantAnalysis: AIItemAnalysis,
        userQuestion: String
    ) -> String {
        """
        あなたはmacOSの開発環境・ストレージ整理の専門家アシスタントです。
        ユーザーが以下のキャッシュまたは不要ファイルを削除してよいか質問しています。簡潔・具体的に日本語で回答してください（3〜5行程度）。

        【対象アイテム情報】
        - 名前: \(item.name)
        - カテゴリ: \(item.category.title)
        - フルパス: \(item.url.path)
        - サイズ: \(ByteFormatter.string(fromBytes: item.sizeBytes))
        - 経過日数: \(item.ageInDays())日前
        - コンテキスト詳細: \(instantAnalysis.detectedDetails)
        - 事前診断: \(instantAnalysis.safetyLevel.badgeText) / \(instantAnalysis.whatIsThis)

        【ユーザーの質問】
        \(userQuestion)
        """
    }

    private static func generateSmartRuleReply(
        for item: ScanItem,
        instant: AIItemAnalysis,
        question: String
    ) -> String {
        let q = question.lowercased()
        if q.contains("戻") || q.contains("復元") || q.contains("再生成") || q.contains("コマンド") {
            return "【復元・再生成の方法】\n\(instant.howToRestore)\n（対象パス: `\(item.url.path)`）"
        }
        if q.contains("中身") || q.contains("詳細") || q.contains("構成") {
            return "【フォルダ内容の解析】\n\(instant.detectedDetails)\n正体: \(instant.whatIsThis)"
        }
        return """
        \(instant.safetyLevel.badgeText)
        ・正体: \(instant.whatIsThis)
        ・削除後の影響: \(instant.impactIfDeleted)
        ・復元方法: \(instant.howToRestore)
        """
    }

    private static func resolvedGeminiKey(from settingsKey: String) -> String {
        let trimmed = settingsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
    }

    // MARK: - Gemini REST API

    @concurrent
    private static func callGeminiAPI(prompt: String, apiKey: String) async -> String? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)") else {
            return nil
        }

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 450
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                return nil
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    // MARK: - Ollama Local HTTP API

    @concurrent
    private static func callOllamaAPI(prompt: String, preferredModel: String) async -> (String, String)? {
        // 起動確認とモデル名解決
        var modelToUse = preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tagsURL = URL(string: "http://localhost:11434/api/tags") {
            var tagsReq = URLRequest(url: tagsURL)
            tagsReq.timeoutInterval = 2.0
            if let (data, resp) = try? await URLSession.shared.data(for: tagsReq),
               let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let installedNames = models.compactMap { $0["name"] as? String }
                if installedNames.isEmpty { return nil }
                if modelToUse.isEmpty || !installedNames.contains(where: { $0.hasPrefix(modelToUse) }) {
                    modelToUse = installedNames[0]
                }
            } else {
                return nil
            }
        }

        guard !modelToUse.isEmpty,
              let genURL = URL(string: "http://localhost:11434/api/generate") else {
            return nil
        }

        let payload: [String: Any] = [
            "model": modelToUse,
            "prompt": prompt,
            "stream": false
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }

        var request = URLRequest(url: genURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["response"] as? String, !text.isEmpty else {
                return nil
            }
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), modelToUse)
        } catch {
            return nil
        }
    }

    // MARK: - Local CLI (claude / gemini)

    @concurrent
    private static func callLocalCLI(prompt: String, preferredTool: LocalCLITool) async -> (String, String)? {
        let toolsOrder: [LocalCLITool] = preferredTool == .claude ? [.claude, .gemini] : [.gemini, .claude]

        for tool in toolsOrder {
            if let output = await runCLICommand(binary: tool.rawValue, prompt: prompt) {
                return (output, "\(tool.rawValue) CLI")
            }
        }
        return nil
    }

    @concurrent
    private static func runCLICommand(binary: String, prompt: String) async -> String? {
        let escapedPrompt = prompt.replacingOccurrences(of: "'", with: "'\\''")
        let command = "command -v \(binary) >/dev/null 2>&1 && \(binary) -p '\(escapedPrompt)'"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 18_000_000_000)
            if process.isRunning {
                process.terminate()
            }
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutTask.cancel()

        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }
}
