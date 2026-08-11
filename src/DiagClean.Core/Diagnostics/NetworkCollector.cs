using System.Net.NetworkInformation;
using System.Net.Sockets;
using DiagClean.Core.Models;

namespace DiagClean.Core.Diagnostics;

/// <summary>
/// Uses System.Net.NetworkInformation, which is cross-platform - unlike the rest of the
/// Diagnostics collectors, this one doesn't need [SupportedOSPlatform("windows")].
/// </summary>
public sealed class NetworkCollector : INetworkCollector
{
    public IReadOnlyList<NetworkAdapterInfo> Collect()
    {
        var results = new List<NetworkAdapterInfo>();

        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.NetworkInterfaceType == NetworkInterfaceType.Loopback)
            {
                continue;
            }

            var props = nic.GetIPProperties();
            var ipAddresses = props.UnicastAddresses
                .Where(a => a.Address.AddressFamily is AddressFamily.InterNetwork or AddressFamily.InterNetworkV6)
                .Select(a => a.Address.ToString())
                .ToList();

            var dnsServers = props.DnsAddresses.Select(a => a.ToString()).ToList();
            var gateway = props.GatewayAddresses.FirstOrDefault()?.Address.ToString();

            results.Add(new NetworkAdapterInfo
            {
                Name = nic.Name,
                Description = nic.Description,
                MacAddress = FormatMac(nic.GetPhysicalAddress()),
                IpAddresses = ipAddresses,
                DnsServers = dnsServers,
                Gateway = gateway,
                IsUp = nic.OperationalStatus == OperationalStatus.Up
            });
        }

        return results;
    }

    private static string FormatMac(PhysicalAddress address)
    {
        var bytes = address.GetAddressBytes();
        return bytes.Length == 0 ? "" : string.Join(":", bytes.Select(b => b.ToString("X2")));
    }
}
