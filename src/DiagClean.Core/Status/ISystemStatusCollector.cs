using DiagClean.Core.Models;

namespace DiagClean.Core.Status;

public interface ISystemStatusCollector
{
    /// <summary>Blocks for roughly a second while sampling rate-based metrics (CPU,
    /// disk I/O, network throughput all need two samples over an interval to compute a
    /// rate) - callers driving a live-refreshing display should call this directly in
    /// their own refresh loop rather than adding an extra sleep on top.</summary>
    SystemStatusSnapshot Collect();
}
