import Foundation
import Testing
@testable import DiagCleanKit

/// Records what it was asked to run and answers with whatever the test dictates, so the
/// service's handling of real exit codes can be pinned down without touching the machine.
private final class StubRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _executed: [MaintenanceCommand] = []
    private var outcomes: [String: CommandOutcome]

    init(failing: [String: CommandOutcome] = [:]) {
        self.outcomes = failing
    }

    var executed: [MaintenanceCommand] {
        lock.lock(); defer { lock.unlock() }
        return _executed
    }

    func run(_ command: MaintenanceCommand) -> CommandOutcome {
        lock.lock()
        _executed.append(command)
        lock.unlock()
        return outcomes[command.executable] ?? CommandOutcome(exitCode: 0)
    }
}

private func action(
    id: String = "test",
    commands: [MaintenanceCommand] = [MaintenanceCommand("/bin/true")],
    admin: Bool = false,
    impact: ActionImpact = .quiet
) -> OptimizationAction {
    OptimizationAction(
        id: id, title: "Test Action", fixes: "A thing", sideEffect: "Nothing visible",
        commands: commands, requiresAdministrator: admin, impact: impact
    )
}

@Suite("OptimizeService")
struct OptimizeServiceTests {

    @Test("reports success when every command exits cleanly")
    func reportsSuccess() async {
        let report = await OptimizeService(runner: StubRunner()).run(actions: [action()])

        #expect(report.successCount == 1)
        #expect(report.outcomes[0].message == "Done.")
    }

    /// The distinction this whole type exists for. `killall -HUP mDNSResponder` as an
    /// ordinary user prints "No matching processes belonging to you were found" and exits
    /// 1; a tool that assumed running it meant it worked would report a flushed DNS cache
    /// having flushed nothing.
    @Test("treats a non-zero exit as failure, not as success")
    func honoursExitCode() async {
        let runner = StubRunner(failing: [
            "/usr/bin/killall": CommandOutcome(
                exitCode: 1, errorOutput: "No matching processes belonging to you were found"
            )
        ])

        let report = await OptimizeService(runner: runner).run(actions: [
            action(commands: [MaintenanceCommand("/usr/bin/killall", ["-HUP", "mDNSResponder"])])
        ])

        #expect(report.failureCount == 1)
        #expect(report.outcomes[0].message.contains("No matching processes"))
    }

    /// A partial success — the DNS cache cleared but the resolver never signalled — is a
    /// failure dressed as a fix.
    @Test("an action fails if any of its commands fails")
    func allCommandsMustSucceed() async {
        let runner = StubRunner(failing: ["/usr/bin/killall": CommandOutcome(exitCode: 1)])

        let report = await OptimizeService(runner: runner).run(actions: [
            action(commands: [
                MaintenanceCommand("/usr/bin/dscacheutil", ["-flushcache"]),
                MaintenanceCommand("/usr/bin/killall", ["-HUP", "mDNSResponder"]),
            ])
        ])

        #expect(report.failureCount == 1)
    }

    @Test("stops an action at its first failing command")
    func stopsAtFirstFailure() async {
        let runner = StubRunner(failing: ["/bin/false": CommandOutcome(exitCode: 1)])

        _ = await OptimizeService(runner: runner).run(actions: [
            action(commands: [
                MaintenanceCommand("/bin/false"),
                MaintenanceCommand("/bin/true"),
            ])
        ])

        #expect(runner.executed.map(\.executable) == ["/bin/false"])
    }

    @Test("refuses an administrator action rather than running one that cannot work")
    func refusesAdminActions() async {
        let runner = StubRunner()

        let report = await OptimizeService(runner: runner).run(actions: [action(admin: true)])

        #expect(report.failureCount == 1)
        #expect(report.outcomes[0].message.contains("administrator"))
        #expect(runner.executed.isEmpty, "nothing should have been attempted")
    }

