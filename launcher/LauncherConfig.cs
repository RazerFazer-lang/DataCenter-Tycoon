using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace DataCenterLauncher;

public sealed class FavoriteServer
{
    public string Name { get; set; } = "Freunde-Server";
    public string Ip { get; set; } = "127.0.0.1";
    public int Port { get; set; } = 7777;
}

public sealed class LauncherConfig
{
    public static string CurrentLauncherVersion
    {
        get
        {
            var v = Assembly.GetExecutingAssembly().GetName().Version;
            return v != null ? $"{v.Major}.{v.Minor}.{Math.Max(v.Build, 0)}" : "3.3.0";
        }
    }
    /// <summary>
    /// Optional baked-in GitHub repo ("owner/repo") or manifest URL for friends.
    /// Can also be overridden by placing a 1-line "release_repo.txt" next to DataCenterLauncher.exe
    /// or by setting it in Launcher Settings.
    /// </summary>
    public const string DefaultReleaseSource = "RazerFazer-lang/DataCenter-Tycoon";

    public string PlayerName { get; set; } = "Admin";
    public string HostIp { get; set; } = "127.0.0.1";
    public int Port { get; set; } = 7777;
    public string WorldName { get; set; } = "Garage Cloud GmbH";
    public int GraphicsQuality { get; set; } = 2;
    public int LaunchModeIndex { get; set; } = 0; // 0=Menu, 1=Host, 2=Join, 3=LoadSave
    public long TotalPlayTimeSeconds { get; set; } = 0;
    public List<FavoriteServer> FavoriteServers { get; set; } = new();

    // Standalone Game Install (for Friends & Players — no Godot needed!)
    public string InstallDir { get; set; } = "";
    public string InstalledGameVersion { get; set; } = "";
    public string UpdateManifestUrl { get; set; } = "";

    // Developer-only paths (auto-detected if project.godot exists on this PC)
    public string GodotExePath { get; set; } = "";
    public string ProjectDir { get; set; } = "";

    [JsonIgnore]
    public bool IsDeveloperEnvironment =>
        !string.IsNullOrWhiteSpace(ProjectDir) && File.Exists(Path.Combine(ProjectDir, "project.godot"));

    private static readonly JsonSerializerOptions JsonOpts = new() { WriteIndented = true };

    public static string AppDataDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DataCenterTycoon");

    public static string ConfigPath =>
        Path.Combine(AppDataDir, "launcher_config.json");

    public static string DefaultInstallDir =>
        Path.Combine(AppDataDir, "game");

    public static string BackupsDir =>
        Path.Combine(AppDataDir, "backups");

    public string FormatPlayTime()
    {
        var ts = TimeSpan.FromSeconds(Math.Max(0, TotalPlayTimeSeconds));
        if (ts.TotalMinutes < 1) return "0 Min.";
        if (ts.TotalHours < 1) return $"{(int)ts.TotalMinutes} Min.";
        return $"{(int)ts.TotalHours} Std. {ts.Minutes} Min.";
    }

