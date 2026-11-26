using System.Diagnostics;
using System.Globalization;
using System.IO.Compression;
using System.Text;
using DataCenterLauncher;

namespace DataCenterLauncher.DeltaTool;

// Kommandozeile für kleine Updates. Wird vom Release-Skript aufgerufen, darum:
// feste Befehle, Exit-Code 0 = ok / 1 = Fehler, und als letzte Zeile immer eine Zusammenfassung
// ("DELTA OK ..." oder "DELTA FEHLER ...").
internal static class Program
{
    private const string Usage =
        "DeltaTool – kleine Updates für DataCenter Tycoon\n" +
        "\n" +
        "  DeltaTool make  --old <ordner|zip> --new <ordner|zip> --out <datei> --from <version> --to <version>\n" +
        "                  [--quality <0-11>] [--no-sha256]\n" +
        "  DeltaTool apply --delta <datei> --install <ordner> --out <ordner>\n" +
        "  DeltaTool info  --delta <datei>\n" +
        "  DeltaTool selftest\n" +
        "\n" +
        "make schreibt neben die .delta-Datei auch <datei>.sha256 (\"<hex>  <name>\").\n" +
        "Asset-Name im Release: DataCenterTycoon-v<to>-from-v<from>-win64.delta\n";

    private static int Main(string[] args)
    {
        CultureInfo.DefaultThreadCurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

        if (args.Length == 0 || args[0] is "-h" or "--help" or "help" or "/?")
        {
            Console.WriteLine(Usage);
            return args.Length == 0 ? 1 : 0;
        }

        var cmd = args[0].ToLowerInvariant();
        try
        {
            var opts = ParseOptions(args.Skip(1).ToArray());
            return cmd switch
            {
                "make" => Make(opts),
                "apply" => Apply(opts),
                "info" => Info(opts),
                "selftest" or "--selftest" => SelfTest.Run(),
                _ => throw new ToolException($"Unbekannter Befehl \"{args[0]}\". Hilfe: DeltaTool --help")
            };
        }
        catch (Exception ex) when (ex is ToolException or DeltaPatchException)
        {
            Console.Error.WriteLine(ex.Message);
            Console.WriteLine($"DELTA FEHLER {cmd}: {ex.Message}");
            return 1;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.ToString());
            Console.WriteLine($"DELTA FEHLER {cmd}: {ex.Message}");
            return 1;
        }
    }

    // --- make ---

    private static int Make(Dictionary<string, string> o)
    {
        var oldArg = Require(o, "old");
        var newArg = Require(o, "new");
        var outFile = Path.GetFullPath(Require(o, "out"));
        var from = Require(o, "from");
        var to = Require(o, "to");
        var options = new DeltaBuildOptions();
        if (o.TryGetValue("quality", out var q))
        {
            if (!int.TryParse(q, out var qi) || qi is < 0 or > 11)
                throw new ToolException("--quality muss eine Zahl von 0 bis 11 sein.");
            options.BrotliQuality = qi;
        }
        bool writeSha = !o.ContainsKey("no-sha256");
        AllowOnly(o, "old", "new", "out", "from", "to", "quality", "no-sha256");

        var total = Stopwatch.StartNew();
        var temp = Path.Combine(Path.GetTempPath(), $"dct_deltatool_{Guid.NewGuid():N}");
        try
        {
            var prep = Stopwatch.StartNew();
            var oldDir = PrepareTree(oldArg, Path.Combine(temp, "old"), "alt");
            var newDir = PrepareTree(newArg, Path.Combine(temp, "new"), "neu");
            if (prep.Elapsed.TotalSeconds > 0.5)
                Console.WriteLine($"Entpackt in {prep.Elapsed.TotalSeconds:F1} s");

            string lastStatus = "";
            var progress = new SyncProgress(p =>
            {
                // Nur bei neuem Arbeitsschritt eine Zeile ausgeben (keine Prozent-Flut im Release-Log).
                if (p.Status != lastStatus)
                {
                    lastStatus = p.Status;
                    Console.WriteLine($"  [{p.Percent,5:F1} %] {p.Status}");
                }
            });

            var res = DeltaPatch.Build(oldDir, newDir, outFile, from, to, progress, options);

            if (writeSha)
            {
                var hex = DeltaPatch.HashFileHex(outFile);
                File.WriteAllText(outFile + ".sha256", $"{hex}  {Path.GetFileName(outFile)}\n", new UTF8Encoding(false));
            }

            var expectedName = DeltaPatch.AssetName(from, to);
            if (!string.Equals(Path.GetFileName(outFile), expectedName, StringComparison.OrdinalIgnoreCase))
                Console.WriteLine($"Hinweis: Der Launcher sucht das Asset unter dem Namen {expectedName}");

            double reusedPct = res.NewTotalBytes > 0 ? res.ReusedBytes * 100.0 / res.NewTotalBytes : 100;
            Console.WriteLine($"Neue Version:    {res.FileCount} Dateien, {Mb(res.NewTotalBytes)}");
            Console.WriteLine($"Wiederverwendet: {Mb(res.ReusedBytes)} ({reusedPct:F1} %)");
            Console.WriteLine($"Neue Bytes:      {Mb(res.PayloadRawBytes)} ungepackt, {Mb(res.PayloadBytes)} gepackt");
            Console.WriteLine($"Delta-Datei:     {outFile}");
            Console.WriteLine($"DELTA OK make {DeltaPatch.NormalizeVersion(from)}->{DeltaPatch.NormalizeVersion(to)} " +
                              $"file={Path.GetFileName(outFile)} bytes={res.DeltaBytes} ({Mb(res.DeltaBytes)}) " +
                              $"files={res.FileCount} changed={res.ChangedFileCount} removed={res.RemovedCount} " +
                              $"reused={reusedPct:F1}% build={res.Elapsed.TotalSeconds:F1}s total={total.Elapsed.TotalSeconds:F1}s");
            return 0;
        }
        finally
        {
            TryDeleteDir(temp);
        }
    }

    /// <summary>Ordner direkt nutzen, ZIP wie der Launcher entpacken (einzelner Hüllordner wird entfernt).</summary>
    private static string PrepareTree(string input, string extractTo, string label)
    {
        if (Directory.Exists(input))
            return Path.GetFullPath(input);
        if (File.Exists(input) && input.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
        {
            Console.WriteLine($"Entpacke {label}: {Path.GetFileName(input)}");
            Directory.CreateDirectory(extractTo);
            ZipFile.ExtractToDirectory(input, extractTo, overwriteFiles: true);
            var rootFiles = Directory.GetFiles(extractTo);
            var rootDirs = Directory.GetDirectories(extractTo);
            return rootFiles.Length == 0 && rootDirs.Length == 1 ? rootDirs[0] : extractTo;
        }
        throw new ToolException($"Weder Ordner noch .zip: {input}");
    }

    // --- apply ---

    private static int Apply(Dictionary<string, string> o)
    {
        var delta = Require(o, "delta");
        var install = Require(o, "install");
        var outDir = Require(o, "out");
        AllowOnly(o, "delta", "install", "out");

        int lastTen = -1;
        var progress = new SyncProgress(p =>
        {
            int ten = (int)(p.Percent / 10);
            if (ten != lastTen)
            {
                lastTen = ten;
                Console.WriteLine($"  [{p.Percent,5:F1} %] {p.Status}");
            }
        });

        var res = DeltaPatch.ApplyAsync(delta, install, outDir, progress).GetAwaiter().GetResult();
        double reusedPct = res.TotalBytes > 0 ? res.ReusedBytes * 100.0 / res.TotalBytes : 100;
        Console.WriteLine($"DELTA OK apply files={res.FileCount} bytes={res.TotalBytes} ({Mb(res.TotalBytes)}) " +
                          $"reused={reusedPct:F1}% new={res.PayloadRawBytes} time={res.Elapsed.TotalSeconds:F1}s out={Path.GetFullPath(outDir)}");
        return 0;
    }

    // --- info ---

    private static int Info(Dictionary<string, string> o)
    {
        var delta = Require(o, "delta");
        AllowOnly(o, "delta");

        var h = DeltaPatch.Verify(delta);
        long size = new FileInfo(delta).Length;
        long total = h.NewTotalBytes();
        long reused = h.ReusedBytes();
        double reusedPct = total > 0 ? reused * 100.0 / total : 100;
        var oldPaths = new HashSet<string>(h.OldFiles.Select(f => f.Path), StringComparer.OrdinalIgnoreCase);

        Console.WriteLine($"Update-Paket:    {Path.GetFileName(delta)}");
        Console.WriteLine($"Version:         v{h.From} -> v{h.To} (Format {h.Format}, erstellt {h.Created})");
        Console.WriteLine($"Paketgröße:      {Mb(size)} ({size} Bytes)");
        Console.WriteLine($"Neue Version:    {h.Files.Count} Dateien, {Mb(total)}");
        Console.WriteLine($"Wiederverwendet: {Mb(reused)} ({reusedPct:F1} %)");
        Console.WriteLine($"Neue Bytes:      {Mb(h.PayloadRawSize)} ungepackt, {Mb(h.PayloadSize)} gepackt ({h.Compression})");
        Console.WriteLine($"Stücke:          {h.ChunkMin / 1024}/{h.ChunkAvg / 1024}/{h.ChunkMax / 1024} KB (min/mittel/max)");
        Console.WriteLine("Dateien:");
        foreach (var f in h.Files)
        {
            long r = f.Parts.Where(p => p.Kind == DeltaPart.KindOld).Sum(p => p.Length);
            bool same = f.Parts.Count == 1 && f.Parts[0].Kind == DeltaPart.KindOld && f.Parts[0].Length == f.Size && f.Parts[0].Offset == 0;
            string state = f.Size == 0 ? "leer" : same ? (string.Equals(f.Parts[0].Path, f.Path, StringComparison.OrdinalIgnoreCase) ? "gleich" : "kopiert")
                : oldPaths.Contains(f.Path) ? "geändert" : "neu";
            double pct = f.Size > 0 ? r * 100.0 / f.Size : 100;
            Console.WriteLine($"  {state,-9} {Mb(f.Size),11}  {pct,5:F1} % alt  {f.Parts.Count,5} Teile  {f.Path}");
        }
        foreach (var r in h.Removed)
            Console.WriteLine($"  {"entfernt",-9} {"",11}  {"",5}        {"",5}        {r}");

        Console.WriteLine($"DELTA OK info {h.From}->{h.To} bytes={size} ({Mb(size)}) files={h.Files.Count} removed={h.Removed.Count} " +
                          $"new_total={total} reused={reusedPct:F1}% payload_raw={h.PayloadRawSize} payload={h.PayloadSize}");
        return 0;
    }

    // --- Hilfen ---

    private static Dictionary<string, string> ParseOptions(string[] args)
    {
        var o = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        for (int i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if (!a.StartsWith("--", StringComparison.Ordinal))
                throw new ToolException($"Unerwartetes Argument \"{a}\".");
            var key = a[2..];
            if (key == "no-sha256")
            {
                o[key] = "1";
                continue;
            }
            if (i + 1 >= args.Length)
                throw new ToolException($"Für --{key} fehlt der Wert.");
            o[key] = args[++i];
        }
        return o;
    }

    private static string Require(Dictionary<string, string> o, string key) =>
        o.TryGetValue(key, out var v) && !string.IsNullOrWhiteSpace(v) ? v : throw new ToolException($"--{key} fehlt.");

    private static void AllowOnly(Dictionary<string, string> o, params string[] keys)
    {
        foreach (var k in o.Keys)
        {
            if (!keys.Contains(k, StringComparer.OrdinalIgnoreCase))
                throw new ToolException($"Unbekannte Option --{k}.");
        }
    }

    internal static string Mb(long bytes) => $"{bytes / 1048576.0:F1} MB";

    internal static void TryDeleteDir(string dir)
    {
        try { if (Directory.Exists(dir)) Directory.Delete(dir, recursive: true); } catch { }
    }
}

internal sealed class ToolException(string message) : Exception(message);

/// <summary>IProgress ohne SynchronizationContext: ruft direkt auf (Konsole).</summary>
internal sealed class SyncProgress(Action<(double Percent, string Status)> onReport) : IProgress<(double Percent, string Status)>
{
    private readonly object _lock = new();
    public void Report((double Percent, string Status) value)
    {
        lock (_lock) onReport(value);
    }
}