    @Test("says plainly when the work continues after the action returns")
    func prolongedActionSaysSo() async {
        let report = await OptimizeService(runner: StubRunner())
            .run(actions: [action(impact: .prolonged)])

        #expect(report.outcomes[0].message.contains("continues in the background"))
    }

    @Test("runs several actions in the order given and reports each")
    func runsInOrder() async {
        let report = await OptimizeService(runner: StubRunner()).run(actions: [
            action(id: "a", commands: [MaintenanceCommand("/bin/a")]),
            action(id: "b", commands: [MaintenanceCommand("/bin/b")]),
        ])

        #expect(report.outcomes.map(\.id) == ["a", "b"])
    }

    @Test("a cancelled run stops between actions and says it was cancelled")
    func honoursCancellation() async {
        let service = OptimizeService(runner: StubRunner())
        let actions = (0..<20).map { action(id: "\($0)") }

        let task = Task { await service.run(actions: actions) }
        task.cancel()
        let report = await task.value

        #expect(report.wasCancelled)
        #expect(report.outcomes.count < actions.count)
    }
}

@Suite("OptimizationCatalog")
struct OptimizationCatalogTests {

    /// The field the CLI does not have. An action nobody can predict the consequences of
    /// is one a technician cannot responsibly run on somebody else's machine.
    @Test("every action says what the user will notice")
    func everyActionDescribesItsSideEffect() {
        for action in OptimizationCatalog.all {
            #expect(!action.sideEffect.isEmpty, "\(action.id) must describe its side effect")
            #expect(!action.fixes.isEmpty, "\(action.id) must say what it fixes")
        }
    }

    /// Anything the user will notice is a decision they make, never one they inherit
    /// from a default.
    @Test("only quiet, unprivileged actions are ticked by default")
    func defaultSelectionIsConservative() {
        for action in OptimizationCatalog.all {
            if action.impact.isDisruptive || action.requiresAdministrator {
                #expect(!action.isSelectedByDefault, "\(action.id) must not be selected by default")
            }
        }
    }

    @Test("the Spotlight rebuild is marked as both privileged and prolonged")
    func spotlightIsFlagged() throws {
        let spotlight = try #require(OptimizationCatalog.all.first { $0.id == "rebuild-spotlight" })

        #expect(spotlight.requiresAdministrator)
        #expect(spotlight.impact == .prolonged)
        #expect(spotlight.sideEffect.contains("hours"))
    }

    /// Verified on a real Mac: dscacheutil alone succeeds as an ordinary user but the
    /// resolver signal needs root, so the action as a whole does.
    @Test("the DNS flush is marked as needing administrator access")
    func dnsFlushNeedsAdmin() throws {
        let dns = try #require(OptimizationCatalog.all.first { $0.id == "flush-dns" })

        #expect(dns.requiresAdministrator)
    }

    @Test("restarting Finder warns that it closes windows")
    func finderRestartWarnsAboutWindows() throws {
        let finder = try #require(OptimizationCatalog.all.first { $0.id == "restart-finder-dock" })

        #expect(finder.impact == .visible)
        #expect(finder.sideEffect.lowercased().contains("window"))
    }

    @Test("commands are absolute paths with separated arguments, never shell strings")
    func commandsAreNotShellStrings() {
        for action in OptimizationCatalog.all {
            for command in action.commands {
                #expect(command.executable.hasPrefix("/"), "\(action.id) must use an absolute path")
                #expect(!command.executable.contains(" "), "\(action.id) must not embed arguments in the path")
            }
        }
    }

    @Test("splits the catalogue by what this process can actually do")
    func splitsByPrivilege() {
        let available = OptimizationCatalog.available(isRoot: false)
        let unavailable = OptimizationCatalog.unavailable(isRoot: false)

        #expect(available.filter(\.requiresAdministrator).isEmpty)
        #expect(unavailable.filter { !$0.requiresAdministrator }.isEmpty)
        #expect(available.count + unavailable.count == OptimizationCatalog.all.count)
        #expect(OptimizationCatalog.available(isRoot: true).count == OptimizationCatalog.all.count)
    }
}
