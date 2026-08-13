using System.Runtime.Versioning;
using System.Text.RegularExpressions;
using DiagClean.Core.Models;
using DiagClean.Core.Shell;

namespace DiagClean.Core.Diagnostics.Mac;

/// <summary>
/// Free space needs a two-step resolution that isn't obvious from `diskutil` alone:
/// a mounted volume's "Part of Whole" points to its APFS *container* (e.g. disk3), not
/// the physical disk `diskutil list physical` enumerates (e.g. disk0) - containers sit
/// on top of a physical partition. The container's own "APFS Physical Store" field
/// (e.g. disk0s2) is what actually names the physical disk. Skipping this step and
/// matching "Part of Whole" directly against physical disk IDs silently produces zero
/// matches on every real Mac (verified live against this machine's own disk layout).
///
/// Multiple volumes also share one container's free space pool (/, /System/Volumes/VM,
/// /Preboot, /Update, /Data all reported the exact same free space on the machine this
/// was built on) - summing across volumes instead of deduping by container would
/// multiply free space several times over.
/// </summary>
[SupportedOSPlatform("macos")]
public sealed class MacDiskHealthCollector : IDiskHealthCollector
{
    public IReadOnlyList<DiskInfo> Collect()
    {
        var freeBytesByPhysicalDisk = MapFreeSpaceByPhysicalDisk();

        var listing = ShellRunner.Run("diskutil", ["list", "physical"]) ?? "";
        var diskIds = ExtractPhysicalDiskIdentifiers(listing);

        var disks = new List<DiskInfo>();
        foreach (var diskId in diskIds)
        {
            var info = ShellRunner.Run("diskutil", ["info", diskId]);
            if (info is null)
            {
                continue;
            }

            var model = MacHardwareCollector.ExtractField(info, "Device / Media Name");
            var sizeBytes = ExtractSizeBytes(info, "Disk Size");
            var smartRaw = MacHardwareCollector.ExtractField(info, "SMART Status");
            var isSolidState = string.Equals(
                MacHardwareCollector.ExtractField(info, "Solid State"), "Yes", StringComparison.OrdinalIgnoreCase);

            disks.Add(new DiskInfo
            {
                DeviceId = $"/dev/{diskId}",
                Model = string.IsNullOrEmpty(model) ? diskId : model,
                SizeGb = Math.Round(sizeBytes / (1024d * 1024 * 1024), 1),
                FreeGb = Math.Round(freeBytesByPhysicalDisk.GetValueOrDefault(diskId, 0) / (1024d * 1024 * 1024), 1),
                SmartStatus = MapSmartStatus(smartRaw),
                SmartDetail = string.IsNullOrEmpty(smartRaw) ? null : smartRaw,
                MediaType = isSolidState ? "SSD" : "HDD"
            });
        }

        return disks;
    }

    private static Dictionary<string, long> MapFreeSpaceByPhysicalDisk()
    {
        // Step 1: one free-space reading per APFS container (dedup - see class comment).
        var freeByContainer = new Dictionary<string, long>();
        foreach (var drive in DriveInfo.GetDrives())
        {
            if (!drive.IsReady || drive.DriveType != DriveType.Fixed)
            {
                continue;
            }

            var info = ShellRunner.Run("diskutil", ["info", drive.RootDirectory.FullName]);
            if (info is null)
            {
                continue;
            }

            var containerId = MacHardwareCollector.ExtractField(info, "Part of Whole");
            if (!string.IsNullOrEmpty(containerId))
            {
                freeByContainer[containerId] = drive.AvailableFreeSpace;
            }
        }

        // Step 2: resolve each container up to its backing physical disk and sum
        // (this sum is legitimate - unlike step 1, two different containers can
        // genuinely share one physical disk, e.g. a Boot Camp partition).
        var freeByPhysicalDisk = new Dictionary<string, long>();
        foreach (var (containerId, freeBytes) in freeByContainer)
        {
            var physicalId = ResolvePhysicalDiskId(containerId);
            freeByPhysicalDisk[physicalId] = freeByPhysicalDisk.GetValueOrDefault(physicalId, 0) + freeBytes;
        }

        return freeByPhysicalDisk;
    }

    private static string ResolvePhysicalDiskId(string diskOrContainerId)
    {
        var info = ShellRunner.Run("diskutil", ["info", diskOrContainerId]);
        if (info is null)
        {
            return diskOrContainerId;
        }

        var physicalStore = MacHardwareCollector.ExtractField(info, "APFS Physical Store");
        if (string.IsNullOrEmpty(physicalStore))
        {
            // Not an APFS container (e.g. plain HFS+, or already a whole disk) -
            // "Part of Whole" on a non-container disk already names itself.
            return diskOrContainerId;
        }

        // "disk0s2" -> "disk0": strip the partition suffix to get the whole-disk identifier.
        var match = Regex.Match(physicalStore, @"^(disk\d+)");
        return match.Success ? match.Groups[1].Value : diskOrContainerId;
    }

    private static List<string> ExtractPhysicalDiskIdentifiers(string listing)
    {
        var ids = new List<string>();
        foreach (var rawLine in listing.Split('\n'))
        {
            var line = rawLine.Trim();
            if (!line.StartsWith("/dev/disk", StringComparison.Ordinal))
            {
                continue;
            }

            var token = line.Split(' ', StringSplitOptions.RemoveEmptyEntries)[0];
            ids.Add(token.Replace("/dev/", ""));
        }

        return ids;
    }

    private static SmartStatus MapSmartStatus(string raw) => raw.ToLowerInvariant() switch
    {
        "verified" => SmartStatus.Healthy,
        "failing" => SmartStatus.Failing,
        "" => SmartStatus.Unknown,
        _ => SmartStatus.Unknown
    };

    private static long ExtractSizeBytes(string info, string label)
    {
        // e.g. "Disk Size:  251.0 GB (251000193024 Bytes) (exactly 490234752 512-Byte-Units)"
        var line = info.Split('\n')
            .Select(l => l.Trim())
            .FirstOrDefault(l => l.StartsWith(label + ":", StringComparison.OrdinalIgnoreCase));

        if (line is null)
        {
            return 0;
        }

        var match = Regex.Match(line, @"\((\d+)\s+Bytes\)");
        return match.Success && long.TryParse(match.Groups[1].Value, out var bytes) ? bytes : 0;
    }
}
