using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace DataCenterLauncher;

// Absturzbericht mit einem Klick (REL-05): Erkennung, Log-Auszug, Bereinigung und GitHub-Issue-Link.
// Reines .NET ohne WPF, damit tools/delta (DeltaTool selftest) es ohne echten Absturz prüfen kann.

/// <summary>Alles, was der Bericht außer Exit-Code und Log braucht.</summary>
public sealed record CrashContext(
    string GameVersion,
    string LauncherVersion,
    string Repo,
    string WindowsVersion = "",
    string Gpu = "",
    DateTime? Time = null,
    TimeSpan? SessionLength = null,
    string DiagnosticZipName = "",
    string UserProfile = "",
    string UserName = "",
    string MachineName = "")
{
    /// <summary>Kontext für den angemeldeten Windows-Benutzer (Pfad, Name und PC-Name werden später entfernt).</summary>
    public static CrashContext ForCurrentUser(
        string gameVersion,
        string launcherVersion,
        string repo,
        string gpu = "",
        TimeSpan? sessionLength = null,
        string diagnosticZipName = "") =>
        new(gameVersion, launcherVersion, repo, CrashReport.DescribeWindows(), gpu, DateTime.Now, sessionLength,
            diagnosticZipName,
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            Environment.UserName,
            Environment.MachineName);
}

/// <summary>Ergebnis der Prüfung nach dem Spielende.</summary>
public sealed record CrashAnalysis(
    bool IsCrash,
    string Reason,
    string ErrorLine,
    string Title,
    string Body,
    string IssueUrl);

public static class CrashReport
{
    public const int MaxUrlLength = 7000;
    public const string DefaultRepo = "RazerFazer-lang/DataCenter-Tycoon";
    private const int MaxLinesBefore = 15;
    private const int MaxLinesFromCrash = 25;
    private const int MaxLineLength = 220;

    /// <summary>Text-Merkmale, die Godots Crash-Handler ins Log schreibt.</summary>
    public static readonly string[] CrashMarkers =
    [
        "CrashHandlerException",
        "Program crashed",
        "Dumping the backtrace",
    ];

    /// <summary>Trennlinie, mit der Godot den Absturz-Block einrahmt (ganze Zeile, genau 64 "=").</summary>
    public static readonly string CrashSeparator = new('=', 64);

