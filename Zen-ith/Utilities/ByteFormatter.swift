import Foundation
import SwiftUI

enum ByteFormatter {
    static func string(fromBytes bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func relativeDateString(from date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 {
            return "たった今"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)分前"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)時間前"
        }
        let days = hours / 24
        return "\(days)日前"
    }

    static func badgeColor(for severity: SizeSeverity) -> Color {
        switch severity {
        case .normal:
            .secondary
        case .warning:
            .orange
        case .critical:
            .red
        }
    }
}
