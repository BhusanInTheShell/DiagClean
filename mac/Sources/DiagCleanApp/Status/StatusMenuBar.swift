import SwiftUI
import DiagCleanKit

/// The menu bar readout, off by default.
///
/// A menu bar item is the most intrusive thing this app can do — it occupies a strip of
/// screen the user did not offer — so it is opt-in, it shows one number rather than a
/// row of them, and it samples on a slower cadence than the window does.
struct StatusMenuBarLabel: View {
    let status: SystemStatus?
    let health: HealthLevel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform.path.ecg")
            if let status {
                Text(String(format: "%.0f%%", status.cpuPercent))
                    .monospacedDigit()
                    .foregroundStyle(health == .normal ? Color.primary : health.tint)
            }
        }
    }
}

struct StatusMenuBarContent: View {
    let status: SystemStatus?
    let health: HealthLevel
    @Binding var isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let status {
                HStack(spacing: Theme.Space.xs) {
                    Circle().fill(health.tint).frame(width: 7, height: 7)
                    Text(health.summary)
                        .font(.callout.weight(.medium))
                }

                Divider()

                row("CPU", String(format: "%.0f%%", status.cpuPercent))
                row("Memory", String(format: "%.0f%%", status.memory.usedFraction * 100))
                row("Disk free", ByteFormat.string(status.disk.availableBytes))
                if let battery = status.battery {
                    row("Battery", "\(battery.percent)%")
                }
            } else {
                Text("Reading system counters…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Hide Menu Bar Item") { isEnabled = false }
            Button("Quit DiagClean") { NSApplication.shared.terminate(nil) }
        }
        .padding(Theme.Space.m)
        .frame(width: 220)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout)
                .monospacedDigit()
        }
    }
}
