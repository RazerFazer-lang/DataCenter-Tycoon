using System.Text;
using DataCenterLauncher;

namespace DataCenterLauncher.DeltaTool;

// "DeltaTool selftest": prüft Absturz-Erkennung und Bereinigung (ohne echten Absturz)
// sowie Bauen/Anwenden kleiner Updates mit künstlichen Ordnern, inkl. Fehlerfällen.
internal static class SelfTest
{
    private static int _checks;
    private static readonly List<string> Failures = new();

    public static int Run()
    {
        Console.WriteLine("== Absturzbericht ==");
        CrashTests();
        Console.WriteLine("== Kleine Updates ==");
        DeltaTests();

        if (Failures.Count == 0)
        {
            Console.WriteLine($"DELTA OK selftest checks={_checks}");
            return 0;
        }
        Console.WriteLine($"DELTA FEHLER selftest: {Failures.Count} von {_checks} Prüfungen fehlgeschlagen: {string.Join("; ", Failures)}");
        return 1;
    }

    private static void Check(bool ok, string name)
    {
        _checks++;
        Console.WriteLine($"  {(ok ? "ok    " : "FEHLER")} {name}");
        if (!ok) Failures.Add(name);
    }

    // --- Absturzbericht ---

    private const string FakeProfile = @"C:\Users\TestUser";

    private static CrashContext Ctx(string zip = "") => new(
        GameVersion: "3.4.0",
        LauncherVersion: "3.4.0",
        Repo: "RazerFazer-lang/DataCenter-Tycoon",
        WindowsVersion: "Windows 11 (Build 26300, 64-Bit)",
        Gpu: "",
        Time: new DateTime(2026, 11, 26, 21, 40, 0),
        SessionLength: TimeSpan.FromMinutes(12),
        DiagnosticZipName: zip,
        UserProfile: FakeProfile,
        UserName: "TestUser",
        MachineName: "DESKTOP-TEST01");

    private const string NormalLog =
        "Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org\n" +
        "Vulkan 1.4.357 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 2080 SUPER\n" +
        "\n" +
        "[Netzwerk] Host gestartet auf Port 7777\n" +
        "====================\n" +
        "Spielstand gespeichert: C:/Users/TestUser/AppData/Roaming/Godot/app_userdata/DataCenter Tycoon Co-op/saves/slot1.save\n" +
        "[Netzwerk] Verbunden mit 127.0.0.1:7777\n" +
        "Spiel beendet.\n";

    private static string CrashLog()
    {
        var sb = new StringBuilder();
        sb.Append("Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org\n");
        sb.Append("Vulkan 1.4.357 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 2080 SUPER\n");
        sb.Append("[Netzwerk] Freund verbunden von 192.168.178.23:7777\n");
        sb.Append("[Netzwerk] Lokal 127.0.0.1 ok\n");
        sb.Append("Lade C:\\Users\\TestUser\\AppData\\Roaming\\Godot\\app_userdata\\DataCenter Tycoon Co-op\\saves\\slot1.save\n");
        sb.Append("debug password=geheim123 join_token: AbCdEf1234567890GhIjKl1234567890xyz\n");
        sb.Append("Benutzer testuser hat das Menü geöffnet\n");
        sb.Append("SCRIPT ERROR: Invalid access to property or key 'power_draw' on a base object of type 'Nil'.\n");
        sb.Append("          at: _update_rack (res://scripts/world/rack.gd:412)\n");
        sb.Append("          GDScript backtrace (most recent call first):\n");
        sb.Append("              [0] _update_rack (res://scripts/world/rack.gd:412)\n");
        sb.Append("ERROR: Condition \"!is_inside_tree()\" is true. Returning: Transform3D()\n");
        sb.Append("   at: get_global_transform (scene/3d/node_3d.cpp:345)\n");
        sb.Append("================================================================\n");
        sb.Append("CrashHandlerException: Program crashed with signal 11\n");
        sb.Append("Engine version: Godot Engine v4.7.2.stable.official (ed1daf0bf2a5c9f3e8d7b6a5c4d3e2f1a0b9c8d7)\n");
        sb.Append("Dumping the backtrace. Please include this when reporting the bug to the project developer.\n");
        for (int i = 0; i < 30; i++)
            sb.Append($"[{i}] error(-1): no debug info in PE/COFF executable\n");
        sb.Append("-- END OF C++ BACKTRACE --\n");
        sb.Append("================================================================\n");
        return sb.ToString();
    }

