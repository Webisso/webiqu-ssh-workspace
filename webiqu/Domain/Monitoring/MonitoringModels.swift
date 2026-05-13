import Foundation

struct MonitoringSnapshot: Equatable, Sendable {
    var cpuUsagePercent: Double
    var memoryUsedMB: Double
    var memoryFreeMB: Double
    var diskUsedGB: Double
    var diskAvailableGB: Double
}

struct MonitoringSample: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let snapshot: MonitoringSnapshot
}

enum MonitoringRefreshInterval: String, CaseIterable, Identifiable, Sendable {
    case second02
    case second05
    case second1
    case second3
    case second5
    case second10
    case second30
    case minute1
    case minute3
    case minute5

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .second02:
            return 0.2
        case .second05:
            return 0.5
        case .second1:
            return 1
        case .second3:
            return 3
        case .second5:
            return 5
        case .second10:
            return 10
        case .second30:
            return 30
        case .minute1:
            return 60
        case .minute3:
            return 180
        case .minute5:
            return 300
        }
    }

    var title: String {
        switch self {
        case .second02:
            return "0.2 saniye"
        case .second05:
            return "0.5 saniye"
        case .second1:
            return "1 saniye"
        case .second3:
            return "3 saniye"
        case .second5:
            return "5 saniye"
        case .second10:
            return "10 saniye"
        case .second30:
            return "30 saniye"
        case .minute1:
            return "1 dk"
        case .minute3:
            return "3 dk"
        case .minute5:
            return "5 dk"
        }
    }
}

struct RemoteMonitoringParser {
    private var previousCPUCounters: (total: Double, idle: Double)?

    mutating func parseUbuntu(cpuStatOutput: String, memInfoOutput: String, diskOutput: String) -> MonitoringSnapshot {
        let cpu = parseCPUUsage(from: cpuStatOutput)
        let (memUsed, memFree) = parseMemory(from: memInfoOutput)
        let (diskUsed, diskAvailable) = parseDisk(from: diskOutput)

        return MonitoringSnapshot(
            cpuUsagePercent: cpu,
            memoryUsedMB: memUsed,
            memoryFreeMB: memFree,
            diskUsedGB: diskUsed,
            diskAvailableGB: diskAvailable
        )
    }

    private mutating func parseCPUUsage(from text: String) -> Double {
        guard let cpuLine = text.split(separator: "\n").first(where: { $0.hasPrefix("cpu ") }) else {
            return 0
        }

        let columns = cpuLine.split(whereSeparator: \.isWhitespace)
        guard columns.count >= 6 else { return 0 }

        let user = Double(columns[1]) ?? 0
        let nice = Double(columns[2]) ?? 0
        let system = Double(columns[3]) ?? 0
        let idle = Double(columns[4]) ?? 0
        let ioWait = Double(columns[5]) ?? 0
        let irq = columns.count > 6 ? (Double(columns[6]) ?? 0) : 0
        let softIrq = columns.count > 7 ? (Double(columns[7]) ?? 0) : 0
        let steal = columns.count > 8 ? (Double(columns[8]) ?? 0) : 0

        let total = user + nice + system + idle + ioWait + irq + softIrq + steal
        let idleTotal = idle + ioWait

        defer {
            previousCPUCounters = (total: total, idle: idleTotal)
        }

        if let previousCPUCounters {
            let totalDelta = total - previousCPUCounters.total
            let idleDelta = idleTotal - previousCPUCounters.idle
            guard totalDelta > 0 else { return 0 }
            let usage = ((totalDelta - idleDelta) / totalDelta) * 100
            return min(max(usage, 0), 100)
        }

        guard total > 0 else { return 0 }
        let usageSinceBoot = ((total - idleTotal) / total) * 100
        return min(max(usageSinceBoot, 0), 100)
    }

    private func parseMemory(from text: String) -> (Double, Double) {
        let lines = text.split(separator: "\n")
        guard
            let totalLine = lines.first(where: { $0.hasPrefix("MemTotal:") }),
            let availableLine = lines.first(where: { $0.hasPrefix("MemAvailable:") })
        else {
            return (0, 0)
        }

        let totalKB = parseMemInfoKB(from: String(totalLine))
        let availableKB = parseMemInfoKB(from: String(availableLine))
        guard totalKB > 0 else { return (0, 0) }

        let usedMB = max((totalKB - availableKB) / 1024, 0)
        let freeMB = max(availableKB / 1024, 0)
        return (usedMB, freeMB)
    }

    private func parseMemInfoKB(from line: String) -> Double {
        let columns = line.split(whereSeparator: \.isWhitespace)
        guard columns.count >= 2 else { return 0 }
        return Double(columns[1]) ?? 0
    }

    private func parseDisk(from text: String) -> (Double, Double) {
        let lines = text.split(separator: "\n")
        guard lines.count >= 2 else { return (0, 0) }

        let rootLine = lines.last ?? lines[1]
        let columns = rootLine.split(whereSeparator: \.isWhitespace)
        guard columns.count >= 5 else { return (0, 0) }

        let usedKB = Double(columns[2]) ?? 0
        let availableKB = Double(columns[3]) ?? 0
        let usedGB = usedKB / 1_048_576
        let availableGB = availableKB / 1_048_576
        return (usedGB, availableGB)
    }
}
