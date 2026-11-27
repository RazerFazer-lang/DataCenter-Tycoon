using System.Buffers;
using System.Buffers.Binary;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace DataCenterLauncher;

// Kleine Updates (REL-02): Nur die Teile laden, die sich zwischen zwei Versionen geändert haben.
// Reines .NET ohne WPF, damit Launcher und tools/delta (DeltaTool) dieselbe Datei nutzen.
//
// Dateiaufbau (.delta):
//   8 Bytes  Magic "DCTDELTA"
//   4 Bytes  Format-Version (int32, little endian)
//   4 Bytes  Länge der Kopfdaten in Bytes (int32, little endian)
//  32 Bytes  SHA-256 der Kopfdaten
//   n Bytes  Kopfdaten als UTF-8-JSON (DeltaHeader)
//   Rest     Neue Bytes, Brotli-gepackt (in der Reihenfolge, in der Apply sie braucht)

/// <summary>Fehler beim Bauen oder Anwenden eines kleinen Updates. Die Meldung ist kurz und deutsch.</summary>
public sealed class DeltaPatchException : Exception
{
    public DeltaPatchException(string message, Exception? inner = null) : base(message, inner) { }
}

/// <summary>Kopfdaten eines kleinen Updates.</summary>
public sealed class DeltaHeader
{
    public int Format { get; set; }
    public string From { get; set; } = "";
    public string To { get; set; } = "";
    public string Created { get; set; } = "";
    public int ChunkMin { get; set; }
    public int ChunkAvg { get; set; }
    public int ChunkMax { get; set; }
    public string Compression { get; set; } = "brotli";
    /// <summary>Gepackte Größe der neuen Bytes.</summary>
    public long PayloadSize { get; set; }
    /// <summary>Ungepackte Größe der neuen Bytes.</summary>
    public long PayloadRawSize { get; set; }
    /// <summary>SHA-256 der gepackten neuen Bytes.</summary>
    public string PayloadSha256 { get; set; } = "";
    /// <summary>Alle Dateien der alten Version (Pfad, Größe, SHA-256).</summary>
    public List<DeltaOldFile> OldFiles { get; set; } = new();
    /// <summary>Alle Dateien der neuen Version mit ihrem Bauplan.</summary>
    public List<DeltaFileEntry> Files { get; set; } = new();
    /// <summary>Dateien, die es in der neuen Version nicht mehr gibt.</summary>
    public List<string> Removed { get; set; } = new();

    public long NewTotalBytes() => Files.Sum(f => f.Size);
    public long ReusedBytes() => Files.Sum(f => f.Parts.Where(p => p.Kind == DeltaPart.KindOld).Sum(p => p.Length));
}

public sealed class DeltaOldFile
{
    public string Path { get; set; } = "";
    public long Size { get; set; }
    public string Sha256 { get; set; } = "";
}

public sealed class DeltaFileEntry
{
    public string Path { get; set; } = "";
    public long Size { get; set; }
    public string Sha256 { get; set; } = "";
    public List<DeltaPart> Parts { get; set; } = new();
}

/// <summary>
/// Ein Stück einer neuen Datei: entweder Bytes aus einer alten Datei ("old": Pfad, Offset, Länge, SHA-256)
/// oder ein Bereich der neuen Bytes im Update-Paket ("delta": Offset, Länge).
/// </summary>
public sealed class DeltaPart
{
    public const string KindOld = "old";
    public const string KindDelta = "delta";

    public string Kind { get; set; } = KindDelta;
    public string? Path { get; set; }
    public long Offset { get; set; }
    public long Length { get; set; }
    public string? Sha256 { get; set; }
}

public sealed class DeltaBuildOptions
{
    /// <summary>Brotli-Stufe 0..11 (9 = guter Mittelweg aus Größe und Zeit).</summary>
    public int BrotliQuality { get; set; } = 9;
    /// <summary>Brotli-Fenster 10..24 (24 = 16 MB).</summary>
    public int BrotliWindow { get; set; } = 24;
}

public sealed record DeltaBuildResult(
    string OutFile,
    long DeltaBytes,
    int FileCount,
    int ChangedFileCount,
    int RemovedCount,
    long NewTotalBytes,
    long ReusedBytes,
    long PayloadRawBytes,
    long PayloadBytes,
    TimeSpan Elapsed);

public sealed record DeltaApplyResult(
    int FileCount,
    long TotalBytes,
    long ReusedBytes,
    long PayloadRawBytes,
    TimeSpan Elapsed);

public static class DeltaPatch
{
    public const int FormatVersion = 1;
    public const int MinChunk = 16 * 1024;
    public const int AvgChunk = 64 * 1024;
    public const int MaxChunk = 256 * 1024;

    private static readonly byte[] Magic = "DCTDELTA"u8.ToArray();
    private const int PrefixSize = 8 + 4 + 4 + 32;
    private const int MaxHeaderBytes = 64 * 1024 * 1024;

