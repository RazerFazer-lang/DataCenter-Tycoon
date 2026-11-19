using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Microsoft.Win32;

namespace DataCenterLauncher;

public partial class MainWindow : Window
{
    private readonly LauncherConfig _config;
    private UpdateCheckResult? _lastUpdateResult;
    private CancellationTokenSource? _downloadCts;
    private bool _isBusy;
    private string _lastBuiltZipPath = "";

    public MainWindow()
    {
        InitializeComponent();
        _config = LauncherConfig.Load();
        PopulateUIFromConfig();
        LoadPatchnotes();
        RefreshLauncherState();
        SetActiveNav(NavPlayBtn, PagePlay);
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        // Auto-check GitHub Releases on startup just like a real Game Launcher!
        if (!string.IsNullOrWhiteSpace(_config.UpdateManifestUrl))
        {
            await RunUpdateCheckAsync(silentIfNoUrl: true);
        }
    }

    private void PopulateUIFromConfig()
    {
        PlayerNameBox.Text = _config.PlayerName;
        QualityCombo.SelectedIndex = Math.Clamp(_config.GraphicsQuality, 0, 3);
        UpdateUrlBox.Text = _config.UpdateManifestUrl;
        InstallDirBox.Text = _config.InstallDir;
        GodotExeBox.Text = _config.GodotExePath;
        ProjectDirBox.Text = _config.ProjectDir;
    }

    private void SyncConfigFromUI()
    {
        _config.PlayerName = string.IsNullOrWhiteSpace(PlayerNameBox.Text) ? "Admin" : PlayerNameBox.Text.Trim();
        _config.GraphicsQuality = Math.Clamp(QualityCombo.SelectedIndex, 0, 3);
        // Kein Startmodus mehr: Das Spiel startet immer im Hauptmenü.
        _config.LaunchModeIndex = 0;

        _config.UpdateManifestUrl = UpdateUrlBox.Text.Trim();
        _config.InstallDir = string.IsNullOrWhiteSpace(InstallDirBox.Text) ? LauncherConfig.DefaultInstallDir : InstallDirBox.Text.Trim();

        var gPath = GodotExeBox.Text.Trim();
        _config.GodotExePath = LauncherConfig.IsSelfExecutable(gPath) ? "" : gPath;
        _config.ProjectDir = ProjectDirBox.Text.Trim();
        _config.Save();
    }

