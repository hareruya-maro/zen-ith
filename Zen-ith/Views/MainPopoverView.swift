import SwiftUI

struct MainPopoverView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Group {
            if viewModel.showingSettings {
                SettingsView(
                    settings: settings,
                    onBack: { viewModel.showingSettings = false },
                    onSettingsChanged: { viewModel.startScan() },
                    onScheduleChanged: { viewModel.reschedulePeriodicScan() }
                )
            } else {
                scannerMainContent
            }
        }
        .frame(width: 520, height: 600)
    }

    private var scannerMainContent: some View {
        VStack(spacing: 0) {
            HeaderView(
                viewModel: viewModel,
                onOpenSettings: { viewModel.showingSettings = true }
            )

            SmartFilterBarView(viewModel: viewModel)

            Divider()

            if viewModel.isScanning && viewModel.items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text("キャッシュ・ワークスペース・Docker環境を走査中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.categoryGroups.isEmpty {
                if viewModel.isSearchActive {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("「\(viewModel.searchQuery)」に一致する項目はありません")
                            .font(.headline)
                        Button("検索をクリア") {
                            viewModel.searchQuery = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.green)
                        Text("クリーンな状態です！")
                            .font(.headline)
                        Text("削除可能なキャッシュや不要ファイルは見つかりませんでした。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            } else {
                allCategoriesSelectionBar

                Divider()

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.categoryGroups) { group in
                            CategorySectionView(
                                group: group,
                                dockerDiskInfos: group.category == .docker ? viewModel.dockerDiskInfos : [],
                                viewModel: viewModel,
                                isExpanded: Binding(
                                    get: { viewModel.expandedCategories.contains(group.category) },
                                    set: { isExpanded in
                                        if isExpanded {
                                            viewModel.expandedCategories.insert(group.category)
                                        } else {
                                            viewModel.expandedCategories.remove(group.category)
                                        }
                                    }
                                )
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }

            Divider()

            FooterActionBarView(viewModel: viewModel)
        }
    }

    private var allCategoriesSelectionBar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.toggleAllSelection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.allSelectionCheckboxIconName)
                        .font(.system(size: 14))
                        .foregroundStyle(viewModel.filteredSelectedCount > 0 ? Color.accentColor : Color.secondary)

                    Text("すべてのタイプを一括選択")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("(\(viewModel.filteredSelectedCount)/\(viewModel.filteredItems.count)項目)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canToggleAllSelection || viewModel.isScanning || viewModel.isCleaning)
            .help(viewModel.isAllChecked ? "すべてのタイプの選択を解除" : "すべてのタイプの対象データを一括選択（⚠️要確認を除く）")
            .accessibilityLabel("すべてのタイプを一括選択")

            Spacer()

            if viewModel.filteredSelectedBytes > 0 && viewModel.filteredSelectedBytes < viewModel.filteredTotalBytes {
                Text("選択 \(ByteFormatter.string(fromBytes: viewModel.filteredSelectedBytes)) /")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Text(ByteFormatter.string(fromBytes: viewModel.filteredTotalBytes))
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }
}
