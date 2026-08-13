using DiagClean.Core.Models;

namespace DiagClean.Core.Optimize;

public interface IOptimizationAction
{
    string Name { get; }
    string Description { get; }
    bool RequiresElevation { get; }

    /// <summary>True if this action can take anywhere from minutes to hours (a full
    /// reindex, e.g.) - the CLI asks for separate, explicit confirmation before running
    /// one of these rather than lumping it in with the instant actions.</summary>
    bool IsSlow { get; }

    OptimizationResult Run();
}