    /// <summary>
    /// Synchronizes all visual states across Home, Sidebar, Updates & Dev views:
    /// Not Installed -> Blue "⬇ SPIEL HERUNTERLADEN"
    /// Update Ready  -> Amber "🔄 UPDATE INSTALLIEREN"
    /// Installed     -> Green "▶ SPIELEN"
    /// </summary>
    private void RefreshLauncherState()
    {
        bool installed = _config.IsGameInstalled;
        bool isDev = _config.IsDeveloperEnvironment;
        bool updateAvailable = _lastUpdateResult is { Success: true, UpdateAvailable: true };

        // Developer UI only appears on your dev PC where project.godot exists
        NavDevBtn.Visibility = isDev ? Visibility.Visible : Visibility.Collapsed;
        DevPlayBtn.Visibility = _config.CanDevLaunch ? Visibility.Visible : Visibility.Collapsed;
        DevSettingsCard.Visibility = isDev ? Visibility.Visible : Visibility.Collapsed;

        // Install Folder & Disk Size info
        InstallDirLabel.Text = $"Installationspfad: {_config.InstallDir}";
        double sizeMb = LauncherConfig.GetDirectorySizeBytes(_config.InstallDir) / 1048576.0;
        InstallSizeText.Text = installed ? $"{sizeMb:F1} MB" : "0 MB";
        UninstallBtn.IsEnabled = installed && !_isBusy;

        if (installed)
        {
            var ver = string.IsNullOrWhiteSpace(_config.InstalledGameVersion) ? "0.5.0" : _config.InstalledGameVersion;
            InstalledVerText.Text = $"v{ver}";

            if (updateAvailable && _lastUpdateResult != null)
            {
                SidebarStatusDot.Fill = (Brush)FindResource("AccentAmber");
                SidebarStatusTitle.Text = $"Update v{_lastUpdateResult.LatestVersion}";
                SidebarStatusDetail.Text = $"Installiert: v{ver} • Neuere Version verfügbar!";

                HeroStateBorder.Background = new SolidColorBrush(Color.FromRgb(56, 38, 12));
                HeroStateBorder.BorderBrush = (Brush)FindResource("AccentAmber");
                HeroStateBadge.Foreground = (Brush)FindResource("AccentAmber");
                HeroStateBadge.Text = $"✨ UPDATE v{_lastUpdateResult.LatestVersion} VERFÜGBAR";

                MainActionBtn.Style = (Style)FindResource("UpdateActionButton");
                MainActionBtn.Content = $"🔄  UPDATE (v{_lastUpdateResult.LatestVersion})";
                LaunchStatusTitle.Text = $"Update auf v{_lastUpdateResult.LatestVersion} bereit";
                LaunchStatusSub.Text = "Klicke auf Update, um die neueste Version für Co-op herunterzuladen.";
            }
            else
            {
                SidebarStatusDot.Fill = (Brush)FindResource("AccentGreen");
                SidebarStatusTitle.Text = "Spiel installiert";
                SidebarStatusDetail.Text = $"Version v{ver} • Bereit zum Spielen";

                HeroStateBorder.Background = new SolidColorBrush(Color.FromRgb(16, 53, 40));
                HeroStateBorder.BorderBrush = (Brush)FindResource("AccentGreen");
                HeroStateBadge.Foreground = (Brush)FindResource("AccentGreen");
                HeroStateBadge.Text = $"✅ INSTALLIERT  •  v{ver}";

                MainActionBtn.Style = (Style)FindResource("PrimaryPlayButton");
                MainActionBtn.Content = "▶   SPIELEN";
                LaunchStatusTitle.Text = $"Bereit zum Spielen (v{ver})";
                LaunchStatusSub.Text = $"Standalone-Build: {_config.GetInstalledGameExe()}";
            }
        }
        else
        {
            InstalledVerText.Text = "Nicht installiert";
            SidebarStatusDot.Fill = (Brush)FindResource("AccentCyan");
            SidebarStatusTitle.Text = "Nicht installiert";
            SidebarStatusDetail.Text = string.IsNullOrWhiteSpace(_config.UpdateManifestUrl)
                ? "GitHub-Repo eintragen oder Release-ZIP installieren."
                : "Klicke auf Herunterladen, um das Spiel zu installieren.";

            HeroStateBorder.Background = new SolidColorBrush(Color.FromRgb(18, 42, 68));
            HeroStateBorder.BorderBrush = (Brush)FindResource("AccentCyan");
            HeroStateBadge.Foreground = (Brush)FindResource("AccentCyan");
            HeroStateBadge.Text = _lastUpdateResult is { Success: true }
                ? $"⬇ BEREIT ZUM DOWNLOAD (v{_lastUpdateResult.LatestVersion})"
                : "⬇ SPIEL NICHT INSTALLIERT";

            MainActionBtn.Style = (Style)FindResource("DownloadActionButton");
            if (_lastUpdateResult is { Success: true, AssetSizeBytes: > 0 })
            {
                double mb = _lastUpdateResult.AssetSizeBytes / 1048576.0;
                MainActionBtn.Content = $"⬇  HERUNTERLADEN ({mb:F0} MB)";
            }
            else
            {
                MainActionBtn.Content = "⬇  SPIEL HERUNTERLADEN";
            }

            LaunchStatusTitle.Text = "Spiel noch nicht heruntergeladen";
            LaunchStatusSub.Text = _config.CanDevLaunch
                ? "Lade ein Release herunter — oder nutze „🛠 Dev-Start“ für dein lokales Godot-Projekt."
                : (string.IsNullOrWhiteSpace(_config.UpdateManifestUrl)
                    ? "Trage dein GitHub-Repo unter ⚙ Einstellungen ein oder installiere eine lokale .zip."
                    : $"Download-Quelle: {_config.UpdateManifestUrl}");
        }

        DualTestBtn.IsEnabled = !_isBusy && (installed || _config.CanDevLaunch);
        MainActionBtn.IsEnabled = !_isBusy;
        DevPlayBtn.IsEnabled = !_isBusy && _config.CanDevLaunch;
        InstallUpdateBtn.IsEnabled = !_isBusy && _lastUpdateResult is { Success: true } && !string.IsNullOrWhiteSpace(_lastUpdateResult.DownloadUrl);
    }

    private void SetBusy(bool busy, bool showHomeProgress = false, bool cancellable = false)
    {
        _isBusy = busy;
        HomeProgressRow.Visibility = showHomeProgress ? Visibility.Visible : Visibility.Collapsed;
        CancelDownloadBtn.Visibility = cancellable ? Visibility.Visible : Visibility.Collapsed;
        CheckUpdateBtn.IsEnabled = !busy;
        HeroCheckUpdatesBtn.IsEnabled = !busy;
        InstallLocalZipBtn.IsEnabled = !busy;
        BuildReleaseZipBtn.IsEnabled = !busy;
        InstallBuiltZipBtn.IsEnabled = !busy;
        RefreshLauncherState();
    }

