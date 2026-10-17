import SwiftUI

/// 各スキャン項目行の直下に展開される「スキップ理由・対処法」カード
struct CleanupFailureInlineCardView: View {
    let detail: CleanupFailureDetail
    let isCleaning: Bool
    let isCommandCopied: Bool
    let onRetryWithAdmin: () -> Void
    let onCopyCommand: (String) -> Void
    let onOpenFullDiskAccess: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text("スキップ理由: \(detail.reasonTitle)")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(detail.rawErrorMessage)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 4)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("この診断メッセージを閉じる")
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("💡 対処方法")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(Array(detail.remediationSteps.enumerated()), id: \.offset) { idx, step in
                    HStack(alignment: .top, spacing: 5) {
                        Text("\(idx + 1).")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.orange)
                        Text(step)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let command = detail.suggestedTerminalCommand {
                HStack(spacing: 6) {
                    Text(command)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))

                    Button {
                        onCopyCommand(command)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: isCommandCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            Text(isCommandCopied ? "コピー済" : "コマンドをコピー")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                if detail.canRetryWithAdmin {
                    Button(action: onRetryWithAdmin) {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 10.5))
                            Text("管理者権限で削除 (Touch ID / パスワード)")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .disabled(isCleaning)
                }

                if detail.needsFullDiskAccessHint {
                    Button(action: onOpenFullDiskAccess) {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 10))
                            Text("フルディスクアクセス設定を開く")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.orange.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}

/// フッター上部に表示されるスキップ項目一括レポート＆一括対処パネル
struct CleanupFailureSummaryPanelView: View {
    @ObservedObject var viewModel: ScannerViewModel

    var body: some View {
        let failures = viewModel.failureList
        if !failures.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)

                    Text("スキップされた項目 (\(failures.count)件)")
                        .font(.system(size: 11.5, weight: .bold))

                    Button {
                        viewModel.showingFailureReport.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Text(viewModel.showingFailureReport ? "詳細を隠す" : "理由と対処法を見る")
                                .font(.system(size: 10.5, weight: .semibold))
                            Image(systemName: viewModel.showingFailureReport ? "chevron.down" : "chevron.up")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if viewModel.canRetryAnyFailureWithAdmin {
                        Button {
                            viewModel.retryAllFailuresWithAdmin()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 10))
                                Text("すべて管理者権限で削除")
                                    .font(.system(size: 10.5, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isCleaning)
                    }

                    Button {
                        viewModel.clearAllFailures()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("スキップ一覧を閉じる")
                }

                if viewModel.showingFailureReport {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(failures) { detail in
                                CleanupFailureInlineCardView(
                                    detail: detail,
                                    isCleaning: viewModel.isCleaning,
                                    isCommandCopied: viewModel.copiedCommandText == detail.suggestedTerminalCommand && detail.suggestedTerminalCommand != nil,
                                    onRetryWithAdmin: {
                                        viewModel.retryFailureWithAdmin(detail)
                                    },
                                    onCopyCommand: { cmd in
                                        viewModel.copyTerminalCommand(cmd)
                                    },
                                    onOpenFullDiskAccess: {
                                        viewModel.openFullDiskAccessSettings()
                                    },
                                    onDismiss: {
                                        viewModel.dismissFailure(id: detail.itemID)
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 165)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
    }
}
