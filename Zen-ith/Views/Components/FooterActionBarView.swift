import SwiftUI

struct FooterActionBarView: View {
    @ObservedObject var viewModel: ScannerViewModel

    var body: some View {
        VStack(spacing: 8) {
            if let message = viewModel.bannerMessage {
                HStack(spacing: 6) {
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        viewModel.bannerMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            if viewModel.isCleaning {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: viewModel.cleanupProgressFraction)
                        .progressViewStyle(.linear)

                    Text(viewModel.cleanupProgressText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.vertical, 4)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("選択中: \(ByteFormatter.string(fromBytes: viewModel.selectedBytes)) (\(viewModel.selectedCount)項目)")
                            .font(.system(size: 12, weight: .semibold))

                        Text(viewModel.settings.deletionMode.title)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        viewModel.cleanSelectedItems()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("\(ByteFormatter.string(fromBytes: viewModel.selectedBytes)) をクリーンアップ")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(viewModel.selectedCount == 0 || viewModel.isScanning)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
