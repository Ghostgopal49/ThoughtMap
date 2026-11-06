import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Thought.createdAt, order: .reverse) private var thoughts: [Thought]

    @AppStorage("reflectionText") private var reflection = ""
    @AppStorage("reflectionDate") private var reflectionDate: Double = 0
    @State private var reflecting = false

    var body: some View {
        let stats = InsightEngine.areaStats(thoughts: thoughts)
        let topAreas = Array(stats.prefix(5))
        let weeks = InsightEngine.weeklyPoints(thoughts: thoughts, areas: topAreas)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if stats.isEmpty {
                        ContentUnavailableView(
                            "No patterns yet",
                            systemImage: "sparkles",
                            description: Text("Add some thoughts and come back. Patterns become clear after a week or two.")
                        )
                        .padding(.top, 60)
                    } else {
                        focusCard(stats)
                        chartCard(weeks, areas: topAreas)
                        areasCard(stats)
                        reflectionCard(stats)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Your mind lately")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func focusCard(_ stats: [AreaStat]) -> some View {
        let total = stats.reduce(0) { $0 + $1.momentum }
        let top = stats[0]
        let share = total > 0 ? Int((top.momentum / total * 100).rounded()) : 0
        return card {
            Text("Most of your attention is on")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(top.name)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.color(top.colorIndex))
            Text("About \(share)% of your recent thinking, with \(top.last7) thoughts this week.")
                .font(.subheadline)
        }
    }

    private func chartCard(_ weeks: [WeekPoint], areas: [AreaStat]) -> some View {
        card {
            Text("Last 8 weeks")
                .font(.headline)
            Chart(weeks) { point in
                LineMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Thoughts", point.count)
                )
                .foregroundStyle(by: .value("Area", point.area))
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Thoughts", point.count)
                )
                .foregroundStyle(by: .value("Area", point.area))
            }
            .chartForegroundStyleScale(
                domain: areas.map(\.name),
                range: areas.map { Palette.color($0.colorIndex) }
            )
            .chartLegend(position: .bottom)
            .frame(height: 220)
        }
    }

    private func areasCard(_ stats: [AreaStat]) -> some View {
        card {
            HStack {
                Text("All areas").font(.headline)
                Spacer()
                Text("last 30 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(stats) { stat in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Palette.color(stat.colorIndex))
                        .frame(width: 10, height: 10)
                    Text(stat.name)
                    Spacer()
                    Text("\(stat.last30)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Image(systemName: stat.trend.symbol)
                        .foregroundStyle(stat.trend.color)
                        .frame(width: 22)
                }
                .font(.body)
            }
        }
    }

    private func reflectionCard(_ stats: [AreaStat]) -> some View {
        card {
            HStack {
                Label("Reflection", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button(reflecting ? "Thinking…" : (reflection.isEmpty ? "Reflect" : "Refresh")) {
                    let recent = Array(thoughts.prefix(40))
                    Task {
                        reflecting = true
                        reflection = await Organizer.shared.reflect(stats: stats, recent: recent)
                        reflectionDate = Date().timeIntervalSince1970
                        reflecting = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(reflecting)
            }
            if reflection.isEmpty {
                Text("Let the on-device AI read your recent thoughts and tell you what it notices.")
                    .foregroundStyle(.secondary)
            } else {
                Text(reflection)
                Text("Written \(Date(timeIntervalSince1970: reflectionDate).formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
