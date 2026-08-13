using DiagClean.Core.Models;

namespace DiagClean.Core.Optimize;

/// <summary>
/// Optimize's actions are one-shot OS commands/service refreshes, not filesystem scans
/// like Cleaning's targets - a single implementation parameterized by a delegate avoids
/// a boilerplate class per action while keeping each action's actual logic in its own
/// small, separately-testable method (see the platform-specific action list classes).
/// </summary>
public sealed class DelegateOptimizationAction : IOptimizationAction
{
    private readonly Func<OptimizationResult> _run;

    public DelegateOptimizationAction(
        string name, string description, bool requiresElevation, bool isSlow, Func<OptimizationResult> run)
    {
        Name = name;
        Description = description;
        RequiresElevation = requiresElevation;
        IsSlow = isSlow;
        _run = run;
    }

    public string Name { get; }
    public string Description { get; }
    public bool RequiresElevation { get; }
    public bool IsSlow { get; }

    public OptimizationResult Run() => _run();
}
