import SwiftUI

struct CategorySectionView: View {
    let group: CategoryGroup
    let dockerDiskInfos: [DockerDiskInfo]
    @ObservedObject var viewModel: ScannerViewModel
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 4) {
                ForEach(group.items) { item in
                    VStack(spacing: 4) {
                        ScanItemRowView(
                            item: item,
                            isAIExpanded: viewModel.activeAIItemID == item.id,
                            isCleaning: viewModel.isCleaning,
                            onToggle: { viewModel.toggleItemSelection(id: item.id) },
                            onToggleAI: { viewModel.toggleAIAdvisor(for: item) },
                            onRevealInFinder: { viewModel.revealInFinder(item) },
                            onDeleteSingle: { viewModel.cleanSingleItem(item) }
                        )

                        if viewModel.activeAIItemID == item.id,
                           let analysis = viewModel.itemAnalyses[item.id] {
                            AIAdvisorDrawerView(
                                item: item,
                                analysis: analysis,
                                chatMessages: viewModel.itemChatHistories[item.id] ?? [],
                                questionDraft: $viewModel.aiQuestionDraft,
                                isAskingAI: viewModel.isAskingAI,
                                onSendPresetQuestion: { q in
                                    viewModel.askAIQuestion(for: item, presetQuestion: q)
                                },
                                onSendDraftQuestion: {
                                    viewModel.askAIQuestion(for: item)
                                },
                                onClose: {
                                    viewModel.activeAIItemID = nil
                                }
                            )
                        }
                    }
                }

                // Dockerカテゴリの場合、仮想ディスクファイル自体の肥大化情報を表示
                if group.category == .docker && !dockerDiskInfos.isEmpty {
                    ForEach(dockerDiskInfos) { disk in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "internaldrive.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("仮想ディスク実サイズ: \(disk.providerName)")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(ByteFormatter.string(fromBytes: disk.allocatedBytes))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(ByteFormatter.badgeColor(for: SizeSeverity.from(bytes: disk.allocatedBytes)))
                                }

                                Text(disk.hintText)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 4)

                            Button {
                                viewModel.revealURLInFinder(disk.diskURL)
                            } label: {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .padding(4)
                                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .help("仮想ディスクファイルをFinderで表示 (\(disk.diskURL.path))")
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.orange.opacity(0.08))
                        )
                        .help(disk.hintText)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.leading, 6)
        } label: {
            HStack(spacing: 8) {
                Button {
                    viewModel.toggleCategorySelection(group.category)
                } label: {
                    Image(systemName: checkboxIconName)
                        .font(.system(size: 14))
                        .foregroundStyle(group.selectedCount > 0 ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(group.items.isEmpty)
                .accessibilityLabel("\(group.category.title) を一括選択")

                Image(systemName: group.category.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)

                Text(group.category.title)
                    .font(.system(size: 13, weight: .semibold))

                Text("(\(group.items.count))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                if group.selectedBytes > 0 && group.selectedBytes < group.totalBytes {
                    Text("選択 \(ByteFormatter.string(fromBytes: group.selectedBytes)) /")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Text(ByteFormatter.string(fromBytes: group.totalBytes))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(ByteFormatter.badgeColor(for: SizeSeverity.from(bytes: group.totalBytes)))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var checkboxIconName: String {
        if group.items.isEmpty {
            return "square.dotted"
        } else if group.isCategoryChecked {
            return "checkmark.square.fill"
        } else if group.isPartiallyChecked {
            return "minus.square.fill"
        } else {
            return "square"
        }
    }
}