    // --- UPDATE CHECK & DOWNLOAD ---

    private async Task RunUpdateCheckAsync(bool silentIfNoUrl = false)
    {
        SyncConfigFromUI();
        if (string.IsNullOrWhiteSpace(_config.UpdateManifestUrl))
        {
            if (!silentIfNoUrl)
            {
                UpdateStatusText.Text = "Noch kein GitHub-Repo eingetragen! Bitte unter ⚙ Einstellungen z.B. „deinname/datacenter-tycoon“ eintragen.";
                RemoteVerText.Text = "Kein Repo";
            }
            return;
        }

        CheckUpdateBtn.IsEnabled = false;
        HeroCheckUpdatesBtn.IsEnabled = false;
        HeroStateBadge.Text = "🔄 SUCHE NACH UPDATES...";
        RemoteVerText.Text = "Lädt...";
        UpdateStatusText.Text = $"Prüfe Releases von {_config.UpdateManifestUrl}...";
        RemoteNotesCard.Visibility = Visibility.Collapsed;

        var res = await UpdateService.CheckForUpdateAsync(_config.UpdateManifestUrl, _config.InstalledGameVersion);
        _lastUpdateResult = res;

        CheckUpdateBtn.IsEnabled = true;
        HeroCheckUpdatesBtn.IsEnabled = true;

        if (!res.Success)
        {
            RemoteVerText.Text = "Fehler";
            UpdateStatusText.Text = res.ErrorMessage;
            RefreshLauncherState();
            return;
        }

        RemoteVerText.Text = $"v{res.LatestVersion}";
        if (!string.IsNullOrWhiteSpace(res.Notes))
        {
            RemoteNotesText.Text = res.Notes;
            RemoteNotesCard.Visibility = Visibility.Visible;
        }

        if (!_config.IsGameInstalled)
        {
            UpdateStatusText.Text = string.IsNullOrWhiteSpace(res.DownloadUrl)
                ? $"Release v{res.LatestVersion} gefunden, aber es hängt noch keine .zip Datei daran."
                : $"✅ Release v{res.LatestVersion} gefunden! Klicke auf „Spiel herunterladen“.";
        }
        else if (res.UpdateAvailable)
        {
            UpdateStatusText.Text = string.IsNullOrWhiteSpace(res.DownloadUrl)
                ? $"Neue Version v{res.LatestVersion} gefunden, aber keine .zip Datei angehängt."
                : $"🎉 Update auf v{res.LatestVersion} verfügbar! Klicke auf „Update installieren“.";
        }
        else
        {
            UpdateStatusText.Text = $"✅ Dein Spiel ist auf dem neuesten Stand (v{_config.InstalledGameVersion}).";
        }

        RefreshLauncherState();
    }

