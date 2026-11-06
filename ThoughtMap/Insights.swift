import SwiftUI

enum Trend {
    case new, rising, steady, fading, quiet

    var symbol: String {
        switch self {
        case .new: return "sparkle"
        case .rising: return "arrow.up.right"
        case .steady: return "arrow.right"
        case .fading: return "arrow.down.right"
        case .quiet: return "moon.zzz"
        }
    }

    var color: Color {
        switch self {
        case .new: return .blue
        case .rising: return .green
        case .steady: return .secondary
        case .fading: return .orange
        case .quiet: return .gray
        }
    }

    var word: String {
        switch self {
        case .new: return "new"
        case .rising: return "rising"
        case .steady: return "steady"
        case .fading: return "fading"
        case .quiet: return "quiet lately"
        }
    }
}

/// How much attention one top-level area (e.g. "Money") is getting.
struct AreaStat: Identifiable {
    let id: UUID
    let name: String
    let colorIndex: Int
    let total: Int
    let last7: Int
    let last30: Int
    let prev30: Int
    /// Recent thoughts count more: each thought's weight halves roughly every 10 days.
    let momentum: Double

    var trend: Trend {
        if last30 == 0 { return .quiet }
        if prev30 == 0 { return .new }
        let ratio = Double(last30) / Double(prev30)
        if ratio >= 1.3 { return .rising }
        if ratio <= 0.7 { return .fading }
        return .steady
    }
}

struct WeekPoint: Identifiable {
    let id = UUID()
    let area: String
    let weekStart: Date
    let count: Int
}

enum InsightEngine {
    static func areaStats(thoughts: [Thought], now: Date = .now) -> [AreaStat] {
        var groups: [UUID: (root: Cluster, items: [Thought])] = [:]
        for thought in thoughts {
            guard let cluster = thought.cluster else { continue }
            let root = cluster.root
            guard !root.isInbox else { continue }
            groups[root.uid, default: (root, [])].items.append(thought)
        }

        let day = 86_400.0
        return groups.values.map { group -> AreaStat in
            var last7 = 0, last30 = 0, prev30 = 0
            var momentum = 0.0
            for thought in group.items {
                let age = now.timeIntervalSince(thought.createdAt) / day
                if age <= 7 { last7 += 1 }
                if age <= 30 { last30 += 1 } else if age <= 60 { prev30 += 1 }
                momentum += exp(-max(age, 0) / 14)
            }
            return AreaStat(
                id: group.root.uid,
                name: group.root.name,
                colorIndex: group.root.colorIndex,
                total: group.items.count,
                last7: last7,
                last30: last30,
                prev30: prev30,
                momentum: momentum
            )
        }
        .sorted { $0.momentum > $1.momentum }
    }

    static func weeklyPoints(thoughts: [Thought], areas: [AreaStat], now: Date = .now, weeks: Int = 8) -> [WeekPoint] {
        let calendar = Calendar.current
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        var points: [WeekPoint] = []
        for offset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { continue }
            for area in areas {
                let count = thoughts.filter {
                    $0.cluster?.root.uid == area.id && $0.createdAt >= start && $0.createdAt < end
                }.count
                points.append(WeekPoint(area: area.name, weekStart: start, count: count))
            }
        }
        return points
    }
}
