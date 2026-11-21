using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Text.Json;

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

public static class UpdateService
{
    private static readonly HttpClient Http = new()
    {
        Timeout = TimeSpan.FromMinutes(10)
    };

    static UpdateService()
    {
        Http.DefaultRequestHeaders.UserAgent.ParseAdd("DataCenterTycoonLauncher/0.5");
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
                url = $"https://api.github.com/repos/{repo}/releases/latest";
                releasePage = $"https://github.com/{repo}/releases";
            }
            else if (!url.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
                     && !url.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
                     && url.Contains('/'))
            {
                var repo = NormalizeGitHubRepo(url);
                url = $"https://api.github.com/repos/{repo}/releases/latest";
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
        var parts = clean.Split('.');
        return parts.Length == 2 ? clean + ".0" : clean;
    }
}
