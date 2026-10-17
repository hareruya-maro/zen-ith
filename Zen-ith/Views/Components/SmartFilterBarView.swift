import SwiftUI

struct SmartFilterBarView: View {
    @ObservedObject var viewModel: ScannerViewModel

    var body: some View {
        VStack(spacing: 8) {
            Picker("スマートフィルタ", selection: Binding(
                get: { viewModel.selectedPreset },
                set: { viewModel.applySmartFilter($0) }
            )) {
                ForEach(SmartFilterPreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(viewModel.isScanning || viewModel.isCleaning)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField(
                    "プロジェクト名・パス・OS名で絞り込み (例: iOS 17, node_modules)...",
                    text: $viewModel.searchQuery
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))

                if viewModel.isSearchActive {
                    Text("\(viewModel.filteredItems.count)件")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())

                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("検索条件をクリア")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        viewModel.isSearchActive ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.18),
                        lineWidth: 1
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

