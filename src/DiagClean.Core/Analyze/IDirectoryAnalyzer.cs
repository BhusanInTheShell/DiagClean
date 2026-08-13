using DiagClean.Core.Models;

namespace DiagClean.Core.Analyze;

public interface IDirectoryAnalyzer
{
    /// <summary>Immediate children (subdirectories and files) of <paramref name="path"/>,
    /// each with its full recursive size for directories, sorted largest first.</summary>
    IReadOnlyList<DiskEntry> GetChildren(string path);
}
