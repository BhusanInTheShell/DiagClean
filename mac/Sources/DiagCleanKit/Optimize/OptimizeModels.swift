import Foundation
import Darwin

/// One shell command an action runs. Kept as an explicit executable path plus separate
/// arguments — never a string to be parsed by a shell — so there is nothing to quote and
/// nothing to inject. It is also shown verbatim in the confirmation: a technician about
/// to restart somebody's Finder is entitled to see exactly what will run.
public struct MaintenanceCommand: Sendable, Equatable {
    public let executable: String
    public let arguments: [String]

    public init(_ executable: String, _ arguments: [String] = []) {
        self.executable = executable
        self.arguments = arguments
    }

    public var displayString: String {
        ([executable] + arguments)
            .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
            .joined(separator: " ")
    }
}

public struct CommandOutcome: Sendable, Equatable {
    public let exitCode: Int32
    public let errorOutput: String

    public var succeeded: Bool { exitCode == 0 }

    public init(exitCode: Int32, errorOutput: String = "") {
        self.exitCode = exitCode
        self.errorOutput = errorOutput
    }
}

/// How long an action ties up the machine, and how much it interrupts.
public enum ActionImpact: Sendable, Equatable {
    /// Finishes in seconds, nothing visible beyond the fix itself.
    case quiet
    /// Finishes quickly but the user will see something happen.
    case visible
    /// Keeps running long after the action returns, degrading the machine meanwhile.
    case prolonged

    public var isDisruptive: Bool { self != .quiet }
}

public struct OptimizationAction: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// The symptom this actually resolves, in the words a technician would use with the
    /// person whose machine it is.
    public let fixes: String
    /// What the person sitting in front of the machine will notice. This is the field
    /// the CLI does not have, and the one that matters most: "restarts Finder" reads as
    /// harmless right up until it closes the twelve windows somebody was working in.
    public let sideEffect: String
    public let commands: [MaintenanceCommand]
    public let requiresAdministrator: Bool
    public let impact: ActionImpact

    public init(
        id: String, title: String, fixes: String, sideEffect: String,
        commands: [MaintenanceCommand], requiresAdministrator: Bool, impact: ActionImpact
    ) {
        self.id = id
        self.title = title
        self.fixes = fixes
        self.sideEffect = sideEffect
        self.commands = commands
        self.requiresAdministrator = requiresAdministrator
        self.impact = impact
    }

    /// Only quiet actions that this process can actually carry out start ticked.
    /// Anything the user will notice is a decision they make, not one they inherit.
    public var isSelectedByDefault: Bool {
        impact == .quiet && !requiresAdministrator
    }
}

public struct OptimizationOutcome: Sendable, Equatable, Identifiable {
    public let id: String
    public let action: OptimizationAction
    public let succeeded: Bool
    public let message: String

    public init(action: OptimizationAction, succeeded: Bool, message: String) {
        self.id = action.id
        self.action = action
        self.succeeded = succeeded
        self.message = message
    }
}

public struct OptimizeReport: Sendable {
    public let outcomes: [OptimizationOutcome]
    public let wasCancelled: Bool
    public let startedAt: Date
    public let finishedAt: Date

    public var successCount: Int { outcomes.filter(\.succeeded).count }
    public var failureCount: Int { outcomes.filter { !$0.succeeded }.count }

    public init(outcomes: [OptimizationOutcome], wasCancelled: Bool, startedAt: Date, finishedAt: Date) {
        self.outcomes = outcomes
        self.wasCancelled = wasCancelled
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

/// Whether this process could carry out an administrator action if asked.
///
/// DiagClean deliberately ships no privilege-escalation path. Prompting for an admin
/// password and running a shell as root is a security-sensitive mechanism, and shipping
/// one that has not been exercised properly is worse than shipping a smaller feature.
/// Actions needing root are shown, labelled, and left unavailable, with the CLI named as
/// the way to run them — rather than offered as a checkbox that is certain to fail.
public enum Privileges {
    public static var isRoot: Bool { geteuid() == 0 }
}
