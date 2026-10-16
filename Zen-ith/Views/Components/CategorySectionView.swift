import SwiftUI

struct CategorySectionView: View {
    let group: CategoryGroup
    @Binding var isExpanded: Bool
    let onToggleCategory: () -> Void
    let onToggleItem: (String) -> Void
    let onRevealItem: (ScanItem) -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 2) {
                ForEach(group.items) { item in
                    ScanItemRowView(
                        item: item,
                        onToggle: { onToggleCategoryItem(item.id) },
                        onRevealInFinder: { onRevealItem(item) }
                    )
                }
            }
            .padding(.top, 4)
            .padding(.leading, 6)
        } label: {
            HStack(spacing: 8) {
                Button(action: onToggleCategory) {
                    Image(systemName: checkboxIconName)
                        .font(.system(size: 14))
                        .foregroundStyle(group.selectedCount > 0 ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
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
        if group.isCategoryChecked {
            return "checkmark.square.fill"
        } else if group.isPartiallyChecked {
            return "minus.square.fill"
        } else {
            return "square"
        }
    }

    private func onToggleCategoryItem(_ id: String) {
        onToggleItem(id)
    }
}
