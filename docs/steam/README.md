# Steam vorbereiten (REL-07)

Stand v3.5: Das Spiel ist für Steam vorbereitet, **ohne** Steam-Konto und ohne Steam-Code im Projekt.
Alles, was Steam später braucht, hat eine feste Stelle. Ohne Steam läuft das Spiel genauso wie bisher.

## Was schon da ist

| Teil | Wo | Was es tut |
|---|---|---|
| Steam-Schnittstelle | `scripts/data/steam_bridge.gd` | Einziger Ort, der Steam anspricht. Ohne GodotSteam oder ohne App-ID tut jede Funktion nichts. |
| Erfolge | `scripts/autoload/achievement_manager.gd` | 19 Erfolge im Spiel, mit Seite im Hauptmenü und Meldung im HUD. Jeder freigeschaltete Erfolg geht über `SteamBridge.unlock_achievement()` auch an Steam. |
| Cloud-taugliche Daten | `user://` | Spielstände, Erfolge und Einstellungen liegen als kleine Textdateien in einem Ordner (siehe unten). |
| Store-Texte | `docs/steam/store_page.md` | Kurz- und Langbeschreibung auf Deutsch und Englisch, Merkmale, Tags, Systemanforderungen. |
| Erfolge für Steamworks | `docs/steam/achievements.md` | API-Namen, Titel und Beschreibungen zum Anlegen in Steamworks. |

## Schritte, sobald es ein Steam-Konto gibt

1. **Steamworks:** App anlegen (Steam Direct, einmalig 100 US-$). Die App-ID notieren.
2. **GodotSteam:** Das GDExtension-Plugin passend zu Godot 4.7 aus der offiziellen GodotSteam-Quelle nach `addons/godotsteam/` legen. Es meldet sich als Engine-Singleton `Steam`.
3. **App-ID eintragen:** In `scripts/data/steam_bridge.gd` die Konstante `APP_ID` setzen. Für Tests zusätzlich `steam_appid.txt` mit der ID neben die exe legen. Diese Datei gehört nicht in das Release.
4. **Erfolge anlegen:** Alle Einträge aus `docs/steam/achievements.md` in Steamworks unter *Stats & Achievements* mit genau diesen API-Namen anlegen und veröffentlichen.
5. **Steam Cloud (Auto-Cloud):** Unter *Steam Cloud → Root Paths* eintragen:
   - Root: `WinAppDataRoaming`, Unterordner: `Godot/app_userdata/DataCenter Tycoon Co-op`
   - Dateien: `saves/*.json` (Spielstände) und `achievements.cfg` (Erfolge)
   - **Nicht** synchronisieren: `settings.cfg` (Fenstergröße und Grafik passen nicht auf jeden PC), `saves/backups/`, `logs/`, `shader_cache/`, `vulkan/`
6. **Freundesliste:** `SteamBridge.set_status()` ist vorbereitet. In Steamworks unter *Rich Presence* den Token `#Status` mit dem Text `{#status}` anlegen.
7. **Netzwerk über Steam (später):** Co-op läuft heute über ENet mit IP und Port. Für Einladungen über Steam kommt ein `SteamMultiplayerPeer` aus GodotSteam an die Stelle von `ENetMultiplayerPeer` in `scripts/autoload/network_manager.gd`. Die Spiellogik bleibt dabei gleich, weil alle Aufrufe über Godots Multiplayer-API laufen.
8. **Build hochladen:** Mit SteamPipe (`steamcmd`) den Inhalt des Release-Ordners hochladen, also exe und pck ohne Launcher. Steam übernimmt dann Updates selbst.

## Was bewusst noch fehlt

- Kein GodotSteam im Projekt und keine App-ID. Nichts wird heruntergeladen, solange es kein Konto gibt.
- Kein Steam-Netzwerk. ENet mit LAN, VPN und Portfreigabe bleibt der Weg, siehe Pausemenü „So erreichen dich Freunde“.
