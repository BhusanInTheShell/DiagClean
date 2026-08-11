using System.Management;
using System.Runtime.Versioning;
using DiagClean.Core.Models;

namespace DiagClean.Core.Diagnostics;

[SupportedOSPlatform("windows")]
public sealed class DiskHealthCollector : IDiskHealthCollector
{
    public IReadOnlyList<DiskInfo> Collect()
    {
        var failurePredictions = ReadFailurePredictions();
        var disks = new List<DiskInfo>();

        using var driveSearcher = new ManagementObjectSearcher(
            "SELECT DeviceID, Model, Size, MediaType, PNPDeviceID FROM Win32_DiskDrive");

        foreach (ManagementObject drive in driveSearcher.Get().Cast<ManagementObject>())
        {
            var pnpId = drive["PNPDeviceID"]?.ToString() ?? "";
            var sizeBytes = drive["Size"] is not null ? Convert.ToInt64(drive["Size"]) : 0L;

            var (status, detail) = MatchSmartStatus(pnpId, failurePredictions);
            var freeGb = SumFreeSpaceForDrive(drive);

            disks.Add(new DiskInfo
            {
                DeviceId = drive["DeviceID"]?.ToString() ?? "",
                Model = drive["Model"]?.ToString() ?? "",
                SizeGb = Math.Round(sizeBytes / (1024d * 1024 * 1024), 1),
                FreeGb = Math.Round(freeGb, 1),
                SmartStatus = status,
                SmartDetail = detail,
                MediaType = drive["MediaType"]?.ToString() ?? "Unknown"
            });
        }

        return disks;
    }

    private static double SumFreeSpaceForDrive(ManagementObject drive)
    {
        double freeBytes = 0;
        try
        {
            foreach (ManagementObject partition in drive.GetRelated("Win32_DiskPartition").Cast<ManagementObject>())
            {
                foreach (ManagementObject logicalDisk in partition.GetRelated("Win32_LogicalDisk").Cast<ManagementObject>())
                {
                    if (logicalDisk["FreeSpace"] is not null)
                    {
                        freeBytes += Convert.ToDouble(logicalDisk["FreeSpace"]);
                    }
                }
            }
        }
        catch (ManagementException)
        {
            // Associator query can fail on dynamic/spanned volumes - report 0 free rather than crash the collector.
        }

        return freeBytes / (1024d * 1024 * 1024);
    }

    private static Dictionary<string, bool> ReadFailurePredictions()
    {
        var predictions = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var searcher = new ManagementObjectSearcher(
                @"root\WMI", "SELECT InstanceName, PredictFailure FROM MSStorageDriver_FailurePredictStatus");
            foreach (ManagementObject mo in searcher.Get().Cast<ManagementObject>())
            {
                var instanceName = mo["InstanceName"]?.ToString() ?? "";
                predictions[instanceName] = mo["PredictFailure"] is bool b && b;
            }
        }
        catch (ManagementException)
        {
            // Predictive SMART data isn't exposed by every storage driver (common on NVMe/RAID controllers).
        }

        return predictions;
    }

    private static (SmartStatus status, string? detail) MatchSmartStatus(
        string pnpId, Dictionary<string, bool> predictions)
    {
        if (string.IsNullOrEmpty(pnpId))
        {
            return (SmartStatus.Unknown, null);
        }

        var match = predictions.Keys.FirstOrDefault(k =>
            pnpId.Contains(k, StringComparison.OrdinalIgnoreCase) ||
            k.Contains(pnpId, StringComparison.OrdinalIgnoreCase));

        if (match is null)
        {
            return (SmartStatus.Unknown, null);
        }

        var predicted = predictions[match];
        return predicted
            ? (SmartStatus.Failing, "Drive-reported predictive failure flag is set")
            : (SmartStatus.Healthy, null);
    }
}
