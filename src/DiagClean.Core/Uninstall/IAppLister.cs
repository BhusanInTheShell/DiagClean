using DiagClean.Core.Models;

namespace DiagClean.Core.Uninstall;

public interface IAppLister
{
    IReadOnlyList<InstalledApp> ListApps();
}