    private static void CrashTests()
    {
        var crash = CrashLog();

        var a = CrashReport.Analyze(-1073741819, crash, Ctx("DataCenterTycoon_Diagnose_2026-11-26_21-40.zip"));
        Check(a.IsCrash, "Absturz-Log + Exit-Code 0xC0000005 = Absturz");
        Check(a.Title.StartsWith("Absturz in v3.4.0: SCRIPT ERROR: Invalid access", StringComparison.Ordinal), $"Titel nennt erste Fehlerzeile ({a.Title})");
        Check(a.IssueUrl.StartsWith("https://github.com/RazerFazer-lang/DataCenter-Tycoon/issues/new?title=", StringComparison.Ordinal), "Issue-Link zeigt auf GitHub issues/new");
        Check(a.IssueUrl.Contains("&labels=crash&body=", StringComparison.Ordinal), "Issue-Link hat Label und Text");
        Check(a.IssueUrl.Length <= CrashReport.MaxUrlLength, $"Issue-Link kurz genug ({a.IssueUrl.Length} Zeichen)");
        var all = a.Title + "\n" + a.Body;
        Check(!all.Contains("TestUser", StringComparison.OrdinalIgnoreCase), "Benutzername entfernt");
        Check(all.Contains("%USERPROFILE%", StringComparison.Ordinal), "Profilpfad durch %USERPROFILE% ersetzt");
        Check(!all.Contains("192.168.178.23", StringComparison.Ordinal) && all.Contains("x.x.x.x:7777", StringComparison.Ordinal), "fremde IP durch x.x.x.x ersetzt");
        Check(all.Contains("127.0.0.1", StringComparison.Ordinal), "127.0.0.1 bleibt stehen");
        Check(!all.Contains("geheim123", StringComparison.Ordinal) && !all.Contains("AbCdEf1234567890", StringComparison.Ordinal), "Passwort und Token entfernt");
        Check(all.Contains("CrashHandlerException", StringComparison.Ordinal), "Absturz-Block im Text");
        Check(all.Contains("ähnliche Zeilen ausgelassen", StringComparison.Ordinal), "gleichartige Backtrace-Zeilen zusammengefasst");
        Check(a.Body.Contains("0xC0000005, Zugriffsverletzung", StringComparison.Ordinal), "Exit-Code lesbar");
        Check(a.Body.Contains("DataCenterTycoon_Diagnose_2026-11-26_21-40.zip", StringComparison.Ordinal), "Text bittet um Diagnose-ZIP");
        Check(a.Body.Contains("Windows 11", StringComparison.Ordinal), "Windows-Version im Text");

        var gpu = CrashReport.FindGpuInLog(crash);
        Check(gpu == "NVIDIA GeForce RTX 2080 SUPER (Vulkan 1.4.357, Forward+)", $"Grafikkarte aus Log ({gpu})");

        var b = CrashReport.Analyze(0, crash, Ctx());
        Check(b.IsCrash, "Absturz-Merkmal im Log reicht auch bei Exit-Code 0");

        var c = CrashReport.Analyze(0, NormalLog, Ctx());
        Check(!c.IsCrash && c.IssueUrl.Length == 0, "normales Beenden (Exit 0, kein Merkmal) ist kein Absturz");

        var d = CrashReport.Analyze(0, null, Ctx());
        Check(!d.IsCrash, "kein Log + Exit 0 ist kein Absturz");

        var e = CrashReport.Analyze(1, NormalLog, Ctx());
        Check(e.IsCrash && e.Title == "Absturz in v3.4.0: Exit-Code 1 (Fehler, z. B. im Task-Manager beendet)", $"Exit-Code 1 ohne Merkmal = Absturz ({e.Title})");
        Check(!e.Body.Contains("TestUser", StringComparison.OrdinalIgnoreCase), "normales Log im Bericht ebenfalls bereinigt");

        var f = CrashReport.Analyze(unchecked((int)0xC0000005), null, Ctx());
        Check(f.IsCrash && f.Body.Contains("Kein Log dieser Sitzung", StringComparison.Ordinal), "Absturz ohne Log hat trotzdem einen Bericht");

        // Riesiges Log mit langen Zeilen und Umlauten: Link bleibt unter 7000 Zeichen, Absturz-Block bleibt drin.
        var huge = new StringBuilder();
        for (int i = 0; i < 4000; i++)
            huge.Append($"ERROR: Überlauf {i} – sehr lange Zeile mit Umlauten äöüß und Pfad C:/Users/TestUser/x/{new string('y', 300)}\n");
        huge.Append(crash);
        var g = CrashReport.Analyze(-1073741819, huge.ToString(), Ctx());
        Check(g.IsCrash && g.IssueUrl.Length <= CrashReport.MaxUrlLength, $"riesiges Log: Link {g.IssueUrl.Length} Zeichen");
        Check(g.Body.Contains("CrashHandlerException", StringComparison.Ordinal), "riesiges Log: Absturz-Block bleibt im Text");
        Check(!g.Body.Contains("TestUser", StringComparison.OrdinalIgnoreCase), "riesiges Log: bereinigt");

        var s = CrashReport.Scrub(
            "C:/Users/TestUser/a C:\\\\Users\\\\TestUser\\\\b TESTUSER ok TestUser2 10.0.0.5:7777 0.0.0.0 999.1.1.1 " +
            "Windows 10.0.26300.0 v4.7.2.stable Token = \"xyz\" Join-Code: 4711 res://scripts/main.gd",
            FakeProfile, "TestUser", "DESKTOP-TEST01");
        Check(s.StartsWith("%USERPROFILE%/a %USERPROFILE%\\\\b <user> ok TestUser2 x.x.x.x:7777 x.x.x.x 999.1.1.1 Windows 10.0.26300.0 v4.7.2.stable", StringComparison.Ordinal),
            $"Bereinigung Pfade/Namen/IPs ({s})");
        Check(s.Contains("Token = <entfernt>", StringComparison.Ordinal) && s.Contains("Join-Code: <entfernt>", StringComparison.Ordinal) && s.EndsWith("res://scripts/main.gd", StringComparison.Ordinal),
            "Bereinigung Token/Join-Code, Pfade im Spiel bleiben");
    }

