import Foundation

/// ユーザーが選択可能なAIアドバイザー方式
enum AIProviderOption: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case localCLI = "localCLI"
    case ollama = "ollama"
    case geminiAPI = "geminiAPI"
    case openAIAPI = "openAIAPI"
    case offlineSmart = "offlineSmart"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            "ハイブリッド自動（推奨）"
        case .localCLI:
            "ローカルCLI連携 (agy / claude / codex)"
        case .ollama:
            "ローカルLLM (Ollama)"
        case .geminiAPI:
            "Gemini API (APIキー)"
        case .openAIAPI:
            "ChatGPT / OpenAI API (APIキー)"
        case .offlineSmart:
            "内蔵スマート解析のみ（通信なし・即時）"
        }
    }

    var description: String {
        switch self {
        case .auto:
            "即座にスマート解析を表示し、詳細質問時は設定済みのAPIキー・Ollama・ローカルCLI (Antigravity / Claude / Codex) を自動選択します"
        case .localCLI:
            "Macにインストールされている agy (Antigravity CLI)、claude (Claude Code)、codex (ChatGPT / OpenAI Codex CLI) を呼び出して回答を生成します"
        case .ollama:
            "ローカルで起動中の Ollama (http://localhost:11434) のモデルを使用してオフラインで回答します"
        case .geminiAPI:
            "Google Gemini API (gemini-2.5-flash) を直接呼び出して高速に回答します"
        case .openAIAPI:
            "OpenAI API (gpt-4o-mini) を直接呼び出して高速に回答します"
        case .offlineSmart:
            "外部通信やLLM呼び出しを行わず、フォルダ内のメタデータと知識辞書のみで即座に解説します"
        }
    }
}

/// ローカルCLIツールの選択肢
enum LocalCLITool: String, CaseIterable, Identifiable, Sendable {
    case antigravity = "agy"
    case claude = "claude"
    case codex = "codex"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .antigravity: "Antigravity CLI (agy -p)"
        case .claude: "Claude Code CLI (claude -p)"
        case .codex: "ChatGPT / Codex CLI (codex exec)"
        }
    }

    /// 非対話モードでプロンプトを実行するシェルコマンドを生成する
    func buildShellCommand(escapedSingleQuotedPrompt: String) -> String {
        switch self {
        case .antigravity:
            return "command -v agy >/dev/null 2>&1 && agy -p '\(escapedSingleQuotedPrompt)'"
        case .claude:
            return "command -v claude >/dev/null 2>&1 && claude -p '\(escapedSingleQuotedPrompt)'"
        case .codex:
            return "command -v codex >/dev/null 2>&1 && codex exec --ephemeral '\(escapedSingleQuotedPrompt)'"
        }
    }
}

/// 削除の安全性レベル
enum DeletionSafetyLevel: Sendable {
    case safe           // 🟢 安全に削除可能
    case recreatable    // 🟡 削除可（再ビルド・再インストールで復元）
    case caution        // 🟠 要確認（再ダウンロードや環境構築が必要）
    case critical       // 🔴 注意（失うと戻せない可能性あり）

    var badgeText: String {
        switch self {
        case .safe: "🟢 安全に削除可能"
        case .recreatable: "🟡 削除OK（自動再生成・再取得可）"
        case .caution: "🟠 要確認（再構築に時間がかかる）"
        case .critical: "🔴 注意（重要データの可能性）"
        }
    }
}

/// 個別アイテムに対するAI・スマート初期診断結果
struct AIItemAnalysis: Sendable {
    let safetyLevel: DeletionSafetyLevel
    let whatIsThis: String
    let impactIfDeleted: String
    let howToRestore: String
    let detectedDetails: String
    var aiDeepExplanation: String?
    var sourceLabel: String
}

/// アイテムごとの追加質問チャット履歴
struct AIChatMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let isUser: Bool
    let text: String
    let sourceLabel: String?

    init(id: UUID = UUID(), isUser: Bool, text: String, sourceLabel: String? = nil) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.sourceLabel = sourceLabel
    }
}