    private async Task StartDownloadOrUpdateAsync()
    {
        SyncConfigFromUI();

        if (string.IsNullOrWhiteSpace(_config.UpdateManifestUrl))
        {
            var answer = MessageBox.Show(
                "Es ist noch kein GitHub-Repo für den Online-Download hinterlegt.\n\n" +
                "• Klicke auf [JA], um dein GitHub-Repo in den Einstellungen einzutragen.\n" +
                "• Klicke auf [NEIN], um stattdessen eine lokale Release-.zip zu installieren" +
                (_config.CanDevLaunch ? " (oder nutze „🛠 Dev-Start“ für dein Godot-Projekt)." : "."),
                "Download-Quelle konfigurieren",
                MessageBoxButton.YesNoCancel,
                MessageBoxImage.Information);

            if (answer == MessageBoxResult.Yes)
                SetActiveNav(NavSettingsBtn, PageSettings);
            else if (answer == MessageBoxResult.No)
                await PickAndInstallLocalZipAsync();
            return;
        }

        // Check latest release first if not yet checked
        if (_lastUpdateResult == null || !_lastUpdateResult.Success || string.IsNullOrWhiteSpace(_lastUpdateResult.DownloadUrl))
        {
            await RunUpdateCheckAsync();
        }

        if (_lastUpdateResult == null || !_lastUpdateResult.Success || string.IsNullOrWhiteSpace(_lastUpdateResult.DownloadUrl))
        {
            MessageBox.Show(
                _lastUpdateResult?.ErrorMessage ?? "Kein herunterladbares .zip-Release gefunden. Prüfe dein GitHub-Repo unter ⚙ Einstellungen.",
                "Download nicht möglich",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        _downloadCts?.Cancel();
        _downloadCts = new CancellationTokenSource();

        SetBusy(true, showHomeProgress: true, cancellable: true);
        HomeProgressBar.Value = 2;
        UpdateProgressBar.Visibility = Visibility.Visible;
        UpdateProgressBar.Value = 2;

        var progress = new Progress<(double Percent, string Status)>(p =>
        {
            HomeProgressBar.Value = p.Percent;
            UpdateProgressBar.Value = p.Percent;
            LaunchStatusTitle.Text = p.Percent < 85 ? "Lade Spiel herunter..." : "Installiere Dateien...";
            LaunchStatusSub.Text = p.Status;
            UpdateStatusText.Text = p.Status;
        });

        var (ok, msg, _) = await UpdateService.DownloadAndInstallAsync(
            _lastUpdateResult.DownloadUrl,
            _config.InstallDir,
            _lastUpdateResult.LatestVersion,
            progress,
            _downloadCts.Token);

        if (ok)
        {
            _config.InstalledGameVersion = _lastUpdateResult.LatestVersion;
            _config.Save();
            _lastUpdateResult = _lastUpdateResult with { UpdateAvailable = false };
            LoadPatchnotes();
        }

        UpdateStatusText.Text = msg;
        SetBusy(false, showHomeProgress: false, cancellable: false);
        UpdateProgressBar.Visibility = Visibility.Collapsed;

        if (!ok && msg != "Download abgebrochen.")
            MessageBox.Show(msg, "Download-Fehler", MessageBoxButton.OK, MessageBoxImage.Warning);
    }

    private async Task PickAndInstallLocalZipAsync(string? preselectedZip = null)
    {
        string? zipPath = preselectedZip;
        if (string.IsNullOrWhiteSpace(zipPath))
        {
            var dlg = new OpenFileDialog
            {
                Title = "DataCenter Tycoon Release-.zip auswählen",
                Filter = "ZIP-Archiv (*.zip)|*.zip"
            };
            if (dlg.ShowDialog() != true) return;
            zipPath = dlg.FileName;
        }

        if (!File.Exists(zipPath))
        {
            MessageBox.Show("ZIP-Datei existiert nicht.", "Fehler", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        SetBusy(true, showHomeProgress: true, cancellable: false);
        UpdateProgressBar.Visibility = Visibility.Visible;

        var progress = new Progress<(double Percent, string Status)>(p =>
        {
            HomeProgressBar.Value = p.Percent;
            UpdateProgressBar.Value = p.Percent;
            LaunchStatusTitle.Text = "Installiere lokales Paket...";
            LaunchStatusSub.Text = p.Status;
            UpdateStatusText.Text = p.Status;
        });

        var (ok, msg, _) = await UpdateService.InstallFromLocalZipAsync(zipPath, _config.InstallDir, _config.GetProjectVersion(), progress);
        if (ok)
        {
            _config.AutoDetectPaths();
            _config.Save();
            LoadPatchnotes();
        }

        UpdateStatusText.Text = msg;
        SetBusy(false, showHomeProgress: false, cancellable: false);
        UpdateProgressBar.Visibility = Visibility.Collapsed;

        if (ok)
            MessageBox.Show("Spiel wurde erfolgreich in den Launcher installiert! Du kannst jetzt direkt auf „▶ SPIELEN“ klicken.", "Installiert", MessageBoxButton.OK, MessageBoxImage.Information);
        else
            MessageBox.Show(msg, "Installation fehlgeschlagen", MessageBoxButton.OK, MessageBoxImage.Warning);
    }

    // --- LAUNCH LOGIC ---

    private bool LaunchInstalledGame(IEnumerable<string> userArgs, out string error)
    {
        error = "";
        var exe = _config.GetInstalledGameExe();
        if (string.IsNullOrWhiteSpace(exe) || !File.Exists(exe) || LauncherConfig.IsSelfExecutable(exe))
        {
            error = "Kein installiertes Spiel gefunden. Bitte lade das Spiel zuerst über den Launcher herunter.";
            return false;
        }

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = exe,
                WorkingDirectory = Path.GetDirectoryName(exe) ?? _config.InstallDir,
                UseShellExecute = false
            };
            foreach (var arg in userArgs)
                psi.ArgumentList.Add(arg);
            Process.Start(psi);
            return true;
        }
        catch (Exception ex)
        {
            error = $"Spielstart fehlgeschlagen: {ex.Message}";
            return false;
        }
    }

    private bool LaunchGodotDev(IEnumerable<string> userArgs, out string error)
    {
        error = "";
        if (!_config.CanDevLaunch)
        {
            error = "Godot 4 .exe oder project.godot nicht gefunden. Bitte unter ⚙ Einstellungen prüfen.";
            return false;
        }

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = _config.GodotExePath,
                WorkingDirectory = _config.ProjectDir,
                UseShellExecute = false
            };
            psi.ArgumentList.Add("--path");
            psi.ArgumentList.Add(_config.ProjectDir);
            psi.ArgumentList.Add("--");
            foreach (var arg in userArgs)
                psi.ArgumentList.Add(arg);
            Process.Start(psi);
            return true;
        }
        catch (Exception ex)
        {
            error = $"Godot-Start fehlgeschlagen: {ex.Message}";
            return false;
        }
    }

