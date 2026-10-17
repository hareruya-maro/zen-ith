import Foundation

/// ユーザーが選択可能なAIアドバイザー方式
enum AIProviderOption: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case localCLI = "localCLI"
    case ollama = "ollama"
    case geminiAPI = "geminiAPI"
    case offlineSmart = "offlineSmart"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            "ハイブリッド自動（推奨）"
        case .localCLI:
            "ローカルCLI連携 (claude / gemini)"
        case .ollama:
            "ローカルLLM (Ollama)"
        case .geminiAPI:
            "Gemini API (APIキー)"
        case .offlineSmart:
            "内蔵スマート解析のみ（通信なし・即時）"
        }
    }

    var description: String {
        switch self {
        case .auto:
            "即座にスマート解析を表示し、詳細質問時は設定済みのGemini API・Ollama・ローカルCLIを自動選択します"
        case .localCLI:
            "Macにインストールされている claude または gemini コマンドラインツールを呼び出して回答を生成します"
        case .ollama:
            "ローカルで起動中の Ollama (http://localhost:11434) のモデルを使用してオフラインで回答します"
        case .geminiAPI:
            "Google Gemini API (gemini-2.5-flash) を直接呼び出して高速に回答します"
        case .offlineSmart:
            "外部通信やLLM呼び出しを行わず、フォルダ内のメタデータと知識辞書のみで即座に解説します"
        }
    }
}

/// ローカルCLIツールの選択肢
enum LocalCLITool: String, CaseIterable, Identifiable, Sendable {
    case claude = "claude"
    case gemini = "gemini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code CLI (claude -p)"
        case .gemini: "Gemini CLI (gemini -p)"
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
