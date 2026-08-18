import Foundation

public protocol CommandRunning: Sendable {
    func run(_ command: MaintenanceCommand) -> CommandOutcome
}

public struct LiveCommandRunner: CommandRunning {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 60) {
        self.timeout = timeout
    }

    public func run(_ command: MaintenanceCommand) -> CommandOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments

        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return CommandOutcome(exitCode: -1, errorOutput: error.localizedDescription)
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandOutcome(
            exitCode: process.terminationStatus,
            errorOutput: String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}

public struct OptimizeProgress: Sendable {
    public let action: OptimizationAction
    public let completed: Int
    public let total: Int
}

/// Runs the selected actions, one at a time, and reports what actually happened.
///
/// Success is the command's real exit status, never an assumption that running it worked.
/// That distinction is not academic here: `killall -HUP mDNSResponder` as an ordinary
/// user prints "No matching processes belonging to you were found" and exits 1, so a tool
/// that assumed success would cheerfully report a flushed DNS cache while having flushed
/// nothing at all.
public struct OptimizeService: Sendable {
    private let runner: CommandRunning
    private let now: @Sendable () -> Date

    public init(runner: CommandRunning = LiveCommandRunner(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.runner = runner
        self.now = now
    }

    /// Cancellation is honoured between actions, never during one. A half-run action is
    /// a state nobody could describe, so the loop finishes the one in hand and stops.
    public func run(
        actions: [OptimizationAction],
        progress: @Sendable (OptimizeProgress) -> Void = { _ in }
    ) async -> OptimizeReport {
        let startedAt = now()
        var outcomes: [OptimizationOutcome] = []
        var wasCancelled = false

        for (index, action) in actions.enumerated() {
            if Task.isCancelled {
                wasCancelled = true
                break
            }

            progress(OptimizeProgress(action: action, completed: index, total: actions.count))
            outcomes.append(perform(action))
        }

        return OptimizeReport(
            outcomes: outcomes, wasCancelled: wasCancelled,
            startedAt: startedAt, finishedAt: now()
        )
    }

    private func perform(_ action: OptimizationAction) -> OptimizationOutcome {
        // Refused rather than attempted. Running an action that cannot possibly work and
        // reporting the failure would be honest but pointless; saying why up front is
        // more use to the person reading it.
        if action.requiresAdministrator && !Privileges.isRoot {
            return OptimizationOutcome(
                action: action, succeeded: false,
                message: "Needs administrator access. Run it from the DiagClean CLI with sudo."
            )
        }

        // Every command in an action has to succeed. A partial success — the DNS cache
        // cleared but the resolver never signalled — is a failure dressed as a fix.
        for command in action.commands {
            let outcome = runner.run(command)
            guard outcome.succeeded else {
                let detail = outcome.errorOutput.isEmpty
                    ? "\(command.displayString) exited with code \(outcome.exitCode)."
                    : outcome.errorOutput
                return OptimizationOutcome(action: action, succeeded: false, message: detail)
            }
        }

        return OptimizationOutcome(action: action, succeeded: true, message: successMessage(for: action))
    }

    private func successMessage(for action: OptimizationAction) -> String {
        switch action.impact {
        case .prolonged:
            // Says plainly that the work is not over, because the action returning is
            // not the same as the machine being done.
            return "Started. It continues in the background after DiagClean is closed."
        case .visible, .quiet:
            return "Done."
        }
    }
}
