import SwiftUI
import DiagCleanKit

struct StatusView: View {
    @State private var model = StatusViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 240), spacing: Theme.Space.m)
    ]

    var body: some View {
        ScrollView {
            if let status = model.status {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    header(status)

                    LazyVGrid(columns: columns, spacing: Theme.Space.m) {
                        cpuCard(status)
                        memoryCard(status)
                        diskCard(status)
                        if let battery = status.battery {
                            batteryCard(battery)
                        }
                    }

                    processCard(status)
                }
                .padding(Theme.Space.xl)
            } else {
                VStack(spacing: Theme.Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Reading system counters…")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .background(Theme.windowBackground)
        .navigationTitle("Status")
        // Sampling follows the view's lifetime, so nothing keeps polling once this
        // screen is not on display.
        .task {
            model.start()
        }
        .onDisappear { model.stop() }
    }

    // MARK: - Header

    private func header(_ status: SystemStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Circle()
                .fill(model.overallHealth.tint)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.overallHealth.summary)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("Up \(uptimeText(status.uptime)) · \(status.coreCount) cores")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
        }
    }

    private func uptimeText(_ uptime: TimeInterval) -> String {
        let days = Int(uptime) / 86_400
        let hours = (Int(uptime) % 86_400) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    // MARK: - Cards

    private func cpuCard(_ status: SystemStatus) -> some View {
        MetricCard(
            title: "CPU",
            value: model.hasRates ? String(format: "%.0f%%", status.cpuPercent) : "—",
            health: StatusCalculator.cpuHealth(percent: status.cpuPercent),
            fraction: status.cpuPercent / 100,
            // Load average is per-core on macOS, so it only means anything next to the
            // core count.
            detail: status.loadAverage.map {
                String(format: "Load %.2f · %.2f · %.2f", $0.oneMinute, $0.fiveMinutes, $0.fifteenMinutes)
            } ?? "—"
        )
    }

    private func memoryCard(_ status: SystemStatus) -> some View {
        let memory = status.memory
        var detail = "\(ByteFormat.string(Int64(memory.usedBytes))) of \(ByteFormat.string(Int64(memory.totalBytes)))"
        if memory.swapUsedBytes > 0 {
            // Swap in use is the clearest single sign that a machine is short on memory
            // rather than merely using it.
            detail += " · \(ByteFormat.string(Int64(memory.swapUsedBytes))) swap"
        }

        return MetricCard(
            title: "Memory",
            value: String(format: "%.0f%%", memory.usedFraction * 100),
            health: StatusCalculator.memoryHealth(memory),
            fraction: memory.usedFraction,
            detail: detail
        )
    }

    private func diskCard(_ status: SystemStatus) -> some View {
        let disk = status.disk
        var detail = "\(ByteFormat.string(disk.availableBytes)) free of \(ByteFormat.string(disk.totalBytes))"
        if disk.purgeableBytes > 1_000_000_000 {
            // Names the gap between this figure and the raw free space, so the headline
            // number is never a mystery when compared against another tool.
            detail += " · incl. \(ByteFormat.string(disk.purgeableBytes)) purgeable"
        }

        return MetricCard(
            title: "Disk",
            value: String(format: "%.0f%%", disk.usedFraction * 100),
            health: StatusCalculator.diskHealth(disk),
            fraction: disk.usedFraction,
            detail: detail
        )
    }

    private func batteryCard(_ battery: BatterySample) -> some View {
        var detail = battery.isPluggedIn
            ? (battery.isCharging ? "Charging" : "Plugged in")
            : "On battery"
        if let minutes = battery.minutesRemaining {
            detail += " · \(minutes / 60)h \(minutes % 60)m \(battery.isPluggedIn ? "to full" : "left")"
        }

        return MetricCard(
            title: "Battery",
            value: "\(battery.percent)%",
            health: StatusCalculator.batteryHealth(battery),
            fraction: Double(battery.percent) / 100,
            detail: detail
        )
    }

    // MARK: - Processes

    private func processCard(_ status: SystemStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Busiest processes")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)

            if status.topProcesses.isEmpty {
                Text(model.hasRates ? "Nothing is using a meaningful amount of CPU." : "Measuring…")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(status.topProcesses) { process in
                        HStack(spacing: Theme.Space.m) {
                            Text(process.name)
                                .font(.callout)
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: Theme.Space.m)
                            Text(ByteFormat.string(Int64(process.residentBytes)))
                                .font(.caption)
                                .foregroundStyle(Theme.tertiaryText)
                                .sizeStyle()
                            Text(Self.processPercentText(process.cpuPercent))
                                .font(.callout)
                                .foregroundStyle(Theme.secondaryText)
                                .sizeStyle()
                                .frame(width: 48, alignment: .trailing)
                        }
                        .padding(.vertical, Theme.Space.xs)
                        if process.id != status.topProcesses.last?.id {
                            Divider()
                        }
                    }
                }
            }

            if status.unreadableProcessCount > 0 {
                // Said out loud rather than quietly omitted: macOS will not report task
                // info for another user's processes without elevation, and a "busiest
                // processes" list missing a third of the machine will eventually mislead
                // somebody hunting a runaway daemon.
                Text("\(status.unreadableProcessCount) system processes are not shown — macOS does not report them without elevated access.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Space.xs)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

extension StatusView {
    /// Whole numbers above 10%, one decimal below it. Rounding a busiest-processes list
    /// to whole percent turns every row on a quiet machine into "0%", which tells the
    /// reader nothing and looks like the column is broken.
    static func processPercentText(_ percent: Double) -> String {
        percent >= 10
            ? String(format: "%.0f%%", percent)
            : String(format: "%.1f%%", percent)
    }
}

// MARK: - Metric card

struct MetricCard: View {
    let title: String
    let value: String
    let health: HealthLevel
    let fraction: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if health != .normal {
                    Circle()
                        .fill(health.tint)
                        .frame(width: 7, height: 7)
                }
            }

            Text(value)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.primaryText)
                .monospacedDigit()

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.separator.opacity(0.4))
                    Capsule()
                        .fill(health.tint)
                        .frame(width: max(2, geometry.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 4)

            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

extension HealthLevel {
    /// Colour is the only place this app spends saturation, so it has to mean something:
    /// accent for fine, amber for worth a look, red for deal with this.
    var tint: Color {
        switch self {
        case .normal: return Theme.accent
        case .elevated: return Color(red: 0.85, green: 0.68, blue: 0.35)
        case .critical: return Theme.destructive
        }
    }

    var summary: String {
        switch self {
        case .normal: return "Everything looks healthy"
        case .elevated: return "Worth a look"
        case .critical: return "Needs attention"
        }
    }
}