    // --- Kleine Updates ---

    private static void DeltaTests()
    {
        var root = Path.Combine(Path.GetTempPath(), $"dct_selftest_{Guid.NewGuid():N}");
        try
        {
            var oldDir = Path.Combine(root, "old");
            var newDir = Path.Combine(root, "new");
            Directory.CreateDirectory(Path.Combine(oldDir, "sub", "dir"));
            Directory.CreateDirectory(Path.Combine(newDir, "sub", "dir"));
            var rnd = new Random(42);

            byte[] big = RandomBytes(rnd, 3 * 1024 * 1024);
            byte[] same = RandomBytes(rnd, 100 * 1024);
            byte[] renamed = RandomBytes(rnd, 500 * 1024);
            byte[] inner = RandomBytes(rnd, 1024 * 1024);

            File.WriteAllBytes(Path.Combine(oldDir, "game.pck"), big);
            File.WriteAllBytes(Path.Combine(oldDir, "same.txt"), same);
            File.WriteAllBytes(Path.Combine(oldDir, "old_name.dat"), renamed);
            File.WriteAllText(Path.Combine(oldDir, "removed.txt"), "weg damit");
            File.WriteAllBytes(Path.Combine(oldDir, "sub", "dir", "inner.bin"), inner);
            File.WriteAllBytes(Path.Combine(oldDir, "empty.txt"), []);
            File.WriteAllText(Path.Combine(oldDir, "version.json"), "{\"version\": \"1.0.0\"}");

            // game.pck: 1000 Bytes eingefügt, 100 Bytes überschrieben, 5000 Bytes angehängt.
            var changed = new List<byte>(big);
            changed.InsertRange(1024 * 1024, RandomBytes(rnd, 1000));
            for (int i = 0; i < 100; i++) changed[2 * 1024 * 1024 + i] ^= 0x5A;
            changed.AddRange(RandomBytes(rnd, 5000));
            File.WriteAllBytes(Path.Combine(newDir, "game.pck"), changed.ToArray());
            File.WriteAllBytes(Path.Combine(newDir, "same.txt"), same);
            File.WriteAllBytes(Path.Combine(newDir, "new_name.dat"), renamed);
            File.WriteAllBytes(Path.Combine(newDir, "brand_new.bin"), RandomBytes(rnd, 200 * 1024));
            File.WriteAllBytes(Path.Combine(newDir, "sub", "dir", "inner.bin"), inner);
            File.WriteAllBytes(Path.Combine(newDir, "empty.txt"), []);
            File.WriteAllText(Path.Combine(newDir, "version.json"), "{\"version\": \"1.1.0\"}");

            var deltaFile = Path.Combine(root, DeltaPatch.AssetName("1.0.0", "1.1.0"));
            var built = DeltaPatch.Build(oldDir, newDir, deltaFile, "1.0.0", "1.1.0");
            Check(File.Exists(deltaFile), $"Delta gebaut ({built.DeltaBytes} Bytes, {built.Elapsed.TotalMilliseconds:F0} ms)");
            Check(built.ReusedBytes > 4L * 1024 * 1024, $"vorhandene Bytes wiederverwendet ({built.ReusedBytes})");
            Check(built.PayloadRawBytes < 700 * 1024, $"nur wenig neue Bytes ({built.PayloadRawBytes})");
            Check(built.RemovedCount == 2 && built.FileCount == 7, "Dateizahl und entfernte Dateien stimmen");

            var header = DeltaPatch.Verify(deltaFile);
            Check(header.From == "1.0.0" && header.To == "1.1.0" && header.Removed.SequenceEqual(["old_name.dat", "removed.txt"]), "Kopfdaten lesbar, entfernte Dateien vermerkt");
            Check(header.Files.Single(x => x.Path == "new_name.dat").Parts is [{ Kind: DeltaPart.KindOld, Path: "old_name.dat" }],
                "umbenannte Datei wird aus der alten kopiert");

            Check(DeltaPatch.TryParseAssetName("DataCenterTycoon-v3.4.0-from-v3.3.0-win64.delta", out var pf, out var pt) && pf == "3.3.0" && pt == "3.4.0",
                "Asset-Name wird erkannt");
            Check(!DeltaPatch.TryParseAssetName("DataCenterTycoon-v3.4.0-win64.zip", out _, out _), "ZIP ist kein Delta-Asset");

            // Anwenden und Byte für Byte vergleichen.
            var outDir = Path.Combine(root, "out");
            var applied = DeltaPatch.ApplyAsync(deltaFile, oldDir, outDir).GetAwaiter().GetResult();
            Check(TreesEqual(newDir, outDir, out var diff), $"angewendet = neue Version, Byte für Byte {diff}");
            Check(applied.FileCount == 7, "alle Dateien geschrieben");

            ExpectFail(() => DeltaPatch.ApplyAsync(deltaFile, oldDir, outDir).GetAwaiter().GetResult(), "nicht leer", "voller Zielordner wird abgelehnt");

            // Falsche installierte Version.
            var wrongVer = CopyTree(oldDir, Path.Combine(root, "wrongver"));
            File.WriteAllText(Path.Combine(wrongVer, "version.json"), "{\"version\": \"0.9.0\"}");
            var out2 = Path.Combine(root, "out2");
            ExpectFail(() => DeltaPatch.ApplyAsync(deltaFile, wrongVer, out2).GetAwaiter().GetResult(), "braucht v1.0.0", "falsche Version wird abgelehnt");
            Check(!Directory.Exists(out2), "bei falscher Version wird nichts geschrieben");

            // Veränderte alte Datei (gleiche Größe): Stück-Prüfsumme muss anschlagen, Ziel wird entfernt.
            var tampered = CopyTree(oldDir, Path.Combine(root, "tampered"));
            var tp = Path.Combine(tampered, "game.pck");
            var tb = File.ReadAllBytes(tp);
            tb[10] ^= 0xFF;
            File.WriteAllBytes(tp, tb);
            var out3 = Path.Combine(root, "out3");
            ExpectFail(() => DeltaPatch.ApplyAsync(deltaFile, tampered, out3).GetAwaiter().GetResult(), "verändert oder beschädigt", "veränderte alte Datei wird erkannt");
            Check(!Directory.Exists(out3), "halbfertiger Zielordner wird entfernt");

            // Fehlende alte Datei.
            var missing = CopyTree(oldDir, Path.Combine(root, "missing"));
            File.Delete(Path.Combine(missing, "same.txt"));
            ExpectFail(() => DeltaPatch.ApplyAsync(deltaFile, missing, Path.Combine(root, "out4")).GetAwaiter().GetResult(), "fehlt", "fehlende alte Datei wird erkannt");

            // Beschädigtes Paket: Byte in den Daten, Byte in den Kopfdaten, abgeschnitten.
            var bytes = File.ReadAllBytes(deltaFile);
            var badPayload = (byte[])bytes.Clone();
            badPayload[^10] ^= 0xFF;
            var badPayloadFile = Path.Combine(root, "bad_payload.delta");
            File.WriteAllBytes(badPayloadFile, badPayload);
            ExpectFail(() => DeltaPatch.ApplyAsync(badPayloadFile, oldDir, Path.Combine(root, "out5")).GetAwaiter().GetResult(), "Prüfsumme der Daten", "beschädigte Daten werden erkannt");
            Check(!Directory.Exists(Path.Combine(root, "out5")), "bei beschädigten Daten wird nichts geschrieben");

            var badHeader = (byte[])bytes.Clone();
            badHeader[60] ^= 0x01;
            var badHeaderFile = Path.Combine(root, "bad_header.delta");
            File.WriteAllBytes(badHeaderFile, badHeader);
            ExpectFail(() => DeltaPatch.ApplyAsync(badHeaderFile, oldDir, Path.Combine(root, "out6")).GetAwaiter().GetResult(), "Kopfdaten", "beschädigte Kopfdaten werden erkannt");

            var truncatedFile = Path.Combine(root, "truncated.delta");
            File.WriteAllBytes(truncatedFile, bytes.AsSpan(0, bytes.Length - 100).ToArray());
            ExpectFail(() => DeltaPatch.ApplyAsync(truncatedFile, oldDir, Path.Combine(root, "out7")).GetAwaiter().GetResult(), "unvollständig", "abgeschnittenes Paket wird erkannt");

            ExpectFail(() => DeltaPatch.Build(oldDir, newDir, Path.Combine(root, "x.delta"), "2.0.0", "1.1.0"), "alte version.json", "make prüft --from gegen version.json");
        }
        finally
        {
            Program.TryDeleteDir(root);
        }
    }