    public static LauncherConfig Load()
    {
        LauncherConfig cfg;
        try
        {
            Directory.CreateDirectory(AppDataDir);
            if (File.Exists(ConfigPath))
            {
                var raw = File.ReadAllText(ConfigPath);
                cfg = JsonSerializer.Deserialize<LauncherConfig>(raw) ?? new LauncherConfig();
            }
            else
            {
                cfg = new LauncherConfig();
            }
        }
        catch
        {
            cfg = new LauncherConfig();
        }

        cfg.AutoDetectPaths();
        return cfg;
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(AppDataDir);
            File.WriteAllText(ConfigPath, JsonSerializer.Serialize(this, JsonOpts));
        }
        catch
        {
            // Ignore write errors
        }
    }

    public void AutoDetectPaths()
    {
        // 1. Default standalone install directory inside %LOCALAPPDATA%\DataCenterTycoon\game
        if (string.IsNullOrWhiteSpace(InstallDir))
            InstallDir = DefaultInstallDir;

        // 2. Load bundled release_repo.txt next to launcher exe if no update URL configured yet
        if (string.IsNullOrWhiteSpace(UpdateManifestUrl))
        {
            var repoFile = Path.Combine(AppContext.BaseDirectory, "release_repo.txt");
            if (File.Exists(repoFile))
            {
                try
                {
                    var line = File.ReadAllText(repoFile).Trim();
                    if (!string.IsNullOrWhiteSpace(line))
                        UpdateManifestUrl = line;
                }
                catch { }
            }
            else if (!string.IsNullOrWhiteSpace(DefaultReleaseSource))
            {
                UpdateManifestUrl = DefaultReleaseSource;
            }
        }

        // 3. Auto-detect local Godot project folder (Developer PC only)
        if (string.IsNullOrWhiteSpace(ProjectDir) || !File.Exists(Path.Combine(ProjectDir, "project.godot")))
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 6 && dir != null; i++)
            {
                if (File.Exists(Path.Combine(dir.FullName, "project.godot")))
                {
                    ProjectDir = dir.FullName;
                    break;
                }
                dir = dir.Parent;
            }
        }

        // 4. Auto-detect Godot 4 executable (Developer PC only — handles OneDrive Desktop too!)
        if (string.IsNullOrWhiteSpace(GodotExePath) || !File.Exists(GodotExePath) || IsSelfExecutable(GodotExePath))
        {
            GodotExePath = FindGodotExecutable() ?? "";
        }

        // 5. Sync InstalledGameVersion from installed game folder (if game is installed)
        var installedExe = GetInstalledGameExe();
        if (string.IsNullOrWhiteSpace(installedExe))
        {
            InstalledGameVersion = "";
        }
        else
        {
            var verFromInstall = ReadVersionJson(Path.GetDirectoryName(installedExe));
            if (!string.IsNullOrWhiteSpace(verFromInstall))
                InstalledGameVersion = verFromInstall;
            else if (string.IsNullOrWhiteSpace(InstalledGameVersion))
                InstalledGameVersion = "0.5.0";
        }
    }

    public string? GetInstalledGameExe()
    {
        string[] candidateDirs =
        [
            InstallDir,
            Path.Combine(AppContext.BaseDirectory, "game")
        ];

        foreach (var dir in candidateDirs)
        {
            if (string.IsNullOrWhiteSpace(dir) || !Directory.Exists(dir)) continue;

            // Preferred exact filename first
            var preferred = Path.Combine(dir, "DataCenterTycoon.exe");
            if (File.Exists(preferred) && !IsSelfExecutable(preferred))
                return preferred;

            try
            {
                var found = Directory.GetFiles(dir, "*.exe", SearchOption.AllDirectories)
                    .FirstOrDefault(f =>
                        !IsSelfExecutable(f) &&
                        !Path.GetFileName(f).Contains("console", StringComparison.OrdinalIgnoreCase) &&
                        !Path.GetFileName(f).Contains("launcher", StringComparison.OrdinalIgnoreCase) &&
                        !Path.GetFileName(f).Contains("godot", StringComparison.OrdinalIgnoreCase));
                if (!string.IsNullOrWhiteSpace(found))
                    return found;
            }
            catch { }
        }
        return null;
    }

    public bool IsGameInstalled => !string.IsNullOrWhiteSpace(GetInstalledGameExe());

    public bool CanDevLaunch =>
        IsDeveloperEnvironment &&
        !string.IsNullOrWhiteSpace(GodotExePath) &&
        File.Exists(GodotExePath) &&
        !IsSelfExecutable(GodotExePath);

    public string GetProjectVersion()
    {
        var v = ReadVersionJson(ProjectDir);
        return string.IsNullOrWhiteSpace(v) ? "0.5.0" : v;
    }

    public static string? ReadVersionJson(string? dir)
    {
        if (string.IsNullOrWhiteSpace(dir)) return null;
        var vPath = Path.Combine(dir, "version.json");
        if (!File.Exists(vPath)) return null;
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(vPath));
            if (doc.RootElement.TryGetProperty("version", out var vProp))
                return vProp.GetString()?.Trim();
        }
        catch { }
        return null;
    }

    public static bool IsSelfExecutable(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return false;
        try
        {
            var fileName = Path.GetFileName(path);
            if (fileName.Equals("DataCenterLauncher.exe", StringComparison.OrdinalIgnoreCase))
                return true;

            var self = Environment.ProcessPath;
            if (!string.IsNullOrWhiteSpace(self) &&
                string.Equals(Path.GetFullPath(path), Path.GetFullPath(self), StringComparison.OrdinalIgnoreCase))
                return true;
        }
        catch { }
        return false;
    }

    public static string? FindGodotExecutable()
    {
        var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var desktopReal = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory); // Handles OneDrive\Desktop!
        string[] searchRoots =
        [
            desktopReal,
            Path.Combine(userProfile, "Desktop"),
            Path.Combine(userProfile, "OneDrive", "Desktop"),
            Path.Combine(userProfile, "Downloads"),
            @"C:\Program Files\Godot",
            @"C:\Godot",
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs"),
        ];

        var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var root in searchRoots)
        {
            if (string.IsNullOrWhiteSpace(root) || !visited.Add(root) || !Directory.Exists(root)) continue;
            try
            {
                foreach (var f in Directory.GetFiles(root, "*Godot*4*.exe", SearchOption.TopDirectoryOnly))
                {
                    if (!f.Contains("console", StringComparison.OrdinalIgnoreCase))
                        return f;
                }
                foreach (var sub in Directory.GetDirectories(root))
                {
                    try
                    {
                        foreach (var f in Directory.GetFiles(sub, "*Godot*4*.exe", SearchOption.TopDirectoryOnly))
                        {
                            if (!f.Contains("console", StringComparison.OrdinalIgnoreCase))
                                return f;
                        }
                    }
                    catch { }
                }
            }
            catch { }
        }
        return null;
    }

    public static string GetGodotUserDataDir() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Godot", "app_userdata", "DataCenter Tycoon Co-op");

    public static long GetDirectorySizeBytes(string dir)
    {
        if (string.IsNullOrWhiteSpace(dir) || !Directory.Exists(dir)) return 0;
        long total = 0;
        try
        {
            foreach (var f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories))
                total += new FileInfo(f).Length;
        }
        catch { }
        return total;
    }
}