    // Gear-Hash (FastCDC): vor der Durchschnittsgröße strengere Maske (18 Bit), danach lockerere (14 Bit).
    // Geprüft werden die oberen Bits, weil die vom längsten Fenster (64 Bytes) abhängen.
    private const ulong MaskS = ~0UL << (64 - 18);
    private const ulong MaskL = ~0UL << (64 - 14);
    private static readonly ulong[] Gear = CreateGearTable();

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
        WriteIndented = false
    };

    private static readonly Regex AssetNameRegex = new(
        @"^DataCenterTycoon-v(?<to>\d+(?:\.\d+)+)-from-v(?<from>\d+(?:\.\d+)+)-win64\.delta$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    // --- NAMEN & VERSIONEN ---

    /// <summary>Name des Release-Assets, z. B. DataCenterTycoon-v3.4.0-from-v3.3.0-win64.delta</summary>
    public static string AssetName(string fromVersion, string toVersion) =>
        $"DataCenterTycoon-v{NormalizeVersion(toVersion)}-from-v{NormalizeVersion(fromVersion)}-win64.delta";

    public static bool TryParseAssetName(string name, out string fromVersion, out string toVersion)
    {
        var m = AssetNameRegex.Match(name.Trim());
        fromVersion = m.Success ? m.Groups["from"].Value : "";
        toVersion = m.Success ? m.Groups["to"].Value : "";
        return m.Success;
    }

    public static string NormalizeVersion(string? v) => (v ?? "").Trim().TrimStart('v', 'V').Trim();

    /// <summary>Vergleicht Versionen ("v3.4" == "3.4.0").</summary>
    public static bool VersionsEqual(string? a, string? b)
    {
        var x = NormalizeVersion(a);
        var y = NormalizeVersion(b);
        if (x.Length == 0 || y.Length == 0) return false;
        if (Version.TryParse(PadVersion(x), out var vx) && Version.TryParse(PadVersion(y), out var vy))
            return vx == vy;
        return string.Equals(x, y, StringComparison.OrdinalIgnoreCase);
    }

    private static string PadVersion(string v) => v.Split('.').Length == 2 ? v + ".0" : v;

    /// <summary>Liest "version" aus version.json im Ordner (oder null).</summary>
    public static string? ReadInstalledVersion(string dir)
    {
        try
        {
            var p = Path.Combine(dir, "version.json");
            if (!File.Exists(p)) return null;
            using var doc = JsonDocument.Parse(File.ReadAllText(p));
            if (doc.RootElement.TryGetProperty("version", out var v) && v.ValueKind == JsonValueKind.String)
                return NormalizeVersion(v.GetString());
        }
        catch { }
        return null;
    }

    // --- BAUEN ---

    /// <summary>
    /// Baut ein kleines Update von oldDir (Version fromVersion) nach newDir (Version toVersion).
    /// Wirft DeltaPatchException mit deutscher Meldung, wenn etwas nicht passt.
    /// </summary>
    public static DeltaBuildResult Build(
        string oldDir,
        string newDir,
        string outFile,
        string fromVersion,
        string toVersion,
        IProgress<(double Percent, string Status)>? progress = null,
        DeltaBuildOptions? options = null,
        CancellationToken ct = default)
    {
        options ??= new DeltaBuildOptions();
        var sw = Stopwatch.StartNew();
        var from = NormalizeVersion(fromVersion);
        var to = NormalizeVersion(toVersion);
        if (from.Length == 0 || to.Length == 0)
            throw new DeltaPatchException("Von- und Zu-Version müssen angegeben werden.");
        if (!Directory.Exists(oldDir))
            throw new DeltaPatchException($"Alter Ordner nicht gefunden: {oldDir}");
        if (!Directory.Exists(newDir))
            throw new DeltaPatchException($"Neuer Ordner nicht gefunden: {newDir}");
        if (options.BrotliQuality is < 0 or > 11)
            throw new DeltaPatchException("Brotli-Stufe muss zwischen 0 und 11 liegen.");
        if (options.BrotliWindow is < 10 or > 24)
            throw new DeltaPatchException("Brotli-Fenster muss zwischen 10 und 24 liegen.");

        CheckTreeVersion(oldDir, from, "alte");
        CheckTreeVersion(newDir, to, "neue");

        var oldList = ListFiles(oldDir);
        var newList = ListFiles(newDir);
        if (newList.Count == 0)
            throw new DeltaPatchException("Der neue Ordner ist leer.");
        long oldTotal = oldList.Sum(f => f.Size);
        long newTotal = newList.Sum(f => f.Size);
        long workTotal = Math.Max(1, oldTotal + newTotal * 2);
        long workDone = 0;

        // 1) Alte Dateien in Stücke teilen und merken, wo welches Stück liegt.
        var globalIndex = new Dictionary<Hash256, ChunkLoc>();
        var posIndex = new Dictionary<(int File, long Offset), (Hash256 Hash, int Length)>();
        var oldEntries = new List<DeltaOldFile>(oldList.Count);
        var oldByContent = new Dictionary<string, int>(StringComparer.Ordinal);
        var oldByPath = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        for (int fi = 0; fi < oldList.Count; fi++)
        {
            var (rel, full, size) = oldList[fi];
            progress?.Report((workDone * 98.0 / workTotal, $"Zerlege alte Datei {rel}"));
            using var fileHash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            int fileIdx = fi;
            ChunkFile(full, fileHash, (offset, data) =>
            {
                var h = Hash256.Of(data);
                globalIndex.TryAdd(h, new ChunkLoc(fileIdx, offset, data.Length));
                posIndex[(fileIdx, offset)] = (h, data.Length);
            }, ct);
            var hex = Convert.ToHexStringLower(fileHash.GetHashAndReset());
            oldEntries.Add(new DeltaOldFile { Path = rel, Size = size, Sha256 = hex });
            oldByContent.TryAdd($"{hex}:{size}", fi);
            oldByPath[rel] = fi;
            workDone += size;
        }

        // 2) Neue Dateien zusammensetzen: vorhandene Stücke wiederverwenden, Rest in die neuen Bytes.
        var outFull = Path.GetFullPath(outFile);
        var outDirName = Path.GetDirectoryName(outFull);
        if (!string.IsNullOrEmpty(outDirName))
            Directory.CreateDirectory(outDirName);
        var tmpPayload = outFull + ".payload.tmp";
        var tmpOut = outFull + ".tmp";

        var files = new List<DeltaFileEntry>(newList.Count);
        long reused = 0;
        int changed = 0;
        long payloadRaw;

        try
        {
            using (var payloadFs = new FileStream(tmpPayload, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16))
            using (var writer = new BrotliWriter(payloadFs, options.BrotliQuality, options.BrotliWindow))
            {
                foreach (var (rel, full, size) in newList)
                {
                    ct.ThrowIfCancellationRequested();
                    progress?.Report((workDone * 98.0 / workTotal, $"Vergleiche neue Datei {rel}"));
                    var hex = HashFileHex(full, ct);
                    workDone += size;
                    var entry = new DeltaFileEntry { Path = rel, Size = size, Sha256 = hex };
                    files.Add(entry);
                    if (size == 0)
                        continue;

                    // Ganze Datei unverändert (gleicher Pfad bevorzugt, sonst gleiche Datei unter anderem Namen)?
                    int match = -1;
                    if (oldByPath.TryGetValue(rel, out var samePath)
                        && oldEntries[samePath].Size == size && oldEntries[samePath].Sha256 == hex)
                        match = samePath;
                    else if (oldByContent.TryGetValue($"{hex}:{size}", out var other))
                        match = other;

                    if (match >= 0)
                    {
                        entry.Parts.Add(new DeltaPart
                        {
                            Kind = DeltaPart.KindOld,
                            Path = oldEntries[match].Path,
                            Offset = 0,
                            Length = size,
                            Sha256 = hex
                        });
                        reused += size;
                        workDone += size;
                        continue;
                    }

                    changed++;
                    var builder = new PartBuilder(oldEntries, writer);
                    ChunkFile(full, null, (offset, data) =>
                    {
                        var h = Hash256.Of(data);
                        ChunkLoc? loc = null;
                        // Erst schauen, ob das Stück direkt hinter dem letzten wiederverwendeten liegt (lange Läufe).
                        if (builder.InOldRun
                            && posIndex.TryGetValue((builder.OldFile, builder.NextOldOffset), out var next)
                            && next.Hash == h && next.Length == data.Length)
                            loc = new ChunkLoc(builder.OldFile, builder.NextOldOffset, data.Length);
                        else if (globalIndex.TryGetValue(h, out var g) && g.Length == data.Length)
                            loc = g;

                        if (loc is { } l)
                        {
                            builder.AddOld(l, data);
                            reused += data.Length;
                        }
                        else
                        {
                            builder.AddNew(data);
                        }
                    }, ct);
                    builder.Flush();
                    entry.Parts = builder.Parts;
                    workDone += size;
                }

                progress?.Report((99, "Packe neue Bytes..."));
                writer.Finish();
                payloadRaw = writer.RawBytes;
            }

            var payloadSize = new FileInfo(tmpPayload).Length;
            var payloadHash = HashFileHex(tmpPayload, ct);
            var newPaths = new HashSet<string>(newList.Select(f => f.Rel), StringComparer.OrdinalIgnoreCase);

            var header = new DeltaHeader
            {
                Format = FormatVersion,
                From = from,
                To = to,
                Created = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"),
                ChunkMin = MinChunk,
                ChunkAvg = AvgChunk,
                ChunkMax = MaxChunk,
                Compression = "brotli",
                PayloadSize = payloadSize,
                PayloadRawSize = payloadRaw,
                PayloadSha256 = payloadHash,
                OldFiles = oldEntries,
                Files = files,
                Removed = oldEntries.Select(o => o.Path).Where(p => !newPaths.Contains(p)).ToList()
            };

            var headerBytes = JsonSerializer.SerializeToUtf8Bytes(header, JsonOpts);
            if (headerBytes.Length > MaxHeaderBytes)
                throw new DeltaPatchException("Kopfdaten zu groß.");

            using (var outFs = new FileStream(tmpOut, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16))
            {
                Span<byte> prefix = stackalloc byte[PrefixSize];
                Magic.CopyTo(prefix);
                BinaryPrimitives.WriteInt32LittleEndian(prefix[8..], FormatVersion);
                BinaryPrimitives.WriteInt32LittleEndian(prefix[12..], headerBytes.Length);
                SHA256.HashData(headerBytes, prefix[16..]);
                outFs.Write(prefix);
                outFs.Write(headerBytes);
                using var payloadIn = new FileStream(tmpPayload, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16, FileOptions.SequentialScan);
                payloadIn.CopyTo(outFs, 1 << 20);
            }

            File.Move(tmpOut, outFull, overwrite: true);
            var deltaBytes = new FileInfo(outFull).Length;
            progress?.Report((100, "Fertig."));
            return new DeltaBuildResult(outFull, deltaBytes, files.Count, changed, header.Removed.Count,
                newTotal, reused, payloadRaw, payloadSize, sw.Elapsed);
        }
        catch (Exception ex) when (ex is not DeltaPatchException and not OperationCanceledException)
        {
            throw new DeltaPatchException($"Kleines Update konnte nicht gebaut werden: {ex.Message}", ex);
        }
        finally
        {
            TryDeleteFile(tmpPayload);
            TryDeleteFile(tmpOut);
        }
    }

    private static void CheckTreeVersion(string dir, string expected, string label)
    {
        var v = ReadInstalledVersion(dir);
        if (v != null && !VersionsEqual(v, expected))
            throw new DeltaPatchException($"Die {label} version.json sagt v{v}, angegeben ist v{expected}.");
    }

    private sealed class PartBuilder
    {
        private readonly List<DeltaOldFile> _old;
        private readonly BrotliWriter _writer;
        private int _kind; // 0 = nichts, 1 = alt, 2 = neu
        private long _runStart;
        private long _runLen;
        private IncrementalHash? _runHash;

        public List<DeltaPart> Parts { get; } = new();
        public int OldFile { get; private set; } = -1;
        public long NextOldOffset { get; private set; }
        public bool InOldRun => _kind == 1;

        public PartBuilder(List<DeltaOldFile> old, BrotliWriter writer)
        {
            _old = old;
            _writer = writer;
        }

        public void AddOld(ChunkLoc loc, ReadOnlySpan<byte> data)
        {
            if (!(_kind == 1 && OldFile == loc.File && NextOldOffset == loc.Offset))
            {
                Flush();
                _kind = 1;
                OldFile = loc.File;
                _runStart = loc.Offset;
                _runLen = 0;
                _runHash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            }
            // Die Bytes sind laut SHA-256 identisch mit den alten, darum reicht es, die neuen zu hashen.
            _runHash!.AppendData(data);
            _runLen += data.Length;
            NextOldOffset = loc.Offset + data.Length;
        }

        public void AddNew(ReadOnlySpan<byte> data)
        {
            if (_kind != 2)
            {
                Flush();
                _kind = 2;
                _runStart = _writer.RawBytes;
                _runLen = 0;
            }
            _writer.Write(data);
            _runLen += data.Length;
        }

        public void Flush()
        {
            if (_kind == 1 && _runHash != null)
            {
                Parts.Add(new DeltaPart
                {
                    Kind = DeltaPart.KindOld,
                    Path = _old[OldFile].Path,
                    Offset = _runStart,
                    Length = _runLen,
                    Sha256 = Convert.ToHexStringLower(_runHash.GetHashAndReset())
                });
                _runHash.Dispose();
                _runHash = null;
            }
            else if (_kind == 2)
            {
                Parts.Add(new DeltaPart { Kind = DeltaPart.KindDelta, Offset = _runStart, Length = _runLen });
            }
            _kind = 0;
            OldFile = -1;
        }
    }

    // --- ANWENDEN ---

    /// <summary>
    /// Baut die neue Version in outDir aus den Dateien in installDir und den neuen Bytes im Update-Paket.
    /// Prüft Version, jedes wiederverwendete Stück und jede fertige Datei. Bei einem Fehler wird outDir
    /// wieder entfernt und eine DeltaPatchException (deutsche Meldung) geworfen. installDir bleibt unverändert.
    /// </summary>
    public static Task<DeltaApplyResult> ApplyAsync(
        string deltaFile,
        string installDir,
        string outDir,
        IProgress<(double Percent, string Status)>? progress = null,
        CancellationToken ct = default)
    {
        return Task.Run(() => Apply(deltaFile, installDir, outDir, progress, ct), ct);
    }

    /// <summary>Liest und prüft die Kopfdaten (Magic, Format, SHA-256, Länge).</summary>
    public static DeltaHeader ReadHeader(string deltaFile)
    {
        try
        {
            using var fs = new FileStream(deltaFile, FileMode.Open, FileAccess.Read, FileShare.Read);
            return ReadHeaderCore(fs, out _);
        }
        catch (Exception ex) when (ex is not DeltaPatchException)
        {
            throw new DeltaPatchException($"Update-Paket konnte nicht gelesen werden: {ex.Message}", ex);
        }
    }

    /// <summary>Prüft Kopfdaten und die Prüfsumme der gepackten neuen Bytes (ohne etwas zu schreiben).</summary>
    public static DeltaHeader Verify(string deltaFile, CancellationToken ct = default)
    {
        try
        {
            using var fs = new FileStream(deltaFile, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16);
            var header = ReadHeaderCore(fs, out long payloadStart);
            fs.Position = payloadStart;
            if (!HashEquals(HashStreamToEnd(fs, ct), header.PayloadSha256))
                throw new DeltaPatchException("Update-Paket ist beschädigt (Prüfsumme der Daten stimmt nicht).");
            return header;
        }
        catch (Exception ex) when (ex is not DeltaPatchException and not OperationCanceledException)
        {
            throw new DeltaPatchException($"Update-Paket konnte nicht gelesen werden: {ex.Message}", ex);
        }
    }

    private static byte[] HashStreamToEnd(Stream s, CancellationToken ct)
    {
        using var h = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var buf = ArrayPool<byte>.Shared.Rent(1 << 20);
        try
        {
            int r;
            while ((r = s.Read(buf, 0, buf.Length)) > 0)
            {
                ct.ThrowIfCancellationRequested();
                h.AppendData(buf, 0, r);
            }
        }
        finally { ArrayPool<byte>.Shared.Return(buf); }
        return h.GetHashAndReset();
    }

    private static DeltaHeader ReadHeaderCore(FileStream fs, out long payloadStart)
    {
        Span<byte> prefix = stackalloc byte[PrefixSize];
        if (fs.Length < PrefixSize)
            throw new DeltaPatchException("Update-Paket ist beschädigt (zu kurz).");
        fs.ReadExactly(prefix);
        if (!prefix[..8].SequenceEqual(Magic))
            throw new DeltaPatchException("Das ist kein Update-Paket von DataCenter Together.");
        int format = BinaryPrimitives.ReadInt32LittleEndian(prefix[8..]);
        if (format != FormatVersion)
            throw new DeltaPatchException($"Update-Paket hat ein unbekanntes Format (v{format}). Bitte den Launcher aktualisieren.");
        int headerLen = BinaryPrimitives.ReadInt32LittleEndian(prefix[12..]);
        if (headerLen <= 0 || headerLen > MaxHeaderBytes || PrefixSize + (long)headerLen > fs.Length)
            throw new DeltaPatchException("Update-Paket ist beschädigt (Kopfdaten-Länge).");

        var headerBytes = new byte[headerLen];
        fs.ReadExactly(headerBytes);
        Span<byte> actual = stackalloc byte[32];
        SHA256.HashData(headerBytes, actual);
        if (!actual.SequenceEqual(prefix[16..48]))
            throw new DeltaPatchException("Update-Paket ist beschädigt (Prüfsumme der Kopfdaten stimmt nicht).");

        DeltaHeader? header;
        try { header = JsonSerializer.Deserialize<DeltaHeader>(headerBytes, JsonOpts); }
        catch (JsonException ex) { throw new DeltaPatchException("Update-Paket ist beschädigt (Kopfdaten unlesbar).", ex); }
        if (header == null || header.Format != format)
            throw new DeltaPatchException("Update-Paket ist beschädigt (Kopfdaten unvollständig).");

        payloadStart = PrefixSize + headerLen;
        if (header.PayloadSize < 0 || payloadStart + header.PayloadSize != fs.Length)
            throw new DeltaPatchException("Update-Paket ist unvollständig (Dateigröße stimmt nicht).");
        return header;
    }

    private static DeltaApplyResult Apply(
        string deltaFile,
        string installDir,
        string outDir,
        IProgress<(double Percent, string Status)>? progress,
        CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        bool createdOut = false;
        bool touchedOut = false;
        var outRoot = Path.GetFullPath(outDir);
        var installRoot = Path.GetFullPath(installDir);

        try
        {
            if (!File.Exists(deltaFile))
                throw new DeltaPatchException("Update-Paket nicht gefunden.");
            if (!Directory.Exists(installRoot))
                throw new DeltaPatchException("Spielordner nicht gefunden.");
            if (string.Equals(Path.TrimEndingDirectorySeparator(outRoot), Path.TrimEndingDirectorySeparator(installRoot), StringComparison.OrdinalIgnoreCase))
                throw new DeltaPatchException("Zielordner darf nicht der Spielordner sein.");

            using var fs = new FileStream(deltaFile, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16);
            progress?.Report((0, "Prüfe Update-Paket..."));
            var header = ReadHeaderCore(fs, out long payloadStart);

            var installed = ReadInstalledVersion(installRoot);
            if (installed == null)
                throw new DeltaPatchException("Im Spielordner fehlt version.json.");
            if (!VersionsEqual(installed, header.From))
                throw new DeltaPatchException($"Installiert ist v{installed}, das kleine Update braucht v{header.From}.");

            // Gepackte neue Bytes prüfen, bevor irgendetwas geschrieben wird.
            fs.Position = payloadStart;
            if (!HashEquals(HashStreamToEnd(fs, ct), header.PayloadSha256))
                throw new DeltaPatchException("Update-Paket ist beschädigt (Prüfsumme der Daten stimmt nicht).");

            // Kopfdaten auf Plausibilität prüfen und alte Dateien vorab ansehen (vorhanden, Größe).
            var oldSizes = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
            foreach (var o in header.OldFiles)
                oldSizes[o.Path] = o.Size;
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var checkedOld = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            long expectedPayload = 0;
            foreach (var f in header.Files)
            {
                SafeJoin(outRoot, f.Path);
                if (!seen.Add(f.Path) || f.Size < 0)
                    throw new DeltaPatchException("Update-Paket ist beschädigt (Dateiliste).");
                long sum = 0;
                foreach (var p in f.Parts)
                {
                    if (p.Length <= 0 || p.Offset < 0)
                        throw new DeltaPatchException("Update-Paket ist beschädigt (Bauplan).");
                    sum += p.Length;
                    if (p.Kind == DeltaPart.KindOld)
                    {
                        if (string.IsNullOrEmpty(p.Path) || string.IsNullOrEmpty(p.Sha256) || !oldSizes.TryGetValue(p.Path, out var oldSize))
                            throw new DeltaPatchException("Update-Paket ist beschädigt (Bauplan).");
                        if (p.Offset + p.Length > oldSize)
                            throw new DeltaPatchException("Update-Paket ist beschädigt (Bauplan).");
                        if (checkedOld.Add(p.Path))
                        {
                            var oldFull = SafeJoin(installRoot, p.Path);
                            var info = new FileInfo(oldFull);
                            if (!info.Exists)
                                throw new DeltaPatchException($"Datei fehlt im Spielordner: {p.Path}");
                            if (info.Length != oldSize)
                                throw new DeltaPatchException($"Datei im Spielordner wurde verändert: {p.Path}");
                        }
                    }
                    else if (p.Kind == DeltaPart.KindDelta)
                    {
                        if (p.Offset != expectedPayload)
                            throw new DeltaPatchException("Update-Paket ist beschädigt (Bauplan).");
                        expectedPayload += p.Length;
                    }
                    else
                    {
                        throw new DeltaPatchException("Update-Paket ist beschädigt (unbekannter Teil).");
                    }
                }
                if (sum != f.Size)
                    throw new DeltaPatchException("Update-Paket ist beschädigt (Dateigröße im Bauplan).");
            }
            if (expectedPayload != header.PayloadRawSize)
                throw new DeltaPatchException("Update-Paket ist beschädigt (Datenlänge).");

            // Zielordner vorbereiten (muss leer sein).
            if (Directory.Exists(outRoot))
            {
                if (Directory.EnumerateFileSystemEntries(outRoot).Any())
                    throw new DeltaPatchException("Zielordner ist nicht leer.");
            }
            else
            {
                Directory.CreateDirectory(outRoot);
                createdOut = true;
            }
            touchedOut = true;

            long total = Math.Max(1, header.NewTotalBytes());
            long done = 0;
            long reused = 0;
            long payloadPos = 0;
            long lastReport = 0;
            var buf = ArrayPool<byte>.Shared.Rent(1 << 20);
            var oldHandles = new Dictionary<string, FileStream>(StringComparer.OrdinalIgnoreCase);

            try
            {
                fs.Position = payloadStart;
                using var brotli = new BrotliStream(fs, CompressionMode.Decompress, leaveOpen: true);

                foreach (var f in header.Files)
                {
                    ct.ThrowIfCancellationRequested();
                    var target = SafeJoin(outRoot, f.Path);
                    var targetDir = Path.GetDirectoryName(target);
                    if (!string.IsNullOrEmpty(targetDir))
                        Directory.CreateDirectory(targetDir);

                    using var fileHash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
                    using (var outFs = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None, 1 << 16))
                    {
                        if (f.Size > 0)
                            outFs.SetLength(f.Size);
                        foreach (var p in f.Parts)
                        {
                            long rem = p.Length;
                            if (p.Kind == DeltaPart.KindOld)
                            {
                                if (!oldHandles.TryGetValue(p.Path!, out var src))
                                {
                                    src = new FileStream(SafeJoin(installRoot, p.Path!), FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16);
                                    oldHandles[p.Path!] = src;
                                }
                                src.Position = p.Offset;
                                using var partHash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
                                while (rem > 0)
                                {
                                    int n = (int)Math.Min(buf.Length, rem);
                                    src.ReadExactly(buf, 0, n);
                                    partHash.AppendData(buf, 0, n);
                                    fileHash.AppendData(buf, 0, n);
                                    outFs.Write(buf, 0, n);
                                    rem -= n;
                                    done += n;
                                    reused += n;
                                    Report();
                                }
                                if (!HashEquals(partHash.GetHashAndReset(), p.Sha256))
                                    throw new DeltaPatchException($"Datei im Spielordner ist verändert oder beschädigt: {p.Path}");
                            }
                            else
                            {
                                while (rem > 0)
                                {
                                    int n = (int)Math.Min(buf.Length, rem);
                                    try { brotli.ReadExactly(buf, 0, n); }
                                    catch (EndOfStreamException ex) { throw new DeltaPatchException("Update-Paket ist beschädigt (Daten unvollständig).", ex); }
                                    fileHash.AppendData(buf, 0, n);
                                    outFs.Write(buf, 0, n);
                                    rem -= n;
                                    done += n;
                                    payloadPos += n;
                                    Report();
                                }
                            }
                        }
                    }

                    if (!HashEquals(fileHash.GetHashAndReset(), f.Sha256))
                        throw new DeltaPatchException($"Datei wurde falsch zusammengesetzt (Prüfsumme stimmt nicht): {f.Path}");
                }

                if (payloadPos != header.PayloadRawSize || brotli.Read(buf, 0, 1) != 0)
                    throw new DeltaPatchException("Update-Paket ist beschädigt (Datenlänge).");
            }
            finally
            {
                foreach (var h in oldHandles.Values)
                    h.Dispose();
                ArrayPool<byte>.Shared.Return(buf);
            }

            var newVer = ReadInstalledVersion(outRoot);
            if (newVer != null && !VersionsEqual(newVer, header.To))
                throw new DeltaPatchException($"Neue version.json sagt v{newVer}, erwartet war v{header.To}.");

            progress?.Report((100, "Neue Version zusammengesetzt."));
            return new DeltaApplyResult(header.Files.Count, total, reused, header.PayloadRawSize, sw.Elapsed);

            void Report()
            {
                if (progress == null || done - lastReport < (8L << 20)) return;
                lastReport = done;
                double pct = done * 100.0 / total;
                progress.Report((pct, $"Setze neue Version zusammen: {pct:F0} %"));
                ct.ThrowIfCancellationRequested();
            }
        }
        catch (Exception ex)
        {
            if (touchedOut)
                CleanupOutDir(outRoot, createdOut);
            if (ex is DeltaPatchException or OperationCanceledException)
                throw;
            if (ex is InvalidDataException)
                throw new DeltaPatchException("Update-Paket ist beschädigt (Daten nicht lesbar).", ex);
            throw new DeltaPatchException($"Kleines Update fehlgeschlagen: {ex.Message}", ex);
        }
    }

    private static void CleanupOutDir(string outRoot, bool createdOut)
    {
        try
        {
            if (!Directory.Exists(outRoot)) return;
            if (createdOut)
            {
                Directory.Delete(outRoot, recursive: true);
                return;
            }
            foreach (var d in Directory.GetDirectories(outRoot))
                Directory.Delete(d, recursive: true);
            foreach (var f in Directory.GetFiles(outRoot))
                File.Delete(f);
        }
        catch { }
    }

    // --- HILFEN ---

    /// <summary>Hängt einen relativen Pfad an root an und verhindert, dass er aus root herausführt.</summary>
    private static string SafeJoin(string root, string rel)
    {
        if (string.IsNullOrWhiteSpace(rel) || rel.Contains('\0') || rel.Contains(':') || Path.IsPathRooted(rel))
            throw new DeltaPatchException("Update-Paket ist beschädigt (ungültiger Dateipfad).");
        foreach (var seg in rel.Split('/', '\\'))
        {
            if (seg.Length == 0 || seg == "." || seg == "..")
                throw new DeltaPatchException("Update-Paket ist beschädigt (ungültiger Dateipfad).");
        }
        var rootFull = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root)) + Path.DirectorySeparatorChar;
        var full = Path.GetFullPath(Path.Combine(rootFull, rel.Replace('/', Path.DirectorySeparatorChar)));
        if (!full.StartsWith(rootFull, StringComparison.OrdinalIgnoreCase))
            throw new DeltaPatchException("Update-Paket ist beschädigt (ungültiger Dateipfad).");
        return full;
    }

    private static List<(string Rel, string Full, long Size)> ListFiles(string dir)
    {
        var root = Path.GetFullPath(dir);
        return Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)
            .Select(f => (Rel: Path.GetRelativePath(root, f).Replace('\\', '/'), Full: f, Size: new FileInfo(f).Length))
            .OrderBy(x => x.Rel, StringComparer.Ordinal)
            .ToList();
    }

    private static bool HashEquals(byte[] actual, string? expectedHex) =>
        !string.IsNullOrEmpty(expectedHex)
        && string.Equals(Convert.ToHexStringLower(actual), expectedHex, StringComparison.OrdinalIgnoreCase);

    /// <summary>SHA-256 einer Datei als Hex (klein).</summary>
    public static string HashFileHex(string path, CancellationToken ct = default)
    {
        using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16, FileOptions.SequentialScan);
        return Convert.ToHexStringLower(HashStreamToEnd(fs, ct));
    }

    private static void TryDeleteFile(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }

    // --- STÜCKE (FastCDC) ---

    private delegate void ChunkHandler(long offset, ReadOnlySpan<byte> data);

    private readonly record struct ChunkLoc(int File, long Offset, int Length);

    private readonly record struct Hash256(ulong A, ulong B, ulong C, ulong D)
    {
        public static Hash256 Of(ReadOnlySpan<byte> data)
        {
            Span<byte> h = stackalloc byte[32];
            SHA256.HashData(data, h);
            return new Hash256(
                BinaryPrimitives.ReadUInt64LittleEndian(h),
                BinaryPrimitives.ReadUInt64LittleEndian(h[8..]),
                BinaryPrimitives.ReadUInt64LittleEndian(h[16..]),
                BinaryPrimitives.ReadUInt64LittleEndian(h[24..]));
        }
    }

    private static void ChunkFile(string path, IncrementalHash? fileHash, ChunkHandler onChunk, CancellationToken ct)
    {
        var buf = ArrayPool<byte>.Shared.Rent(4 * 1024 * 1024);
        try
        {
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16, FileOptions.SequentialScan);
            int start = 0, end = 0;
            long fileOffset = 0;
            bool eof = false;
            while (true)
            {
                if (!eof && end - start < MaxChunk)
                {
                    ct.ThrowIfCancellationRequested();
                    if (start > 0)
                    {
                        Buffer.BlockCopy(buf, start, buf, 0, end - start);
                        end -= start;
                        start = 0;
                    }
                    while (end < buf.Length)
                    {
                        int r = fs.Read(buf, end, buf.Length - end);
                        if (r == 0) { eof = true; break; }
                        fileHash?.AppendData(buf, end, r);
                        end += r;
                    }
                }

                int avail = end - start;
                if (avail == 0) break;
                int cut = FindCut(buf.AsSpan(start, avail));
                onChunk(fileOffset, buf.AsSpan(start, cut));
                start += cut;
                fileOffset += cut;
            }
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buf);
        }
    }

    private static int FindCut(ReadOnlySpan<byte> d)
    {
        int n = d.Length;
        if (n <= MinChunk) return n;
        if (n > MaxChunk) n = MaxChunk;
        int normal = Math.Min(AvgChunk, n);
        var gear = Gear;
        ulong h = 0;
        int i = MinChunk;
        for (; i < normal; i++)
        {
            h = (h << 1) + gear[d[i]];
            if ((h & MaskS) == 0) return i + 1;
        }
        for (; i < n; i++)
        {
            h = (h << 1) + gear[d[i]];
            if ((h & MaskL) == 0) return i + 1;
        }
        return n;
    }

    private static ulong[] CreateGearTable()
    {
        // Feste Zufallszahlen (SplitMix64), damit gleiche Eingaben immer gleiche Stücke ergeben.
        var t = new ulong[256];
        ulong s = 0x44435444454C5441UL; // "DCTDELTA"
        for (int i = 0; i < t.Length; i++)
        {
            s += 0x9E3779B97F4A7C15UL;
            ulong z = s;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
            t[i] = z ^ (z >> 31);
        }
        return t;
    }

    // --- BROTLI ---

    private sealed class BrotliWriter : IDisposable
    {
        private BrotliEncoder _enc;
        private readonly Stream _out;
        private readonly byte[] _buf = new byte[1 << 20];
        private bool _finished;

        public long RawBytes { get; private set; }

        public BrotliWriter(Stream output, int quality, int window)
        {
            _out = output;
            _enc = new BrotliEncoder(quality, window);
        }

        public void Write(ReadOnlySpan<byte> data)
        {
            RawBytes += data.Length;
            while (true)
            {
                var st = _enc.Compress(data, _buf, out int consumed, out int written, isFinalBlock: false);
                if (written > 0) _out.Write(_buf, 0, written);
                data = data[consumed..];
                if (st == OperationStatus.InvalidData)
                    throw new InvalidOperationException("Brotli konnte die Daten nicht packen.");
                if (st == OperationStatus.Done && data.IsEmpty)
                    return;
                if (st != OperationStatus.DestinationTooSmall && consumed == 0 && written == 0)
                    throw new InvalidOperationException("Brotli kommt nicht weiter.");
            }
        }

        public void Finish()
        {
            if (_finished) return;
            while (true)
            {
                var st = _enc.Compress(ReadOnlySpan<byte>.Empty, _buf, out _, out int written, isFinalBlock: true);
                if (written > 0) _out.Write(_buf, 0, written);
                if (st == OperationStatus.Done) break;
                if (st != OperationStatus.DestinationTooSmall)
                    throw new InvalidOperationException("Brotli konnte nicht abschließen.");
            }
            _out.Flush();
            _finished = true;
        }

        public void Dispose() => _enc.Dispose();
    }
}
