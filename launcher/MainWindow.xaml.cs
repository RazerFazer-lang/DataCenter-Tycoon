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
    private LauncherUpdateCheckResult? _lastLauncherUpdateResult;
    private bool _launcherBannerDismissed;
    private string _activeTagFilter = "all";
    private CancellationTokenSource? _downloadCts;
    private bool _isBusy;
    private bool _isGameRunning;
    private string _lastBuiltZipPath = "";

    private sealed record TagMeta(string Key, string Label, Color Bg, Color Border, Color Fg);

    private static readonly TagMeta[] TagDefs =
    [
        new("neu", "NEU", Color.FromRgb(15, 56, 40), Color.FromRgb(36, 216, 122), Color.FromRgb(64, 240, 150)),
        new("fix", "BUGFIX", Color.FromRgb(62, 20, 24), Color.FromRgb(242, 95, 92), Color.FromRgb(255, 138, 134)),
        new("verbesserung", "VERBESSERUNG", Color.FromRgb(16, 45, 66), Color.FromRgb(46, 216, 255), Color.FromRgb(106, 228, 255)),
        new("3d", "3D / GRAFIK", Color.FromRgb(42, 26, 68), Color.FromRgb(179, 136, 255), Color.FromRgb(204, 174, 255)),
        new("balance", "BALANCE", Color.FromRgb(58, 42, 14), Color.FromRgb(255, 184, 48), Color.FromRgb(255, 210, 108)),
        new("launcher", "LAUNCHER", Color.FromRgb(18, 38, 70), Color.FromRgb(77, 163, 255), Color.FromRgb(130, 192, 255)),
        new("gameplay", "GAMEPLAY", Color.FromRgb(18, 54, 48), Color.FromRgb(42, 214, 172), Color.FromRgb(110, 242, 208)),
        new("infrastruktur", "INFRASTRUKTUR", Color.FromRgb(24, 44, 72), Color.FromRgb(66, 168, 255), Color.FromRgb(138, 202, 255)),
        new("coop", "CO-OP", Color.FromRgb(48, 30, 68), Color.FromRgb(198, 124, 255), Color.FromRgb(222, 176, 255)),
        new("ki", "KI / PERSONAL", Color.FromRgb(60, 44, 18), Color.FromRgb(255, 196, 66), Color.FromRgb(255, 220, 130)),
    ];

    public MainWindow()
    {
        InitializeComponent();
        _config = LauncherConfig.Load();
        TopBarHint.Text = $"Launcher v{LauncherConfig.CurrentLauncherVersion}";
        LauncherVerStatText.Text = $"v{LauncherConfig.CurrentLauncherVersion}";
        LauncherUpdateStatusText.Text = $"Installiert: v{LauncherConfig.CurrentLauncherVersion} • Wird beim Start automatisch geprüft.";
        PopulateUIFromConfig();
        LoadPatchnotes();
        RefreshFavoriteServers();
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

        HeroPlayTimeText.Text = $"⏱ Spielzeit: {_config.FormatPlayTime()}";

        if (_isGameRunning)
        {
            SidebarStatusDot.Fill = (Brush)FindResource("AccentGreen");
            SidebarStatusTitle.Text = "Spiel läuft…";
            SidebarStatusDetail.Text = $"Spielzeit: {_config.FormatPlayTime()}";
            MainActionBtn.Style = (Style)FindResource("SecondaryButton");
            MainActionBtn.Content = "🟢  SPIEL LÄUFT…";
            MainActionBtn.IsEnabled = false;
        }
        else
        {
            MainActionBtn.IsEnabled = !_isBusy;
        }

        DualTestBtn.IsEnabled = !_isBusy && !_isGameRunning && (installed || _config.CanDevLaunch);
        DevPlayBtn.IsEnabled = !_isBusy && !_isGameRunning && _config.CanDevLaunch;

        // Update-Button NUR aktivieren, wenn noch nicht installiert ODER tatsächlich ein Update vorliegt!
        bool hasDlUrl = _lastUpdateResult is { Success: true } && !string.IsNullOrWhiteSpace(_lastUpdateResult.DownloadUrl);
        if (!installed)
        {
            InstallUpdateBtn.Content = "⬇ Spiel herunterladen";
            InstallUpdateBtn.IsEnabled = !_isBusy && !_isGameRunning && hasDlUrl;
        }
        else if (updateAvailable && _lastUpdateResult != null)
        {
            InstallUpdateBtn.Content = $"⬇ Update auf v{_lastUpdateResult.LatestVersion} installieren";
            InstallUpdateBtn.IsEnabled = !_isBusy && !_isGameRunning && hasDlUrl;
        }
        else
        {
            InstallUpdateBtn.Content = $"✓ Spiel ist aktuell (v{_config.InstalledGameVersion})";
            InstallUpdateBtn.IsEnabled = false;
        }

        RepairGameBtn.IsEnabled = !_isBusy && !_isGameRunning && installed;
        RefreshLauncherUpdateUI();
    }

    private void RefreshLauncherUpdateUI()
    {
        var cur = LauncherConfig.CurrentLauncherVersion;
        if (_lastLauncherUpdateResult is { Success: true, UpdateAvailable: true } lu && !string.IsNullOrWhiteSpace(lu.DownloadUrl))
        {
            TopBarHint.Text = $"Launcher v{cur} → v{lu.LatestVersion}";
            TopBarHint.Foreground = (Brush)FindResource("AccentAmber");
            TopLauncherVerDot.Fill = (Brush)FindResource("AccentAmber");
            TopLauncherVerPill.BorderBrush = (Brush)FindResource("AccentAmber");

            LauncherVerStatText.Text = $"v{cur} → v{lu.LatestVersion}";
            LauncherVerStatText.Foreground = (Brush)FindResource("AccentAmber");
            double mb = lu.AssetSizeBytes > 0 ? lu.AssetSizeBytes / 1048576.0 : 0;
            string sizeInfo = mb > 0 ? $" ({mb:F1} MB)" : "";
            LauncherBannerTitle.Text = $"🚀 Neue Launcher-Version v{lu.LatestVersion} verfügbar!{sizeInfo}";
            LauncherBannerSub.Text = $"Aktuell installiert: v{cur} — ein Klick aktualisiert den Launcher und startet ihn neu.";
            LauncherUpdateStatusText.Text = $"🎉 Neue Launcher-Version v{lu.LatestVersion} verfügbar (aktuell v{cur}){sizeInfo}.";
            LauncherUpdateCard.BorderBrush = (Brush)FindResource("AccentAmber");
            UpdatesPageLauncherBtn.Visibility = Visibility.Visible;
            UpdatesPageLauncherBtn.IsEnabled = !_isBusy;
            ApplyLauncherUpdateBtn.IsEnabled = !_isBusy;
            LauncherUpdateBanner.Visibility = _launcherBannerDismissed ? Visibility.Collapsed : Visibility.Visible;
        }
        else
        {
            TopBarHint.Text = $"Launcher v{cur}";
            TopBarHint.Foreground = (Brush)FindResource("TextMuted");
            TopLauncherVerDot.Fill = (Brush)FindResource("AccentGreen");
            TopLauncherVerPill.BorderBrush = new SolidColorBrush(Color.FromRgb(42, 64, 92));

            LauncherVerStatText.Text = $"v{cur}";
            LauncherVerStatText.Foreground = (Brush)FindResource("TextMain");
            LauncherUpdateCard.BorderBrush = (Brush)FindResource("BorderSubtle");
            UpdatesPageLauncherBtn.Visibility = Visibility.Collapsed;
            LauncherUpdateBanner.Visibility = Visibility.Collapsed;

            if (_lastLauncherUpdateResult is { Success: true })
                LauncherUpdateStatusText.Text = $"✅ Launcher ist auf dem neuesten Stand (v{cur}).";
            else if (_lastLauncherUpdateResult is { Success: false } errLu && !string.IsNullOrWhiteSpace(errLu.ErrorMessage))
                LauncherUpdateStatusText.Text = errLu.ErrorMessage;
        }
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
        BuildLauncherReleaseBtn.IsEnabled = !busy;
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
        UpdateStatusText.Text = $"Prüfe Spiel- & Launcher-Releases von {_config.UpdateManifestUrl}...";
        RemoteNotesCard.Visibility = Visibility.Collapsed;

        var gameTask = UpdateService.CheckForUpdateAsync(_config.UpdateManifestUrl, _config.InstalledGameVersion);
        var launcherTask = UpdateService.CheckForLauncherUpdateAsync(_config.UpdateManifestUrl, LauncherConfig.CurrentLauncherVersion);
        await Task.WhenAll(gameTask, launcherTask);

        var res = await gameTask;
        _lastUpdateResult = res;
        _lastLauncherUpdateResult = await launcherTask;

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
            PopulateRemoteNotes(res.Notes);
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

    private async Task StartDownloadOrUpdateAsync(bool forceRepair = false)
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

        // Automatisches Spielstand-Backup vor jedem Update!
        if (_config.IsGameInstalled && !forceRepair)
        {
            UpdateService.CreateSavesBackup("pre_update");
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

    private bool LaunchInstalledGame(IEnumerable<string> userArgs, out string error, bool trackSession = false)
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
            var proc = Process.Start(psi);
            if (trackSession && proc != null)
            {
                _ = TrackGameProcessAsync(proc);
            }
            return true;
        }
        catch (Exception ex)
        {
            error = $"Spielstart fehlgeschlagen: {ex.Message}";
            return false;
        }
    }

    private async Task TrackGameProcessAsync(Process proc)
    {
        _isGameRunning = true;
        RefreshLauncherState();
        WindowState = WindowState.Minimized;
        var sw = Stopwatch.StartNew();

        try
        {
            await proc.WaitForExitAsync();
        }
        catch { }

        sw.Stop();
        _config.TotalPlayTimeSeconds += (long)sw.Elapsed.TotalSeconds;
        _config.Save();
        _isGameRunning = false;

        Dispatcher.Invoke(() =>
        {
            if (WindowState == WindowState.Minimized)
                WindowState = WindowState.Normal;
            Activate();
            RefreshLauncherState();
            LaunchStatusTitle.Text = $"Sitzung beendet ({(int)sw.Elapsed.TotalMinutes} Min.)";
            LaunchStatusSub.Text = $"Gesamtspielzeit: {_config.FormatPlayTime()}";
        });
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

        // 3. Installed & Ready -> Play! (startet im Hauptmenü, minimiert Launcher & zählt Spielzeit)
        var args = BuildUserArgsFromUI();
        if (LaunchInstalledGame(args, out var err, trackSession: true))
        {
            LaunchStatusTitle.Text = "Spiel läuft… 🟢";
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

    private void DismissLauncherBannerBtn_Click(object sender, RoutedEventArgs e)
    {
        _launcherBannerDismissed = true;
        LauncherUpdateBanner.Visibility = Visibility.Collapsed;
    }

    private async void ApplyLauncherUpdateBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_isBusy || _lastLauncherUpdateResult == null || string.IsNullOrWhiteSpace(_lastLauncherUpdateResult.DownloadUrl))
            return;

        _downloadCts?.Cancel();
        _downloadCts = new CancellationTokenSource();
        SetBusy(true, showHomeProgress: false, cancellable: false);
        LauncherUpdateBanner.Visibility = Visibility.Visible;
        LauncherUpdateProgressBar.Visibility = Visibility.Visible;
        LauncherUpdateProgressBar.Value = 5;

        var progress = new Progress<(double Percent, string Status)>(p =>
        {
            LauncherUpdateProgressBar.Value = p.Percent;
            LauncherBannerSub.Text = p.Status;
            LauncherUpdateStatusText.Text = p.Status;
        });

        var (ok, msg) = await UpdateService.DownloadAndApplyLauncherUpdateAsync(
            _lastLauncherUpdateResult.DownloadUrl,
            progress,
            _downloadCts.Token);

        if (ok)
        {
            Application.Current.Shutdown();
            return;
        }

        LauncherUpdateProgressBar.Visibility = Visibility.Collapsed;
        LauncherBannerSub.Text = msg;
        LauncherUpdateStatusText.Text = msg;
        SetBusy(false);
        MessageBox.Show(msg, "Launcher-Update", MessageBoxButton.OK, MessageBoxImage.Warning);
    }

    private async void BuildLauncherReleaseBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_isBusy) return;
        SyncConfigFromUI();

        SetBusy(true, showHomeProgress: false, cancellable: false);
        DevBuildProgressBar.Visibility = Visibility.Visible;
        DevBuildProgressBar.Value = 8;

        var progress = new Progress<(double Percent, string Status)>(p =>
        {
            DevBuildProgressBar.Value = p.Percent;
            DevBuildStatusText.Text = p.Status;
        });

        var (ok, msg, _) = await UpdateService.BuildLauncherReleaseAsync(
            _config.ProjectDir,
            LauncherConfig.CurrentLauncherVersion,
            progress);

        DevBuildStatusText.Text = msg;
        SetBusy(false);
        DevBuildProgressBar.Visibility = Visibility.Collapsed;

        MessageBox.Show(
            ok
                ? $"{msg}\n\nTipp für Auto-Updates: Lade diese .zip auf GitHub Releases hoch (z. B. mit Tag „launcher-v{LauncherConfig.CurrentLauncherVersion}“ oder direkt als Asset im Spiel-Release). Alle Launcher erkennen das Update automatisch!"
                : msg,
            ok ? "Launcher-Release erstellt" : "Build-Fehler",
            MessageBoxButton.OK,
            ok ? MessageBoxImage.Information : MessageBoxImage.Warning);
    }

    private async void CheckUpdateBtn_Click(object sender, RoutedEventArgs e) => await RunUpdateCheckAsync(silentIfNoUrl: false);

    private async void InstallUpdateBtn_Click(object sender, RoutedEventArgs e) => await StartDownloadOrUpdateAsync();

    private async void RepairGameBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_isBusy || _isGameRunning) return;

        var dlg = new RepairDialog { Owner = this };
        if (dlg.ShowDialog() != true) return;

        if (!dlg.DeleteSaves)
            UpdateService.CreateSavesBackup("pre_repair");

        var cleanSummary = UpdateService.CleanUserDataForRepair(dlg.ResetConfigs, dlg.ClearShaderCache, dlg.DeleteSaves);
        UpdateStatusText.Text = $"Reparatur vorbereitet ({cleanSummary}) — lade Spiel neu herunter…";
        await StartDownloadOrUpdateAsync(forceRepair: true);
    }

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

    // --- PATCHNOTES MIT FARBIGEN TAGS, FILTER-CHIPS & VORSCHAU ---

    private sealed record ParsedChangeItem(string TagKey, string Text);
    private sealed record ParsedRelease(string Version, string Date, string Title, List<ParsedChangeItem> Items);

    private static TagMeta GetTagMeta(string key) =>
        TagDefs.FirstOrDefault(t => t.Key.Equals(key, StringComparison.OrdinalIgnoreCase)) ?? TagDefs[2];

    private static string NormalizeTagKey(string raw)
    {
        var k = raw.Trim().ToLowerInvariant();
        return k switch
        {
            "neu" or "new" or "feature" or "feat" or "added" => "neu",
            "fix" or "bugfix" or "bug" or "fixed" or "hotfix" => "fix",
            "3d" or "grafik" or "graphics" or "visual" or "art" or "model" or "models" => "3d",
            "balance" or "balancing" or "gameplay" or "economy" => "balance",
            "launcher" or "updater" or "installer" => "launcher",
            _ => "verbesserung"
        };
    }

    private static ParsedChangeItem ParseChangeItemFromString(string rawText)
    {
        var text = rawText.Trim().TrimStart('-', '*', '•', ' ');
        // Prüft auf Prefix wie "[FIX] ...", "[NEU] ...", "Bugfix: ..."
        if (text.StartsWith('['))
        {
            var close = text.IndexOf(']');
            if (close > 1 && close < 20)
            {
                var tag = NormalizeTagKey(text[1..close]);
                return new ParsedChangeItem(tag, text[(close + 1)..].Trim());
            }
        }
        var lower = text.ToLowerInvariant();
        if (lower.Contains("behoben") || lower.Contains("fix") || lower.Contains("repariert") || lower.Contains("fehler") || lower.Contains("sichtbar") || lower.Contains("verloren"))
            return new ParsedChangeItem("fix", text);
        if (lower.Contains("launcher") || lower.Contains("updater"))
            return new ParsedChangeItem("launcher", text);
        if (lower.Contains("3d-modell") || lower.Contains("blender") || lower.Contains("mixamo") || lower.Contains("charakter") || lower.Contains("lieferwagen"))
            return new ParsedChangeItem("3d", text);
        if (lower.Contains("neu") || lower.Contains("erstmals") || lower.Contains("editor"))
            return new ParsedChangeItem("neu", text);
        return new ParsedChangeItem("verbesserung", text);
    }

    private UIElement CreateTaggedRow(ParsedChangeItem item, bool compact = false)
    {
        var meta = GetTagMeta(item.TagKey);
        var row = new Grid { Margin = new Thickness(0, compact ? 2 : 3, 0, compact ? 4 : 5) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(compact ? 84 : 108) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var badge = new Border
        {
            Background = new SolidColorBrush(meta.Bg),
            BorderBrush = new SolidColorBrush(meta.Border),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(5),
            Padding = new Thickness(compact ? 6 : 8, 2, compact ? 6 : 8, 2),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 1, 8, 0),
            Child = new TextBlock
            {
                Text = meta.Label,
                Foreground = new SolidColorBrush(meta.Fg),
                FontSize = compact ? 9.5 : 10.2,
                FontWeight = FontWeights.Bold
            }
        };
        Grid.SetColumn(badge, 0);
        row.Children.Add(badge);

        var tb = new TextBlock
        {
            Text = item.Text,
            Foreground = new SolidColorBrush(Color.FromRgb(204, 220, 236)),
            FontSize = compact ? 11.5 : 12.8,
            TextWrapping = TextWrapping.Wrap,
            TextTrimming = compact ? TextTrimming.CharacterEllipsis : TextTrimming.None,
            MaxHeight = compact ? 36 : double.PositiveInfinity,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(tb, 1);
        row.Children.Add(tb);

        return row;
    }

    private void PopulateRemoteNotes(string rawNotes)
    {
        RemoteNotesPanel.Children.Clear();
        var lines = rawNotes.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries);
        foreach (var rawLine in lines)
        {
            var line = rawLine.Trim();
            if (string.IsNullOrWhiteSpace(line)) continue;
            if (line.StartsWith('#'))
            {
                RemoteNotesPanel.Children.Add(new TextBlock
                {
                    Text = line.TrimStart('#', ' '),
                    Foreground = (Brush)FindResource("AccentCyan"),
                    FontWeight = FontWeights.Bold,
                    FontSize = 13,
                    Margin = new Thickness(0, 6, 0, 4)
                });
                continue;
            }
            RemoteNotesPanel.Children.Add(CreateTaggedRow(ParseChangeItemFromString(line)));
        }
    }

    private void LoadPatchnotes()
    {
        PatchnotesPanel.Children.Clear();
        NotesFilterPanel.Children.Clear();
        HomeWhatsNewPanel.Children.Clear();

        string[] candidates =
        [
            !string.IsNullOrWhiteSpace(_config.ProjectDir) ? Path.Combine(_config.ProjectDir, "version.json") : "",
            !string.IsNullOrWhiteSpace(_config.InstallDir) ? Path.Combine(_config.InstallDir, "version.json") : "",
            Path.Combine(AppContext.BaseDirectory, "version.json")
        ];

        string? versionFile = candidates.FirstOrDefault(p => !string.IsNullOrWhiteSpace(p) && File.Exists(p));
        if (versionFile == null)
        {
            var emptyHint = new TextBlock
            {
                Text = "Patchnotes erscheinen automatisch, sobald das Spiel heruntergeladen oder ein GitHub-Release geprüft wurde.",
                Foreground = (Brush)FindResource("TextMuted"),
                FontSize = 13,
                TextWrapping = TextWrapping.Wrap
            };
            PatchnotesPanel.Children.Add(emptyHint);
            HomeWhatsNewPanel.Children.Add(new TextBlock
            {
                Text = "Noch keine lokalen Patchnotes vorhanden.",
                Foreground = (Brush)FindResource("TextMuted"),
                FontSize = 11.5
            });
            return;
        }

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(versionFile));
            var root = doc.RootElement;
            var ver = root.TryGetProperty("version", out var vp) ? vp.GetString() : "1.0.6";
            var code = root.TryGetProperty("codename", out var cp) ? cp.GetString() : "";
            NotesHeaderTitle.Text = $"Spiel v{ver} — {code}  •  Launcher v{LauncherConfig.CurrentLauncherVersion}";
            HomeWhatsNewHeader.Text = $"NEUESTES UPDATE  •  v{ver}";

            var releases = new List<ParsedRelease>();
            var tagCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            int totalItems = 0;

            if (root.TryGetProperty("changelog", out var cl) && cl.ValueKind == JsonValueKind.Array)
            {
                foreach (var entry in cl.EnumerateArray())
                {
                    var eVer = entry.TryGetProperty("version", out var ev) ? (ev.GetString() ?? "") : "";
                    var eDate = entry.TryGetProperty("date", out var ed) ? (ed.GetString() ?? "") : "";
                    var eTitle = entry.TryGetProperty("title", out var et) ? (et.GetString() ?? "") : "";
                    var parsedItems = new List<ParsedChangeItem>();

                    if (entry.TryGetProperty("items", out var items) && items.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var item in items.EnumerateArray())
                        {
                            ParsedChangeItem parsed;
                            if (item.ValueKind == JsonValueKind.Object)
                            {
                                var tRaw = item.TryGetProperty("tag", out var tp) ? (tp.GetString() ?? "verbesserung") : "verbesserung";
                                var txt = item.TryGetProperty("text", out var txp) ? (txp.GetString() ?? "") : "";
                                parsed = new ParsedChangeItem(NormalizeTagKey(tRaw), txt);
                            }
                            else
                            {
                                parsed = ParseChangeItemFromString(item.GetString() ?? "");
                            }

                            if (!string.IsNullOrWhiteSpace(parsed.Text))
                            {
                                parsedItems.Add(parsed);
                                totalItems++;
                                tagCounts[parsed.TagKey] = tagCounts.GetValueOrDefault(parsed.TagKey) + 1;
                            }
                        }
                    }

                    releases.Add(new ParsedRelease(eVer, eDate, eTitle, parsedItems));
                }
            }

            // Home "Neuestes Update" Vorschau (Top 3 Einträge)
            if (releases.Count > 0)
            {
                foreach (var topItem in releases[0].Items.Take(3))
                    HomeWhatsNewPanel.Children.Add(CreateTaggedRow(topItem, compact: true));
            }

            // Filter-Chips aufbauen
            AddFilterChip("all", $"Alle ({totalItems})", Color.FromRgb(46, 216, 255));
            foreach (var def in TagDefs)
            {
                int cnt = tagCounts.GetValueOrDefault(def.Key);
                if (cnt > 0)
                    AddFilterChip(def.Key, $"{def.Label} ({cnt})", def.Border);
            }

            // Version-Cards rendern (gefiltert nach _activeTagFilter)
            foreach (var rel in releases)
            {
                var visibleItems = _activeTagFilter == "all"
                    ? rel.Items
                    : rel.Items.Where(i => i.TagKey.Equals(_activeTagFilter, StringComparison.OrdinalIgnoreCase)).ToList();

                if (visibleItems.Count == 0) continue;

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
                var header = new DockPanel { Margin = new Thickness(0, 0, 0, 10) };

                if (!string.IsNullOrWhiteSpace(rel.Date))
                {
                    var dateLbl = new TextBlock
                    {
                        Text = rel.Date,
                        Foreground = (Brush)FindResource("TextMuted"),
                        FontSize = 11.5,
                        VerticalAlignment = VerticalAlignment.Center
                    };
                    DockPanel.SetDock(dateLbl, Dock.Right);
                    header.Children.Add(dateLbl);
                }

                var leftHeader = new StackPanel { Orientation = Orientation.Horizontal };
                leftHeader.Children.Add(new Border
                {
                    Background = new SolidColorBrush(Color.FromRgb(20, 48, 72)),
                    BorderBrush = (Brush)FindResource("AccentCyan"),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(6),
                    Padding = new Thickness(9, 2, 9, 2),
                    Margin = new Thickness(0, 0, 10, 0),
                    Child = new TextBlock { Text = rel.Version, Foreground = (Brush)FindResource("AccentCyan"), FontWeight = FontWeights.Bold, FontSize = 12 }
                });
                leftHeader.Children.Add(new TextBlock
                {
                    Text = rel.Title,
                    Foreground = (Brush)FindResource("TextMain"),
                    FontWeight = FontWeights.Bold,
                    FontSize = 14.5,
                    TextWrapping = TextWrapping.Wrap,
                    VerticalAlignment = VerticalAlignment.Center
                });
                header.Children.Add(leftHeader);
                stack.Children.Add(header);

                foreach (var item in visibleItems)
                    stack.Children.Add(CreateTaggedRow(item));

                card.Child = stack;
                PatchnotesPanel.Children.Add(card);
            }
        }
        catch (Exception ex)
        {
            PatchnotesPanel.Children.Add(new TextBlock { Text = $"Fehler beim Laden der Patchnotes: {ex.Message}", Foreground = (Brush)FindResource("AccentAmber") });
        }
    }

    private void AddFilterChip(string filterKey, string label, Color accentColor)
    {
        bool active = _activeTagFilter.Equals(filterKey, StringComparison.OrdinalIgnoreCase);
        var btn = new Button
        {
            Style = (Style)FindResource("FilterChipButton"),
            Content = label,
            Tag = filterKey
        };
        if (active)
        {
            btn.Background = new SolidColorBrush(Color.FromArgb(60, accentColor.R, accentColor.G, accentColor.B));
            btn.BorderBrush = new SolidColorBrush(accentColor);
            btn.Foreground = new SolidColorBrush(Colors.White);
        }
        btn.Click += (_, _) =>
        {
            _activeTagFilter = filterKey;
            LoadPatchnotes();
        };
        NotesFilterPanel.Children.Add(btn);
    }

    private void SetActiveNav(Button activeBtn, UIElement activePage)
    {
        Button[] navBtns = [NavPlayBtn, NavNotesBtn, NavRoadmapBtn, NavUpdatesBtn, NavToolsBtn, NavDevBtn, NavSettingsBtn];
        UIElement[] pages = [PagePlay, PageNotes, PageRoadmap, PageUpdates, PageTools, PageDev, PageSettings];

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

    private void NavPlayBtn_Click(object sender, RoutedEventArgs e) { RefreshFavoriteServers(); RefreshLauncherState(); SetActiveNav(NavPlayBtn, PagePlay); }
    private void NavNotesBtn_Click(object sender, RoutedEventArgs e) { LoadPatchnotes(); SetActiveNav(NavNotesBtn, PageNotes); }
    private async void NavRoadmapBtn_Click(object sender, RoutedEventArgs e) { SetActiveNav(NavRoadmapBtn, PageRoadmap); await LoadRoadmapAsync(); }
    private void NavUpdatesBtn_Click(object sender, RoutedEventArgs e) { RefreshLauncherState(); SetActiveNav(NavUpdatesBtn, PageUpdates); }
    private void NavToolsBtn_Click(object sender, RoutedEventArgs e) { RefreshBackupsList(); RefreshCustomModelsList(); SetActiveNav(NavToolsBtn, PageTools); }
    private void NavDevBtn_Click(object sender, RoutedEventArgs e) => SetActiveNav(NavDevBtn, PageDev);
    private void NavSettingsBtn_Click(object sender, RoutedEventArgs e) => SetActiveNav(NavSettingsBtn, PageSettings);

    // --- CO-OP FAVORITEN (SCHNELL-BEITRITT) ---

    private void AddFavServerBtn_Click(object sender, RoutedEventArgs e)
    {
        AddFavServerRow.Visibility = AddFavServerRow.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
    }

    private void SaveFavServerBtn_Click(object sender, RoutedEventArgs e)
    {
        var name = string.IsNullOrWhiteSpace(NewFavNameBox.Text) ? "Co-op Server" : NewFavNameBox.Text.Trim();
        var ip = string.IsNullOrWhiteSpace(NewFavIpBox.Text) ? "127.0.0.1" : NewFavIpBox.Text.Trim();
        int port = int.TryParse(NewFavPortBox.Text.Trim(), out var p) ? Math.Clamp(p, 1, 65535) : 7777;
        _config.FavoriteServers.Add(new FavoriteServer { Name = name, Ip = ip, Port = port });
        _config.Save();
        AddFavServerRow.Visibility = Visibility.Collapsed;
        RefreshFavoriteServers();
    }

    private void RefreshFavoriteServers()
    {
        HomeFavServersPanel.Children.Clear();
        if (_config.FavoriteServers.Count == 0)
        {
            HomeFavServersPanel.Children.Add(new TextBlock
            {
                Text = "Noch keine Server gespeichert — klicke auf „+ Server“ für 1-Klick-Co-op-Join.",
                Foreground = (Brush)FindResource("TextMuted"),
                FontSize = 11.2,
                TextWrapping = TextWrapping.Wrap
            });
            return;
        }

        for (int i = 0; i < _config.FavoriteServers.Count; i++)
        {
            var srv = _config.FavoriteServers[i];
            int idx = i;
            var row = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(18, 26, 40)),
                BorderBrush = (Brush)FindResource("BorderSubtle"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(7),
                Padding = new Thickness(10, 6, 8, 6),
                Margin = new Thickness(0, 0, 0, 6)
            };
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var info = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            info.Children.Add(new TextBlock { Text = srv.Name, Foreground = (Brush)FindResource("TextMain"), FontSize = 12, FontWeight = FontWeights.SemiBold });
            info.Children.Add(new TextBlock { Text = $"{srv.Ip}:{srv.Port}", Foreground = (Brush)FindResource("TextMuted"), FontSize = 10.5 });
            Grid.SetColumn(info, 0);
            grid.Children.Add(info);

            var btns = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            var joinBtn = new Button
            {
                Style = (Style)FindResource("PrimaryPlayButton"),
                Content = "⚡ Join",
                FontSize = 11,
                Padding = new Thickness(10, 4, 10, 4),
                Margin = new Thickness(0, 0, 6, 0)
            };
            joinBtn.Click += (_, _) => JoinFavoriteServer(srv);
            btns.Children.Add(joinBtn);

            var delBtn = new Button
            {
                Style = (Style)FindResource("SecondaryButton"),
                Content = "✕",
                FontSize = 10.5,
                Padding = new Thickness(7, 4, 7, 4)
            };
            delBtn.Click += (_, _) =>
            {
                if (idx >= 0 && idx < _config.FavoriteServers.Count)
                {
                    _config.FavoriteServers.RemoveAt(idx);
                    _config.Save();
                    RefreshFavoriteServers();
                }
            };
            btns.Children.Add(delBtn);

            Grid.SetColumn(btns, 1);
            grid.Children.Add(btns);
            row.Child = grid;
            HomeFavServersPanel.Children.Add(row);
        }
    }

    private void JoinFavoriteServer(FavoriteServer srv)
    {
        if (_isBusy || _isGameRunning) return;
        SyncConfigFromUI();
        var args = new List<string>
        {
            $"--quality={_config.GraphicsQuality}",
            $"--name={_config.PlayerName}",
            $"--join={srv.Ip}",
            $"--port={srv.Port}"
        };

        bool ok = _config.IsGameInstalled
            ? LaunchInstalledGame(args, out var err, trackSession: true)
            : LaunchGodotDev(args, out err);

        if (ok)
        {
            LaunchStatusTitle.Text = $"Verbinde mit {srv.Name}… ⚡";
            LaunchStatusSub.Text = $"{srv.Ip}:{srv.Port}";
        }
        else
        {
            MessageBox.Show(err, "Direkt-Beitritt fehlgeschlagen", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    // --- ROADMAP-BOARD ---

    private async void RefreshRoadmapBtn_Click(object sender, RoutedEventArgs e) => await LoadRoadmapAsync();

    private async Task LoadRoadmapAsync()
    {
        RoadmapColumnsGrid.Children.Clear();
        RoadmapSubText.Text = "Lade Roadmap…";

        string? localRoadmap = new[]
        {
            !string.IsNullOrWhiteSpace(_config.ProjectDir) ? Path.Combine(_config.ProjectDir, "roadmap.json") : "",
            !string.IsNullOrWhiteSpace(_config.InstallDir) ? Path.Combine(_config.InstallDir, "roadmap.json") : "",
            Path.Combine(AppContext.BaseDirectory, "roadmap.json")
        }.FirstOrDefault(p => !string.IsNullOrWhiteSpace(p) && File.Exists(p));

        var rawJson = await UpdateService.FetchRoadmapJsonAsync(_config.UpdateManifestUrl, localRoadmap);
        if (string.IsNullOrWhiteSpace(rawJson))
        {
            RoadmapSubText.Text = "Roadmap konnte nicht geladen werden (offline und keine lokale roadmap.json gefunden).";
            return;
        }

        try
        {
            using var doc = JsonDocument.Parse(rawJson);
            var root = doc.RootElement;
            var updated = root.TryGetProperty("updated", out var up) ? up.GetString() : "";
            RoadmapSubText.Text = string.IsNullOrWhiteSpace(updated)
                ? "Offizielle Entwicklungs-Roadmap für DataCenter Tycoon."
                : $"Offizielle Entwicklungs-Roadmap • Stand: {updated}";

            if (!root.TryGetProperty("columns", out var cols) || cols.ValueKind != JsonValueKind.Array)
                return;

            int colIdx = 0;
            Color[] colAccents = [Color.FromRgb(77, 163, 255), Color.FromRgb(255, 184, 48), Color.FromRgb(36, 216, 122)];
            string[] colIcons = ["📋", "⚙", "✅"];

            foreach (var col in cols.EnumerateArray())
            {
                var cTitle = col.TryGetProperty("title", out var tp) ? (tp.GetString() ?? "") : "";
                var accent = colAccents[colIdx % colAccents.Length];
                var icon = colIcons[colIdx % colIcons.Length];

                var colCard = new Border
                {
                    Background = new SolidColorBrush(Color.FromRgb(16, 23, 35)),
                    BorderBrush = new SolidColorBrush(Color.FromArgb(120, accent.R, accent.G, accent.B)),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(11),
                    Padding = new Thickness(14, 12, 14, 12),
                    Margin = new Thickness(colIdx == 0 ? 0 : 6, 0, colIdx == 2 ? 0 : 6, 0)
                };

                var colGrid = new Grid();
                colGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                colGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

                var colHeader = new TextBlock
                {
                    Text = $"{icon}  {cTitle.ToUpperInvariant()}",
                    Foreground = new SolidColorBrush(accent),
                    FontWeight = FontWeights.Bold,
                    FontSize = 13,
                    Margin = new Thickness(2, 0, 0, 10)
                };
                Grid.SetRow(colHeader, 0);
                colGrid.Children.Add(colHeader);

                var itemsStack = new StackPanel();
                if (col.TryGetProperty("items", out var items) && items.ValueKind == JsonValueKind.Array)
                {
                    foreach (var it in items.EnumerateArray())
                    {
                        var iTag = it.TryGetProperty("tag", out var tg) ? (tg.GetString() ?? "gameplay") : "gameplay";
                        var iVer = it.TryGetProperty("version", out var iv) ? (iv.GetString() ?? "") : "";
                        var iTitle = it.TryGetProperty("title", out var itl) ? (itl.GetString() ?? "") : "";
                        var iDesc = it.TryGetProperty("desc", out var idsc) ? (idsc.GetString() ?? "") : "";
                        var meta = GetTagMeta(iTag);

                        var itemCard = new Border
                        {
                            Background = (Brush)FindResource("BgCard"),
                            BorderBrush = (Brush)FindResource("BorderSubtle"),
                            BorderThickness = new Thickness(1),
                            CornerRadius = new CornerRadius(9),
                            Padding = new Thickness(12, 10, 12, 10),
                            Margin = new Thickness(0, 0, 0, 9)
                        };
                        var st = new StackPanel();
                        var topRow = new DockPanel { Margin = new Thickness(0, 0, 0, 6) };
                        if (!string.IsNullOrWhiteSpace(iVer))
                        {
                            var verTb = new TextBlock { Text = iVer, Foreground = (Brush)FindResource("TextMuted"), FontSize = 11, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center };
                            DockPanel.SetDock(verTb, Dock.Right);
                            topRow.Children.Add(verTb);
                        }
                        topRow.Children.Add(new Border
                        {
                            Background = new SolidColorBrush(meta.Bg),
                            BorderBrush = new SolidColorBrush(meta.Border),
                            BorderThickness = new Thickness(1),
                            CornerRadius = new CornerRadius(5),
                            Padding = new Thickness(7, 2, 7, 2),
                            HorizontalAlignment = HorizontalAlignment.Left,
                            Child = new TextBlock { Text = meta.Label, Foreground = new SolidColorBrush(meta.Fg), FontSize = 9.5, FontWeight = FontWeights.Bold }
                        });
                        st.Children.Add(topRow);
                        st.Children.Add(new TextBlock { Text = iTitle, Foreground = (Brush)FindResource("TextMain"), FontSize = 13, FontWeight = FontWeights.Bold, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 4) });
                        st.Children.Add(new TextBlock { Text = iDesc, Foreground = new SolidColorBrush(Color.FromRgb(166, 186, 208)), FontSize = 11.5, TextWrapping = TextWrapping.Wrap });
                        itemCard.Child = st;
                        itemsStack.Children.Add(itemCard);
                    }
                }

                var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = itemsStack };
                Grid.SetRow(sv, 1);
                colGrid.Children.Add(sv);
                colCard.Child = colGrid;
                RoadmapColumnsGrid.Children.Add(colCard);
                colIdx++;
            }
        }
        catch (Exception ex)
        {
            RoadmapSubText.Text = $"Roadmap-Fehler: {ex.Message}";
        }
    }

    // --- WERKZEUGE: SAVEGAME-MANAGER, CUSTOM-MODELLE (DRAG & DROP) & BUG-DIAGNOSE ---

    private void ManualBackupBtn_Click(object sender, RoutedEventArgs e)
    {
        var (_, msg, _) = UpdateService.CreateSavesBackup("manual");
        BackupStatusText.Text = msg;
        RefreshBackupsList();
    }

    private void OpenBackupsBtn_Click(object sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(LauncherConfig.BackupsDir);
        Process.Start(new ProcessStartInfo { FileName = LauncherConfig.BackupsDir, UseShellExecute = true });
    }

    private void RefreshBackupsList()
    {
        BackupsListPanel.Children.Clear();
        Directory.CreateDirectory(LauncherConfig.BackupsDir);
        var files = Directory.GetFiles(LauncherConfig.BackupsDir, "saves_*.zip")
            .OrderByDescending(File.GetCreationTimeUtc)
            .Take(8)
            .ToList();

        if (files.Count == 0)
        {
            BackupsListPanel.Children.Add(new TextBlock
            {
                Text = "Noch keine Backups angelegt. Klicke auf „💾 Jetzt sichern“ oder starte ein Update.",
                Foreground = (Brush)FindResource("TextMuted"),
                FontSize = 12
            });
            return;
        }

        foreach (var f in files)
        {
            var fi = new FileInfo(f);
            var row = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(18, 26, 40)),
                BorderBrush = (Brush)FindResource("BorderSubtle"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(7),
                Padding = new Thickness(12, 8, 10, 8),
                Margin = new Thickness(0, 0, 0, 6)
            };
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var info = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            info.Children.Add(new TextBlock { Text = fi.Name, Foreground = (Brush)FindResource("TextMain"), FontSize = 12.2, FontWeight = FontWeights.SemiBold });
            info.Children.Add(new TextBlock { Text = $"{fi.CreationTime:dd.MM.yyyy HH:mm}  •  {fi.Length / 1024.0:F0} KB", Foreground = (Brush)FindResource("TextMuted"), FontSize = 11 });
            Grid.SetColumn(info, 0);
            grid.Children.Add(info);

            var restoreBtn = new Button
            {
                Style = (Style)FindResource("SecondaryButton"),
                Content = "↩ Wiederherstellen",
                FontSize = 11.5,
                Padding = new Thickness(10, 5, 10, 5)
            };
            restoreBtn.Click += (_, _) =>
            {
                if (MessageBox.Show($"Spielstände aus „{fi.Name}“ wiederherstellen?\n(Vorher wird automatisch ein Sicherheits-Backup deiner aktuellen Spielstände erstellt.)",
                    "Backup wiederherstellen", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes)
                {
                    var (_, msg) = UpdateService.RestoreSavesBackup(f);
                    BackupStatusText.Text = msg;
                    RefreshBackupsList();
                }
            };
            Grid.SetColumn(restoreBtn, 1);
            grid.Children.Add(restoreBtn);
            row.Child = grid;
            BackupsListPanel.Children.Add(row);
        }
    }

    private string GetCustomModelsDir()
    {
        string dir = _config.IsGameInstalled
            ? Path.Combine(_config.InstallDir, "custom_models")
            : (_config.IsDeveloperEnvironment
                ? Path.Combine(_config.ProjectDir, "assets", "models")
                : Path.Combine(LauncherConfig.AppDataDir, "custom_models"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    private void ModelDropZone_DragOver(object sender, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private void ModelDropZone_Drop(object sender, DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(DataFormats.FileDrop)) return;
        var files = (string[])e.Data.GetData(DataFormats.FileDrop);
        ImportCustomModelFiles(files);
    }

    private void AddCustomModelBtn_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Title = "Eigene 3D-Modelle (.glb) auswählen",
            Filter = "glTF 2.0 Modell (*.glb)|*.glb",
            Multiselect = true
        };
        if (dlg.ShowDialog() == true)
            ImportCustomModelFiles(dlg.FileNames);
    }

    private void ImportCustomModelFiles(IEnumerable<string> paths)
    {
        var dir = GetCustomModelsDir();
        int copied = 0;
        foreach (var p in paths)
        {
            if (File.Exists(p) && p.EndsWith(".glb", StringComparison.OrdinalIgnoreCase))
            {
                File.Copy(p, Path.Combine(dir, Path.GetFileName(p)), overwrite: true);
                copied++;
            }
        }
        ModelsStatusText.Text = copied > 0
            ? $"✅ {copied} .glb-Modell(e) nach {dir} kopiert!"
            : "⚠ Bitte nur .glb-Dateien hineinziehen.";
        RefreshCustomModelsList();
    }

    private void RefreshCustomModelsList()
    {
        CustomModelsListPanel.Children.Clear();
        var dir = GetCustomModelsDir();
        var files = Directory.GetFiles(dir, "*.glb")
            .Concat(Directory.GetFiles(dir, "*.glb.disabled"))
            .OrderBy(Path.GetFileName)
            .ToList();

        if (files.Count == 0)
        {
            CustomModelsListPanel.Children.Add(new TextBlock
            {
                Text = $"Noch keine eigenen .glb-Modelle in {dir}.",
                Foreground = (Brush)FindResource("TextMuted"),
                FontSize = 12
            });
            return;
        }

        foreach (var f in files)
        {
            bool enabled = f.EndsWith(".glb", StringComparison.OrdinalIgnoreCase);
            var fi = new FileInfo(f);
            var row = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(18, 26, 40)),
                BorderBrush = enabled ? (Brush)FindResource("AccentGreen") : (Brush)FindResource("BorderSubtle"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(7),
                Padding = new Thickness(12, 7, 10, 7),
                Margin = new Thickness(0, 0, 0, 6)
            };
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var displayName = fi.Name.Replace(".disabled", "", StringComparison.OrdinalIgnoreCase);
            var info = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            info.Children.Add(new TextBlock
            {
                Text = $"{(enabled ? "🟢" : "⚪")}  {displayName}",
                Foreground = enabled ? (Brush)FindResource("TextMain") : (Brush)FindResource("TextMuted"),
                FontSize = 12.2,
                FontWeight = FontWeights.SemiBold
            });
            info.Children.Add(new TextBlock { Text = $"{fi.Length / 1048576.0:F1} MB  •  {(enabled ? "Aktiv" : "Deaktiviert")}", Foreground = (Brush)FindResource("TextMuted"), FontSize = 10.8 });
            Grid.SetColumn(info, 0);
            grid.Children.Add(info);

            var btns = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            var toggleBtn = new Button
            {
                Style = (Style)FindResource("SecondaryButton"),
                Content = enabled ? "Deaktivieren" : "Aktivieren",
                FontSize = 11.2,
                Padding = new Thickness(10, 4, 10, 4),
                Margin = new Thickness(0, 0, 6, 0)
            };
            toggleBtn.Click += (_, _) =>
            {
                try
                {
                    var target = enabled ? f + ".disabled" : f[..^".disabled".Length];
                    if (File.Exists(target)) File.Delete(target);
                    File.Move(f, target);
                    RefreshCustomModelsList();
                }
                catch (Exception ex) { ModelsStatusText.Text = $"Fehler: {ex.Message}"; }
            };
            btns.Children.Add(toggleBtn);

            var delBtn = new Button
            {
                Style = (Style)FindResource("SecondaryButton"),
                Content = "🗑",
                FontSize = 11.2,
                Padding = new Thickness(8, 4, 8, 4)
            };
            delBtn.Click += (_, _) =>
            {
                if (MessageBox.Show($"Modell „{displayName}“ wirklich löschen?", "Modell löschen", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes)
                {
                    try { File.Delete(f); RefreshCustomModelsList(); } catch { }
                }
            };
            btns.Children.Add(delBtn);

            Grid.SetColumn(btns, 1);
            grid.Children.Add(btns);
            row.Child = grid;
            CustomModelsListPanel.Children.Add(row);
        }
    }

    private void ReportBugBtn_Click(object sender, RoutedEventArgs e)
    {
        var (ok, msg, zipPath) = UpdateService.CreateDiagnosticZip(_config);
        DiagStatusText.Text = msg;
        if (ok && File.Exists(zipPath))
        {
            Process.Start(new ProcessStartInfo { FileName = "explorer.exe", Arguments = $"/select,\"{zipPath}\"", UseShellExecute = true });
        }
        var repo = UpdateService.NormalizeGitHubRepo(_config.UpdateManifestUrl);
        var issueUrl = string.IsNullOrWhiteSpace(repo)
            ? "https://github.com/RazerFazer-lang/DataCenter-Tycoon/issues/new"
            : $"https://github.com/{repo}/issues/new";
        Process.Start(new ProcessStartInfo { FileName = issueUrl, UseShellExecute = true });
    }

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

    private void OpenLogsBtn_Click(object sender, RoutedEventArgs e)
    {
        // Godot 4 schreibt auf dem PC standardmäßig nach user://logs/godot.log
        var dir = Path.Combine(LauncherConfig.GetGodotUserDataDir(), "logs");
        Directory.CreateDirectory(dir);
        var latest = Path.Combine(dir, "godot.log");
        var psi = File.Exists(latest)
            ? new ProcessStartInfo { FileName = "explorer.exe", Arguments = $"/select,\"{latest}\"", UseShellExecute = true }
            : new ProcessStartInfo { FileName = dir, UseShellExecute = true };
        Process.Start(psi);
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
