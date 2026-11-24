using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace DataCenterLauncher;

public sealed record UpdateCheckResult(
    bool Success,
    bool UpdateAvailable,
    string LatestVersion,
    string DownloadUrl,
    long AssetSizeBytes,
    string Notes,
    string ReleasePageUrl = "",
    string ErrorMessage = ""
);

public sealed record LauncherUpdateCheckResult(
    bool Success,
    bool UpdateAvailable,
    string CurrentVersion,
    string LatestVersion,
    string DownloadUrl,
    long AssetSizeBytes,
    string Notes,
    string ReleasePageUrl = "",
    string ErrorMessage = ""
);

public static class UpdateService
{
    private static readonly HttpClient Http = new()
    {
        Timeout = TimeSpan.FromMinutes(10)
    };

    static UpdateService()
    {
        Http.DefaultRequestHeaders.UserAgent.ParseAdd($"DataCenterTycoonLauncher/{LauncherConfig.CurrentLauncherVersion}");
    }

    public static string NormalizeGitHubRepo(string input)
    {
        var s = input.Trim().TrimEnd('/');
        if (s.StartsWith("https://github.com/", StringComparison.OrdinalIgnoreCase))
            s = s["https://github.com/".Length..];
        else if (s.StartsWith("http://github.com/", StringComparison.OrdinalIgnoreCase))
            s = s["http://github.com/".Length..];

        var parts = s.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length >= 2)
            return $"{parts[0]}/{parts[1]}";
        return "";
    }

    /// <summary>
    /// Supports:
    /// 1) "owner/repo" or "https://github.com/owner/repo" (GitHub Releases API)
    /// 2) Full GitHub API URL "https://api.github.com/repos/owner/repo/releases/latest"
    /// 3) Direct manifest.json URL ({ "version": "0.5.0", "download_url": "https://.../game.zip", "notes": "..." })
    /// </summary>
    public static async Task<UpdateCheckResult> CheckForUpdateAsync(string manifestUrl, string installedVersion)
    {
        if (string.IsNullOrWhiteSpace(manifestUrl))
            return new UpdateCheckResult(false, false, installedVersion, "", 0, "", "",
                "Noch kein GitHub-Repo eingetragen (unter ⚙ Einstellungen festlegen).");

        try
        {
            var url = manifestUrl.Trim();
            string releasePage = "";

            if (url.StartsWith("https://github.com/", StringComparison.OrdinalIgnoreCase)
                || url.StartsWith("http://github.com/", StringComparison.OrdinalIgnoreCase))
            {
                var repo = NormalizeGitHubRepo(url);
                url = $"https://api.github.com/repos/{repo}/releases?per_page=15";
                releasePage = $"https://github.com/{repo}/releases";
            }
            else if (!url.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
                     && !url.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
                     && url.Contains('/'))
            {
                var repo = NormalizeGitHubRepo(url);
                url = $"https://api.github.com/repos/{repo}/releases?per_page=15";
                releasePage = $"https://github.com/{repo}/releases";
            }

            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            using var resp = await Http.GetAsync(url, cts.Token);
            if ((int)resp.StatusCode == 404)
            {
                return new UpdateCheckResult(false, false, installedVersion, "", 0, "", releasePage,
                    "Kein veröffentlichtes GitHub Release gefunden (404). Stelle sicher, dass das Repo öffentlich ist und ein Release existiert.");
            }
            resp.EnsureSuccessStatusCode();

            var json = await resp.Content.ReadAsStringAsync(cts.Token);
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            // Falls wir eine Release-Liste (/releases) bekommen, das neueste SPIEL-Release (ohne "launcher-" Tag) auswählen!
            if (root.ValueKind == JsonValueKind.Array)
            {
                bool foundGameRel = false;
                foreach (var rel in root.EnumerateArray())
                {
                    if (rel.TryGetProperty("draft", out var dr) && dr.ValueKind == JsonValueKind.True) continue;
                    var tag = rel.TryGetProperty("tag_name", out var tp) ? (tp.GetString() ?? "") : "";
                    if (tag.StartsWith("launcher", StringComparison.OrdinalIgnoreCase)) continue;
                    root = rel;
                    foundGameRel = true;
                    break;
                }
                if (!foundGameRel)
                {
                    return new UpdateCheckResult(false, false, installedVersion, "", 0, "", releasePage,
                        "Kein Spiel-Release auf GitHub gefunden.");
                }
            }

            string latest = installedVersion;
            string dlUrl = "";
            long assetSize = 0;
            string notes = "";

            if (root.TryGetProperty("tag_name", out var tagProp))
            {
                latest = (tagProp.GetString() ?? installedVersion).TrimStart('v', 'V');
                notes = root.TryGetProperty("body", out var bodyProp) ? (bodyProp.GetString() ?? "") : "";
                if (root.TryGetProperty("html_url", out var htmlProp))
                    releasePage = htmlProp.GetString() ?? releasePage;

                if (root.TryGetProperty("assets", out var assets) && assets.ValueKind == JsonValueKind.Array)
                {
                    foreach (var a in assets.EnumerateArray())
                    {
                        var name = a.TryGetProperty("name", out var np) ? (np.GetString() ?? "") : "";
                        if (name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)
                            && !name.Contains("launcher", StringComparison.OrdinalIgnoreCase)
                            && a.TryGetProperty("browser_download_url", out var urlProp))
                        {
                            dlUrl = urlProp.GetString() ?? "";
                            if (a.TryGetProperty("size", out var szProp))
                                assetSize = szProp.GetInt64();
                            break;
                        }
                    }
                }
            }
            else
            {
                if (root.TryGetProperty("version", out var vProp))
                    latest = (vProp.GetString() ?? installedVersion).TrimStart('v', 'V');
                if (root.TryGetProperty("download_url", out var dProp))
                    dlUrl = dProp.GetString() ?? "";
                if (root.TryGetProperty("notes", out var nProp))
                    notes = nProp.GetString() ?? "";
                if (root.TryGetProperty("size", out var szProp))
                    assetSize = szProp.GetInt64();
            }

            bool newer = string.IsNullOrWhiteSpace(installedVersion) || IsNewerVersion(latest, installedVersion);
            return new UpdateCheckResult(true, newer, latest, dlUrl, assetSize, notes, releasePage);
        }
        catch (Exception ex)
        {
            return new UpdateCheckResult(false, false, installedVersion, "", 0, "", "",
                $"Update-Check fehlgeschlagen: {ex.Message}");
        }
    }

    public static async Task<(bool Ok, string Message, string InstalledExe)> DownloadAndInstallAsync(
        string downloadUrl,
        string installDir,
        string expectedVersion,
        IProgress<(double Percent, string Status)> progress,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(downloadUrl))
            return (false, "Kein gültiger Download-Link (.zip) im Release gefunden.", "");

        var tempZip = Path.Combine(Path.GetTempPath(), $"dct_download_{Guid.NewGuid():N}.zip");

        try
        {
            progress.Report((2, "Verbinde mit Download-Server..."));
            using var resp = await Http.GetAsync(downloadUrl, HttpCompletionOption.ResponseHeadersRead, ct);
            resp.EnsureSuccessStatusCode();

            var totalBytes = resp.Content.Headers.ContentLength ?? -1L;
            var sw = Stopwatch.StartNew();

            await using (var remote = await resp.Content.ReadAsStreamAsync(ct))
            await using (var local = File.Create(tempZip))
            {
                var buffer = new byte[81920];
                long downloaded = 0;
                int read;
                long lastReportMs = 0;

                while ((read = await remote.ReadAsync(buffer, ct)) > 0)
                {
                    await local.WriteAsync(buffer.AsMemory(0, read), ct);
                    downloaded += read;

                    if (sw.ElapsedMilliseconds - lastReportMs >= 120)
                    {
                        lastReportMs = sw.ElapsedMilliseconds;
                        double mbDone = downloaded / 1048576.0;
                        double speedMbps = sw.Elapsed.TotalSeconds > 0.2 ? mbDone / sw.Elapsed.TotalSeconds : 0.0;

                        if (totalBytes > 0)
                        {
                            double mbTotal = totalBytes / 1048576.0;
                            double pct = Math.Clamp((double)downloaded / totalBytes * 84.0, 3.0, 84.0);
                            progress.Report((pct, $"Lädt herunter: {mbDone:F1} / {mbTotal:F1} MB  ({speedMbps:F1} MB/s)"));
                        }
                        else
                        {
                            progress.Report((45, $"Lädt herunter: {mbDone:F1} MB  ({speedMbps:F1} MB/s)"));
                        }
                    }
                }
            }

            var res = await InstallFromLocalZipAsync(tempZip, installDir, expectedVersion, progress, startPercent: 85.0);
            try { File.Delete(tempZip); } catch { }
            return res;
        }
        catch (OperationCanceledException)
        {
            try { File.Delete(tempZip); } catch { }
            return (false, "Download abgebrochen.", "");
        }
        catch (Exception ex)
        {
            try { File.Delete(tempZip); } catch { }
            return (false, $"Download fehlgeschlagen: {ex.Message}", "");
        }
    }

    public static async Task<(bool Ok, string Message, string InstalledExe)> InstallFromLocalZipAsync(
        string zipPath,
        string installDir,
        string versionHint,
        IProgress<(double Percent, string Status)> progress,
        double startPercent = 10.0)
    {
        if (!File.Exists(zipPath))
            return (false, "ZIP-Datei nicht gefunden.", "");

        var stagingDir = Path.Combine(Path.GetTempPath(), $"dct_extract_{Guid.NewGuid():N}");

        try
        {
            progress.Report((startPercent, "Entpacke Spiel-Dateien..."));
            await Task.Run(() =>
            {
                Directory.CreateDirectory(stagingDir);
                ZipFile.ExtractToDirectory(zipPath, stagingDir, overwriteFiles: true);

                // If ZIP contains a single wrapper folder (e.g. DataCenterTycoon/...), unwrap it cleanly
                var rootFiles = Directory.GetFiles(stagingDir);
                var rootDirs = Directory.GetDirectories(stagingDir);
                string sourceRoot = (rootFiles.Length == 0 && rootDirs.Length == 1) ? rootDirs[0] : stagingDir;

                progress.Report((startPercent + (96.0 - startPercent) * 0.5, "Installiere Spiel in Zielordner..."));

                // Neue Version erst daneben aufbauen, dann tauschen. So bleibt die alte
                // Installation erhalten, falls Kopieren oder Tauschen fehlschlägt.
                var targetDir = Path.TrimEndingDirectorySeparator(Path.GetFullPath(installDir));
                var newDir = targetDir + ".new";
                var oldDir = targetDir + ".old";

                if (Directory.Exists(newDir))
                    Directory.Delete(newDir, recursive: true);

                CopyDirectory(sourceRoot, newDir);

                // Ensure version.json exists so launcher remembers version
                var vFile = Path.Combine(newDir, "version.json");
                if (!File.Exists(vFile) && !string.IsNullOrWhiteSpace(versionHint))
                {
                    File.WriteAllText(vFile, JsonSerializer.Serialize(new { version = versionHint }));
                }

                if (Directory.Exists(oldDir))
                    Directory.Delete(oldDir, recursive: true);

                bool hadOld = Directory.Exists(targetDir);
                if (hadOld)
                    Directory.Move(targetDir, oldDir);

                try
                {
                    Directory.Move(newDir, targetDir);
                }
                catch
                {
                    if (hadOld && !Directory.Exists(targetDir) && Directory.Exists(oldDir))
                        Directory.Move(oldDir, targetDir);
                    throw;
                }

                try { if (Directory.Exists(oldDir)) Directory.Delete(oldDir, recursive: true); } catch { }
            });

            try { Directory.Delete(stagingDir, recursive: true); } catch { }

            var exe = Directory.GetFiles(installDir, "*.exe", SearchOption.AllDirectories)
                .FirstOrDefault(f =>
                    !LauncherConfig.IsSelfExecutable(f) &&
                    !Path.GetFileName(f).Contains("console", StringComparison.OrdinalIgnoreCase) &&
                    !Path.GetFileName(f).Contains("launcher", StringComparison.OrdinalIgnoreCase));

            if (string.IsNullOrWhiteSpace(exe))
                return (false, "In der ZIP-Datei wurde keine Spiel-.exe (DataCenterTycoon.exe) gefunden!", "");

            progress.Report((100, "Installation abgeschlossen! Bereit zum Spielen."));
            return (true, "Spiel erfolgreich installiert!", exe);
        }
        catch (Exception ex)
        {
            try { if (Directory.Exists(stagingDir)) Directory.Delete(stagingDir, recursive: true); } catch { }
            return (false, $"Installation fehlgeschlagen: {ex.Message}", "");
        }
    }

    public static (bool Ok, string Message) UninstallGame(string installDir)
    {
        try
        {
            if (Directory.Exists(installDir))
                Directory.Delete(installDir, recursive: true);
            return (true, "Spiel deinstalliert. Deine Spielstände blieben sicher erhalten.");
        }
        catch (Exception ex)
        {
            return (false, $"Deinstallation fehlgeschlagen (läuft das Spiel noch?): {ex.Message}");
        }
    }

    public static async Task<(bool Ok, string Message, string ZipPath)> BuildWindowsReleaseZipAsync(
        string godotExe,
        string projectDir,
        string version,
        IProgress<(double Percent, string Status)> progress)
    {
        if (string.IsNullOrWhiteSpace(godotExe) || !File.Exists(godotExe))
            return (false, "Godot 4 .exe nicht gefunden! Bitte unter Einstellungen wählen.", "");
        if (string.IsNullOrWhiteSpace(projectDir) || !File.Exists(Path.Combine(projectDir, "project.godot")))
            return (false, "Godot Projektordner (project.godot) nicht gefunden.", "");

        var distRoot = Path.Combine(projectDir, "dist");
        var winOutDir = Path.Combine(distRoot, "windows");
        var outExe = Path.Combine(winOutDir, "DataCenterTycoon.exe");
        var outZip = Path.Combine(distRoot, $"DataCenterTycoon-v{version}-win64.zip");

        try
        {
            progress.Report((10, "Bereite Windows-Exportordner vor..."));
            if (Directory.Exists(winOutDir))
                Directory.Delete(winOutDir, recursive: true);
            Directory.CreateDirectory(winOutDir);

            progress.Report((22, "Godot 4 exportiert Windows-Build (DataCenterTycoon.exe + .pck)..."));

            var psi = new ProcessStartInfo
            {
                FileName = godotExe,
                WorkingDirectory = projectDir,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            psi.ArgumentList.Add("--headless");
            psi.ArgumentList.Add("--path");
            psi.ArgumentList.Add(projectDir);
            psi.ArgumentList.Add("--export-release");
            psi.ArgumentList.Add("Windows Desktop");
            psi.ArgumentList.Add(outExe);

            using var proc = Process.Start(psi);
            if (proc == null)
                return (false, "Godot konnte nicht gestartet werden.", "");

            var stdOutTask = proc.StandardOutput.ReadToEndAsync();
            var stdErrTask = proc.StandardError.ReadToEndAsync();
            await proc.WaitForExitAsync();

            var errText = await stdErrTask;
            var outText = await stdOutTask;

            if (proc.ExitCode != 0 || !File.Exists(outExe))
            {
                var combined = (errText + "\n" + outText).Trim();
                if (combined.Contains("export template", StringComparison.OrdinalIgnoreCase)
                    || combined.Contains("templates", StringComparison.OrdinalIgnoreCase))
                {
                    return (false,
                        "Godot Export-Vorlagen fehlen! Öffne Godot 4 → Editor → Export-Vorlagen verwalten → Herunterladen & Installieren (einmalig), dann erneut klicken.",
                        "");
                }
                var shortErr = combined.Length > 260 ? combined[^260..] : combined;
                return (false, $"Godot-Export fehlgeschlagen (Code {proc.ExitCode}): {shortErr}", "");
            }

            progress.Report((75, "Kopiere version.json & erstelle Release-ZIP..."));
            var projVer = Path.Combine(projectDir, "version.json");
            if (File.Exists(projVer))
                File.Copy(projVer, Path.Combine(winOutDir, "version.json"), overwrite: true);

            // Create custom_models folder placeholder so friends know where .glb files go
            var cmDir = Path.Combine(winOutDir, "custom_models");
            Directory.CreateDirectory(cmDir);
            var readmeModels = Path.Combine(projectDir, "assets", "models", "README_MODELS.txt");
            if (File.Exists(readmeModels))
                File.Copy(readmeModels, Path.Combine(cmDir, "README_MODELS.txt"), overwrite: true);

            await Task.Run(() =>
            {
                if (File.Exists(outZip))
                    File.Delete(outZip);
                ZipFile.CreateFromDirectory(winOutDir, outZip, CompressionLevel.Optimal, includeBaseDirectory: false);
            });

            double zipMb = new FileInfo(outZip).Length / 1048576.0;
            progress.Report((100, $"Fertig! Release-ZIP erstellt ({zipMb:F1} MB)."));
            return (true, $"Release-ZIP bereit ({zipMb:F1} MB): {Path.GetFileName(outZip)}", outZip);
        }
        catch (Exception ex)
        {
            return (false, $"Release-Build fehlgeschlagen: {ex.Message}", "");
        }
    }

    private static void CopyDirectory(string sourceDir, string destDir)
    {
        Directory.CreateDirectory(destDir);
        foreach (var file in Directory.GetFiles(sourceDir))
            File.Copy(file, Path.Combine(destDir, Path.GetFileName(file)), overwrite: true);
        foreach (var sub in Directory.GetDirectories(sourceDir))
            CopyDirectory(sub, Path.Combine(destDir, Path.GetFileName(sub)));
    }

    private static bool IsNewerVersion(string candidate, string current)
    {
        if (Version.TryParse(NormalizeVer(candidate), out var vNew)
            && Version.TryParse(NormalizeVer(current), out var vCur))
        {
            return vNew > vCur;
        }
        return !string.Equals(candidate.Trim(), current.Trim(), StringComparison.OrdinalIgnoreCase);
    }

    private static string NormalizeVer(string v)
    {
        var clean = v.Trim().TrimStart('v', 'V');
        var dashIdx = clean.IndexOf('-');
        if (dashIdx > 0) clean = clean[..dashIdx];
        var parts = clean.Split('.');
        return parts.Length == 2 ? clean + ".0" : clean;
    }

    /// <summary>
    /// Prüft automatisch, ob auf GitHub Releases oder in einem Manifest eine neuere Launcher-Version vorliegt.
    /// Unterstützt:
    /// 1) Eigene Launcher-Releases mit Tag "launcher-vX.Y.Z" (Asset .exe oder .zip)
    /// 2) Normale Releases, die ein Asset mit "launcher" im Namen enthalten (z. B. DataCenterLauncher-v1.2.0.zip)
    /// 3) Manifest-JSON mit "launcher_version" + "launcher_download_url"
    /// </summary>
    public static async Task<LauncherUpdateCheckResult> CheckForLauncherUpdateAsync(string manifestUrl, string currentLauncherVersion)
    {
        if (string.IsNullOrWhiteSpace(manifestUrl))
            return new LauncherUpdateCheckResult(false, false, currentLauncherVersion, currentLauncherVersion, "", 0, "", "",
                "Keine Update-Quelle konfiguriert.");

        try
        {
            var raw = manifestUrl.Trim();
            string repo = NormalizeGitHubRepo(raw);
            bool isGitHub = !string.IsNullOrWhiteSpace(repo)
                && (raw.Contains("github.com", StringComparison.OrdinalIgnoreCase)
                    || (!raw.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
                        && !raw.StartsWith("https://", StringComparison.OrdinalIgnoreCase)));

            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));

            if (isGitHub)
            {
                var apiUrl = $"https://api.github.com/repos/{repo}/releases?per_page=15";
                using var resp = await Http.GetAsync(apiUrl, cts.Token);
                if ((int)resp.StatusCode == 404)
                {
                    return new LauncherUpdateCheckResult(true, false, currentLauncherVersion, currentLauncherVersion, "", 0, "",
                        $"https://github.com/{repo}/releases");
                }
                resp.EnsureSuccessStatusCode();

                var json = await resp.Content.ReadAsStringAsync(cts.Token);
                using var doc = JsonDocument.Parse(json);
                if (doc.RootElement.ValueKind != JsonValueKind.Array)
                    return new LauncherUpdateCheckResult(true, false, currentLauncherVersion, currentLauncherVersion, "", 0, "",
                        $"https://github.com/{repo}/releases");

                string bestVer = currentLauncherVersion;
                string bestUrl = "";
                long bestSize = 0;
                string bestNotes = "";
                string bestPage = $"https://github.com/{repo}/releases";
                bool foundAnyLauncherRelease = false;

                foreach (var rel in doc.RootElement.EnumerateArray())
                {
                    if (rel.TryGetProperty("draft", out var dr) && dr.ValueKind == JsonValueKind.True)
                        continue;

                    var tag = rel.TryGetProperty("tag_name", out var tp) ? (tp.GetString() ?? "") : "";
                    var notes = rel.TryGetProperty("body", out var bp) ? (bp.GetString() ?? "") : "";
                    var html = rel.TryGetProperty("html_url", out var hp) ? (hp.GetString() ?? bestPage) : bestPage;
                    bool isDedicatedLauncherTag = tag.StartsWith("launcher", StringComparison.OrdinalIgnoreCase);

                    if (!rel.TryGetProperty("assets", out var assets) || assets.ValueKind != JsonValueKind.Array)
                        continue;

                    string candidateUrl = "";
                    long candidateSize = 0;
                    string candidateAssetName = "";

                    foreach (var a in assets.EnumerateArray())
                    {
                        var name = a.TryGetProperty("name", out var np) ? (np.GetString() ?? "") : "";
                        bool isZipOrExe = name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)
                                       || name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase);
                        if (!isZipOrExe) continue;

                        bool hasLauncherInName = name.Contains("launcher", StringComparison.OrdinalIgnoreCase);
                        if ((isDedicatedLauncherTag || hasLauncherInName)
                            && a.TryGetProperty("browser_download_url", out var up))
                        {
                            candidateUrl = up.GetString() ?? "";
                            candidateAssetName = name;
                            candidateSize = a.TryGetProperty("size", out var sp) ? sp.GetInt64() : 0;
                            if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) || hasLauncherInName)
                                break;
                        }
                    }

                    if (string.IsNullOrWhiteSpace(candidateUrl))
                        continue;

                    string candidateVer = ExtractVersionString(isDedicatedLauncherTag ? tag : candidateAssetName);
                    if (string.IsNullOrWhiteSpace(candidateVer))
                        candidateVer = ExtractVersionString(tag);
                    if (string.IsNullOrWhiteSpace(candidateVer))
                        continue;

                    if (!foundAnyLauncherRelease || IsNewerVersion(candidateVer, bestVer))
                    {
                        foundAnyLauncherRelease = true;
                        bestVer = candidateVer;
                        bestUrl = candidateUrl;
                        bestSize = candidateSize;
                        bestNotes = notes;
                        bestPage = html;
                    }
                }

                bool newer = foundAnyLauncherRelease && IsNewerVersion(bestVer, currentLauncherVersion);
                return new LauncherUpdateCheckResult(true, newer, currentLauncherVersion, bestVer, bestUrl, bestSize, bestNotes, bestPage);
            }
            else
            {
                using var resp = await Http.GetAsync(raw, cts.Token);
                resp.EnsureSuccessStatusCode();
                var json = await resp.Content.ReadAsStringAsync(cts.Token);
                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement;

                string latest = root.TryGetProperty("launcher_version", out var lv)
                    ? (lv.GetString() ?? currentLauncherVersion).TrimStart('v', 'V')
                    : currentLauncherVersion;
                string dlUrl = root.TryGetProperty("launcher_download_url", out var ld) ? (ld.GetString() ?? "") : "";
                string notes = root.TryGetProperty("launcher_notes", out var ln) ? (ln.GetString() ?? "") : "";
                long size = root.TryGetProperty("launcher_size", out var ls) ? ls.GetInt64() : 0;

                bool newer = !string.IsNullOrWhiteSpace(dlUrl) && IsNewerVersion(latest, currentLauncherVersion);
                return new LauncherUpdateCheckResult(true, newer, currentLauncherVersion, latest, dlUrl, size, notes);
            }
        }
        catch (Exception ex)
        {
            return new LauncherUpdateCheckResult(false, false, currentLauncherVersion, currentLauncherVersion, "", 0, "", "",
                $"Launcher-Update-Check fehlgeschlagen: {ex.Message}");
        }
    }

    /// <summary>
    /// Lädt ein neues Launcher-Update (.exe oder .zip) herunter und startet ein sicheres
    /// Austausch-Skript, das die laufende DataCenterLauncher.exe nach Beendigung ersetzt und neu startet.
    /// </summary>
    public static async Task<(bool Ok, string Message)> DownloadAndApplyLauncherUpdateAsync(
        string downloadUrl,
        IProgress<(double Percent, string Status)> progress,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(downloadUrl))
            return (false, "Kein Download-Link für das Launcher-Update vorhanden.");

        var currentExe = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(currentExe) || !File.Exists(currentExe))
            return (false, "Aktueller Launcher-Pfad konnte nicht ermittelt werden.");

        var workDir = Path.Combine(Path.GetTempPath(), $"dct_launcher_upd_{Guid.NewGuid():N}");
        Directory.CreateDirectory(workDir);

        try
        {
            bool isZip = downloadUrl.Contains(".zip", StringComparison.OrdinalIgnoreCase);
            var dlPath = Path.Combine(workDir, isZip ? "launcher_update.zip" : "DataCenterLauncher.exe");

            progress.Report((5, "Lade neue Launcher-Version herunter..."));
            using var resp = await Http.GetAsync(downloadUrl, HttpCompletionOption.ResponseHeadersRead, ct);
            resp.EnsureSuccessStatusCode();

            var totalBytes = resp.Content.Headers.ContentLength ?? -1L;
            var sw = Stopwatch.StartNew();

            await using (var remote = await resp.Content.ReadAsStreamAsync(ct))
            await using (var local = File.Create(dlPath))
            {
                var buffer = new byte[81920];
                long downloaded = 0;
                int read;
                long lastReportMs = 0;

                while ((read = await remote.ReadAsync(buffer, ct)) > 0)
                {
                    await local.WriteAsync(buffer.AsMemory(0, read), ct);
                    downloaded += read;
                    if (sw.ElapsedMilliseconds - lastReportMs >= 100)
                    {
                        lastReportMs = sw.ElapsedMilliseconds;
                        double mbDone = downloaded / 1048576.0;
                        double pct = totalBytes > 0 ? Math.Clamp((double)downloaded / totalBytes * 80.0, 5.0, 80.0) : 45.0;
                        progress.Report((pct, totalBytes > 0
                            ? $"Launcher-Update: {mbDone:F1} / {totalBytes / 1048576.0:F1} MB"
                            : $"Launcher-Update: {mbDone:F1} MB"));
                    }
                }
            }

            string newExePath = dlPath;
            string? sourceFolderToCopy = null;

            if (isZip)
            {
                progress.Report((85, "Entpacke Launcher-Update..."));
                var extractDir = Path.Combine(workDir, "extracted");
                ZipFile.ExtractToDirectory(dlPath, extractDir, overwriteFiles: true);
                var foundExe = Directory.GetFiles(extractDir, "DataCenterLauncher.exe", SearchOption.AllDirectories).FirstOrDefault()
                            ?? Directory.GetFiles(extractDir, "*Launcher*.exe", SearchOption.AllDirectories).FirstOrDefault();
                if (string.IsNullOrWhiteSpace(foundExe))
                    return (false, "Im Launcher-ZIP wurde keine DataCenterLauncher.exe gefunden.");
                newExePath = foundExe;
                sourceFolderToCopy = Path.GetDirectoryName(foundExe);
            }

            progress.Report((94, "Bereite Neustart & Austausch vor..."));
            var targetDir = Path.GetDirectoryName(currentExe) ?? AppContext.BaseDirectory;
            var swapScript = Path.Combine(workDir, "apply_update.cmd");
            int pid = Environment.ProcessId;

            var sb = new StringBuilder();
            sb.AppendLine("@echo off");
            sb.AppendLine("setlocal");
            sb.AppendLine(":waitloop");
            sb.AppendLine($"tasklist /FI \"PID eq {pid}\" 2>NUL | find \"{pid}\" >NUL");
            sb.AppendLine("if \"%ERRORLEVEL%\"==\"0\" (");
            sb.AppendLine("  timeout /t 1 /nobreak >NUL");
            sb.AppendLine("  goto waitloop");
            sb.AppendLine(")");
            sb.AppendLine("timeout /t 1 /nobreak >NUL");
            if (!string.IsNullOrWhiteSpace(sourceFolderToCopy))
            {
                sb.AppendLine($"xcopy /E /Y /Q \"{sourceFolderToCopy}\\*\" \"{targetDir}\\\" >NUL");
            }
            else
            {
                sb.AppendLine($"copy /Y \"{newExePath}\" \"{currentExe}\" >NUL");
            }
            sb.AppendLine($"start \"\" \"{currentExe}\"");
            sb.AppendLine($"rmdir /S /Q \"{workDir}\" 2>NUL");

            File.WriteAllText(swapScript, sb.ToString(), Encoding.Default);

            progress.Report((100, "Launcher wird neu gestartet..."));
            Process.Start(new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = $"/c \"\"{swapScript}\"\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            });

            return (true, "Launcher-Update wird jetzt installiert und neu gestartet...");
        }
        catch (OperationCanceledException)
        {
            try { Directory.Delete(workDir, true); } catch { }
            return (false, "Launcher-Update abgebrochen.");
        }
        catch (Exception ex)
        {
            try { Directory.Delete(workDir, true); } catch { }
            return (false, $"Launcher-Update fehlgeschlagen: {ex.Message}");
        }
    }

    /// <summary>
    /// Baut eine eigenständige Single-File DataCenterLauncher.exe + ZIP für GitHub Releases.
    /// </summary>
    public static async Task<(bool Ok, string Message, string ZipPath)> BuildLauncherReleaseAsync(
        string projectDir,
        string launcherVersion,
        IProgress<(double Percent, string Status)> progress)
    {
        var csproj = Path.Combine(projectDir, "launcher", "DataCenterLauncher.csproj");
        if (!File.Exists(csproj))
            return (false, "launcher/DataCenterLauncher.csproj nicht gefunden.", "");

        var outDir = Path.Combine(projectDir, "dist", "launcher_standalone");
        var outZip = Path.Combine(projectDir, "dist", $"DataCenterLauncher-v{launcherVersion}-win64.zip");

        try
        {
            progress.Report((15, "Baue eigenständige DataCenterLauncher.exe (.NET 9 win-x64)..."));
            if (Directory.Exists(outDir))
                Directory.Delete(outDir, true);
            Directory.CreateDirectory(outDir);

            var psi = new ProcessStartInfo
            {
                FileName = "dotnet",
                WorkingDirectory = Path.Combine(projectDir, "launcher"),
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            psi.ArgumentList.Add("publish");
            psi.ArgumentList.Add(csproj);
            psi.ArgumentList.Add("-c");
            psi.ArgumentList.Add("Release");
            psi.ArgumentList.Add("-r");
            psi.ArgumentList.Add("win-x64");
            psi.ArgumentList.Add("--self-contained");
            psi.ArgumentList.Add("true");
            psi.ArgumentList.Add("-p:PublishSingleFile=true");
            psi.ArgumentList.Add("-p:IncludeNativeLibrariesForSelfExtract=true");
            psi.ArgumentList.Add("-o");
            psi.ArgumentList.Add(outDir);

            using var proc = Process.Start(psi);
            if (proc == null) return (false, "dotnet publish konnte nicht gestartet werden.", "");

            var errTask = proc.StandardError.ReadToEndAsync();
            var outTask = proc.StandardOutput.ReadToEndAsync();
            await proc.WaitForExitAsync();

            if (proc.ExitCode != 0)
            {
                var err = (await errTask + "\n" + await outTask).Trim();
                return (false, $"Launcher-Build fehlgeschlagen: {(err.Length > 240 ? err[^240..] : err)}", "");
            }

            progress.Report((80, "Erstelle Launcher-Release-ZIP..."));
            await Task.Run(() =>
            {
                if (File.Exists(outZip)) File.Delete(outZip);
                ZipFile.CreateFromDirectory(outDir, outZip, CompressionLevel.Optimal, includeBaseDirectory: false);
            });

            double mb = new FileInfo(outZip).Length / 1048576.0;
            progress.Report((100, $"Launcher-Release bereit ({mb:F1} MB)."));
            return (true, $"Launcher-Release erstellt ({mb:F1} MB): {Path.GetFileName(outZip)}", outZip);
        }
        catch (Exception ex)
        {
            return (false, $"Launcher-Build fehlgeschlagen: {ex.Message}", "");
        }
    }

    private static string ExtractVersionString(string input)
    {
        if (string.IsNullOrWhiteSpace(input)) return "";
        var m = Regex.Match(input, @"(\d+\.\d+(?:\.\d+)?)");
        return m.Success ? m.Groups[1].Value : "";
    }

    // --- BACKUP, REPARATUR, DIAGNOSE & ROADMAP ---

    public static (bool Ok, string Message, string BackupPath) CreateSavesBackup(string reasonTag = "auto")
    {
        try
        {
            var savesDir = Path.Combine(LauncherConfig.GetGodotUserDataDir(), "saves");
            if (!Directory.Exists(savesDir) || Directory.GetFiles(savesDir, "*", SearchOption.AllDirectories).Length == 0)
                return (false, "Keine Spielstände zum Sichern vorhanden.", "");

            Directory.CreateDirectory(LauncherConfig.BackupsDir);
            var stamp = DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss");
            var zipPath = Path.Combine(LauncherConfig.BackupsDir, $"saves_{reasonTag}_{stamp}.zip");
            ZipFile.CreateFromDirectory(savesDir, zipPath, CompressionLevel.Optimal, includeBaseDirectory: false);

            // Maximal 12 neueste Backups behalten
            var allBackups = Directory.GetFiles(LauncherConfig.BackupsDir, "saves_*.zip")
                .OrderByDescending(File.GetCreationTimeUtc)
                .Skip(12);
            foreach (var old in allBackups)
            {
                try { File.Delete(old); } catch { }
            }

            return (true, $"Backup erstellt: {Path.GetFileName(zipPath)}", zipPath);
        }
        catch (Exception ex)
        {
            return (false, $"Backup fehlgeschlagen: {ex.Message}", "");
        }
    }

    public static (bool Ok, string Message) RestoreSavesBackup(string backupZipPath)
    {
        if (!File.Exists(backupZipPath))
            return (false, "Backup-Datei nicht gefunden.");

        try
        {
            // Sicherheits-Backup vor Wiederherstellung
            CreateSavesBackup("pre_restore");
            var savesDir = Path.Combine(LauncherConfig.GetGodotUserDataDir(), "saves");
            Directory.CreateDirectory(savesDir);
            ZipFile.ExtractToDirectory(backupZipPath, savesDir, overwriteFiles: true);
            return (true, $"Spielstände erfolgreich aus {Path.GetFileName(backupZipPath)} wiederhergestellt!");
        }
        catch (Exception ex)
        {
            return (false, $"Wiederherstellung fehlgeschlagen: {ex.Message}");
        }
    }

    public static string CleanUserDataForRepair(bool resetSettings, bool clearShaderCache, bool deleteSaves)
    {
        var userData = LauncherConfig.GetGodotUserDataDir();
        var actions = new List<string>();
        if (!Directory.Exists(userData))
            return "Keine lokalen Benutzerdaten gefunden.";

        if (resetSettings)
        {
            string[] settingFiles = ["settings.cfg", "settings.json", "override.cfg"];
            foreach (var f in settingFiles)
            {
                var p = Path.Combine(userData, f);
                if (File.Exists(p))
                {
                    try { File.Delete(p); } catch { }
                }
            }
            actions.Add("Einstellungen zurückgesetzt");
        }

        if (clearShaderCache)
        {
            string[] cacheDirs = ["shader_cache", "vulkan", ".godot"];
            foreach (var d in cacheDirs)
            {
                var p = Path.Combine(userData, d);
                if (Directory.Exists(p))
                {
                    try { Directory.Delete(p, true); } catch { }
                }
            }
            actions.Add("Shader-Cache geleert");
        }

        if (deleteSaves)
        {
            var savesDir = Path.Combine(userData, "saves");
            if (Directory.Exists(savesDir))
            {
                try { Directory.Delete(savesDir, true); } catch { }
            }
            actions.Add("Spielstände gelöscht");
        }

        return actions.Count > 0 ? string.Join(" • ", actions) : "Benutzerdaten unverändert behalten";
    }

    public static (bool Ok, string Message, string ZipPath) CreateDiagnosticZip(LauncherConfig config)
    {
        var workDir = Path.Combine(Path.GetTempPath(), $"dct_diag_{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(workDir);
            var userData = LauncherConfig.GetGodotUserDataDir();
            var logFile = Path.Combine(userData, "logs", "godot.log");
            if (File.Exists(logFile))
                File.Copy(logFile, Path.Combine(workDir, "godot.log"), overwrite: true);

            if (File.Exists(LauncherConfig.ConfigPath))
                File.Copy(LauncherConfig.ConfigPath, Path.Combine(workDir, "launcher_config.json"), overwrite: true);

            var sysInfo = new StringBuilder();
            sysInfo.AppendLine("DataCenter Tycoon Co-op — Diagnose-Bericht");
            sysInfo.AppendLine($"Zeitstempel:      {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
            sysInfo.AppendLine($"Launcher-Version: v{LauncherConfig.CurrentLauncherVersion}");
            sysInfo.AppendLine($"Spiel-Version:    v{config.InstalledGameVersion}");
            sysInfo.AppendLine($"Install-Pfad:     {config.InstallDir}");
            sysInfo.AppendLine($"OS:               {Environment.OSVersion}");
            sysInfo.AppendLine($"64-Bit OS:        {Environment.Is64BitOperatingSystem}");
            sysInfo.AppendLine($"CPU-Kerne:        {Environment.ProcessorCount}");
            sysInfo.AppendLine($".NET Runtime:     {Environment.Version}");
            sysInfo.AppendLine($"Gesamtspielzeit:  {config.FormatPlayTime()}");
            File.WriteAllText(Path.Combine(workDir, "system_info.txt"), sysInfo.ToString(), Encoding.UTF8);

            var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            var outZip = Path.Combine(desktop, $"DataCenterTycoon_Diagnose_{DateTime.Now:yyyy-MM-dd_HH-mm}.zip");
            if (File.Exists(outZip)) File.Delete(outZip);
            ZipFile.CreateFromDirectory(workDir, outZip, CompressionLevel.Optimal, includeBaseDirectory: false);
            try { Directory.Delete(workDir, true); } catch { }
            return (true, $"Diagnose-Paket auf dem Desktop erstellt: {Path.GetFileName(outZip)}", outZip);
        }
        catch (Exception ex)
        {
            try { if (Directory.Exists(workDir)) Directory.Delete(workDir, true); } catch { }
            return (false, $"Diagnose-Export fehlgeschlagen: {ex.Message}", "");
        }
    }

    public static async Task<string?> FetchRoadmapJsonAsync(string manifestUrl, string? localFallbackPath)
    {
        try
        {
            var repo = NormalizeGitHubRepo(manifestUrl);
            if (!string.IsNullOrWhiteSpace(repo))
            {
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8));
                var rawUrl = $"https://raw.githubusercontent.com/{repo}/main/roadmap.json";
                using var resp = await Http.GetAsync(rawUrl, cts.Token);
                if (resp.IsSuccessStatusCode)
                    return await resp.Content.ReadAsStringAsync(cts.Token);
            }
        }
        catch { }

        if (!string.IsNullOrWhiteSpace(localFallbackPath) && File.Exists(localFallbackPath))
        {
            try { return await File.ReadAllTextAsync(localFallbackPath); } catch { }
        }
        return null;
    }
}
