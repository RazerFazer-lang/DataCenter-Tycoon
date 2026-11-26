using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace DataCenterLauncher;

/// <summary>Antwort eines laufenden Spiels oder Servers auf die Statusabfrage.</summary>
public sealed class ServerStatus
{
    public string Ip { get; init; } = "";
    public int Port { get; init; }
    public string World { get; init; } = "";
    public string Host { get; init; } = "";
    public int Players { get; init; }
    public int Max { get; init; } = 4;
    public bool Password { get; init; }
    public string Version { get; init; } = "";
    public string Build { get; init; } = "";
    public bool Dedicated { get; init; }
    public int PingMs { get; init; }
}

/// <summary>
/// Lobby ohne Internetdienst, gleiches Protokoll wie im Spiel (NetworkManager): "DCT_Q1:&lt;Nonce&gt;" per UDP an
/// Spielport + 2, Antwort ist JSON mit "magic" = "DCT_STATUS_1". Für das LAN geht die Frage als Broadcast an 7779.
/// </summary>
public static class ServerQuery
{
    public const int StatusPortOffset = 2;
    public const int DefaultPort = 7777;
    private const string Query = "DCT_Q1";
    private const string Magic = "DCT_STATUS_1";

    /// <summary>Fragt einen Server. null = keine Antwort in der Zeit.</summary>
    public static async Task<ServerStatus?> QueryAsync(string host, int port, int timeoutMs = 1500)
    {
        try
        {
            var addr = await ResolveAsync(host);
            if (addr == null) return null;
            using var udp = new UdpClient(addr.AddressFamily);
            var nonce = Random.Shared.Next(1, int.MaxValue).ToString();
            var data = Encoding.UTF8.GetBytes($"{Query}:{nonce}");
            var sw = Stopwatch.StartNew();
            await udp.SendAsync(data, data.Length, new IPEndPoint(addr, port + StatusPortOffset));
            using var cts = new CancellationTokenSource(timeoutMs);
            while (!cts.IsCancellationRequested)
            {
                var res = await udp.ReceiveAsync(cts.Token);
                var st = Parse(res.Buffer, res.RemoteEndPoint.Address.ToString(), nonce, (int)sw.ElapsedMilliseconds);
                if (st != null) return st;
            }
        }
        catch (OperationCanceledException) { }
        catch (SocketException) { }
        catch (FormatException) { }
        return null;
    }

    /// <summary>Sucht Spiele im LAN (Broadcast an Port 7779 auf allen Adaptern).</summary>
    public static async Task<List<ServerStatus>> DiscoverLanAsync(int timeoutMs = 1200)
    {
        var found = new Dictionary<string, ServerStatus>();
        try
        {
            using var udp = new UdpClient(AddressFamily.InterNetwork) { EnableBroadcast = true };
            var nonce = "lan" + Random.Shared.Next(1, 999999);
            var data = Encoding.UTF8.GetBytes($"{Query}:{nonce}");
            var sw = Stopwatch.StartNew();
            var targets = new List<IPAddress> { IPAddress.Broadcast };
            targets.AddRange(SubnetBroadcasts());
            foreach (var t in targets.Distinct())
            {
                try { await udp.SendAsync(data, data.Length, new IPEndPoint(t, DefaultPort + StatusPortOffset)); }
                catch (SocketException) { }
            }
            using var cts = new CancellationTokenSource(timeoutMs);
            while (!cts.IsCancellationRequested)
            {
                var res = await udp.ReceiveAsync(cts.Token);
                var st = Parse(res.Buffer, res.RemoteEndPoint.Address.ToString(), nonce, (int)sw.ElapsedMilliseconds);
                if (st != null) found[$"{st.Ip}:{st.Port}"] = st;
            }
        }
        catch (OperationCanceledException) { }
        catch (SocketException) { }
        return found.Values.OrderBy(s => s.World).ToList();
    }

    private static ServerStatus? Parse(byte[] buf, string ip, string nonce, int ping)
    {
        if (buf.Length == 0 || buf.Length > 512) return null;
        try
        {
            using var doc = JsonDocument.Parse(buf);
            var r = doc.RootElement;
            if (r.ValueKind != JsonValueKind.Object || Str(r, "magic") != Magic || Str(r, "nonce") != nonce) return null;
            int port = Int(r, "port", 0);
            if (port < 1 || port > 65535) return null;
            return new ServerStatus
            {
                Ip = ip,
                Port = port,
                World = Str(r, "world").Trim(),
                Host = Str(r, "host").Trim(),
                Players = Math.Clamp(Int(r, "players", 0), 0, 16),
                Max = Math.Clamp(Int(r, "max", 4), 1, 16),
                Password = r.TryGetProperty("password", out var pw) && pw.ValueKind == JsonValueKind.True,
                Version = Str(r, "version"),
                Build = Str(r, "build"),
                Dedicated = r.TryGetProperty("dedicated", out var dd) && dd.ValueKind == JsonValueKind.True,
                PingMs = ping,
            };
        }
        catch (JsonException) { return null; }
    }

    private static string Str(JsonElement r, string key) =>
        r.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? (v.GetString() ?? "") : "";

    private static int Int(JsonElement r, string key, int fallback) =>
        r.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var i) ? i : fallback;

    private static async Task<IPAddress?> ResolveAsync(string host)
    {
        if (IPAddress.TryParse(host.Trim(), out var ip)) return ip;
        try
        {
            var list = await Dns.GetHostAddressesAsync(host.Trim());
            return list.FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork) ?? list.FirstOrDefault();
        }
        catch (SocketException) { return null; }
        catch (ArgumentException) { return null; }
    }

    /// <summary>Gerichtete Broadcasts je Adapter (Windows schickt 255.255.255.255 sonst oft nur über einen).</summary>
    private static IEnumerable<IPAddress> SubnetBroadcasts()
    {
        var list = new List<IPAddress>();
        try
        {
            foreach (var ni in System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != System.Net.NetworkInformation.OperationalStatus.Up) continue;
                foreach (var ua in ni.GetIPProperties().UnicastAddresses)
                {
                    if (ua.Address.AddressFamily != AddressFamily.InterNetwork || ua.IPv4Mask == null) continue;
                    var a = ua.Address.GetAddressBytes();
                    var m = ua.IPv4Mask.GetAddressBytes();
                    if (a[0] == 127) continue;
                    var b = new byte[4];
                    for (int i = 0; i < 4; i++) b[i] = (byte)(a[i] | ~m[i]);
                    list.Add(new IPAddress(b));
                }
            }
        }
        catch (System.Net.NetworkInformation.NetworkInformationException) { }
        return list;
    }
}
