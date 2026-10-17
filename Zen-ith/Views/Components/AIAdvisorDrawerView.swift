import SwiftUI

struct AIAdvisorDrawerView: View {
    let item: ScanItem
    let analysis: AIItemAnalysis
    let chatMessages: [AIChatMessage]
    @Binding var questionDraft: String
    let isAskingAI: Bool
    let onSendPresetQuestion: (String) -> Void
    let onSendDraftQuestion: () -> Void
    let onClose: () -> Void

    private let quickQuestions = [
        "今すぐ消しても開発中の作業に影響はない？",
        "消した後に元に戻す具体的なコマンドを教えて",
        "このフォルダの中身と肥大化している理由を教えて"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ヘッダー行：安全性バッジ＋エンジン表示＋閉じるボタン
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(analysis.safetyLevel.badgeText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(safetyColor)

                Spacer()

                Text(analysis.sourceLabel)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("解説を閉じる")
            }

            // 3つの基本ポイント（正体・影響・復元方法）＋フルパス表示
            VStack(alignment: .leading, spacing: 5) {
                if item.isFileSystemItem {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                            .padding(.top, 1)

                        Text(item.url.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                advisorPointRow(icon: "info.circle.fill", label: "正体", text: analysis.whatIsThis)
                advisorPointRow(icon: "checkmark.shield.fill", label: "削除の影響", text: analysis.impactIfDeleted)
                advisorPointRow(icon: "arrow.counterclockwise.circle.fill", label: "復元・再生成", text: analysis.howToRestore)

                Text("🔍 \(analysis.detectedDetails)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            Divider()

            // クイック質問チップ
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickQuestions, id: \.self) { q in
                        Button {
                            onSendPresetQuestion(q)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkle")
                                    .font(.system(size: 9))
                                Text(q)
                                    .font(.system(size: 10))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isAskingAI)
                    }
                }
            }

            // チャット履歴表示
            if !chatMessages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(chatMessages) { msg in
                        if msg.isUser {
                            HStack {
                                Spacer(minLength: 24)
                                Text(msg.text)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                if let source = msg.sourceLabel {
                                    Text("🤖 \(source)")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Text(msg.text)
                                    .font(.system(size: 11))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            if isAskingAI {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("AIが「\(item.name)」を分析しています...")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            // 自由質問入力欄
            HStack(spacing: 6) {
                TextField("「これ消して大丈夫？」などAIに追加質問...", text: $questionDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit {
                        onSendDraftQuestion()
                    }
                    .disabled(isAskingAI)

                Button(action: onSendDraftQuestion) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isAskingAI || questionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
                )
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private func advisorPointRow(icon: String, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(width: 14)
                .padding(.top, 1)

            Text("\(label): ")
                .font(.system(size: 11, weight: .semibold))
            + Text(text)
                .font(.system(size: 11))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var safetyColor: Color {
        switch analysis.safetyLevel {
        case .safe: .green
        case .recreatable: .blue
        case .caution: .orange
        case .critical: .red
        }
    }
}