    private List<string> BuildUserArgsFromUI()
    {
        var args = new List<string>
        {
            $"--quality={_config.GraphicsQuality}",
            $"--name={_config.PlayerName}"
        };
        return args;
    }

    // --- BUTTON HANDLERS ---

    private async void MainActionBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_isBusy) return;
        SyncConfigFromUI();

        bool installed = _config.IsGameInstalled;
        bool updateAvailable = _lastUpdateResult is { Success: true, UpdateAvailable: true };

        // 1. Not installed -> Download!
        if (!installed)
        {
            await StartDownloadOrUpdateAsync();
            return;
        }

        // 2. Update available -> Install Update!
        if (updateAvailable)
        {
            await StartDownloadOrUpdateAsync();
            return;
        }

        // 3. Installed & Ready -> Play! (startet im Hauptmenü)
        var args = BuildUserArgsFromUI();
        if (LaunchInstalledGame(args, out var err))
        {
            LaunchStatusTitle.Text = "Spiel gestartet! 🚀";
            LaunchStatusSub.Text = $"Standalone-Build • Grafik-Stufe {_config.GraphicsQuality}";
        }
        else
        {
            MessageBox.Show(err, "Startfehler", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void DevPlayBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_isBusy) return;
        SyncConfigFromUI();

        var args = BuildUserArgsFromUI();
        if (LaunchGodotDev(args, out var err))
        {
            LaunchStatusTitle.Text = "Godot 4 Dev-Start läuft! 🛠";
            LaunchStatusSub.Text = $"{Path.GetFileName(_config.GodotExePath)} • Grafik-Stufe {_config.GraphicsQuality}";
        }
        else
        {
            MessageBox.Show(err, "Dev-Start fehlgeschlagen", MessageBoxButton.OK, MessageBoxImage.Warning);
            SetActiveNav(NavSettingsBtn, PageSettings);
        }
    }

    private async void DualTestBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_isBusy) return;
        SyncConfigFromUI();

        bool useInstalled = _config.IsGameInstalled;
        if (!useInstalled && !_config.CanDevLaunch)
        {
            MessageBox.Show("Bitte lade das Spiel erst herunter (oder wähle Godot 4 unter Einstellungen).",
                "Nicht bereit", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        DualTestBtn.IsEnabled = false;
        LaunchStatusTitle.Text = "Starte 2× Co-op Test (Host + Client)...";
        LaunchStatusSub.Text = "Instanz 1 hostet auf 127.0.0.1, Instanz 2 tritt automatisch bei.";

        var hostArgs = new List<string>
        {
            $"--quality={_config.GraphicsQuality}",
            $"--name={_config.PlayerName}_Host",
            "--host",
            $"--world={_config.WorldName}",
            $"--port={_config.Port}"
        };

        bool ok1 = useInstalled ? LaunchInstalledGame(hostArgs, out var err) : LaunchGodotDev(hostArgs, out err);
        if (!ok1)
        {
            DualTestBtn.IsEnabled = true;
            MessageBox.Show(err, "Startfehler", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        await Task.Delay(1700);

        var clientArgs = new List<string>
        {
            $"--quality={_config.GraphicsQuality}",
            $"--name={_config.PlayerName}_Freund",
            "--join=127.0.0.1",
            $"--port={_config.Port}"
        };

        bool ok2 = useInstalled ? LaunchInstalledGame(clientArgs, out var err2) : LaunchGodotDev(clientArgs, out err2);
        LaunchStatusTitle.Text = ok2 ? "2× Co-op Test läuft! ⚡" : "Client-Start fehlgeschlagen";
        LaunchStatusSub.Text = ok2 ? $"Host + Client verbunden auf 127.0.0.1:{_config.Port}" : err2;
        DualTestBtn.IsEnabled = true;
    }

    private void CancelDownloadBtn_Click(object sender, RoutedEventArgs e) => _downloadCts?.Cancel();

    private async void CheckUpdateBtn_Click(object sender, RoutedEventArgs e) => await RunUpdateCheckAsync(silentIfNoUrl: false);

    private async void InstallUpdateBtn_Click(object sender, RoutedEventArgs e) => await StartDownloadOrUpdateAsync();

    private async void InstallLocalZipBtn_Click(object sender, RoutedEventArgs e) => await PickAndInstallLocalZipAsync();

    private void UninstallBtn_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show("Möchtest du die installierten Spiel-Dateien wirklich entfernen?\n\nDeine Spielstände bleiben sicher erhalten.",
                "Spiel deinstallieren", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes)
            return;

        var (ok, msg) = UpdateService.UninstallGame(_config.InstallDir);
        if (ok)
        {
            _config.InstalledGameVersion = "";
            _config.Save();
            if (_lastUpdateResult != null)
                _lastUpdateResult = _lastUpdateResult with { UpdateAvailable = true };
        }
        UpdateStatusText.Text = msg;
        RefreshLauncherState();
    }

    // --- DEVELOPER RELEASE BUILDER ---

    private async void BuildReleaseZipBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_isBusy) return;
        SyncConfigFromUI();

        SetBusy(true, showHomeProgress: false, cancellable: false);
        DevBuildProgressBar.Visibility = Visibility.Visible;
        DevBuildProgressBar.Value = 5;

        var progress = new Progress<(double Percent, string Status)>(p =>
        {
            DevBuildProgressBar.Value = p.Percent;
            DevBuildStatusText.Text = p.Status;
        });

        var (ok, msg, zipPath) = await UpdateService.BuildWindowsReleaseZipAsync(
            _config.GodotExePath,
            _config.ProjectDir,
            _config.GetProjectVersion(),
            progress);

        DevBuildStatusText.Text = msg;
        if (ok)
        {
            _lastBuiltZipPath = zipPath;
            MessageBox.Show(
                $"{msg}\n\nDu kannst diese .zip jetzt:\n1) Direkt lokal testen („🧪 Lokal im Launcher installieren“)\n2) Auf GitHub Releases hochladen, damit deine Freunde sie über den Launcher laden!",
                "Release-ZIP erstellt", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        else
        {
            MessageBox.Show(msg, "Build-Hinweis", MessageBoxButton.OK, MessageBoxImage.Warning);
        }

        SetBusy(false);
        DevBuildProgressBar.Visibility = Visibility.Collapsed;
    }

    private async void InstallBuiltZipBtn_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(_lastBuiltZipPath) && File.Exists(_lastBuiltZipPath))
        {
            await PickAndInstallLocalZipAsync(_lastBuiltZipPath);
            return;
        }

        var distDir = Path.Combine(_config.ProjectDir, "dist");
        var latestZip = Directory.Exists(distDir)
            ? Directory.GetFiles(distDir, "DataCenterTycoon-*.zip")
                .OrderByDescending(File.GetLastWriteTime)
                .FirstOrDefault()
            : null;

        await PickAndInstallLocalZipAsync(latestZip);
    }

    private void OpenDistDirBtn_Click(object sender, RoutedEventArgs e)
    {
        var dir = Path.Combine(_config.ProjectDir, "dist");
        Directory.CreateDirectory(dir);
        Process.Start(new ProcessStartInfo { FileName = dir, UseShellExecute = true });
    }

    private void OpenGitHubReleaseBtn_Click(object sender, RoutedEventArgs e)
    {
        SyncConfigFromUI();
        var repo = UpdateService.NormalizeGitHubRepo(_config.UpdateManifestUrl);
        var url = string.IsNullOrWhiteSpace(repo)
            ? "https://github.com/new"
            : $"https://github.com/{repo}/releases/new";
        Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
    }

    private void PrepareFriendsBundleBtn_Click(object sender, RoutedEventArgs e)
    {
        SyncConfigFromUI();
        var bundleDir = Path.Combine(_config.ProjectDir, "dist", "Freunde_Launcher");
        Directory.CreateDirectory(bundleDir);

        // Prefer self-contained published exe if present, otherwise current running exe
        var standaloneExe = Path.Combine(_config.ProjectDir, "dist", "launcher_standalone", "DataCenterLauncher.exe");
        var sourceExe = File.Exists(standaloneExe) ? standaloneExe : Environment.ProcessPath;

        if (!string.IsNullOrWhiteSpace(sourceExe) && File.Exists(sourceExe))
            File.Copy(sourceExe, Path.Combine(bundleDir, "DataCenterLauncher.exe"), overwrite: true);

        if (!string.IsNullOrWhiteSpace(_config.UpdateManifestUrl))
            File.WriteAllText(Path.Combine(bundleDir, "release_repo.txt"), _config.UpdateManifestUrl.Trim());

        var readme =
            "DATACENTER TYCOON CO-OP — LAUNCHER FÜR FREUNDE\r\n" +
            "==============================================\r\n" +
            "1. Doppelklick auf DataCenterLauncher.exe\r\n" +
            "2. Klicke auf 'SPIEL HERUNTERLADEN' (kein Godot und kein .NET nötig!)\r\n" +
            "3. Sobald der Download fertig ist, klicke auf 'SPIELEN'!\r\n" +
            "4. Neue Updates erkennt der Launcher ab sofort automatisch beim Start.\r\n";
        File.WriteAllText(Path.Combine(bundleDir, "LIESMICH.txt"), readme);

        Process.Start(new ProcessStartInfo { FileName = bundleDir, UseShellExecute = true });
        DevBuildStatusText.Text = $"🎁 Freunde-Paket bereit in: {bundleDir}";
    }

    // --- PATCHNOTES & NAVIGATION ---

    private void LoadPatchnotes()
    {
        PatchnotesPanel.Children.Clear();

        string[] candidates =
        [
            !string.IsNullOrWhiteSpace(_config.InstallDir) ? Path.Combine(_config.InstallDir, "version.json") : "",
            !string.IsNullOrWhiteSpace(_config.ProjectDir) ? Path.Combine(_config.ProjectDir, "version.json") : "",
            Path.Combine(AppContext.BaseDirectory, "version.json")
        ];

        string? versionFile = candidates.FirstOrDefault(p => !string.IsNullOrWhiteSpace(p) && File.Exists(p));
        if (versionFile == null)
        {
            PatchnotesPanel.Children.Add(new TextBlock
            {
                Text = "Patchnotes erscheinen automatisch, sobald das Spiel heruntergeladen oder ein GitHub-Release geprüft wurde.",
                Foreground = (Brush)FindResource("TextMuted"),
                FontSize = 13,
                TextWrapping = TextWrapping.Wrap
            });
            return;
        }

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(versionFile));
            var root = doc.RootElement;
            var ver = root.TryGetProperty("version", out var vp) ? vp.GetString() : "0.5.0";
            var code = root.TryGetProperty("codename", out var cp) ? cp.GetString() : "";
            NotesHeaderTitle.Text = $"Version {ver} — {code}";

            if (root.TryGetProperty("changelog", out var cl) && cl.ValueKind == JsonValueKind.Array)
            {
                foreach (var entry in cl.EnumerateArray())
                {
                    var card = new Border
                    {
                        Background = (Brush)FindResource("BgCard"),
                        BorderBrush = (Brush)FindResource("BorderSubtle"),
                        BorderThickness = new Thickness(1),
                        CornerRadius = new CornerRadius(10),
                        Padding = new Thickness(18, 14, 18, 14),
                        Margin = new Thickness(0, 0, 0, 12)
                    };

                    var stack = new StackPanel();
                    var header = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 8) };
                    var eVer = entry.TryGetProperty("version", out var ev) ? (ev.GetString() ?? "") : "";
                    var eTitle = entry.TryGetProperty("title", out var et) ? (et.GetString() ?? "") : "";

                    header.Children.Add(new Border
                    {
                        Background = new SolidColorBrush(Color.FromRgb(20, 48, 72)),
                        BorderBrush = (Brush)FindResource("AccentCyan"),
                        BorderThickness = new Thickness(1),
                        CornerRadius = new CornerRadius(6),
                        Padding = new Thickness(8, 2, 8, 2),
                        Margin = new Thickness(0, 0, 10, 0),
                        Child = new TextBlock { Text = eVer, Foreground = (Brush)FindResource("AccentCyan"), FontWeight = FontWeights.Bold, FontSize = 12 }
                    });
                    header.Children.Add(new TextBlock { Text = eTitle, Foreground = (Brush)FindResource("TextMain"), FontWeight = FontWeights.Bold, FontSize = 15, VerticalAlignment = VerticalAlignment.Center });
                    stack.Children.Add(header);

                    if (entry.TryGetProperty("items", out var items) && items.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var item in items.EnumerateArray())
                        {
                            stack.Children.Add(new TextBlock
                            {
                                Text = $"•  {item.GetString()}",
                                Foreground = new SolidColorBrush(Color.FromRgb(196, 214, 232)),
                                FontSize = 12.8,
                                TextWrapping = TextWrapping.Wrap,
                                Margin = new Thickness(4, 2, 0, 3)
                            });
                        }
                    }

                    card.Child = stack;
                    PatchnotesPanel.Children.Add(card);
                }
            }
        }
        catch (Exception ex)
        {
            PatchnotesPanel.Children.Add(new TextBlock { Text = $"Fehler: {ex.Message}", Foreground = (Brush)FindResource("AccentAmber") });
        }
    }

    private void SetActiveNav(Button activeBtn, UIElement activePage)
    {
        Button[] navBtns = [NavPlayBtn, NavNotesBtn, NavUpdatesBtn, NavDevBtn, NavSettingsBtn];
        UIElement[] pages = [PagePlay, PageNotes, PageUpdates, PageDev, PageSettings];

        foreach (var b in navBtns)
        {
            b.Background = Brushes.Transparent;
            b.Foreground = (Brush)FindResource("TextMuted");
        }
        foreach (var p in pages)
            p.Visibility = Visibility.Collapsed;

        activeBtn.Background = new SolidColorBrush(Color.FromRgb(23, 41, 64));
        activeBtn.Foreground = (Brush)FindResource("AccentCyan");
        activePage.Visibility = Visibility.Visible;
    }

    private void NavPlayBtn_Click(object sender, RoutedEventArgs e) { RefreshLauncherState(); SetActiveNav(NavPlayBtn, PagePlay); }
    private void NavNotesBtn_Click(object sender, RoutedEventArgs e) { LoadPatchnotes(); SetActiveNav(NavNotesBtn, PageNotes); }
    private void NavUpdatesBtn_Click(object sender, RoutedEventArgs e) { RefreshLauncherState(); SetActiveNav(NavUpdatesBtn, PageUpdates); }
    private void NavDevBtn_Click(object sender, RoutedEventArgs e) => SetActiveNav(NavDevBtn, PageDev);
    private void NavSettingsBtn_Click(object sender, RoutedEventArgs e) => SetActiveNav(NavSettingsBtn, PageSettings);

    private void BrowseInstallDir_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFolderDialog { Title = "Spiel-Installationsordner auswählen" };
        if (dlg.ShowDialog() == true)
            InstallDirBox.Text = dlg.FolderName;
    }

    private void BrowseGodotExe_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog { Title = "Godot 4 .exe auswählen", Filter = "Godot 4 (*.exe)|*.exe" };
        if (dlg.ShowDialog() == true)
            GodotExeBox.Text = dlg.FileName;
    }

    private void AutoDetectGodot_Click(object sender, RoutedEventArgs e)
    {
        var found = LauncherConfig.FindGodotExecutable();
        if (!string.IsNullOrWhiteSpace(found))
        {
            GodotExeBox.Text = found;
            SettingsSavedHint.Text = "✅ Godot 4 gefunden!";
        }
        else
        {
            SettingsSavedHint.Text = "⚠ Nicht automatisch gefunden — bitte manuell auswählen.";
        }
    }

    private void BrowseProjectDir_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFolderDialog { Title = "Godot Projektordner (project.godot) auswählen" };
        if (dlg.ShowDialog() == true)
            ProjectDirBox.Text = dlg.FolderName;
    }

    private async void SaveSettingsBtn_Click(object sender, RoutedEventArgs e)
    {
        SyncConfigFromUI();
        _config.AutoDetectPaths();
        RefreshLauncherState();
        SettingsSavedHint.Text = "✅ Gespeichert!";
        if (!string.IsNullOrWhiteSpace(_config.UpdateManifestUrl))
            await RunUpdateCheckAsync(silentIfNoUrl: true);
    }

    private void OpenInstallDirBtn_Click(object sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(_config.InstallDir);
        Process.Start(new ProcessStartInfo { FileName = _config.InstallDir, UseShellExecute = true });
    }

    private void OpenSavesBtn_Click(object sender, RoutedEventArgs e)
    {
        var dir = Path.Combine(LauncherConfig.GetGodotUserDataDir(), "saves");
        Directory.CreateDirectory(dir);
        Process.Start(new ProcessStartInfo { FileName = dir, UseShellExecute = true });
    }

    private void OpenModelsBtn_Click(object sender, RoutedEventArgs e)
    {
        string dir = _config.IsGameInstalled
            ? Path.Combine(_config.InstallDir, "custom_models")
            : (_config.IsDeveloperEnvironment
                ? Path.Combine(_config.ProjectDir, "assets", "models")
                : Path.Combine(LauncherConfig.AppDataDir, "custom_models"));
        Directory.CreateDirectory(dir);
        Process.Start(new ProcessStartInfo { FileName = dir, UseShellExecute = true });
    }

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left)
            DragMove();
    }

    private void MinimizeBtn_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void CloseBtn_Click(object sender, RoutedEventArgs e)
    {
        _downloadCts?.Cancel();
        SyncConfigFromUI();
        Close();
    }
}