    private static void ExpectFail(Action a, string messagePart, string name)
    {
        try
        {
            a();
            Check(false, name + " (kein Fehler)");
        }
        catch (DeltaPatchException ex)
        {
            Check(ex.Message.Contains(messagePart, StringComparison.OrdinalIgnoreCase), $"{name} ({ex.Message})");
        }
    }

    private static byte[] RandomBytes(Random rnd, int n)
    {
        var b = new byte[n];
        rnd.NextBytes(b);
        return b;
    }

    private static string CopyTree(string src, string dst)
    {
        foreach (var f in Directory.GetFiles(src, "*", SearchOption.AllDirectories))
        {
            var t = Path.Combine(dst, Path.GetRelativePath(src, f));
            Directory.CreateDirectory(Path.GetDirectoryName(t)!);
            File.Copy(f, t);
        }
        return dst;
    }

    internal static bool TreesEqual(string a, string b, out string diff)
    {
        var fa = Directory.GetFiles(a, "*", SearchOption.AllDirectories).Select(f => Path.GetRelativePath(a, f)).OrderBy(x => x, StringComparer.Ordinal).ToList();
        var fb = Directory.GetFiles(b, "*", SearchOption.AllDirectories).Select(f => Path.GetRelativePath(b, f)).OrderBy(x => x, StringComparer.Ordinal).ToList();
        if (!fa.SequenceEqual(fb))
        {
            diff = "(Dateiliste unterschiedlich)";
            return false;
        }
        foreach (var rel in fa)
        {
            if (!File.ReadAllBytes(Path.Combine(a, rel)).AsSpan().SequenceEqual(File.ReadAllBytes(Path.Combine(b, rel))))
            {
                diff = $"({rel} unterschiedlich)";
                return false;
            }
        }
        diff = $"({fa.Count} Dateien gleich)";
        return true;
    }
}
