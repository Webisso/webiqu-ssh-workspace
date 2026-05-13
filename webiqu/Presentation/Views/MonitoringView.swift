import Charts
import SwiftUI

struct MonitoringView: View {
    let snapshot: MonitoringSnapshot
    let history: [MonitoringSample]
    let selectedInterval: MonitoringRefreshInterval
    let lastRefreshAt: Date?
    let isConnected: Bool
    let onIntervalChange: (MonitoringRefreshInterval) -> Void
    let onRefreshNow: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statCards

                GroupBox("CPU Usage") {
                    cpuChart
                        .frame(height: 180)
                }

                GroupBox("Memory Usage") {
                    memoryChart
                        .frame(height: 180)
                }

                GroupBox("Disk Usage") {
                    diskChart
                        .frame(height: 180)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server Monitoring")
                        .font(.title3.weight(.semibold))
                    Text(lastRefreshText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                refreshMenu

                Button("Refresh Now", action: onRefreshNow)
                    .disabled(!isConnected)
            }
        }
    }

    private var refreshMenu: some View {
        Menu {
            ForEach(MonitoringRefreshInterval.allCases) { interval in
                Button {
                    onIntervalChange(interval)
                } label: {
                    HStack {
                        Text(interval.title)
                        if interval == selectedInterval {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Refresh:")
                    .foregroundStyle(.secondary)
                Text(selectedInterval.title)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var statCards: some View {
        let totalMemory = max(1, snapshot.memoryUsedMB + snapshot.memoryFreeMB)
        let memoryUsagePercent = (snapshot.memoryUsedMB / totalMemory) * 100
        let totalDisk = max(1, snapshot.diskUsedGB + snapshot.diskAvailableGB)
        let diskUsagePercent = (snapshot.diskUsedGB / totalDisk) * 100

        return HStack(spacing: 12) {
            monitoringCard(
                title: "CPU",
                value: String(format: "%.1f%%", snapshot.cpuUsagePercent),
                detail: "Realtime load",
                tint: .orange
            )

            monitoringCard(
                title: "Memory",
                value: String(format: "%.1f%%", memoryUsagePercent),
                detail: String(format: "%.0f MB used", snapshot.memoryUsedMB),
                tint: .blue
            )

            monitoringCard(
                title: "Disk",
                value: String(format: "%.1f%%", diskUsagePercent),
                detail: String(format: "%.1f GB used", snapshot.diskUsedGB),
                tint: .green
            )
        }
    }

    private var cpuChart: some View {
        Chart(history) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("CPU", point.snapshot.cpuUsagePercent)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.orange)

            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("CPU", point.snapshot.cpuUsagePercent)
            )
            .foregroundStyle(.orange.opacity(0.15))
        }
        .chartYScale(domain: 0...100)
    }

    private var memoryChart: some View {
        Chart(memorySeries) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Memory", point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.blue)

            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Memory", point.value)
            )
            .foregroundStyle(.blue.opacity(0.15))
        }
        .chartYScale(domain: 0...100)
    }

    private var diskChart: some View {
        Chart(diskSeries) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Disk", point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.green)

            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Disk", point.value)
            )
            .foregroundStyle(.green.opacity(0.12))
        }
        .chartYScale(domain: 0...100)
    }

    private var lastRefreshText: String {
        guard let lastRefreshAt else {
            return "Last refresh: never"
        }
        return "Last refresh: \(lastRefreshAt.formatted(date: .abbreviated, time: .standard))"
    }

    private func monitoringCard(title: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var memorySeries: [UsagePoint] {
        history.compactMap { sample in
            let total = sample.snapshot.memoryUsedMB + sample.snapshot.memoryFreeMB
            guard total > 0 else { return nil }
            let value = (sample.snapshot.memoryUsedMB / total) * 100
            return UsagePoint(timestamp: sample.timestamp, value: min(max(value, 0), 100))
        }
    }

    private var diskSeries: [UsagePoint] {
        history.compactMap { sample in
            let total = sample.snapshot.diskUsedGB + sample.snapshot.diskAvailableGB
            guard total > 0 else { return nil }
            let value = (sample.snapshot.diskUsedGB / total) * 100
            return UsagePoint(timestamp: sample.timestamp, value: min(max(value, 0), 100))
        }
    }
}

private struct UsagePoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}