    private static readonly Regex ErrorLineRegex = new(
        @"^\s*(?:USER SCRIPT ERROR|SCRIPT ERROR|USER ERROR|ERROR)\s*:",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    private static readonly Regex Ipv4Regex = new(
        @"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?!\d|\.\d)",
        RegexOptions.CultureInvariant);

    private static readonly Regex SecretRegex = new(
        @"(?<key>\b(?:password|passwort|passwd|pwd|kennwort|secret|token|join[_\-]?(?:token|code|key)|beitrittscode|api[_\-]?key|authorization)\b)(?<sep>\s*[:=]\s*)(?<val>""[^""]*""|'[^']*'|[^\s,;]+)",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    private static readonly Regex LongTokenRegex = new(
        @"(?<![\w/\\.\-])[A-Za-z0-9_\-+=]{32,}(?![\w/\\.\-])",
        RegexOptions.CultureInvariant);

    private static readonly Regex GpuLineRegex = new(
        @"^(?<api>[^\r\n]+?) - (?<method>[^\r\n]+?) - Using Device(?: #\d+)?:\s*(?:(?<vendor>[^\r\n]+?) - )?(?<device>[^\r\n]+?)\s*$",
        RegexOptions.Multiline | RegexOptions.CultureInvariant);

    private static readonly Regex GpuFallbackRegex = new(
        @"Using Device(?: #\d+)?:\s*(?<device>[^\r\n]+?)\s*$",
        RegexOptions.Multiline | RegexOptions.CultureInvariant);

    private static readonly Regex DigitsRegex = new(@"\d+", RegexOptions.CultureInvariant);

    // --- ERKENNUNG ---

    public static bool IsCrashMarkerLine(string line)
    {
        var t = line.Trim();
        if (t == CrashSeparator) return true;
        foreach (var m in CrashMarkers)
        {
            if (t.Contains(m, StringComparison.Ordinal)) return true;
        }
        return false;
    }

    public static bool HasCrashMarker(string? logText)
    {
        if (string.IsNullOrEmpty(logText)) return false;
        foreach (var line in SplitLines(logText))
        {
            if (IsCrashMarkerLine(line)) return true;
        }
        return false;
    }

    /// <summary>
    /// Prüft Exit-Code und Log einer Sitzung. Absturz = Exit-Code ungleich 0 oder Absturz-Merkmal im Log.
    /// Liefert bei einem Absturz fertigen Titel, Text und Issue-Link (bereinigt, Link höchstens maxUrlLength Zeichen).
    /// </summary>
    public static CrashAnalysis Analyze(int exitCode, string? logText, CrashContext ctx, int maxUrlLength = MaxUrlLength)
    {
        var log = logText ?? "";
        bool marker = HasCrashMarker(log);
        bool isCrash = exitCode != 0 || marker;
        string reason = (exitCode != 0, marker) switch
        {
            (true, true) => $"Exit-Code {FormatExitCode(exitCode)} und Absturz-Meldung im Log",
            (true, false) => $"Exit-Code {FormatExitCode(exitCode)}",
            (false, true) => "Absturz-Meldung im Log",
            _ => "Normal beendet"
        };
        if (!isCrash)
            return new CrashAnalysis(false, reason, "", "", "", "");

        var (before, fromCrash) = SelectLogLines(log, ctx);
        var errorLine = FindErrorLine(before.Concat(fromCrash)) ?? $"Exit-Code {FormatExitCode(exitCode)}";
        var ver = CleanVersion(ctx.GameVersion);
        var title = Shorten(ver.Length > 0 ? $"Absturz in v{ver}: {errorLine}" : $"Absturz: {errorLine}", 120);
        var repo = string.IsNullOrWhiteSpace(ctx.Repo) ? DefaultRepo : ctx.Repo.Trim();

        // Text so lange kürzen, bis der Link passt: erst ältere Zeilen vor dem Absturz, dann das Ende des Blocks.
        var pre = new List<string>(before);
        var post = new List<string>(fromCrash);
        while (true)
        {
            var body = BuildBody(ctx, exitCode, reason, pre, post);
            var url = BuildIssueUrl(repo, title, body);
            if (url.Length <= maxUrlLength)
                return new CrashAnalysis(true, reason, errorLine, title, body, url);

            if (pre.Count > 0) pre.RemoveAt(0);
            else if (post.Count > 1) post.RemoveAt(post.Count - 1);
            else
            {
                // Notfall: Text hart abschneiden.
                var shortBody = BuildBody(ctx, exitCode, reason, [], []);
                while (shortBody.Length > 0 && BuildIssueUrl(repo, title, shortBody).Length > maxUrlLength)
                    shortBody = shortBody[..(shortBody.Length * 9 / 10)];
                return new CrashAnalysis(true, reason, errorLine, title, shortBody, BuildIssueUrl(repo, title, shortBody));
            }
        }
    }

    private static string CleanVersion(string? v) => (v ?? "").Trim().TrimStart('v', 'V').Trim();

    /// <summary>Wählt die relevanten Log-Zeilen: bis zu 15 vor dem Absturz-Block und 25 ab dort, sonst die letzten 40.</summary>
    private static (List<string> Before, List<string> FromCrash) SelectLogLines(string log, CrashContext ctx)
    {
        var lines = SplitLines(log).Where(l => l.Trim().Length > 0).ToList();
        if (lines.Count == 0) return ([], []);

        int crashIdx = lines.FindIndex(IsCrashMarkerLine);
        List<string> before, from;
        if (crashIdx >= 0)
        {
            before = lines.GetRange(Math.Max(0, crashIdx - MaxLinesBefore * 2), crashIdx - Math.Max(0, crashIdx - MaxLinesBefore * 2));
            from = lines.GetRange(crashIdx, lines.Count - crashIdx);
            before = Collapse(before);
            from = Collapse(from);
            if (before.Count > MaxLinesBefore) before = before.GetRange(before.Count - MaxLinesBefore, MaxLinesBefore);
            if (from.Count > MaxLinesFromCrash) from = from.GetRange(0, MaxLinesFromCrash);
        }
        else
        {
            const int total = MaxLinesBefore + MaxLinesFromCrash;
            before = Collapse(lines.GetRange(Math.Max(0, lines.Count - total * 2), Math.Min(lines.Count, total * 2)));
            if (before.Count > total) before = before.GetRange(before.Count - total, total);
            from = [];
        }

        return (before.Select(l => CleanLine(l, ctx)).ToList(), from.Select(l => CleanLine(l, ctx)).ToList());
    }

    private static string CleanLine(string line, CrashContext ctx)
    {
        var s = Scrub(line.TrimEnd(), ctx).Replace("```", "'''");
        return s.Length > MaxLineLength ? s[..MaxLineLength] + "…" : s;
    }

    /// <summary>Fasst gleichartige Zeilen hintereinander zusammen (z. B. 30× "[n] error(-1): no debug info").</summary>
    private static List<string> Collapse(List<string> lines)
    {
        var result = new List<string>();
        int i = 0;
        while (i < lines.Count)
        {
            var key = DigitsRegex.Replace(lines[i].Trim(), "#");
            int j = i + 1;
            while (j < lines.Count && DigitsRegex.Replace(lines[j].Trim(), "#") == key) j++;
            result.Add(lines[i]);
            int skipped = j - i - 1;
            if (skipped == 1) result.Add(lines[i + 1]);
            else if (skipped > 1) result.Add($"    … ({skipped} ähnliche Zeilen ausgelassen)");
            i = j;
        }
        return result;
    }

    private static string? FindErrorLine(IEnumerable<string> lines)
    {
        string? crashLine = null;
        foreach (var l in lines)
        {
            var t = l.Trim();
            if (ErrorLineRegex.IsMatch(t))
            {
                if (t.StartsWith("ERROR:", StringComparison.OrdinalIgnoreCase))
                    t = t["ERROR:".Length..].Trim();
                return Shorten(t, 90);
            }
            if (crashLine == null && t != CrashSeparator && IsCrashMarkerLine(t))
                crashLine = Shorten(t, 90);
        }
        return crashLine;
    }

    private static string BuildBody(CrashContext ctx, int exitCode, string reason, List<string> before, List<string> fromCrash)
    {
        var sb = new StringBuilder();
        var ver = CleanVersion(ctx.GameVersion);
        var lver = CleanVersion(ctx.LauncherVersion);
        sb.Append("**Absturzbericht** (vom Launcher erstellt)\n\n");
        sb.Append("- Spiel: ").Append(ver.Length > 0 ? "v" + ver : "unbekannt").Append('\n');
        sb.Append("- Launcher: ").Append(lver.Length > 0 ? "v" + lver : "unbekannt").Append('\n');
        sb.Append("- Windows: ").Append(string.IsNullOrWhiteSpace(ctx.WindowsVersion) ? "unbekannt" : ctx.WindowsVersion).Append('\n');
        sb.Append("- Grafikkarte: ").Append(string.IsNullOrWhiteSpace(ctx.Gpu) ? "unbekannt" : Scrub(ctx.Gpu, ctx)).Append('\n');
        sb.Append("- Exit-Code: ").Append(FormatExitCode(exitCode)).Append('\n');
        sb.Append("- Zeit: ").Append((ctx.Time ?? DateTime.Now).ToString("yyyy-MM-dd HH:mm")).Append('\n');
        if (ctx.SessionLength is { } len)
            sb.Append("- Sitzung: ").Append(len.TotalMinutes < 1 ? "unter 1 Min." : $"{(int)len.TotalMinutes} Min.").Append('\n');
        sb.Append("- Erkannt durch: ").Append(reason).Append("\n\n");

        sb.Append("**Letzte Log-Zeilen** (Pfade, Namen und IPs entfernt):\n");
        if (before.Count + fromCrash.Count == 0)
        {
            sb.Append("_Kein Log dieser Sitzung gefunden._\n\n");
        }
        else
        {
            sb.Append("```text\n");
            foreach (var l in before) sb.Append(l).Append('\n');
            foreach (var l in fromCrash) sb.Append(l).Append('\n');
            sb.Append("```\n\n");
        }

        sb.Append("**Bitte die Diagnose-Datei anhängen:** ");
        if (!string.IsNullOrWhiteSpace(ctx.DiagnosticZipName))
            sb.Append('`').Append(ctx.DiagnosticZipName).Append("` liegt auf deinem Desktop (im Explorer markiert). ");
        else
            sb.Append("Die ZIP-Datei liegt auf deinem Desktop (im Explorer markiert). ");
        sb.Append("Zieh sie einfach in dieses Feld.\n\n");
        sb.Append("**Was hast du kurz vor dem Absturz gemacht?**\n\n");
        return sb.ToString();
    }

    public static string BuildIssueUrl(string repo, string title, string body, string labels = "crash")
    {
        var r = string.IsNullOrWhiteSpace(repo) ? DefaultRepo : repo.Trim().Trim('/');
        var url = $"https://github.com/{r}/issues/new?title={Uri.EscapeDataString(title)}";
        if (!string.IsNullOrWhiteSpace(labels))
            url += $"&labels={Uri.EscapeDataString(labels)}";
        return url + $"&body={Uri.EscapeDataString(body)}";
    }

    // --- BEREINIGUNG ---

    /// <summary>Entfernt Profilpfad, Benutzer- und PC-Namen, IPv4-Adressen (außer 127.0.0.1), Passwörter und Tokens.</summary>
    public static string Scrub(string text, CrashContext ctx) => Scrub(text, ctx.UserProfile, ctx.UserName, ctx.MachineName);

    /// <summary>Wie Scrub(text, ctx), aber für den angemeldeten Windows-Benutzer.</summary>
    public static string ScrubForCurrentUser(string text) =>
        Scrub(text, Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), Environment.UserName, Environment.MachineName);

    public static string Scrub(string text, string? userProfile, string? userName, string? machineName)
    {
        if (string.IsNullOrEmpty(text)) return text ?? "";
        var s = text;

        if (!string.IsNullOrWhiteSpace(userProfile))
        {
            var segs = userProfile.Trim().Split(['\\', '/'], StringSplitOptions.RemoveEmptyEntries);
            if (segs.Length >= 2)
            {
                var pattern = string.Join(@"[\\/]+", segs.Select(Regex.Escape)) + @"(?!\w)";
                s = Regex.Replace(s, pattern, "%USERPROFILE%", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
            }
        }

        if (!string.IsNullOrWhiteSpace(userName) && userName.Trim().Length >= 2)
            s = Regex.Replace(s, $@"(?<!\w){Regex.Escape(userName.Trim())}(?!\w)", "<user>", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

        if (!string.IsNullOrWhiteSpace(machineName) && machineName.Trim().Length >= 3)
            s = Regex.Replace(s, $@"(?<!\w){Regex.Escape(machineName.Trim())}(?!\w)", "<pc>", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

        s = Ipv4Regex.Replace(s, m => m.Value != "127.0.0.1" && m.Value.Split('.').All(p => int.Parse(p) <= 255)
            ? "x.x.x.x"
            : m.Value);

        s = SecretRegex.Replace(s, m => m.Groups["key"].Value + m.Groups["sep"].Value + "<entfernt>");
        s = LongTokenRegex.Replace(s, m => LooksLikeToken(m.Value) ? "<entfernt>" : m.Value);
        return s;
    }

    private static bool LooksLikeToken(string s)
    {
        int digits = 0, letters = 0;
        foreach (var c in s)
        {
            if (char.IsAsciiDigit(c)) digits++;
            else if (char.IsAsciiLetter(c)) letters++;
        }
        return digits >= 6 && letters >= 6;
    }

    // --- HILFEN ---

    public static string FormatExitCode(int code)
    {
        if (code is >= 0 and <= 255)
        {
            return code switch
            {
                0 => "0",
                1 => "1 (Fehler, z. B. im Task-Manager beendet)",
                _ => code.ToString()
            };
        }
        uint u = unchecked((uint)code);
        string? desc = u switch
        {
            0xC0000005 => "Zugriffsverletzung",
            0xC00000FD => "Stack-Überlauf",
            0xC0000409 => "Abbruch durch Sicherheitsprüfung",
            0xC0000374 => "Speicher beschädigt",
            0xC000001D => "unbekannter Prozessorbefehl",
            0xC0000094 => "Division durch null",
            0xC0000142 => "Start fehlgeschlagen (DLL)",
            0xC000013A => "mit Strg+C beendet",
            0x80000003 => "Haltepunkt",
            0xE06D7363 => "C++-Ausnahme",
            0xC0000017 => "kein Speicher mehr",
            _ => null
        };
        return desc == null ? $"{code} (0x{u:X8})" : $"{code} (0x{u:X8}, {desc})";
    }

    public static string DescribeWindows()
    {
        if (!OperatingSystem.IsWindows())
            return RuntimeInformation.OSDescription;
        var v = Environment.OSVersion.Version;
        var name = v.Major == 10 && v.Build >= 22000 ? "Windows 11"
            : v.Major == 10 ? "Windows 10"
            : $"Windows {v.Major}.{v.Minor}";
        return $"{name} (Build {v.Build}, {(Environment.Is64BitOperatingSystem ? "64-Bit" : "32-Bit")})";
    }

    /// <summary>Liest die Grafikkarte aus Godots Startzeile ("Vulkan ... - Forward+ - Using Device #0: NVIDIA - ...").</summary>
    public static string FindGpuInLog(string? log)
    {
        if (string.IsNullOrEmpty(log)) return "";
        var m = GpuLineRegex.Match(log);
        if (m.Success)
            return $"{m.Groups["device"].Value.Trim()} ({m.Groups["api"].Value.Trim()}, {m.Groups["method"].Value.Trim()})";
        var f = GpuFallbackRegex.Match(log);
        return f.Success ? f.Groups["device"].Value.Trim() : "";
    }

    /// <summary>
    /// Liest das Godot-Log, wenn es während der Sitzung geschrieben wurde (sonst null).
    /// Bei großen Logs nur das Ende (maxBytes).
    /// </summary>
    public static string? ReadSessionLog(string logPath, DateTime sessionStartUtc, int maxBytes = 1 << 20)
    {
        try
        {
            var fi = new FileInfo(logPath);
            if (!fi.Exists || fi.LastWriteTimeUtc < sessionStartUtc.AddSeconds(-5))
                return null;
            using var fs = new FileStream(logPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            long start = Math.Max(0, fs.Length - maxBytes);
            fs.Position = start;
            using var reader = new StreamReader(fs, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
            var text = reader.ReadToEnd();
            if (start > 0)
            {
                int nl = text.IndexOf('\n');
                if (nl >= 0) text = text[(nl + 1)..];
            }
            return text;
        }
        catch
        {
            return null;
        }
    }

    private static IEnumerable<string> SplitLines(string text) =>
        text.Split('\n').Select(l => l.TrimEnd('\r'));

    private static string Shorten(string s, int max)
    {
        s = s.Trim();
        return s.Length <= max ? s : s[..(max - 1)].TrimEnd() + "…";
    }
}
