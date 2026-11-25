extends Node
## Host-authoritative simulation state and RPC router for DataCenter Tycoon Co-op (v0.3).
## Supports 4U/6U Racks, 6 Interactive Server Component Categories (CPU/GPU/RAM/SSD/Cooling/PSU),
## UPS Backup Batteries, Rack Move/Sell, 3 Halls (Garage + Hall B + Enterprise Hall C),
## 4-Minute Day/Night Cycle, Daily kWh Electricity Bill, Contracts, AI Platform, and Emergencies.

signal world_snapshot_loaded
signal state_updated
## Ein Checklisten-Flag hat sich geändert (lokal oder vom Server für alle Spieler).
signal checklist_changed
signal racks_changed
signal coolers_changed
signal ups_changed
signal carts_changed
signal crates_changed
signal cables_changed
signal extinguisher_changed
## Auspacken: ein Gerät kommt aus seinem Karton (nur Anzeige, das Gerät steht schon).
signal unpack_started(entity_id: String, item_type: String, carton_pos: Vector3)
## Deckel des Altpapier-Containers klappt ("garage" / "nord").
signal paper_bin_used(site: String)
signal strip_loads_changed
signal room_level_changed
signal halle_nord_changed
signal delivery_site_changed
signal decor_items_changed
signal building_upgrades_changed
signal constructions_changed
signal van_updated
signal tickets_changed
signal call_changed
signal inventory_changed
## Sicherungen im Wand-Sicherungskasten oder der Sicherungsvorrat haben sich geändert.
signal fuses_changed
## Türen, Seitenwände und Antenne (Racks, Sicherungskasten, Router) wurden geöffnet/geschlossen.
signal panel_states_changed
## Motorisiertes Sektional-Garagentor (server-autoritativ synchronisiert).
signal garage_door_changed(is_open: bool)
signal cart_changed
signal shelf_changed
signal workbench_changed
## Live-Bewegung des Spielers an der Werkbank: {tool, item, xf, task, t}
signal workbench_hand_moved(data: Dictionary)
## Der Host hat einen Handgriff abgelehnt; die Vorab-Anzeige muss zurück.
signal workbench_task_rejected(task_id: String)
signal bench_supplies_changed
signal host_permissions_changed
signal world_ping_received(peer_id: int, world_pos: Vector3, kind: String, label: String)
signal player_emote_received(peer_id: int, emote_id: String)
signal daily_deals_changed

## Wenn aktiv, darf nur der Host (peer 1) Racks/Geräte verkaufen, Kredite aufnehmen, Mitarbeiter entlassen & Hallen ausbauen.
var host_only_destructive: bool = false
## Server-autoritativer Zustand des motorisierten Garagentors (true = offen, false = geschlossen).
var garage_door_open: bool = true

## Meilensteine A–D: Wetter, Kalt-/Warmgang-Airflow, Kabelmanagement, Karriere, Gebrauchtmarkt & Team-Aufträge
var weather_state: String = "clear" # "clear" | "cloudy" | "rain" | "storm" | "heatwave"
var _weather_timer: float = 95.0
var airflow_bonus: float = 0.0 # 0.0..0.30 (+30% Kühlleistung & geringerer Klima-Strom)
var cable_mgmt_bonus: float = 0.0 # 0.0..0.12 (+12% Umsatz-/Ruf-Bonus für saubere Kabelführung)
var daily_deals: Array = []
var career_completed: Array = []
var active_team_order: Dictionary = {}

const CAREER_MILESTONES := [
	{
		"id": "career_handwerk",
		"title": "Handwerk & Lokal-Webhosting",
		"client": "Keller & Söhne Handwerksverbund",
		"desc": "Betreibe mind. 1 Rack mit 15 CU Rechenleistung.",
		"req_racks": 1, "req_cu": 15, "req_room": 0, "req_ups": false, "req_rep": 0.0, "req_ai": 0,
		"reward": 1200, "rep_bonus": 4.0,
	},
	{
		"id": "career_esports",
		"title": "Regionaler Gameserver-Host",
		"client": "Nordliga eSports e.V.",
		"desc": "Betreibe mind. 2 Racks mit 45 CU bei stabiler Kühlung (< 65 °C).",
		"req_racks": 2, "req_cu": 45, "req_room": 0, "req_ups": false, "req_rep": 50.0, "req_ai": 0,
		"reward": 4500, "rep_bonus": 6.0,
	},
	{
		"id": "career_erp",
		"title": "Mittelstands-ERP & Cloud",
		"client": "Bergmann Maschinenbau GmbH",
		"desc": "Betreibe mind. 4 Racks mit 110 CU und mindestens 1 angeschlossener USV.",
		"req_racks": 4, "req_cu": 110, "req_room": 1, "req_ups": true, "req_rep": 60.0, "req_ai": 0,
		"reward": 12500, "rep_bonus": 8.0,
	},
	{
		"id": "career_bank",
		"title": "Hochverfügbarkeit (99,9 % SLA)",
		"client": "Hanseatische Privatbank AG",
		"desc": "Betreibe mind. 6 Racks mit 240 CU, USV & Kunden-Ruf ≥ 75.",
		"req_racks": 6, "req_cu": 240, "req_room": 1, "req_ups": true, "req_rep": 75.0, "req_ai": 0,
		"reward": 28000, "rep_bonus": 10.0,
	},
	{
		"id": "career_research",
		"title": "KI- & Forschungs-Rechenknoten",
		"client": "Norddeutscher Forschungsverbund",
		"desc": "Halle C aktiv, mind. 9 Racks, 420 CU & KI-Plattform Stufe 2+.",
		"req_racks": 9, "req_cu": 420, "req_room": 2, "req_ups": true, "req_rep": 80.0, "req_ai": 2,
		"reward": 65000, "rep_bonus": 12.0,
	},
]

const USED_SELLERS: Array[String] = [
	"Insolvenzmasse Bürotechnik Nord",
	"Leasing-Rückläufer RZ Süd",
	"Gebrauchtposten IT-Systemhaus",
	"Behörden-Ausmusterung",
]

const MAX_SHARED_PANELS := 512
## Vom Server geführter Zustand aller öffenbaren Abdeckungen: "<entity_id>|<panel_id>" -> true (nur offene).
var shared_open_panels: Dictionary = {}
signal event_logged(message: String, severity: String)
signal world_saved(display_name: String, is_autosave: bool)
signal daily_bill_charged(day_num: int, bill_amount: int, kwh_used: float)

const SIM_TICK_INTERVAL := 0.5
## Forschungsbaum: "mult" ist der Faktor auf den Wert "stat" bei der jeweiligen Stufe.
## "requires" nennt Zweige, die vorher mindestens diese Stufe brauchen.
const RESEARCH_TREE := {
	"cooling": {
		"label": "Kühltechnik", "desc": "Effizientere Kühlkörper und Luftführung.", "stat": "Abwärme",
		"requires": {},
		"levels": [{"cost": 2000, "mult": 0.90}, {"cost": 6000, "mult": 0.80}, {"cost": 15000, "mult": 0.70}],
	},
	"efficiency": {
		"label": "Energieeffizienz", "desc": "Bessere Netzteile und Spannungswandler.", "stat": "Stromverbrauch",
		"requires": {},
		"levels": [{"cost": 2000, "mult": 0.92}, {"cost": 6000, "mult": 0.85}, {"cost": 15000, "mult": 0.78}],
	},
	"reliability": {
		"label": "Zuverlässigkeit", "desc": "Monitoring und vorbeugende Wartung.", "stat": "Fehlerrate",
		"requires": {"cooling": 1},
		"levels": [{"cost": 2000, "mult": 0.85}, {"cost": 6000, "mult": 0.70}, {"cost": 15000, "mult": 0.55}],
	},
}
const RESEARCH_ORDER: Array[String] = ["cooling", "efficiency", "reliability"]
## Wasserschaden: Abstand zwischen zwei Lecks in Sekunden, betroffene Slots und Kosten (deutlich seltener!).
const WATER_LEAK_MIN_S := 540.0
const WATER_LEAK_MAX_S := 840.0
const WATER_LEAK_MAX_SLOTS := 2
const WATER_LEAK_COST := 150.0
const PAYOUT_CYCLE_SECONDS := 5.0
const AUTOSAVE_INTERVAL := 180.0
# Echtzeit: ein Spieltag dauert einen echten Tag.
## Echte Sekunden pro Spieltag (1440 = 24 Minuten, also 1 Spielminute pro Sekunde).
const DAY_LENGTH_SECONDS := 1440.0
# Grundpreis pro kWh. Der Tagespreis (electricity_rate) schwankt um diesen Wert.
const ELECTRICITY_RATE_PER_KWH := 1.45
const ELECTRICITY_RATE_MIN := 1.00
const ELECTRICITY_RATE_MAX := 2.05
# Maximale zufällige Änderung pro Tag in $/kWh.
const ELECTRICITY_RATE_DAILY_SWING := 0.18
# Anteil, um den sich der Preis pro Tag zum Grundpreis zurückbewegt (0..1).
const ELECTRICITY_RATE_REVERSION := 0.3
const SELL_REFUND_RATIO := 0.70
const CART_MAX_ITEMS := 4
const VAN_ARRIVE_DURATION := 4.4
const VAN_DEPART_DURATION := 4.4
# Mengen-Kisten & Lieferzonen-Limit (v2.1):
const BULK_PACK_MAX := 6
const DELIVERY_ZONE_MAX_CRATES := 16
# Lieferkosten je Fahrzeug-Kategorie + optionaler Sofort-Express + feste Lieferfenster (Uhrzeit im Spieltag):
const DELIVERY_FEES := {1: 15, 2: 45, 3: 95}
const DELIVERY_EXPRESS_SURCHARGE := 35
const DELIVERY_SLOTS_HOURS: Array[int] = [8, 12, 16, 20]
# 3 Liefer-Kategorien: Stufe 1 (Lieferwagen, 1 Fahrer), Stufe 2 (Kastenwagen 7,5t, 2 Mitarbeiter), Stufe 3 (LKW 18t, 3 Mitarbeiter)
const DELIVERY_TIER_META := {
	1: {
		"name": "Express-Lieferwagen",
		"staff": 1,
		"max_per_trip": 4,
		"speed_mult": 1.0,
		"method": "Sackkarre (1 Fahrer)",
		"icon": "🚐",
	},
	2: {
		"name": "Kastenwagen 7,5t",
		"staff": 2,
		"max_per_trip": 6,
		"speed_mult": 1.30,
		"method": "Ausklapp-Rampe & 2 Sackkarren (2 Mitarbeiter)",
		"icon": "🚚",
	},
	3: {
		"name": "Schwerlast-LKW 18t",
		"staff": 3,
		"max_per_trip": 9,
		"speed_mult": 1.55,
		"method": "Hydraulik-Ladebordwand & 3 Logistiker",
		"icon": "🚛",
	},
}
# Abladen in Fahrten: Der Fahrer trägt 1 Karton von Hand oder bis zu 4/6/9 auf Sackkarren/Hubwagen.
const VAN_TRIP_MAX_CRATES := 9
const VAN_DRIVER_EXIT_TIME := 2.2 # Fahrertür auf, aussteigen, zur Schiebetür gehen
const VAN_DRIVER_ENTER_TIME := 2.8 # Sackkarre verstauen bzw. Schiebetür zu, zur Fahrertür gehen, einsteigen
const VAN_LOAD_TIME_PER_CRATE := 1.2
const VAN_TRUCK_FETCH_TIME := 0.8 # Sackkarre aus dem Laderaum holen
const VAN_DROP_TIME_HAND := 0.9
const VAN_TRUCK_TILT_TIME := 0.6
const VAN_DROP_TIME_PER_CRATE_TRUCK := 0.8
const VAN_DRIVER_WALK_SPEED := 1.4
const VAN_DRIVER_TURN_TIME := 0.3
const VAN_CARGO_DOOR_POS := Vector3(0.1, 0.0, 10.9) # vor der Schiebetür des haltenden Wagens (Welt)
const VAN_DROP_STAND_OFFSET := 0.65 # Fahrer steht so weit vor den Ablageplätzen (Richtung Straße)
const VAN_DROP_STAND_OFFSET_TRUCK := 1.4 # mit Sackkarre: die Kartons auf der Schaufel stehen dann über den Plätzen
const VAN_PARCEL_ITEM := "parts_parcel" # Sammelpaket für bestellte Bauteile
const VAN_PARCEL_DROP_POS := Vector3(-1.3, 0.0, 7.35) # Holzpalette in der Lieferzone

const HALL_B_COST := 1800
const HALL_C_COST := 4800

const WALL_BREAKER_ID := "wall_breaker"
const WALL_ROUTER_ID := "wall_router"
const HALL_C_BREAKER_ID := "hall_c_breaker"
const HALL_C_ROUTER_ID := "hall_c_router"
const HALL_NORD_BREAKER_ID := "hall_nord_breaker"
const HALL_NORD_ROUTER_ID := "hall_nord_router"

const HALLE_NORD_COST := 8500
const HALLE_NORD_REQ_LEVEL := 3
const HALLE_NORD_ORIGIN := Vector3(0.0, 0.0, -320.0)
const HALLE_NORD_EXTRA_WATTS := 8500
const HALLE_NORD_EXTRA_MBPS := 10000.0

const ITEM_CATALOG := {
	"rack": {
		"name": "Server-Rack (4U)",
		"category": "placeable",
		"price": 400,
		"slots": 4,
		"max_pdu_watts": 3200,
		"passive_cooling": 0.0,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.24, 0.28, 0.34),
		"desc": "4 Einschub-Slots | Max. 3.200W PDU | Für Server & Switches",
	},
	"rack_pro": {
		"name": "Enterprise-Rack Pro (6U)",
		"category": "placeable",
		"price": 950,
		"unlock_level": 3,
		"slots": 6,
		"max_pdu_watts": 6000,
		"passive_cooling": 4.0,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.18, 0.44, 0.62),
		"desc": "Ab Firmen-Level 3 • 6 Einschub-Slots | Max. 6.000W PDU | Aktiv-Kühlung (-4°C)",
	},
	"empty_carton": {
		"name": "Leerer Karton",
		"category": "junk",
		"price": 0,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.64, 0.51, 0.37),
		"desc": "Verpackung. Gehört in den Altpapier-Container vor der Garage.",
	},
	"old_fuse": {
		"name": "Alte Schraubsicherung",
		"category": "junk",
		"price": 0,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"revenue_bonus": 0.0,
		"color": Color(0.55, 0.50, 0.42),
		"desc": "Ausgebaute Sicherung aus F2 • Mit [Q] ablegen",
	},
	"web_server": {
		"name": "1U Standard-Chassis",
		"category": "module",
		"price": 180,
		"watts": 110,
		"compute": 8,
		"heat": 3.0,
		"revenue_bonus": 0.0,
		"color": Color(0.28, 0.56, 0.82),
		"desc": "Kompaktes 1U-Servergehäuse (Basis-Board) • Am Rack mit CPU, RAM, GPU, SSD & PSU bestücken!",
	},
	"storage_server": {
		"name": "2U Storage-Chassis",
		"category": "module",
		"price": 280,
		"watts": 120,
		"compute": 10,
		"heat": 3.2,
		"revenue_bonus": 0.08,
		"color": Color(0.24, 0.68, 0.48),
		"desc": "8× Hot-Swap Drive-Bays • +8% Bonus-Einnahmen • Ideal für Cloud-Storage & Datenbanken",
	},
	"gpu_server": {
		"name": "4U GPU/AI-Chassis",
		"category": "module",
		"price": 420,
		"watts": 150,
		"compute": 14,
		"heat": 4.0,
		"revenue_bonus": 0.04,
		"color": Color(0.84, 0.58, 0.18),
		"desc": "Großes High-Airflow PCIe-Gehäuse • Optimiert für fette Grafikkarten, Streaming & KI-Hosting",
	},
	# --- Mainboards: werden im Rack-Menü in einen freien Einschub gekauft und eingebaut ---
	"mb_h110m_srv": {
		"name": "Bordwerk Mini M110",
		"category": "module", "mainboard": true, "mb_cat": "entry", "chassis": "web_server", "form": "1U",
		"price": 120, "watts": 35, "compute": 3, "base_compute": 3, "heat": 1.2, "revenue_bonus": 0.0,
		"color": Color(0.36, 0.62, 0.86),
		"desc": "Günstiges Single-Sockel-Board • 2 RAM-Bänke • Ideal für den ersten Webserver",
	},
	"mb_b450m_pro4": {
		"name": "Bordwerk Pro B45",
		"category": "module", "mainboard": true, "mb_cat": "entry", "chassis": "web_server", "form": "1U",
		"price": 160, "watts": 40, "compute": 4, "base_compute": 4, "heat": 1.4, "revenue_bonus": 0.0,
		"color": Color(0.36, 0.62, 0.86),
		"desc": "Einstiegs-Board • 4 RAM-Bänke • M.2-Steckplatz für schnelle NVMe-SSDs",
	},
	"mb_x570d4u": {
		"name": "Bordwerk Rack X57",
		"category": "module", "mainboard": true, "mb_cat": "entry", "chassis": "web_server", "form": "1U",
		"price": 230, "watts": 45, "compute": 5, "base_compute": 5, "heat": 1.6, "revenue_bonus": 0.02,
		"color": Color(0.36, 0.62, 0.86),
		"desc": "Server-Board mit Fernwartung (IPMI) • ECC-RAM • +2% Einnahmen",
	},
	"mb_x11scl_f": {
		"name": "Bordwerk Server S11",
		"category": "module", "mainboard": true, "mb_cat": "entry", "chassis": "web_server", "form": "1U",
		"price": 260, "watts": 40, "compute": 5, "base_compute": 5, "heat": 1.5, "revenue_bonus": 0.03,
		"color": Color(0.36, 0.62, 0.86),
		"desc": "Kernova-Board mit IPMI • Sehr stabil • +3% Einnahmen",
	},
	"mb_x11dpi_n": {
		"name": "Bordwerk Duo S11 (Dual-Sockel)",
		"category": "module", "mainboard": true, "mb_cat": "server", "chassis": "web_server", "form": "1U",
		"price": 380, "watts": 60, "compute": 7, "base_compute": 7, "heat": 2.2, "revenue_bonus": 0.04,
		"color": Color(0.52, 0.48, 0.90),
		"desc": "2 Kernova-Sockel • 16 RAM-Bänke • Für Webhosting mit vielen Nutzern",
	},
	"mb_romed8_2t": {
		"name": "Bordwerk Rack R8",
		"category": "module", "mainboard": true, "mb_cat": "server", "chassis": "web_server", "form": "1U",
		"price": 520, "watts": 70, "compute": 9, "base_compute": 9, "heat": 2.6, "revenue_bonus": 0.05,
		"color": Color(0.52, 0.48, 0.90),
		"desc": "Quarvex-Board • 8 RAM-Kanäle • 2× 10-GbE • +5% Einnahmen",
	},
	"mb_mz73_lm0": {
		"name": "Bordwerk Duo R73 (Dual Quarvex)",
		"category": "module", "mainboard": true, "mb_cat": "server", "chassis": "web_server", "form": "1U",
		"price": 780, "watts": 85, "compute": 11, "base_compute": 11, "heat": 3.0, "revenue_bonus": 0.06,
		"color": Color(0.52, 0.48, 0.90),
		"desc": "2 Quarvex-Sockel • 24 RAM-Bänke • Für Datenbanken & große Kunden",
	},
	"mb_x13dei_t": {
		"name": "Bordwerk Duo S13 (Dual Kernova)",
		"category": "module", "mainboard": true, "mb_cat": "server", "chassis": "web_server", "form": "1U",
		"price": 950, "watts": 90, "compute": 12, "base_compute": 12, "heat": 3.2, "revenue_bonus": 0.07,
		"color": Color(0.52, 0.48, 0.90),
		"desc": "Aktuelle Dual-Kernova-Plattform • DDR5 • +7% Einnahmen",
	},
	"mb_x10sdv_4c": {
		"name": "Bordwerk NAS N10",
		"category": "module", "mainboard": true, "mb_cat": "storage", "chassis": "storage_server", "form": "2U",
		"price": 240, "watts": 35, "compute": 5, "base_compute": 5, "heat": 1.3, "revenue_bonus": 0.08,
		"color": Color(0.24, 0.68, 0.48),
		"desc": "Sparsames NAS-Board • 6 SATA-Ports • +8% Einnahmen bei Speicher",
	},
	"mb_x11ssh_ctf": {
		"name": "Bordwerk Speicher N11 (SAS)",
		"category": "module", "mainboard": true, "mb_cat": "storage", "chassis": "storage_server", "form": "2U",
		"price": 340, "watts": 50, "compute": 6, "base_compute": 6, "heat": 1.8, "revenue_bonus": 0.09,
		"color": Color(0.24, 0.68, 0.48),
		"desc": "SAS-Controller onboard • 8 Hot-Swap-Laufwerke • +9% Einnahmen",
	},
	"mb_h12ssl_nt": {
		"name": "Bordwerk Speicher N12",
		"category": "module", "mainboard": true, "mb_cat": "storage", "chassis": "storage_server", "form": "2U",
		"price": 520, "watts": 65, "compute": 8, "base_compute": 8, "heat": 2.3, "revenue_bonus": 0.11,
		"color": Color(0.24, 0.68, 0.48),
		"desc": "Quarvex-Storage-Board • viele NVMe-Lanes • +11% Einnahmen",
	},
	"mb_genoad8x_2t": {
		"name": "Bordwerk Speicher N8X",
		"category": "module", "mainboard": true, "mb_cat": "storage", "chassis": "storage_server", "form": "2U",
		"price": 860, "watts": 80, "compute": 10, "base_compute": 10, "heat": 2.8, "revenue_bonus": 0.14,
		"color": Color(0.24, 0.68, 0.48),
		"desc": "All-Flash-Plattform • DDR5 • +14% Einnahmen bei Cloud-Speicher",
	},
	"mb_ws_x299_sage": {
		"name": "Bordwerk Grafik G4 (4× PCIe)",
		"category": "module", "mainboard": true, "mb_cat": "gpu", "chassis": "gpu_server", "form": "4U",
		"price": 420, "watts": 70, "compute": 10, "base_compute": 10, "heat": 2.6, "revenue_bonus": 0.03,
		"color": Color(0.84, 0.58, 0.18),
		"desc": "4 PCIe-x16-Plätze • Für Streaming & Render-Server",
	},
	"mb_trx50_sage": {
		"name": "Bordwerk Grafik G3",
		"category": "module", "mainboard": true, "mb_cat": "gpu", "chassis": "gpu_server", "form": "4U",
		"price": 680, "watts": 85, "compute": 12, "base_compute": 12, "heat": 3.0, "revenue_bonus": 0.05,
		"color": Color(0.84, 0.58, 0.18),
		"desc": "Quarvex-Board • 3 GPU-Plätze • +5% Einnahmen",
	},
	"mb_wrx90e_sage": {
		"name": "Bordwerk Grafik G7",
		"category": "module", "mainboard": true, "mb_cat": "gpu", "chassis": "gpu_server", "form": "4U",
		"price": 980, "watts": 100, "compute": 14, "base_compute": 14, "heat": 3.6, "revenue_bonus": 0.07,
		"color": Color(0.84, 0.58, 0.18),
		"desc": "Quarvex Werkstatt • 7 PCIe-5.0-Plätze • Für KI-Hosting",
	},
	"mb_hgx_8gpu": {
		"name": "Bordwerk KI-Basis 8-GPU",
		"category": "module", "mainboard": true, "mb_cat": "gpu", "chassis": "gpu_server", "form": "4U",
		"price": 1450, "watts": 130, "compute": 18, "base_compute": 18, "heat": 4.4, "revenue_bonus": 0.10,
		"color": Color(0.84, 0.58, 0.18),
		"desc": "Rechenzentrums-Board für KI-Beschleuniger • +10% Einnahmen",
	},
	"net_switch": {
		"name": "Rack-Switch 1U (24-Port)",
		"category": "module",
		"price": 200,
		"watts": 65,
		"compute": 0,
		"heat": 1.2,
		"revenue_bonus": 0.0,
		"color": Color(0.24, 0.62, 0.72),
		"desc": "Leitet LAN-Netzwerk im Rack an bis zu 3 weitere Racks weiter",
	},
	"cooler": {
		"name": "Klimaanlage AC-1",
		"category": "placeable",
		"price": 350,
		"watts": 300,
		"compute": 0,
		"heat": -18.0,
		"color": Color(0.82, 0.92, 0.98),
		"desc": "Goldis-Wärmepumpe (Außengerät) | -18°C | 300W | Nur auf dem Rasen rechts vom Garagentor, braucht ein Goldis Innengerät",
	},
	"chiller": {
		"name": "Industrie-Kühler AC-Pro",
		"category": "placeable",
		"price": 850,
		"watts": 540,
		"compute": 0,
		"heat": -40.0,
		"color": Color(0.28, 0.76, 0.98),
		"desc": "Goldis-Wärmepumpe Pro (Außengerät) | -40°C | 540W | Nur auf dem Rasen rechts vom Garagentor, braucht ein Goldis Innengerät",
	},
	"cool_k90": {
		"name": "Goldis Kaltwassersatz K-90",
		"category": "placeable",
		"price": 2400,
		"unlock_level": 2,
		"watts": 1050,
		"compute": 0,
		"heat": -90.0,
		"color": Color(0.30, 0.50, 0.62),
		"desc": "Profi-Außengerät mit vier Lüftern | -90°C | 1.050W | Rasen rechts vom Garagentor, braucht ein Goldis Innengerät",
	},
	"cool_inrow": {
		"name": "Goldis Reihenkühler R-130",
		"category": "placeable",
		"price": 5500,
		"unlock_level": 3,
		"watts": 1350,
		"compute": 0,
		"heat": -130.0,
		"relief": 6.0,
		"relief_radius": 2.2,
		"color": Color(0.16, 0.42, 0.60),
		"desc": "Steht drinnen neben den Racks | -130°C | 1.350W | Kein Innengerät nötig, nahe Racks laufen 6°C kühler",
	},
	"cool_tower": {
		"name": "Goldis Kälteturm T-220",
		"category": "placeable",
		"price": 9800,
		"unlock_level": 4,
		"watts": 2050,
		"compute": 0,
		"heat": -220.0,
		"color": Color(0.46, 0.54, 0.60),
		"desc": "Großer Rückkühlturm mit Dachlüftern | -220°C | 2.050W | Rasen rechts vom Garagentor, braucht ein Goldis Innengerät",
	},
	"cool_cdu": {
		"name": "Goldis Flüssigkühlung F-380",
		"category": "placeable",
		"price": 18000,
		"unlock_level": 5,
		"watts": 3000,
		"compute": 0,
		"heat": -380.0,
		"relief": 12.0,
		"relief_radius": 4.5,
		"color": Color(0.10, 0.48, 0.78),
		"desc": "Wasserkreislauf für die ganze Rack-Reihe, steht drinnen | -380°C | 3.000W | Kein Innengerät nötig, nahe Racks laufen 12°C kühler",
	},
	"indoor_unit": {
		"name": "Goldis Innengerät",
		"category": "placeable",
		"price": 180,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.94, 0.95, 0.96),
		"desc": "Wandgerät der Goldis-Wärmepumpe | Bläst die Kälte in den Raum | Kein Kabel nötig, läuft sobald ein Außengerät Strom hat",
	},
	"ups": {
		"name": "USV-Notstrom klein (2 kWh)",
		"category": "placeable",
		"price": 700,
		"watts": 300,
		"compute": 0,
		"heat": 1.0,
		"color": Color(0.95, 0.68, 0.14),
		"desc": "Übernimmt bei Blackout sofort | 2.000 Wh | bis 3.000 W | Lädt mit 300 W",
	},
	"ups_cabinet": {
		"name": "USV-Schrank (9 kWh)",
		"category": "placeable",
		"price": 3200,
		"unlock_level": 2,
		"watts": 1500,
		"compute": 0,
		"heat": 3.0,
		"color": Color(0.90, 0.62, 0.16),
		"desc": "Batterieschrank mit sechs Akku-Einschüben | 9.000 Wh | bis 9.000 W | Lädt mit 1.500 W",
	},
	"ups_container": {
		"name": "Batterie-Container (40 kWh)",
		"category": "placeable",
		"price": 12000,
		"unlock_level": 4,
		"watts": 6000,
		"compute": 0,
		"heat": 8.0,
		"color": Color(0.86, 0.46, 0.14),
		"desc": "Großspeicher mit eigener Klimatisierung | 40.000 Wh | bis 30.000 W | Lädt mit 6.000 W, braucht 2 m Platz",
	},
	"cart": {
		"name": "Schwerlast-Rollwagen",
		"category": "vehicle",
		"price": 220,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.22, 0.56, 0.92),
		"desc": "Transportiert bis zu 4 Kartons gleichzeitig durch alle Hallen!",
	},
	"kit_cpu": {
		"name": "CPU-Reparatur-Kit",
		"category": "repair_kit",
		"kit_cat": "cpu",
		"short_label": "CPU-KIT",
		"price": 65,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.22, 0.74, 0.97),
		"desc": "Ersatz-CPU-Modul, Wärmeleitpaste & ESD-Werkzeug für die Werkbank.",
	},
	"kit_ram": {
		"name": "RAM-Reparatur-Kit",
		"category": "repair_kit",
		"kit_cat": "ram",
		"short_label": "RAM-KIT",
		"price": 55,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.20, 0.83, 0.60),
		"desc": "Ersatz-ECC-DIMM-Riegel & Kontaktspray für die Werkbank.",
	},
	"kit_gpu": {
		"name": "GPU-Reparatur-Kit",
		"category": "repair_kit",
		"kit_cat": "gpu",
		"short_label": "GPU-KIT",
		"price": 110,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.65, 0.55, 0.98),
		"desc": "GPU-Ersatzmodul, Wärmeleitpads & 8-Pin-Stecker für die Werkbank.",
	},
	"kit_storage": {
		"name": "SSD-Reparatur-Kit",
		"category": "repair_kit",
		"kit_cat": "storage",
		"short_label": "SSD-KIT",
		"price": 45,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.98, 0.75, 0.14),
		"desc": "M.2-NVMe-Ersatzmodul & M2-Befestigungsschraube für die Werkbank.",
	},
	"kit_cooling": {
		"name": "Kühlungs-Reparatur-Kit",
		"category": "repair_kit",
		"kit_cat": "cooling",
		"short_label": "COOL-KIT",
		"price": 40,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.38, 0.65, 0.98),
		"desc": "92mm-Hot-Swap-Lüftermodul & PWM-Kabel für die Werkbank.",
	},
	"kit_psu": {
		"name": "Netzteil-Reparatur-Kit",
		"category": "repair_kit",
		"kit_cat": "psu",
		"short_label": "PSU-KIT",
		"price": 75,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.98, 0.45, 0.09),
		"desc": "Server-Netzteil-Ersatzmodul & 24-Pin/8-Pin-Kabelsatz.",
	},
	"kit_mainboard": {
		"name": "Mainboard-Reparatur-Kit",
		"category": "repair_kit",
		"kit_cat": "mainboard",
		"short_label": "MB-KIT",
		"price": 125,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.96, 0.25, 0.37),
		"desc": "Ersatz-Platine, Kondensatoren & Abstandshalter für die Werkbank.",
	},
	"kit_bundle_all": {
		"name": "Werkstatt-Komplett-Bundle (7 Kits)",
		"category": "repair_bundle",
		"short_label": "7x KITS",
		"price": 420,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.95, 0.68, 0.14),
		"desc": "Enthält je 1 Reparatur-Kit für alle 7 Kategorien (18 % günstiger!).",
	},
	# --- Kaufbare & frei platzierbare Einrichtung, Lagerregale & Technik-Props ---
	"prop_storage_shelf": {
		"name": "Schwerlast-Lagerregal (4 Plätze)",
		"category": "placeable",
		"is_decor": true,
		"price": 220,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.28, 0.42, 0.56),
		"desc": "Frei platzierbares 3D-Lagerregal mit 4 echten Ablageplätzen für Bauteile, Kits & Kartons!",
	},
	"prop_esd_workbench": {
		"name": "ESD-Diagnose-Werkbank",
		"category": "placeable",
		"is_decor": true,
		"price": 480,
		"watts": 40,
		"compute": 0,
		"heat": 0.2,
		"color": Color(0.20, 0.62, 0.72),
		"desc": "Professionelle Elektronik-Werkbank mit Oszilloskop • +35 % Reparatur- & Diagnose-Tempo!",
	},
	"prop_parts_cabinet": {
		"name": "Ersatzteil-Schrank & Kabeltrommeln",
		"category": "placeable",
		"is_decor": true,
		"price": 360,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.84, 0.60, 0.16),
		"desc": "Interaktiver Ersatzteil-Schrank [E] • Füllt Wartungs- & Reinigungs-Kits direkt vor Ort auf!",
	},
	"prop_cold_aisle_gate": {
		"name": "Kaltgang-Schiebetür-Portal",
		"category": "placeable",
		"is_decor": true,
		"price": 550,
		"watts": 25,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.16, 0.64, 0.94),
		"desc": "Glas-/Alu-Kaltgang-Portal mit digitaler Temperatur-Anzeige • +6 % Kühleffizienz (bis +18 %)!",
	},
	"prop_vending_lounge": {
		"name": "Getränkeautomat & Kaffee-Lounge",
		"category": "placeable",
		"is_decor": true,
		"price": 320,
		"watts": 90,
		"compute": 0,
		"heat": 0.4,
		"color": Color(0.76, 0.26, 0.24),
		"desc": "Beleuchteter Snack-/Getränkeautomat mit Lounge-Deko • +5 % Firmen-Ruf!",
	},
	"prop_cctv_monitor": {
		"name": "CCTV- & Temperatur-Stele",
		"category": "placeable",
		"is_decor": true,
		"price": 290,
		"watts": 35,
		"compute": 0,
		"heat": 0.1,
		"color": Color(0.22, 0.76, 0.50),
		"desc": "Überwachungskamera, Live-Temperaturanzeige & Feuerlöscher-Station • +4 % Ruf & Frühwarnung!",
	},
	"prop_power_strip": {
		"name": "Industrie-Stromleiste (6-fach)",
		"category": "placeable",
		"is_decor": true,
		"price": 75,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.92, 0.72, 0.14),
		"desc": "Frei platzierbare 6-fach Steckdosenleiste (Alu-Profil) • 1 Zuleitung vom Sicherungskasten + 5 freie Strom-Ports!",
	},
	"prop_lan_strip": {
		"name": "LAN-Verteilerleiste (8-Port)",
		"category": "placeable",
		"is_decor": true,
		"price": 110,
		"watts": 10,
		"compute": 0,
		"heat": 0.05,
		"color": Color(0.18, 0.52, 0.90),
		"desc": "Frei platzierbare 8-Port RJ45-Netzwerkleiste • 1 Uplink vom Router + 7 einzeln steckbare LAN-Ports!",
	},
	"slot_build_box": {
		"name": "Server-Bausatz",
		"category": "workshop_box",
		"price": 0,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.72, 0.56, 0.38),
		"desc": "Gelieferter Server-Bausatz — an der Werkbank zusammenbauen.",
	},
	"server_tray": {
		"name": "Server-Schlitten",
		"category": "server_tray",
		"price": 0,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.32, 0.68, 0.92),
		"desc": "Ausgebautes oder fertig montiertes Server-Chassis.",
	},
}

const REPAIR_KIT_ORDER: Array[String] = [
	"kit_cpu", "kit_ram", "kit_gpu", "kit_storage", "kit_cooling", "kit_psu", "kit_mainboard",
]

const COMPONENT_ORDER := ["cpu", "gpu", "ram", "storage", "cooling", "psu"]

const COMPONENT_CATALOG := {
	"cpu": {
		"label": "Prozessor (CPU)",
		"icon": "🧠",
		"tiers": [
			{"name": "Kernova 8-Core", "cost": 0, "compute": 0, "watts": 0, "heat": 0.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "Quarvex Multi-Core 32C", "cost": 220, "compute": 10, "watts": 60, "heat": 2.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "Dual-Socket Pro 96C", "cost": 520, "compute": 24, "watts": 140, "heat": 4.5, "watt_mult": 1.0, "fault_mult": 0.95},
			{"name": "Enterprise 192-Core", "cost": 1150, "compute": 52, "watts": 240, "heat": 8.0, "watt_mult": 1.0, "fault_mult": 0.90},
		],
	},
	"gpu": {
		"label": "Grafikkarte (GPU)",
		"icon": "🎮",
		"tiers": [
			{"name": "Integrierte Grafik", "cost": 0, "compute": 0, "watts": 0, "heat": 0.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "Prismor Compute 49", "cost": 340, "compute": 18, "watts": 180, "heat": 6.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "Dual Tensor AI-GPU", "cost": 780, "compute": 44, "watts": 340, "heat": 11.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "Vierfach-KI-Cluster", "cost": 1650, "compute": 95, "watts": 560, "heat": 18.0, "watt_mult": 1.0, "fault_mult": 1.0},
		],
	},
	"ram": {
		"label": "Arbeitsspeicher (RAM)",
		"icon": "💾",
		"tiers": [
			{"name": "32 GB DDR5 ECC", "cost": 0, "compute": 0, "watts": 0, "heat": 0.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "128 GB DDR5 ECC", "cost": 160, "compute": 6, "watts": 25, "heat": 0.6, "watt_mult": 1.0, "fault_mult": 0.95},
			{"name": "512 GB ECC Quad", "cost": 420, "compute": 16, "watts": 55, "heat": 1.4, "watt_mult": 1.0, "fault_mult": 0.90},
			{"name": "2 TB Enterprise RAM", "cost": 920, "compute": 36, "watts": 95, "heat": 2.4, "watt_mult": 1.0, "fault_mult": 0.85},
		],
	},
	"storage": {
		"label": "Speicher (SSD / NVMe)",
		"icon": "💿",
		"tiers": [
			{"name": "SATA SSD Standard", "cost": 0, "compute": 0, "watts": 0, "heat": 0.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "NVMe Gen4 RAID", "cost": 150, "compute": 4, "watts": 15, "heat": 0.4, "watt_mult": 1.0, "fault_mult": 0.80},
			{"name": "Enterprise Gen5 NVMe", "cost": 380, "compute": 10, "watts": 30, "heat": 0.8, "watt_mult": 1.0, "fault_mult": 0.58},
			{"name": "Ultra-Array", "cost": 820, "compute": 22, "watts": 45, "heat": 1.2, "watt_mult": 1.0, "fault_mult": 0.35},
		],
	},
	"cooling": {
		"label": "Server-Kühlung",
		"icon": "❄️",
		"tiers": [
			{"name": "Standard-Lüfter", "cost": 0, "compute": 0, "watts": 0, "heat": 0.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "High-Airflow Windhall", "cost": 140, "compute": 0, "watts": 15, "heat": -4.0, "watt_mult": 1.0, "fault_mult": 0.90},
			{"name": "Vapor-Chamber Pro", "cost": 340, "compute": 0, "watts": 30, "heat": -9.0, "watt_mult": 1.0, "fault_mult": 0.78},
			{"name": "Direct-Liquid Coldplate", "cost": 720, "compute": 0, "watts": 45, "heat": -16.0, "watt_mult": 1.0, "fault_mult": 0.62},
		],
	},
	"psu": {
		"label": "Netzteil (PSU)",
		"icon": "🔌",
		"tiers": [
			{"name": "Effizienz Bronze (Standard)", "cost": 0, "compute": 0, "watts": 0, "heat": 0.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "Effizienz Gold Plus", "cost": 160, "compute": 0, "watts": 0, "heat": -1.0, "watt_mult": 0.88, "fault_mult": 0.90},
			{"name": "Effizienz Platin Pro", "cost": 390, "compute": 0, "watts": 0, "heat": -2.2, "watt_mult": 0.76, "fault_mult": 0.75},
			{"name": "Redundant Titanium", "cost": 850, "compute": 0, "watts": 0, "heat": -3.5, "watt_mult": 0.65, "fault_mult": 0.55},
		],
	},
}

const POWER_TIERS := [
	{"watts": 2400, "cost": 0, "label": "Garagen-Sicherung (2.4 kW)"},
	{"watts": 4800, "cost": 900, "label": "Starkstrom-Anschluss (4.8 kW)"},
	{"watts": 9600, "cost": 2400, "label": "Gewerbe-Trafo (9.6 kW)"},
	{"watts": 18000, "cost": 5500, "label": "Industrie-Einspeisung (18 kW)"},
	{"watts": 36000, "cost": 11000, "label": "Umspannwerk-Direktleitung (36 kW)"},
]

const ROUTER_TIERS := [
	{"label": "Alter DSL-Router (50 Mbit/s)", "speed": "50 Mbit/s", "max_mbps": 50.0, "max_cu": 36, "ports": 2, "ddos_mult": 1.0, "cost": 0},
	{"label": "VDSL Business-Router (250 Mbit/s)", "speed": "250 Mbit/s", "max_mbps": 250.0, "max_cu": 95, "ports": 3, "ddos_mult": 1.25, "cost": 450},
	{"label": "1G Glasfaser-Gateway (1 Gbit/s)", "speed": "1 Gbit/s", "max_mbps": 1000.0, "max_cu": 210, "ports": 5, "ddos_mult": 1.55, "cost": 1150},
	{"label": "10G Enterprise Core-Router", "speed": "10 Gbit/s", "max_mbps": 10000.0, "max_cu": 480, "ports": 7, "ddos_mult": 2.0, "cost": 2800},
	{"label": "100G Backbone Fiber-Cluster", "speed": "100 Gbit/s", "max_mbps": 100000.0, "max_cu": 1400, "ports": 12, "ddos_mult": 3.0, "cost": 6500},
]

const AI_TIERS := [
	{"level": 0, "label": "Aus", "cost": 0, "min_compute": 0, "min_ram_gb": 0, "min_gpu": 0, "rate": 0.0},
	{"level": 1, "label": "OpenGarage AI v1 (Beta)", "cost": 800, "min_compute": 15, "min_ram_gb": 16, "min_gpu": 30, "rate": 1.6},
	{"level": 2, "label": "OpenGarage AI Pro", "cost": 2200, "min_compute": 40, "min_ram_gb": 64, "min_gpu": 120, "rate": 2.6},
	{"level": 3, "label": "Hyperscale Neural Cloud", "cost": 5000, "min_compute": 85, "min_ram_gb": 256, "min_gpu": 400, "rate": 4.0},
	{"level": 4, "label": "AGI Supercluster Tier", "cost": 12000, "min_compute": 180, "min_ram_gb": 512, "min_gpu": 900, "rate": 5.8},
]

const CONTRACTS_TEMPLATE := [
	{"id": "c_blog", "title": "Indie-Webshop Hosting", "client": "PixelBäcker GmbH", "required_compute": 10, "req_ram_gb": 4, "req_mbps": 15.0, "payout_per_cycle": 32, "penalty_per_cycle": 12},
	{"id": "c_clan", "title": "Multiplayer Game-Server", "client": "Nordic Frag Clan", "required_compute": 25, "req_ram_gb": 16, "req_mbps": 35.0, "payout_per_cycle": 85, "penalty_per_cycle": 30},
	{"id": "c_stream", "title": "Live-Video Transcoding", "client": "StreamPulse Media", "required_compute": 45, "req_ram_gb": 32, "req_mbps": 120.0, "payout_per_cycle": 160, "penalty_per_cycle": 60},
	{"id": "c_ml", "title": "Startup ML-Training", "client": "VektorLabs AI", "required_compute": 75, "req_ram_gb": 64, "req_mbps": 200.0, "payout_per_cycle": 280, "penalty_per_cycle": 100},
	{"id": "c_fin", "title": "Fintech Realtime-API", "client": "EuroPay Core", "required_compute": 110, "req_ram_gb": 128, "req_mbps": 450.0, "payout_per_cycle": 430, "penalty_per_cycle": 165},
	{"id": "c_enterprise", "title": "Enterprise GPU Cluster", "client": "Helios Dynamics", "required_compute": 160, "req_ram_gb": 256, "req_mbps": 1200.0, "payout_per_cycle": 680, "penalty_per_cycle": 240},
	{"id": "c_llm", "title": "Global LLM Inference", "client": "Synthetix Corp", "required_compute": 260, "req_ram_gb": 512, "req_mbps": 4000.0, "payout_per_cycle": 1180, "penalty_per_cycle": 420},
]

## Zufällige, befristete Vertragsangebote. Sie werden nur auf dem Host erzeugt und über contracts synchronisiert.
const RANDOM_CONTRACT_MAX_OFFERS := 3
const RANDOM_CONTRACT_DURATION_MIN := 2
const RANDOM_CONTRACT_DURATION_MAX := 5
## Tage, die ein Angebot angenommen werden kann, bevor es verfällt.
const RANDOM_CONTRACT_OFFER_DAYS := 2
const RANDOM_CONTRACT_SCALE_MIN := 0.6
const RANDOM_CONTRACT_SCALE_MAX := 1.3
## Aufschlag auf die Einnahmen, weil der Vertrag befristet ist.
const RANDOM_CONTRACT_PREMIUM_MIN := 1.10
const RANDOM_CONTRACT_PREMIUM_MAX := 1.40
const RANDOM_CONTRACT_PENALTY_MULT := 1.25
## Basisvorlagen dürfen höchstens so viel RAM verlangen (Vielfaches des vorhandenen RAMs).
const RANDOM_CONTRACT_RAM_REACH := 2
const RANDOM_CONTRACT_TITLES := [
	"Black-Friday Shop-Spitze",
	"Hochschul-Rendering",
	"Wahlabend Live-Ticker",
	"E-Sport-Turnier Server",
	"Backup-Migration",
	"Wetterdaten-Simulation",
]
const RANDOM_CONTRACT_CLIENTS := [
	"Kaufhaus Lindner",
	"TU Nordheim",
	"Regio-Nachrichten",
	"Arena Cup Events",
	"Steuerbüro Kranz",
	"Meteo Süd",
]

## Endziel nach Halle C: Meilensteine für den Firmenwert. Der letzte Eintrag ist das Endziel.
const COMPANY_VALUE_MILESTONES := [
	{"value": 15000, "title": "Regionaler Hoster"},
	{"value": 40000, "title": "Mittelstands-Rechenzentrum"},
	{"value": 100000, "title": "Landesweiter Cloud-Anbieter"},
	{"value": 250000, "title": "Hyperscaler"},
]
## Anteil des Kaufpreises, mit dem verbaute Hardware in den Firmenwert eingeht.
const COMPANY_HARDWARE_VALUE_FACTOR := 0.6
## Firmenstufen: Mindest-Firmenwert für Stufe 1 bis 10. Die Stufe schaltet Bauteile, Pro-Rack, Halle Nord & Boni frei.
const COMPANY_LEVEL_THRESHOLDS := [0, 24000, 72000, 180000, 400000, 750000, 1300000, 2100000, 3300000, 5000000]
const COMPANY_LEVEL_BENEFITS := {
	1: {
		"rev_mult": 1.00, "discount": 0.00, "fail_mult": 1.00, "delivery_bonus": 0, "max_contracts": 4,
		"summary": "Start-Setup: Standard-Rack, Express-Lieferwagen, Basis-Hardware",
	},
	2: {
		"rev_mult": 1.06, "discount": 0.05, "fail_mult": 0.90, "delivery_bonus": 4, "max_contracts": 6,
		"summary": "+6% Kundenvergütung • -5% Hardware-/Stromkosten • 7,5t-LKW & 20 Lieferplätze • -10% Ausfallrate • 6 Verträge",
	},
	3: {
		"rev_mult": 1.14, "discount": 0.10, "fail_mult": 0.80, "delivery_bonus": 8, "max_contracts": 8,
		"summary": "Pro-Rack (6U) & Großstandort Halle Nord (240 m²) freigeschaltet • +14% Einnahmen • -10% Kosten • 18t-LKW & 24 Plätze",
	},
	4: {
		"rev_mult": 1.20, "discount": 0.13, "fail_mult": 0.76, "delivery_bonus": 10, "max_contracts": 10,
		"summary": "GPU-Server & Kälteturm freigeschaltet • +20% Einnahmen • -13% Kosten • 26 Lieferplätze • -24% Ausfallrate • 10 Verträge",
	},
	5: {
		"rev_mult": 1.25, "discount": 0.15, "fail_mult": 0.72, "delivery_bonus": 12, "max_contracts": 11,
		"summary": "Flüssigkühlung freigeschaltet • +25% Einnahmen • -15% Kosten • 28 Lieferplätze • -28% Ausfallrate • 11 Verträge",
	},
	6: {
		"rev_mult": 1.29, "discount": 0.17, "fail_mult": 0.69, "delivery_bonus": 14, "max_contracts": 12,
		"summary": "Regionaler Marktführer • +29% Einnahmen • -17% Kosten • 30 Lieferplätze • -31% Ausfallrate • 12 Verträge",
	},
	7: {
		"rev_mult": 1.33, "discount": 0.19, "fail_mult": 0.66, "delivery_bonus": 16, "max_contracts": 13,
		"summary": "Landesweiter Betreiber • +33% Einnahmen • -19% Kosten • 32 Lieferplätze • -34% Ausfallrate • 13 Verträge",
	},
	8: {
		"rev_mult": 1.37, "discount": 0.21, "fail_mult": 0.64, "delivery_bonus": 18, "max_contracts": 14,
		"summary": "Cloud-Konzern • +37% Einnahmen • -21% Kosten • 34 Lieferplätze • -36% Ausfallrate • 14 Verträge",
	},
	9: {
		"rev_mult": 1.41, "discount": 0.23, "fail_mult": 0.62, "delivery_bonus": 20, "max_contracts": 15,
		"summary": "Europäischer Konzern • +41% Einnahmen • -23% Kosten • 36 Lieferplätze • -38% Ausfallrate • 15 Verträge",
	},
	10: {
		"rev_mult": 1.46, "discount": 0.25, "fail_mult": 0.60, "delivery_bonus": 24, "max_contracts": 17,
		"summary": "Hyperscaler • +46% Einnahmen • -25% Kosten • 40 Lieferplätze • -40% Ausfallrate • 17 Verträge",
	},
}
## Benötigte Firmenstufe je Mainboard-Kategorie.
const MAINBOARD_CATEGORY_LEVEL := {"entry": 1, "server": 2, "storage": 3, "gpu": 4}
## Support-SLA: Sekunden, bis ein unbeantwortetes Ticket eskaliert, je Priorität.
const TICKET_SLA_SECONDS := {"HOCH": 120.0, "KRITISCH": 60.0}
const TICKET_DEFAULT_SLA := 120.0
const TICKET_ESCALATION_SAT_PENALTY := 15.0
const TICKET_ESCALATION_REP_PENALTY := 2.0

# Authoritative world state
var is_active: bool = false
var money: float = 1200.0
var breaker_on: bool = true
## Anzahl der Sicherungs-Steckplätze im Wand-Sicherungskasten und Preis einer Ersatzsicherung.
const FUSE_SLOT_COUNT := 4
const FUSE_PRICE := 35
## Steckplätze im Sicherungskasten: "ok" (eingesetzt), "blown" (durchgebrannt) oder "empty" (leer).
var breaker_fuses: Array = []
## Gekaufte Sicherungen, die noch nicht eingesetzt sind.
var fuse_stock: int = 0
## Drehsicherung (Stromstufen-Upgrade): Der Kauf legt sie ins Lager (0 oder 1).
## Erst das Einsetzen in Steckplatz F2 erhöht die Stromstufe und gibt die alte Sicherung in die Hand.
const POWER_FUSE_SLOT := 1
const OLD_FUSE_ITEM := "old_fuse"
var power_fuse_stock: int = 0
## Client-Kopie: Die Drehsicherung ist bestellt und mit dem Lieferwagen unterwegs.
var power_fuse_on_way_synced: bool = false
const POWER_FUSE_ACC := "acc:power_fuse"
## Der Stromkasten der Start-Garage hat genau eine Steckdose, alles Weitere läuft über Stromleisten.
const BREAKER_BASE_SOCKETS := 1
var ups_backup_active: bool = false
var avg_ups_charge: float = 0.0
## Netzausfall der Stadtwerke: Restdauer in Sekunden (0 = Netz da). Währenddessen ist breaker_on false.
var grid_outage_left: float = 0.0
## Stand des Hauptschalters vor dem Netzausfall; wird am Ende wiederhergestellt.
var _grid_breaker_restore: bool = false
var _grid_outage_cooldown: float = -1.0
const GRID_OUTAGE_MIN_SEC := 35.0
const GRID_OUTAGE_MAX_SEC := 110.0
const GRID_OUTAGE_FIRST_DAY := 2
var overload_timer: float = 0.0
var power_tier: int = 0
var router_tier: int = 0
## Erforschte Stufe pro Zweig aus RESEARCH_TREE (fehlender Eintrag = 0).
var research_levels: Dictionary = {}
var room_level: int = 0 # 0 = Garage, 1 = +Halle B, 2 = +Halle C Enterprise
var halle_nord_owned: bool = false
var delivery_target_site: String = "garage" # "garage" | "halle_nord"
## Sichtbare Gebäude-Upgrades (erst nach Kauf + Live-Bautrupp sichtbar!) & laufende Baustellen
const BUILDING_UPGRADE_CATALOG := {
	"upg_pv_solar": {
		"name": "PV-Solaranlage & Solar-Carport",
		"price": 2800,
		"duration": 50.0,
		"req_nord": false,
		"icon": "☀",
		"effect": "-28 % laufende Stromkosten (Dach-PV & Solar-Carport mit Wallboxen)",
		"desc": "Bautrupp installiert Photovoltaik-Module & Solar-Carport mit E-Ladesäulen.",
	},
	"upg_diesel_gen": {
		"name": "2-MVA Notstrom-Dieselgenerator",
		"price": 4200,
		"duration": 65.0,
		"req_nord": true,
		"icon": "⚡",
		"effect": "Übernimmt bei Stadtwerke-Netzausfall automatisch (kein Blackout!)",
		"desc": "Schwerlast-Dieselaggregat im Schallschutz-Container inkl. Kabelbrücke zur Halle.",
	},
	"upg_security_gate": {
		"name": "Sicherheits-Pförtnerhaus, Schranke & Pylon",
		"price": 2400,
		"duration": 45.0,
		"req_nord": true,
		"icon": "🛡",
		"effect": "+12 % Firmen-Ruf & 24/7-Zugangskontrolle mit Pförtner-NPC",
		"desc": "Verglastes Torhaus mit automatischer Schranke, Ausweis-Stele & Firmen-Pylon.",
	},
	"upg_noc_suite": {
		"name": "Verglaster NOC-Leitstand & 3-Screen-Videowall",
		"price": 3400,
		"duration": 55.0,
		"req_nord": true,
		"icon": "🖥",
		"effect": "+15 % Support-Einnahmen & automatische Wartungs-Frühwarnung",
		"desc": "Stahl-Glas-Leitstand mit 3-Monitor-Telemetrie-Wand & Kaffeebar in Halle Nord.",
	},
	"upg_roof_chillers": {
		"name": "Dach-Rückkühlwerk & Außen-Chiller-Farm",
		"price": 3800,
		"duration": 60.0,
		"req_nord": false,
		"icon": "❄",
		"effect": "-4,5 °C niedrigere Grundtemperatur in allen Hallen",
		"desc": "Industrielle Kaltwasserkühler & Dach-Rückkühler mit Verrohrung.",
	},
	"upg_cold_aisle_pro": {
		"name": "Kaltgang-Einhausung & LED-Bodenführung",
		"price": 2600,
		"duration": 45.0,
		"req_nord": true,
		"icon": "💨",
		"effect": "+22 % zusätzliche Kühleffizienz & digitale Gang-Temperaturanzeigen",
		"desc": "Leuchtende Kaltgang-Führung, Glas-Einhausungsportale & hängende Temp-Displays.",
	},
}
const BUILDING_UPGRADE_ORDER: Array[String] = [
	"upg_pv_solar", "upg_roof_chillers", "upg_security_gate",
	"upg_noc_suite", "upg_cold_aisle_pro", "upg_diesel_gen",
]
## Anteil der Defekte ohne sichtbare Spuren; die findet man nur mit POST-Code und Messgerät.
const FAULT_HIDDEN_CHANCE := 0.5
const FAULT_DIAGNOSIS_META := {
	"cpu": {"code": "ERR-THM-07", "cause": "Wärmeleitpaste ausgetrocknet / CPU-Throttling", "tool": "Wärmeleitpaste- & Wartungs-Kit"},
	"cooling": {"code": "ERR-FAN-04", "cause": "Lüfterlager blockiert / Kühlkörper verstaubt", "tool": "Druckluft & Ersatz-Lüfter"},
	"psu": {"code": "ERR-PSU-12", "cause": "Netzteil-Kondensator defekt (Spannungsabfall)", "tool": "Netzteil-Ersatzmodul"},
	"ram": {"code": "ERR-ECC-03", "cause": "ECC-Speicherbank meldet Paritätsfehler", "tool": "Kontaktspray & ECC-Riegel"},
	"storage": {"code": "ERR-NVM-08", "cause": "NVMe-Controller überhitzt / Sektorfehler", "tool": "NVMe-Ersatzmodul"},
	"gpu": {"code": "ERR-GPU-15", "cause": "VRMs überhitzt / 8-Pin-Stecker verschmort", "tool": "GPU-Wärmeleitpads & Stecker"},
	"mainboard": {"code": "ERR-BKP-02", "cause": "Backplane-Stecker locker / Bus-Fehler", "tool": "Diagnose-Prüfer & Löt-Kit"},
}
var building_upgrades: Dictionary = {} # upgrade_id -> true
var active_constructions: Dictionary = {} # upgrade_id -> {remaining, duration, site}
var decor_items: Dictionary = {} # decor_id -> {id, item_type, pos, rot_y, stored_items}
var bench_screws: int = BENCH_SCREWS_START
var bench_paste: float = BENCH_PASTE_START
## Gekauftes Profi-Werkzeug: akku, torque, paste_gun, meter_pro, rcd -> true
var bench_tools: Dictionary = {}
var maint_kits: int = 3 # Vorrat an Wartungs-/Druckluft-/Wärmeleitpaste-Kits
## Zahl der erreichten Firmenwert-Meilensteine. -1 = alter Spielstand, wird beim nächsten Check still übernommen.
var company_milestones_reached: int = 0
## Erreichte Firmenstufe (1-5). 0 = alter Spielstand, wird beim nächsten Check aus dem Firmenwert berechnet.
var company_level: int = 1
var ai_platform_level: int = 0
var ddos_active: bool = false
var ddos_cooldown: float = 55.0

# Day/Night & Daily Power Bill
var day_number: int = 1
var time_of_day: float = 0.36 # 0..1 (0.36 ≈ 08:38)
var daily_kwh: float = 0.0
var last_daily_bill: int = 0
## Strompreis des laufenden Tags in $/kWh.
var electricity_rate: float = ELECTRICITY_RATE_PER_KWH
## Strompreis, mit dem die letzte Tagesrechnung berechnet wurde.
var last_bill_rate: float = ELECTRICITY_RATE_PER_KWH

var room_temp: float = 22.0
## Countdown bis zum nächsten Wasserschaden (nur auf dem Host, wird nicht gespeichert).
var water_leak_cooldown: float = randf_range(WATER_LEAK_MIN_S, WATER_LEAK_MAX_S)
var total_watts: int = 0
var max_watts: int = 2400
var total_compute: int = 0
var raw_compute: int = 0
var max_bandwidth_cu: int = 36
var used_compute: int = 0
var total_ram_gb: int = 0
var total_cpu_score: int = 0
var total_gpu_score: int = 0
var total_storage_tb: float = 0.0
var used_bandwidth_mbps: float = 0.0
var max_bandwidth_mbps: float = 50.0
var revenue_bonus_mult: float = 1.0
var ai_revenue_per_sec: float = 0.0
var next_payout_in: float = PAYOUT_CYCLE_SECONDS

var racks: Dictionary = {}
var coolers: Dictionary = {}
var ups_units: Dictionary = {}
var carts: Dictionary = {}
var crates: Dictionary = {}
var cables: Dictionary = {}
var contracts: Dictionary = {}
var parts_inventory: Dictionary = {} # part_id -> int count in player's warehouse!
## Gemeinsamer Warenkorb für PC-Shop & Rack-Konfigurator (lokal pro Spieler).
var shopping_cart: Array = []
## Offene Bausatz-Bestellungen, die gerade im Lieferwagen liegen (order_id -> build_data).
var pending_build_orders: Dictionary = {}
## Freie Stellplätze im 3D-Lagerregal: "shelf_0:0" .. "shelf_0:11" -> crate_data Dictionary.
const STORAGE_SHELF_SLOTS := 12
## Verbrauchsmaterial der Werkbank: Schrauben (Stück) und Wärmeleitpaste (Anwendungen).
## Bauqualität: Deckel nach Schnellreparatur am Rack (mit bzw. ohne Ersatzteil-Kit).
const RACK_REPAIR_QUALITY_KIT := 70
const RACK_REPAIR_QUALITY := 50
const BENCH_JOBS: Array[String] = ["assembly", "repair", "service"]
const BENCH_SCREWS_START := 80
const BENCH_PASTE_START := 10.0
const SCREW_BOX_PRICE := 14
const SCREW_BOX_COUNT := 100
const PASTE_TUBE_PRICE := 9
const PASTE_TUBE_USES := 10.0
## Profi-Werkzeug für die Werkbank (einmalig, kommt per Lieferwagen). "needs" = vorher nötig.
const BENCH_TOOLS := {
	"akku": {"name": "Akkuschrauber", "price": 180, "desc": "Schraubt fast doppelt so schnell – rein und raus."},
	"torque": {"name": "Drehmoment-Kupplung", "price": 320, "needs": "akku", "desc": "Aufsatz für den Akkuschrauber: stoppt genau richtig, nichts wird locker oder überdreht."},
	"paste_gun": {"name": "Dosierpistole", "price": 140, "desc": "Trägt immer die ideale Menge Wärmeleitpaste auf."},
	"meter_pro": {"name": "Profi-Multimeter", "price": 260, "desc": "Misst doppelt so schnell und grenzt den Verdacht nach dem POST-Code enger ein."},
	"rcd": {"name": "Personenschutz-Schalter", "price": 120, "desc": "Schaltet bei Arbeiten unter Strom sofort ab: das Mainboard bleibt heil."},
}
const BENCH_SCREWS_MAX := 600
const BENCH_PASTE_MAX := 60.0
const MAINTAIN_MIN_DUST := 15.0
const MAINTAIN_MAX_THERMAL := 85.0
var storage_shelf_slots: Dictionary = {}
## Aktiver Zustand der IT-Werkbank (leer oder build_box / assembly / repair / ready_tray).
var workbench_state: Dictionary = {}
var support_tickets: Dictionary = {}
var active_call: Dictionary = {}
var total_rental_income_per_cycle: float = 0.0
## Ruf der Firma (0-100). Bestimmt, wie viele Kunden ein Dienst anlockt und wie schnell sie kommen.
var reputation: float = 10.0
var _last_rep_tier: int = -1
const REPUTATION_START := 10.0
const MAX_SERVICES_PER_RACK := 4
const REPUTATION_LABELS: Array[String] = ["Unbekannt", "Lokal bekannt", "Geschätzt", "Gefragt", "Etabliert", "Renommiert", "Branchengröße", "Marktführer"]
const REPUTATION_THRESHOLDS: Array[float] = [15.0, 27.0, 40.0, 53.0, 66.0, 79.0, 91.0]
## Bedarf pro Nutzer, der bei mehreren Diensten nach Nutzerzahl gemittelt wird.
const _BLEND_KEYS: Array[String] = ["ram_gb_per_user", "cpu_per_user", "gpu_per_user", "storage_tb_per_user", "mbps_per_user", "pay_per_user"]
var checklist_opened_pc: bool = false
var checklist_ordered_anything: bool = false
var checklist_dismissed: bool = false
## Feuerlöscher: id -> {station, held_by, slot, pos, yaw, fill}. station = "garage" / "nord" / "" (nicht im Halter).
var extinguishers: Dictionary = make_default_extinguishers()
const EXT_STATIONS: Array[String] = ["garage", "nord"]
## Sprühzeit einer vollen Füllung und Zeit bis zum Auffüllen im Halter (Sekunden).
const EXT_SPRAY_SECONDS := 20.0
const EXT_REFILL_SECONDS := 45.0
const EXT_SPRAY_TICK := 0.16
var _ext_sync_fill: Dictionary = {}
## Aktiver Slot (1-4) je Spieler (peer_id -> Slot). Der Server verteilt Änderungen an alle.
var player_active_slot: Dictionary = {}
const SLOT_COUNT := 4

# Delivery Van State ("idle" | "arriving" | "unloading" | "departing")
var pending_delivery_items: Array = []
var van_cargo: Array = []
var van_phase: String = "idle"
var van_phase_time: float = 0.0
var van_cargo_count: int = 0
var van_delivery_tier: int = 1
var _van_empty_accum: float = 0.0
var pending_delivery_count: int = 0
## Geplantes Lieferfenster (Tag & Stunde) für reguläre Bestellungen; Express liefert sofort.
var scheduled_delivery_day: int = 0
var scheduled_delivery_hour: int = -1
var pending_delivery_express: bool = false

# Abladefahrten des Fahrers (der Server rechnet, Clients spielen nur ab)
var van_trip_phase: String = "" # "" | exit | load | walk_in | drop | walk_back | enter
var van_trip_time: float = 0.0
var van_trip_duration: float = 0.0
var van_trip_step: int = 0 # zählt jeden Schrittwechsel, damit Clients ihre Animation neu starten
var van_trip_count: int = 0
var van_trip_kind: String = "hand" # hand | truck
var van_trip_target: Vector3 = Vector3.ZERO
var van_trip_dropped: int = 0
var van_trip_done: int = 0
var van_trip_total: int = 0
var _van_trip_items: Array = []
var _van_parcel_parts: Array = []

var current_save_id: String = "mein_datacenter"
var current_save_name: String = "Mein DataCenter"

var _next_entity_num: int = 1
var _next_ticket_num: int = 101
var _sim_accum: float = 0.0
var _autosave_accum: float = 0.0
var _phone_ring_accum: float = 0.0
var _call_cooldown: float = 18.0
var _van_unload_accum: float = 0.0
var _delivery_slot_cursor: int = 0
# Spieluhr: der Host zählt in jedem Frame weiter, der Tageswechsel läuft im Simulations-Tick.
var _day_rollover_pending: bool = false
## Tempo der Spieluhr (Admin-Menü). Gilt nur für die laufende Sitzung.
var clock_scale: float = 1.0
# Client: Abweichung zur Host-Uhr, die weich über mehrere Frames ausgeglichen wird.
var _time_correction: float = 0.0
const TIME_SNAP_THRESHOLD := 0.02
const TIME_CORRECTION_RATE := 2.0


func _process(delta: float) -> void:
	if not is_active or not NetworkManager.is_in_session:
		return
	if not multiplayer.is_server():
		var corr := _time_correction * clampf(delta * TIME_CORRECTION_RATE, 0.0, 1.0)
		_time_correction -= corr
		time_of_day = fposmod(time_of_day + delta * clock_scale / DAY_LENGTH_SECONDS + corr, 1.0)
		if van_phase != "idle":
			van_phase_time += delta
		# Ticket-Alter lokal weiterzählen, damit der SLA-Countdown läuft. Jeder Sync vom Host korrigiert den Wert.
		for ctid in support_tickets.keys():
			var ct: Dictionary = support_tickets[ctid]
			ct["age"] = float(ct.get("age", 0.0)) + delta
		return

	# Dedizierter Server ohne verbundene Spieler: Welt pausiert (kein Geld, keine Ereignisse, kein Lieferwagen).
	if is_world_paused_for_empty_server():
		return

	_update_delivery_van(delta)
	_update_extinguishers(delta)
	_update_slot_boot(delta)

	# Eigene Spieluhr: ein Spieltag dauert DAY_LENGTH_SECONDS echte Sekunden.
	var next_time := time_of_day + delta * clock_scale / DAY_LENGTH_SECONDS
	if next_time >= 1.0:
		_day_rollover_pending = true
	time_of_day = fposmod(next_time, 1.0)

	_sim_accum += delta
	if _sim_accum >= SIM_TICK_INTERVAL:
		var steps := int(_sim_accum / SIM_TICK_INTERVAL)
		_sim_accum -= float(steps) * SIM_TICK_INTERVAL
		for _i in range(mini(steps, 3)):
			_run_simulation_step(SIM_TICK_INTERVAL)

	if SettingsManager.autosave_enabled:
		_autosave_accum += delta
		if _autosave_accum >= AUTOSAVE_INTERVAL:
			_autosave_accum = 0.0
			save_current_world("", true)


## true, wenn ein dedizierter Server läuft und niemand verbunden ist.
func is_world_paused_for_empty_server() -> bool:
	return NetworkManager.is_dedicated and NetworkManager.players.is_empty()


func get_delivery_fee(tier: int, express: bool = false) -> int:
	var base := int(DELIVERY_FEES.get(clampi(tier, 1, 3), 15))
	return base + (DELIVERY_EXPRESS_SURCHARGE if express else 0)


func get_next_delivery_slot() -> Dictionary:
	var cur_h := time_of_day * 24.0
	for h in DELIVERY_SLOTS_HOURS:
		if float(h) > cur_h + 0.12:
			return {"day": day_number, "hour": h, "tomorrow": false}
	return {"day": day_number + 1, "hour": DELIVERY_SLOTS_HOURS[0], "tomorrow": true}


func get_next_delivery_slot_label() -> String:
	var s := get_next_delivery_slot()
	if bool(s["tomorrow"]):
		return "Morgen %02d:00 Uhr" % int(s["hour"])
	return "%02d:00 Uhr" % int(s["hour"])


func get_scheduled_delivery_label() -> String:
	if pending_delivery_express:
		return "Sofort-Express"
	if scheduled_delivery_hour < 0:
		return get_next_delivery_slot_label()
	if scheduled_delivery_day > day_number:
		return "Morgen %02d:00 Uhr" % scheduled_delivery_hour
	return "%02d:00 Uhr" % scheduled_delivery_hour


func _is_delivery_window_due() -> bool:
	if pending_delivery_express:
		return true
	if scheduled_delivery_hour < 0:
		return true
	if day_number > scheduled_delivery_day:
		return true
	return day_number == scheduled_delivery_day and (time_of_day * 24.0) >= float(scheduled_delivery_hour)


func _update_delivery_van(delta: float) -> void:
	match van_phase:
		"idle":
			if not pending_delivery_items.is_empty() and _is_delivery_window_due():
				van_cargo = _pack_van_cargo(pending_delivery_items)
				pending_delivery_items.clear()
				pending_delivery_express = false
				scheduled_delivery_hour = -1
				scheduled_delivery_day = 0
				van_delivery_tier = compute_delivery_tier(van_cargo)
				van_phase = "arriving"
				van_phase_time = 0.0
				set_garage_door_open_server(true)
				_reset_van_trip()
				_broadcast_van_state()
		"arriving":
			van_phase_time += delta
			if van_phase_time >= VAN_ARRIVE_DURATION:
				van_phase = "unloading"
				van_phase_time = 0.0
				van_trip_total = van_cargo.size()
				van_trip_done = 0
				_rpc_play_sfx.rpc("van_horn")
				_rpc_play_sfx.rpc("van_door")
				var tmeta: Dictionary = DELIVERY_TIER_META.get(van_delivery_tier, DELIVERY_TIER_META[1])
				post_event_f("%s %s ist angekommen (%d Pakete · %s)!", [
					str(tmeta["icon"]), str(tmeta["name"]), van_trip_total, str(tmeta["method"])
				], "good")
				_begin_van_trip_step("exit", VAN_DRIVER_EXIT_TIME)
		"unloading":
			van_phase_time += delta
			van_trip_time += delta
			_update_van_trip()
		"departing":
			van_phase_time += delta
			if van_phase_time >= VAN_DEPART_DURATION:
				van_phase = "idle"
				van_phase_time = 0.0
				_broadcast_van_state()


func _tier_speed_mult() -> float:
	var tmeta: Dictionary = DELIVERY_TIER_META.get(van_delivery_tier, DELIVERY_TIER_META[1])
	return maxf(1.0, float(tmeta.get("speed_mult", 1.0)))


func _tier_max_per_trip() -> int:
	var tmeta: Dictionary = DELIVERY_TIER_META.get(van_delivery_tier, DELIVERY_TIER_META[1])
	return clampi(int(tmeta.get("max_per_trip", 4)), 1, VAN_TRIP_MAX_CRATES)


## Schrittfolge pro Lieferung: exit, dann je Fahrt load → walk_in → drop → walk_back, zuletzt enter.
func _update_van_trip() -> void:
	match van_trip_phase:
		"exit":
			if van_trip_time >= van_trip_duration:
				_start_next_van_trip()
		"load":
			if van_trip_time >= van_trip_duration:
				_begin_van_trip_step("walk_in", _van_trip_walk_time())
		"walk_in":
			if van_trip_time >= van_trip_duration:
				var spd := _tier_speed_mult()
				var drop_t := VAN_DROP_TIME_HAND / spd
				if van_trip_kind == "truck":
					drop_t = (VAN_TRUCK_TILT_TIME + float(_van_trip_items.size()) * VAN_DROP_TIME_PER_CRATE_TRUCK) / spd
				_begin_van_trip_step("drop", drop_t)
		"drop":
			_drop_due_van_trip_items()
			if van_trip_time >= van_trip_duration:
				_begin_van_trip_step("walk_back", _van_trip_walk_time())
		"walk_back":
			if van_trip_time >= van_trip_duration:
				_start_next_van_trip()
		"enter":
			if van_trip_time >= van_trip_duration:
				van_phase = "departing"
				van_phase_time = 0.0
				_reset_van_trip()
				_rpc_play_sfx.rpc("van_door")
				_broadcast_van_state()
		_:
			# z. B. nach dem Laden eines Spielstands mitten im Abladen
			_start_next_van_trip()


func _start_next_van_trip() -> void:
	if van_cargo.is_empty():
		_van_trip_items.clear()
		van_trip_count = 0
		_begin_van_trip_step("enter", VAN_DRIVER_ENTER_TIME)
		return
	_van_trip_items = _take_van_trip_items()
	van_trip_count = _van_trip_items.size()
	van_trip_dropped = 0
	var is_cart := str(_van_trip_items[0]) == "cart"
	van_trip_kind = "hand" if van_trip_count == 1 and not is_cart and van_delivery_tier == 1 else "truck"
	var stand_offset := VAN_DROP_STAND_OFFSET_TRUCK if van_trip_kind == "truck" else VAN_DROP_STAND_OFFSET
	van_trip_target = _van_trip_stand_pos(_van_trip_items, stand_offset)
	var spd := _tier_speed_mult()
	var load_t := (float(van_trip_count) * VAN_LOAD_TIME_PER_CRATE) / spd
	if van_trip_kind == "truck":
		load_t += VAN_TRUCK_FETCH_TIME / spd
	_begin_van_trip_step("load", load_t)


## Nimmt die Kartons der nächsten Fahrt aus dem Laderaum. Ein Rollwagen fährt immer allein.
func _take_van_trip_items() -> Array:
	var items: Array = [van_cargo.pop_front()]
	if str(items[0]) == "cart":
		return items
	var limit := _tier_max_per_trip()
	while not van_cargo.is_empty() and items.size() < limit and str(van_cargo[0]) != "cart":
		items.append(van_cargo.pop_front())
	return items


## Liefert die Kartons ab, deren Zeitpunkt im Schritt "drop" erreicht ist.
func _drop_due_van_trip_items() -> void:
	var n := _van_trip_items.size()
	var due := 0
	var spd := _tier_speed_mult()
	if van_trip_time >= van_trip_duration:
		due = n
	elif van_trip_kind == "truck":
		due = clampi(floori((van_trip_time - VAN_TRUCK_TILT_TIME / spd) / (VAN_DROP_TIME_PER_CRATE_TRUCK / spd)), 0, n)
	if due <= van_trip_dropped:
		return
	while van_trip_dropped < due:
		var item := str(_van_trip_items[van_trip_dropped])
		van_trip_dropped += 1
		van_trip_done += 1
		if item == VAN_PARCEL_ITEM:
			_deliver_parts_parcel()
		else:
			_deliver_item_to_zone(item)
	_broadcast_van_state()


## Stellt fest, wo der Fahrer stehen bleibt: vor der Mitte der Plätze, die diese Fahrt belegt.
func _van_trip_stand_pos(items: Array, stand_offset: float) -> Vector3:
	var sum := Vector3.ZERO
	var slot := _delivery_slot_cursor
	var cart_n := carts.size()
	for entry in items:
		var s := str(entry)
		if s == "cart":
			sum += _cart_drop_pos(cart_n)
			cart_n += 1
		elif s == VAN_PARCEL_ITEM:
			sum += VAN_PARCEL_DROP_POS
		else:
			sum += _delivery_slot_pos(slot)
			slot += 1
	var avg := sum / float(maxi(items.size(), 1))
	return Vector3(avg.x, 0.0, avg.z + stand_offset)


func _van_trip_walk_time() -> float:
	return VAN_CARGO_DOOR_POS.distance_to(van_trip_target) / VAN_DRIVER_WALK_SPEED + VAN_DRIVER_TURN_TIME


func _begin_van_trip_step(step: String, duration: float) -> void:
	van_trip_phase = step
	van_trip_time = 0.0
	van_trip_duration = maxf(duration, 0.1)
	van_trip_step += 1
	_broadcast_van_state()


func _reset_van_trip() -> void:
	van_trip_phase = ""
	van_trip_time = 0.0
	van_trip_duration = 0.0
	van_trip_count = 0
	van_trip_dropped = 0
	van_trip_done = 0
	van_trip_total = 0
	_van_trip_items.clear()


## Welche Artikel bei Mehrfachbestellung automatisch in Mengen-Kisten (bis 6 Stück/Kiste) gebündelt werden.
func is_bulk_packable(item_type: String) -> bool:
	if is_repair_kit(item_type):
		return true
	return item_type == "web_server" or item_type == "storage_server" or item_type == "gpu_server" or item_type == "net_switch" or item_type == INDOOR_UNIT_TYPE or is_strip_type(item_type)


func is_heavy_delivery_item(item_type: String) -> bool:
	var base := item_type
	if base.begins_with("bulk:"):
		var parts := base.split(":")
		if parts.size() >= 2:
			base = parts[1]
	return base == "rack" or base == "rack_pro" or is_ups_type(base) or base == "cart" or is_heat_pump_type(base) or is_floor_cooler_type(base)


## Berechnet die Liefer-Kategorie (1 = Lieferwagen, 2 = Kastenwagen 7,5t, 3 = Schwerlast-LKW 18t).
func compute_delivery_tier(packed_cargo: Array) -> int:
	var total := 0
	var heavy := 0
	for entry in packed_cargo:
		var s := str(entry)
		if s == VAN_PARCEL_ITEM:
			total += 1
			continue
		total += 1
		if is_heavy_delivery_item(s):
			heavy += 1
	if total >= 10 or heavy >= 4:
		return 3
	if total >= 5 or heavy >= 2:
		return 2
	return 1


## Fasst Bauteile/Zubehör ins Sammelpaket UND bündelt gleiche Mengen-Artikel (Kits, Module) in bis zu 6er-Kisten.
func _pack_items_preview(items: Array, out_parcels: Array = []) -> Array:
	var physical: Array = []
	var bulk_counts: Dictionary = {}
	var bulk_order: Array[String] = []
	var has_parcel := false
	for entry in items:
		var s := str(entry)
		if s.begins_with("part:"):
			has_parcel = true
			out_parcels.append(s.substr(5))
		elif s.begins_with("acc:"):
			has_parcel = true
			out_parcels.append(s)
		elif s == VAN_PARCEL_ITEM:
			continue
		elif s.begins_with("bulk:"):
			physical.append(s)
		elif is_bulk_packable(s):
			if not bulk_counts.has(s):
				bulk_counts[s] = 0
				bulk_order.append(s)
			bulk_counts[s] = int(bulk_counts[s]) + 1
		else:
			physical.append(s)
	for btype in bulk_order:
		var rem := int(bulk_counts[btype])
		while rem > 0:
			var chunk := mini(rem, BULK_PACK_MAX)
			if chunk > 1:
				physical.append("bulk:%s:%d" % [btype, chunk])
			else:
				physical.append(btype)
			rem -= chunk
	if has_parcel:
		physical.push_front(VAN_PARCEL_ITEM)
	return physical


func _pack_van_cargo(items: Array) -> Array:
	_van_parcel_parts.clear()
	return _pack_items_preview(items, _van_parcel_parts)


func is_pos_in_delivery_zone(pos: Vector3) -> bool:
	return pos.z >= 4.4 and pos.z <= 9.2 and absf(pos.x) <= 3.4


func get_delivery_zone_ground_crates() -> int:
	var n := 0
	for c in crates.values():
		var cd: Dictionary = c as Dictionary
		if int(cd.get("held_by", 0)) == 0 and is_pos_in_delivery_zone(cd.get("pos", Vector3.ZERO) as Vector3):
			n += 1
	for ct in carts.values():
		var ctd: Dictionary = ct as Dictionary
		if int(ctd.get("pushed_by", 0)) == 0 and is_pos_in_delivery_zone(ctd.get("pos", Vector3.ZERO) as Vector3):
			n += 1
	return n


func get_incoming_delivery_crates() -> int:
	if multiplayer.is_server():
		var n := 0
		for e in van_cargo:
			if str(e) != VAN_PARCEL_ITEM:
				n += 1
		for e in _van_trip_items:
			if str(e) != VAN_PARCEL_ITEM:
				n += 1
		n -= mini(van_trip_dropped, _van_trip_items.size())
		var pend_packed := _pack_items_preview(pending_delivery_items)
		for e in pend_packed:
			if str(e) != VAN_PARCEL_ITEM:
				n += 1
		return maxi(0, n)
	return maxi(0, van_cargo_count + pending_delivery_count)


func get_delivery_zone_used_slots() -> int:
	return get_delivery_zone_ground_crates() + get_incoming_delivery_crates()


func get_delivery_zone_free_slots() -> int:
	return maxi(0, get_max_delivery_slots() - get_delivery_zone_used_slots())


func get_max_delivery_slots() -> int:
	var lvl_b: Dictionary = COMPANY_LEVEL_BENEFITS.get(get_company_level(), {})
	var extra := int(lvl_b.get("delivery_bonus", 0))
	return DELIVERY_ZONE_MAX_CRATES + extra + (career_completed.size() * 2)


func get_level_revenue_mult() -> float:
	var lvl_b: Dictionary = COMPANY_LEVEL_BENEFITS.get(get_company_level(), {})
	return float(lvl_b.get("rev_mult", 1.0)) + float(career_completed.size()) * 0.03


func get_level_discount_mult() -> float:
	var lvl_b: Dictionary = COMPANY_LEVEL_BENEFITS.get(get_company_level(), {})
	var disc := float(lvl_b.get("discount", 0.0)) + float(career_completed.size()) * 0.015
	return clampf(1.0 - disc, 0.65, 1.0)


func get_level_failure_mult() -> float:
	var lvl_b: Dictionary = COMPANY_LEVEL_BENEFITS.get(get_company_level(), {})
	var fm := float(lvl_b.get("fail_mult", 1.0)) - float(career_completed.size()) * 0.03
	return clampf(fm, 0.45, 1.0)


func get_max_contracts_limit() -> int:
	var lvl_b: Dictionary = COMPANY_LEVEL_BENEFITS.get(get_company_level(), {})
	return int(lvl_b.get("max_contracts", 4)) + career_completed.size()


## Berechnet für den Warenkorb: {"crates": physische Kisten, "tier": 1..3, "packed": Array}.
func preview_cart_delivery(entries: Array) -> Dictionary:
	var raw_items: Array = []
	for raw in entries:
		var e: Dictionary = raw
		var kind := str(e.get("kind", "item"))
		var qty := clampi(int(e.get("qty", 1)), 1, 24)
		if kind == "item":
			var itype := str(e.get("id", ""))
			if itype == "kit_bundle_all":
				for _q in range(qty):
					for kid in REPAIR_KIT_ORDER:
						raw_items.append(kid)
			elif ITEM_CATALOG.has(itype):
				for _q in range(qty):
					raw_items.append(itype)
		elif kind == "slot_build":
			raw_items.append("slot_build_box")
		elif kind == "part":
			raw_items.append("part:" + str(e.get("id", "")))
		elif kind == "acc":
			raw_items.append("acc:" + str(e.get("id", "")))
	var packed := _pack_items_preview(raw_items)
	var physical_crates := 0
	for p in packed:
		if str(p) != VAN_PARCEL_ITEM:
			physical_crates += 1
	return {
		"crates": physical_crates,
		"total_packages": packed.size(),
		"tier": compute_delivery_tier(packed),
		"packed": packed,
	}


func _deliver_parts_parcel() -> void:
	if _van_parcel_parts.is_empty():
		return
	var n_parts := 0
	var n_fuses := 0
	var n_crates := 0
	var n_power := 0
	var n_bench := 0
	for pid_v in _van_parcel_parts:
		var pid := str(pid_v)
		match pid:
			"acc:fuse":
				fuse_stock += 1
				n_fuses += 1
			"acc:power_strip", "acc:net_hub":
				# Vor v2.6 bestelltes Zubehör kommt als echte Leiste.
				_spawn_crate_internal("prop_power_strip" if pid == "acc:power_strip" else "prop_lan_strip")
				n_crates += 1
			"acc:tool_akku", "acc:tool_torque", "acc:tool_paste_gun", "acc:tool_meter_pro", "acc:tool_rcd":
				var tid := pid.substr(9)
				if has_bench_tool(tid):
					money += float(BENCH_TOOLS[tid]["price"])
				else:
					bench_tools[tid] = true
					_rpc_sync_bench_tools.rpc(bench_tools)
					post_event_f("📦 Neues Werkzeug an der Werkbank: %s.", [str(BENCH_TOOLS[tid]["name"])], "good")
			"acc:screw_box":
				bench_screws = mini(BENCH_SCREWS_MAX, bench_screws + SCREW_BOX_COUNT)
				n_bench += 1
			"acc:paste_tube":
				bench_paste = minf(BENCH_PASTE_MAX, bench_paste + PASTE_TUBE_USES)
				n_bench += 1
			"acc:power_fuse":
				if power_fuse_stock == 0:
					power_fuse_stock = 1
					n_power += 1
			_:
				if pid.begins_with("acc:"):
					continue
				parts_inventory[pid] = int(parts_inventory.get(pid, 0)) + 1
				n_parts += 1
	_van_parcel_parts.clear()
	_rpc_play_sfx.rpc("pickup")
	if n_parts > 0:
		_broadcast_inventory()
		post_event_f("📦 %d Hardware-Bauteil(e) ins Teile-Lager geliefert! Jetzt am Rack einbauen [E].", [n_parts], "good")
	if n_bench > 0:
		_rpc_sync_bench_supplies.rpc(bench_screws, bench_paste)
		post_event_f("📦 %d× Werkbank-Material geliefert (Schrauben: %d, Wärmeleitpaste: %.0f Anwendungen).", [n_bench, bench_screws, bench_paste], "good")
	if n_fuses > 0 or n_power > 0:
		_broadcast_fuses()
	if n_fuses > 0:
		post_event_f("📦 %d Sicherung(en) geliefert. Am Sicherungskasten mit [E] einsetzen.", [n_fuses], "good")
	if n_power > 0:
		post_event("📦 Drehsicherung geliefert. Am Sicherungskasten mit [E] in Steckplatz F2 einsetzen.", "good")
	if n_crates > 0:
		_broadcast_crates()
	_broadcast_sim_tick()


func _cart_drop_pos(cart_count: int) -> Vector3:
	return Vector3(-1.1 + float(cart_count % 3) * 0.95, 0.0, 6.4)


func _delivery_slot_pos(index: int) -> Vector3:
	# 4x4 Raster = 16 saubere Stellplätze innerhalb der gelben Lieferzonen-Markierung
	var idx := index % DELIVERY_ZONE_MAX_CRATES
	var col := idx % 4
	var row := idx / 4
	var base := Vector3(-1.35 + float(col) * 0.90, 0.0, 5.45 + float(row) * 0.78)
	if halle_nord_owned and delivery_target_site == "halle_nord":
		return HALLE_NORD_ORIGIN + Vector3(0.0, 0.0, 2.5) + base
	return base


func _find_free_delivery_slot_pos() -> Vector3:
	for offset in range(DELIVERY_ZONE_MAX_CRATES):
		var slot_idx := (_delivery_slot_cursor + offset) % DELIVERY_ZONE_MAX_CRATES
		var cand := _delivery_slot_pos(slot_idx)
		var occupied := false
		for c in crates.values():
			var cd: Dictionary = c as Dictionary
			if int(cd.get("held_by", 0)) == 0:
				var cp: Vector3 = cd.get("pos", Vector3.ZERO) as Vector3
				if Vector2(cp.x - cand.x, cp.z - cand.z).length() < 0.48:
					occupied = true
					break
		if not occupied:
			_delivery_slot_cursor = (slot_idx + 1) % DELIVERY_ZONE_MAX_CRATES
			return cand
	var fallback := _delivery_slot_pos(_delivery_slot_cursor)
	_delivery_slot_cursor = (_delivery_slot_cursor + 1) % DELIVERY_ZONE_MAX_CRATES
	return fallback


func _deliver_item_to_zone(item_type: String) -> void:
	if item_type == "cart":
		var cid := _alloc_id("cart")
		var cart_pos := _cart_drop_pos(carts.size())
		carts[cid] = {
			"id": cid,
			"pos": cart_pos,
			"rot_y": 0.0,
			"pushed_by": 0,
			"items": [],
		}
		_broadcast_carts()
		_rpc_play_sfx.rpc("place")
	elif item_type.begins_with("build:"):
		var oid := item_type.substr(6)
		var bdata: Dictionary = pending_build_orders.get(oid, {}).duplicate(true)
		pending_build_orders.erase(oid)
		var cid := _spawn_crate_internal("slot_build_box")
		var rlabel := str(bdata.get("rack_label", "Rack"))
		var sidx := int(bdata.get("slot_idx", 0))
		crates[cid]["label"] = "%s · Slot %d" % [rlabel, sidx + 1]
		crates[cid]["build_data"] = bdata
		_broadcast_crates()
		_rpc_play_sfx.rpc("drop")
		post_event_f("📦 Bausatz-Karton geliefert: %s — an der Werkbank [E] zusammenbauen!", [crates[cid]["label"]], "good")
	elif item_type.begins_with("bulk:"):
		var parts := item_type.split(":")
		var base_type := parts[1] if parts.size() >= 2 else item_type
		var pcount := clampi(int(parts[2]) if parts.size() >= 3 else 1, 1, BULK_PACK_MAX)
		_spawn_crate_internal(base_type, pcount)
		_broadcast_crates()
		_rpc_play_sfx.rpc("drop")
	else:
		_spawn_crate_internal(item_type, 1)
		_broadcast_crates()
		_rpc_play_sfx.rpc("drop")


func _broadcast_van_state() -> void:
	van_cargo_count = van_cargo.size()
	var pend_packed := _pack_items_preview(pending_delivery_items)
	pending_delivery_count = pend_packed.size()
	var trip := {
		"phase": van_trip_phase,
		"t": van_trip_time,
		"dur": van_trip_duration,
		"step": van_trip_step,
		"n": van_trip_count,
		"kind": van_trip_kind,
		"target": van_trip_target,
		"dropped": van_trip_dropped,
		"done": van_trip_done,
		"total": van_trip_total,
		"tier": van_delivery_tier,
		"sched_day": scheduled_delivery_day,
		"sched_hour": scheduled_delivery_hour,
		"express": pending_delivery_express,
	}
	_rpc_sync_van_state.rpc(van_phase, van_phase_time, van_cargo_count, pending_delivery_count, trip)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_van_state(phase: String, phase_t: float, cargo_n: int, pending_n: int, trip: Dictionary) -> void:
	if not multiplayer.is_server():
		van_phase = phase
		van_phase_time = phase_t
		van_cargo_count = cargo_n
		pending_delivery_count = pending_n
		van_trip_phase = str(trip.get("phase", ""))
		van_trip_time = float(trip.get("t", 0.0))
		van_trip_duration = float(trip.get("dur", 0.0))
		van_trip_step = int(trip.get("step", 0))
		van_trip_count = clampi(int(trip.get("n", 0)), 0, VAN_TRIP_MAX_CRATES)
		van_trip_kind = "truck" if str(trip.get("kind", "hand")) == "truck" else "hand"
		var target: Variant = trip.get("target", Vector3.ZERO)
		van_trip_target = target if target is Vector3 else Vector3.ZERO
		van_trip_dropped = clampi(int(trip.get("dropped", 0)), 0, VAN_TRIP_MAX_CRATES)
		van_trip_done = maxi(int(trip.get("done", 0)), 0)
		van_trip_total = maxi(int(trip.get("total", 0)), 0)
		van_delivery_tier = clampi(int(trip.get("tier", 1)), 1, 3)
		scheduled_delivery_day = int(trip.get("sched_day", 0))
		scheduled_delivery_hour = int(trip.get("sched_hour", -1))
		pending_delivery_express = bool(trip.get("express", false))
	van_updated.emit()


func initialize_new_world(save_id: String = "mein_datacenter", save_name: String = "Mein DataCenter") -> void:
	clear_local_state()
	is_active = true
	current_save_id = SaveManager.sanitize_save_id(save_id)
	current_save_name = save_name.strip_edges()
	if current_save_name.is_empty():
		current_save_name = "Mein DataCenter"
	money = 1800.0
	# Neuer Spielstand: F1 und F2 mit intakten Sicherungen bestückt, F3/F4 leer, Hauptschalter an.
	breaker_fuses = _make_fuse_slots("empty")
	breaker_fuses[0] = "ok"
	breaker_fuses[1] = "ok"
	fuse_stock = 0
	power_fuse_stock = 0
	breaker_on = true
	grid_outage_left = 0.0
	_grid_breaker_restore = false
	_grid_outage_cooldown = -1.0
	ups_backup_active = false
	avg_ups_charge = 0.0
	overload_timer = 0.0
	power_tier = 0
	router_tier = 0
	research_levels = {}
	room_level = 0
	halle_nord_owned = false
	delivery_target_site = "garage"
	building_upgrades.clear()
	active_constructions.clear()
	decor_items.clear()
	maint_kits = 3
	ai_platform_level = 0
	ddos_active = false
	ddos_cooldown = 70.0
	day_number = 1
	time_of_day = 0.36
	daily_kwh = 0.0
	last_daily_bill = 0
	electricity_rate = ELECTRICITY_RATE_PER_KWH
	last_bill_rate = ELECTRICITY_RATE_PER_KWH
	company_milestones_reached = 0
	company_level = 1
	room_temp = 22.0
	max_watts = int(POWER_TIERS[0]["watts"])
	max_bandwidth_cu = int(ROUTER_TIERS[0]["max_cu"])
	raw_compute = 0
	total_rental_income_per_cycle = 0.0
	reputation = REPUTATION_START
	_last_rep_tier = -1
	next_payout_in = PAYOUT_CYCLE_SECONDS
	_next_entity_num = 1
	_next_ticket_num = 101
	_delivery_slot_cursor = 0
	_autosave_accum = 0.0
	_phone_ring_accum = 0.0
	_call_cooldown = 20.0

	contracts.clear()
	for tmpl in CONTRACTS_TEMPLATE:
		var tmpl_dict: Dictionary = tmpl
		var cid := str(tmpl_dict["id"])
		var entry: Dictionary = tmpl_dict.duplicate(true)
		entry["active"] = false
		entry["status"] = "idle"
		contracts[cid] = entry
	_fill_random_contract_offers()

	# v1.0 Clean Empty Garage Start + Starter-Reparatur-Kits ordentlich im Lagerregal.
	_ensure_starter_shelf_kits()
	weather_state = "clear"
	_weather_timer = 105.0
	career_completed.clear()
	_generate_daily_deals()
	_roll_team_order()
	_recalculate_networks_and_metrics()
	world_snapshot_loaded.emit()
	state_updated.emit()
	post_event("Willkommen in deiner leeren Garage ($1.800)! Geh an den PC [E], bestelle dein erstes Rack + Server und vermiete es!", "info")


func export_save_data() -> Dictionary:
	var data := build_snapshot()
	data["next_entity_num"] = _next_entity_num
	data["next_ticket_num"] = _next_ticket_num
	data["delivery_slot_cursor"] = _delivery_slot_cursor
	data["ddos_cooldown"] = ddos_cooldown
	var all_pending: Array = []
	# Inhalt des Sammelpakets statt des Platzhalters speichern, sonst gehen Bestellungen verloren.
	for pid_v in _van_parcel_parts:
		var ps := str(pid_v)
		all_pending.append(ps if ps.begins_with("acc:") else "part:" + ps)
	for item in van_cargo:
		if str(item) != VAN_PARCEL_ITEM:
			all_pending.append(str(item))
	for item in pending_delivery_items:
		all_pending.append(str(item))
	data["pending_delivery_items"] = all_pending
	# Ware, die schon unterwegs war, kommt nach dem Laden sofort statt erst im nächsten Lieferfenster.
	if not van_cargo.is_empty() or not _van_parcel_parts.is_empty():
		data["scheduled_delivery_day"] = 0
		data["scheduled_delivery_hour"] = -1
		data["pending_delivery_express"] = false
	data["finance"] = FinanceManager.export_data()
	data["checklist_dismissed"] = checklist_dismissed
	var history := get_node_or_null("/root/StatsHistory")
	if history != null and history.has_method("export_data"):
		data["stats_history"] = history.call("export_data")
	return data


func load_from_save_data(data: Dictionary, save_id: String, display_name: String) -> void:
	clear_local_state()
	current_save_id = SaveManager.sanitize_save_id(save_id)
	current_save_name = display_name.strip_edges()
	if current_save_name.is_empty():
		current_save_name = current_save_id
	_next_entity_num = maxi(1, int(data.get("next_entity_num", 120)))
	_next_ticket_num = maxi(101, int(data.get("next_ticket_num", 101)))
	_delivery_slot_cursor = int(data.get("delivery_slot_cursor", 0))
	ddos_cooldown = float(data.get("ddos_cooldown", 55.0))
	_autosave_accum = 0.0

	_apply_snapshot(data)
	if not workbench_state.is_empty():
		workbench_state["worker"] = 0
		workbench_state["done"] = AssemblyPlan.sanitize_done(AssemblyPlan.build(workbench_state), workbench_state.get("done", {}))
	var saved_finance: Variant = data.get("finance", {})
	FinanceManager.import_data(saved_finance if saved_finance is Dictionary else {})
	# Queue any items that were in transit when the game was saved
	var saved_pending: Variant = data.get("pending_delivery_items", [])
	if saved_pending is Array:
		for item in saved_pending:
			pending_delivery_items.append(str(item))
	_migrate_mounted_strips(data)
	# Upgrade older v0.2/v0.3 saves cleanly with a starter cart
	if not data.has("carts"):
		var cid := _alloc_id("cart")
		carts[cid] = {"id": cid, "pos": Vector3(-3.2, 0.0, 2.8), "rot_y": 0.25, "pushed_by": 0, "items": []}
		carts_changed.emit()
	for tmpl in CONTRACTS_TEMPLATE:
		var tmpl_dict: Dictionary = tmpl
		var cid := str(tmpl_dict["id"])
		if not contracts.has(cid):
			var entry: Dictionary = tmpl_dict.duplicate(true)
			entry["active"] = false
			entry["status"] = "idle"
			contracts[cid] = entry
	# Ältere Spielstände ohne befristete Angebote bekommen sofort welche.
	_fill_random_contract_offers()

	checklist_dismissed = bool(data.get("checklist_dismissed", false))
	_recalculate_networks_and_metrics()
	world_snapshot_loaded.emit()
	# StatsHistory leert sich bei world_snapshot_loaded, deshalb erst danach den gespeicherten Verlauf einspielen.
	var history := get_node_or_null("/root/StatsHistory")
	if history != null and history.has_method("import_data"):
		history.call("import_data", data.get("stats_history", {}))
	state_updated.emit()
	post_event_f("Spielstand '%s' geladen! (Tag %d • $%.0f • %d Racks • %d CU)", [
		current_save_name, day_number, money, racks.size(), total_compute
	], "good")


## Spielstände vor v2.6: am Kasten bzw. Router montierte Leisten werden zu echten Leisten in Kisten.
func _migrate_mounted_strips(data: Dictionary) -> void:
	var got := 0
	for pair in [["power_strips", "prop_power_strip"], ["net_hubs", "prop_lan_strip"]]:
		var left := clampi(int(data.get(pair[0], 0)), 0, 8)
		got += left
		while left > 0:
			var n := mini(left, BULK_PACK_MAX)
			_spawn_crate_internal(str(pair[1]), n)
			left -= n
	if got > 0:
		crates_changed.emit()
		post_event_f("📦 %d montierte Leisten sind jetzt echte Leisten und stehen als Kiste in der Lieferzone. Alte Kabel bleiben stecken, bis du sie ziehst.", [got], "info")


func save_current_world(custom_display_name: String = "", is_autosave: bool = false) -> Dictionary:
	if not is_active or not NetworkManager.is_in_session or not multiplayer.is_server():
		return {"ok": false, "error": "Nur der Host kann den Spielstand speichern."}

	var target_name := custom_display_name.strip_edges()
	if not target_name.is_empty():
		current_save_name = target_name
		current_save_id = SaveManager.sanitize_save_id(target_name)
	elif current_save_id.is_empty():
		current_save_id = "mein_datacenter"
		current_save_name = "Mein DataCenter"

	var result := SaveManager.save_world(current_save_id, current_save_name, export_save_data(), is_autosave)
	if bool(result.get("ok", false)):
		_autosave_accum = 0.0
		_rpc_notify_saved.rpc(current_save_name, is_autosave)
		if not is_autosave:
			_rpc_play_sfx.rpc("save")
			post_event_f("Spielstand '%s' wurde gespeichert.", [current_save_name], "good")
	return result


@rpc("authority", "call_local", "reliable")
func _rpc_notify_saved(display_name: String, is_autosave: bool) -> void:
	world_saved.emit(display_name, is_autosave)


func clear_local_state() -> void:
	clock_scale = 1.0
	_rack_power_prev.clear()
	_strip_over.clear()
	_strip_parent.clear()
	strip_loads.clear()
	_ups_over = 0.0
	is_active = false
	FinanceManager.reset()
	racks.clear()
	coolers.clear()
	ups_units.clear()
	carts.clear()
	crates.clear()
	cables.clear()
	contracts.clear()
	parts_inventory.clear()
	shopping_cart.clear()
	pending_build_orders.clear()
	storage_shelf_slots.clear()
	workbench_state.clear()
	bench_screws = BENCH_SCREWS_START
	bench_paste = BENCH_PASTE_START
	bench_tools = {}
	weather_state = "clear"
	airflow_bonus = 0.0
	cable_mgmt_bonus = 0.0
	daily_deals.clear()
	career_completed.clear()
	active_team_order.clear()
	breaker_fuses = _make_fuse_slots("ok")
	fuse_stock = 0
	power_fuse_stock = 0
	shared_open_panels.clear()
	garage_door_open = true
	support_tickets.clear()
	active_call.clear()
	total_rental_income_per_cycle = 0.0
	total_ram_gb = 0
	total_cpu_score = 0
	total_gpu_score = 0
	total_storage_tb = 0.0
	used_bandwidth_mbps = 0.0
	max_bandwidth_mbps = 50.0
	checklist_opened_pc = false
	checklist_ordered_anything = false
	checklist_dismissed = false
	pending_delivery_items.clear()
	scheduled_delivery_day = 0
	scheduled_delivery_hour = -1
	pending_delivery_express = false
	van_cargo.clear()
	van_phase = "idle"
	van_phase_time = 0.0
	van_cargo_count = 0
	pending_delivery_count = 0
	extinguishers = make_default_extinguishers()
	ddos_active = false
	ups_backup_active = false
	overload_timer = 0.0
	_sim_accum = 0.0
	_autosave_accum = 0.0
	_phone_ring_accum = 0.0
	_call_cooldown = 20.0
	_van_unload_accum = 0.0


func _alloc_id(prefix: String) -> String:
	var id := "%s_%d" % [prefix, _next_entity_num]
	_next_entity_num += 1
	return id


## Vergibt für Racks immer die niedrigste freie Nummer ab 1 (rack_1, rack_2, ...),
## unabhängig davon, wie viele Kisten/Kabel vorher erzeugt wurden.
func _alloc_rack_id() -> String:
	var n := 1
	while racks.has("rack_%d" % n):
		n += 1
	return "rack_%d" % n


## Ohne diese Bauteile läuft ein Server nicht. Eine Grafikkarte ist optional.
const REQUIRED_PART_CATS: Array[String] = ["cpu", "ram", "storage", "cooling", "psu"]


func _default_components(server_type: String = "web_server") -> Dictionary:
	# Mainboards kommen nackt: CPU, RAM, GPU, Speicher, Kühlung und Netzteil kauft der Spieler danach selbst.
	if is_mainboard(server_type):
		return HardwareCatalog.make_empty_components()
	return HardwareCatalog.make_default_components(server_type)


func _make_empty_slot() -> Dictionary:
	return {
		"item_type": "",
		"state": "ok",
		"repair_progress": 0.0,
		"fire_level": 0.0,
		"components": _default_components(),
	}


func _make_rack_data(rack_id: String, rack_type: String, pos: Vector3, rot_y: float) -> Dictionary:
	var slot_count := int(ITEM_CATALOG.get(rack_type, {}).get("slots", 4))
	var slots: Array = []
	for _i in range(slot_count):
		slots.append(_make_empty_slot())
	return {
		"id": rack_id,
		"custom_name": "",
		"rack_type": rack_type,
		"pos": pos,
		"rot_y": rot_y,
		"powered": false,
		"networked": false,
		"temp": 22.0,
		"rental_type": "none",
		"rental_customer": "",
		"active_users": 0,
		"satisfaction": 100.0,
		"grace_timer": 0.0,
		"rental_income": 0.0,
		"metrics": {},
		"services": [],
		"slots": slots,
	}


func _ensure_loaded_compat() -> void:
	for rid in racks.keys():
		var r: Dictionary = racks[rid]
		if not r.has("rack_type"):
			r["rack_type"] = "rack"
		if not (r.get("custom_name") is String):
			r["custom_name"] = ""
		if not r.has("rental_type"):
			r["rental_type"] = "none"
		if not r.has("rental_customer"):
			r["rental_customer"] = ""
		if not r.has("active_users"):
			r["active_users"] = 0
		if not r.has("satisfaction"):
			r["satisfaction"] = 100.0
		if not r.has("grace_timer"):
			r["grace_timer"] = 0.0
		if not r.has("rental_income"):
			r["rental_income"] = 0.0
		if not r.has("metrics") or not (r["metrics"] is Dictionary):
			r["metrics"] = {}
		# Alte Spielstände hatten genau einen Dienst pro Rack: in die Dienstliste übernehmen.
		if not (r.get("services") is Array):
			var migrated: Array = []
			var old_type := str(r.get("rental_type", "none"))
			if old_type != "none" and HardwareCatalog.RENTAL_PROFILES.has(old_type):
				migrated.append({
					"type": old_type,
					"customer": str(r.get("rental_customer", "")),
					"users": float(r.get("active_users", 0)),
					"trend": 0.0,
				})
			r["services"] = migrated
		var slots: Array = r.get("slots", [])
		for s in slots:
			var sd: Dictionary = s
			var stype := str(sd.get("item_type", ""))
			if not sd.has("components") or not (sd["components"] is Dictionary):
				sd["components"] = _default_components(stype if stype != "" else "web_server")
			else:
				sd["components"] = HardwareCatalog.normalize_components(sd["components"] as Dictionary, stype if stype != "" else "web_server")
	for cid in coolers.keys():
		var c: Dictionary = coolers[cid]
		if not c.has("cooler_type"):
			c["cooler_type"] = "cooler"


func _spawn_crate_internal(item_type: String, pack_count: int = 1) -> String:
	var cid := _alloc_id("crate")
	var pos := _find_free_delivery_slot_pos()
	crates[cid] = {
		"id": cid,
		"item_type": item_type,
		"pos": pos,
		"held_by": 0,
		"pack_count": maxi(1, pack_count),
	}
	return cid


func build_snapshot() -> Dictionary:
	return {
		"current_save_name": current_save_name,
		"money": money,
		"breaker_on": breaker_on,
		"breaker_fuses": breaker_fuses.duplicate(),
		"fuse_stock": fuse_stock,
		"power_fuse_stock": power_fuse_stock,
		"power_fuse_on_way": _power_fuse_on_way(),
		"grid_outage_left": grid_outage_left,
		"grid_breaker_restore": _grid_breaker_restore,
		"ups_backup_active": ups_backup_active,
		"avg_ups_charge": avg_ups_charge,
		"overload_timer": overload_timer,
		"power_tier": power_tier,
		"router_tier": router_tier,
		"research_levels": research_levels.duplicate(),
		"room_level": room_level,
		"halle_nord_owned": halle_nord_owned,
		"delivery_target_site": delivery_target_site,
		"building_upgrades": building_upgrades.duplicate(true),
		"active_constructions": active_constructions.duplicate(true),
		"decor_items": decor_items.duplicate(true),
		"maint_kits": maint_kits,
		"company_milestones_reached": company_milestones_reached,
		"company_level": company_level,
		"ai_platform_level": ai_platform_level,
		"ddos_active": ddos_active,
		"day_number": day_number,
		"time_of_day": time_of_day,
		"clock_scale": clock_scale,
		"daily_kwh": daily_kwh,
		"last_daily_bill": last_daily_bill,
		"electricity_rate": electricity_rate,
		"last_bill_rate": last_bill_rate,
		"room_temp": room_temp,
		"total_watts": total_watts,
		"max_watts": max_watts,
		"total_compute": total_compute,
		"raw_compute": raw_compute,
		"max_bandwidth_cu": max_bandwidth_cu,
		"used_compute": used_compute,
		"revenue_bonus_mult": revenue_bonus_mult,
		"ai_revenue_per_sec": ai_revenue_per_sec,
		"next_payout_in": next_payout_in,
		"racks": racks.duplicate(true),
		"coolers": coolers.duplicate(true),
		"ups_units": ups_units.duplicate(true),
		"carts": carts.duplicate(true),
		"crates": crates.duplicate(true),
		"cables": cables.duplicate(true),
		"contracts": contracts.duplicate(true),
		"parts_inventory": parts_inventory.duplicate(true),
		"support_tickets": support_tickets.duplicate(true),
		"active_call": active_call.duplicate(true),
		"total_rental_income_per_cycle": total_rental_income_per_cycle,
		"reputation": reputation,
		"total_ram_gb": total_ram_gb,
		"total_cpu_score": total_cpu_score,
		"total_gpu_score": total_gpu_score,
		"total_storage_tb": total_storage_tb,
		"used_bandwidth_mbps": used_bandwidth_mbps,
		"max_bandwidth_mbps": max_bandwidth_mbps,
		"extinguishers": extinguishers.duplicate(true),
		"van_phase": van_phase,
		"van_phase_time": van_phase_time,
		"van_cargo_count": van_cargo.size(),
		"van_delivery_tier": van_delivery_tier,
		"pending_delivery_count": pending_delivery_items.size(),
		"scheduled_delivery_day": scheduled_delivery_day,
		"scheduled_delivery_hour": scheduled_delivery_hour,
		"pending_delivery_express": pending_delivery_express,
		"checklist_opened_pc": checklist_opened_pc,
		"checklist_ordered_anything": checklist_ordered_anything,
		"open_panels": shared_open_panels.duplicate(),
		"garage_door_open": garage_door_open,
		"storage_shelf_slots": storage_shelf_slots.duplicate(true),
		"workbench_state": workbench_state.duplicate(true),
		"bench_screws": bench_screws,
		"bench_paste": bench_paste,
		"bench_tools": bench_tools.duplicate(),
		"pending_build_orders": pending_build_orders.duplicate(true),
		"host_only_destructive": host_only_destructive,
		"weather_state": weather_state,
		"airflow_bonus": airflow_bonus,
		"cable_mgmt_bonus": cable_mgmt_bonus,
		"daily_deals": daily_deals.duplicate(true),
		"career_completed": career_completed.duplicate(),
		"active_team_order": active_team_order.duplicate(true),
	}


func send_full_snapshot_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_rpc_receive_full_snapshot.rpc_id(peer_id, build_snapshot())


@rpc("authority", "call_remote", "reliable")
func _rpc_receive_full_snapshot(snap: Dictionary) -> void:
	_apply_snapshot(snap)
	world_snapshot_loaded.emit()


func _apply_snapshot(snap: Dictionary) -> void:
	is_active = true
	current_save_name = str(snap.get("current_save_name", current_save_name))
	money = float(snap.get("money", 1200.0))
	breaker_on = bool(snap.get("breaker_on", true))
	# Alte Spielstände ohne Sicherungsdaten starten mit vollständig bestücktem Kasten.
	breaker_fuses = _sanitize_fuses(snap.get("breaker_fuses", null))
	fuse_stock = maxi(0, int(snap.get("fuse_stock", 0)))
	power_fuse_stock = clampi(int(snap.get("power_fuse_stock", 0)), 0, 1)
	power_fuse_on_way_synced = bool(snap.get("power_fuse_on_way", false))
	ups_backup_active = bool(snap.get("ups_backup_active", false))
	grid_outage_left = maxf(0.0, float(snap.get("grid_outage_left", 0.0)))
	_grid_breaker_restore = bool(snap.get("grid_breaker_restore", false))
	_grid_outage_cooldown = -1.0
	avg_ups_charge = float(snap.get("avg_ups_charge", 0.0))
	overload_timer = float(snap.get("overload_timer", 0.0))
	power_tier = int(snap.get("power_tier", 0))
	router_tier = clampi(int(snap.get("router_tier", 0)), 0, ROUTER_TIERS.size() - 1)
	research_levels = _sanitize_research(snap.get("research_levels", {}))
	# Backwards-compatible migration from old v0.2 room_expanded bool
	if snap.has("room_level"):
		room_level = clampi(int(snap.get("room_level", 0)), 0, 2)
	else:
		room_level = 1 if bool(snap.get("room_expanded", false)) else 0
	halle_nord_owned = bool(snap.get("halle_nord_owned", false))
	delivery_target_site = str(snap.get("delivery_target_site", "garage"))
	if not halle_nord_owned:
		delivery_target_site = "garage"
	building_upgrades = (snap.get("building_upgrades", {}) as Dictionary).duplicate(true)
	active_constructions = (snap.get("active_constructions", {}) as Dictionary).duplicate(true)
	decor_items = (snap.get("decor_items", {}) as Dictionary).duplicate(true)
	maint_kits = maxi(0, int(snap.get("maint_kits", 3)))
	ai_platform_level = int(snap.get("ai_platform_level", 0))
	company_milestones_reached = clampi(int(snap.get("company_milestones_reached", -1)), -1, COMPANY_VALUE_MILESTONES.size())
	company_level = clampi(int(snap.get("company_level", 0)), 0, COMPANY_LEVEL_THRESHOLDS.size())
	ddos_active = bool(snap.get("ddos_active", false))
	day_number = maxi(1, int(snap.get("day_number", 1)))
	time_of_day = clampf(float(snap.get("time_of_day", 0.36)), 0.0, 0.999)
	# Ein Spielstand startet immer mit normaler Uhr, Mitspieler übernehmen das Tempo des Hosts.
	clock_scale = 1.0 if multiplayer.is_server() else clampf(float(snap.get("clock_scale", 1.0)), 0.0, 10.0)
	daily_kwh = float(snap.get("daily_kwh", 0.0))
	last_daily_bill = int(snap.get("last_daily_bill", 0))
	electricity_rate = clampf(float(snap.get("electricity_rate", ELECTRICITY_RATE_PER_KWH)), ELECTRICITY_RATE_MIN, ELECTRICITY_RATE_MAX)
	last_bill_rate = clampf(float(snap.get("last_bill_rate", ELECTRICITY_RATE_PER_KWH)), ELECTRICITY_RATE_MIN, ELECTRICITY_RATE_MAX)
	room_temp = float(snap.get("room_temp", 22.0))
	total_watts = int(snap.get("total_watts", 0))
	max_watts = int(snap.get("max_watts", 2400))
	total_compute = int(snap.get("total_compute", 0))
	raw_compute = int(snap.get("raw_compute", total_compute))
	max_bandwidth_cu = int(snap.get("max_bandwidth_cu", int(ROUTER_TIERS[router_tier]["max_cu"])))
	used_compute = int(snap.get("used_compute", 0))
	revenue_bonus_mult = float(snap.get("revenue_bonus_mult", 1.0))
	ai_revenue_per_sec = float(snap.get("ai_revenue_per_sec", 0.0))
	next_payout_in = float(snap.get("next_payout_in", PAYOUT_CYCLE_SECONDS))
	racks = snap.get("racks", {}).duplicate(true)
	coolers = snap.get("coolers", {}).duplicate(true)
	ups_units = snap.get("ups_units", {}).duplicate(true)
	carts = snap.get("carts", {}).duplicate(true)
	crates = snap.get("crates", {}).duplicate(true)
	cables = snap.get("cables", {}).duplicate(true)
	contracts = snap.get("contracts", {}).duplicate(true)
	parts_inventory = snap.get("parts_inventory", {}).duplicate(true)
	support_tickets = snap.get("support_tickets", {}).duplicate(true)
	active_call = snap.get("active_call", {}).duplicate(true)
	total_rental_income_per_cycle = float(snap.get("total_rental_income_per_cycle", 0.0))
	reputation = clampf(float(snap.get("reputation", REPUTATION_START)), 0.0, 100.0)
	_last_rep_tier = -1
	total_ram_gb = int(snap.get("total_ram_gb", 0))
	total_cpu_score = int(snap.get("total_cpu_score", 0))
	total_gpu_score = int(snap.get("total_gpu_score", 0))
	total_storage_tb = float(snap.get("total_storage_tb", 0.0))
	used_bandwidth_mbps = float(snap.get("used_bandwidth_mbps", 0.0))
	max_bandwidth_mbps = float(snap.get("max_bandwidth_mbps", float(ROUTER_TIERS[router_tier]["max_mbps"])))
	extinguishers = _sanitize_extinguishers(snap.get("extinguishers", {}))
	shared_open_panels = _sanitize_open_panels(snap.get("open_panels", {}))
	panel_states_changed.emit()
	garage_door_open = bool(snap.get("garage_door_open", true))
	garage_door_changed.emit(garage_door_open)
	if snap.has("storage_shelf_slots") and snap["storage_shelf_slots"] is Dictionary:
		storage_shelf_slots = (snap["storage_shelf_slots"] as Dictionary).duplicate(true)
	else:
		storage_shelf_slots.clear()
		_ensure_starter_shelf_kits()
	workbench_state = (snap.get("workbench_state", {}) as Dictionary).duplicate(true) if snap.get("workbench_state", {}) is Dictionary else {}
	bench_screws = clampi(int(snap.get("bench_screws", BENCH_SCREWS_START)), 0, BENCH_SCREWS_MAX)
	bench_paste = clampf(float(snap.get("bench_paste", BENCH_PASTE_START)), 0.0, BENCH_PASTE_MAX)
	bench_tools = _sanitize_bench_tools(snap.get("bench_tools", {}))
	pending_build_orders = (snap.get("pending_build_orders", {}) as Dictionary).duplicate(true) if snap.get("pending_build_orders", {}) is Dictionary else {}
	shelf_changed.emit()
	workbench_changed.emit()
	van_phase = str(snap.get("van_phase", "idle"))
	van_phase_time = float(snap.get("van_phase_time", 0.0))
	van_cargo_count = int(snap.get("van_cargo_count", 0))
	van_delivery_tier = clampi(int(snap.get("van_delivery_tier", 1)), 1, 3)
	host_only_destructive = bool(snap.get("host_only_destructive", false))
	weather_state = str(snap.get("weather_state", "clear"))
	airflow_bonus = clampf(float(snap.get("airflow_bonus", 0.0)), 0.0, 0.35)
	cable_mgmt_bonus = clampf(float(snap.get("cable_mgmt_bonus", 0.0)), 0.0, 0.15)
	daily_deals = (snap.get("daily_deals", []) as Array).duplicate(true) if snap.get("daily_deals", []) is Array else []
	if daily_deals.is_empty() and multiplayer.is_server():
		_generate_daily_deals()
	career_completed = (snap.get("career_completed", []) as Array).duplicate() if snap.get("career_completed", []) is Array else []
	active_team_order = (snap.get("active_team_order", {}) as Dictionary).duplicate(true) if snap.get("active_team_order", {}) is Dictionary else {}
	if active_team_order.is_empty() and multiplayer.is_server():
		_roll_team_order()
	host_permissions_changed.emit()
	daily_deals_changed.emit()
	pending_delivery_count = int(snap.get("pending_delivery_count", 0))
	scheduled_delivery_day = maxi(0, int(snap.get("scheduled_delivery_day", 0)))
	scheduled_delivery_hour = clampi(int(snap.get("scheduled_delivery_hour", -1)), -1, 23)
	pending_delivery_express = bool(snap.get("pending_delivery_express", false))
	# Ältere Spielstände haben diese Felder nicht. Die übrigen Schritte leitet die Checkliste aus Racks/Kisten ab.
	checklist_opened_pc = bool(snap.get("checklist_opened_pc", false))
	checklist_ordered_anything = bool(snap.get("checklist_ordered_anything", false))
	_ensure_loaded_compat()

	racks_changed.emit()
	coolers_changed.emit()
	ups_changed.emit()
	carts_changed.emit()
	crates_changed.emit()
	cables_changed.emit()
	extinguisher_changed.emit()
	room_level_changed.emit()
	halle_nord_changed.emit()
	van_updated.emit()
	inventory_changed.emit()
	tickets_changed.emit()
	call_changed.emit()
	state_updated.emit()


func handle_player_disconnect(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var changed_crates := false
	for cid in crates.keys():
		if int(crates[cid]["held_by"]) == peer_id:
			crates[cid]["held_by"] = 0
			crates[cid]["pos"] = Vector3(0.0, 0.0, 2.0)
			changed_crates = true
	if changed_crates:
		_broadcast_crates()
	var changed_carts := false
	for kid in carts.keys():
		if int(carts[kid].get("pushed_by", 0)) == peer_id:
			carts[kid]["pushed_by"] = 0
			changed_carts = true
	if changed_carts:
		_broadcast_carts()
	player_active_slot.erase(peer_id)
	if not workbench_state.is_empty() and get_workbench_worker() == peer_id:
		workbench_state["worker"] = 0
		_broadcast_workbench()
	for ext_id in extinguishers.keys():
		var ext: Dictionary = extinguishers[ext_id]
		if int(ext["held_by"]) == peer_id:
			_stow_extinguisher(str(ext_id))
			_broadcast_extinguishers()


# ==============================================================================
# PURE STAT & QUERY HELPERS
# ==============================================================================

func get_time_string() -> String:
	var total_mins := int(floorf(time_of_day * 1440.0)) % 1440
	var hh := total_mins / 60
	var mm := total_mins % 60
	return "%02d:%02d" % [hh, mm]


## Uhrzeit des Rechners als Tagesanteil 0..1 (00:00 = 0.0).
func _real_time_of_day() -> float:
	var t := Time.get_time_dict_from_system()
	var secs := int(t.get("hour", 0)) * 3600 + int(t.get("minute", 0)) * 60 + int(t.get("second", 0))
	return float(secs) / 86400.0


func get_estimated_daily_bill() -> int:
	return int(roundf(daily_kwh * electricity_rate))


## Neuer Tagespreis: zufällige Änderung, die zum Grundpreis zurückzieht. Nur auf dem Host.
func _roll_electricity_rate(current: float) -> float:
	var pull := (ELECTRICITY_RATE_PER_KWH - current) * ELECTRICITY_RATE_REVERSION
	var swing := randf_range(-ELECTRICITY_RATE_DAILY_SWING, ELECTRICITY_RATE_DAILY_SWING)
	return snappedf(clampf(current + pull + swing, ELECTRICITY_RATE_MIN, ELECTRICITY_RATE_MAX), 0.01)


## Kategorien der Mainboard-Auswahl im Rack-Menü (Reihenfolge = Anzeige-Reihenfolge).
const MAINBOARD_CATEGORIES := [
	{"id": "entry", "label": "Einsteiger", "form": "1U", "color": Color(0.36, 0.62, 0.86),
		"desc": "Günstige Single-Sockel-Boards für Webhosting und die ersten Kunden."},
	{"id": "server", "label": "Server", "form": "1U", "color": Color(0.52, 0.48, 0.90),
		"desc": "Dual-Sockel und viele RAM-Bänke für Datenbanken und viele Nutzer."},
	{"id": "storage", "label": "Storage", "form": "2U", "color": Color(0.24, 0.68, 0.48),
		"desc": "Viele Laufwerks-Anschlüsse und Bonus-Einnahmen bei Cloud-Speicher."},
	{"id": "gpu", "label": "GPU & KI", "form": "4U", "color": Color(0.84, 0.58, 0.18),
		"desc": "Mehrere PCIe-x16-Plätze für Grafikkarten, Streaming und KI-Hosting."},
]


func is_slot_upgradeable(item_type: String) -> bool:
	# Die alten Chassis bleiben nur für bestehende Spielstände gültig.
	if item_type == "web_server" or item_type == "storage_server" or item_type == "gpu_server":
		return true
	return is_mainboard(item_type)


func is_mainboard(item_type: String) -> bool:
	var entry: Dictionary = ITEM_CATALOG.get(item_type, {})
	return bool(entry.get("mainboard", false))


## Welches 3D-Gehäuse (1U/2U/4U) für einen Einschub gezeigt wird.
func get_chassis_visual(item_type: String) -> String:
	if is_mainboard(item_type):
		return str(ITEM_CATALOG[item_type].get("chassis", "web_server"))
	return item_type


## Mainboard-IDs einer Kategorie ("" = alle), aufsteigend nach Preis sortiert.
func get_mainboards(mb_cat: String = "") -> Array:
	var out: Array = []
	for key in ITEM_CATALOG:
		var id := str(key)
		if not is_mainboard(id):
			continue
		if mb_cat != "" and str(ITEM_CATALOG[id].get("mb_cat", "")) != mb_cat:
			continue
		out.append(id)
	out.sort_custom(func(a, b) -> bool: return int(ITEM_CATALOG[a]["price"]) < int(ITEM_CATALOG[b]["price"]))
	return out


## Aktuelle Stufe eines Forschungszweigs (0 = nicht erforscht).
func get_research_level(branch: String) -> int:
	if not RESEARCH_TREE.has(branch):
		return 0
	var node: Dictionary = RESEARCH_TREE[branch]
	var levels: Array = node["levels"]
	return clampi(int(research_levels.get(branch, 0)), 0, levels.size())


## Faktor, den die erforschte Stufe auf den Wert des Zweigs anwendet (1.0 = kein Bonus).
func get_research_mult(branch: String) -> float:
	var lvl := get_research_level(branch)
	if lvl <= 0:
		return 1.0
	var node: Dictionary = RESEARCH_TREE[branch]
	var levels: Array = node["levels"]
	return float(levels[lvl - 1]["mult"])


## Kosten der nächsten Stufe, -1 wenn der Zweig unbekannt oder voll erforscht ist.
func get_research_cost(branch: String) -> int:
	if not RESEARCH_TREE.has(branch):
		return -1
	var node: Dictionary = RESEARCH_TREE[branch]
	var levels: Array = node["levels"]
	var lvl := get_research_level(branch)
	if lvl >= levels.size():
		return -1
	return int(levels[lvl]["cost"])


## Grund, warum die nächste Stufe gesperrt ist. "" = freigeschaltet (Geld wird getrennt geprüft).
func get_research_block_reason(branch: String) -> String:
	if not RESEARCH_TREE.has(branch):
		return tr("Unbekannte Forschung")
	if get_research_cost(branch) < 0:
		return tr("Voll erforscht")
	var node: Dictionary = RESEARCH_TREE[branch]
	var req: Dictionary = node.get("requires", {})
	for other in req.keys():
		var need := int(req[other])
		if get_research_level(str(other)) < need:
			var other_node: Dictionary = RESEARCH_TREE[str(other)]
			return tr("Benötigt %s %d") % [tr(str(other_node["label"])), need]
	return ""


## Nur bekannte Zweige mit gültiger Stufe übernehmen (Spielstand und Netzwerk sind nicht vertrauenswürdig).
func _sanitize_research(raw: Variant) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = raw
	for branch in RESEARCH_ORDER:
		var node: Dictionary = RESEARCH_TREE[branch]
		var levels: Array = node["levels"]
		var lvl := clampi(int(d.get(branch, 0)), 0, levels.size())
		if lvl > 0:
			out[branch] = lvl
	return out


## Bauqualität eines Einschubs oder Schlittens (0–100). Server aus alten Spielständen haben 100.
func get_build_quality(data: Dictionary) -> int:
	return clampi(int(roundf(float(data.get("build_quality", 100)))), 0, 100)


func get_slot_sloppiness(slot: Dictionary) -> float:
	return float(100 - get_build_quality(slot)) / 100.0


func get_slot_stats(slot: Dictionary) -> Dictionary:
	var item_type := str(slot.get("item_type", ""))
	if item_type == "" or not ITEM_CATALOG.has(item_type):
		return {
			"compute": 0, "watts": 0, "heat": 0.0, "fault_mult": 1.0,
			"revenue_bonus": 0.0, "total_value": 0,
			"cpu_score": 0, "ram_gb": 0, "gpu_score": 0, "vram_gb": 0,
			"storage_tb": 0.0, "psu_max_watts": 0, "psu_overloaded": false, "ram_tag": "",
			"missing_parts": [], "complete": false,
		}

	var base: Dictionary = ITEM_CATALOG[item_type]
	var compute := int(base["compute"])
	var watts := float(base["watts"])
	var heat := float(base["heat"])
	var fault_mult := 1.0
	var watt_mult := 1.0
	var total_val := int(base["price"])
	var rev_bonus := float(base.get("revenue_bonus", 0.0))
	var cpu_score := 0
	var ram_gb := 0
	var gpu_score := 0
	var vram_gb := 0
	var storage_tb := 0.0
	var psu_max_watts := 550
	var ram_tag := "DDR3"
	var missing: Array = []

	if is_slot_upgradeable(item_type):
		var raw_comps: Dictionary = slot.get("components", {})
		var comps := HardwareCatalog.normalize_components(raw_comps, item_type)
		# Mainboard-/Chassis-Basis plus alle eingebauten Bauteile
		watts = 65.0
		heat = 2.0
		compute = int(ITEM_CATALOG[item_type].get("base_compute", 4 if item_type == "web_server" else (6 if item_type == "storage_server" else 10)))
		for cat in HardwareCatalog.CATEGORY_ORDER:
			var part_id := str(comps.get(cat, ""))
			if part_id.is_empty():
				if REQUIRED_PART_CATS.has(cat):
					missing.append(cat)
				continue
			var pd := HardwareCatalog.get_part(cat, part_id)
			if pd.is_empty():
				continue
			total_val += int(pd.get("cost", 0))
			compute += int(pd.get("compute", 0))
			watts += float(pd.get("watts", 0))
			heat += float(pd.get("heat", 0.0))
			fault_mult *= float(pd.get("fault_mult", 1.0))
			rev_bonus += float(pd.get("revenue_bonus", 0.0))
			if cat == "cpu":
				cpu_score += int(pd.get("cpu_score", 12))
			elif cat == "ram":
				ram_gb += int(pd.get("ram_gb", 2))
				ram_tag = str(pd.get("tag", "DDR3"))
			elif cat == "gpu":
				gpu_score += int(pd.get("gpu_score", 4))
				vram_gb += int(pd.get("vram_gb", 0))
			elif cat == "storage":
				storage_tb += float(pd.get("storage_tb", 0.5))
			elif cat == "psu":
				psu_max_watts = int(pd.get("psu_max_watts", 350))
				watt_mult *= float(pd.get("watt_mult", 1.0))

	# Ohne Pflichtteile startet das Board nicht: keine Rechenleistung, nur Standby-Verbrauch.
	if not missing.is_empty():
		compute = 0
		watts = 10.0
		heat = 0.5
	var psu_overloaded := is_slot_upgradeable(item_type) and not missing.has("psu") and (watts > float(psu_max_watts))
	if psu_overloaded:
		fault_mult *= 2.4
		heat += 4.5

	# Forschung wirkt auf alle Server.
	heat *= get_research_mult("cooling")
	watt_mult *= get_research_mult("efficiency")
	fault_mult *= get_research_mult("reliability")

	# Schlampig gebaute Server laufen wärmer, fallen öfter aus und drosseln.
	var sloppy := get_slot_sloppiness(slot)
	heat *= 1.0 + 0.60 * sloppy
	fault_mult = clampf(fault_mult, 0.15, 3.0) * (1.0 + 2.0 * sloppy)
	var throttle := 1.0 - 0.30 * maxf(0.0, sloppy - 0.15)
	compute = int(roundf(float(compute) * throttle))
	cpu_score = int(roundf(float(cpu_score) * throttle))
	gpu_score = int(roundf(float(gpu_score) * throttle))

	var final_watts := maxi(40, int(roundf(watts * watt_mult)))
	var final_heat := maxf(1.5, heat)
	return {
		"compute": compute,
		"watts": final_watts,
		"heat": final_heat,
		"fault_mult": clampf(fault_mult, 0.15, 6.0),
		"build_quality": get_build_quality(slot),
		"revenue_bonus": rev_bonus,
		"total_value": total_val,
		"cpu_score": cpu_score,
		"ram_gb": ram_gb,
		"gpu_score": gpu_score,
		"vram_gb": vram_gb,
		"storage_tb": storage_tb,
		"psu_max_watts": psu_max_watts,
		"psu_overloaded": psu_overloaded,
		"ram_tag": ram_tag,
		"missing_parts": missing,
		"complete": missing.is_empty(),
	}


func get_rack_hardware_summary(rack_id: String) -> Dictionary:
	var out := {
		"cpu_score": 0, "ram_gb": 0, "gpu_score": 0, "vram_gb": 0,
		"storage_tb": 0.0, "watts": 0, "compute": 0,
		"active_servers": 0, "total_servers": 0, "psu_overloaded": false,
	}
	if not racks.has(rack_id):
		return out
	var r: Dictionary = racks[rack_id]
	var powered := bool(r.get("powered", false))
	var networked := bool(r.get("networked", false))
	for sl in r["slots"]:
		var sd: Dictionary = sl
		var itype := str(sd.get("item_type", ""))
		if itype == "":
			continue
		if is_slot_upgradeable(itype):
			out["total_servers"] = int(out["total_servers"]) + 1
		var st := get_slot_stats(sd)
		if not bool(sd.get("offline", false)):
			out["watts"] = int(out["watts"]) + int(st["watts"])
		if bool(st["psu_overloaded"]):
			out["psu_overloaded"] = true
		if not bool(st.get("complete", true)) and is_slot_upgradeable(itype):
			out["incomplete_servers"] = int(out.get("incomplete_servers", 0)) + 1
		if powered and networked and is_slot_on(sd) and is_slot_upgradeable(itype) and bool(st.get("complete", true)):
			out["active_servers"] = int(out["active_servers"]) + 1
			out["cpu_score"] = int(out["cpu_score"]) + int(st["cpu_score"])
			out["ram_gb"] = int(out["ram_gb"]) + int(st["ram_gb"])
			out["gpu_score"] = int(out["gpu_score"]) + int(st["gpu_score"])
			out["vram_gb"] = int(out["vram_gb"]) + int(st["vram_gb"])
			out["storage_tb"] = float(out["storage_tb"]) + float(st["storage_tb"])
			out["compute"] = int(out["compute"]) + int(st["compute"])
	return out


func get_open_ticket_count() -> int:
	return support_tickets.size()


func get_part_stock(part_id: String) -> int:
	return int(parts_inventory.get(part_id, 0))


func get_total_inventory_parts() -> int:
	var n := 0
	for k in parts_inventory.keys():
		n += maxi(0, int(parts_inventory[k]))
	return n


func get_starter_checklist() -> Array:
	var has_rack := not racks.is_empty()
	var has_ordered := checklist_ordered_anything or has_rack or not crates.is_empty() or van_phase != "idle" or get_total_inventory_parts() > 0
	var has_server := false
	var has_wired := false
	var has_rented := false
	for rid in racks.keys():
		var r: Dictionary = racks[rid]
		if bool(r.get("powered", false)) and bool(r.get("networked", false)):
			has_wired = true
		if str(r.get("rental_type", "none")) != "none":
			has_rented = true
		for sl in r["slots"]:
			if str((sl as Dictionary).get("item_type", "")) != "":
				has_server = true
	# "hint" erklärt den aktuellen Schritt. {aktion} wird im HUD durch die belegte Taste ersetzt.
	return [
		{"text": "PC am Schreibtisch öffnen [E]", "done": checklist_opened_pc or has_ordered,
			"hint": "Geh zum Schreibtisch, schau auf den Monitor und drück [E]."},
		{"text": "Im Shop Rack + Server-Chassis bestellen", "done": has_ordered,
			"hint": "Kauf im Shop am PC ein Rack und mindestens ein Server-Chassis. Die Bestellung wird geliefert."},
		{"text": "Rack aufstellen & Server einschieben [E]", "done": has_rack and has_server,
			"hint": "Stell das Rack auf, [R] dreht es. Schieb dann den Server mit [E] in einen freien Slot."},
		{"text": "Strom (gelb) & LAN (blau) verkabeln [E]", "done": has_wired,
			"hint": "Nimm das Stromkabel [{tool_power_cable}] und das LAN-Kabel [{tool_net_cable}] und schließ das Rack mit [E] an. Erst mit beidem läuft es."},
		{"text": "Rack im Rack-Menü [E] vermieten", "done": has_rented,
			"hint": "Öffne am Rack das Rack-Menü und wähl einen Mietvertrag. Ab dann zahlen Kunden Miete."},
	]


## Lässt bis zu WATER_LEAK_MAX_SLOTS laufende Server eines zufälligen Racks mit Strom abstürzen.
func _trigger_water_leak() -> void:
	var candidates: Array[String] = []
	for rid in racks.keys():
		var rack: Dictionary = racks[rid]
		if not bool(rack.get("powered", false)):
			continue
		for slot in rack["slots"]:
			if str(slot["item_type"]) != "" and is_slot_on(slot):
				candidates.append(str(rid))
				break
	if candidates.is_empty():
		return

	var target := candidates[randi() % candidates.size()]
	var slots: Array = racks[target]["slots"]
	var ok_idx: Array[int] = []
	for i in range(slots.size()):
		var s: Dictionary = slots[i]
		if str(s["item_type"]) != "" and is_slot_on(s):
			ok_idx.append(i)
	ok_idx.shuffle()

	var hit := PackedStringArray()
	for j in range(mini(WATER_LEAK_MAX_SLOTS, ok_idx.size())):
		var slot: Dictionary = slots[ok_idx[j]]
		slot["state"] = "crashed"
		slot["repair_progress"] = 0.0
		slot["faulty_part"] = ""
		slot["diagnosed"] = false
		slot["fault_hidden"] = false
		hit.append(str(ok_idx[j] + 1))

	money = maxf(0.0, money - WATER_LEAK_COST)
	post_event_f("WASSERSCHADEN über %s! Slot %s ausgefallen, Trocknung kostet $%d. Reparatur über die 3D-Vorschau im Rack-Menü.", [
		get_rack_display_name(target), ", ".join(hit), int(WATER_LEAK_COST)
	], "alert")
	_rpc_play_sfx.rpc("alarm")
	_recalculate_networks_and_metrics()
	_broadcast_racks()


func is_ticket_issue_fixed(ticket: Dictionary) -> bool:
	var rid := str(ticket.get("rack_id", ""))
	if not racks.has(rid):
		return true
	var r: Dictionary = racks[rid]
	if str(r.get("rental_type", "none")) == "none":
		return true
	var issue := str(ticket.get("issue_key", "ok"))
	var m: Dictionary = r.get("metrics", {})
	if not bool(r.get("powered", false)) or not bool(r.get("networked", false)):
		return false
	match issue:
		"ram":
			return float(m.get("ram_pct", 0.0)) < 88.0
		"cpu":
			return float(m.get("cpu_pct", 0.0)) < 88.0
		"gpu":
			return float(m.get("gpu_pct", 0.0)) < 88.0
		"storage":
			return float(m.get("storage_pct", 0.0)) < 88.0
		"network":
			return float(m.get("net_pct", 0.0)) < 90.0 and used_bandwidth_mbps <= max_bandwidth_mbps
		"overheat":
			return float(r.get("temp", 22.0)) < 68.0
		"psu":
			return not bool(get_rack_hardware_summary(rid)["psu_overloaded"])
		"offline":
			return bool(r.get("powered", false)) and bool(r.get("networked", false)) and int(get_rack_hardware_summary(rid)["active_servers"]) > 0
		_:
			return str(m.get("bottleneck", "ok")) == "ok"


func get_rack_sell_value(rack_id: String) -> int:
	if not racks.has(rack_id):
		return 0
	var r: Dictionary = racks[rack_id]
	var rtype := str(r.get("rack_type", "rack"))
	var total := int(ITEM_CATALOG.get(rtype, {}).get("price", 400))
	for slot in r["slots"]:
		var st := get_slot_stats(slot as Dictionary)
		total += int(st["total_value"])
	return int(roundf(float(total) * SELL_REFUND_RATIO))


func get_device_sell_value(kind: String, eid: String) -> int:
	if kind == "cooler" and coolers.has(eid):
		var ctype := str(coolers[eid].get("cooler_type", "cooler"))
		return int(roundf(float(ITEM_CATALOG[ctype]["price"]) * SELL_REFUND_RATIO))
	if kind == "decor" and decor_items.has(eid):
		var dtype := str((decor_items[eid] as Dictionary).get("item_type", ""))
		return int(roundf(float((ITEM_CATALOG.get(dtype, {}) as Dictionary).get("price", 0)) * SELL_REFUND_RATIO))
	if kind == "ups" and ups_units.has(eid):
		return int(roundf(float(ITEM_CATALOG[get_ups_type(ups_units[eid])]["price"]) * SELL_REFUND_RATIO * (0.5 + 0.5 * get_ups_health(ups_units[eid]) / 100.0)))
	if kind == "cart" and carts.has(eid):
		var total := int(ITEM_CATALOG["cart"]["price"])
		var c_items: Array = carts[eid].get("items", [])
		for it in c_items:
			total += int(ITEM_CATALOG.get(str(it), {}).get("price", 0))
		return int(roundf(float(total) * SELL_REFUND_RATIO))
	return 0


func get_active_slot(peer_id: int) -> int:
	return clampi(int(player_active_slot.get(peer_id, 1)), 1, SLOT_COUNT)


## Kiste im aktiven Slot des Spielers (Kisten in anderen Slots zählen nicht).
func get_player_held_crate(peer_id: int) -> Dictionary:
	var slot := get_active_slot(peer_id)
	for cid in crates.keys():
		var c: Dictionary = crates[cid]
		if int(c.get("held_by", 0)) == peer_id and int(c.get("held_slot", 1)) == slot:
			return c
	return {}


func get_player_pushed_cart(peer_id: int) -> Dictionary:
	for cid in carts.keys():
		var c: Dictionary = carts[cid]
		if int(c.get("pushed_by", 0)) == peer_id:
			return c
	return {}


static func make_default_extinguishers() -> Dictionary:
	var out := {}
	for st in ["garage", "nord"]:
		out[st] = {"station": st, "held_by": 0, "slot": 1, "pos": Vector3.ZERO, "yaw": 0.0, "fill": 1.0}
	return out


func _sanitize_extinguishers(raw: Variant) -> Dictionary:
	var out := make_default_extinguishers()
	if not (raw is Dictionary):
		return out
	var used := {}
	for id in out.keys():
		var r: Variant = (raw as Dictionary).get(id, null)
		if not (r is Dictionary):
			continue
		var e: Dictionary = out[id]
		var rd: Dictionary = r
		e["held_by"] = maxi(0, int(rd.get("held_by", 0)))
		e["slot"] = clampi(int(rd.get("slot", 1)), 1, SLOT_COUNT)
		e["fill"] = clampf(float(rd.get("fill", 1.0)), 0.0, 1.0)
		e["yaw"] = float(rd.get("yaw", 0.0))
		if rd.get("pos", null) is Vector3:
			e["pos"] = rd["pos"]
		var st := str(rd.get("station", id))
		if st != "" and (not EXT_STATIONS.has(st) or used.has(st)):
			st = ""
		if int(e["held_by"]) != 0:
			st = ""
		if st != "":
			used[st] = true
		e["station"] = st
	for id in out.keys():
		var e2: Dictionary = out[id]
		# Ohne Halter, Hand und Bodenplatz wäre der Löscher verschwunden: zurück an den eigenen Halter.
		if str(e2["station"]) == "" and int(e2["held_by"]) == 0 and (e2["pos"] as Vector3) == Vector3.ZERO:
			for st2 in EXT_STATIONS:
				if not used.has(st2):
					e2["station"] = st2
					used[st2] = true
					break
	return out


## Feuerlöscher im aktiven Slot des Spielers, sonst "".
func get_held_extinguisher(peer_id: int) -> String:
	var slot := get_active_slot(peer_id)
	for id in extinguishers.keys():
		var e: Dictionary = extinguishers[id]
		if int(e["held_by"]) == peer_id and int(e["slot"]) == slot:
			return str(id)
	return ""


func get_extinguisher_at_station(station: String) -> String:
	for id in extinguishers.keys():
		var e: Dictionary = extinguishers[id]
		if int(e["held_by"]) == 0 and str(e["station"]) == station:
			return str(id)
	return ""


func get_extinguisher_fill(ext_id: String) -> float:
	return float((extinguishers.get(ext_id, {}) as Dictionary).get("fill", 0.0))


func is_player_holding_extinguisher(peer_id: int) -> bool:
	return get_held_extinguisher(peer_id) != ""


func _stow_extinguisher(ext_id: String) -> void:
	var e: Dictionary = extinguishers[ext_id]
	e["held_by"] = 0
	for st in [ext_id] + EXT_STATIONS:
		if get_extinguisher_at_station(st) == "":
			e["station"] = st
			return
	e["station"] = ""
	e["pos"] = Vector3(-2.8, 0.0, -3.6)


func is_player_holding_anything(peer_id: int) -> bool:
	return (
		is_player_holding_extinguisher(peer_id)
		or not get_player_held_crate(peer_id).is_empty()
		or not get_player_pushed_cart(peer_id).is_empty()
	)


func get_free_compute() -> int:
	if ddos_active:
		return 0
	return maxi(0, total_compute - used_compute)


func has_any_fire() -> bool:
	for rid in racks.keys():
		for slot in racks[rid]["slots"]:
			if str(slot["state"]) == "burning":
				return true
	return false


func has_any_crash() -> bool:
	for rid in racks.keys():
		for slot in racks[rid]["slots"]:
			if str(slot["item_type"]) != "" and str(slot["state"]) == "crashed":
				return true
	return false


func count_cables_on(cable_type: String, endpoint_id: String) -> int:
	var n := 0
	for cid in cables.keys():
		var c: Dictionary = cables[cid]
		if str(c["cable_type"]) == cable_type:
			if str(c["from_id"]) == endpoint_id or str(c["to_id"]) == endpoint_id:
				n += 1
	return n


## Buchse jedes Kabels an einem Anschluss: {cable_id: slot}. Kabel ohne gespeicherte Buchse
## (alte Spielstände) bekommen der Reihe nach die freien Buchsen, sortiert nach Kabel-ID.
func get_cable_slot_map(cable_type: String, endpoint_id: String) -> Dictionary:
	var result := {}
	var used := {}
	var legacy: Array[String] = []
	for cid in cables.keys():
		var c: Dictionary = cables[cid]
		if str(c.get("cable_type", "")) != cable_type:
			continue
		var s := -1
		if str(c.get("from_id", "")) == endpoint_id:
			s = int(c.get("from_slot", -1))
		elif str(c.get("to_id", "")) == endpoint_id:
			s = int(c.get("to_slot", -1))
		else:
			continue
		if s >= 0 and not used.has(s):
			result[str(cid)] = s
			used[s] = true
		else:
			legacy.append(str(cid))
	legacy.sort()
	var next := 0
	for cid in legacy:
		while used.has(next):
			next += 1
		result[cid] = next
		used[next] = true
	return result


## Gewünschte Buchse, wenn sie existiert und frei ist, sonst die erste freie. -1 = keine frei.
func pick_free_slot(cable_type: String, endpoint_id: String, wanted: int) -> int:
	var used: Array = get_cable_slot_map(cable_type, endpoint_id).values()
	var max_n := get_max_ports(cable_type, endpoint_id)
	if wanted >= 0 and wanted < max_n and not used.has(wanted):
		return wanted
	for i in range(max_n):
		if not used.has(i):
			return i
	return -1


## Cluster-Ports pro Rack: Ein Rack kann sich mit bis zu zwei Nachbar-Racks zusammenschließen.
const CLUSTER_PORTS_PER_RACK := 2


## Physische RJ45-Port-Anzahl je Router-Stufe (0=DSL, 1=VDSL, 2=Gateway, 3=Core10G, 4=Core100G).
const ROUTER_TIER_JACK_COUNTS: Array[int] = [2, 3, 5, 6, 6]


func is_power_strip_decor(eid: String) -> bool:
	return decor_items.has(eid) and str((decor_items[eid] as Dictionary).get("item_type", "")) == "prop_power_strip"


func is_lan_strip_decor(eid: String) -> bool:
	return decor_items.has(eid) and str((decor_items[eid] as Dictionary).get("item_type", "")) == "prop_lan_strip"


## Liefert das Kabel an genau dieser Buchse (slot_idx), oder {} wenn der Port frei ist.
func get_cable_on_slot(cable_type: String, endpoint_id: String, slot_idx: int) -> Dictionary:
	if slot_idx < 0:
		return {}
	var smap := get_cable_slot_map(cable_type, endpoint_id)
	for cid in smap.keys():
		if int(smap[cid]) == slot_idx and cables.has(cid):
			return cables[cid] as Dictionary
	return {}


func get_max_ports(cable_type: String, endpoint_id: String) -> int:
	if cable_type == "cluster":
		return CLUSTER_PORTS_PER_RACK if racks.has(endpoint_id) else 0
	if cable_type == "power":
		if endpoint_id == WALL_BREAKER_ID:
			return BREAKER_BASE_SOCKETS
		if endpoint_id == HALL_C_BREAKER_ID:
			return 6 + power_tier * 2
		if endpoint_id == HALL_NORD_BREAKER_ID:
			return 16
		if is_power_strip_decor(endpoint_id):
			return 6
		if racks.has(endpoint_id):
			return 2
		if coolers.has(endpoint_id):
			# Das Innengerät hat keine Strombuchse, es läuft über das Außengerät.
			return 0 if is_indoor_unit(endpoint_id) else 1
		if ups_units.has(endpoint_id):
			return 2 # Connect to breaker AND optionally daisy-chain out
		return 0
	else:
		if endpoint_id == WALL_ROUTER_ID:
			return ROUTER_TIER_JACK_COUNTS[clampi(router_tier, 0, ROUTER_TIER_JACK_COUNTS.size() - 1)]
		if endpoint_id == HALL_C_ROUTER_ID:
			return 4
		if endpoint_id == HALL_NORD_ROUTER_ID:
			return 16
		if is_lan_strip_decor(endpoint_id):
			return 8
		if racks.has(endpoint_id):
			return 1 + _count_rack_switches(endpoint_id) * 3
		return 0


func _count_rack_switches(rack_id: String) -> int:
	if not racks.has(rack_id):
		return 0
	var count := 0
	for slot in racks[rack_id]["slots"]:
		if str(slot["item_type"]) == "net_switch" and str(slot["state"]) == "ok":
			count += 1
	return count


const INDOOR_UNIT_TYPE := "indoor_unit"
## Goldis-Außengeräte stehen nur auf dem Rasen rechts vom Garagentor (von der Straße aus gesehen).
const HEAT_PUMP_LAWN_MIN := Vector2(4.5, 5.5)
const HEAT_PUMP_LAWN_MAX := Vector2(10.0, 7.0)
const HEAT_PUMP_TREE_POS := Vector2(6.8, 7.5)
const HEAT_PUMP_TREE_CLEARANCE := 1.3
const HEAT_PUMP_SPACING := 1.25
## Goldis-Innengeräte hängen an den Innenseiten der Außenwände.
const WALL_UNIT_Y := 2.35
const WALL_UNIT_OFFSET := 0.12
const WALL_UNIT_HALF_WIDTH := 0.5
const WALL_UNIT_SPACING := 1.05
const WALL_HIT_TOLERANCE := 0.3
const WALL_FACE_NORTH_Z := -4.475
const WALL_FACE_SOUTH_Z := 4.475
const WALL_FACE_WEST_X := -5.475
const WALL_FACE_EAST_X := 21.475
const GARAGE_DOOR_HALF_WIDTH := 2.2


## Notstrom: Kapazität (Wh), höchste Abgabe (W), Ladeleistung (W), Wärme und Preis für neue Akkus.
const UPS_TYPES := {
	"ups": {"cap": 2000.0, "out": 3000.0, "charge_w": 300.0, "heat": 0.8, "swap": 250},
	"ups_cabinet": {"cap": 9000.0, "out": 9000.0, "charge_w": 1500.0, "heat": 3.0, "swap": 1100},
	"ups_container": {"cap": 40000.0, "out": 30000.0, "charge_w": 6000.0, "heat": 8.0, "swap": 4200},
}
## Eine echte Sekunde ist eine Spielminute, 60 davon sind eine Stunde für die Wh-Rechnung.
const UPS_SECONDS_PER_HOUR := 60.0
const UPS_WEAR_PER_CYCLE := 0.6
const UPS_MIN_HEALTH := 25.0
var _ups_over: float = 0.0


func is_ups_type(item_type: String) -> bool:
	return UPS_TYPES.has(item_type)


func get_ups_type(u: Dictionary) -> String:
	var t := str(u.get("ups_type", "ups"))
	return t if UPS_TYPES.has(t) else "ups"


func get_ups_spec(u: Dictionary) -> Dictionary:
	return UPS_TYPES[get_ups_type(u)]


func get_ups_health(u: Dictionary) -> float:
	return clampf(float(u.get("health", 100.0)), UPS_MIN_HEALTH, 100.0)


## Nutzbare Kapazität in Wh, Alterung eingerechnet.
func get_ups_capacity(u: Dictionary) -> float:
	return float(get_ups_spec(u)["cap"]) * get_ups_health(u) / 100.0


func get_ups_stored_wh(u: Dictionary) -> float:
	return get_ups_capacity(u) * clampf(float(u.get("charge", 0.0)), 0.0, 100.0) / 100.0


func is_ups_ready(u: Dictionary) -> bool:
	return bool(u.get("connected", false)) and float(u.get("charge", 0.0)) > 0.2 and not bool(u.get("tripped", false))


## Gesamte Abgabeleistung aller bereiten Notstrom-Geräte.
func get_ups_total_out() -> float:
	var sum := 0.0
	for uid in ups_units.keys():
		if is_ups_ready(ups_units[uid]):
			sum += float(get_ups_spec(ups_units[uid])["out"])
	return sum


## Restzeit in Spielminuten bei aktueller Last (alle bereiten Geräte zusammen).
func get_ups_runtime_minutes() -> int:
	var wh := 0.0
	for uid in ups_units.keys():
		if is_ups_ready(ups_units[uid]):
			wh += get_ups_stored_wh(ups_units[uid])
	return int(wh / maxf(50.0, float(total_watts) * 1.06) * 60.0)


func request_swap_ups_cells(uid: String) -> void:
	_rpc_req_swap_ups_cells.rpc_id(1, uid)


func get_ups_swap_cost(u: Dictionary) -> int:
	return int(get_ups_spec(u)["swap"])


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_swap_ups_cells(uid: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not ups_units.has(uid) or not SecurityGuard.check_rate_limit(peer_id, "ups_swap", 4, 5.0):
		return
	var u: Dictionary = ups_units[uid]
	var cost := get_ups_swap_cost(u)
	if money < float(cost) or get_ups_health(u) > 95.0 or bool(u.get("discharging", false)):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money -= float(cost)
	u["health"] = 100.0
	u["charge"] = minf(float(u.get("charge", 0.0)), 40.0)
	_recalculate_networks_and_metrics()
	_broadcast_ups()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("upgrade")
	post_event_f("%s hat die Akkus von %s getauscht (-$%d).", [NetworkManager.get_player_name(peer_id), uid.to_upper(), cost], "good")


## Außengeräte (Rasen). Brauchen ein Goldis Innengerät.
func is_heat_pump_type(item_type: String) -> bool:
	return item_type == "cooler" or item_type == "chiller" or item_type == "cool_k90" or item_type == "cool_tower"


## Standgeräte, die drinnen neben den Racks stehen und ohne Innengerät kühlen.
func is_floor_cooler_type(item_type: String) -> bool:
	return item_type == "cool_inrow" or item_type == "cool_cdu"


func is_indoor_unit(cooler_id: String) -> bool:
	return coolers.has(cooler_id) and str(coolers[cooler_id].get("cooler_type", "cooler")) == INDOOR_UNIT_TYPE


func has_indoor_unit() -> bool:
	for cid in coolers.keys():
		if str(coolers[cid].get("cooler_type", "cooler")) == INDOOR_UNIT_TYPE:
			return true
	return false


## Platzierungsprüfung je nach Gerätetyp: Außengeräte auf den Rasen, Innengeräte an die Wand, alles andere in die Halle.
func can_place_item_at(item_type: String, pos: Vector3, rot_y: float = 0.0, ignore_rack_id: String = "") -> bool:
	if is_heat_pump_type(item_type):
		return can_place_heat_pump_at(pos)
	if item_type == INDOOR_UNIT_TYPE:
		return can_place_wall_unit_at(pos, rot_y)
	if is_strip_type(item_type):
		if pos.y >= STRIP_WALL_MIN_Y:
			return can_place_strip_on_wall(pos, rot_y, ignore_rack_id)
		return can_place_strip_at(pos, ignore_rack_id)
	if item_type == "ups_container":
		return can_place_at(pos, ignore_rack_id) and _is_wide_spot_free(pos)
	return can_place_at(pos, ignore_rack_id)


## Der Batterie-Container ist 2 m breit und braucht rundum Platz.
func _is_wide_spot_free(pos: Vector3) -> bool:
	for group in [racks, coolers, ups_units]:
		for gid in (group as Dictionary).keys():
			var entry: Dictionary = (group as Dictionary)[gid]
			if str(entry.get("cooler_type", "")) == INDOOR_UNIT_TYPE:
				continue
			var gpos: Vector3 = entry["pos"]
			if Vector2(gpos.x - pos.x, gpos.z - pos.z).length() < 1.7:
				return false
	return true


## Strom- und LAN-Leisten sind flach: feineres Raster und weniger Abstand zu Geräten.
func is_strip_type(item_type: String) -> bool:
	return item_type == "prop_power_strip" or item_type == "prop_lan_strip"


## Leisten an der Wand: Höhe über dem Boden ab hier, darunter liegt die Leiste.
const STRIP_WALL_MIN_Y := 0.28
const STRIP_WALL_MAX_Y := 1.75
## Dauerlast in Watt: normale Leiste und Hauptleiste direkt am Stromkasten (Drehstrom-Zuleitung).
const STRIP_LIMIT_W := 3500
const STRIP_MAIN_LIMIT_W := 22000
const STRIP_TRIP_SECONDS := 4.0
var strip_loads: Dictionary = {}
var _strip_over: Dictionary = {}
var _strip_parent: Dictionary = {}


func is_strip_on(did: String) -> bool:
	return bool((decor_items.get(did, {}) as Dictionary).get("on", true))


func is_wall_strip(d: Dictionary) -> bool:
	return bool(d.get("wall", false))


func get_strip_limit(did: String) -> int:
	if not is_power_strip_decor(did):
		return 0
	for cid in cables.keys():
		var c: Dictionary = cables[cid]
		if str(c.get("cable_type", "")) != "power":
			continue
		var a := str(c["from_id"])
		var b := str(c["to_id"])
		if (a == did or b == did) and ([WALL_BREAKER_ID, HALL_C_BREAKER_ID, HALL_NORD_BREAKER_ID].has(a) or [WALL_BREAKER_ID, HALL_C_BREAKER_ID, HALL_NORD_BREAKER_ID].has(b)):
			return STRIP_MAIN_LIMIT_W
	return STRIP_LIMIT_W


func get_strip_load(did: String) -> int:
	return int(strip_loads.get(did, 0))


func request_toggle_strip(did: String) -> void:
	_rpc_req_toggle_strip.rpc_id(1, did)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_toggle_strip(did: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not (is_power_strip_decor(did) or is_lan_strip_decor(did)) or not SecurityGuard.check_rate_limit(peer_id, "strip", 8, 4.0):
		return
	var d: Dictionary = decor_items[did]
	var on := not is_strip_on(did)
	d["on"] = on
	if on:
		d["tripped"] = false
		_strip_over.erase(did)
	_after_strip_change()
	_rpc_play_sfx.rpc("strip_switch")


func _after_strip_change() -> void:
	_recalculate_networks_and_metrics()
	_broadcast_decor_items()
	_broadcast_racks()
	_broadcast_coolers()
	_broadcast_ups()
	_broadcast_sim_tick()


## Überlastete Leisten lösen nach ein paar Sekunden aus (nur Host).
func _tick_strips(dt: float) -> void:
	for did_v in strip_loads.keys():
		var did := str(did_v)
		if not is_power_strip_decor(did) or not is_strip_on(did):
			_strip_over.erase(did)
			continue
		if get_strip_load(did) <= get_strip_limit(did):
			_strip_over.erase(did)
			continue
		_strip_over[did] = float(_strip_over.get(did, 0.0)) + dt
		if float(_strip_over[did]) >= STRIP_TRIP_SECONDS:
			_strip_over.erase(did)
			decor_items[did]["on"] = false
			decor_items[did]["tripped"] = true
			post_event_f("STROMLEISTE AUSGELÖST: %d W bei höchstens %d W. Last verteilen und am Schalter wieder einschalten.", [get_strip_load(did), get_strip_limit(did)], "alert")
			_after_strip_change()
			_rpc_play_sfx.rpc("breaker_trip")
			return


## Last aller Geräte den Kabelweg zurück bis zum Stromkasten auf die Leisten verteilen.
func _compute_strip_loads(device_watts: Dictionary) -> void:
	var loads := {}
	for did in decor_items.keys():
		if is_power_strip_decor(str(did)):
			loads[did] = 0
	for dev in device_watts.keys():
		var cur := str(dev)
		var guard := 0
		while _strip_parent.has(cur) and guard < 64:
			guard += 1
			cur = str(_strip_parent[cur])
			if loads.has(cur):
				loads[cur] = int(loads[cur]) + int(device_watts[dev])
	strip_loads = loads
	strip_loads_changed.emit()


## Montageplatz einer Leiste an einer Wand. Leer = hier geht es nicht.
func get_strip_wall_spot(hit: Vector3, normal: Vector3) -> Dictionary:
	if absf(normal.y) > 0.3:
		return {}
	var n := Vector3(signf(normal.x), 0.0, 0.0) if absf(normal.x) > absf(normal.z) else Vector3(0.0, 0.0, signf(normal.z))
	var y := clampf(roundf(hit.y * 10.0) / 10.0, STRIP_WALL_MIN_Y + 0.02, STRIP_WALL_MAX_Y)
	for w in _strip_walls():
		var wn: Vector3 = w["n"]
		if not wn.is_equal_approx(n):
			continue
		var on_x := absf(wn.z) > 0.5
		var plane: float = w["at"]
		if absf((hit.z if on_x else hit.x) - plane) > WALL_HIT_TOLERANCE:
			continue
		var along := clampf(roundf((hit.x if on_x else hit.z) * 4.0) / 4.0, float(w["lo"]), float(w["hi"]))
		if absf(along - (hit.x if on_x else hit.z)) > 0.6:
			continue
		var pos := Vector3(along, y, plane) if on_x else Vector3(plane, y, along)
		return {"pos": pos, "rot_y": atan2(wn.x, wn.z)}
	return {}


func _strip_walls() -> Array:
	var out: Array = []
	var max_x := _interior_max_x() - 0.5
	out.append({"n": Vector3(0, 0, 1), "at": WALL_FACE_NORTH_Z, "lo": -5.0, "hi": max_x})
	out.append({"n": Vector3(0, 0, -1), "at": WALL_FACE_SOUTH_Z, "lo": -5.0, "hi": max_x})
	out.append({"n": Vector3(1, 0, 0), "at": WALL_FACE_WEST_X, "lo": -4.0, "hi": 4.0})
	if room_level >= 2:
		out.append({"n": Vector3(-1, 0, 0), "at": WALL_FACE_EAST_X, "lo": -4.0, "hi": 4.0})
	if halle_nord_owned:
		var o := HALLE_NORD_ORIGIN
		out.append({"n": Vector3(0, 0, 1), "at": o.z - 5.86, "lo": -9.3, "hi": 9.3})
		out.append({"n": Vector3(0, 0, -1), "at": o.z + 5.86, "lo": -9.3, "hi": 9.3})
		out.append({"n": Vector3(1, 0, 0), "at": -9.86, "lo": o.z - 5.3, "hi": o.z + 5.3})
		out.append({"n": Vector3(-1, 0, 0), "at": 9.86, "lo": o.z - 5.3, "hi": o.z + 5.3})
	return out


## Was schon an der Wand hängt: [x, y, halbe Breite, halbe Höhe] je Wandebene z.
const STRIP_WALL_KEEPOUT := [
	[-4.475, -4.2, 1.15, 0.55, 0.85], [-4.475, -2.8, 1.25, 0.45, 0.60], [-4.475, -1.0, 1.6, 0.60, 0.45],
	[-4.475, 14.6, 1.55, 0.75, 0.70], [-4.475, 16.6, 1.6, 0.75, 0.50],
]


func can_place_strip_on_wall(pos: Vector3, rot_y: float, ignore_id: String = "") -> bool:
	if pos.y < STRIP_WALL_MIN_Y or pos.y > STRIP_WALL_MAX_Y + 0.01:
		return false
	var n := Vector3(sin(rot_y), 0.0, cos(rot_y)).round()
	var spot := get_strip_wall_spot(pos, n)
	if spot.is_empty() or (spot["pos"] as Vector3).distance_to(pos) > 0.05:
		return false
	if absf(n.z) > 0.5:
		var local_z := pos.z - HALLE_NORD_ORIGIN.z if pos.z < -100.0 else pos.z
		# Tore frei lassen
		if n.z < 0.0 and local_z > 4.0 and absf(pos.x) < 2.75:
			return false
		if pos.z > -100.0:
			for k in STRIP_WALL_KEEPOUT:
				if absf(pos.z - float(k[0])) < 0.2 and absf(pos.x - float(k[1])) < float(k[3]) + 0.34 and absf(pos.y - float(k[2])) < float(k[4]) + 0.07:
					return false
	for did in decor_items.keys():
		if str(did) == ignore_id:
			continue
		var d: Dictionary = decor_items[did]
		if is_wall_strip(d) and (d["pos"] as Vector3).distance_to(pos) < 0.72 and absf((d["pos"] as Vector3).y - pos.y) < 0.14:
			return false
	for cid in coolers.keys():
		var c: Dictionary = coolers[cid]
		if str(c.get("cooler_type", "")) == INDOOR_UNIT_TYPE and (c["pos"] as Vector3).distance_to(pos) < 0.75:
			return false
	return true


func snap_place_pos(item_type: String, pos: Vector3) -> Vector3:
	if is_strip_type(item_type) and pos.y >= STRIP_WALL_MIN_Y:
		return pos
	var f := 4.0 if is_strip_type(item_type) else 2.0
	return Vector3(roundf(pos.x * f) / f, 0.0, roundf(pos.z * f) / f)


func can_place_strip_at(pos: Vector3, ignore_id: String = "") -> bool:
	if halle_nord_owned and pos.z < -100.0:
		var lz := pos.z - HALLE_NORD_ORIGIN.z
		if pos.x < -9.3 or pos.x > 9.3 or lz < -5.0 or lz > 5.2:
			return false
		if lz < -2.3 and pos.x > 4.3:
			return false
		if lz > 4.0 and absf(pos.x) < 2.3:
			return false
	else:
		var max_x := 4.8 if room_level == 0 else (11.7 if room_level == 1 else 20.6)
		if pos.x < -4.8 or pos.x > max_x or pos.z < -4.0 or pos.z > 3.9:
			return false
		if pos.z > 2.6 and absf(pos.x) < 2.2:
			return false
	for group in [racks, coolers, ups_units]:
		for gid in (group as Dictionary).keys():
			var entry: Dictionary = (group as Dictionary)[gid]
			if str(entry.get("cooler_type", "")) == INDOOR_UNIT_TYPE:
				continue
			var gpos: Vector3 = entry["pos"]
			if Vector2(gpos.x - pos.x, gpos.z - pos.z).length() < 0.62:
				return false
	for did in decor_items.keys():
		if str(did) == ignore_id or is_wall_strip(decor_items[did]):
			continue
		var d: Dictionary = decor_items[did]
		var dpos: Vector3 = d.get("pos", Vector3.ZERO)
		var gap := 0.24 if is_strip_type(str(d.get("item_type", ""))) else 0.62
		if Vector2(dpos.x - pos.x, dpos.z - pos.z).length() < gap:
			return false
	return true


func can_place_heat_pump_at(pos: Vector3) -> bool:
	if pos.x < HEAT_PUMP_LAWN_MIN.x or pos.x > HEAT_PUMP_LAWN_MAX.x:
		return false
	if pos.z < HEAT_PUMP_LAWN_MIN.y or pos.z > HEAT_PUMP_LAWN_MAX.y:
		return false
	if Vector2(pos.x, pos.z).distance_to(HEAT_PUMP_TREE_POS) < HEAT_PUMP_TREE_CLEARANCE:
		return false
	for cid in coolers.keys():
		var c: Dictionary = coolers[cid]
		if str(c.get("cooler_type", "cooler")) == INDOOR_UNIT_TYPE:
			continue
		var cpos: Vector3 = c["pos"]
		if Vector2(cpos.x - pos.x, cpos.z - pos.z).length() < HEAT_PUMP_SPACING:
			return false
	return true


func _interior_max_x() -> float:
	# Innenseite der jeweils letzten geschlossenen Trennwand bzw. der Ostwand
	return 5.39 if room_level == 0 else (12.39 if room_level == 1 else WALL_FACE_EAST_X)


func _snap_half(v: float) -> float:
	return roundf(v * 2.0) * 0.5


## Rechnet einen Treffer auf einer Innenwand in eine Montageposition um.
## Ein leeres Dictionary bedeutet: keine gültige Wand an dieser Stelle.
func get_wall_mount_spot(hit_pos: Vector3, normal: Vector3) -> Dictionary:
	if absf(normal.y) > 0.3:
		return {}
	var pos := Vector3.ZERO
	var rot_y := 0.0
	if absf(normal.z) >= absf(normal.x):
		if normal.z > 0.0:
			if absf(hit_pos.z - WALL_FACE_NORTH_Z) > WALL_HIT_TOLERANCE:
				return {}
			pos = Vector3(_snap_half(hit_pos.x), WALL_UNIT_Y, WALL_FACE_NORTH_Z + WALL_UNIT_OFFSET)
			rot_y = 0.0
		else:
			if absf(hit_pos.z - WALL_FACE_SOUTH_Z) > WALL_HIT_TOLERANCE:
				return {}
			pos = Vector3(_snap_half(hit_pos.x), WALL_UNIT_Y, WALL_FACE_SOUTH_Z - WALL_UNIT_OFFSET)
			rot_y = PI
	else:
		if normal.x > 0.0:
			if absf(hit_pos.x - WALL_FACE_WEST_X) > WALL_HIT_TOLERANCE:
				return {}
			pos = Vector3(WALL_FACE_WEST_X + WALL_UNIT_OFFSET, WALL_UNIT_Y, _snap_half(hit_pos.z))
			rot_y = PI * 0.5
		else:
			if absf(hit_pos.x - WALL_FACE_EAST_X) > WALL_HIT_TOLERANCE:
				return {}
			pos = Vector3(WALL_FACE_EAST_X - WALL_UNIT_OFFSET, WALL_UNIT_Y, _snap_half(hit_pos.z))
			rot_y = -PI * 0.5
	if not can_place_wall_unit_at(pos, rot_y):
		return {}
	return {"pos": pos, "rot_y": rot_y}


func can_place_wall_unit_at(pos: Vector3, rot_y: float) -> bool:
	if absf(pos.y - WALL_UNIT_Y) > 0.02:
		return false
	var facing := Vector3(sin(rot_y), 0.0, cos(rot_y))
	var margin := WALL_UNIT_HALF_WIDTH + 0.08
	if facing.z > 0.9 or facing.z < -0.9:
		var face_z := WALL_FACE_NORTH_Z + WALL_UNIT_OFFSET if facing.z > 0.0 else WALL_FACE_SOUTH_Z - WALL_UNIT_OFFSET
		if absf(pos.z - face_z) > 0.02:
			return false
		if pos.x < WALL_FACE_WEST_X + margin or pos.x > _interior_max_x() - margin:
			return false
		# Über der offenen Garagentor-Öffnung gibt es keine Wand
		if facing.z < 0.0 and absf(pos.x) < GARAGE_DOOR_HALF_WIDTH + margin:
			return false
	elif facing.x > 0.9 or facing.x < -0.9:
		if facing.x < 0.0 and room_level < 2:
			return false
		var face_x := WALL_FACE_WEST_X + WALL_UNIT_OFFSET if facing.x > 0.0 else WALL_FACE_EAST_X - WALL_UNIT_OFFSET
		if absf(pos.x - face_x) > 0.02:
			return false
		if pos.z < WALL_FACE_NORTH_Z + margin or pos.z > WALL_FACE_SOUTH_Z - margin:
			return false
	else:
		return false
	for cid in coolers.keys():
		var c: Dictionary = coolers[cid]
		if str(c.get("cooler_type", "cooler")) != INDOOR_UNIT_TYPE:
			continue
		var cpos: Vector3 = c["pos"]
		if cpos.distance_to(pos) < WALL_UNIT_SPACING:
			return false
	return true


func can_place_at(pos: Vector3, ignore_rack_id: String = "") -> bool:
	if halle_nord_owned and pos.z < -100.0:
		var lz := pos.z - HALLE_NORD_ORIGIN.z
		if pos.x < -9.3 or pos.x > 9.3 or lz < -5.2 or lz > 5.2:
			return false
		# Verglaster NOC-Leitstand, Schaltanlage/Core-Rack, Shuttle-Kiosk & Rolltor freihalten
		if lz < -2.3 and pos.x > 4.3:
			return false
		if lz < -4.5 and pos.x < -3.7:
			return false
		if lz < -4.3 and absf(pos.x - 3.2) < 0.9:
			return false
		if lz > 4.0 and absf(pos.x) < 2.3:
			return false
	else:
		var max_x := 4.8 if room_level == 0 else (11.7 if room_level == 1 else 20.6)
		if pos.x < -4.8 or pos.x > max_x:
			return false
		if pos.z < -3.7 or pos.z > 3.7:
			return false
		# Keep desk & North Wall walkway clear
		if pos.z < -2.9 and pos.x > 1.5 and pos.x < 5.0:
			return false
		# Keep Hall C subpanel walkway clear
		if pos.z < -3.0 and pos.x > 13.5 and pos.x < 17.5:
			return false
		# Keep garage doorway clear
		if pos.z > 2.6 and absf(pos.x) < 2.2:
			return false
	for rid in racks.keys():
		if rid == ignore_rack_id:
			continue
		var rpos: Vector3 = racks[rid]["pos"]
		if Vector2(rpos.x - pos.x, rpos.z - pos.z).length() < 1.05:
			return false
	for cid in coolers.keys():
		var cpos: Vector3 = coolers[cid]["pos"]
		if Vector2(cpos.x - pos.x, cpos.z - pos.z).length() < 0.95:
			return false
	for uid in ups_units.keys():
		var upos: Vector3 = ups_units[uid]["pos"]
		if Vector2(upos.x - pos.x, upos.z - pos.z).length() < 0.95:
			return false
	return true


func get_active_contract_count() -> int:
	var n := 0
	for cid in contracts.keys():
		if bool(contracts[cid]["active"]):
			n += 1
	return n


## Reihenfolge für die Anzeige: feste Vorlagen zuerst, danach befristete Angebote.
func get_contract_display_order() -> Array[String]:
	var order: Array[String] = []
	for tmpl in CONTRACTS_TEMPLATE:
		var tmpl_dict: Dictionary = tmpl
		var cid := str(tmpl_dict["id"])
		if contracts.has(cid):
			order.append(cid)
	var extra: Array[String] = []
	for key in contracts.keys():
		var cid := str(key)
		if not order.has(cid):
			extra.append(cid)
	extra.sort()
	order.append_array(extra)
	return order


## Erzeugt ein befristetes Angebot, abgeleitet von einer Vorlage, die zum aktuellen Ausbau passt.
func _make_random_contract() -> Dictionary:
	var ram_cap := maxi(int(total_ram_gb), 4) * RANDOM_CONTRACT_RAM_REACH
	var bases: Array[Dictionary] = []
	for tmpl in CONTRACTS_TEMPLATE:
		var tmpl_dict: Dictionary = tmpl
		if int(tmpl_dict["req_ram_gb"]) <= ram_cap:
			bases.append(tmpl_dict)
	if bases.is_empty():
		var first: Dictionary = CONTRACTS_TEMPLATE[0]
		bases.append(first)
	var base: Dictionary = bases[randi() % bases.size()]
	var scale := randf_range(RANDOM_CONTRACT_SCALE_MIN, RANDOM_CONTRACT_SCALE_MAX)
	var premium := randf_range(RANDOM_CONTRACT_PREMIUM_MIN, RANDOM_CONTRACT_PREMIUM_MAX)
	var cid := ""
	while cid == "" or contracts.has(cid):
		cid = "r_%d_%d" % [day_number, randi() % 100000]
	return {
		"id": cid,
		"title": str(RANDOM_CONTRACT_TITLES[randi() % RANDOM_CONTRACT_TITLES.size()]),
		"client": str(RANDOM_CONTRACT_CLIENTS[randi() % RANDOM_CONTRACT_CLIENTS.size()]),
		"required_compute": maxi(1, int(roundf(float(base["required_compute"]) * scale))),
		"req_ram_gb": maxi(2, int(roundf(float(base["req_ram_gb"]) * scale))),
		"req_mbps": snappedf(maxf(5.0, float(base["req_mbps"]) * scale), 0.5),
		"payout_per_cycle": maxi(1, int(roundf(float(base["payout_per_cycle"]) * scale * premium))),
		"penalty_per_cycle": maxi(1, int(roundf(float(base["penalty_per_cycle"]) * scale * RANDOM_CONTRACT_PENALTY_MULT))),
		"random": true,
		"duration_days": randi_range(RANDOM_CONTRACT_DURATION_MIN, RANDOM_CONTRACT_DURATION_MAX),
		"days_left": 0,
		"offer_days_left": RANDOM_CONTRACT_OFFER_DAYS,
		"active": false,
		"status": "idle",
	}


## Füllt die offenen befristeten Angebote auf. Gibt die Zahl neuer Angebote zurück.
func _fill_random_contract_offers() -> int:
	var offers := 0
	for key in contracts.keys():
		var c: Dictionary = contracts[key]
		if bool(c.get("random", false)) and not bool(c.get("active", false)):
			offers += 1
	var added := 0
	while offers < RANDOM_CONTRACT_MAX_OFFERS:
		var entry := _make_random_contract()
		contracts[str(entry["id"])] = entry
		offers += 1
		added += 1
	return added


## Tageswechsel: Laufzeiten und Annahmefristen herunterzählen, abgelaufene entfernen, neue Angebote erzeugen.
func _advance_random_contracts() -> void:
	for key in contracts.keys():
		var c: Dictionary = contracts[key]
		if not bool(c.get("random", false)):
			continue
		if bool(c.get("active", false)):
			c["days_left"] = int(c.get("days_left", 0)) - 1
			if int(c["days_left"]) <= 0:
				contracts.erase(key)
				post_event_f("✅ Befristeter Vertrag '%s' (%s) ist erfüllt und ausgelaufen.", [str(c["title"]), str(c["client"])], "good")
		else:
			c["offer_days_left"] = int(c.get("offer_days_left", 1)) - 1
			if int(c["offer_days_left"]) <= 0:
				contracts.erase(key)
	if _fill_random_contract_offers() > 0:
		post_event("📄 Neue befristete Vertragsangebote im Support-Hub.", "info")


func _catalog_price(item_id: String) -> float:
	var item: Dictionary = ITEM_CATALOG.get(item_id, {})
	return float(item.get("price", 0))


## Firmenwert: Bargeld + Restwert der Hardware + bezahlte Ausbauten.
func get_company_value() -> int:
	var hardware := 0.0
	for rid in racks.keys():
		var r: Dictionary = racks[rid]
		hardware += _catalog_price(str(r.get("rack_type", "rack")))
		var slots: Array = r.get("slots", [])
		for slot_v in slots:
			if not (slot_v is Dictionary):
				continue
			var slot: Dictionary = slot_v
			var item_type := str(slot.get("item_type", ""))
			if item_type == "":
				continue
			hardware += _catalog_price(item_type)
			var comps_v: Variant = slot.get("components", {})
			if not (comps_v is Dictionary):
				continue
			var comps: Dictionary = comps_v
			for cat in comps.keys():
				var pid := str(comps[cat])
				# Serienteile sind im Gerätepreis enthalten, nur Nachrüstungen zählen extra.
				if HardwareCatalog.is_stock_default_part(pid):
					continue
				var pd := HardwareCatalog.get_part(str(cat), pid)
				hardware += float(pd.get("cost", 0))
	for cid in coolers.keys():
		var cooler: Dictionary = coolers[cid]
		hardware += _catalog_price(str(cooler.get("cooler_type", "cooler")))
	for uu in ups_units.values():
		hardware += _catalog_price(get_ups_type(uu))

	var upgrades := 0.0
	for i in range(1, clampi(power_tier, 0, POWER_TIERS.size() - 1) + 1):
		upgrades += float(POWER_TIERS[i]["cost"])
	for i in range(1, clampi(router_tier, 0, ROUTER_TIERS.size() - 1) + 1):
		upgrades += float(ROUTER_TIERS[i]["cost"])
	for i in range(1, clampi(ai_platform_level, 0, AI_TIERS.size() - 1) + 1):
		upgrades += float(AI_TIERS[i]["cost"])
	for branch in research_levels.keys():
		if not RESEARCH_TREE.has(branch):
			continue
		var levels: Array = RESEARCH_TREE[branch]["levels"]
		for i in range(clampi(int(research_levels[branch]), 0, levels.size())):
			upgrades += float(levels[i]["cost"])
	if room_level >= 1:
		upgrades += float(HALL_B_COST)
	if room_level >= 2:
		upgrades += float(HALL_C_COST)

	return int(roundf(money + hardware * COMPANY_HARDWARE_VALUE_FACTOR + upgrades))


func _count_company_milestones(value: int) -> int:
	var n := 0
	for m_v in COMPANY_VALUE_MILESTONES:
		var m: Dictionary = m_v
		if value >= int(m["value"]):
			n += 1
	return n


## Nur auf dem Host: neu erreichte Meilensteine melden. Erreichte Meilensteine gehen nie verloren.
func _check_company_milestones() -> void:
	if not multiplayer.is_server():
		return
	var value := get_company_value()
	_update_company_level(value)
	var reached := _count_company_milestones(value)
	if company_milestones_reached < 0:
		company_milestones_reached = reached
		return
	while company_milestones_reached < reached:
		var m: Dictionary = COMPANY_VALUE_MILESTONES[company_milestones_reached]
		company_milestones_reached += 1
		if company_milestones_reached >= COMPANY_VALUE_MILESTONES.size():
			post_event_f("🏆 Endziel erreicht: %s! Firmenwert $%d.", [str(m["title"]), value], "good")
			_rpc_play_sfx.rpc("upgrade")
		else:
			post_event_f("🏅 Meilenstein erreicht: %s (Firmenwert über $%d).", [str(m["title"]), int(m["value"])], "good")


## Text für die Upgrades-App: aktueller Firmenwert und nächstes Ziel.
func get_company_goal_text() -> String:
	var value := get_company_value()
	var level_text := tr("Firmenstufe %d") % get_company_level()
	var idx := maxi(company_milestones_reached, 0)
	if idx >= COMPANY_VALUE_MILESTONES.size():
		return level_text + "  •  " + tr("Firmenwert: $%d  •  Endziel erreicht!") % value
	var m: Dictionary = COMPANY_VALUE_MILESTONES[idx]
	return level_text + "  •  " + tr("Firmenwert: $%d  •  Nächstes Ziel: $%d (%s)") % [value, int(m["value"]), tr(str(m["title"]))]


func _level_for_value(value: int) -> int:
	var lvl := 1
	for i in range(1, COMPANY_LEVEL_THRESHOLDS.size()):
		if value >= int(COMPANY_LEVEL_THRESHOLDS[i]):
			lvl = i + 1
	return lvl


## Nur auf dem Host: Firmenstufe anheben. Eine erreichte Stufe geht nie verloren.
func _update_company_level(value: int) -> void:
	var target := _level_for_value(value)
	if company_level <= 0:
		company_level = target
		return
	while company_level < target:
		company_level += 1
		var binfo: Dictionary = COMPANY_LEVEL_BENEFITS.get(company_level, {})
		post_event_f("⭐ FIRMENSTUFE %d ERREICHT! %s", [company_level, str(binfo.get("summary", "Neue Inhalte freigeschaltet!"))], "good")
		_rpc_play_sfx.rpc("upgrade")


func get_company_level() -> int:
	return clampi(company_level, 1, COMPANY_LEVEL_THRESHOLDS.size())


## Bauteile der Leistungsstufe vtier N brauchen Firmenstufe N + 1.
func get_part_required_level(pd: Dictionary) -> int:
	return clampi(int(pd.get("vtier", 0)) + 1, 1, 5)


func is_part_unlocked(pd: Dictionary) -> bool:
	return get_company_level() >= get_part_required_level(pd)


## Artikel mit 'unlock_level' und Mainboards werden nach Firmenstufe freigeschaltet.
func get_item_required_level(item_type: String) -> int:
	if not ITEM_CATALOG.has(item_type):
		return 1
	var item: Dictionary = ITEM_CATALOG[item_type]
	var req := int(item.get("unlock_level", 1))
	if bool(item.get("mainboard", false)):
		req = maxi(req, int(MAINBOARD_CATEGORY_LEVEL.get(str(item.get("mb_cat", "")), 1)))
	return req


func is_item_unlocked(item_type: String) -> bool:
	return get_company_level() >= get_item_required_level(item_type)


# ==============================================================================
# SIMULATION LOOP (HOST ONLY)
# ==============================================================================

func _run_simulation_step(dt: float) -> void:
	var prev_ups_backup := ups_backup_active
	_recalculate_networks_and_metrics()

	# 0. Day/Night Clock & kWh Meter (PV-Solaranlage spart 28 % laufenden Strom!)
	var kw_now := float(total_watts) / 1000.0
	if breaker_on:
		var pv_mult := 0.72 if has_building_upgrade("upg_pv_solar") else 1.0
		# Verbrauch in Spielstunden: ein Spieltag zählt 24 Stunden Last (realistische kWh pro Tag).
		daily_kwh += kw_now * pv_mult * (dt / DAY_LENGTH_SECONDS) * 24.0
	if _day_rollover_pending:
		_day_rollover_pending = false
		day_number += 1
		var bill := get_estimated_daily_bill()
		var billed_kwh := daily_kwh
		daily_kwh = 0.0
		last_daily_bill = bill
		last_bill_rate = electricity_rate
		electricity_rate = _roll_electricity_rate(electricity_rate)
		post_event_f("⚡ Strompreis für Tag %d: $%.2f pro kWh.", [day_number, electricity_rate], "info")
		_advance_random_contracts()
		_check_company_milestones()
		_generate_daily_deals()
		_roll_team_order()
		if bill > 0:
			# Die Stromrechnung wird nicht mehr sofort abgebucht. FinanceManager stellt daraus
			# eine Rechnung mit Fälligkeit aus, die in der Rechnungen-App bezahlt wird.
			_rpc_daily_bill.rpc(day_number, bill, billed_kwh)
			_rpc_play_sfx.rpc("bill")
			post_event_f("⚡ Tag %d Stromrechnung erhalten: $%d (%.1f kWh verbraucht).", [day_number - 1, bill, billed_kwh], "warn")
		else:
			post_event_f("☀ Tag %d beginnt – keine Stromkosten angefallen.", [day_number], "info")

	_tick_grid_outage(dt * (2.2 if weather_state == "storm" else 1.0))
	_tick_weather(dt)
	_tick_constructions(dt)
	_check_career_milestones()
	_tick_team_order(dt)

	# 1. UPS Charging & Emergency Backup Discharging
	var ups_dirty := false
	var connected_ups_ids: Array[String] = []
	var active_backup_ids: Array[String] = []
	var charge_sum := 0.0

	for uid in ups_units.keys():
		var u: Dictionary = ups_units[uid]
		if bool(u.get("connected", false)):
			connected_ups_ids.append(uid)
			if not breaker_on and is_ups_ready(u):
				active_backup_ids.append(uid)

	if breaker_on:
		_ups_over = 0.0
		for uid in ups_units.keys():
			ups_units[uid]["discharging"] = false
			if bool(ups_units[uid].get("tripped", false)):
				ups_units[uid]["tripped"] = false
				ups_dirty = true
		for uid in connected_ups_ids:
			var u: Dictionary = ups_units[uid]
			if float(u["charge"]) < 100.0:
				var add_wh := float(get_ups_spec(u)["charge_w"]) * 0.92 * dt / UPS_SECONDS_PER_HOUR
				u["charge"] = minf(100.0, float(u["charge"]) + add_wh / get_ups_capacity(u) * 100.0)
				ups_dirty = true
	else:
		if not active_backup_ids.is_empty():
			var total_out := get_ups_total_out()
			var need_wh := (float(total_watts) * 1.06 + 20.0 * float(active_backup_ids.size())) * dt / UPS_SECONDS_PER_HOUR
			for uid in active_backup_ids:
				var u: Dictionary = ups_units[uid]
				var spec := get_ups_spec(u)
				var wh := need_wh * float(spec["out"]) / maxf(1.0, total_out)
				u["discharging"] = true
				u["charge"] = maxf(0.0, float(u["charge"]) - wh / get_ups_capacity(u) * 100.0)
				u["health"] = maxf(UPS_MIN_HEALTH, get_ups_health(u) - wh / float(spec["cap"]) * UPS_WEAR_PER_CYCLE)
				ups_dirty = true
			# Mehr Last als die Geräte liefern können: nach 3 s schalten sie ab.
			if float(total_watts) > total_out * 1.05:
				_ups_over += dt
				if _ups_over >= 3.0:
					_ups_over = 0.0
					for uid in active_backup_ids:
						ups_units[uid]["tripped"] = true
						ups_units[uid]["discharging"] = false
					post_event_f("NOTSTROM ÜBERLASTET: %d W bei höchstens %d W. Die Geräte haben abgeschaltet.", [total_watts, int(total_out)], "alert")
					active_backup_ids.clear()
			else:
				_ups_over = maxf(0.0, _ups_over - dt)
		else:
			for uid in ups_units.keys():
				ups_units[uid]["discharging"] = false

	for uid in connected_ups_ids:
		charge_sum += float(ups_units[uid]["charge"])
	avg_ups_charge = charge_sum / float(connected_ups_ids.size()) if not connected_ups_ids.is_empty() else 0.0

	# Check if UPS just ran dry during a blackout
	if prev_ups_backup and not breaker_on and active_backup_ids.is_empty():
		_recalculate_networks_and_metrics()
		_rpc_play_sfx.rpc("power_down")
		if grid_outage_left > 0.0:
			post_event("USV-BATTERIEN LEER! Der Netzausfall dauert an. Alles steht, bis die Stadtwerke das Netz wiederherstellen.", "alert")
		else:
			post_event("USV-BATTERIEN LEER! Vollständiger Blackout – Hauptsicherung einschalten!", "alert")
		ups_dirty = true

	if ups_dirty:
		_broadcast_ups()

	_tick_strips(dt)

	# 2. Power Overload check (only trips when breaker is ON)
	if breaker_on and total_watts > max_watts:
		overload_timer += dt
		if overload_timer >= 3.0:
			breaker_on = false
			overload_timer = 0.0
			_blow_random_fuse()
			_recalculate_networks_and_metrics()
			_rpc_play_sfx.rpc("breaker_trip")
			if has_working_fuse():
				post_event("Überlast! Eine Sicherung ist durchgebrannt und der Hauptschalter hat ausgelöst. Hauptschalter wieder einschalten und Ersatz am PC kaufen.", "warn")
			else:
				post_event("Überlast! Die letzte intakte Sicherung ist durchgebrannt. Neue Sicherung am PC kaufen und im Sicherungskasten einsetzen.", "warn")
			if ups_backup_active:
				post_event("ÜBERLAST! Sicherung rausgeflogen – 🔋 USV-NOTSTROM hat übernommen!", "warn")
				_rpc_play_sfx.rpc("ups_beep")
			else:
				post_event_f("BLACKOUT! Sicherung bei %dW / %dW rausgeflogen! Am Sicherungskasten einschalten.", [total_watts, max_watts], "alert")
				_rpc_play_sfx.rpc("power_down")
	else:
		overload_timer = maxf(0.0, overload_timer - dt * 1.5)

	# 3. Room & Rack Temperature + Cooling
	var total_heat_gen := 0.0
	var total_cooling := 0.0
	# Ladende und speisende Batterien geben Wärme ab
	for uid in ups_units.keys():
		var uh: Dictionary = ups_units[uid]
		if bool(uh.get("discharging", false)) or (breaker_on and bool(uh.get("connected", false)) and float(uh["charge"]) < 99.5):
			total_heat_gen += float(get_ups_spec(uh)["heat"])

	for rid in racks.keys():
		var rack: Dictionary = racks[rid]
		var rtype := str(rack.get("rack_type", "rack"))
		var rack_passive_cool := float(ITEM_CATALOG.get(rtype, {}).get("passive_cooling", 0.0))
		var rack_heat := 0.0
		var active_modules := 0
		for slot in rack["slots"]:
			var sd: Dictionary = slot
			var item_type := str(sd["item_type"])
			if item_type == "":
				continue
			if str(sd["state"]) == "burning":
				rack_heat += 18.0
			elif bool(rack["powered"]) and is_slot_on(sd):
				var stats := get_slot_stats(sd)
				rack_heat += float(stats["heat"])
				active_modules += 1
		var effective_rack_heat := maxf(0.0, rack_heat - rack_passive_cool)
		total_heat_gen += effective_rack_heat
		var local_hot_spot := float(maxi(0, active_modules - 1)) * 2.2 - rack_passive_cool * 0.6 - _get_floor_cooler_relief(rack["pos"])
		var target_rack_temp := clampf(room_temp + local_hot_spot + (14.0 if _rack_has_fire(rack) else 0.0), 16.0, 105.0)
		rack["temp"] = move_toward(float(rack["temp"]), target_rack_temp, dt * 3.0)

	var heat_pump_capacity := 0.0
	var indoor_units := 0
	for cid in coolers.keys():
		var cooler: Dictionary = coolers[cid]
		var ctype := str(cooler.get("cooler_type", "cooler"))
		if ctype == INDOOR_UNIT_TYPE:
			indoor_units += 1
		elif is_floor_cooler_type(ctype):
			# Reihenkühler und Flüssigkühlung wirken direkt, ohne Innengerät.
			if bool(cooler["powered"]):
				total_cooling += absf(float(ITEM_CATALOG[ctype]["heat"])) * (1.0 + airflow_bonus)
		elif bool(cooler["powered"]):
			heat_pump_capacity += absf(float(ITEM_CATALOG[ctype]["heat"]))
	# Die Kälte der Außengeräte kommt nur über ein Goldis Innengerät in den Raum.
	# Kaltgang/Warmgang-Airflow steigert die reale Kühlleistung um bis zu +30 %!
	if indoor_units > 0:
		var extra_cool_bonus := 0.22 if has_building_upgrade("upg_cold_aisle_pro") else 0.0
		var gate_count := 0
		for did in decor_items.keys():
			if str((decor_items[did] as Dictionary).get("item_type", "")) == "prop_cold_aisle_gate":
				gate_count += 1
		extra_cool_bonus += minf(0.18, float(gate_count) * 0.06)
		total_cooling += heat_pump_capacity * (1.0 + airflow_bonus + extra_cool_bonus)

	# Slight natural night cooling (-3°C at night) + dynamisches Wetter + Dach-Rückkühlwerk (-4.5°C)!
	var night_bonus := -3.0 if (time_of_day < 0.22 or time_of_day > 0.80) else 0.0
	var chiller_farm_bonus := -4.5 if has_building_upgrade("upg_roof_chillers") else 0.0
	var weather_temp_delta := 8.5 if weather_state == "heatwave" else (-2.5 if (weather_state == "rain" or weather_state == "storm") else 0.0)
	var target_room := clampf(22.0 + night_bonus + chiller_farm_bonus + weather_temp_delta + total_heat_gen - total_cooling, 15.0, 96.0)
	room_temp = move_toward(room_temp, target_room, dt * 2.0)

	# 4. Hardware Faults & Fires — DRASTISCH seltener (~80 % weniger Ausfälle!) + Staub/Wartungs-Simulation!
	var racks_dirty := false
	for rid in racks.keys():
		var rack: Dictionary = racks[rid]
		var rtemp := float(rack["temp"])
		var slots: Array = rack["slots"]
		for i in range(slots.size()):
			var slot: Dictionary = slots[i]
			var item_type := str(slot["item_type"])
			if item_type == "":
				continue
			var st := str(slot["state"])
			if st == "burning":
				money = maxf(0.0, money - 3.0 * dt)
			elif is_slot_on(slot) and bool(rack["powered"]):
				# Staub sammelt sich sehr langsam an; vorbeugende Wartung drückt Ausfallrisiko auf nahezu 0 %!
				var dust := clampf(float(slot.get("dust_level", 0.0)) + dt * 0.048, 0.0, 100.0)
				var th_hp := clampf(float(slot.get("thermal_health", 100.0)) - dt * 0.022 * (1.0 + 1.5 * get_slot_sloppiness(slot)), 0.0, 100.0)
				slot["dust_level"] = dust
				slot["thermal_health"] = th_hp

				var stats := get_slot_stats(slot)
				var fmult := float(stats["fault_mult"])
				# Wartungs-Faktor: sauber gewartete Server (< 20 % Staub & > 75 % Paste) fallen fast nie aus!
				var maint_risk := 0.14 if (dust < 20.0 and th_hp > 75.0) else (0.55 if dust < 55.0 else (1.15 + (dust - 55.0) * 0.015))
				var eff_temp := rtemp + (dust * 0.05) + ((100.0 - th_hp) * 0.03)

				if eff_temp >= 82.0 and randf() < 0.008 * fmult:
					slot["state"] = "burning"
					slot["fire_level"] = 1.0
					racks_dirty = true
					post_event_f("BRAND in %s (Slot %d)! Feuerlöscher von der Wand holen!", [get_rack_display_name(rid), i + 1], "alert")
					_rpc_play_sfx.rpc("alarm")
				elif eff_temp >= 70.0 and randf() < 0.0032 * fmult:
					slot["state"] = "crashed"
					slot["repair_progress"] = 0.0
					slot["faulty_part"] = "cooling" if dust >= 45.0 else "cpu"
					slot["diagnosed"] = false
					slot["fault_hidden"] = randf() < FAULT_HIDDEN_CHANCE
					racks_dirty = true
					post_event_f("Überhitzung: %s Slot %d abgestürzt! Diagnose & Reparatur im Rack-Menü nötig.", [get_rack_display_name(rid), i + 1], "warn")
					_rpc_play_sfx.rpc("alarm")
				elif bool(rack["networked"]) and randf() < 0.00022 * fmult * maint_risk:
					slot["state"] = "crashed"
					slot["repair_progress"] = 0.0
					slot["faulty_part"] = _pick_faulty_part(slot)
					slot["diagnosed"] = false
					slot["fault_hidden"] = randf() < FAULT_HIDDEN_CHANCE
					racks_dirty = true
					if str(slot["faulty_part"]) != "":
						post_event_f("Hardware-Störung in %s Slot %d — Diagnose im Rack-Menü starten.", [get_rack_display_name(rid), i + 1], "warn")
					else:
						post_event_f("Hardware-Störung in %s Slot %d — Wartung [E] nötig.", [get_rack_display_name(rid), i + 1], "warn")
					_rpc_play_sfx.rpc("error")

	if racks_dirty:
		_recalculate_networks_and_metrics()
		_broadcast_racks()

	# 5. DDoS Random Events
	var has_power := breaker_on or ups_backup_active
	if (ai_platform_level > 0 or get_active_contract_count() >= 2) and total_compute >= 20 and has_power:
		if not ddos_active:
			ddos_cooldown -= dt
			if ddos_cooldown <= 0.0:
				ddos_active = true
				var dmult := float(ROUTER_TIERS[clampi(router_tier, 0, ROUTER_TIERS.size() - 1)]["ddos_mult"])
				ddos_cooldown = randf_range(65.0, 105.0) * dmult
				post_event("DDOS-ANGRIFF ERKANNT! Am Wand-Router [E] oder am PC abwehren!", "alert")
				_rpc_play_sfx.rpc("alarm")

	# 5a. Wasserschaden: Ein Leck legt einzelne Server eines Racks lahm.
	if has_power and get_active_contract_count() >= 1:
		water_leak_cooldown -= dt
		if water_leak_cooldown <= 0.0:
			water_leak_cooldown = randf_range(WATER_LEAK_MIN_S, WATER_LEAK_MAX_S)
			_trigger_water_leak()

	# 5b. Rack Rentals, Active Users, Resource Load & Support Tickets/Calls
	_update_rack_rentals_and_support(dt)

	# 6. AI Platform Passive Revenue
	if ai_platform_level > 0 and has_power and not ddos_active:
		var free_c := get_free_compute()
		var tier_rate := float(AI_TIERS[ai_platform_level]["rate"])
		if free_c > 0:
			ai_revenue_per_sec = float(free_c) * tier_rate * 0.16 * revenue_bonus_mult
			money += ai_revenue_per_sec * dt
		else:
			ai_revenue_per_sec = 0.0
	else:
		ai_revenue_per_sec = 0.0

	# 7. Contract Payout Cycle
	next_payout_in -= dt
	if next_payout_in <= 0.0:
		next_payout_in = PAYOUT_CYCLE_SECONDS
		_process_contract_payouts()

	_broadcast_sim_tick()


## Laufende Standgeräte senken den Wärmestau naher Racks (stärkstes Gerät zählt).
func _get_floor_cooler_relief(pos: Vector3) -> float:
	var best := 0.0
	for cid in coolers.keys():
		var c: Dictionary = coolers[cid]
		var ctype := str(c.get("cooler_type", ""))
		if not is_floor_cooler_type(ctype) or not bool(c.get("powered", false)):
			continue
		var cat: Dictionary = ITEM_CATALOG[ctype]
		var cpos: Vector3 = c["pos"]
		if Vector2(cpos.x - pos.x, cpos.z - pos.z).length() <= float(cat.get("relief_radius", 2.5)):
			best = maxf(best, float(cat.get("relief", 4.0)))
	return best


func _rack_has_fire(rack: Dictionary) -> bool:
	for slot in rack["slots"]:
		if str(slot["state"]) == "burning":
			return true
	return false


func _process_contract_payouts() -> void:
	var avail_ram := 0 if ddos_active else total_ram_gb
	var avail_mbps := 0.0 if ddos_active else max_bandwidth_mbps
	var net_delta := 0.0
	var had_sla_breach := false

	for cid in contracts.keys():
		var c: Dictionary = contracts[cid]
		if not bool(c["active"]):
			c["status"] = "idle"
			continue
		var req_ram := int(c.get("req_ram_gb", 4))
		var req_mbps := float(c.get("req_mbps", 15.0))
		if avail_ram >= req_ram and avail_mbps >= req_mbps:
			avail_ram -= req_ram
			avail_mbps -= req_mbps
			c["status"] = "ok"
			net_delta += float(c["payout_per_cycle"]) * revenue_bonus_mult
		else:
			c["status"] = "underpowered"
			net_delta -= float(c["penalty_per_cycle"])
			had_sla_breach = true

	# Add Rented Rack customer payouts (scaled by live active users & satisfaction!)
	var rental_payout := 0.0
	if not ddos_active:
		for rid in racks.keys():
			var rk: Dictionary = racks[rid]
			if str(rk.get("rental_type", "none")) != "none" and bool(rk.get("powered", false)) and bool(rk.get("networked", false)):
				rental_payout += float(rk.get("rental_income", 0.0))
	net_delta += rental_payout

	money = maxf(0.0, money + net_delta)
	if had_sla_breach:
		post_event("SLA-Strafe! Zu wenig aktiver RAM (GB) oder Internet-Bandbreite (Mbit/s) für laufende Verträge.", "warn")


func _update_rack_rentals_and_support(dt: float) -> void:
	var tickets_dirty := false
	var call_dirty := false
	var total_rent := 0.0
	var time_wave := 0.85 + 0.30 * sin((time_of_day - 0.25) * TAU)

	# Manage incoming phone call ringing & timeout
	_call_cooldown = maxf(0.0, _call_cooldown - dt)
	if not active_call.is_empty():
		active_call["timer"] = float(active_call.get("timer", 0.0)) + dt
		if str(active_call.get("state", "ringing")) == "ringing":
			_phone_ring_accum += dt
			if _phone_ring_accum >= 4.2:
				_phone_ring_accum = 0.0
				_rpc_play_sfx.rpc("phone_ring")
			if float(active_call["timer"]) >= 42.0:
				var crid := str(active_call.get("rack_id", ""))
				if racks.has(crid):
					racks[crid]["satisfaction"] = maxf(5.0, float(racks[crid].get("satisfaction", 60.0)) - 12.0)
				post_event_f("📞 Verpasster Kundenanruf von %s! Zufriedenheit gesunken.", [str(active_call.get("customer", "Kunde"))], "warn")
				active_call.clear()
				_call_cooldown = 30.0
				call_dirty = true
		call_dirty = true

	var worst_call_rack := ""
	var worst_call_issue := ""
	var worst_call_sat := 999.0
	var rep_delta := 0.0
	# Freie Hardware der Cluster-Racks, einmal pro Tick ermittelt und beim Verleihen verbraucht.
	var cluster_spare := _compute_cluster_spare()

	for rid in racks.keys():
		var r: Dictionary = racks[rid]
		var services := _get_rack_services(r)
		if services.is_empty():
			r["rental_type"] = "none"
			r["rental_customer"] = ""
			r["active_users"] = 0
			r["rental_income"] = 0.0
			r["metrics"] = {}
			continue

		var rtype := str((services[0] as Dictionary)["type"])
		var prof: Dictionary = HardwareCatalog.RENTAL_PROFILES[rtype]
		var hw := get_rack_hardware_summary(rid)
		var powered := bool(r.get("powered", false))
		var networked := bool(r.get("networked", false))
		var active_servers := int(hw["active_servers"])
		var rtemp := float(r.get("temp", 22.0))
		var sat := float(r.get("satisfaction", 100.0))
		var grace := maxf(0.0, float(r.get("grace_timer", 0.0)) - dt)
		r["grace_timer"] = grace

		# Kunden kommen nach und nach: Jeder Dienst startet mit wenigen Nutzern und wächst je nach Ruf.
		var online := powered and networked and active_servers > 0
		# Auslastung aus dem letzten Tick bremst das Wachstum, bevor die Hardware an ihre Grenze kommt.
		var prev_m: Dictionary = r["metrics"] if r.get("metrics") is Dictionary else {}
		var prev_load := maxf(
			maxf(float(prev_m.get("ram_pct", 0.0)), float(prev_m.get("cpu_pct", 0.0))),
			maxf(maxf(float(prev_m.get("gpu_pct", 0.0)), float(prev_m.get("storage_pct", 0.0))), float(prev_m.get("net_pct", 0.0)))
		)
		var users_int := 0
		for svc in services:
			users_int += _update_service_users(svc as Dictionary, sat, online, dt, time_wave, prev_load)
		users_int = maxi(1, users_int)
		_sync_rack_rental_fields(r)
		r["active_users"] = users_int
		# Ressourcenbedarf und Preis pro Nutzer: Mittel aller Dienste, gewichtet nach Nutzerzahl.
		prof = _blend_service_profiles(services)

		# Cluster-Kabel: Reicht die eigene Hardware nicht, leiht sich das Rack freie Kapazität der verbundenen Racks.
		var cluster_borrowed: Dictionary = {}
		if active_servers > 0:
			hw = hw.duplicate()
			cluster_borrowed = _borrow_cluster_capacity(str(rid), hw, users_int, prof, cluster_spare)

		# Calculate live per-resource utilization % so player can self-assess RAM/CPU/GPU/Storage/Router!
		var ram_total := maxf(0.5, float(hw["ram_gb"]))
		var ram_used := float(users_int) * float(prof["ram_gb_per_user"])
		var ram_pct := (ram_used / ram_total) * 100.0 if active_servers > 0 else 100.0

		var cpu_total := maxf(1.0, float(hw["cpu_score"]))
		var cpu_used := float(users_int) * float(prof["cpu_per_user"])
		var cpu_pct := (cpu_used / cpu_total) * 100.0 if active_servers > 0 else 100.0

		var gpu_pct := 0.0
		if float(prof["gpu_per_user"]) > 0.001:
			var gpu_total := maxf(1.0, float(hw["gpu_score"]))
			gpu_pct = ((float(users_int) * float(prof["gpu_per_user"])) / gpu_total) * 100.0 if active_servers > 0 else 100.0

		var sto_total := maxf(0.1, float(hw["storage_tb"]))
		var sto_used := float(users_int) * float(prof["storage_tb_per_user"])
		var sto_pct := (sto_used / sto_total) * 100.0 if active_servers > 0 else 100.0

		var net_need_mbps := float(users_int) * float(prof.get("mbps_per_user", 0.5))
		var net_pct := (net_need_mbps / maxf(1.0, max_bandwidth_mbps)) * 100.0
		if used_bandwidth_mbps > max_bandwidth_mbps:
			net_pct = maxf(net_pct, (used_bandwidth_mbps / maxf(1.0, max_bandwidth_mbps)) * 100.0)

		var bottleneck := "ok"
		var peak_load := maxf(maxf(ram_pct, cpu_pct), maxf(maxf(gpu_pct, sto_pct), net_pct))
		if not powered or not networked or active_servers == 0:
			bottleneck = "offline"
		elif _rack_has_fire(r):
			bottleneck = "overheat"
		elif bool(hw["psu_overloaded"]):
			bottleneck = "psu"
		elif rtemp >= 74.0:
			bottleneck = "overheat"
		elif peak_load >= 92.0:
			if ram_pct >= cpu_pct and ram_pct >= gpu_pct and ram_pct >= sto_pct and ram_pct >= net_pct:
				bottleneck = "ram"
			elif cpu_pct >= gpu_pct and cpu_pct >= sto_pct and cpu_pct >= net_pct:
				bottleneck = "cpu"
			elif gpu_pct >= sto_pct and gpu_pct >= net_pct:
				bottleneck = "gpu"
			elif sto_pct >= net_pct:
				bottleneck = "storage"
			else:
				bottleneck = "network"

		r["metrics"] = {
			"ram_used_gb": ram_used,
			"ram_total_gb": float(hw["ram_gb"]),
			"ram_pct": ram_pct,
			"cpu_pct": cpu_pct,
			"gpu_pct": gpu_pct,
			"storage_used_tb": sto_used,
			"storage_total_tb": float(hw["storage_tb"]),
			"storage_pct": sto_pct,
			"net_used_mbps": net_need_mbps,
			"net_pct": net_pct,
			"bottleneck": bottleneck,
			"cluster_borrowed": cluster_borrowed,
		}

		# Satisfaction dynamics
		if bottleneck == "ok" and not ddos_active:
			sat = minf(100.0, sat + 1.4 * dt)
		elif grace <= 0.0:
			var penalty_rate := 2.4 if bottleneck == "offline" else (1.9 if peak_load >= 115.0 else 1.15)
			sat = maxf(0.0, sat - penalty_rate * dt)
		r["satisfaction"] = sat

		var income := 0.0
		if powered and networked and active_servers > 0 and not ddos_active:
			var sat_mult := clampf(sat / 100.0, 0.25, 1.15)
			income = float(users_int) * float(prof["pay_per_user"]) * sat_mult * revenue_bonus_mult
		r["rental_income"] = income
		total_rent += income
		# Zufriedene Kunden empfehlen dich weiter, unzufriedene schaden dem Ruf.
		rep_delta += (sat - 60.0) / 100.0 * 0.05 * dt * sqrt(float(services.size()))

		# Auto-generate specific Customer Support Ticket on persistent bottleneck!
		if bottleneck != "ok" and not _has_open_ticket_for_rack(rid):
			if bottleneck == "offline" or sat < 86.0 or peak_load >= 96.0:
				_create_support_ticket(rid, r, bottleneck)
				tickets_dirty = true

		# Track most critical rack for an incoming VoIP Phone Call at the PC!
		if bottleneck != "ok" and grace <= 0.0 and (sat < 68.0 or bottleneck == "offline" or peak_load >= 112.0):
			if sat < worst_call_sat:
				worst_call_sat = sat
				worst_call_rack = rid
				worst_call_issue = bottleneck

		# If customer satisfaction collapses completely, customer cancels rental!
		if sat <= 5.0:
			var cname := str(r.get("rental_customer", "Kunde"))
			r["rental_type"] = "none"
			r["rental_customer"] = ""
			r["active_users"] = 0
			r["satisfaction"] = 100.0
			r["rental_income"] = 0.0
			services.clear()
			reputation = maxf(0.0, reputation - 8.0)
			_clear_tickets_for_rack(rid)
			tickets_dirty = true
			post_event_f("❌ %s hat %s gekündigt (dauerhafte Überlastung)! Hardware aufrüsten & neu vermieten.", [cname, get_rack_display_name(rid)], "alert")
			_rpc_play_sfx.rpc("alarm")

	reputation = clampf(reputation + rep_delta, 0.0, 100.0)
	var rep_tier := get_reputation_tier()
	if rep_tier != _last_rep_tier:
		if _last_rep_tier >= 0:
			if rep_tier > _last_rep_tier:
				post_event_f("⭐ Dein Ruf steigt: %s! Neue Kunden kommen schneller und zahlreicher.", [get_reputation_label()], "good")
			else:
				post_event_f("📉 Dein Ruf sinkt: %s. Es kommen weniger neue Kunden.", [get_reputation_label()], "warn")
		_last_rep_tier = rep_tier

	total_rental_income_per_cycle = total_rent

	# Trigger Live Customer Phone Call at PC if a rack is critically impacted!
	if active_call.is_empty() and _call_cooldown <= 0.0 and worst_call_rack != "":
		var cr: Dictionary = racks[worst_call_rack]
		var cname := str(cr.get("rental_customer", "Kunde"))
		var rtype := str(cr.get("rental_type", "web"))
		var call_msg := _describe_issue_call(worst_call_rack, cr, worst_call_issue)
		active_call = {
			"id": "call_%d" % _next_ticket_num,
			"rack_id": worst_call_rack,
			"customer": cname,
			"rental_type": rtype,
			"issue_key": worst_call_issue,
			"message": str(call_msg["text"]),
			"message_args": call_msg["args"],
			"state": "ringing",
			"timer": 0.0,
		}
		_next_ticket_num += 1
		_phone_ring_accum = 0.0
		_rpc_play_sfx.rpc("phone_ring")
		post_event_f("📞 EINGEHENDER ANRUF AM PC: %s beschwert sich über %s! Zum PC [E] gehen!", [cname, worst_call_rack.to_upper()], "alert")
		call_dirty = true

	# Tickets altern lassen. Unbeantwortete Tickets eskalieren nach Ablauf der SLA-Frist.
	for tid in support_tickets.keys():
		var t: Dictionary = support_tickets[tid]
		t["age"] = float(t.get("age", 0.0)) + dt
		if bool(t.get("reassured", false)) or bool(t.get("escalated", false)):
			continue
		if float(t["age"]) < get_ticket_sla(t):
			continue
		t["escalated"] = true
		var erid := str(t.get("rack_id", ""))
		if racks.has(erid):
			racks[erid]["satisfaction"] = maxf(0.0, float(racks[erid].get("satisfaction", 60.0)) - TICKET_ESCALATION_SAT_PENALTY)
		reputation = maxf(0.0, reputation - TICKET_ESCALATION_REP_PENALTY)
		tickets_dirty = true
		_rpc_play_sfx.rpc("alarm")
		post_event_f("⏰ Ticket %s eskaliert: %s wartet zu lange auf eine Antwort (-%d%% Zufriedenheit).", [str(tid), str(t.get("customer", "Kunde")), int(TICKET_ESCALATION_SAT_PENALTY)], "alert")

	if tickets_dirty:
		_broadcast_tickets()
	if call_dirty:
		_broadcast_call()


## Aktive Dienste eines Racks. Ungültige Einträge (unbekannte Dienste, "none") werden entfernt.
func _get_rack_services(r: Dictionary) -> Array:
	if not (r.get("services") is Array):
		r["services"] = []
	var arr: Array = r["services"]
	for i in range(arr.size() - 1, -1, -1):
		var e: Variant = arr[i]
		if not (e is Dictionary):
			arr.remove_at(i)
			continue
		var t := str((e as Dictionary).get("type", ""))
		if t == "none" or not HardwareCatalog.RENTAL_PROFILES.has(t):
			arr.remove_at(i)
	return arr


func _find_service(services: Array, service_type: String) -> int:
	for i in range(services.size()):
		if str((services[i] as Dictionary).get("type", "")) == service_type:
			return i
	return -1


## Hält die alten Einzelfelder (rental_type, rental_customer) passend zur Dienstliste.
## Tickets, Anrufe, Terminal und Rack-Schild lesen weiter diese Felder.
func _sync_rack_rental_fields(r: Dictionary) -> void:
	var services: Array = r.get("services", [])
	if services.is_empty():
		r["rental_type"] = "none"
		r["rental_customer"] = ""
		r["active_users"] = 0
		r["rental_income"] = 0.0
		r["satisfaction"] = 100.0
		r["grace_timer"] = 0.0
		return
	var first: Dictionary = services[0]
	r["rental_type"] = str(first.get("type", "none"))
	var cname := str(first.get("customer", ""))
	if services.size() > 1:
		cname += " +%d" % (services.size() - 1)
	r["rental_customer"] = cname
	var total := 0
	for s in services:
		total += int(roundf(float((s as Dictionary).get("users", 0.0))))
	r["active_users"] = total


func get_reputation_factor() -> float:
	return clampf(reputation / 100.0, 0.0, 1.0)


func get_reputation_tier() -> int:
	var tier := 0
	for th in REPUTATION_THRESHOLDS:
		if reputation >= th:
			tier += 1
	return tier


func get_reputation_label() -> String:
	return REPUTATION_LABELS[get_reputation_tier()]


## Neue Kunden kommen nur, solange die Hardware des Racks noch Luft hat (höchste Auslastung in %).
const USER_GROWTH_LOAD_LIMIT := 85.0
## Bereich unter dem Limit, in dem das Wachstum weich ausläuft.
const USER_GROWTH_SOFT_RANGE := 25.0
## Ab dieser Auslastung wandern Kunden langsam ab, auch bei hoher Zufriedenheit.
const USER_SHED_LOAD_LIMIT := 100.0


## Startnutzer eines neuen Dienstes: bei schlechtem Ruf nur eine Handvoll.
func _start_users_for(service_type: String) -> float:
	var p: Dictionary = HardwareCatalog.RENTAL_PROFILES[service_type]
	return maxf(1.0, roundf(float(p.get("base_users", 1)) * (0.15 + 0.35 * get_reputation_factor())))


## Nutzerzahl eines Dienstes fortschreiben. Gibt die gerundete Nutzerzahl zurück.
func _update_service_users(svc: Dictionary, sat: float, online: bool, dt: float, time_wave: float, load_pct: float = 0.0) -> int:
	var st := str(svc.get("type", ""))
	if not HardwareCatalog.RENTAL_PROFILES.has(st):
		return 0
	var p: Dictionary = HardwareCatalog.RENTAL_PROFILES[st]
	var base := float(p.get("base_users", 1))
	var prev := float(svc.get("users", base))
	var cur := prev
	if not online:
		cur = maxf(base * 0.2, cur - 4.5 * dt)
	elif sat >= 72.0:
		if load_pct < USER_GROWTH_LOAD_LIMIT:
			var headroom := clampf((USER_GROWTH_LOAD_LIMIT - load_pct) / USER_GROWTH_SOFT_RANGE, 0.0, 1.0)
			var growth := float(p.get("growth_rate", 1.0)) * time_wave * (0.35 + 0.65 * get_reputation_factor())
			cur += growth * headroom * dt * 0.36
		elif load_pct >= USER_SHED_LOAD_LIMIT:
			# Hardware voll ausgelastet: ein Teil der Kunden wandert langsam ab.
			cur = maxf(base, cur - 1.0 * dt)
	elif sat < 45.0:
		cur = maxf(base * 0.25, cur - 2.2 * dt)
	svc["users"] = cur
	if dt > 0.0:
		var per_min := (cur - prev) / dt * 60.0
		svc["trend"] = lerpf(float(svc.get("trend", 0.0)), per_min, clampf(dt * 0.5, 0.0, 1.0))
	return maxi(0, int(roundf(cur)))


## Ein gemeinsames Profil für alle Dienste eines Racks, gewichtet nach Nutzerzahl.
func _blend_service_profiles(services: Array) -> Dictionary:
	var first_type := str((services[0] as Dictionary).get("type", ""))
	var out: Dictionary = (HardwareCatalog.RENTAL_PROFILES[first_type] as Dictionary).duplicate(true)
	if services.size() == 1:
		return out
	var sums := {}
	for k in _BLEND_KEYS:
		sums[k] = 0.0
	var total_w := 0.0
	var base_sum := 0.0
	var max_sum := 0.0
	var growth_sum := 0.0
	for s in services:
		var sd: Dictionary = s
		var p: Dictionary = HardwareCatalog.RENTAL_PROFILES[str(sd["type"])]
		var w := maxf(1.0, float(sd.get("users", 1.0)))
		total_w += w
		for k in _BLEND_KEYS:
			var fallback := 0.5 if k == "mbps_per_user" else 0.0
			sums[k] = float(sums[k]) + w * float(p.get(k, fallback))
		base_sum += float(p.get("base_users", 0))
		max_sum += float(p.get("max_users", 0))
		growth_sum += float(p.get("growth_rate", 0.0))
	for k in _BLEND_KEYS:
		out[k] = float(sums[k]) / total_w
	out["base_users"] = int(base_sum)
	out["max_users"] = int(max_sum)
	out["growth_rate"] = growth_sum
	return out


func _has_open_ticket_for_rack(rack_id: String) -> bool:
	for tid in support_tickets.keys():
		if str(support_tickets[tid].get("rack_id", "")) == rack_id:
			return true
	return false


func _clear_tickets_for_rack(rack_id: String) -> void:
	var del_ids: Array[String] = []
	for tid in support_tickets.keys():
		if str(support_tickets[tid].get("rack_id", "")) == rack_id:
			del_ids.append(str(tid))
	for tid in del_ids:
		support_tickets.erase(tid)


func _create_support_ticket(rack_id: String, rack: Dictionary, issue_key: String) -> void:
	var tid := "T-%d" % _next_ticket_num
	_next_ticket_num += 1
	var cname := str(rack.get("rental_customer", "Kunde"))
	var rtype := str(rack.get("rental_type", "web"))
	var users := int(rack.get("active_users", 0))
	var m: Dictionary = rack.get("metrics", {})
	var rid_up := get_rack_display_name(rack_id)
	# Titel und Text bleiben Vorlagen mit Werten. Übersetzt wird erst beim
	# Empfänger, damit jeder Spieler sie in seiner eigenen Sprache sieht.
	var title := ""
	var title_args: Array = []
	var msg := ""
	var msg_args: Array = []
	var prio := "HOCH"
	match issue_key:
		"ram":
			title = "Arbeitsspeicher (RAM) voll!"
			msg = "Hallo Support, bei unseren %d aktiven Nutzern läuft der RAM auf %s über (%.1f / %.0f GB)! Dienste stürzen ab — bitte mehr/schnelleren RAM (DDR3/DDR4/DDR5) einbauen!"
			msg_args = [users, rid_up, float(m.get("ram_used_gb", 0.0)), float(m.get("ram_total_gb", 0.0))]
		"cpu":
			title = "CPU-Auslastung bei %.0f%%!"
			title_args = [float(m.get("cpu_pct", 100.0))]
			msg = "Unsere %d aktiven User klagen über extreme Lags auf %s! Der Prozessor ist komplett am Limit — wir brauchen dringend stärkere CPUs oder einen weiteren Server!"
			msg_args = [users, rid_up]
		"gpu":
			title = "GPU-Leistung reicht nicht aus!"
			msg = "Bei %d aktiven Nutzern hängen unsere GPU-Jobs auf %s (%.0f%% Last). Bitte bessere Grafikkarten verbauen!"
			msg_args = [users, rid_up, float(m.get("gpu_pct", 100.0))]
		"storage":
			title = "Festplatten-Speicher fast voll!"
			msg = "Warnung: Unsere %d Nutzer belegen bereits %.1f / %.1f TB auf %s! Uploads schlagen fehl — bitte größere HDD/SSD/NVMe einbauen!"
			msg_args = [users, float(m.get("storage_used_tb", 0.0)), float(m.get("storage_total_tb", 0.0)), rid_up]
		"network":
			title = "Internet-Leitung zu langsam!"
			msg = "Hoher Ping & Paketverlust bei %d aktiven Usern! Dein Router drosselt %s — bitte Internet-Router upgraden!"
			msg_args = [users, rid_up]
		"overheat":
			prio = "KRITISCH"
			title = "Kritische Rack-Temperatur (%.0f°C)!"
			title_args = [float(rack.get("temp", 75.0))]
			msg = "Thermal Throttling auf %s! Bitte sofort Server-Kühlung verbessern oder Klimaanlage anschließen!"
			msg_args = [rid_up]
		"psu":
			prio = "KRITISCH"
			title = "Netzteil-Überlastung erkannt!"
			msg = "Spannungsabfälle auf %s — ein verbautes Netzteil ist zu schwach für die Komponenten! Bitte stärkeres Netzteil (PSU) einbauen."
			msg_args = [rid_up]
		_:
			prio = "KRITISCH"
			title = "Komplettausfall — Server offline!"
			msg = "NOTFALL: Unser gemietetes %s ist komplett unerreichbar! Bitte sofort Stromkabel, Netzwerkkabel & Server-Zustand prüfen!"
			msg_args = [rid_up]

	support_tickets[tid] = {
		"id": tid,
		"rack_id": rack_id,
		"customer": cname,
		"rental_type": rtype,
		"issue_key": issue_key,
		"title": title,
		"title_args": title_args,
		"message": msg,
		"message_args": msg_args,
		"priority": prio,
		"created_day": day_number,
		"age": 0.0,
		"reassured": false,
		"compensated": false,
		"escalated": false,
	}
	_rpc_play_sfx.rpc("ticket_notify")
	post_event_f("🎧 Neues Support-Ticket %s von %s: %s", [tid, cname, {"text": title, "args": title_args}], "warn")


## Antwortfrist eines Tickets in Sekunden (nach Priorität).
func get_ticket_sla(ticket: Dictionary) -> float:
	return float(TICKET_SLA_SECONDS.get(str(ticket.get("priority", "HOCH")), TICKET_DEFAULT_SLA))


## Restzeit bis zur Eskalation. 0 bei beantworteten oder bereits eskalierten Tickets.
func get_ticket_sla_remaining(ticket: Dictionary) -> float:
	if bool(ticket.get("reassured", false)) or bool(ticket.get("escalated", false)):
		return 0.0
	return maxf(0.0, get_ticket_sla(ticket) - float(ticket.get("age", 0.0)))


## Liefert den Anruftext als Vorlage plus Werte ({text, args}).
func _describe_issue_call(rack_id: String, rack: Dictionary, issue_key: String) -> Dictionary:
	var users := int(rack.get("active_users", 0))
	var m: Dictionary = rack.get("metrics", {})
	var who := str(rack.get("rental_customer", ""))
	var rid_up := get_rack_display_name(rack_id)
	match issue_key:
		"ram":
			return {"text": "„Hallo?! Hier ist %s! Bei %d aktiven Usern ist der RAM auf %s zu %.0f%% voll — unsere Kunden fliegen ständig raus! Wann baut ihr mehr RAM ein?“",
				"args": [who, users, rid_up, float(m.get("ram_pct", 100.0))]}
		"cpu":
			return {"text": "„Dringend! Hier %s — die CPU auf %s hängt bei %.0f%% Last mit %d Usern, alles laggt unerträglich! Macht bitte sofort ein CPU-Upgrade!“",
				"args": [who, rid_up, float(m.get("cpu_pct", 100.0)), users]}
		"gpu":
			return {"text": "„Hier %s! Unsere KI/Video-Aufträge auf %s stehen still, die GPU ist restlos überlastet (%.0f%%)! Wir brauchen dringend dickere Grafikkarten!“",
				"args": [who, rid_up, float(m.get("gpu_pct", 100.0))]}
		"storage":
			return {"text": "„Hallo Support, %s hier! Der Speicher auf %s ist komplett voll (%.1f / %.1f TB) — unsere Kunden können nichts mehr hochladen!“",
				"args": [who, rid_up, float(m.get("storage_used_tb", 0.0)), float(m.get("storage_total_tb", 0.0))]}
		"network":
			return {"text": "„%s am Apparat! Euer alter Router bremst unser ganzes %s aus — Ping über 400 ms bei %d Usern! Wann gibt's schnelleres Internet?“",
				"args": [who, rid_up, users]}
		"overheat":
			return {"text": "„ALARM! Hier %s — euer Monitoring meldet %.0f°C auf %s! Wenn die Server gleich abbrennen, kündigen wir sofort!“",
				"args": [who, float(rack.get("temp", 80.0)), rid_up]}
		"psu":
			return {"text": "„%s hier! Auf %s brechen ständig die Netzteile ein — bitte baut stärkere PSUs ein, bevor uns Daten verloren gehen!“",
				"args": [who, rid_up]}
		_:
			return {"text": "„NOTFALL! Hier ist %s — unser gemietetes %s ist KOMPLETT OFFLINE! Prüft sofort Strom, LAN-Kabel und Server!“",
				"args": [who, rid_up]}


func _recalculate_networks_and_metrics() -> void:
	if multiplayer.is_server():
		_refresh_slot_power()
	max_watts = int(POWER_TIERS[power_tier]["watts"])
	if halle_nord_owned:
		max_watts += HALLE_NORD_EXTRA_WATTS

	for rid in racks.keys():
		racks[rid]["powered"] = false
		racks[rid]["networked"] = false
		racks[rid]["clustered"] = count_cables_on("cluster", str(rid)) > 0
	for cid in coolers.keys():
		coolers[cid]["powered"] = false
	for uid in ups_units.keys():
		ups_units[uid]["connected"] = false

	# First discover which UPS units are wired into the main breaker power graph
	var bus_sources: Array[String] = [WALL_BREAKER_ID]
	if room_level >= 2:
		bus_sources.append(HALL_C_BREAKER_ID)
	if halle_nord_owned:
		bus_sources.append(HALL_NORD_BREAKER_ID)

	var bus_visited: Dictionary = {}
	var bus_queue: Array = []
	for src in bus_sources:
		bus_visited[src] = true
		bus_queue.append(src)

	while not bus_queue.is_empty():
		var curr := str(bus_queue.pop_front())
		for cab_id in cables.keys():
			var cab: Dictionary = cables[cab_id]
			if str(cab["cable_type"]) != "power":
				continue
			var other := ""
			if str(cab["from_id"]) == curr:
				other = str(cab["to_id"])
			elif str(cab["to_id"]) == curr:
				other = str(cab["from_id"])
			if other == "" or bus_visited.has(other):
				continue
			bus_visited[other] = true
			if ups_units.has(other):
				ups_units[other]["connected"] = true
				bus_queue.append(other)
			elif racks.has(other) or (is_power_strip_decor(other) and is_strip_on(other)):
				bus_queue.append(other)

	# Determine if UPS backup is keeping the power bus alive during a breaker outage
	var has_charged_ups := false
	for uid in ups_units.keys():
		if is_ups_ready(ups_units[uid]):
			has_charged_ups = true
			break

	ups_backup_active = (not breaker_on) and has_charged_ups
	var power_alive := breaker_on or ups_backup_active

	_strip_parent = {}
	if power_alive:
		var p_visited: Dictionary = {}
		var p_queue: Array = []
		for src in bus_sources:
			p_visited[src] = true
			p_queue.append(src)
		while not p_queue.is_empty():
			var curr := str(p_queue.pop_front())
			for cab_id in cables.keys():
				var cab: Dictionary = cables[cab_id]
				if str(cab["cable_type"]) != "power":
					continue
				var other := ""
				if str(cab["from_id"]) == curr:
					other = str(cab["to_id"])
				elif str(cab["to_id"]) == curr:
					other = str(cab["from_id"])
				if other == "" or p_visited.has(other):
					continue
				p_visited[other] = true
				_strip_parent[other] = curr
				if racks.has(other):
					racks[other]["powered"] = true
					p_queue.append(other)
				elif coolers.has(other):
					coolers[other]["powered"] = true
				elif ups_units.has(other) or (is_power_strip_decor(other) and is_strip_on(other)):
					p_queue.append(other)

		# Goldis Innengeräte laufen, sobald mindestens ein Außengerät Strom hat.
		var any_heat_pump_on := false
		for cid in coolers.keys():
			if is_heat_pump_type(str(coolers[cid].get("cooler_type", "cooler"))) and bool(coolers[cid]["powered"]):
				any_heat_pump_on = true
				break
		if any_heat_pump_on:
			for cid in coolers.keys():
				if is_indoor_unit(str(cid)):
					coolers[cid]["powered"] = true

		# BFS Network from Wall Router (+ Hall C Router if unlocked)
		var n_visited: Dictionary = {WALL_ROUTER_ID: true}
		var n_queue: Array = [WALL_ROUTER_ID]
		if room_level >= 2:
			n_visited[HALL_C_ROUTER_ID] = true
			n_queue.append(HALL_C_ROUTER_ID)
		if halle_nord_owned:
			n_visited[HALL_NORD_ROUTER_ID] = true
			n_queue.append(HALL_NORD_ROUTER_ID)

		while not n_queue.is_empty():
			var curr := str(n_queue.pop_front())
			var can_forward := (
				curr == WALL_ROUTER_ID
				or curr == HALL_C_ROUTER_ID
				or curr == HALL_NORD_ROUTER_ID
				or (is_lan_strip_decor(curr) and is_strip_on(curr))
				or (racks.has(curr) and bool(racks[curr]["powered"]) and _count_rack_switches(curr) > 0)
			)
			if not can_forward:
				continue
			for cab_id in cables.keys():
				var cab: Dictionary = cables[cab_id]
				if str(cab["cable_type"]) != "network":
					continue
				var other := ""
				if str(cab["from_id"]) == curr:
					other = str(cab["to_id"])
				elif str(cab["to_id"]) == curr:
					other = str(cab["from_id"])
				if other == "" or n_visited.has(other):
					continue
				n_visited[other] = true
				if racks.has(other):
					racks[other]["networked"] = true
					n_queue.append(other)
				elif is_lan_strip_decor(other):
					n_queue.append(other)

	# Aggregate real hardware & network bandwidth metrics (GB RAM, TB Storage, CPU, GPU, Mbit/s, Watts)
	var watts := 0
	var compute := 0
	var bonus_sum := 0.0
	var sum_ram := 0
	var sum_cpu := 0
	var sum_gpu := 0
	var sum_sto := 0.0
	var sum_mbps := 0.0
	var device_watts := {}
	if multiplayer.is_server():
		_apply_rack_power_changes()

	for rid in racks.keys():
		var rack: Dictionary = racks[rid]
		if not bool(rack["powered"]):
			continue
		var rack_w0 := watts
		var r_rent := str(rack.get("rental_type", "none"))
		if bool(rack["networked"]) and r_rent != "none" and HardwareCatalog.RENTAL_PROFILES.has(r_rent):
			var rprof: Dictionary = HardwareCatalog.RENTAL_PROFILES[r_rent]
			sum_mbps += float(rack.get("active_users", 0)) * float(rprof.get("mbps_per_user", 0.5))
		for slot in rack["slots"]:
			var sd: Dictionary = slot
			var item_type := str(sd["item_type"])
			if item_type == "":
				continue
			var st := str(sd["state"])
			var stats := get_slot_stats(sd)
			if is_slot_on(sd):
				watts += int(stats["watts"])
				if bool(rack["networked"]):
					compute += int(stats["compute"])
					bonus_sum += float(stats["revenue_bonus"])
					sum_ram += int(stats["ram_gb"])
					sum_cpu += int(stats["cpu_score"])
					sum_gpu += int(stats["gpu_score"])
					sum_sto += float(stats["storage_tb"])
			elif st == "burning":
				watts += int(stats["watts"])
		device_watts[rid] = watts - rack_w0

	# Kaltgang-/Warmgang-Airflow & Kabelmanagement-Bonus live berechnen
	_recompute_layout_bonuses()

	var heatwave_cooler_mult := 1.22 if weather_state == "heatwave" else 1.0
	var airflow_watt_save := 1.0 - airflow_bonus * 0.45
	for cid in coolers.keys():
		if bool(coolers[cid]["powered"]):
			var ctype := str(coolers[cid].get("cooler_type", "cooler"))
			var cw := int(roundf(float(ITEM_CATALOG[ctype]["watts"]) * heatwave_cooler_mult * airflow_watt_save))
			watts += cw
			device_watts[cid] = cw

	# Ladende Notstrom-Batterien ziehen ihre Ladeleistung
	if breaker_on:
		for uid in ups_units.keys():
			var u: Dictionary = ups_units[uid]
			if bool(u["connected"]) and float(u["charge"]) < 99.5:
				var chw := int(get_ups_spec(u)["charge_w"])
				watts += chw
				device_watts[uid] = chw
	_compute_strip_loads(device_watts)

	var req_compute := 0
	for cid in contracts.keys():
		if bool(contracts[cid]["active"]):
			req_compute += int(contracts[cid]["required_compute"])
			sum_mbps += float(contracts[cid].get("req_mbps", 15.0))

	var rt_d: Dictionary = ROUTER_TIERS[clampi(router_tier, 0, ROUTER_TIERS.size() - 1)]
	max_bandwidth_cu = int(rt_d["max_cu"])
	max_bandwidth_mbps = float(rt_d.get("max_mbps", 50.0))
	if halle_nord_owned:
		max_bandwidth_mbps += HALLE_NORD_EXTRA_MBPS
		max_bandwidth_cu += 600
	total_watts = watts
	total_ram_gb = sum_ram
	total_cpu_score = sum_cpu
	total_gpu_score = sum_gpu
	total_storage_tb = sum_sto
	used_bandwidth_mbps = sum_mbps
	raw_compute = compute
	total_compute = mini(compute, max_bandwidth_cu)
	used_compute = req_compute
	revenue_bonus_mult = (1.0 + minf(bonus_sum + cable_mgmt_bonus, 0.92)) * get_level_revenue_mult()


# ==============================================================================
# CLIENT -> HOST ACTION REQUESTS
# ==============================================================================

func _get_sender_id() -> int:
	var sid := multiplayer.get_remote_sender_id()
	if sid == 0:
		return multiplayer.get_unique_id()
	return sid


## Checkliste in der Lobby: Der Server führt die Flags. Erledigt ein Spieler einen Schritt,
## wird er bei allen Spielern sofort abgehakt, damit niemand dieselbe Aufgabe doppelt macht.
func request_mark_checklist_opened_pc() -> void:
	if checklist_opened_pc:
		return
	# Sofort lokal abhaken, der Server bestätigt es danach für alle.
	checklist_opened_pc = true
	checklist_changed.emit()
	_rpc_req_checklist_opened_pc.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_checklist_opened_pc() -> void:
	if not multiplayer.is_server():
		return
	checklist_opened_pc = true
	_broadcast_checklist()


func _broadcast_checklist() -> void:
	if not multiplayer.is_server():
		return
	_rpc_sync_checklist.rpc(checklist_opened_pc, checklist_ordered_anything)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_checklist(opened_pc: bool, ordered: bool) -> void:
	checklist_opened_pc = opened_pc
	checklist_ordered_anything = ordered
	checklist_changed.emit()


func request_buy_item(item_type: String) -> void:
	_rpc_req_buy_item.rpc_id(1, item_type)


func request_checkout_cart(entries: Array, express: bool = false) -> void:
	_rpc_req_checkout_cart.rpc_id(1, entries, express)


## Kauft ein Bauteil direkt am Rack und baut es sofort ein (kein Lieferwagen).
func request_buy_install_component(rack_id: String, slot_idx: int, category: String, part_id: String) -> void:
	_rpc_req_buy_install_component.rpc_id(1, rack_id, slot_idx, category, part_id)


## Kauft ein Mainboard/Chassis direkt am Rack und setzt es sofort in einen leeren Slot.
func request_buy_install_module(rack_id: String, slot_idx: int, item_type: String) -> void:
	_rpc_req_buy_install_module.rpc_id(1, rack_id, slot_idx, item_type)


func request_sell_inventory_part(part_id: String) -> void:
	_rpc_req_sell_inventory_part.rpc_id(1, part_id)


func request_pickup_crate(crate_id: String) -> void:
	_rpc_req_pickup_crate.rpc_id(1, crate_id)


func request_drop_crate(drop_pos: Vector3) -> void:
	_rpc_req_drop_crate.rpc_id(1, drop_pos)


func request_place_held_structure(pos: Vector3, rot_y: float) -> void:
	_rpc_req_place_held_structure.rpc_id(1, pos, rot_y)


func request_relocate_rack(rack_id: String, pos: Vector3, rot_y: float) -> void:
	_rpc_req_relocate_rack.rpc_id(1, rack_id, pos, rot_y)


func request_sell_rack(rack_id: String) -> void:
	_rpc_req_sell_rack.rpc_id(1, rack_id)


func request_pack_device(kind: String, entity_id: String) -> void:
	_rpc_req_pack_device.rpc_id(1, kind, entity_id)


func request_sell_device(kind: String, entity_id: String) -> void:
	_rpc_req_sell_device.rpc_id(1, kind, entity_id)


func request_install_module(rack_id: String, slot_idx: int) -> void:
	_rpc_req_install_module.rpc_id(1, rack_id, slot_idx)


func request_remove_module(rack_id: String, slot_idx: int) -> void:
	_rpc_req_remove_module.rpc_id(1, rack_id, slot_idx)


func request_sell_slot_module(rack_id: String, slot_idx: int) -> void:
	_rpc_req_sell_slot_module.rpc_id(1, rack_id, slot_idx)


func request_upgrade_slot_component(rack_id: String, slot_idx: int, category: String) -> void:
	_rpc_req_upgrade_slot_component.rpc_id(1, rack_id, slot_idx, category)


func request_install_component(rack_id: String, slot_idx: int, category: String, part_id: String) -> void:
	_rpc_req_install_component.rpc_id(1, rack_id, slot_idx, category, part_id)


func request_set_rack_rental(rack_id: String, rental_type: String) -> void:
	_rpc_req_set_rack_rental.rpc_id(1, rack_id, rental_type)


## Leerer Name setzt das Rack auf den Standardnamen „Rack N“ zurück.
func request_rename_rack(rack_id: String, new_name: String) -> void:
	_rpc_req_rename_rack.rpc_id(1, rack_id, new_name.left(RACK_NAME_MAX_LEN * 4))


func request_reply_ticket(ticket_id: String, action: String) -> void:
	_rpc_req_reply_ticket.rpc_id(1, ticket_id, action)


func request_answer_call() -> void:
	_rpc_req_answer_call.rpc_id(1)


func request_resolve_call(choice: String) -> void:
	_rpc_req_resolve_call.rpc_id(1, choice)


## from_slot/to_slot: angeschaute Buchse an den Enden (-1 = egal, Server nimmt die erste freie).
func request_connect_cable(cable_type: String, from_id: String, to_id: String, from_slot: int = -1, to_slot: int = -1) -> void:
	_rpc_req_connect_cable.rpc_id(1, cable_type, from_id, to_id, from_slot, to_slot)


func request_disconnect_cables_on(cable_type: String, endpoint_id: String) -> void:
	_rpc_req_disconnect_cables_on.rpc_id(1, cable_type, endpoint_id)


func request_disconnect_cable_slot(cable_type: String, endpoint_id: String, slot_idx: int) -> void:
	_rpc_req_disconnect_cable_slot.rpc_id(1, cable_type, endpoint_id, slot_idx)


func request_toggle_breaker() -> void:
	_rpc_req_toggle_breaker.rpc_id(1)


func request_buy_fuse() -> void:
	_rpc_req_buy_fuse.rpc_id(1)


func request_insert_fuse(slot_idx: int) -> void:
	_rpc_req_insert_fuse.rpc_id(1, slot_idx)


func request_pickup_extinguisher(ext_id: String) -> void:
	_rpc_req_pickup_extinguisher.rpc_id(1, ext_id)


func request_hang_extinguisher(station: String) -> void:
	_rpc_req_hang_extinguisher.rpc_id(1, station)


func request_drop_extinguisher(pos: Vector3, yaw: float) -> void:
	_rpc_req_drop_extinguisher.rpc_id(1, pos, yaw)


## Ein Sprühstoß. rack_id leer = daneben gesprüht, leert trotzdem die Füllung.
func request_spray_extinguisher(rack_id: String, slot_idx: int) -> void:
	_rpc_req_spray_extinguisher.rpc_id(1, rack_id, slot_idx)


func is_shared_panel_open(entity_id: String, panel_id: String) -> bool:
	return shared_open_panels.has(_panel_key(entity_id, panel_id))


## Tür/Seitenwand/Antenne umschalten: Der Server entscheidet und schickt den neuen Zustand an alle.
func request_toggle_panel(entity_id: String, panel_id: String) -> void:
	if entity_id.is_empty() or panel_id.is_empty():
		return
	_rpc_req_toggle_panel.rpc_id(1, entity_id, panel_id)


func _panel_key(entity_id: String, panel_id: String) -> String:
	return entity_id + "|" + panel_id


func _sanitize_open_panels(data: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (data is Dictionary):
		return out
	var src := data as Dictionary
	for k in src.keys():
		if out.size() >= MAX_SHARED_PANELS:
			break
		var ks := str(k)
		var v: Variant = src[k]
		if ks.length() <= 160 and ks.contains("|") and typeof(v) == TYPE_BOOL and bool(v):
			out[ks] = true
	return out


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_toggle_panel(entity_id: String, panel_id: String) -> void:
	if not multiplayer.is_server():
		return
	if entity_id.length() > 64 or panel_id.length() > 95:
		return
	var key := _panel_key(entity_id, panel_id)
	var opened := not shared_open_panels.has(key)
	if opened:
		if shared_open_panels.size() >= MAX_SHARED_PANELS:
			return
		shared_open_panels[key] = true
	else:
		shared_open_panels.erase(key)
	_rpc_sync_panel.rpc(key, opened)
	if panel_id.begins_with("slot_") and racks.has(entity_id):
		_on_slot_panel_toggled(entity_id, int(panel_id.trim_prefix("slot_")), opened)


## --- Strom im Einschub: ausgefahren = stromlos, eingeschoben = der Server fährt hoch ---

## Hochfahrzeit je nach Servergröße (Sekunden).
func get_boot_seconds(item_type: String) -> float:
	if not is_slot_upgradeable(item_type):
		return 6.0
	match str((ITEM_CATALOG.get(item_type, {}) as Dictionary).get("mb_cat", "entry")):
		"server":
			return 9.0
		"storage":
			return 11.0
		"gpu":
			return 15.0
	return 6.0


## true, wenn der Server Strom bekommt und fertig hochgefahren ist (Rack-Strom wird extra geprüft).
func is_slot_on(slot: Dictionary) -> bool:
	return str(slot.get("state", "ok")) == "ok" and not bool(slot.get("offline", false))


func _on_slot_panel_toggled(rack_id: String, slot_idx: int, opened: bool) -> void:
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	if str(slot.get("item_type", "")) == "":
		return
	var was_on := is_slot_on(slot) and bool(racks[rack_id].get("powered", false))
	_recalculate_networks_and_metrics()
	_broadcast_racks()
	_broadcast_sim_tick()
	if opened and was_on:
		_rpc_play_sfx.rpc("server_off")


func _close_slot_panel(rack_id: String, slot_idx: int) -> void:
	var key := _panel_key(rack_id, "slot_%d" % slot_idx)
	if shared_open_panels.has(key):
		shared_open_panels.erase(key)
		_rpc_sync_panel.rpc(key, false)


## Abstand zwischen zwei Servern beim Start eines ganzen Racks.
const RACK_BOOT_STAGGER := 1.5
const RACK_BOOT_FIRST := 1.2
## Letzter bekannter Stromzustand je Rack. Fehlt ein Rack, gilt der erste Wert nicht als Wechsel.
var _rack_power_prev: Dictionary = {}


## Strom weg = alle Server aus. Strom da = Server fahren der Reihe nach hoch (nur Host).
func _apply_rack_power_changes() -> void:
	for rid_v in racks.keys():
		var rid := str(rid_v)
		var now := bool(racks[rid]["powered"])
		if _rack_power_prev.has(rid) and bool(_rack_power_prev[rid]) != now:
			var k := 0
			for i in range((racks[rid]["slots"] as Array).size()):
				var slot: Dictionary = racks[rid]["slots"][i]
				if str(slot.get("item_type", "")) == "" or str(slot.get("state", "ok")) != "ok":
					continue
				slot["offline"] = true
				slot.erase("boot_wait")
				if now and not is_slot_extended(rid, i):
					var t := get_boot_seconds(str(slot["item_type"]))
					slot["boot_left"] = t
					slot["boot_total"] = t
					slot["boot_wait"] = RACK_BOOT_FIRST + float(k) * RACK_BOOT_STAGGER
					k += 1
				else:
					slot.erase("boot_left")
					slot.erase("boot_total")
		_rack_power_prev[rid] = now
	for old in _rack_power_prev.keys():
		if not racks.has(old):
			_rack_power_prev.erase(old)


## Hält den Stromzustand aller Einschübe passend zur Schiene (nur Host).
func _refresh_slot_power() -> void:
	for rid in racks.keys():
		var slots: Array = racks[rid]["slots"]
		for i in range(slots.size()):
			var slot: Dictionary = slots[i]
			if str(slot.get("item_type", "")) == "":
				continue
			if is_slot_extended(str(rid), i):
				slot["offline"] = true
				slot.erase("boot_left")
				slot.erase("boot_total")
				slot.erase("boot_wait")
			elif bool(slot.get("offline", false)):
				if str(slot.get("state", "ok")) != "ok":
					slot.erase("boot_left")
					slot.erase("boot_total")
				elif not slot.has("boot_left"):
					var t := get_boot_seconds(str(slot["item_type"]))
					slot["boot_left"] = t
					slot["boot_total"] = t


func _update_slot_boot(dt: float) -> void:
	var done := false
	var woke := false
	for rid in racks.keys():
		if not bool(racks[rid].get("powered", false)):
			continue
		for slot_v in racks[rid]["slots"]:
			var slot: Dictionary = slot_v
			if not slot.has("boot_left"):
				continue
			if float(slot.get("boot_wait", 0.0)) > 0.0:
				slot["boot_wait"] = float(slot["boot_wait"]) - dt
				if float(slot["boot_wait"]) <= 0.0:
					slot.erase("boot_wait")
					woke = true
				continue
			slot["boot_left"] = float(slot["boot_left"]) - dt
			if float(slot["boot_left"]) <= 0.0:
				slot.erase("boot_left")
				slot.erase("boot_total")
				slot.erase("offline")
				done = true
	if done:
		_recalculate_networks_and_metrics()
		_broadcast_racks()
		_broadcast_sim_tick()
	elif woke:
		_broadcast_racks()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_panel(key: String, opened: bool) -> void:
	if not multiplayer.is_server():
		if opened:
			shared_open_panels[key] = true
		else:
			shared_open_panels.erase(key)
	panel_states_changed.emit()


func request_toggle_garage_door() -> void:
	_rpc_req_set_garage_door.rpc_id(1, not garage_door_open)


func request_set_garage_door(open: bool) -> void:
	if garage_door_open == open:
		return
	_rpc_req_set_garage_door.rpc_id(1, open)


func set_garage_door_open_server(open: bool) -> void:
	if not multiplayer.is_server():
		return
	if garage_door_open == open:
		return
	garage_door_open = open
	_rpc_sync_garage_door.rpc(open)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_set_garage_door(open: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "garage_door", 8, 4.0):
		return
	if garage_door_open == open:
		return
	garage_door_open = open
	_rpc_sync_garage_door.rpc(open)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_garage_door(open: bool) -> void:
	garage_door_open = open
	garage_door_changed.emit(open)


func request_repair_slot(rack_id: String, slot_idx: int, amount: float) -> void:
	_rpc_req_repair_slot.rpc_id(1, rack_id, slot_idx, amount)


func request_diagnose_slot(rack_id: String, slot_idx: int) -> void:
	_rpc_req_diagnose_slot.rpc_id(1, rack_id, slot_idx)


## Ausgefallen durch ein defektes Bauteil, das noch niemand in der 3D-Vorschau gefunden hat.
func is_slot_awaiting_diagnosis(slot: Dictionary) -> bool:
	return str(slot.get("state", "")) == "crashed" \
		and str(slot.get("faulty_part", "")) != "" \
		and not bool(slot.get("diagnosed", false))


## Teil, das man dem Server (Einschub oder Schlitten) als kaputt ansieht. "" = nichts zu sehen.
func get_visible_fault(data: Dictionary) -> String:
	if str(data.get("state", "")) != "crashed" or bool(data.get("fault_hidden", false)):
		return ""
	return str(data.get("faulty_part", ""))


func get_component_label(cat: String) -> String:
	# Das Mainboard ist kein austauschbares Bauteil, braucht aber einen Namen für den Hover.
	if cat == "mainboard":
		return tr("Mainboard")
	return str((COMPONENT_CATALOG.get(cat, {}) as Dictionary).get("label", cat))


## Wählt zufällig ein eingebautes Bauteil. Switches haben keine sichtbaren Bauteile in der Vorschau.
func _pick_faulty_part(slot: Dictionary) -> String:
	if get_chassis_visual(str(slot.get("item_type", ""))) == "net_switch":
		return ""
	var comps: Dictionary = slot.get("components", {}) as Dictionary
	var cands: Array[String] = ["mainboard"]
	for cat_v in COMPONENT_ORDER:
		var cat := str(cat_v)
		# Dieselbe Regel wie beim Modellaufbau, damit der Defekt immer sichtbar ist.
		if HardwareMeshFactory.has_part(comps, cat):
			cands.append(cat)
	if cands.is_empty():
		return ""
	return cands[randi() % cands.size()]


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_diagnose_slot(rack_id: String, slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not racks.has(rack_id):
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	if not is_slot_awaiting_diagnosis(slot):
		return
	slot["diagnosed"] = true
	post_event_f("%s hat den Defekt gefunden: %s in %s Slot %d. Jetzt das Teil in der 3D-Vorschau anklicken, um es zu reparieren.", [
		NetworkManager.get_player_name(peer_id), get_component_label(str(slot["faulty_part"])),
		get_rack_display_name(rack_id), slot_idx + 1
	], "good")
	_broadcast_racks()


func request_toggle_contract(contract_id: String) -> void:
	_rpc_req_toggle_contract.rpc_id(1, contract_id)


func request_upgrade_power() -> void:
	_rpc_req_upgrade_power.rpc_id(1)


func request_upgrade_router() -> void:
	_rpc_req_upgrade_router.rpc_id(1)


func request_research(branch: String) -> void:
	_rpc_req_research.rpc_id(1, branch)


func request_expand_room() -> void:
	_rpc_req_expand_room.rpc_id(1)


func request_upgrade_ai_platform() -> void:
	_rpc_req_upgrade_ai_platform.rpc_id(1)


func request_mitigate_ddos() -> void:
	_rpc_req_mitigate_ddos.rpc_id(1)


func request_grab_cart(cart_id: String) -> void:
	_rpc_req_grab_cart.rpc_id(1, cart_id)


func request_release_cart(pos: Vector3, rot_y: float) -> void:
	_rpc_req_release_cart.rpc_id(1, pos, rot_y)


func request_load_held_crate_to_cart(cart_id: String) -> void:
	_rpc_req_load_held_crate_to_cart.rpc_id(1, cart_id)


func request_load_ground_crate_to_pushed_cart(crate_id: String) -> void:
	_rpc_req_load_ground_crate_to_pushed_cart.rpc_id(1, crate_id)


func request_unload_cart_to_hands(cart_id: String) -> void:
	_rpc_req_unload_cart_to_hands.rpc_id(1, cart_id)


func update_cart_pose_from_host(cart_id: String, pos: Vector3, rot_y: float) -> void:
	if carts.has(cart_id):
		carts[cart_id]["pos"] = pos
		carts[cart_id]["rot_y"] = rot_y


# ==============================================================================
# HOST RPC HANDLERS
# ==============================================================================

func _disconnect_all_cables_of(entity_id: String) -> void:
	var to_del: Array = []
	for cid in cables.keys():
		var c: Dictionary = cables[cid]
		if str(c["from_id"]) == entity_id or str(c["to_id"]) == entity_id:
			to_del.append(cid)
	for cid in to_del:
		cables.erase(cid)


func set_host_only_destructive(enabled: bool) -> void:
	if not multiplayer.is_server():
		return
	if host_only_destructive == enabled:
		return
	host_only_destructive = enabled
	_rpc_sync_host_permissions.rpc(enabled)
	post_event(
		"Host-Schutz aktiviert: Nur der Host darf verkaufen, Kredite aufnehmen & ausbauen."
		if enabled else
		"Host-Schutz deaktiviert: Alle Mitspieler dürfen verkaufen & ausbauen.",
		"info"
	)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_host_permissions(enabled: bool) -> void:
	host_only_destructive = enabled
	host_permissions_changed.emit()


func is_destructive_action_allowed(peer_id: int) -> bool:
	return not host_only_destructive or peer_id <= 1


func _deny_destructive_action(peer_id: int, action_label: String) -> void:
	_rpc_play_sfx.rpc_id(peer_id, "error")
	post_event_f("Nur der Host darf %s (Host-Schutz aktiv).", [action_label], "warn")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_buy_item(item_type: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "buy", 10, 5.0):
		return
	if not ITEM_CATALOG.has(item_type):
		return
	if get_delivery_zone_free_slots() < 1:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		post_event_f("🚫 Lieferzone voll (%d/%d Plätze)! Erst Pakete aus der Einfahrt räumen.", [
			get_delivery_zone_used_slots(), DELIVERY_ZONE_MAX_CRATES
		], "warn")
		return
	var price := float(ITEM_CATALOG[item_type]["price"])
	if money < price:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money -= price

	# Add to Delivery Vehicle! If vehicle is currently approaching, toss right into its cargo hold.
	if van_phase == "arriving" or van_phase == "unloading":
		van_cargo.append(item_type)
		if van_phase == "arriving":
			van_delivery_tier = maxi(van_delivery_tier, compute_delivery_tier(van_cargo))
	else:
		pending_delivery_items.append(item_type)
		if van_phase == "idle":
			van_cargo = _pack_van_cargo(pending_delivery_items)
			pending_delivery_items.clear()
			scheduled_delivery_day = 0
			scheduled_delivery_hour = -1
			pending_delivery_express = false
			van_delivery_tier = compute_delivery_tier(van_cargo)
			van_phase = "arriving"
			van_phase_time = 0.0
			_van_unload_accum = 0.0
			_reset_van_trip()

	_broadcast_van_state()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("cash")
	var tmeta: Dictionary = DELIVERY_TIER_META.get(van_delivery_tier, DELIVERY_TIER_META[1])
	post_event_f("%s bestellte %s — %s %s liefert gleich!", [
		NetworkManager.get_player_name(peer_id), ITEM_CATALOG[item_type]["name"], str(tmeta["icon"]), str(tmeta["name"])
	], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_pickup_crate(crate_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if is_player_holding_anything(peer_id) or not crates.has(crate_id):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	if int(crates[crate_id]["held_by"]) != 0:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	crates[crate_id]["held_by"] = peer_id
	crates[crate_id]["held_slot"] = get_active_slot(peer_id)
	# Was ein Spieler nimmt, holt der Techniker nicht mehr zurück.
	crates[crate_id].erase("tech")
	_broadcast_crates()
	_rpc_play_sfx.rpc_id(peer_id, "pickup")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_drop_crate(drop_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if not SecurityGuard.is_finite_vec3(drop_pos):
		return
	var peer_id := _get_sender_id()
	var held := get_player_held_crate(peer_id)
	if held.is_empty():
		return
	var cid := str(held["id"])
	crates[cid]["held_by"] = 0
	crates[cid]["pos"] = _clamp_drop_pos(drop_pos)
	_broadcast_crates()
	_rpc_play_sfx.rpc_id(peer_id, "drop")


## Hält eine Ablageposition im begehbaren Bereich (Garage/Hallen bzw. Halle Nord) und außerhalb von Geräten.
func _clamp_drop_pos(drop_pos: Vector3) -> Vector3:
	var min_x := -5.0
	var max_x := 5.0 if room_level == 0 else (11.8 if room_level == 1 else 20.8)
	var min_z := -4.0
	var max_z := 8.8
	if halle_nord_owned and drop_pos.z < -100.0:
		min_x = -9.5
		max_x = 9.5
		min_z = HALLE_NORD_ORIGIN.z - 5.5
		max_z = HALLE_NORD_ORIGIN.z + 12.5
	var clamped := Vector3(clampf(drop_pos.x, min_x, max_x), 0.0, clampf(drop_pos.z, min_z, max_z))
	# Verhindert, dass abgelegte Items in einem Server-Rack oder Gerät verschwinden!
	return _push_drop_outside_obstacles(clamped, min_x, max_x, min_z, max_z)


func _push_drop_outside_obstacles(pos: Vector3, min_x: float, max_x: float, min_z: float, max_z: float) -> Vector3:
	var out := pos
	var obstacles: Array[Vector3] = []
	for rk in racks.values():
		obstacles.append((rk as Dictionary).get("pos", Vector3.ZERO) as Vector3)
	for cl in coolers.values():
		obstacles.append((cl as Dictionary).get("pos", Vector3.ZERO) as Vector3)
	for up in ups_units.values():
		obstacles.append((up as Dictionary).get("pos", Vector3.ZERO) as Vector3)
	for _pass in range(2):
		for ob in obstacles:
			var dx := out.x - ob.x
			var dz := out.z - ob.z
			var dist := Vector2(dx, dz).length()
			var min_r := 0.78
			if dist < min_r:
				var dir := Vector2(dx, dz)
				if dir.length_squared() < 0.0004:
					dir = Vector2(0.0, 1.0)
				else:
					dir = dir.normalized()
				out.x = clampf(ob.x + dir.x * min_r, min_x, max_x)
				out.z = clampf(ob.z + dir.y * min_r, min_z, max_z)
	return out


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_place_held_structure(pos: Vector3, rot_y: float) -> void:
	if not multiplayer.is_server():
		return
	if not SecurityGuard.is_finite_vec3(pos) or not SecurityGuard.is_finite_float(rot_y):
		return
	var peer_id := _get_sender_id()
	var held := get_player_held_crate(peer_id)
	if held.is_empty():
		return
	var item_type := str(held["item_type"])
	if str(ITEM_CATALOG[item_type]["category"]) != "placeable":
		return
	var new_id := ""
	var snapped := snap_place_pos(item_type, pos)
	if item_type == INDOOR_UNIT_TYPE:
		# Wandgeräte behalten Höhe und Wandabstand aus get_wall_mount_spot().
		snapped = pos
	elif is_heat_pump_type(item_type):
		# Außengeräte zeigen immer mit dem Lüfter zur Straße.
		rot_y = 0.0
	if not can_place_item_at(item_type, snapped, rot_y):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	var held_cid := str(held["id"])
	var pcount := maxi(1, int(crates[held_cid].get("pack_count", 1)))
	if pcount > 1:
		crates[held_cid]["pack_count"] = pcount - 1
	else:
		crates.erase(held_cid)
	if item_type == "rack" or item_type == "rack_pro":
		var rid := _alloc_rack_id()
		new_id = rid
		racks[rid] = _make_rack_data(rid, item_type, snapped, rot_y)
		_recalculate_networks_and_metrics()
		_broadcast_racks()
		post_event_f("%s hat %s (%s) aufgestellt.", [NetworkManager.get_player_name(peer_id), get_rack_display_name(rid), ITEM_CATALOG[item_type]["name"]], "info")
	elif is_heat_pump_type(item_type) or is_floor_cooler_type(item_type) or item_type == INDOOR_UNIT_TYPE:
		var cid := _alloc_id("cooler")
		new_id = cid
		coolers[cid] = {
			"id": cid,
			"cooler_type": item_type,
			"pos": snapped,
			"rot_y": rot_y,
			"powered": false,
		}
		_recalculate_networks_and_metrics()
		_broadcast_coolers()
		if item_type == INDOOR_UNIT_TYPE:
			post_event_f("%s hat ein %s an die Wand gehängt (läuft, sobald ein Außengerät Strom hat).", [NetworkManager.get_player_name(peer_id), ITEM_CATALOG[item_type]["name"]], "info")
		elif is_floor_cooler_type(item_type):
			post_event_f("%s hat %s aufgestellt (Stromkabel oben anschließen!).", [NetworkManager.get_player_name(peer_id), ITEM_CATALOG[item_type]["name"]], "info")
		else:
			post_event_f("%s hat %s auf den Rasen gestellt (Stromkabel seitlich anschließen!).", [NetworkManager.get_player_name(peer_id), ITEM_CATALOG[item_type]["name"]], "info")
	elif is_ups_type(item_type):
		var uid := _alloc_id("ups")
		new_id = uid
		ups_units[uid] = {
			"id": uid,
			"ups_type": item_type,
			"health": clampf(float((held.get("ups", {}) as Dictionary).get("health", 100.0)), UPS_MIN_HEALTH, 100.0),
			"pos": snapped,
			"rot_y": rot_y,
			"connected": false,
			"charge": clampf(float((held.get("ups", {}) as Dictionary).get("charge", 25.0)), 0.0, 100.0), # ab Werk 25 % geladen
			"discharging": false,
		}
		_recalculate_networks_and_metrics()
		_broadcast_ups()
		post_event_f("%s hat USV-Notstrom %s aufgestellt (mit Stromkabel [2] verbinden!).", [NetworkManager.get_player_name(peer_id), uid.to_upper()], "good")
	elif is_decor_type(item_type):
		var did := _alloc_id("decor")
		new_id = did
		var stored: Array = []
		if item_type == "prop_storage_shelf":
			stored = [null, null, null, null]
		decor_items[did] = {
			"id": did,
			"item_type": item_type,
			"pos": snapped,
			"rot_y": rot_y,
			"wall": is_strip_type(item_type) and snapped.y >= STRIP_WALL_MIN_Y,
			"stored_items": stored,
		}
		_recalculate_networks_and_metrics()
		_broadcast_decor_items()
		post_event_f("%s hat %s aufgestellt.", [NetworkManager.get_player_name(peer_id), ITEM_CATALOG[item_type]["name"]], "good")

	_broadcast_crates()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("place")
	if pcount <= 1 and not bool(held.get("unboxed", false)):
		var drop := _carton_drop_pos(snapped, rot_y)
		_rpc_unpack_fx.rpc(new_id, item_type, drop)
		_spawn_empty_carton(CartonFactory.kind_for(item_type), drop, UNPACK_SECONDS)


# --- Auspacken und Altpapier ---

const UNPACK_SECONDS := 2.1
const EMPTY_CARTONS_MAX := 30


@rpc("authority", "call_local", "reliable")
func _rpc_unpack_fx(entity_id: String, item_type: String, carton_pos: Vector3) -> void:
	unpack_started.emit(entity_id, item_type, carton_pos)


## Freier Platz vor dem Gerät für den leeren Karton.
func _carton_drop_pos(pos: Vector3, rot_y: float) -> Vector3:
	var fwd := Vector3(sin(rot_y), 0.0, cos(rot_y))
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var base := Vector3(pos.x, 0.0, pos.z)
	for off in [fwd * 1.15, fwd * 1.15 + side * 0.8, fwd * 1.15 - side * 0.8, side * 1.2, -side * 1.2, -fwd * 1.2]:
		var p := _clamp_drop_pos(base + (off as Vector3))
		if Vector2(p.x - base.x, p.z - base.z).length() < 0.8:
			continue
		var free := true
		for c in crates.values():
			var cd: Dictionary = c
			if int(cd.get("held_by", 0)) == 0 and (cd["pos"] as Vector3).distance_to(p) < 0.6:
				free = false
				break
		if free:
			return p
	return _clamp_drop_pos(base + fwd * 1.15)


func _spawn_empty_carton(kind: String, pos: Vector3, delay: float = 0.0) -> void:
	if not multiplayer.is_server():
		return
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(_spawn_empty_carton.bind(kind, pos, 0.0))
		return
	if not is_active:
		return
	var n := 0
	for c in crates.values():
		if str((c as Dictionary).get("item_type", "")) == "empty_carton":
			n += 1
	if n >= EMPTY_CARTONS_MAX:
		return
	var cid := _alloc_id("crate")
	crates[cid] = {"id": cid, "item_type": "empty_carton", "carton": kind, "pos": pos, "held_by": 0, "pack_count": 1}
	_broadcast_crates()


func request_dump_carton(site: String) -> void:
	_rpc_req_dump_carton.rpc_id(1, site)


## Leeren Karton aus der Hand oder alle vom geschobenen Rollwagen in den Container werfen.
@rpc("any_peer", "call_local", "reliable")
func _rpc_req_dump_carton(site: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if site != "garage" and site != "nord":
		return
	var sum := 0
	var held := get_player_held_crate(peer_id)
	if str(held.get("item_type", "")) == "empty_carton":
		sum += CartonFactory.refund(str(held.get("carton", "deco")))
		crates.erase(str(held["id"]))
		_broadcast_crates()
	else:
		var cart := get_player_pushed_cart(peer_id)
		if not cart.is_empty():
			var cart_id := str(cart["id"])
			var items: Array = carts[cart_id]["items"]
			for i in range(items.size() - 1, -1, -1):
				if str(items[i]) == "empty_carton":
					sum += CartonFactory.refund(str(_cart_take(cart_id, i).get("carton", "deco")))
					items.remove_at(i)
			if sum > 0:
				_broadcast_carts()
	if sum <= 0:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money += float(sum)
	_broadcast_sim_tick()
	_rpc_paper_bin.rpc(site)
	_rpc_play_sfx.rpc_id(peer_id, "cash")


@rpc("authority", "call_local", "reliable")
func _rpc_paper_bin(site: String) -> void:
	paper_bin_used.emit(site)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_relocate_rack(rack_id: String, pos: Vector3, rot_y: float) -> void:
	if not multiplayer.is_server():
		return
	if not SecurityGuard.is_finite_vec3(pos) or not SecurityGuard.is_finite_float(rot_y):
		return
	var peer_id := _get_sender_id()
	if not racks.has(rack_id):
		return
	var snapped := Vector3(roundf(pos.x * 2.0) * 0.5, 0.0, roundf(pos.z * 2.0) * 0.5)
	if not can_place_at(snapped, rack_id):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	_disconnect_all_cables_of(rack_id)
	racks[rack_id]["pos"] = snapped
	racks[rack_id]["rot_y"] = rot_y
	_recalculate_networks_and_metrics()
	_broadcast_cables()
	_broadcast_racks()
	_broadcast_coolers()
	_broadcast_ups()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("place")
	post_event_f("%s hat %s umgesetzt (Kabel neu anschließen!).", [NetworkManager.get_player_name(peer_id), get_rack_display_name(rack_id)], "info")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_sell_rack(rack_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "sell", 6, 5.0):
		return
	if not is_destructive_action_allowed(peer_id):
		_deny_destructive_action(peer_id, "Racks verkaufen")
		return
	if not racks.has(rack_id):
		return
	var refund := get_rack_sell_value(rack_id)
	_disconnect_all_cables_of(rack_id)
	_clear_tickets_for_rack(rack_id)
	if not active_call.is_empty() and str(active_call.get("rack_id", "")) == rack_id:
		active_call.clear()
		_broadcast_call()
	var sold_name := get_rack_display_name(rack_id)
	racks.erase(rack_id)
	# Offene Türen/Schächte dieses Racks aufräumen, damit ein neues Rack mit derselben ID sauber startet.
	var prefix := rack_id + "|"
	for pkey in shared_open_panels.keys():
		if str(pkey).begins_with(prefix):
			shared_open_panels.erase(pkey)
			_rpc_sync_panel.rpc(str(pkey), false)
	money += float(refund)
	_recalculate_networks_and_metrics()
	_broadcast_cables()
	_broadcast_racks()
	_broadcast_tickets()
	_broadcast_coolers()
	_broadcast_ups()
	_broadcast_crates()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("sell")
	post_event_f("%s verkaufte %s für +$%d.", [NetworkManager.get_player_name(peer_id), sold_name, refund], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_pack_device(kind: String, entity_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if is_player_holding_anything(peer_id):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	var item_type := ""
	var ups_back := {}
	if kind == "cooler" and coolers.has(entity_id):
		item_type = str(coolers[entity_id].get("cooler_type", "cooler"))
		_disconnect_all_cables_of(entity_id)
		coolers.erase(entity_id)
		_broadcast_coolers()
	elif kind == "ups" and ups_units.has(entity_id):
		item_type = get_ups_type(ups_units[entity_id])
		ups_back = {"charge": float(ups_units[entity_id].get("charge", 0.0)), "health": get_ups_health(ups_units[entity_id])}
		_disconnect_all_cables_of(entity_id)
		ups_units.erase(entity_id)
		_broadcast_ups()
	else:
		return

	var cid := _alloc_id("crate")
	crates[cid] = {"id": cid, "item_type": item_type, "pos": Vector3.ZERO, "held_by": peer_id, "held_slot": get_active_slot(peer_id), "unboxed": true}
	if ups_back.size() > 0:
		crates[cid]["ups"] = ups_back
	_recalculate_networks_and_metrics()
	_broadcast_cables()
	_broadcast_crates()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc_id(peer_id, "pickup")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_sell_device(kind: String, entity_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "sell", 6, 5.0):
		return
	if not is_destructive_action_allowed(peer_id):
		_deny_destructive_action(peer_id, "Geräte verkaufen")
		return
	var refund := get_device_sell_value(kind, entity_id)
	if refund <= 0:
		return
	_disconnect_all_cables_of(entity_id)
	if kind == "cooler":
		coolers.erase(entity_id)
		_broadcast_coolers()
	elif kind == "ups":
		ups_units.erase(entity_id)
		_broadcast_ups()
	elif kind == "cart":
		if carts.has(entity_id) and int(carts[entity_id].get("pushed_by", 0)) != 0:
			_rpc_play_sfx.rpc_id(peer_id, "error")
			return
		carts.erase(entity_id)
		_broadcast_carts()
	money += float(refund)
	_recalculate_networks_and_metrics()
	_broadcast_cables()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("sell")
	post_event_f("%s verkaufte %s für +$%d.", [NetworkManager.get_player_name(peer_id), entity_id.to_upper(), refund], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_install_module(rack_id: String, slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	var held := get_player_held_crate(peer_id)
	if held.is_empty():
		return
	var item_type := str(held["item_type"])
	if str(ITEM_CATALOG[item_type]["category"]) != "module":
		return
	if not racks.has(rack_id):
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	if str(slots[slot_idx]["item_type"]) != "":
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	var held_mod_cid := str(held["id"])
	var mod_pcount := maxi(1, int(crates[held_mod_cid].get("pack_count", 1)))
	if mod_pcount > 1:
		crates[held_mod_cid]["pack_count"] = mod_pcount - 1
	else:
		crates.erase(held_mod_cid)
		if not bool(held.get("unboxed", false)):
			_spawn_empty_carton("server", _carton_drop_pos(racks[rack_id]["pos"], float(racks[rack_id].get("rot_y", 0.0))), 0.6)
			_rpc_play_sfx.rpc("carton_open")
	slots[slot_idx] = {
		"item_type": item_type,
		"state": "ok",
		"repair_progress": 0.0,
		"fire_level": 0.0,
		"offline": true, # fährt nach dem Einbau erst hoch
		"components": _default_components(item_type),
	}
	_recalculate_networks_and_metrics()
	_broadcast_crates()
	_broadcast_racks()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("snap")
	post_event_f("%s baute %s in %s (Slot %d) ein.", [
		NetworkManager.get_player_name(peer_id),
		ITEM_CATALOG[item_type]["name"],
		get_rack_display_name(rack_id),
		slot_idx + 1,
	], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_remove_module(rack_id: String, slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if is_player_holding_anything(peer_id) or not racks.has(rack_id):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		if is_player_holding_anything(peer_id):
			post_event("Hände voll! Erst Item mit [Q] ablegen oder freien Slot (1–4) wählen.", "warn")
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var item_type := str(slots[slot_idx]["item_type"])
	if item_type == "" or str(slots[slot_idx]["state"]) == "burning":
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	slots[slot_idx] = _make_empty_slot()
	var cid := _alloc_id("crate")
	crates[cid] = {"id": cid, "item_type": item_type, "pos": Vector3.ZERO, "held_by": peer_id, "held_slot": get_active_slot(peer_id), "unboxed": true}
	_recalculate_networks_and_metrics()
	_broadcast_racks()
	_broadcast_crates()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc_id(peer_id, "pickup")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_sell_slot_module(rack_id: String, slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "sell", 8, 5.0):
		return
	if not is_destructive_action_allowed(peer_id):
		_deny_destructive_action(peer_id, "Server-Module verkaufen")
		return
	if not racks.has(rack_id):
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	var item_type := str(slot["item_type"])
	if item_type == "" or str(slot["state"]) == "burning":
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var stats := get_slot_stats(slot)
	var refund := int(roundf(float(stats["total_value"]) * SELL_REFUND_RATIO))
	slots[slot_idx] = _make_empty_slot()
	money += float(refund)
	_recalculate_networks_and_metrics()
	_broadcast_racks()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("sell")
	post_event_f("%s verkaufte Modul aus %s Slot %d für +$%d.", [
		NetworkManager.get_player_name(peer_id), get_rack_display_name(rack_id), slot_idx + 1, refund
	], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_upgrade_slot_component(rack_id: String, slot_idx: int, category: String) -> void:
	# Legacy helper: advances to next part in HardwareCatalog
	if not multiplayer.is_server() or not racks.has(rack_id):
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	var comps: Dictionary = HardwareCatalog.normalize_components(slot.get("components", {}), str(slot.get("item_type", "web_server")))
	var cur_id := str(comps.get(category, HardwareCatalog.DEFAULT_PARTS.get(category, "")))
	var arr := HardwareCatalog.get_category_parts(category)
	var idx := HardwareCatalog.get_part_index(category, cur_id)
	if idx + 1 < arr.size():
		_rpc_req_install_component(rack_id, slot_idx, category, str((arr[idx + 1] as Dictionary)["id"]))


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_install_component(rack_id: String, slot_idx: int, category: String, part_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not racks.has(rack_id) or not HardwareCatalog.PARTS.has(category):
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	var item_type := str(slot["item_type"])
	if not is_slot_upgradeable(item_type) or str(slot["state"]) == "burning":
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	var new_part := HardwareCatalog.get_part(category, part_id)
	if new_part.is_empty():
		return
	var comps := HardwareCatalog.normalize_components(slot.get("components", {}), item_type)
	var old_id := str(comps.get(category, ""))
	if old_id == part_id:
		return

	# v1.0 Unified Warehouse Flow: install purchased parts from parts_inventory (stock defaults always free)!
	var is_default := HardwareCatalog.is_stock_default_part(part_id)
	if not is_default:
		var stock := int(parts_inventory.get(part_id, 0))
		if stock <= 0:
			_rpc_play_sfx.rpc_id(peer_id, "error")
			post_event_f("%s nicht im Teile-Lager! Erst im PC-Shop bestellen.", [str(new_part["name"])], "warn")
			return
		parts_inventory[part_id] = stock - 1
		if int(parts_inventory[part_id]) <= 0:
			parts_inventory.erase(part_id)

	# Return old swapped-out non-default component neatly back into the Parts Warehouse!
	if old_id != "" and not HardwareCatalog.is_stock_default_part(old_id):
		parts_inventory[old_id] = int(parts_inventory.get(old_id, 0)) + 1

	comps[category] = part_id
	slot["components"] = comps
	_recalculate_networks_and_metrics()
	_broadcast_inventory()
	_broadcast_racks()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("upgrade")
	post_event_f("%s baute %s aus dem Lager in %s Slot %d ein!", [
		NetworkManager.get_player_name(peer_id), str(new_part["name"]), get_rack_display_name(rack_id), slot_idx + 1
	], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_buy_install_component(rack_id: String, slot_idx: int, category: String, part_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not racks.has(rack_id) or not HardwareCatalog.PARTS.has(category):
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	var item_type := str(slot["item_type"])
	if not is_slot_upgradeable(item_type) or str(slot["state"]) == "burning":
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var new_part := HardwareCatalog.get_part(category, part_id)
	if new_part.is_empty():
		return
	var cost := float(new_part.get("cost", 0))
	if cost <= 0.0 or money < cost or not is_part_unlocked(new_part):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var comps := HardwareCatalog.normalize_components(slot.get("components", {}), item_type)
	if str(comps.get(category, "")) == part_id:
		return

	# Teil direkt ins Lager buchen und sofort über den normalen Einbau-Weg verbauen.
	money -= cost
	parts_inventory[part_id] = int(parts_inventory.get(part_id, 0)) + 1
	_rpc_req_install_component(rack_id, slot_idx, category, part_id)
	_rpc_play_sfx.rpc("cash")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_buy_install_module(rack_id: String, slot_idx: int, item_type: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not racks.has(rack_id) or not ITEM_CATALOG.has(item_type):
		return
	if str(ITEM_CATALOG[item_type]["category"]) != "module":
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	if str(slots[slot_idx]["item_type"]) != "":
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var cost := float(ITEM_CATALOG[item_type]["price"])
	if money < cost or not is_item_unlocked(item_type):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	money -= cost
	slots[slot_idx] = {
		"item_type": item_type,
		"state": "ok",
		"repair_progress": 0.0,
		"fire_level": 0.0,
		"components": _default_components(item_type),
	}
	_recalculate_networks_and_metrics()
	_broadcast_racks()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("cash")
	_rpc_play_sfx.rpc("snap")
	post_event_f("%s kaufte %s und baute es in %s (Slot %d) ein.", [
		NetworkManager.get_player_name(peer_id),
		ITEM_CATALOG[item_type]["name"],
		get_rack_display_name(rack_id),
		slot_idx + 1,
	], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_checkout_cart(entries: Array, express: bool = false) -> void:
	if not multiplayer.is_server() or entries.is_empty() or entries.size() > 40:
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "checkout", 6, 5.0):
		return
	var total_cost := 0.0
	var queue_items: Array = []

	for raw in entries:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var kind := str(e.get("kind", "item")) # "item" | "part"
		var qty := clampi(int(e.get("qty", 1)), 1, 24)
		if kind == "item":
			var itype := str(e.get("id", ""))
			if not ITEM_CATALOG.has(itype) or not is_item_unlocked(itype):
				continue
			total_cost += float(ITEM_CATALOG[itype]["price"]) * float(qty)
			if itype == "kit_bundle_all":
				for _q in range(qty):
					for kid in REPAIR_KIT_ORDER:
						queue_items.append(kid)
			else:
				for _q in range(qty):
					queue_items.append(itype)
		elif kind == "slot_build":
			var mb_id := str(e.get("mainboard_id", ""))
			var comps_d: Dictionary = e.get("components", {}) as Dictionary
			var bprice := calculate_slot_build_price(mb_id, comps_d)
			if bprice <= 0 or not ITEM_CATALOG.has(mb_id):
				continue
			total_cost += float(bprice)
			var oid := _alloc_id("build")
			var rid := str(e.get("rack_id", ""))
			var sidx := maxi(0, int(e.get("slot_idx", 0)))
			var rlbl := str(e.get("rack_label", get_rack_display_name(rid) if not rid.is_empty() else "Rack"))
			pending_build_orders[oid] = {
				"rack_id": rid,
				"slot_idx": sidx,
				"rack_label": rlbl,
				"mainboard_id": mb_id,
				"components": comps_d.duplicate(true),
			}
			queue_items.append("build:" + oid)
		elif kind == "part":
			var cat := str(e.get("cat", ""))
			var pid := str(e.get("id", ""))
			var pd := HardwareCatalog.get_part(cat, pid)
			if pd.is_empty() or int(pd.get("cost", 0)) <= 0 or not is_part_unlocked(pd):
				continue
			total_cost += float(pd["cost"]) * float(qty)
			for _q in range(qty):
				queue_items.append("part:" + pid)
		elif kind == "acc":
			# Zubehör (Sicherung, Werkbank-Material, Werkzeug) kommt per Lieferwagen.
			var aid := str(e.get("id", ""))
			var aprice := _accessory_price(aid)
			if aprice <= 0:
				continue
			var room := _accessory_order_room(aid)
			for qi_prev in queue_items:
				if str(qi_prev) == "acc:" + aid:
					room -= 1
			qty = mini(qty, room)
			if qty <= 0:
				continue
			total_cost += float(aprice) * float(qty)
			for _q in range(qty):
				queue_items.append("acc:" + aid)

	var added_parcels: Array = []
	var packed_now := _pack_items_preview(queue_items, added_parcels)
	var order_tier := compute_delivery_tier(packed_now)
	var shipping_fee := float(get_delivery_fee(order_tier, express))
	var grand_total := total_cost + shipping_fee

	if queue_items.is_empty() or money < grand_total:
		for qi in queue_items:
			var qstr := str(qi)
			if qstr.begins_with("build:"):
				pending_build_orders.erase(qstr.substr(6))
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	# Lieferflächen-Limit (max. DELIVERY_ZONE_MAX_CRATES physische Kisten inkl. laufender Lieferungen)
	var needed_slots := 0
	for pe in packed_now:
		if str(pe) != VAN_PARCEL_ITEM:
			needed_slots += 1
	var free_slots := get_delivery_zone_free_slots()
	if needed_slots > free_slots:
		# Angelegte build_orders wieder aufräumen, da Bestellung abgebrochen wurde
		for qi in queue_items:
			var qstr := str(qi)
			if qstr.begins_with("build:"):
				pending_build_orders.erase(qstr.substr(6))
		_rpc_play_sfx.rpc_id(peer_id, "error")
		post_event_f("🚫 Lieferzone zu voll (%d frei, %d Kisten benötigt)! Erst Pakete aus der Einfahrt holen.", [
			free_slots, needed_slots
		], "warn")
		return

	money -= grand_total
	if not checklist_ordered_anything:
		checklist_ordered_anything = true
		_broadcast_checklist()
	if van_phase == "arriving":
		for ap in added_parcels:
			_van_parcel_parts.append(str(ap))
		if not added_parcels.is_empty() and not van_cargo.has(VAN_PARCEL_ITEM):
			van_cargo.push_front(VAN_PARCEL_ITEM)
		for pn in packed_now:
			if str(pn) != VAN_PARCEL_ITEM:
				van_cargo.append(str(pn))
		van_delivery_tier = maxi(van_delivery_tier, compute_delivery_tier(van_cargo))
		order_tier = van_delivery_tier
	else:
		for qi in queue_items:
			pending_delivery_items.append(str(qi))
		if express:
			pending_delivery_express = true
			scheduled_delivery_hour = -1
			scheduled_delivery_day = 0
		elif scheduled_delivery_hour < 0:
			var next_slot := get_next_delivery_slot()
			scheduled_delivery_day = int(next_slot["day"])
			scheduled_delivery_hour = int(next_slot["hour"])

	_broadcast_van_state()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("cash")
	var tmeta: Dictionary = DELIVERY_TIER_META.get(order_tier, DELIVERY_TIER_META[1])
	if express or van_phase == "arriving":
		post_event_f("🛒 %s bestellte %d Artikel ($%.0f + $%.0f Express-Lieferung) — %s %s ist sofort unterwegs!", [
			NetworkManager.get_player_name(peer_id), queue_items.size(), total_cost, shipping_fee,
			str(tmeta["icon"]), str(tmeta["name"])
		], "good")
	else:
		post_event_f("🛒 %s bestellte %d Artikel ($%.0f + $%.0f Versand) — %s %s kommt im Lieferfenster %s!", [
			NetworkManager.get_player_name(peer_id), queue_items.size(), total_cost, shipping_fee,
			str(tmeta["icon"]), str(tmeta["name"]), get_scheduled_delivery_label()
		], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_sell_inventory_part(part_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	var stock := int(parts_inventory.get(part_id, 0))
	if stock <= 0:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var cat := HardwareCatalog.find_part_category(part_id)
	var pd := HardwareCatalog.get_part(cat, part_id)
	var refund := maxi(5, int(roundf(float(pd.get("cost", 0)) * 0.60)))
	parts_inventory[part_id] = stock - 1
	if int(parts_inventory[part_id]) <= 0:
		parts_inventory.erase(part_id)
	money += float(refund)
	_broadcast_inventory()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("sell")
	post_event_f("💰 %s verkaufte %s aus dem Lager (+$%d).", [
		NetworkManager.get_player_name(peer_id), str(pd.get("name", part_id)), refund
	], "good")


## Höchstlänge eines selbst vergebenen Rack-Namens.
const RACK_NAME_MAX_LEN := 24


## Anzeigename eines Racks: eigener Name oder „Rack N“ (ohne interne Debug-IDs).
func get_rack_display_name(rack_id: String) -> String:
	var shown := ""
	if racks.has(rack_id):
		shown = str((racks[rack_id] as Dictionary).get("custom_name", ""))
	if shown.is_empty():
		var num := rack_id.get_slice("_", rack_id.get_slice_count("_") - 1)
		shown = ("Rack %s" % num) if num.is_valid_int() else rack_id
	return shown


## Entfernt Steuerzeichen und kürzt auf RACK_NAME_MAX_LEN.
func _sanitize_rack_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		if ch.unicode_at(0) >= 32:
			out += ch
	return out.strip_edges().left(RACK_NAME_MAX_LEN)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_rename_rack(rack_id: String, new_name: String) -> void:
	if not multiplayer.is_server():
		return
	if not racks.has(rack_id):
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "rename", 6, 10.0):
		return
	var r: Dictionary = racks[rack_id]
	var filtered := SecurityGuard.sanitize_label(new_name, RACK_NAME_MAX_LEN, "")
	if not new_name.strip_edges().is_empty() and filtered.is_empty():
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var clean := _sanitize_rack_name(filtered.left(RACK_NAME_MAX_LEN * 4))
	if clean == str(r.get("custom_name", "")):
		return
	var old_name := get_rack_display_name(rack_id)
	r["custom_name"] = clean
	_broadcast_racks()
	post_event_f("%s hat %s in %s umbenannt.", [NetworkManager.get_player_name(peer_id), old_name, get_rack_display_name(rack_id)], "info")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_set_rack_rental(rack_id: String, rental_type: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not racks.has(rack_id) or not HardwareCatalog.RENTAL_PROFILES.has(rental_type):
		return
	var r: Dictionary = racks[rack_id]
	var services := _get_rack_services(r)
	var pname := str(NetworkManager.get_player_name(peer_id))

	# "none" beendet alle Dienste. Jeder andere Dienst wird an- oder ausgeschaltet,
	# so kann ein Rack mehrere Dienste gleichzeitig vermieten.
	if rental_type == "none":
		if services.is_empty():
			return
		services.clear()
		post_event_f("%s beendete alle Vermietungen von %s.", [pname, get_rack_display_name(rack_id)], "info")
	else:
		var prof: Dictionary = HardwareCatalog.RENTAL_PROFILES[rental_type]
		var idx := _find_service(services, rental_type)
		if idx >= 0:
			var gone: Dictionary = services[idx]
			services.remove_at(idx)
			post_event_f("%s beendete %s (%s) auf %s.", [pname, str(prof["short"]), str(gone.get("customer", "")), get_rack_display_name(rack_id)], "info")
		else:
			if services.size() >= MAX_SERVICES_PER_RACK:
				_rpc_play_sfx.rpc_id(peer_id, "error")
				post_event_f("%s hat schon %d Dienste. Beende erst einen, bevor du einen neuen startest.", [get_rack_display_name(rack_id), MAX_SERVICES_PER_RACK], "warn")
				return
			var cname := HardwareCatalog.pick_customer_name(rental_type, _next_entity_num + racks.size() + day_number + services.size())
			var start_users := _start_users_for(rental_type)
			services.append({"type": rental_type, "customer": cname, "users": start_users, "trend": 0.0})
			if services.size() == 1:
				r["satisfaction"] = 95.0
				r["grace_timer"] = 18.0
			else:
				r["grace_timer"] = maxf(float(r.get("grace_timer", 0.0)), 10.0)
			post_event_f("🤝 %s vermietet %s als %s an %s (%d Start-User, Ruf: %s)!", [
				pname, get_rack_display_name(rack_id), str(prof["short"]), cname, int(start_users), get_reputation_label()
			], "good")

	_sync_rack_rental_fields(r)
	_clear_tickets_for_rack(rack_id)
	if not active_call.is_empty() and str(active_call.get("rack_id", "")) == rack_id:
		active_call.clear()
		_broadcast_call()
	_rpc_play_sfx.rpc("cash")
	_broadcast_racks()
	_broadcast_tickets()
	_broadcast_sim_tick()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_reply_ticket(ticket_id: String, action: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not support_tickets.has(ticket_id):
		return
	var t: Dictionary = support_tickets[ticket_id]
	var rid := str(t.get("rack_id", ""))

	match action:
		"reassure":
			if bool(t.get("reassured", false)):
				return
			t["reassured"] = true
			if racks.has(rid):
				racks[rid]["satisfaction"] = minf(100.0, float(racks[rid].get("satisfaction", 70.0)) + 12.0)
				racks[rid]["grace_timer"] = maxf(float(racks[rid].get("grace_timer", 0.0)), 45.0)
			_rpc_play_sfx.rpc("ticket_notify")
			post_event_f("⌨ %s antwortete auf Ticket %s — Kunde beruhigt (+45s Zeit zum Aufrüsten).", [NetworkManager.get_player_name(peer_id), ticket_id], "info")
		"compensate":
			if bool(t.get("compensated", false)) or money < 60.0:
				_rpc_play_sfx.rpc_id(peer_id, "error")
				return
			money -= 60.0
			t["compensated"] = true
			if racks.has(rid):
				racks[rid]["satisfaction"] = minf(100.0, float(racks[rid].get("satisfaction", 60.0)) + 24.0)
				racks[rid]["grace_timer"] = maxf(float(racks[rid].get("grace_timer", 0.0)), 75.0)
			_rpc_play_sfx.rpc("cash")
			post_event_f("💰 %s gewährte $60 Rabatt für Ticket %s (+24%% Zufriedenheit).", [NetworkManager.get_player_name(peer_id), ticket_id], "good")
		"resolve":
			if not is_ticket_issue_fixed(t):
				_rpc_play_sfx.rpc_id(peer_id, "error")
				post_event_f("Problem bei %s besteht noch! Erst Hardware/Kabel/Router beheben.", [get_rack_display_name(rid)], "warn")
				return
			var cname := str(t.get("customer", "Kunde"))
			support_tickets.erase(ticket_id)
			if racks.has(rid):
				racks[rid]["satisfaction"] = minf(100.0, float(racks[rid].get("satisfaction", 80.0)) + 16.0)
			money += 35.0
			_rpc_play_sfx.rpc("cash")
			post_event_f("✅ Ticket %s von %s gelöst! (+$35 Support-Bonus & +16%% Zufriedenheit)", [ticket_id, cname], "good")

	_broadcast_tickets()
	_broadcast_racks()
	_broadcast_sim_tick()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_answer_call() -> void:
	if not multiplayer.is_server() or active_call.is_empty():
		return
	if str(active_call.get("state", "")) != "ringing":
		return
	active_call["state"] = "answered"
	active_call["timer"] = 0.0
	_rpc_play_sfx.rpc("phone_pickup")
	_broadcast_call()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_resolve_call(choice: String) -> void:
	if not multiplayer.is_server() or active_call.is_empty():
		return
	var peer_id := _get_sender_id()
	var rid := str(active_call.get("rack_id", ""))
	var cname := str(active_call.get("customer", "Kunde"))
	match choice:
		"upgrade_promise":
			if racks.has(rid):
				racks[rid]["satisfaction"] = minf(100.0, float(racks[rid].get("satisfaction", 60.0)) + 14.0)
				racks[rid]["grace_timer"] = maxf(float(racks[rid].get("grace_timer", 0.0)), 60.0)
			post_event_f("📞 %s versprach %s sofortiges Upgrade (+60s Schonfrist).", [NetworkManager.get_player_name(peer_id), cname], "good")
		"restart_compensate":
			if money >= 60.0:
				money -= 60.0
				if racks.has(rid):
					racks[rid]["satisfaction"] = minf(100.0, float(racks[rid].get("satisfaction", 60.0)) + 26.0)
					racks[rid]["grace_timer"] = maxf(float(racks[rid].get("grace_timer", 0.0)), 80.0)
				post_event_f("📞 %s gab %s $60 Gutschrift am Telefon (+26%% Zufriedenheit).", [NetworkManager.get_player_name(peer_id), cname], "good")
			else:
				_rpc_play_sfx.rpc_id(peer_id, "error")
				return
		_:
			if racks.has(rid):
				racks[rid]["grace_timer"] = maxf(float(racks[rid].get("grace_timer", 0.0)), 20.0)
			post_event_f("📞 Anruf von %s beendet.", [cname], "info")

	active_call.clear()
	_call_cooldown = 38.0
	_rpc_play_sfx.rpc("phone_hangup")
	_broadcast_call()
	_broadcast_sim_tick()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_connect_cable(cable_type: String, from_id: String, to_id: String, from_slot: int, to_slot: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if cable_type != "power" and cable_type != "network" and cable_type != "cluster":
		return
	if from_id == to_id:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	if not _is_valid_cable_endpoint(cable_type, from_id) or not _is_valid_cable_endpoint(cable_type, to_id):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	for cid in cables.keys():
		var c: Dictionary = cables[cid]
		if str(c["cable_type"]) == cable_type:
			var a := str(c["from_id"])
			var b := str(c["to_id"])
			if (a == from_id and b == to_id) or (a == to_id and b == from_id):
				_rpc_play_sfx.rpc_id(peer_id, "error")
				return

	if cable_type == "power" and (from_id == WALL_BREAKER_ID or to_id == WALL_BREAKER_ID) \
			and count_cables_on("power", WALL_BREAKER_ID) >= get_max_ports("power", WALL_BREAKER_ID):
		post_event("Der Stromkasten hat nur eine Steckdose. Schließe dort eine Stromleiste an und verteile von ihr weiter.", "warn")
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	if count_cables_on(cable_type, from_id) >= get_max_ports(cable_type, from_id):
		post_event_f("Kein freier %s-Port an %s (Rack-Switch oder Upgrade nötig).", [
			_cable_type_label(cable_type), from_id.to_upper()
		], "warn")
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	if count_cables_on(cable_type, to_id) >= get_max_ports(cable_type, to_id):
		post_event_f("Kein freier %s-Port an %s.", [
			_cable_type_label(cable_type), to_id.to_upper()
		], "warn")
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	var use_from_slot := pick_free_slot(cable_type, from_id, from_slot)
	var use_to_slot := pick_free_slot(cable_type, to_id, to_slot)
	var cab_id := _alloc_id("cable")
	cables[cab_id] = {
		"id": cab_id, "cable_type": cable_type, "from_id": from_id, "to_id": to_id,
		"from_slot": use_from_slot, "to_slot": use_to_slot,
	}
	_recalculate_networks_and_metrics()
	_broadcast_cables()
	_broadcast_racks()
	_broadcast_coolers()
	_broadcast_ups()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("cable")
	var label := "%skabel" % _cable_type_label(cable_type)
	post_event_f("%s verband %s: %s ↔ %s", [NetworkManager.get_player_name(peer_id), label, from_id.to_upper(), to_id.to_upper()], "info")


## Verleihende Racks behalten diesen Anteil ihrer Hardware als Reserve für die eigenen Mieter.
const CLUSTER_LENDER_RESERVE := 0.85
## Ein leihendes Rack holt sich so viel, dass seine Auslastung unter diesem Wert bleibt.
const CLUSTER_BORROW_TARGET := 0.85
const CLUSTER_RESOURCES: Array[String] = ["ram_gb", "cpu_score", "gpu_score", "storage_tb"]


## Racks, die über ein Cluster-Kabel direkt mit rack_id verbunden sind.
func _cluster_neighbors(rack_id: String) -> Array[String]:
	var out: Array[String] = []
	for cid in cables.keys():
		var c: Dictionary = cables[cid]
		if str(c.get("cable_type", "")) != "cluster":
			continue
		var a := str(c.get("from_id", ""))
		var b := str(c.get("to_id", ""))
		if a == rack_id and racks.has(b):
			out.append(b)
		elif b == rack_id and racks.has(a):
			out.append(a)
	return out


## Freie Hardware je Cluster-Rack aus der Auslastung des letzten Ticks.
## Racks ohne Strom, ohne laufende Server, mit Brand oder überlasteter PSU verleihen nichts,
## ebenso Racks, die selbst gerade leihen.
func _compute_cluster_spare() -> Dictionary:
	var spare: Dictionary = {}
	for rid in racks.keys():
		var rack_id := str(rid)
		if count_cables_on("cluster", rack_id) == 0:
			continue
		var r: Dictionary = racks[rid]
		if not bool(r.get("powered", false)) or _rack_has_fire(r):
			continue
		var hw := get_rack_hardware_summary(rack_id)
		if int(hw["active_servers"]) <= 0 or bool(hw["psu_overloaded"]):
			continue
		var m: Dictionary = r["metrics"] if r.get("metrics") is Dictionary else {}
		var lent_last: Variant = m.get("cluster_borrowed", {})
		if lent_last is Dictionary and not (lent_last as Dictionary).is_empty():
			continue
		var has_tenants := not _get_rack_services(r).is_empty()
		var used_frac := {
			"ram_gb": float(m.get("ram_pct", 0.0)) / 100.0,
			"cpu_score": float(m.get("cpu_pct", 0.0)) / 100.0,
			"gpu_score": float(m.get("gpu_pct", 0.0)) / 100.0,
			"storage_tb": float(m.get("storage_pct", 0.0)) / 100.0,
		}
		var free: Dictionary = {}
		for key in CLUSTER_RESOURCES:
			var total := float(hw[key])
			var used := total * float(used_frac[key]) if has_tenants else 0.0
			free[key] = maxf(0.0, total * CLUSTER_LENDER_RESERVE - used)
		spare[rack_id] = free
	return spare


## Ergänzt hw um geliehene Kapazität der Nachbar-Racks und verbraucht sie in spare.
## Gibt die geliehenen Mengen je Ressource zurück (leer, wenn nichts geliehen wurde).
func _borrow_cluster_capacity(rack_id: String, hw: Dictionary, users: int, prof: Dictionary, spare: Dictionary) -> Dictionary:
	var borrowed: Dictionary = {}
	var neighbors := _cluster_neighbors(rack_id)
	if neighbors.is_empty():
		return borrowed
	var needs := {
		"ram_gb": float(users) * float(prof["ram_gb_per_user"]),
		"cpu_score": float(users) * float(prof["cpu_per_user"]),
		"gpu_score": float(users) * float(prof["gpu_per_user"]),
		"storage_tb": float(users) * float(prof["storage_tb_per_user"]),
	}
	for key in CLUSTER_RESOURCES:
		var want := float(needs[key]) / CLUSTER_BORROW_TARGET - float(hw[key])
		if want <= 0.0:
			continue
		var got := 0.0
		for nid in neighbors:
			if not spare.has(nid):
				continue
			var ns: Dictionary = spare[nid]
			var take := minf(want - got, float(ns.get(key, 0.0)))
			if take <= 0.0:
				continue
			ns[key] = float(ns[key]) - take
			got += take
			if got >= want:
				break
		if got > 0.0:
			hw[key] = float(hw[key]) + got
			borrowed[key] = got
	return borrowed


func _cable_type_label(cable_type: String) -> String:
	match cable_type:
		"power":
			return "Strom"
		"cluster":
			return "Cluster"
		_:
			return "Netzwerk"


func _is_valid_cable_endpoint(cable_type: String, endpoint_id: String) -> bool:
	# Cluster-Kabel verbinden nur Racks untereinander.
	if cable_type == "cluster":
		return racks.has(endpoint_id)
	if cable_type == "power":
		if endpoint_id == WALL_BREAKER_ID:
			return true
		if endpoint_id == HALL_C_BREAKER_ID and room_level >= 2:
			return true
		if endpoint_id == HALL_NORD_BREAKER_ID and halle_nord_owned:
			return true
		# Das Goldis Innengerät hat keine Strombuchse.
		return racks.has(endpoint_id) or (coolers.has(endpoint_id) and not is_indoor_unit(endpoint_id)) or ups_units.has(endpoint_id) or is_power_strip_decor(endpoint_id)
	else:
		if endpoint_id == WALL_ROUTER_ID:
			return true
		if endpoint_id == HALL_C_ROUTER_ID and room_level >= 2:
			return true
		if endpoint_id == HALL_NORD_ROUTER_ID and halle_nord_owned:
			return true
		return racks.has(endpoint_id) or is_lan_strip_decor(endpoint_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_disconnect_cable_slot(cable_type: String, endpoint_id: String, slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var target_cid := ""
	if slot_idx >= 0:
		var smap := get_cable_slot_map(cable_type, endpoint_id)
		for cid in smap.keys():
			if int(smap[cid]) == slot_idx and cables.has(cid):
				target_cid = str(cid)
				break
	if target_cid == "":
		_rpc_req_disconnect_cables_on(cable_type, endpoint_id)
		return
	cables.erase(target_cid)
	_recalculate_networks_and_metrics()
	_broadcast_cables()
	_broadcast_racks()
	_broadcast_coolers()
	_broadcast_ups()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("cable_cut")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_disconnect_cables_on(cable_type: String, endpoint_id: String) -> void:
	if not multiplayer.is_server():
		return
	var to_remove: Array = []
	for cid in cables.keys():
		var c: Dictionary = cables[cid]
		if str(c["cable_type"]) == cable_type:
			if str(c["from_id"]) == endpoint_id or str(c["to_id"]) == endpoint_id:
				to_remove.append(cid)
	if to_remove.is_empty():
		return
	cables.erase(to_remove[to_remove.size() - 1])
	_recalculate_networks_and_metrics()
	_broadcast_cables()
	_broadcast_racks()
	_broadcast_coolers()
	_broadcast_ups()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("cable_cut")


## Zufällige Netzausfälle der Stadtwerke (nur Host). Der Hauptschalter fällt ab, die USV überbrückt,
## und nach Ablauf kommt das Netz von selbst zurück.
func _tick_grid_outage(dt: float) -> void:
	if grid_outage_left > 0.0:
		grid_outage_left = maxf(0.0, grid_outage_left - dt)
		if grid_outage_left <= 0.0:
			_end_grid_outage()
		return
	if day_number < GRID_OUTAGE_FIRST_DAY:
		return
	if _grid_outage_cooldown < 0.0:
		_grid_outage_cooldown = _roll_grid_outage_cooldown()
	_grid_outage_cooldown -= dt
	if _grid_outage_cooldown <= 0.0:
		_grid_outage_cooldown = _roll_grid_outage_cooldown()
		_start_grid_outage(randf_range(GRID_OUTAGE_MIN_SEC, GRID_OUTAGE_MAX_SEC))


func _roll_grid_outage_cooldown() -> float:
	return randf_range(0.8, 2.2) * float(DAY_LENGTH_SECONDS)


## Restdauer des Netzausfalls in Spielminuten (für HUD und Hinweise).
func get_grid_outage_minutes() -> int:
	if grid_outage_left <= 0.0:
		return 0
	return maxi(1, roundi(grid_outage_left / float(DAY_LENGTH_SECONDS) * 1440.0))


func _broadcast_power_change() -> void:
	_recalculate_networks_and_metrics()
	_broadcast_racks()
	_broadcast_coolers()
	_broadcast_ups()
	_broadcast_sim_tick()


func _start_grid_outage(duration: float) -> void:
	# 2-MVA Notstrom-Dieselgenerator übernimmt bei Netzausfall komplett unterbrechungsfrei!
	if has_building_upgrade("upg_diesel_gen"):
		post_event("⚡ Stadtwerke-Netzausfall erkannt — 2-MVA Notstrom-Dieselgenerator hat automatisch übernommen (0 s Ausfallzeit)!", "good")
		_rpc_play_sfx.rpc("save")
		return
	_grid_breaker_restore = breaker_on
	grid_outage_left = duration
	breaker_on = false
	overload_timer = 0.0
	_broadcast_power_change()
	_rpc_play_sfx.rpc("power_down")
	var minutes := get_grid_outage_minutes()
	if ups_backup_active:
		_rpc_play_sfx.rpc("ups_beep")
		post_event_f("NETZAUSFALL! Die Stadtwerke melden eine Störung (ca. %d Min.). USV-Notstrom hat übernommen.", [minutes], "warn")
	else:
		post_event_f("NETZAUSFALL! Die Stadtwerke melden eine Störung (ca. %d Min.). Ohne USV steht alles still.", [minutes], "alert")


func _end_grid_outage() -> void:
	grid_outage_left = 0.0
	var restore := _grid_breaker_restore and has_working_fuse()
	_grid_breaker_restore = false
	if restore:
		breaker_on = true
		overload_timer = 0.0
	_broadcast_power_change()
	if restore:
		_rpc_play_sfx.rpc("breaker_on")
		post_event("Netz wieder da: Die Stadtwerke haben die Störung behoben, der Strom läuft wieder.", "good")
	else:
		post_event("Netz wieder da. Der Hauptschalter ist aus und muss von Hand eingeschaltet werden.", "info")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_toggle_breaker() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not breaker_on and grid_outage_left > 0.0:
		# Wunsch merken: Nach dem Netzausfall schaltet der Hauptschalter wieder ein.
		_grid_breaker_restore = true
		_rpc_play_sfx.rpc_id(peer_id, "error")
		post_event("Hauptschalter bleibt aus: Netzausfall der Stadtwerke. Der Strom kommt automatisch zurück.", "warn")
		return
	if not breaker_on and not has_working_fuse():
		_rpc_play_sfx.rpc_id(peer_id, "error")
		post_event("Hauptschalter lässt sich nicht einschalten: Im Sicherungskasten steckt keine intakte Sicherung.", "warn")
		return
	breaker_on = not breaker_on
	overload_timer = 0.0
	_recalculate_networks_and_metrics()
	_broadcast_racks()
	_broadcast_coolers()
	_broadcast_ups()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("breaker_on" if breaker_on else "breaker_trip")
	post_event_f("%s hat die Hauptsicherung EINGESCHALTET." if breaker_on else "%s hat die Hauptsicherung ABGESCHALTET.", [
		NetworkManager.get_player_name(peer_id),
	], "good" if breaker_on else "warn")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_pickup_extinguisher(ext_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if is_player_holding_anything(peer_id) or not extinguishers.has(ext_id) or int((extinguishers[ext_id] as Dictionary)["held_by"]) != 0:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var e: Dictionary = extinguishers[ext_id]
	e["held_by"] = peer_id
	e["slot"] = get_active_slot(peer_id)
	e["station"] = ""
	_broadcast_extinguishers()
	_rpc_play_sfx.rpc_id(peer_id, "pickup")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_hang_extinguisher(station: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	var ext_id := get_held_extinguisher(peer_id)
	if ext_id == "" or not EXT_STATIONS.has(station) or get_extinguisher_at_station(station) != "":
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var e: Dictionary = extinguishers[ext_id]
	e["held_by"] = 0
	e["station"] = station
	_broadcast_extinguishers()
	_rpc_play_sfx.rpc_id(peer_id, "drop")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_drop_extinguisher(pos: Vector3, yaw: float) -> void:
	if not multiplayer.is_server():
		return
	if not SecurityGuard.is_finite_vec3(pos) or not SecurityGuard.is_finite_float(yaw):
		return
	var peer_id := _get_sender_id()
	var ext_id := get_held_extinguisher(peer_id)
	if ext_id == "":
		return
	var e: Dictionary = extinguishers[ext_id]
	e["held_by"] = 0
	e["station"] = ""
	e["pos"] = _clamp_drop_pos(pos)
	e["yaw"] = fposmod(yaw, TAU)
	_broadcast_extinguishers()
	_rpc_play_sfx.rpc_id(peer_id, "drop")


func _broadcast_extinguishers() -> void:
	if multiplayer.is_server():
		for id in extinguishers.keys():
			_ext_sync_fill[id] = float((extinguishers[id] as Dictionary)["fill"])
		_rpc_sync_extinguishers.rpc(extinguishers.duplicate(true))


## Im Halter füllen sich die Löscher wieder auf (nur Host).
func _update_extinguishers(delta: float) -> void:
	var dirty := false
	for id in extinguishers.keys():
		var e: Dictionary = extinguishers[id]
		var fill := float(e["fill"])
		if int(e["held_by"]) == 0 and str(e["station"]) != "" and fill < 1.0:
			fill = minf(1.0, fill + delta / EXT_REFILL_SECONDS)
			e["fill"] = fill
			if fill >= 1.0:
				dirty = true
		if absf(fill - float(_ext_sync_fill.get(id, 1.0))) >= 0.04:
			dirty = true
	if dirty:
		_broadcast_extinguishers()


func request_set_active_slot(slot: int) -> void:
	# Lokal sofort setzen, damit Prüfungen direkt nach dem Tastendruck den neuen Slot sehen.
	player_active_slot[multiplayer.get_unique_id()] = slot
	_rpc_req_set_active_slot.rpc_id(1, slot)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_set_active_slot(slot: int) -> void:
	if not multiplayer.is_server():
		return
	if slot < 1 or slot > SLOT_COUNT:
		return
	var peer_id := _get_sender_id()
	player_active_slot[peer_id] = slot
	_rpc_sync_active_slot.rpc(peer_id, slot)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_active_slot(peer_id: int, slot: int) -> void:
	player_active_slot[peer_id] = slot


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_spray_extinguisher(rack_id: String, slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "extinguish", 25, 2.0):
		return
	var ext_id := get_held_extinguisher(peer_id)
	if ext_id == "":
		return
	var ext: Dictionary = extinguishers[ext_id]
	if float(ext["fill"]) <= 0.0:
		return
	ext["fill"] = maxf(0.0, float(ext["fill"]) - EXT_SPRAY_TICK / EXT_SPRAY_SECONDS)
	if float(ext["fill"]) <= 0.0:
		_broadcast_extinguishers()
		post_event_f("%s: Der Feuerlöscher ist leer. Im Wandhalter füllt er sich wieder auf.", [NetworkManager.get_player_name(peer_id)], "warn")
	if not racks.has(rack_id):
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	if str(slot["state"]) != "burning":
		return
	slot["fire_level"] = maxf(0.0, float(slot["fire_level"]) - 0.20)
	if float(slot["fire_level"]) <= 0.01:
		slot["state"] = "crashed"
		slot["repair_progress"] = 0.0
		slot["faulty_part"] = ""
		slot["diagnosed"] = false
		racks[rack_id]["temp"] = minf(float(racks[rack_id]["temp"]), 55.0)
		post_event_f("%s hat den Brand in %s Slot %d gelöscht! Jetzt reparieren [E].", [
			NetworkManager.get_player_name(peer_id), get_rack_display_name(rack_id), slot_idx + 1
		], "good")
		_rpc_play_sfx.rpc("repair")
	_broadcast_racks()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_repair_slot(rack_id: String, slot_idx: int, amount: float) -> void:
	if not multiplayer.is_server():
		return
	if not SecurityGuard.is_finite_float(amount):
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "repair", 25, 2.0):
		return
	if not racks.has(rack_id):
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	if str(slot["state"]) != "crashed":
		return
	# Erst das defekte Teil finden, dann reparieren.
	if is_slot_awaiting_diagnosis(slot):
		return
	var speed_mult := get_repair_speed_multiplier()
	var used_kit := false
	if maint_kits > 0 and float(slot["repair_progress"]) <= 0.001:
		maint_kits -= 1
		used_kit = true
	if used_kit or bool(slot.get("_using_kit", false)):
		slot["_using_kit"] = true
		speed_mult *= 2.2
	slot["repair_progress"] = minf(1.0, float(slot["repair_progress"]) + clampf(amount * speed_mult, 0.0, 1.0))
	if float(slot["repair_progress"]) >= 1.0:
		var full_ok := bool(slot.get("_using_kit", false))
		slot["state"] = "ok"
		slot["offline"] = true # nach der Reparatur neu hochfahren
		slot["repair_progress"] = 0.0
		slot["faulty_part"] = ""
		slot["diagnosed"] = false
		slot.erase("_using_kit")
		slot["dust_level"] = 0.0 if full_ok else 35.0
		slot["thermal_health"] = 100.0 if full_ok else 72.0
		# Schnell geflickt ist nicht ordentlich repariert: volle Qualität gibt es nur an der Werkbank.
		slot["build_quality"] = mini(get_build_quality(slot), RACK_REPAIR_QUALITY_KIT if full_ok else RACK_REPAIR_QUALITY)
		_recalculate_networks_and_metrics()
		_broadcast_sim_tick()
		var diag_str := tr("notdürftig mit Ersatzteil-Kit (Bauqualität höchstens 70 %)") if full_ok else tr("notdürftig (Bauqualität höchstens 50 %)")
		post_event_f("%s hat %s Slot %d %s repariert!", [
			NetworkManager.get_player_name(peer_id), get_rack_display_name(rack_id), slot_idx + 1, diag_str
		], "good")
		_rpc_play_sfx.rpc("repair")
	_broadcast_racks()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_toggle_contract(contract_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not contracts.has(contract_id):
		return
	var c: Dictionary = contracts[contract_id]
	var now_active := not bool(c["active"])
	if now_active and get_active_contract_count() >= 4:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	c["active"] = now_active
	c["status"] = "ok" if now_active else "idle"
	if bool(c.get("random", false)):
		if now_active:
			c["days_left"] = int(c.get("duration_days", RANDOM_CONTRACT_DURATION_MIN))
		else:
			# Ein gekündigter befristeter Vertrag ist weg und kann nicht neu angenommen werden.
			contracts.erase(contract_id)
	_recalculate_networks_and_metrics()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("click")
	post_event_f("%s hat Vertrag '%s' angenommen." if now_active else "%s hat Vertrag '%s' gekündigt.", [
		NetworkManager.get_player_name(peer_id), str(c["title"]),
	], "good" if now_active else "info")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_upgrade_power() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if power_fuse_stock > 0:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		post_event("Die Drehsicherung liegt schon im Lager. Setze sie am Sicherungskasten in F2 ein.", "warn")
		return
	if _power_fuse_on_way():
		_rpc_play_sfx.rpc_id(peer_id, "error")
		post_event("Die Drehsicherung ist schon bestellt und kommt mit dem Lieferwagen.", "warn")
		return
	if power_tier + 1 >= POWER_TIERS.size():
		return
	var next_tier: Dictionary = POWER_TIERS[power_tier + 1]
	var cost := float(next_tier["cost"])
	if money < cost:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money -= cost
	# Wie beim Warenkorb: Zubehör kommt ins Sammelpaket des Lieferwagens.
	if van_phase != "arriving":
		pending_delivery_items.append(POWER_FUSE_ACC)
	else:
		_van_parcel_parts.append(POWER_FUSE_ACC)
		if not van_cargo.has(VAN_PARCEL_ITEM):
			van_cargo.push_front(VAN_PARCEL_ITEM)
	_broadcast_van_state()
	_broadcast_fuses()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("cash")
	post_event_f("%s hat eine Drehsicherung für %s bestellt. Sie kommt mit dem Lieferwagen im Sammelpaket.", [
		NetworkManager.get_player_name(peer_id), str(next_tier["label"])
	], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_research(branch: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not get_research_block_reason(branch).is_empty():
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var cost := float(get_research_cost(branch))
	if money < cost:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money -= cost
	var new_level := get_research_level(branch) + 1
	research_levels[branch] = new_level
	_recalculate_networks_and_metrics()
	_broadcast_racks()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("upgrade")
	var node: Dictionary = RESEARCH_TREE[branch]
	post_event_f("%s erforschte %s Stufe %d!", [
		NetworkManager.get_player_name(peer_id), str(node["label"]), new_level
	], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_upgrade_router() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if router_tier + 1 >= ROUTER_TIERS.size():
		return
	var next_r: Dictionary = ROUTER_TIERS[router_tier + 1]
	var cost := float(next_r["cost"])
	if money < cost:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money -= cost
	router_tier += 1
	_recalculate_networks_and_metrics()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("upgrade")
	post_event_f("%s installierte neuen Router: %s!", [
		NetworkManager.get_player_name(peer_id), str(next_r["label"])
	], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_expand_room() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "expand", 4, 5.0):
		return
	if not is_destructive_action_allowed(peer_id):
		_deny_destructive_action(peer_id, "die Halle ausbauen")
		return
	if room_level >= 2:
		return
	var cost := float(HALL_B_COST if room_level == 0 else HALL_C_COST)
	if money < cost:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money -= cost
	room_level += 1
	_rpc_sync_room_level.rpc(room_level)
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("upgrade")
	if room_level == 1:
		post_event_f("%s schaltete HALLE B (Garagen-Anbau) frei! +63 m² Stellfläche!", [NetworkManager.get_player_name(peer_id)], "good")
	else:
		post_event_f("%s schaltete HALLE C (Enterprise-Flügel) inkl. eigenem Strom- & Glasfaser-Verteiler frei!", [NetworkManager.get_player_name(peer_id)], "good")
	_check_company_milestones()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_upgrade_ai_platform() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if ai_platform_level + 1 >= AI_TIERS.size():
		return
	var next_ai: Dictionary = AI_TIERS[ai_platform_level + 1]
	if money < float(next_ai["cost"]) or total_ram_gb < int(next_ai.get("min_ram_gb", 0)) or total_gpu_score < int(next_ai.get("min_gpu", 0)):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money -= float(next_ai["cost"])
	ai_platform_level += 1
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("upgrade")
	post_event_f("%s startete %s — freie Server-Kapazität verdient jetzt live Geld!", [
		NetworkManager.get_player_name(peer_id), str(next_ai["label"])
	], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_mitigate_ddos() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not ddos_active:
		return
	ddos_active = false
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("repair")
	post_event_f("%s hat den DDoS-Angriff erfolgreich abgewehrt!", [NetworkManager.get_player_name(peer_id)], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_grab_cart(cart_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if is_player_holding_anything(peer_id) or not carts.has(cart_id):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	if int(carts[cart_id].get("pushed_by", 0)) != 0:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	carts[cart_id]["pushed_by"] = peer_id
	_broadcast_carts()
	_rpc_play_sfx.rpc_id(peer_id, "pickup")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_release_cart(pos: Vector3, rot_y: float) -> void:
	if not multiplayer.is_server():
		return
	if not SecurityGuard.is_finite_vec3(pos) or not SecurityGuard.is_finite_float(rot_y):
		return
	var peer_id := _get_sender_id()
	var cart := get_player_pushed_cart(peer_id)
	if cart.is_empty():
		return
	var cid := str(cart["id"])
	if halle_nord_owned and pos.z < -100.0:
		carts[cid]["pos"] = Vector3(clampf(pos.x, -9.4, 9.4), 0.0, clampf(pos.z, HALLE_NORD_ORIGIN.z - 5.2, HALLE_NORD_ORIGIN.z + 12.0))
	else:
		var max_x := 4.9 if room_level == 0 else (11.8 if room_level == 1 else 20.8)
		carts[cid]["pos"] = Vector3(clampf(pos.x, -4.9, max_x), 0.0, clampf(pos.z, -3.9, 9.2))
	carts[cid]["rot_y"] = rot_y
	carts[cid]["pushed_by"] = 0
	_broadcast_carts()
	_rpc_play_sfx.rpc_id(peer_id, "drop")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_load_held_crate_to_cart(cart_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	var held := get_player_held_crate(peer_id)
	if held.is_empty() or not carts.has(cart_id):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var items: Array = carts[cart_id]["items"]
	if items.size() >= CART_MAX_ITEMS:
		post_event_f("Rollwagen ist voll (%d/%d Kartons)!", [CART_MAX_ITEMS, CART_MAX_ITEMS], "warn")
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var item_type := str(held["item_type"])
	_cart_store(cart_id, held)
	crates.erase(str(held["id"]))
	items.append(item_type)
	_broadcast_crates()
	_broadcast_carts()
	_rpc_play_sfx.rpc("cart_load")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_load_ground_crate_to_pushed_cart(crate_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	var cart := get_player_pushed_cart(peer_id)
	if cart.is_empty() or not crates.has(crate_id):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	if int(crates[crate_id].get("held_by", 0)) != 0:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var cid := str(cart["id"])
	var items: Array = carts[cid]["items"]
	if items.size() >= CART_MAX_ITEMS:
		post_event_f("Rollwagen ist voll (%d/%d Kartons)!", [CART_MAX_ITEMS, CART_MAX_ITEMS], "warn")
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var item_type := str(crates[crate_id]["item_type"])
	_cart_store(cid, crates[crate_id])
	crates.erase(crate_id)
	items.append(item_type)
	_broadcast_crates()
	_broadcast_carts()
	_rpc_play_sfx.rpc("cart_load")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_unload_cart_to_hands(cart_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if is_player_holding_anything(peer_id) or not carts.has(cart_id):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var items: Array = carts[cart_id]["items"]
	if items.is_empty():
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var full := _cart_take(cart_id, items.size() - 1)
	var item_type := str(items.pop_back())
	var crate_id := _alloc_id("crate")
	var crate: Dictionary = full if str(full.get("item_type", "")) == item_type else {}
	crate.merge({"id": crate_id, "item_type": item_type, "pos": Vector3.ZERO, "held_by": peer_id, "held_slot": get_active_slot(peer_id)}, true)
	crates[crate_id] = crate
	_broadcast_carts()
	_broadcast_crates()
	_rpc_play_sfx.rpc_id(peer_id, "pickup")


## Merkt sich den ganzen Inhalt einer aufgeladenen Kiste (Menge, Bauteile, Akku-Zustand), nicht nur ihre Art.
func _cart_store(cart_id: String, crate: Dictionary) -> void:
	var c: Dictionary = carts[cart_id]
	var items: Array = c["items"]
	var data: Array = c.get("data", []) if c.get("data", []) is Array else []
	data.resize(items.size())
	var copy := crate.duplicate(true)
	for k in ["id", "pos", "held_by", "held_slot", "tech"]:
		copy.erase(k)
	data.append(copy)
	c["data"] = data


func _cart_take(cart_id: String, idx: int) -> Dictionary:
	var c: Dictionary = carts[cart_id]
	var data: Variant = c.get("data", [])
	if not (data is Array) or idx < 0 or idx >= (data as Array).size():
		return {}
	var v: Variant = (data as Array)[idx]
	(data as Array).remove_at(idx)
	return (v as Dictionary).duplicate(true) if v is Dictionary else {}


# ==============================================================================
# HOST -> ALL CLIENTS BROADCASTS
# ==============================================================================

## message ist eine deutsche Vorlage (Übersetzungsschlüssel), args die Werte für ihre Platzhalter.
## Übersetzt wird beim Empfänger, damit jeder Spieler Meldungen in seiner eigenen Sprache sieht.
func post_event(message: String, severity: String = "info", args: Array = []) -> void:
	if multiplayer.is_server():
		_rpc_event_log.rpc(message, severity, args)
	else:
		event_logged.emit(_format_event(message, args), severity)


@rpc("authority", "call_local", "reliable")
func _rpc_event_log(message: String, severity: String, args: Array = []) -> void:
	event_logged.emit(_format_event(message, args), severity)


## Wie post_event, aber mit args vor severity. So wird aus post_event("…" % [a, b], "warn")
## einfach post_event_f("…", [a, b], "warn"), ohne die Klammern umzustellen.
func post_event_f(message: String, args: Array, severity: String = "info") -> void:
	post_event(message, severity, args)


## Übersetzt eine gespeicherte Vorlage mit ihren Werten in der Sprache dieses
## Spielers. Alte Spielstände ohne args liefern ihren Text unverändert.
func format_message(message: String, args: Array = []) -> String:
	return _format_event(message, args)


func _format_event(message: String, args: Array) -> String:
	var template := tr(message)
	if args.is_empty():
		return template
	var tr_args: Array = []
	for v in args:
		if v is String:
			tr_args.append(tr(v))
		elif v is Dictionary and (v as Dictionary).has("text"):
			# Eingebettete Vorlage, z. B. ein Ticket-Titel mit eigenen Werten.
			tr_args.append(_format_event(str(v["text"]), v.get("args", [])))
		else:
			tr_args.append(v)
	return template % tr_args


@rpc("authority", "call_local", "reliable")
func _rpc_play_sfx(sfx_name: String) -> void:
	SfxManager.play(sfx_name)


@rpc("authority", "call_local", "reliable")
func _rpc_daily_bill(day_num: int, bill_amount: int, kwh_used: float) -> void:
	daily_bill_charged.emit(day_num, bill_amount, kwh_used)


func _broadcast_racks() -> void:
	_rpc_sync_racks.rpc(racks)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_racks(data: Dictionary) -> void:
	if not multiplayer.is_server():
		racks = data.duplicate(true)
	racks_changed.emit()


func _broadcast_coolers() -> void:
	_rpc_sync_coolers.rpc(coolers)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_coolers(data: Dictionary) -> void:
	if not multiplayer.is_server():
		coolers = data.duplicate(true)
	coolers_changed.emit()


func _broadcast_ups() -> void:
	_rpc_sync_ups.rpc(ups_units)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_ups(data: Dictionary) -> void:
	if not multiplayer.is_server():
		ups_units = data.duplicate(true)
	ups_changed.emit()


func _broadcast_carts() -> void:
	_rpc_sync_carts.rpc(carts)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_carts(data: Dictionary) -> void:
	if not multiplayer.is_server():
		carts = data.duplicate(true)
	carts_changed.emit()


func _broadcast_crates() -> void:
	_rpc_sync_crates.rpc(crates)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_crates(data: Dictionary) -> void:
	if not multiplayer.is_server():
		crates = data.duplicate(true)
	crates_changed.emit()


func _broadcast_cables() -> void:
	_rpc_sync_cables.rpc(cables)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_cables(data: Dictionary) -> void:
	if not multiplayer.is_server():
		cables = data.duplicate(true)
	cables_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_extinguishers(data: Dictionary) -> void:
	extinguishers = data.duplicate(true)
	extinguisher_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_room_level(lvl: int) -> void:
	room_level = lvl
	room_level_changed.emit()


func _broadcast_inventory() -> void:
	_rpc_sync_inventory.rpc(parts_inventory)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_inventory(data: Dictionary) -> void:
	if not multiplayer.is_server():
		parts_inventory = data.duplicate(true)
	inventory_changed.emit()


# ==============================================================================
# SICHERUNGSKASTEN: Sicherungen kaufen, einsetzen, bei Überlast durchbrennen lassen
# ==============================================================================
func _make_fuse_slots(state: String) -> Array:
	var arr: Array = []
	for _i in range(FUSE_SLOT_COUNT):
		arr.append(state)
	return arr


func _sanitize_fuses(data: Variant) -> Array:
	if not (data is Array):
		return _make_fuse_slots("ok")
	var src: Array = data
	var arr: Array = []
	for i in range(FUSE_SLOT_COUNT):
		var s := str(src[i]) if i < src.size() else "empty"
		arr.append(s if s == "ok" or s == "blown" else "empty")
	return arr


func count_working_fuses() -> int:
	var n := 0
	for f in breaker_fuses:
		if str(f) == "ok":
			n += 1
	return n


## Der Hauptschalter lässt sich nur einschalten, solange mindestens eine intakte Sicherung steckt.
func has_working_fuse() -> bool:
	return count_working_fuses() > 0


## Die Kastentür muss offen sein, bevor Sicherungen und der Hauptschalter bedient werden können.
func is_breaker_door_open() -> bool:
	return shared_open_panels.has(_panel_key(WALL_BREAKER_ID, "breaker:door"))


func _blow_random_fuse() -> void:
	var ok_idx: Array[int] = []
	for i in range(breaker_fuses.size()):
		if str(breaker_fuses[i]) == "ok":
			ok_idx.append(i)
	if ok_idx.is_empty():
		return
	breaker_fuses[ok_idx[randi() % ok_idx.size()]] = "blown"
	_broadcast_fuses()


func _broadcast_fuses() -> void:
	_rpc_sync_fuses.rpc(breaker_fuses, fuse_stock, power_fuse_stock, _power_fuse_on_way())


@rpc("authority", "call_local", "reliable")
func _rpc_sync_fuses(fuses: Array, stock: int, power_stock: int, power_on_way: bool) -> void:
	if not multiplayer.is_server():
		breaker_fuses = _sanitize_fuses(fuses)
		fuse_stock = maxi(0, stock)
		power_fuse_stock = clampi(power_stock, 0, 1)
		power_fuse_on_way_synced = power_on_way
	fuses_changed.emit()


## Server: sucht die Drehsicherung in allen Lieferwarteschlangen.
func _power_fuse_on_way() -> bool:
	return pending_delivery_items.has(POWER_FUSE_ACC) \
		or van_cargo.has(POWER_FUSE_ACC) \
		or _van_parcel_parts.has(POWER_FUSE_ACC)


## Für die UI: Ist die Drehsicherung bestellt, aber noch nicht geliefert?
func is_power_fuse_on_way() -> bool:
	if multiplayer.is_server():
		return _power_fuse_on_way()
	return power_fuse_on_way_synced


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_buy_fuse() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if money < float(FUSE_PRICE):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money -= float(FUSE_PRICE)
	fuse_stock += 1
	_broadcast_fuses()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("cash")


## Preis eines Zubehörteils aus dem Warenkorb (0 = unbekannte ID).
func _accessory_price(aid: String) -> int:
	match aid:
		"fuse":
			return FUSE_PRICE
		"screw_box":
			return SCREW_BOX_PRICE
		"paste_tube":
			return PASTE_TUBE_PRICE
	if aid.begins_with("tool_") and BENCH_TOOLS.has(aid.substr(5)):
		return int(BENCH_TOOLS[aid.substr(5)]["price"])
	return 0


## Wie viele Stück noch bestellt werden dürfen. Lieferungen, die unterwegs sind, zählen mit.
func _accessory_order_room(aid: String) -> int:
	var key := "acc:" + aid
	var on_way := pending_delivery_items.count(key) + van_cargo.count(key) + _van_parcel_parts.count(key)
	match aid:
		"screw_box":
			return maxi(0, (BENCH_SCREWS_MAX - bench_screws) / SCREW_BOX_COUNT - on_way)
		"paste_tube":
			return maxi(0, int((BENCH_PASTE_MAX - bench_paste) / PASTE_TUBE_USES) - on_way)
	if aid.begins_with("tool_"):
		var tid := aid.substr(5)
		var need := str((BENCH_TOOLS.get(tid, {}) as Dictionary).get("needs", ""))
		var need_ok := need == "" or has_bench_tool(need) or pending_delivery_items.has("acc:tool_" + need) or van_cargo.has("acc:tool_" + need) or _van_parcel_parts.has("acc:tool_" + need)
		return 0 if (has_bench_tool(tid) or on_way > 0 or not need_ok) else 1
	return 20


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_insert_fuse(slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if slot_idx < 0 or slot_idx >= breaker_fuses.size():
		return
	if slot_idx == POWER_FUSE_SLOT and power_fuse_stock > 0:
		_install_power_fuse(peer_id)
		return
	if str(breaker_fuses[slot_idx]) == "ok":
		return
	if fuse_stock <= 0:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		post_event("Keine Sicherung im Lager. Kaufe Sicherungen am PC im Shop unter \"Klima & USV\".", "warn")
		return
	fuse_stock -= 1
	breaker_fuses[slot_idx] = "ok"
	_broadcast_fuses()
	_rpc_play_sfx.rpc("pickup")
	post_event_f("%s hat eine Sicherung in Steckplatz %d eingesetzt.", [
		NetworkManager.get_player_name(peer_id), slot_idx + 1,
	], "good")


## Setzt die gekaufte Drehsicherung in F2 ein: Stromstufe +1, die alte Sicherung landet in der Hand.
func _install_power_fuse(peer_id: int) -> void:
	if power_tier + 1 >= POWER_TIERS.size():
		power_fuse_stock = 0
		_broadcast_fuses()
		return
	if is_player_holding_anything(peer_id):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		post_event("Hände frei machen: Die alte Sicherung wird dir beim Einsetzen in die Hand gegeben.", "warn")
		return
	power_fuse_stock = 0
	power_tier += 1
	var cid := _alloc_id("crate")
	crates[cid] = {"id": cid, "item_type": OLD_FUSE_ITEM, "pos": Vector3.ZERO, "held_by": peer_id, "held_slot": get_active_slot(peer_id)}
	_recalculate_networks_and_metrics()
	_broadcast_fuses()
	_broadcast_crates()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("upgrade")
	post_event_f("%s hat die Drehsicherung in F2 eingesetzt: Stromversorgung jetzt %s!", [
		NetworkManager.get_player_name(peer_id), str(POWER_TIERS[power_tier]["label"])
	], "good")


func _broadcast_tickets() -> void:
	_rpc_sync_tickets.rpc(support_tickets)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_tickets(data: Dictionary) -> void:
	if not multiplayer.is_server():
		support_tickets = data.duplicate(true)
	tickets_changed.emit()


func _broadcast_call() -> void:
	_rpc_sync_call.rpc(active_call)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_call(data: Dictionary) -> void:
	if not multiplayer.is_server():
		active_call = data.duplicate(true)
	call_changed.emit()


func _broadcast_sim_tick() -> void:
	var rack_temps := {}
	for rid in racks.keys():
		var rk: Dictionary = racks[rid]
		rack_temps[rid] = {
			"temp": float(rk["temp"]),
			"powered": bool(rk["powered"]),
			"networked": bool(rk["networked"]),
			"rental_type": str(rk.get("rental_type", "none")),
			"rental_customer": str(rk.get("rental_customer", "")),
			"active_users": int(rk.get("active_users", 0)),
			"satisfaction": float(rk.get("satisfaction", 100.0)),
			"rental_income": float(rk.get("rental_income", 0.0)),
			"metrics": (rk.get("metrics", {}) as Dictionary).duplicate(true),
			"services": (rk.get("services", []) as Array).duplicate(true),
		}
	var cooler_pwr := {}
	for cid in coolers.keys():
		cooler_pwr[cid] = bool(coolers[cid]["powered"])
	var ups_sync := {}
	for uid in ups_units.keys():
		ups_sync[uid] = {
			"connected": bool(ups_units[uid]["connected"]),
			"charge": float(ups_units[uid]["charge"]),
			"discharging": bool(ups_units[uid]["discharging"]),
			"health": get_ups_health(ups_units[uid]),
			"tripped": bool(ups_units[uid].get("tripped", false)),
		}

	var packet := {
		"money": money,
		"breaker_on": breaker_on,
		"grid_outage_left": grid_outage_left,
		"ups_backup_active": ups_backup_active,
		"avg_ups_charge": avg_ups_charge,
		"strip_loads": strip_loads.duplicate(),
		"overload_timer": overload_timer,
		"power_tier": power_tier,
		"router_tier": router_tier,
		"research_levels": research_levels.duplicate(),
		"company_milestones_reached": company_milestones_reached,
		"company_level": company_level,
		"ai_platform_level": ai_platform_level,
		"ddos_active": ddos_active,
		"day_number": day_number,
		"time_of_day": time_of_day,
		"clock_scale": clock_scale,
		"daily_kwh": daily_kwh,
		"last_daily_bill": last_daily_bill,
		"electricity_rate": electricity_rate,
		"last_bill_rate": last_bill_rate,
		"room_temp": room_temp,
		"total_watts": total_watts,
		"max_watts": max_watts,
		"total_compute": total_compute,
		"raw_compute": raw_compute,
		"max_bandwidth_cu": max_bandwidth_cu,
		"used_compute": used_compute,
		"revenue_bonus_mult": revenue_bonus_mult,
		"ai_revenue_per_sec": ai_revenue_per_sec,
		"total_rental_income_per_cycle": total_rental_income_per_cycle,
		"reputation": reputation,
		"total_ram_gb": total_ram_gb,
		"total_cpu_score": total_cpu_score,
		"total_gpu_score": total_gpu_score,
		"total_storage_tb": total_storage_tb,
		"used_bandwidth_mbps": used_bandwidth_mbps,
		"max_bandwidth_mbps": max_bandwidth_mbps,
		"next_payout_in": next_payout_in,
		"contracts": contracts,
		"rack_temps": rack_temps,
		"cooler_pwr": cooler_pwr,
		"ups_sync": ups_sync,
		"weather_state": weather_state,
		"airflow_bonus": airflow_bonus,
		"cable_mgmt_bonus": cable_mgmt_bonus,
		"career_completed": career_completed,
		"active_team_order": active_team_order,
		"halle_nord_owned": halle_nord_owned,
		"delivery_target_site": delivery_target_site,
		"building_upgrades": building_upgrades.duplicate(true),
		"active_constructions": active_constructions.duplicate(true),
		"decor_items": decor_items.duplicate(true),
		"maint_kits": maint_kits,
	}
	_rpc_sync_sim_tick.rpc(packet)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_sim_tick(packet: Dictionary) -> void:
	if not multiplayer.is_server():
		money = float(packet["money"])
		breaker_on = bool(packet["breaker_on"])
		ups_backup_active = bool(packet["ups_backup_active"])
		grid_outage_left = float(packet.get("grid_outage_left", 0.0))
		avg_ups_charge = float(packet["avg_ups_charge"])
		if packet.get("strip_loads", null) is Dictionary:
			strip_loads = (packet["strip_loads"] as Dictionary).duplicate()
			strip_loads_changed.emit()
		overload_timer = float(packet["overload_timer"])
		power_tier = int(packet["power_tier"])
		router_tier = clampi(int(packet.get("router_tier", 0)), 0, ROUTER_TIERS.size() - 1)
		research_levels = _sanitize_research(packet.get("research_levels", {}))
		ai_platform_level = int(packet["ai_platform_level"])
		company_milestones_reached = int(packet.get("company_milestones_reached", company_milestones_reached))
		company_level = int(packet.get("company_level", company_level))
		ddos_active = bool(packet["ddos_active"])
		day_number = int(packet["day_number"])
		clock_scale = clampf(float(packet.get("clock_scale", 1.0)), 0.0, 10.0)
		var host_time := float(packet["time_of_day"])
		var time_diff := wrapf(host_time - time_of_day, -0.5, 0.5)
		if absf(time_diff) > TIME_SNAP_THRESHOLD:
			time_of_day = host_time
			_time_correction = 0.0
		else:
			_time_correction = time_diff
		daily_kwh = float(packet["daily_kwh"])
		electricity_rate = float(packet.get("electricity_rate", ELECTRICITY_RATE_PER_KWH))
		last_bill_rate = float(packet.get("last_bill_rate", ELECTRICITY_RATE_PER_KWH))
		last_daily_bill = int(packet["last_daily_bill"])
		room_temp = float(packet["room_temp"])
		total_watts = int(packet["total_watts"])
		max_watts = int(packet["max_watts"])
		total_compute = int(packet["total_compute"])
		raw_compute = int(packet.get("raw_compute", total_compute))
		max_bandwidth_cu = int(packet.get("max_bandwidth_cu", 36))
		used_compute = int(packet["used_compute"])
		revenue_bonus_mult = float(packet["revenue_bonus_mult"])
		ai_revenue_per_sec = float(packet["ai_revenue_per_sec"])
		total_rental_income_per_cycle = float(packet.get("total_rental_income_per_cycle", 0.0))
		reputation = clampf(float(packet.get("reputation", reputation)), 0.0, 100.0)
		total_ram_gb = int(packet.get("total_ram_gb", 0))
		total_cpu_score = int(packet.get("total_cpu_score", 0))
		total_gpu_score = int(packet.get("total_gpu_score", 0))
		total_storage_tb = float(packet.get("total_storage_tb", 0.0))
		used_bandwidth_mbps = float(packet.get("used_bandwidth_mbps", 0.0))
		max_bandwidth_mbps = float(packet.get("max_bandwidth_mbps", 50.0))
		next_payout_in = float(packet["next_payout_in"])
		contracts = packet["contracts"].duplicate(true)
		weather_state = str(packet.get("weather_state", weather_state))
		airflow_bonus = float(packet.get("airflow_bonus", airflow_bonus))
		cable_mgmt_bonus = float(packet.get("cable_mgmt_bonus", cable_mgmt_bonus))
		if packet.has("career_completed") and packet["career_completed"] is Array:
			career_completed = (packet["career_completed"] as Array).duplicate()
		if packet.has("active_team_order") and packet["active_team_order"] is Dictionary:
			active_team_order = (packet["active_team_order"] as Dictionary).duplicate(true)
		var prev_hn := halle_nord_owned
		halle_nord_owned = bool(packet.get("halle_nord_owned", halle_nord_owned))
		delivery_target_site = str(packet.get("delivery_target_site", delivery_target_site))
		maint_kits = int(packet.get("maint_kits", maint_kits))
		if packet.has("building_upgrades") and packet["building_upgrades"] is Dictionary:
			var new_bu: Dictionary = (packet["building_upgrades"] as Dictionary).duplicate(true)
			if new_bu != building_upgrades:
				building_upgrades = new_bu
				building_upgrades_changed.emit()
		if packet.has("active_constructions") and packet["active_constructions"] is Dictionary:
			var new_ac: Dictionary = (packet["active_constructions"] as Dictionary).duplicate(true)
			if new_ac != active_constructions:
				active_constructions = new_ac
				constructions_changed.emit()
		if halle_nord_owned != prev_hn:
			halle_nord_changed.emit()
		var rtemps: Dictionary = packet["rack_temps"]
		for rid in rtemps.keys():
			if racks.has(rid):
				var rt: Dictionary = rtemps[rid]
				racks[rid]["temp"] = float(rt["temp"])
				racks[rid]["powered"] = bool(rt["powered"])
				racks[rid]["networked"] = bool(rt["networked"])
				racks[rid]["rental_type"] = str(rt.get("rental_type", "none"))
				racks[rid]["rental_customer"] = str(rt.get("rental_customer", ""))
				racks[rid]["active_users"] = int(rt.get("active_users", 0))
				racks[rid]["satisfaction"] = float(rt.get("satisfaction", 100.0))
				racks[rid]["rental_income"] = float(rt.get("rental_income", 0.0))
				racks[rid]["metrics"] = (rt.get("metrics", {}) as Dictionary).duplicate(true)
				racks[rid]["services"] = (rt.get("services", []) as Array).duplicate(true)
		var cpwr: Dictionary = packet["cooler_pwr"]
		for cid in cpwr.keys():
			if coolers.has(cid):
				coolers[cid]["powered"] = bool(cpwr[cid])
		var usync: Dictionary = packet["ups_sync"]
		for uid in usync.keys():
			if ups_units.has(uid):
				ups_units[uid]["connected"] = bool(usync[uid]["connected"])
				ups_units[uid]["charge"] = float(usync[uid]["charge"])
				ups_units[uid]["discharging"] = bool(usync[uid]["discharging"])
				ups_units[uid]["health"] = float(usync[uid].get("health", 100.0))
				ups_units[uid]["tripped"] = bool(usync[uid].get("tripped", false))
	state_updated.emit()


# ==============================================================================
# WERKSTATT-, LAGERREGAL-, SCHACHT- & WARENKORB-SYSTEM (v1.1 Overhaul)
# ==============================================================================

func is_repair_kit(item_type: String) -> bool:
	return ITEM_CATALOG.has(item_type) and str(ITEM_CATALOG[item_type].get("category", "")) == "repair_kit"


func get_repair_kit_cat(item_type: String) -> String:
	if not is_repair_kit(item_type):
		return ""
	return str(ITEM_CATALOG[item_type].get("kit_cat", ""))


func get_repair_kit_id_for_cat(cat: String) -> String:
	for kid in REPAIR_KIT_ORDER:
		if str(ITEM_CATALOG[kid].get("kit_cat", "")) == cat:
			return kid
	return ""


func get_crate_display_label(crate: Dictionary) -> String:
	var pcount := maxi(1, int(crate.get("pack_count", 1)))
	var suffix := (" (%d×)" % pcount) if pcount > 1 else ""
	var custom_lbl := str(crate.get("label", ""))
	if not custom_lbl.is_empty():
		return custom_lbl + suffix
	var itype := str(crate.get("item_type", ""))
	if itype == "server_tray":
		var td: Dictionary = crate.get("tray_data", {}) as Dictionary
		var mb_id := str(td.get("mainboard_id", ""))
		var mb_name := str(ITEM_CATALOG.get(mb_id, {}).get("name", "Server"))
		var st := str(td.get("state", "ok"))
		if st == "crashed":
			return "%s (DEFEKT)" % mb_name
		return "%s (BEREIT)" % mb_name
	if ITEM_CATALOG.has(itype):
		var short_l := str(ITEM_CATALOG[itype].get("short_label", ""))
		if not short_l.is_empty():
			return short_l + suffix
		return str(ITEM_CATALOG[itype]["name"]) + suffix
	return itype + suffix


func calculate_slot_build_price(mainboard_id: String, comps: Dictionary) -> int:
	if not ITEM_CATALOG.has(mainboard_id):
		return 0
	var total := int(ITEM_CATALOG[mainboard_id].get("price", 0))
	for cat_v in COMPONENT_ORDER:
		var cat := str(cat_v)
		var pid := str(comps.get(cat, ""))
		if pid.is_empty():
			continue
		var pd := HardwareCatalog.get_part(cat, pid)
		if not pd.is_empty():
			total += maxi(0, int(pd.get("cost", 0)))
	return total


func _ensure_starter_shelf_kits() -> void:
	if not storage_shelf_slots.is_empty():
		return
	var starters: Array[String] = ["kit_ram", "kit_cpu", "kit_cooling", "kit_psu"]
	for i in range(starters.size()):
		var kid := starters[i]
		storage_shelf_slots["shelf_0:%d" % i] = {
			"id": _alloc_id("crate"),
			"item_type": kid,
			"label": str(ITEM_CATALOG[kid].get("short_label", kid)),
			"pos": Vector3.ZERO,
			"held_by": 0,
		}


## --- Gemeinsamer Warenkorb (Rack-Konfigurator + PC-Shop) ---

func cart_add_entry(kind: String, id: String, cat: String, display_name: String, price: int, amount: int = 1) -> void:
	var add_n := maxi(1, amount)
	var key := "%s:%s" % [kind, id]
	for item in shopping_cart:
		if str(item.get("key", "")) == key:
			item["qty"] = mini(int(item.get("qty", 1)) + add_n, 24)
			cart_changed.emit()
			return
	shopping_cart.append({
		"key": key,
		"kind": kind,
		"id": id,
		"cat": cat,
		"name": display_name,
		"price": price,
		"qty": mini(add_n, 24),
	})
	cart_changed.emit()


func cart_add_slot_build(rack_id: String, slot_idx: int, mainboard_id: String, comps: Dictionary) -> bool:
	if not ITEM_CATALOG.has(mainboard_id):
		return false
	var rlabel := get_rack_display_name(rack_id)
	var key := "slot_build:%s:%d" % [rack_id, slot_idx]
	var price := calculate_slot_build_price(mainboard_id, comps)
	var mb_name := str(ITEM_CATALOG[mainboard_id]["name"])
	var entry := {
		"key": key,
		"kind": "slot_build",
		"id": mainboard_id,
		"cat": "slot_build",
		"rack_id": rack_id,
		"slot_idx": slot_idx,
		"rack_label": rlabel,
		"mainboard_id": mainboard_id,
		"components": comps.duplicate(true),
		"name": "%s · Slot %d (%s)" % [rlabel, slot_idx + 1, mb_name],
		"price": price,
		"qty": 1,
	}
	for i in range(shopping_cart.size()):
		if str(shopping_cart[i].get("key", "")) == key:
			shopping_cart[i] = entry
			cart_changed.emit()
			return true
	shopping_cart.append(entry)
	cart_changed.emit()
	return true


func cart_remove_entry(key: String) -> void:
	for i in range(shopping_cart.size() - 1, -1, -1):
		if str(shopping_cart[i].get("key", "")) == key:
			shopping_cart.remove_at(i)
			cart_changed.emit()
			return


func cart_change_qty(key: String, delta: int) -> void:
	for i in range(shopping_cart.size() - 1, -1, -1):
		if str(shopping_cart[i].get("key", "")) == key:
			if str(shopping_cart[i].get("kind", "")) == "slot_build":
				if delta < 0:
					shopping_cart.remove_at(i)
					cart_changed.emit()
				return
			var nq := int(shopping_cart[i].get("qty", 1)) + delta
			if nq <= 0:
				shopping_cart.remove_at(i)
			else:
				shopping_cart[i]["qty"] = mini(nq, 24)
			cart_changed.emit()
			return


func cart_clear() -> void:
	shopping_cart.clear()
	cart_changed.emit()


func get_cart_count() -> int:
	var n := 0
	for item in shopping_cart:
		n += int(item.get("qty", 1))
	return n


func get_cart_total() -> int:
	var t := 0
	for item in shopping_cart:
		t += int(item.get("price", 0)) * int(item.get("qty", 1))
	return t


## --- Ausfahrbare Rack-Schächte (Teleskopschienen) ---

func is_slot_extended(rack_id: String, slot_idx: int) -> bool:
	return is_shared_panel_open(rack_id, "slot_%d" % slot_idx)


func request_toggle_slot_extended(rack_id: String, slot_idx: int) -> void:
	request_toggle_panel(rack_id, "slot_%d" % slot_idx)


## --- Server-Schlitten aus ausgefahrenem Schacht ziehen & einsetzen ---

func request_pull_server_tray(rack_id: String, slot_idx: int) -> void:
	_rpc_req_pull_server_tray.rpc_id(1, rack_id, slot_idx)


func request_insert_server_tray(rack_id: String, slot_idx: int) -> void:
	_rpc_req_insert_server_tray.rpc_id(1, rack_id, slot_idx)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_pull_server_tray(rack_id: String, slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if is_player_holding_anything(peer_id) or not racks.has(rack_id):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		if is_player_holding_anything(peer_id):
			post_event("Hände voll! Erst Item mit [Q] ablegen oder freien Slot (1–4) wählen.", "warn")
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	var itype := str(slot.get("item_type", ""))
	if itype == "" or str(slot.get("state", "")) == "burning":
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var rlabel := get_rack_display_name(rack_id)
	_tray_from_slot(rack_id, slot_idx, slot, peer_id)
	slots[slot_idx] = _make_empty_slot()
	_recalculate_networks_and_metrics()
	_broadcast_racks()
	_broadcast_crates()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc_id(peer_id, "pickup")
	post_event_f("🔧 %s hat den Server-Schlitten aus %s · Slot %d herausgezogen.", [
		NetworkManager.get_player_name(peer_id), rlabel, slot_idx + 1
	], "info")


## Server aus dem Einschub als Schlitten in die Hand nehmen; liefert die Kisten-ID.
func _tray_from_slot(rack_id: String, slot_idx: int, slot: Dictionary, peer_id: int) -> String:
	var rlabel := get_rack_display_name(rack_id)
	var itype := str(slot.get("item_type", ""))
	var st := str(slot.get("state", "ok"))
	var cid := _alloc_id("crate")
	crates[cid] = {
		"id": cid,
		"item_type": "server_tray",
		"pos": Vector3.ZERO,
		"held_by": peer_id,
		"held_slot": get_active_slot(peer_id),
		"label": "%s · Slot %d (%s)" % [rlabel, slot_idx + 1, "DEFEKT" if st == "crashed" else "OK"],
		"tray_data": {
			"mainboard_id": itype,
			"components": (slot.get("components", {}) as Dictionary).duplicate(true),
			"state": st,
			"faulty_part": str(slot.get("faulty_part", "")),
			"diagnosed": bool(slot.get("diagnosed", false)),
			"fault_hidden": bool(slot.get("fault_hidden", false)),
			"build_quality": get_build_quality(slot),
			"source_rack_id": rack_id,
			"source_slot_idx": slot_idx,
		},
	}
	return cid


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_insert_server_tray(rack_id: String, slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	var held := get_player_held_crate(peer_id)
	if held.is_empty() or str(held.get("item_type", "")) != "server_tray":
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	if not racks.has(rack_id):
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	if str(slots[slot_idx].get("item_type", "")) != "":
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	slots[slot_idx] = _slot_from_tray(held.get("tray_data", {}) as Dictionary)
	crates.erase(str(held["id"]))
	_recalculate_networks_and_metrics()
	_broadcast_crates()
	_broadcast_racks()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("snap")
	post_event_f("✅ %s hat den Server in %s · Slot %d eingesetzt!", [
		NetworkManager.get_player_name(peer_id), get_rack_display_name(rack_id), slot_idx + 1
	], "good")


func _slot_from_tray(td: Dictionary) -> Dictionary:
	var mb_id := str(td.get("mainboard_id", "web_server"))
	if not ITEM_CATALOG.has(mb_id):
		mb_id = "web_server"
	var st := str(td.get("state", "ok"))
	return {
		"item_type": mb_id,
		"state": st,
		"faulty_part": str(td.get("faulty_part", "")) if st == "crashed" else "",
		"diagnosed": bool(td.get("diagnosed", false)) if st == "crashed" else false,
		"fault_hidden": bool(td.get("fault_hidden", false)) if st == "crashed" else false,
		"build_quality": get_build_quality(td),
		"repair_progress": 0.0,
		"fire_level": 0.0,
		"offline": true, # fährt nach dem Einschieben erst hoch
		"components": (td.get("components", _default_components(mb_id)) as Dictionary).duplicate(true),
	}


## --- Funktionales 3D-Lagerregal ---

func request_shelf_interact(shelf_id: String, slot_idx: int) -> void:
	_rpc_req_shelf_interact.rpc_id(1, shelf_id, slot_idx)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_shelf_interact(shelf_id: String, slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if slot_idx < 0 or slot_idx >= STORAGE_SHELF_SLOTS:
		return
	var peer_id := _get_sender_id()
	var key := "%s:%d" % [shelf_id, slot_idx]
	var held := get_player_held_crate(peer_id)
	if not held.is_empty():
		if storage_shelf_slots.has(key):
			_rpc_play_sfx.rpc_id(peer_id, "error")
			return
		var stored := held.duplicate(true)
		stored["held_by"] = 0
		stored["pos"] = Vector3.ZERO
		crates.erase(str(held["id"]))
		storage_shelf_slots[key] = stored
		_broadcast_crates()
		_broadcast_shelf()
		_rpc_play_sfx.rpc_id(peer_id, "place")
	else:
		if not storage_shelf_slots.has(key) or is_player_holding_anything(peer_id):
			return
		var taken: Dictionary = (storage_shelf_slots[key] as Dictionary).duplicate(true)
		storage_shelf_slots.erase(key)
		var cid := str(taken.get("id", ""))
		if cid.is_empty() or crates.has(cid):
			cid = _alloc_id("crate")
			taken["id"] = cid
		taken["held_by"] = peer_id
		taken["held_slot"] = get_active_slot(peer_id)
		crates[cid] = taken
		_broadcast_crates()
		_broadcast_shelf()
		_rpc_play_sfx.rpc_id(peer_id, "pickup")


func _broadcast_shelf() -> void:
	if not multiplayer.is_server():
		return
	_rpc_sync_shelf.rpc(storage_shelf_slots.duplicate(true))


@rpc("authority", "call_local", "reliable")
func _rpc_sync_shelf(data: Dictionary) -> void:
	storage_shelf_slots = data.duplicate(true)
	shelf_changed.emit()


## Zählt verfügbare Reparatur-Kits für eine Kategorie (Hand + Lagerregal + Boden, inkl. Mengen-Kisten!).
func count_repair_kits(cat: String) -> int:
	var kid := get_repair_kit_id_for_cat(cat)
	if kid.is_empty():
		return 0
	var total := 0
	for c in crates.values():
		var cd := c as Dictionary
		if str(cd.get("item_type", "")) == kid:
			total += maxi(1, int(cd.get("pack_count", 1)))
	for s in storage_shelf_slots.values():
		var sd := s as Dictionary
		if str(sd.get("item_type", "")) == kid:
			total += maxi(1, int(sd.get("pack_count", 1)))
	return total


func _consume_repair_kit_server(peer_id: int, cat: String) -> bool:
	var kid := get_repair_kit_id_for_cat(cat)
	if kid.is_empty():
		return false
	# 1. Zuerst in der Hand des Spielers prüfen (Mengen-Kiste zieht nur 1 Stück ab!)
	var held := get_player_held_crate(peer_id)
	if not held.is_empty() and str(held.get("item_type", "")) == kid:
		var hcid := str(held["id"])
		var hp := maxi(1, int(crates[hcid].get("pack_count", 1)))
		if hp > 1:
			crates[hcid]["pack_count"] = hp - 1
		else:
			crates.erase(hcid)
		_broadcast_crates()
		return true
	# 2. Danach im Lagerregal
	for key in storage_shelf_slots.keys():
		var sd: Dictionary = storage_shelf_slots[key] as Dictionary
		if str(sd.get("item_type", "")) == kid:
			var sp := maxi(1, int(sd.get("pack_count", 1)))
			if sp > 1:
				sd["pack_count"] = sp - 1
			else:
				storage_shelf_slots.erase(key)
			_broadcast_shelf()
			return true
	# 3. Zuletzt freiliegende Kit-Koffer / Mengen-Kisten am Boden
	for cid in crates.keys():
		var c: Dictionary = crates[cid]
		if int(c.get("held_by", 0)) == 0 and str(c.get("item_type", "")) == kid:
			var gp := maxi(1, int(c.get("pack_count", 1)))
			if gp > 1:
				c["pack_count"] = gp - 1
			else:
				crates.erase(cid)
			_broadcast_crates()
			return true
	return false


## --- Interaktive 3D-Werkbank (Zusammenbau & Reparatur) ---

func request_workbench_place() -> void:
	_rpc_req_workbench_place.rpc_id(1)


func request_workbench_unpack() -> void:
	_rpc_req_workbench_unpack.rpc_id(1)


func request_workbench_pickup() -> void:
	_rpc_req_workbench_pickup.rpc_id(1)


## Arbeitsplatz an der Werkbank belegen bzw. freigeben (immer nur ein Spieler gleichzeitig).
func request_workbench_enter() -> void:
	_rpc_req_workbench_enter.rpc_id(1)


func request_workbench_leave() -> void:
	_rpc_req_workbench_leave.rpc_id(1)


## Ein Handgriff ist fertig. amount ist nur bei der Wärmeleitpaste wichtig (1.0 = genau richtig).
func request_workbench_task(task_id: String, amount: float = 1.0) -> void:
	_rpc_req_workbench_task.rpc_id(1, task_id, amount)


## Liegt gerade etwas auf der Werkbank, an dem gearbeitet werden kann?
func is_workbench_job() -> bool:
	return BENCH_JOBS.has(str(workbench_state.get("mode", "")))


## Fertigen Server überholen: Schrauben nachziehen, Paste erneuern.
func request_workbench_service() -> void:
	_rpc_req_workbench_service.rpc_id(1)


func can_workbench_service() -> bool:
	return str(workbench_state.get("mode", "")) == "ready_tray" and get_build_quality(workbench_state) < 100 and AssemblyPlan.can_service(workbench_state)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_workbench_service() -> void:
	if not multiplayer.is_server() or not can_workbench_service() or get_workbench_worker() != 0:
		return
	workbench_state["mode"] = "service"
	workbench_state["done"] = {}
	workbench_state["flaws"] = []
	_broadcast_workbench()
	_rpc_play_sfx.rpc_id(_get_sender_id(), "pickup")


## CPU mit Gewalt verkehrt herum eingesetzt: Pins verbogen, Teil zerstört.
func request_workbench_break(task_id: String) -> void:
	_rpc_req_workbench_break.rpc_id(1, task_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_workbench_break(task_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if get_workbench_worker() != peer_id or task_id != "cpu_place" or not SecurityGuard.check_rate_limit(peer_id, "wb_break", 6, 5.0):
		return
	var plan := AssemblyPlan.build(workbench_state)
	var done := AssemblyPlan.sanitize_done(plan, workbench_state.get("done", {}))
	if not AssemblyPlan.is_available(plan, done, task_id):
		return
	if str(plan["mode"]) == "repair":
		if bool(workbench_state.get("kit_used", false)) or not _consume_spare_server(peer_id):
			return
		workbench_state.erase("spare")
		workbench_state["spare_broken"] = true
	elif str(plan["mode"]) == "assembly":
		if (workbench_state.get("broken", []) as Array).has("cpu"):
			return
		workbench_state["broken"] = ["cpu"]
	else:
		return
	_broadcast_workbench()
	_rpc_play_sfx.rpc("spark")
	post_event_f("💥 %s hat die CPU verkehrt herum eingedrückt: Pins verbogen, CPU zerstört! Neue CPU wählen.", [get_worker_name(peer_id)], "alert")


## Braucht der Bau gerade ein Ersatzteil (zerstörte CPU)?
func needs_workbench_replacement() -> bool:
	return bool(workbench_state.get("spare_broken", false)) or not (workbench_state.get("broken", []) as Array).is_empty()


func get_workbench_worker() -> int:
	return int(workbench_state.get("worker", 0))


func get_workbench_done() -> Dictionary:
	var raw: Variant = workbench_state.get("done", {})
	return raw if raw is Dictionary else {}


## Hat an der Werkbank schon jemand einen Handgriff gemacht?
func is_workbench_started() -> bool:
	return not get_workbench_done().is_empty()


func send_workbench_hand(data: Dictionary) -> void:
	if not NetworkManager.is_in_session:
		return
	if multiplayer.is_server():
		_rpc_workbench_hand.rpc(data)
		# Technikerbewegungen sieht auch der Host selbst.
		if data.is_empty() or data.has("auto"):
			workbench_hand_moved.emit(data)
	else:
		_rpc_submit_workbench_hand.rpc_id(1, data)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_submit_workbench_hand(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sid := multiplayer.get_remote_sender_id()
	if get_workbench_worker() != sid or data.size() > 6:
		return
	if not SecurityGuard.check_rate_limit(sid, "wb_hand", 40, 1.0):
		return
	var clean := _sanitize_workbench_hand(data)
	workbench_hand_moved.emit(clean)
	for pid in multiplayer.get_peers():
		if pid != sid:
			_rpc_workbench_hand.rpc_id(pid, clean)


func _sanitize_workbench_hand(data: Dictionary) -> Dictionary:
	var xf_v: Variant = data.get("xf", Transform3D.IDENTITY)
	var xf: Transform3D = xf_v if xf_v is Transform3D else Transform3D.IDENTITY
	if not xf.is_finite() or xf.origin.length() > 4.0:
		xf = Transform3D.IDENTITY
	var t_v: Variant = data.get("t", 0.0)
	var t := float(t_v) if (t_v is float or t_v is int) else 0.0
	return {
		"tool": str(data.get("tool", "")).left(16),
		"item": str(data.get("item", "")).left(24),
		"xf": xf,
		"task": str(data.get("task", "")).left(24),
		"t": clampf(t if SecurityGuard.is_finite_float(t) else 0.0, 0.0, AssemblyPlan.PASTE_MAX),
	}


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_workbench_hand(data: Dictionary) -> void:
	workbench_hand_moved.emit(data)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_workbench_place() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not workbench_state.is_empty():
		_sfx_to(peer_id, "error")
		return
	var held := get_player_held_crate(peer_id)
	if held.is_empty():
		return
	if _put_crate_on_bench(held):
		_broadcast_crates()
		_broadcast_workbench()
		_sfx_to(peer_id, "place")
	else:
		_sfx_to(peer_id, "error")


## Bausatz oder Schlitten auf die Werkbank legen. false, wenn die Kiste nicht passt.
func _put_crate_on_bench(held: Dictionary) -> bool:
	var itype := str(held.get("item_type", ""))
	if itype == "slot_build_box":
		var bd: Dictionary = (held.get("build_data", {}) as Dictionary).duplicate(true)
		workbench_state = {
			"mode": "build_box",
			"label": str(held.get("label", "Server-Bausatz")),
			"rack_id": str(bd.get("rack_id", "")),
			"slot_idx": int(bd.get("slot_idx", 0)),
			"rack_label": str(bd.get("rack_label", "Rack")),
			"mainboard_id": str(bd.get("mainboard_id", "web_server")),
			"components": (bd.get("components", {}) as Dictionary).duplicate(true),
		}
		crates.erase(str(held["id"]))
		return true
	elif itype == "server_tray":
		var td: Dictionary = (held.get("tray_data", {}) as Dictionary).duplicate(true)
		var is_crashed := str(td.get("state", "ok")) == "crashed"
		workbench_state = {
			"mode": "repair" if is_crashed else "ready_tray",
			"label": str(held.get("label", "Server-Schlitten")),
			"rack_id": str(td.get("source_rack_id", "")),
			"slot_idx": int(td.get("source_slot_idx", 0)),
			"mainboard_id": str(td.get("mainboard_id", "web_server")),
			"components": (td.get("components", {}) as Dictionary).duplicate(true),
			"state": str(td.get("state", "ok")),
			"faulty_part": str(td.get("faulty_part", "")),
			"diagnosed": bool(td.get("diagnosed", false)),
			"fault_hidden": bool(td.get("fault_hidden", false)),
			"build_quality": get_build_quality(td),
		}
		crates.erase(str(held["id"]))
		return true
	return false


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_workbench_unpack() -> void:
	if not multiplayer.is_server():
		return
	if str(workbench_state.get("mode", "")) != "build_box":
		return
	server_workbench_unpack()
	_spawn_empty_carton("build", Vector3(-3.7, 0.0, 3.1))
	_rpc_play_sfx.rpc("carton_open")


func server_workbench_unpack() -> void:
	if str(workbench_state.get("mode", "")) != "build_box":
		return
	workbench_state["mode"] = "assembly"
	_broadcast_workbench()
	_rpc_play_sfx.rpc("pickup")


func server_workbench_service() -> void:
	if not can_workbench_service() or get_workbench_worker() > 0:
		return
	workbench_state["mode"] = "service"
	workbench_state["done"] = {}
	workbench_state["flaws"] = []
	_broadcast_workbench()


func set_workbench_worker(worker: int) -> void:
	if workbench_state.is_empty():
		return
	workbench_state["worker"] = worker
	_broadcast_workbench()


## Geräusch nur für einen Spieler; der Techniker (negative ID) hört nichts.
func _sfx_to(peer_id: int, sfx_name: String) -> void:
	if peer_id > 0:
		_rpc_play_sfx.rpc_id(peer_id, sfx_name)


func get_worker_name(worker: int) -> String:
	return TechnicianManager.get_worker_name() if worker < 0 else NetworkManager.get_player_name(worker)


# --- Handgriffe des Technikers (nur Host) ---

func server_hold_crate(cid: String, holder: int) -> void:
	if crates.has(cid):
		crates[cid]["held_by"] = holder
		crates[cid]["held_slot"] = 0
		_broadcast_crates()


func server_drop_crate(cid: String, pos: Vector3) -> void:
	if crates.has(cid):
		crates[cid]["held_by"] = 0
		crates[cid]["pos"] = _clamp_drop_pos(pos + Vector3(0.0, 0.0, 0.5))
		_broadcast_crates()


func server_take_tray(rack_id: String, slot_idx: int, holder: int) -> String:
	if not racks.has(rack_id):
		return ""
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return ""
	var slot: Dictionary = slots[slot_idx]
	if str(slot.get("item_type", "")) == "" or str(slot.get("state", "")) == "burning":
		return ""
	var cid := _tray_from_slot(rack_id, slot_idx, slot, holder)
	slots[slot_idx] = _make_empty_slot()
	_recalculate_networks_and_metrics()
	_broadcast_racks()
	_broadcast_crates()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("snap")
	return cid


func server_put_tray(cid: String, rack_id: String, slot_idx: int, who: String) -> bool:
	if not crates.has(cid) or not racks.has(rack_id):
		return false
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size() or str(slots[slot_idx].get("item_type", "")) != "":
		return false
	slots[slot_idx] = _slot_from_tray(crates[cid].get("tray_data", {}) as Dictionary)
	crates.erase(cid)
	_close_slot_panel(rack_id, slot_idx)
	_recalculate_networks_and_metrics()
	_broadcast_crates()
	_broadcast_racks()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("snap")
	post_event_f("✅ %s hat den Server in %s · Slot %d eingesetzt!", [who, get_rack_display_name(rack_id), slot_idx + 1], "good")
	return true


func server_place_on_bench(cid: String) -> bool:
	if not crates.has(cid) or not workbench_state.is_empty():
		return false
	if not _put_crate_on_bench(crates[cid]):
		return false
	_broadcast_crates()
	_broadcast_workbench()
	_rpc_play_sfx.rpc("place")
	return true


func server_take_from_bench(holder: int) -> String:
	if str(workbench_state.get("mode", "")) != "ready_tray" or get_workbench_worker() != 0:
		return ""
	var cid := _crate_from_bench(holder)
	workbench_state.clear()
	_broadcast_workbench()
	_broadcast_crates()
	return cid


# --- Profi-Werkzeug ---

func has_bench_tool(tool_id: String) -> bool:
	return bool(bench_tools.get(tool_id, false))


## Zeitfaktor eines Handgriffs durch gekauftes Werkzeug.
func get_tool_time_mult(kind: String) -> float:
	match kind:
		"screw", "unscrew":
			return 0.55 if has_bench_tool("akku") else 1.0
		"paste":
			return 0.65 if has_bench_tool("paste_gun") else 1.0
		"measure":
			return 0.45 if has_bench_tool("meter_pro") else 1.0
	return 1.0


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_workbench_enter() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not is_workbench_job():
		return
	if get_workbench_worker() > 0:
		# Schon besetzt: dem Anfragenden den echten Stand schicken. Ein Techniker macht dagegen Platz.
		_rpc_sync_workbench.rpc_id(peer_id, workbench_state.duplicate(true))
		return
	workbench_state["worker"] = peer_id
	_broadcast_workbench()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_workbench_leave() -> void:
	if not multiplayer.is_server():
		return
	if workbench_state.is_empty() or get_workbench_worker() != _get_sender_id():
		return
	workbench_state["worker"] = 0
	_broadcast_workbench()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_workbench_task(task_id: String, amount: float) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.is_finite_float(amount) or task_id.length() > 32:
		return
	if not SecurityGuard.check_rate_limit(peer_id, "wb_task", 30, 5.0):
		_reject_workbench_task(peer_id, task_id)
		return
	server_workbench_task(peer_id, task_id, amount)


## Handgriff ausführen (nur Host). peer_id = Spieler oder TechnicianManager.WORKER_ID.
func server_workbench_task(peer_id: int, task_id: String, amount: float) -> bool:
	if get_workbench_worker() != peer_id:
		_reject_workbench_task(peer_id, task_id)
		return false
	_run_workbench_task(peer_id, task_id, amount)
	return get_workbench_done().has(task_id) or not is_workbench_job()


func _run_workbench_task(peer_id: int, task_id: String, amount: float) -> void:
	var plan := AssemblyPlan.build(workbench_state)
	var done := AssemblyPlan.sanitize_done(plan, workbench_state.get("done", {}))
	if not AssemblyPlan.is_available(plan, done, task_id):
		_reject_workbench_task(peer_id, task_id)
		return
	var task: Dictionary = plan["by_id"][task_id]
	var kind := str(task["kind"])
	if kind == "choose":
		_reject_workbench_task(peer_id, task_id)
		return
	if kind == "paste":
		amount = clampf(amount, AssemblyPlan.PASTE_MIN, AssemblyPlan.PASTE_MAX)
	elif kind == "screw":
		amount = clampf(amount, AssemblyPlan.SCREW_MIN, AssemblyPlan.DONE_MAX)
	else:
		amount = 1.0
	if needs_workbench_replacement() and task_id == "cpu_place":
		_reject_workbench_task(peer_id, task_id)
		return
	if not _use_bench_supplies(plan, task, amount, true):
		_sfx_to(peer_id, "error")
		_reject_workbench_task(peer_id, task_id)
		return
	if bool(task["kit"]) and not bool(workbench_state.get("kit_used", false)):
		if not _consume_spare_server(peer_id):
			_sfx_to(peer_id, "error")
			_reject_workbench_task(peer_id, task_id)
			return
		workbench_state["kit_used"] = true
	_use_bench_supplies(plan, task, amount, false)
	if AssemblyPlan.is_live_risk(task, done):
		_workbench_short_circuit(peer_id, plan, done)
	done[task_id] = amount
	workbench_state["done"] = done
	if task_id == "test_on":
		workbench_state["test"] = AssemblyPlan.test_result(plan, done, workbench_state)
		if str((workbench_state["test"] as Dictionary)["kind"]) == "cpu":
			_rpc_play_sfx.rpc("spark")
	elif task_id == "test_off":
		if _handle_failed_test(peer_id):
			_broadcast_workbench()
			return
	if AssemblyPlan.is_complete(plan, done):
		_finish_workbench_job(peer_id)
	else:
		_broadcast_workbench()


## Ersatzteil für die laufende Reparatur festlegen: "kit" oder die ID eines Teils aus dem Teile-Lager.
func request_workbench_choose(spare_id: String) -> void:
	_rpc_req_workbench_choose.rpc_id(1, spare_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_workbench_choose(spare_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if get_workbench_worker() != peer_id or spare_id.length() > 48:
		return
	if not SecurityGuard.check_rate_limit(peer_id, "wb_choose", 10, 5.0):
		return
	server_workbench_choose(peer_id, spare_id)


func server_workbench_choose(peer_id: int, spare_id: String) -> void:
	if get_workbench_worker() != peer_id:
		return
	if str(workbench_state.get("mode", "")) == "assembly":
		_choose_assembly_replacement(peer_id, spare_id)
		return
	if str(workbench_state.get("mode", "")) != "repair":
		return
	var plan := AssemblyPlan.build(workbench_state)
	var done := AssemblyPlan.sanitize_done(plan, workbench_state.get("done", {}))
	var again := done.has("choose") and (not AssemblyPlan.is_choice_locked(plan, done) or bool(workbench_state.get("spare_broken", false)))
	if not again and not AssemblyPlan.is_available(plan, done, "choose"):
		return
	var rcat := str(plan["repair_cat"])
	if spare_id == AssemblyPlan.SPARE_KIT:
		workbench_state["spare"] = {"kind": AssemblyPlan.SPARE_KIT, "id": get_workbench_kit_id()}
	else:
		if not AssemblyPlan.accepts_parts(rcat) or HardwareCatalog.find_part_category(spare_id) != rcat or int(parts_inventory.get(spare_id, 0)) <= 0:
			_sfx_to(peer_id, "error")
			return
		workbench_state["spare"] = {"kind": "part", "id": spare_id}
	workbench_state.erase("spare_broken")
	# Mit dem Teil kann sich der Plan ändern; die Fehlersuche davor bleibt gültig.
	done["choose"] = 1.0
	workbench_state["done"] = AssemblyPlan.sanitize_done(AssemblyPlan.build(workbench_state), done)
	_broadcast_workbench()
	_sfx_to(peer_id, "pickup")


## Beim Zusammenbau zerstörte CPU ersetzen: Kit oder Teil aus dem Lager, wird sofort verbraucht.
func _choose_assembly_replacement(peer_id: int, spare_id: String) -> void:
	if not (workbench_state.get("broken", []) as Array).has("cpu"):
		return
	if spare_id == AssemblyPlan.SPARE_KIT:
		if not _consume_repair_kit_server(peer_id, "cpu"):
			_sfx_to(peer_id, "error")
			return
	else:
		if HardwareCatalog.find_part_category(spare_id) != "cpu" or int(parts_inventory.get(spare_id, 0)) <= 0:
			_sfx_to(peer_id, "error")
			return
		parts_inventory[spare_id] = int(parts_inventory[spare_id]) - 1
		if int(parts_inventory[spare_id]) <= 0:
			parts_inventory.erase(spare_id)
		_broadcast_inventory()
		var comps: Dictionary = (workbench_state.get("components", {}) as Dictionary).duplicate(true)
		comps["cpu"] = spare_id
		workbench_state["components"] = comps
	workbench_state["broken"] = []
	workbench_state["done"] = AssemblyPlan.sanitize_done(AssemblyPlan.build(workbench_state), workbench_state.get("done", {}))
	_broadcast_workbench()
	_sfx_to(peer_id, "pickup")


## Kit, das zum Defekt auf der Werkbank passt.
func get_workbench_kit_id() -> String:
	return get_repair_kit_id_for_cat(get_workbench_kit_cat())


func get_workbench_kit_cat() -> String:
	if str(workbench_state.get("mode", "")) == "assembly":
		return "cpu"
	var cat := str(workbench_state.get("faulty_part", ""))
	return cat if not cat.is_empty() else "mainboard"


## Liegt das gewählte Ersatzteil bereit (oder ist es schon verbaut)?
func is_workbench_spare_ready() -> bool:
	if needs_workbench_replacement():
		return false
	if str(workbench_state.get("mode", "")) != "repair":
		return true
	if bool(workbench_state.get("kit_used", false)):
		return true
	var spare := AssemblyPlan.spare_of(workbench_state)
	match str(spare.get("kind", "")):
		"kit":
			return count_repair_kits(get_workbench_kit_cat()) > 0
		"part":
			return int(parts_inventory.get(str(spare.get("id", "")), 0)) > 0
	return false


func _consume_spare_server(peer_id: int) -> bool:
	var spare := AssemblyPlan.spare_of(workbench_state)
	if str(spare.get("kind", "")) == "part":
		var pid := str(spare.get("id", ""))
		var stock := int(parts_inventory.get(pid, 0))
		if stock <= 0:
			return false
		parts_inventory[pid] = stock - 1
		if int(parts_inventory[pid]) <= 0:
			parts_inventory.erase(pid)
		_broadcast_inventory()
		return true
	return _consume_repair_kit_server(peer_id, get_workbench_kit_cat())


## Prüft bzw. verbraucht Schrauben und Paste. Gelöste Schrauben kommen in die Schale zurück.
func _use_bench_supplies(plan: Dictionary, task: Dictionary, amount: float, dry_run: bool) -> bool:
	var kind := str(task["kind"])
	if kind == "screw" or kind == "unscrew":
		var spec: Dictionary = (plan["items"] as Dictionary).get(str(task["item"]), {})
		if bool(spec.get("captive", false)) or bool(spec.get("own", false)):
			return true
		if kind == "screw":
			if bench_screws <= 0:
				return false
			if not dry_run:
				bench_screws -= 1
		elif not dry_run:
			bench_screws = mini(BENCH_SCREWS_MAX, bench_screws + 1)
		if not dry_run:
			_rpc_sync_bench_supplies.rpc(bench_screws, bench_paste)
	elif kind == "paste" and not is_workbench_paste_free():
		if bench_paste < AssemblyPlan.PASTE_MIN:
			return false
		if not dry_run:
			bench_paste = maxf(0.0, bench_paste - amount)
			_rpc_sync_bench_supplies.rpc(bench_screws, bench_paste)
	return true


## Im CPU-Kit liegt eine kleine Tube Paste bei.
func is_workbench_paste_free() -> bool:
	return str(AssemblyPlan.spare_of(workbench_state).get("kind", "")) == AssemblyPlan.SPARE_KIT


@rpc("authority", "call_local", "reliable")
func _rpc_sync_bench_tools(tools: Dictionary) -> void:
	bench_tools = _sanitize_bench_tools(tools)
	bench_supplies_changed.emit()


func _sanitize_bench_tools(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if raw is Dictionary:
		for k in BENCH_TOOLS.keys():
			if bool((raw as Dictionary).get(k, false)):
				out[k] = true
	return out


@rpc("authority", "call_local", "reliable")
func _rpc_sync_bench_supplies(screws: int, paste: float) -> void:
	bench_screws = clampi(screws, 0, BENCH_SCREWS_MAX)
	bench_paste = clampf(paste, 0.0, BENCH_PASTE_MAX)
	bench_supplies_changed.emit()


func _reject_workbench_task(peer_id: int, task_id: String) -> void:
	if peer_id <= 0:
		return
	_rpc_workbench_rejected.rpc_id(peer_id, task_id)
	_rpc_sync_workbench.rpc_id(peer_id, workbench_state.duplicate(true))


@rpc("authority", "call_local", "reliable")
func _rpc_workbench_rejected(task_id: String) -> void:
	workbench_task_rejected.emit(task_id)


## Teile unter Strom angefasst: Funken, Sicherung fliegt, das Mainboard nimmt Schaden.
func _workbench_short_circuit(peer_id: int, plan: Dictionary, done: Dictionary) -> void:
	done["power_off"] = 1.0
	# Der Testlauf zählt nicht: er muss wiederholt werden und zeigt dann den Schaden.
	done.erase("test_on")
	workbench_state.erase("test")
	var flaws: Array = (workbench_state.get("flaws", []) as Array).duplicate()
	if not flaws.has("live"):
		flaws.append("live")
	workbench_state["flaws"] = flaws
	var msg := "⚡ %s hat unter Strom gearbeitet: Kurzschluss! Die Bauqualität leidet."
	if has_bench_tool("rcd"):
		msg = "⚡ %s hat unter Strom gearbeitet: Der Personenschutz-Schalter hat rechtzeitig abgeschaltet."
	elif str(plan["repair_cat"]) != "mainboard":
		workbench_state["extra_fault"] = "mainboard"
		msg = "⚡ %s hat unter Strom gearbeitet: Kurzschluss! Das Mainboard ist beschädigt."
	_rpc_play_sfx.rpc("spark")
	post_event_f(msg, [get_worker_name(peer_id)], "alert")


## Testlauf nicht bestanden. Vergessene Kabel: nachstecken und neu testen. Zerstörte Teile: neue Reparatur.
func _handle_failed_test(peer_id: int) -> bool:
	var test: Dictionary = workbench_state.get("test", {}) if workbench_state.get("test", {}) is Dictionary else {}
	workbench_state.erase("test")
	if test.is_empty() or bool(test.get("ok", true)):
		return false
	var kind := str(test.get("kind", ""))
	if kind == "cable":
		var done: Dictionary = get_workbench_done().duplicate()
		done.erase("test_on")
		done.erase("test_off")
		workbench_state["done"] = done
		return true
	# Alles bisher Gebaute zählt weiter, dazu kommt jetzt das zerstörte Teil.
	var plan := AssemblyPlan.build(workbench_state)
	var done_now := AssemblyPlan.sanitize_done(plan, workbench_state.get("done", {}))
	workbench_state["build_quality"] = int(AssemblyPlan.quality(plan, done_now, workbench_state)["quality"])
	_apply_workbench_spare()
	workbench_state["mode"] = "repair"
	workbench_state["state"] = "crashed"
	workbench_state["faulty_part"] = kind
	workbench_state["diagnosed"] = true
	workbench_state["fault_hidden"] = kind == "mainboard"
	workbench_state["flaws"] = []
	for k in ["extra_fault", "kit_used", "spare", "spare_broken", "broken"]:
		workbench_state.erase(k)
	workbench_state["done"] = {"lid_out0": 1.0, "lid_out1": 1.0, "lid_off": 1.0}
	post_event_f("💥 Testlauf fehlgeschlagen: %s ist zerstört und muss ersetzt werden.", [get_component_label(kind)], "alert")
	_sfx_to(peer_id, "error")
	return true


## Ein aus dem Lager gewähltes Ersatzteil gehört nach dem Einbau zum Server.
func _apply_workbench_spare() -> void:
	var spare := AssemblyPlan.spare_of(workbench_state)
	if str(workbench_state.get("mode", "")) == "repair" and str(spare.get("kind", "")) == "part" and bool(workbench_state.get("kit_used", false)):
		var comps: Dictionary = (workbench_state.get("components", {}) as Dictionary).duplicate(true)
		comps[AssemblyPlan.repair_cat(workbench_state)] = str(spare.get("id", ""))
		workbench_state["components"] = comps


func _finish_workbench_job(peer_id: int) -> void:
	var mode := str(workbench_state.get("mode", ""))
	var plan := AssemblyPlan.build(workbench_state)
	var result := AssemblyPlan.quality(plan, AssemblyPlan.sanitize_done(plan, workbench_state.get("done", {})), workbench_state)
	_apply_workbench_spare()
	workbench_state["build_quality"] = int(result["quality"])
	workbench_state["mode"] = "ready_tray"
	workbench_state["state"] = "ok"
	workbench_state["faulty_part"] = ""
	workbench_state["diagnosed"] = false
	workbench_state["worker"] = 0
	for k in ["done", "kit_used", "spare", "spare_broken", "broken", "fault_hidden", "flaws", "test", "extra_fault"]:
		workbench_state.erase(k)
	_broadcast_workbench()
	_rpc_play_sfx.rpc("snap")
	var fmt := "🛠️ %s hat %s fertig zusammengebaut! Bauqualität %d %%."
	if mode == "repair":
		fmt = "✅ %s hat %s an der Werkbank repariert! Bauqualität %d %%."
	elif mode == "service":
		fmt = "🔧 %s hat %s überholt! Bauqualität %d %%."
	var q := int(result["quality"])
	post_event_f(fmt, [get_worker_name(peer_id), str(workbench_state.get("label", "Server")), q], "good" if q >= 75 else "warn")
	for n in (result["notes"] as Array).slice(0, 3):
		post_event_f("   Mangel: " + str(n[0]), n[1], "info")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_workbench_pickup() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if workbench_state.is_empty() or is_player_holding_anything(peer_id):
		_sfx_to(peer_id, "error")
		return
	var mode := str(workbench_state.get("mode", ""))
	# Angefangene Arbeit bleibt auf der Werkbank, sonst gingen eingebaute Teile verloren.
	if get_workbench_worker() != 0 or (is_workbench_job() and (is_workbench_started() or not (workbench_state.get("broken", []) as Array).is_empty())):
		_sfx_to(peer_id, "error")
		return
	_crate_from_bench(peer_id)
	workbench_state.clear()
	_broadcast_workbench()
	_broadcast_crates()
	_sfx_to(peer_id, "pickup")


## Inhalt der Werkbank als Kiste in die Hand nehmen; liefert die Kisten-ID.
func _crate_from_bench(peer_id: int) -> String:
	var mode := str(workbench_state.get("mode", ""))
	var cid := _alloc_id("crate")
	if mode == "build_box" or mode == "assembly":
		crates[cid] = {
			"id": cid,
			"item_type": "slot_build_box",
			"pos": Vector3.ZERO,
			"held_by": peer_id,
			"held_slot": get_active_slot(peer_id),
			"label": str(workbench_state.get("label", "Server-Bausatz")),
			"build_data": {
				"rack_id": str(workbench_state.get("rack_id", "")),
				"slot_idx": int(workbench_state.get("slot_idx", 0)),
				"rack_label": str(workbench_state.get("rack_label", "Rack")),
				"mainboard_id": str(workbench_state.get("mainboard_id", "web_server")),
				"components": (workbench_state.get("components", {}) as Dictionary).duplicate(true),
			},
		}
	else:
		var st := str(workbench_state.get("state", "ok"))
		var rlbl := str(workbench_state.get("label", "Server"))
		crates[cid] = {
			"id": cid,
			"item_type": "server_tray",
			"pos": Vector3.ZERO,
			"held_by": peer_id,
			"held_slot": get_active_slot(peer_id),
			"label": rlbl,
			"tray_data": {
				"mainboard_id": str(workbench_state.get("mainboard_id", "web_server")),
				"components": (workbench_state.get("components", {}) as Dictionary).duplicate(true),
				"state": st,
				"faulty_part": str(workbench_state.get("faulty_part", "")),
				"diagnosed": bool(workbench_state.get("diagnosed", false)),
				"fault_hidden": bool(workbench_state.get("fault_hidden", false)),
				"build_quality": get_build_quality(workbench_state),
				"source_rack_id": str(workbench_state.get("rack_id", "")),
				"source_slot_idx": int(workbench_state.get("slot_idx", 0)),
			},
		}
	return cid


func _broadcast_workbench() -> void:
	if not multiplayer.is_server():
		return
	_rpc_sync_workbench.rpc(workbench_state.duplicate(true))


@rpc("authority", "call_local", "reliable")
func _rpc_sync_workbench(data: Dictionary) -> void:
	workbench_state = data.duplicate(true)
	workbench_changed.emit()


# ==============================================================================
# MEILENSTEINE A–D: WETTER, AIRFLOW, KABELMANAGEMENT, KARRIERE, GEBRAUCHTMARKT,
# TEAM-AUFTRÄGE, 3D-PING & EMOTES
# ==============================================================================

func get_weather_label() -> String:
	match weather_state:
		"cloudy":
			return tr("Bewölkt")
		"rain":
			return tr("Regen")
		"storm":
			return tr("Gewitter")
		"heatwave":
			return tr("Hitzewelle")
		_:
			return tr("Sonnig")


func _tick_weather(dt: float) -> void:
	_weather_timer -= dt
	if _weather_timer > 0.0:
		return
	_weather_timer = randf_range(85.0, 145.0)
	var roll := randf()
	var next_w := "clear"
	if roll < 0.36:
		next_w = "clear"
	elif roll < 0.60:
		next_w = "cloudy"
	elif roll < 0.78:
		next_w = "rain"
	elif roll < 0.90 and day_number >= 2:
		next_w = "storm"
	elif day_number >= 2:
		next_w = "heatwave"
	if next_w == weather_state:
		return
	weather_state = next_w
	match weather_state:
		"rain":
			post_event("🌧 Regen zieht auf (-2,5 °C natürliche Außenkühlung).", "info")
		"storm":
			post_event("⛈ GEWITTER! Erhöhtes Risiko für Netzschwankungen – USV bereithalten!", "warn")
		"heatwave":
			post_event("☀ HITZEWELLE (+8,5 °C)! Klimaanlagen ziehen +22% Strom – Sicherungen & Temperaturen im Blick behalten!", "warn")
		"clear":
			post_event("🌤 Das Wetter klart wieder auf.", "info")


## Berechnet Kaltgang-/Warmgang-Airflow (bis +30 % Kühlleistung & weniger Klima-Strom)
## sowie den Kabelmanagement-Bonus (bis +12 % Umsatz-/Ruf-Bonus bei sauberer, kurzer Verkabelung).
func _recompute_layout_bonuses() -> void:
	var rids: Array = racks.keys()
	if rids.size() < 2:
		airflow_bonus = 0.08 if rids.size() == 1 else 0.0
	else:
		var good_pairs := 0
		var bad_pairs := 0
		for i in range(rids.size()):
			var ra: Dictionary = racks[rids[i]]
			var pa: Vector3 = ra.get("pos", Vector3.ZERO) as Vector3
			var ya: float = float(ra.get("rot_y", 0.0))
			var fwd_a := Vector2(sin(ya), cos(ya)).normalized()
			for j in range(i + 1, rids.size()):
				var rb: Dictionary = racks[rids[j]]
				var pb: Vector3 = rb.get("pos", Vector3.ZERO) as Vector3
				var yb: float = float(rb.get("rot_y", 0.0))
				var fwd_b := Vector2(sin(yb), cos(yb)).normalized()
				var d2 := Vector2(pb.x - pa.x, pb.z - pa.z)
				var dist := d2.length()
				if dist < 0.55 or dist > 3.5:
					continue
				var dir_ab := d2 / dist
				var f_dot := fwd_a.dot(fwd_b)
				# Kaltgang: zwei Racks stehen sich Front-an-Front gegenüber (1.1..3.4m)
				if fwd_a.dot(dir_ab) > 0.65 and fwd_b.dot(-dir_ab) > 0.65 and dist >= 1.05:
					good_pairs += 2
				# Saubere parallele Reihe nebeneinander (gleiche Ausrichtung, 0.8..1.35m Abstand)
				elif f_dot > 0.90 and absf(fwd_a.dot(dir_ab)) < 0.35 and dist <= 1.45:
					good_pairs += 1
				# Ungünstig: Abluft direkt in den Ansaugbereich des nächsten Racks (< 1.5m)
				elif f_dot > 0.85 and absf(fwd_a.dot(dir_ab)) > 0.72 and dist < 1.55:
					bad_pairs += 1
		var net_score := maxi(0, good_pairs - bad_pairs)
		airflow_bonus = clampf(float(net_score) * 0.06, 0.0, 0.30)

	# Kabelmanagement-Bonus: kurze, ordentliche Kabelwege ohne wildes Kreuz-und-Quer
	if cables.is_empty():
		cable_mgmt_bonus = 0.0
	else:
		var tidy := 0
		var total_c := 0
		for cid in cables.keys():
			var c: Dictionary = cables[cid]
			var pa := _approx_endpoint_pos(str(c.get("from_id", "")))
			var pb := _approx_endpoint_pos(str(c.get("to_id", "")))
			if pa == Vector3.ZERO and pb == Vector3.ZERO:
				continue
			total_c += 1
			var d := pa.distance_to(pb)
			if d <= 6.8:
				tidy += 1
		cable_mgmt_bonus = clampf((float(tidy) / float(maxi(1, total_c))) * 0.12, 0.0, 0.12)


func _approx_endpoint_pos(eid: String) -> Vector3:
	if racks.has(eid):
		return racks[eid].get("pos", Vector3.ZERO) as Vector3
	if coolers.has(eid):
		return coolers[eid].get("pos", Vector3.ZERO) as Vector3
	if ups_units.has(eid):
		return ups_units[eid].get("pos", Vector3.ZERO) as Vector3
	if eid == WALL_BREAKER_ID:
		return Vector3(-4.5, 1.5, -4.3)
	if eid == WALL_ROUTER_ID:
		return Vector3(0.4, 1.8, -4.3)
	if eid == HALL_C_BREAKER_ID:
		return Vector3(21.0, 1.5, -4.3)
	if eid == HALL_C_ROUTER_ID:
		return Vector3(21.0, 1.8, -2.5)
	if eid == HALL_NORD_BREAKER_ID:
		return HALLE_NORD_ORIGIN + Vector3(-8.2, 1.5, -5.7)
	if eid == HALL_NORD_ROUTER_ID:
		return HALLE_NORD_ORIGIN + Vector3(-4.6, 1.8, -5.7)
	return Vector3.ZERO


# --- Gebrauchtmarkt / Tages-Deals (B-Ware mit 35–45% Rabatt) ---

func _generate_daily_deals() -> void:
	if not multiplayer.is_server():
		return
	daily_deals.clear()
	var pool_items: Array[String] = ["rack", "web_server", "game_server", "storage_server", "ups", "cooler"]
	if get_company_level() >= 2:
		pool_items.append("cloud_server")
	if get_company_level() >= 3:
		pool_items.append("rack_pro")
		pool_items.append("ai_server")
	pool_items.shuffle()
	var count := mini(3, pool_items.size())
	for i in range(count):
		var itype := pool_items[i]
		if not ITEM_CATALOG.has(itype):
			continue
		var meta: Dictionary = ITEM_CATALOG[itype]
		var orig := int(meta["price"])
		var disc_pct := randi_range(35, 45)
		var deal_price := maxi(50, int(roundf(float(orig) * (1.0 - float(disc_pct) / 100.0))))
		daily_deals.append({
			"deal_id": "deal_d%d_%d" % [day_number, i],
			"item_type": itype,
			"name": str(meta["name"]) + " (B-Ware)",
			"seller": USED_SELLERS[(day_number + i) % USED_SELLERS.size()],
			"orig_price": orig,
			"price": deal_price,
			"discount_pct": disc_pct,
			"sold": false,
		})
	_rpc_sync_daily_deals.rpc(daily_deals.duplicate(true))


@rpc("authority", "call_local", "reliable")
func _rpc_sync_daily_deals(deals: Array) -> void:
	daily_deals = deals.duplicate(true)
	daily_deals_changed.emit()


func request_buy_daily_deal(deal_id: String) -> void:
	_rpc_req_buy_daily_deal.rpc_id(1, deal_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_buy_daily_deal(deal_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "buy", 8, 5.0):
		return
	if get_delivery_zone_free_slots() < 1:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		post_event("Lieferzone voll! Erst Pakete aus der Einfahrt räumen.", "warn")
		return
	var found_idx := -1
	for i in range(daily_deals.size()):
		if str(daily_deals[i].get("deal_id", "")) == deal_id:
			found_idx = i
			break
	if found_idx < 0 or bool(daily_deals[found_idx].get("sold", false)):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var deal: Dictionary = daily_deals[found_idx]
	var price := float(deal["price"])
	if money < price:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var item_type := str(deal["item_type"])
	if not ITEM_CATALOG.has(item_type):
		return
	money -= price
	deal["sold"] = true
	if van_phase == "arriving" or van_phase == "unloading":
		van_cargo.append(item_type)
		if van_phase == "arriving":
			van_delivery_tier = maxi(van_delivery_tier, compute_delivery_tier(van_cargo))
	else:
		pending_delivery_items.append(item_type)
		if van_phase == "idle":
			van_cargo = _pack_van_cargo(pending_delivery_items)
			pending_delivery_items.clear()
			scheduled_delivery_day = 0
			scheduled_delivery_hour = -1
			pending_delivery_express = false
			van_delivery_tier = compute_delivery_tier(van_cargo)
			van_phase = "arriving"
			van_phase_time = 0.0
			_van_unload_accum = 0.0
			_reset_van_trip()
	_rpc_sync_daily_deals.rpc(daily_deals.duplicate(true))
	_broadcast_van_state()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("cash")
	post_event_f("%s schnappte sich %s für $%d (-%d%%) aus dem Gebrauchtmarkt!", [
		NetworkManager.get_player_name(peer_id), str(deal["name"]), int(price), int(deal["discount_pct"])
	], "good")


# --- Karriere-Meilensteine (bodenständige Großkunden-Ziele) ---

func _check_career_milestones() -> void:
	if not multiplayer.is_server():
		return
	var has_ups := false
	for u in ups_units.values():
		if bool((u as Dictionary).get("connected", false)):
			has_ups = true
			break
	for m_v in CAREER_MILESTONES:
		var m: Dictionary = m_v
		var mid := str(m["id"])
		if career_completed.has(mid):
			continue
		if racks.size() < int(m["req_racks"]):
			continue
		if total_compute < int(m["req_cu"]):
			continue
		if room_level < int(m["req_room"]):
			continue
		if bool(m["req_ups"]) and not has_ups:
			continue
		if reputation < float(m["req_rep"]):
			continue
		if ai_platform_level < int(m["req_ai"]):
			continue
		if mid == "career_esports" and room_temp >= 65.0:
			continue
		career_completed.append(mid)
		var reward := float(m["reward"])
		money += reward
		reputation = clampf(reputation + float(m["rep_bonus"]), 0.0, 100.0)
		_rpc_play_sfx.rpc("upgrade")
		post_event_f("🏆 KARRIERE-MEILENSTEIN: '%s' (%s) erreicht! Prämie: +$%d & +%.0f Ruf!", [
			str(m["title"]), str(m["client"]), int(reward), float(m["rep_bonus"])
		], "good")


# --- Co-op Team-Aufträge (zeitbasierte Bonusziele) ---

func _roll_team_order() -> void:
	if not multiplayer.is_server():
		return
	var active_slots := 0
	for rk in racks.values():
		for sl in (rk as Dictionary).get("slots", []):
			if not str((sl as Dictionary).get("item_type", "")).is_empty():
				active_slots += 1
	var pick := day_number % 3
	if pick == 0:
		active_team_order = {
			"kind": "uptime_streak",
			"title": "Team-Auftrag: 90 Sek. störungsfreier Betrieb",
			"progress": 0.0,
			"target": 90.0,
			"reward": 850 + day_number * 220,
			"done": false,
		}
	elif pick == 1:
		var goal_slots := maxi(2, active_slots + 2)
		active_team_order = {
			"kind": "expand_slots",
			"title": "Team-Auftrag: %d aktive Server-Einschübe betreiben" % goal_slots,
			"progress": float(active_slots),
			"target": float(goal_slots),
			"reward": 1100 + day_number * 260,
			"done": false,
		}
	else:
		active_team_order = {
			"kind": "cool_ops",
			"title": "Team-Auftrag: 75 Sek. unter 50 °C Raumtemperatur",
			"progress": 0.0,
			"target": 75.0,
			"reward": 950 + day_number * 240,
			"done": false,
		}


func _tick_team_order(dt: float) -> void:
	if not multiplayer.is_server() or active_team_order.is_empty() or bool(active_team_order.get("done", false)):
		return
	var kind := str(active_team_order.get("kind", ""))
	var target := float(active_team_order.get("target", 90.0))
	var prog := float(active_team_order.get("progress", 0.0))
	if kind == "uptime_streak":
		if (breaker_on or ups_backup_active) and not has_any_fire() and not ddos_active and racks.size() >= 1:
			prog += dt
	elif kind == "cool_ops":
		if (breaker_on or ups_backup_active) and room_temp < 50.0 and racks.size() >= 1:
			prog += dt
	elif kind == "expand_slots":
		var running := 0
		for rk in racks.values():
			if bool((rk as Dictionary).get("powered", false)):
				for sl in (rk as Dictionary).get("slots", []):
					if not str((sl as Dictionary).get("item_type", "")).is_empty() and str((sl as Dictionary).get("state", "")) == "ok":
						running += 1
		prog = float(running)
	active_team_order["progress"] = minf(prog, target)
	if prog >= target:
		active_team_order["done"] = true
		var rew := int(active_team_order.get("reward", 1000))
		money += float(rew)
		reputation = clampf(reputation + 2.5, 0.0, 100.0)
		_rpc_play_sfx.rpc("cash")
		post_event_f("🤝 %s abgeschlossen! Team-Bonus: +$%d!", [str(active_team_order["title"]), rew], "good")


# --- 3D-Ping-System & Spieler-Emotes (Co-op) ---

func request_world_ping(world_pos: Vector3, kind: String = "look", label: String = "Schau her!") -> void:
	_rpc_req_world_ping.rpc_id(1, world_pos, kind, label)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_world_ping(world_pos: Vector3, kind: String, label: String) -> void:
	if not multiplayer.is_server():
		return
	if not SecurityGuard.is_finite_vec3(world_pos):
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "ping", 4, 5.0, false):
		return
	var safe_kind := kind.left(16)
	var safe_label := SecurityGuard.sanitize_label(label, 28, "Schau her!")
	_rpc_broadcast_world_ping.rpc(peer_id, world_pos, safe_kind, safe_label)


@rpc("authority", "call_local", "reliable")
func _rpc_broadcast_world_ping(peer_id: int, world_pos: Vector3, kind: String, label: String) -> void:
	SfxManager.play("ping", -8.0, 1.08 if kind == "alert" else 1.0)
	world_ping_received.emit(peer_id, world_pos, kind, label)


func request_player_emote(emote_id: String) -> void:
	_rpc_req_player_emote.rpc_id(1, emote_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_player_emote(emote_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "emote", 3, 4.0, false):
		return
	if emote_id != "wave" and emote_id != "thumbs_up":
		return
	_rpc_broadcast_player_emote.rpc(peer_id, emote_id)


@rpc("authority", "call_local", "reliable")
func _rpc_broadcast_player_emote(peer_id: int, emote_id: String) -> void:
	SfxManager.play("emote", -10.0, 1.05 if emote_id == "thumbs_up" else 0.96)
	player_emote_received.emit(peer_id, emote_id)


# --- Großstandort Halle Nord (240 m², ab Firmen-Level 3, eigene Strom-/Fiber-/Lieferzone) ---

func get_discounted_price(base_price: float) -> int:
	return maxi(1, int(roundf(base_price * get_level_discount_mult())))


func request_buy_halle_nord() -> void:
	_rpc_req_buy_halle_nord.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_buy_halle_nord() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if halle_nord_owned:
		return
	if get_company_level() < HALLE_NORD_REQ_LEVEL or money < float(HALLE_NORD_COST):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money -= float(HALLE_NORD_COST)
	halle_nord_owned = true
	_recalculate_networks_and_metrics()
	_rpc_sync_halle_nord.rpc(true, delivery_target_site)
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("upgrade")
	post_event_f("🏭 %s hat Großstandort HALLE NORD (240 m²) gekauft! Drücke [T] oder nutze das Shuttle-Terminal zum Teleportieren.", [
		NetworkManager.get_player_name(peer_id)
	], "good")


func request_set_delivery_site(site: String) -> void:
	_rpc_req_set_delivery_site.rpc_id(1, site)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_set_delivery_site(site: String) -> void:
	if not multiplayer.is_server():
		return
	var target := "halle_nord" if (site == "halle_nord" and halle_nord_owned) else "garage"
	delivery_target_site = target
	_rpc_sync_halle_nord.rpc(halle_nord_owned, delivery_target_site)
	_broadcast_sim_tick()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_halle_nord(owned: bool, del_site: String) -> void:
	var changed_site := (delivery_target_site != del_site)
	halle_nord_owned = owned
	delivery_target_site = del_site if owned else "garage"
	# Immer melden: Beim Host ist der Wert hier schon gesetzt, der Hallenboden muss trotzdem aktiviert werden.
	halle_nord_changed.emit()
	if changed_site:
		delivery_site_changed.emit()
	state_updated.emit()



# ---------------------------------------------------------------- Kaufbare Einrichtung, Gebäude-Upgrades & Tiefes Wartungssystem

func is_decor_type(item_type: String) -> bool:
	return bool((ITEM_CATALOG.get(item_type, {}) as Dictionary).get("is_decor", false))


func has_building_upgrade(uid: String) -> bool:
	return bool(building_upgrades.get(uid, false))


func is_construction_active(uid: String) -> bool:
	return active_constructions.has(uid)


func get_repair_speed_multiplier() -> float:
	var mult := 1.0
	for did in decor_items.keys():
		if str((decor_items[did] as Dictionary).get("item_type", "")) == "prop_esd_workbench":
			mult = 1.35
			break
	return mult


func get_fault_diagnosis_info(slot: Dictionary) -> Dictionary:
	var part := str(slot.get("faulty_part", ""))
	if FAULT_DIAGNOSIS_META.has(part):
		return FAULT_DIAGNOSIS_META[part] as Dictionary
	return {"code": "ERR-GEN-01", "cause": "Allgemeine Hardware-Störung", "tool": "Wartungs-Kit"}


func get_maintenance_warnings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rid in racks.keys():
		var rack: Dictionary = racks[rid]
		var slots: Array = rack.get("slots", [])
		for i in range(slots.size()):
			var sl: Dictionary = slots[i]
			if str(sl.get("item_type", "")) == "":
				continue
			var dust := float(sl.get("dust_level", 0.0))
			var th_hp := float(sl.get("thermal_health", 100.0))
			if str(sl.get("state", "ok")) != "ok" or dust >= 65.0 or th_hp <= 35.0:
				out.append({
					"rack_id": rid,
					"rack_name": get_rack_display_name(rid),
					"slot_idx": i,
					"state": str(sl.get("state", "ok")),
					"dust": int(roundf(dust)),
					"health": int(roundf(th_hp)),
				})
	return out


func request_buy_building_upgrade(uid: String) -> void:
	_rpc_req_buy_building_upgrade.rpc_id(1, uid)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_buy_building_upgrade(uid: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not BUILDING_UPGRADE_CATALOG.has(uid):
		return
	if has_building_upgrade(uid) or is_construction_active(uid):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var meta: Dictionary = BUILDING_UPGRADE_CATALOG[uid]
	if bool(meta.get("req_nord", false)) and not halle_nord_owned:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var price := float(meta.get("price", 0))
	if money < price:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money -= price
	var dur := float(meta.get("duration", 50.0))
	active_constructions[uid] = {
		"remaining": dur,
		"duration": dur,
		"site": "halle_nord" if bool(meta.get("req_nord", false)) else ("halle_nord" if halle_nord_owned else "garage"),
	}
	_broadcast_building_upgrades()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("upgrade")
	post_event_f("🚧 Bautrupp beauftragt: %s! Handwerker rücken an (Bauzeit ca. %d s).", [
		str(meta["name"]), int(roundf(dur))
	], "good")


func _tick_constructions(dt: float) -> void:
	if active_constructions.is_empty():
		return
	var finished: Array[String] = []
	for uid in active_constructions.keys():
		var c: Dictionary = active_constructions[uid]
		c["remaining"] = maxf(0.0, float(c.get("remaining", 0.0)) - dt)
		if float(c["remaining"]) <= 0.0:
			finished.append(str(uid))
	if not finished.is_empty():
		for uid in finished:
			active_constructions.erase(uid)
			building_upgrades[uid] = true
			var meta: Dictionary = BUILDING_UPGRADE_CATALOG.get(uid, {})
			if uid == "upg_security_gate":
				reputation = minf(100.0, reputation + 8.0)
			post_event_f("✅ Bauarbeiten abgeschlossen: %s ist jetzt einsatzbereit!", [str(meta.get("name", uid))], "good")
		_recalculate_networks_and_metrics()
		_broadcast_building_upgrades()
		_rpc_play_sfx.rpc("save")


## Wartung lohnt sich erst ab sichtbarem Staub bzw. gealterter Wärmeleitpaste.
func is_slot_maintainable(slot: Dictionary) -> bool:
	return roundf(float(slot.get("dust_level", 0.0))) >= MAINTAIN_MIN_DUST \
		or roundf(float(slot.get("thermal_health", 100.0))) <= MAINTAIN_MAX_THERMAL


func request_maintain_slot(rack_id: String, slot_idx: int) -> void:
	_rpc_req_maintain_slot.rpc_id(1, rack_id, slot_idx)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_maintain_slot(rack_id: String, slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "maintain", 10, 5.0):
		return
	if not racks.has(rack_id):
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	if str(slot.get("item_type", "")) == "" or str(slot.get("state", "ok")) != "ok":
		return
	if not is_slot_maintainable(slot):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	if maint_kits <= 0:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		post_event("Keine Wartungs-Kits mehr! Am PC im Shop oder am Ersatzteil-Schrank auffüllen.", "warn")
		return
	maint_kits -= 1
	slot["dust_level"] = 0.0
	slot["thermal_health"] = 100.0
	racks[rack_id]["temp"] = maxf(22.0, float(racks[rack_id].get("temp", 35.0)) - 3.0)
	_broadcast_racks()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("repair")
	post_event_f("🧹 %s hat %s Slot %d gewartet (Staub 0 %%, Wärmeleitpaste 100 %% — Ausfallrisiko minimal!).", [
		NetworkManager.get_player_name(peer_id), get_rack_display_name(rack_id), slot_idx + 1
	], "good")


func request_refill_maint_kits() -> void:
	_rpc_req_refill_maint_kits.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_refill_maint_kits() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if maint_kits >= 12:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var has_cabinet := false
	for did in decor_items.keys():
		if str((decor_items[did] as Dictionary).get("item_type", "")) == "prop_parts_cabinet":
			has_cabinet = true
			break
	var cost := 20.0 if has_cabinet else 45.0
	if money < cost:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money -= cost
	maint_kits = mini(12, maint_kits + 3)
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("snap")
	post_event_f("🧰 +3 Wartungs- & Ersatzteil-Kits aufgefüllt (Vorrat: %d, Kosten: $%d).", [maint_kits, int(cost)], "good")


func get_decor_name(decor_id: String) -> String:
	var itype := str((decor_items.get(decor_id, {}) as Dictionary).get("item_type", ""))
	return str((ITEM_CATALOG.get(itype, {}) as Dictionary).get("name", decor_id))


func request_relocate_decor(decor_id: String, pos: Vector3, rot_y: float) -> void:
	_rpc_req_relocate_decor.rpc_id(1, decor_id, pos, rot_y)


## Einrichtung umsetzen. Kabel und eingelagerte Kisten bleiben dran.
@rpc("any_peer", "call_local", "reliable")
func _rpc_req_relocate_decor(decor_id: String, pos: Vector3, rot_y: float) -> void:
	if not multiplayer.is_server():
		return
	if not SecurityGuard.is_finite_vec3(pos) or not SecurityGuard.is_finite_float(rot_y):
		return
	var peer_id := _get_sender_id()
	if not decor_items.has(decor_id) or not SecurityGuard.check_rate_limit(peer_id, "relocate", 10, 5.0):
		return
	var d: Dictionary = decor_items[decor_id]
	var itype := str(d.get("item_type", ""))
	var snapped := snap_place_pos(itype, pos)
	if not can_place_item_at(itype, snapped, rot_y, decor_id):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	d["pos"] = snapped
	d["rot_y"] = rot_y
	d["wall"] = is_strip_type(itype) and snapped.y >= STRIP_WALL_MIN_Y
	_recalculate_networks_and_metrics()
	_broadcast_decor_items()
	_broadcast_cables()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("place")


func request_sell_decor(decor_id: String) -> void:
	_rpc_req_sell_decor.rpc_id(1, decor_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_sell_decor(decor_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "sell", 6, 5.0):
		return
	if not is_destructive_action_allowed(peer_id):
		_deny_destructive_action(peer_id, "Einrichtung verkaufen")
		return
	if not decor_items.has(decor_id):
		return
	var d: Dictionary = decor_items[decor_id]
	var itype := str(d.get("item_type", ""))
	var refund := int(roundf(float((ITEM_CATALOG.get(itype, {}) as Dictionary).get("price", 0)) * SELL_REFUND_RATIO))
	_disconnect_all_cables_of(decor_id)
	# Eingelagerte Kisten bleiben am Standort des Regals stehen.
	var base_pos: Vector3 = d.get("pos", Vector3.ZERO) as Vector3
	var stored_v: Variant = d.get("stored_items", [])
	if stored_v is Array:
		var dropped := 0
		for item_v in (stored_v as Array):
			if not (item_v is Dictionary):
				continue
			var crate: Dictionary = (item_v as Dictionary).duplicate(true)
			var cid := _alloc_id("crate")
			crate["id"] = cid
			crate["held_by"] = 0
			crate["pos"] = _clamp_drop_pos(base_pos + Vector3(-0.6 + float(dropped) * 0.4, 0.0, 0.0))
			crates[cid] = crate
			dropped += 1
	decor_items.erase(decor_id)
	money += float(refund)
	_recalculate_networks_and_metrics()
	_broadcast_cables()
	_broadcast_racks()
	_broadcast_coolers()
	_broadcast_ups()
	_broadcast_crates()
	_broadcast_decor_items()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("sell")
	post_event_f("%s hat %s für +$%d verkauft.", [
		NetworkManager.get_player_name(peer_id), str((ITEM_CATALOG.get(itype, {}) as Dictionary).get("name", itype)), refund
	], "good")


func request_decor_shelf_interact(decor_id: String, slot_idx: int) -> void:
	_rpc_req_decor_shelf_interact.rpc_id(1, decor_id, slot_idx)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_decor_shelf_interact(decor_id: String, slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not decor_items.has(decor_id):
		return
	var d: Dictionary = decor_items[decor_id]
	if str(d.get("item_type", "")) != "prop_storage_shelf":
		return
	var stored: Array = d.get("stored_items", [null, null, null, null])
	if slot_idx < 0 or slot_idx >= stored.size():
		return
	var held := get_player_held_crate(peer_id)
	if not held.is_empty():
		if stored[slot_idx] != null:
			_rpc_play_sfx.rpc_id(peer_id, "error")
			return
		var cid := str(held["id"])
		stored[slot_idx] = crates[cid].duplicate(true)
		(stored[slot_idx] as Dictionary)["held_by"] = 0
		crates.erase(cid)
		d["stored_items"] = stored
		_broadcast_crates()
		_broadcast_decor_items()
		_rpc_play_sfx.rpc("place")
	else:
		if stored[slot_idx] == null or is_player_holding_anything(peer_id):
			return
		var item_d: Dictionary = (stored[slot_idx] as Dictionary).duplicate(true)
		var new_cid := _alloc_id("crate")
		item_d["id"] = new_cid
		item_d["held_by"] = peer_id
		item_d["held_slot"] = get_active_slot(peer_id)
		crates[new_cid] = item_d
		stored[slot_idx] = null
		d["stored_items"] = stored
		_broadcast_crates()
		_broadcast_decor_items()
		_rpc_play_sfx.rpc("pickup")


func _broadcast_decor_items() -> void:
	_rpc_sync_decor_items.rpc(decor_items.duplicate(true))


@rpc("authority", "call_local", "reliable")
func _rpc_sync_decor_items(data: Dictionary) -> void:
	decor_items = data.duplicate(true)
	decor_items_changed.emit()


func _broadcast_building_upgrades() -> void:
	_rpc_sync_building_upgrades.rpc(building_upgrades.duplicate(true), active_constructions.duplicate(true))


@rpc("authority", "call_local", "reliable")
func _rpc_sync_building_upgrades(bu: Dictionary, ac: Dictionary) -> void:
	building_upgrades = bu.duplicate(true)
	active_constructions = ac.duplicate(true)
	building_upgrades_changed.emit()
	constructions_changed.emit()
	state_updated.emit()
