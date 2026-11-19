# DataCenter Tycoon Co-op (Godot 4 — v1.0.0 Release)

3D First-Person Co-op DataCenter Simulator (1–4 Spieler über eingebautes ENet) im **einheitlichen AAA Schiefergrau-&-Gold-Design** inkl. **eigenem nativen Windows-Launcher (`DataCenterLauncher.exe`)**, **PC-Shop mit Warenkorb & Teile-Lager**, **66 Hardware-Komponenten (DDR2–DDR5)**, **3-Tab Rack-Overlay**, **echten Einheiten (GB, TB, Mbit/Gbit, Watt — kein „CU“)**, **Rack-Vermietung mit Live-Support & Kundenanrufen**, **PC-Sitz- & Tipp-Animation**, **Sprinter-Lieferwagen** und **knackfreier 3D-Soundkulisse**.

## 1. Schnellstart über den eigenen Launcher
1. Doppelklicke auf **`Start_Launcher.bat`** (oder `dist\Freunde_Launcher\DataCenterLauncher.exe`).
2. **Auf deinem Entwickler-PC:** Klicke **`🛠 Dev-Start`** zum sofortigen Testen oder unter **`🛠 Release & Freunde`** auf **`📦 Windows-Build & Release-ZIP erstellen`** → erzeugt `dist\DataCenterTycoon-v1.0.0-win64.zip`.
3. **Für Freunde:** Lade `DataCenterTycoon-v1.0.0-win64.zip` als GitHub Release `v1.0.0` hoch — ihre `DataCenterLauncher.exe` erkennt automatisch **`🔄 UPDATE (v1.0.0)`**!

## 2. Steuerung (Nur Hand — Automatische Kontext-Interaktion!)
| Taste | Aktion |
|---|---|
| `WASD` + `Shift` + `Space` | Laufen / Sprinten / Springen |
| `E` / `Linksklick` | **Kontext-Hand:** PC = Hinsetzen & Windows-OS, Gelbe Buchse = Stromkabel, Blaue Buchse / Router = LAN-Kabel, Sicherung = An/Aus, Karton = Aufheben, Rack = 3-Tab Overlay / Chassis einschieben |
| `F` | **Rack-, Router- & Geräte-Overlay** öffnen |
| `Rechtsklick` | Kabel trennen/abbrechen, Modul aus Rack ausbauen oder Item ablegen |
| `R` | Rack / Kühler / USV vor dem Platzieren um 90° drehen |
| `Q` | Getragenes Item / Kabel ablegen oder Feuerlöscher zurückhängen |
| `H` | Steuerungs-Hilfe ein-/ausblenden |
| `ESC` | Vom PC aufstehen / Overlay schließen / Pause-Menü |

## 3. Kern-Ablauf in v1.0.0
1. **Leere Garage (`$1.800`):** Starte mit deiner abhakbaren 5-Schritte-Checkliste — nur PC-Tisch, Sicherung, alter 50-Mbit/s-DSL-Router & Werkbank stehen bereit.
2. **Einkaufen am Windows-PC (`[E]`):** Sammle im **CloudParts.de Shop** dein Rack, leere `1U / 2U / 4U` Server-Chassis und Einzelteile (`DDR2–DDR5 RAM`, CPUs, GPUs, HDD/SSD/NVMe, Kühlung, Netzteile) im **Warenkorb** und bestelle alles auf einmal.
3. **Lieferung & Aufbau:** Der **Cloud Express Sprinter** liefert Racks/Chassis vor dein Tor und legt gekaufte Bauteile direkt in dein **Teile-Lager**.
4. **3-Tab Rack-Overlay (`[E]`/`[F]`):** Schraube im Tab **`🔧 Hardware-Bau`** deine Bauteile aus dem Lager ein (mit Filtern `DDR2 | DDR3 | DDR4 | DDR5`), betrachte alles in der **`🖥 3D-Vorschau`** und wähle unter **`📊 Übersicht & Vermietung`** den Einsatzzweck (Webhosting, Game-Server, Cloud-Storage, Streaming, Datenbank, KI).
5. **Kunden-Support & Wachstum:** Behalte aktive User, RAM (GB), CPU, Speicher (TB) & Internet (Mbit/Gbit) im Blick — bei Überlastung schreiben Kunden Tickets oder rufen live per VoIP am PC an!
