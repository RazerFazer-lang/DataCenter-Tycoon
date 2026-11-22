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
signal room_level_changed
signal van_updated
signal tickets_changed
signal call_changed
signal inventory_changed
## Sicherungen im Wand-Sicherungskasten oder der Sicherungsvorrat haben sich geändert.
signal fuses_changed
## Türen, Seitenwände und Antenne (Racks, Sicherungskasten, Router) wurden geöffnet/geschlossen.
signal panel_states_changed

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
## Wasserschaden: Abstand zwischen zwei Lecks in Sekunden, betroffene Slots und Kosten.
const WATER_LEAK_MIN_S := 240.0
const WATER_LEAK_MAX_S := 420.0
const WATER_LEAK_MAX_SLOTS := 2
const WATER_LEAK_COST := 150.0
const PAYOUT_CYCLE_SECONDS := 5.0
const AUTOSAVE_INTERVAL := 180.0
# Echtzeit: ein Spieltag dauert einen echten Tag.
const DAY_LENGTH_SECONDS := 86400.0
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
# Abladen in Fahrten: Der Fahrer trägt 1 Karton von Hand oder bis zu 4 auf der Sackkarre.
const VAN_TRIP_MAX_CRATES := 4
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
		"slots": 6,
		"max_pdu_watts": 6000,
		"passive_cooling": 4.0,
		"watts": 0,
		"compute": 0,
		"heat": 0.0,
		"color": Color(0.18, 0.44, 0.62),
		"desc": "6 Einschub-Slots | Max. 6.000W PDU | Aktiv-Kühlung (-4°C)",
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
		"name": "Gigabyte GA-H110M Mini-Server",
		"category": "module", "mainboard": true, "mb_cat": "entry", "chassis": "web_server", "form": "1U",
		"price": 120, "watts": 35, "compute": 3, "base_compute": 3, "heat": 1.2, "revenue_bonus": 0.0,
		"color": Color(0.36, 0.62, 0.86),
		"desc": "Günstiges Single-Sockel-Board • 2 RAM-Bänke • Ideal für den ersten Webserver",
	},
	"mb_b450m_pro4": {
		"name": "ASRock B450M Pro4 Server",
		"category": "module", "mainboard": true, "mb_cat": "entry", "chassis": "web_server", "form": "1U",
		"price": 160, "watts": 40, "compute": 4, "base_compute": 4, "heat": 1.4, "revenue_bonus": 0.0,
		"color": Color(0.36, 0.62, 0.86),
		"desc": "AM4-Board • 4 RAM-Bänke • M.2-Steckplatz für schnelle NVMe-SSDs",
	},
	"mb_x570d4u": {
		"name": "ASRock Rack X570D4U",
		"category": "module", "mainboard": true, "mb_cat": "entry", "chassis": "web_server", "form": "1U",
		"price": 230, "watts": 45, "compute": 5, "base_compute": 5, "heat": 1.6, "revenue_bonus": 0.02,
		"color": Color(0.36, 0.62, 0.86),
		"desc": "Server-AM4 mit Fernwartung (IPMI) • ECC-RAM • +2% Einnahmen",
	},
	"mb_x11scl_f": {
		"name": "Supermicro X11SCL-F",
		"category": "module", "mainboard": true, "mb_cat": "entry", "chassis": "web_server", "form": "1U",
		"price": 260, "watts": 40, "compute": 5, "base_compute": 5, "heat": 1.5, "revenue_bonus": 0.03,
		"color": Color(0.36, 0.62, 0.86),
		"desc": "Xeon-E-Board mit IPMI • Sehr stabil • +3% Einnahmen",
	},
	"mb_x11dpi_n": {
		"name": "Supermicro X11DPi-N (Dual-Sockel)",
		"category": "module", "mainboard": true, "mb_cat": "server", "chassis": "web_server", "form": "1U",
		"price": 380, "watts": 60, "compute": 7, "base_compute": 7, "heat": 2.2, "revenue_bonus": 0.04,
		"color": Color(0.52, 0.48, 0.90),
		"desc": "2 Xeon-Sockel • 16 RAM-Bänke • Für Webhosting mit vielen Nutzern",
	},
	"mb_romed8_2t": {
		"name": "ASRock Rack ROMED8-2T",
		"category": "module", "mainboard": true, "mb_cat": "server", "chassis": "web_server", "form": "1U",
		"price": 520, "watts": 70, "compute": 9, "base_compute": 9, "heat": 2.6, "revenue_bonus": 0.05,
		"color": Color(0.52, 0.48, 0.90),
		"desc": "EPYC-Board • 8 RAM-Kanäle • 2× 10-GbE • +5% Einnahmen",
	},
	"mb_mz73_lm0": {
		"name": "Gigabyte MZ73-LM0 (Dual EPYC)",
		"category": "module", "mainboard": true, "mb_cat": "server", "chassis": "web_server", "form": "1U",
		"price": 780, "watts": 85, "compute": 11, "base_compute": 11, "heat": 3.0, "revenue_bonus": 0.06,
		"color": Color(0.52, 0.48, 0.90),
		"desc": "2 EPYC-Sockel • 24 RAM-Bänke • Für Datenbanken & große Kunden",
	},
	"mb_x13dei_t": {
		"name": "Supermicro X13DEI-T (Dual Xeon)",
		"category": "module", "mainboard": true, "mb_cat": "server", "chassis": "web_server", "form": "1U",
		"price": 950, "watts": 90, "compute": 12, "base_compute": 12, "heat": 3.2, "revenue_bonus": 0.07,
		"color": Color(0.52, 0.48, 0.90),
		"desc": "Aktuelle Dual-Xeon-Plattform • DDR5 • +7% Einnahmen",
	},
	"mb_x10sdv_4c": {
		"name": "Supermicro X10SDV-4C NAS",
		"category": "module", "mainboard": true, "mb_cat": "storage", "chassis": "storage_server", "form": "2U",
		"price": 240, "watts": 35, "compute": 5, "base_compute": 5, "heat": 1.3, "revenue_bonus": 0.08,
		"color": Color(0.24, 0.68, 0.48),
		"desc": "Sparsames NAS-Board • 6 SATA-Ports • +8% Einnahmen bei Speicher",
	},
	"mb_x11ssh_ctf": {
		"name": "Supermicro X11SSH-CTF (SAS)",
		"category": "module", "mainboard": true, "mb_cat": "storage", "chassis": "storage_server", "form": "2U",
		"price": 340, "watts": 50, "compute": 6, "base_compute": 6, "heat": 1.8, "revenue_bonus": 0.09,
		"color": Color(0.24, 0.68, 0.48),
		"desc": "SAS-Controller onboard • 8 Hot-Swap-Laufwerke • +9% Einnahmen",
	},
	"mb_h12ssl_nt": {
		"name": "Supermicro H12SSL-NT Storage",
		"category": "module", "mainboard": true, "mb_cat": "storage", "chassis": "storage_server", "form": "2U",
		"price": 520, "watts": 65, "compute": 8, "base_compute": 8, "heat": 2.3, "revenue_bonus": 0.11,
		"color": Color(0.24, 0.68, 0.48),
		"desc": "EPYC-Storage-Board • viele NVMe-Lanes • +11% Einnahmen",
	},
	"mb_genoad8x_2t": {
		"name": "ASRock Rack GENOAD8X-2T",
		"category": "module", "mainboard": true, "mb_cat": "storage", "chassis": "storage_server", "form": "2U",
		"price": 860, "watts": 80, "compute": 10, "base_compute": 10, "heat": 2.8, "revenue_bonus": 0.14,
		"color": Color(0.24, 0.68, 0.48),
		"desc": "All-Flash-Plattform • DDR5 • +14% Einnahmen bei Cloud-Speicher",
	},
	"mb_ws_x299_sage": {
		"name": "ASUS WS X299 SAGE (4× PCIe)",
		"category": "module", "mainboard": true, "mb_cat": "gpu", "chassis": "gpu_server", "form": "4U",
		"price": 420, "watts": 70, "compute": 10, "base_compute": 10, "heat": 2.6, "revenue_bonus": 0.03,
		"color": Color(0.84, 0.58, 0.18),
		"desc": "4 PCIe-x16-Plätze • Für Streaming & Render-Server",
	},
	"mb_trx50_sage": {
		"name": "ASUS Pro WS TRX50-SAGE",
		"category": "module", "mainboard": true, "mb_cat": "gpu", "chassis": "gpu_server", "form": "4U",
		"price": 680, "watts": 85, "compute": 12, "base_compute": 12, "heat": 3.0, "revenue_bonus": 0.05,
		"color": Color(0.84, 0.58, 0.18),
		"desc": "Threadripper-Board • 3 GPU-Plätze • +5% Einnahmen",
	},
	"mb_wrx90e_sage": {
		"name": "ASUS Pro WS WRX90E-SAGE",
		"category": "module", "mainboard": true, "mb_cat": "gpu", "chassis": "gpu_server", "form": "4U",
		"price": 980, "watts": 100, "compute": 14, "base_compute": 14, "heat": 3.6, "revenue_bonus": 0.07,
		"color": Color(0.84, 0.58, 0.18),
		"desc": "Threadripper PRO • 7 PCIe-5.0-Plätze • Für KI-Hosting",
	},
	"mb_hgx_8gpu": {
		"name": "NVIDIA HGX 8-GPU Baseboard",
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
		"desc": "Kühlt Raum um -18°C | 300W (Stromkabel nötig)",
	},
	"chiller": {
		"name": "Industrie-Kühler AC-Pro",
		"category": "placeable",
		"price": 850,
		"watts": 540,
		"compute": 0,
		"heat": -40.0,
		"color": Color(0.28, 0.76, 0.98),
		"desc": "Doppellüfter-Kühler (-40°C!) | 540W (Stromkabel nötig)",
	},
	"ups": {
		"name": "USV-Notstrom-Batterie",
		"category": "placeable",
		"price": 700,
		"watts": 120,
		"compute": 0,
		"heat": 1.0,
		"color": Color(0.95, 0.68, 0.14),
		"desc": "Übernimmt bei Blackout sofort unterbrechungsfrei Strom!",
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
}

const COMPONENT_ORDER := ["cpu", "gpu", "ram", "storage", "cooling", "psu"]

const COMPONENT_CATALOG := {
	"cpu": {
		"label": "Prozessor (CPU)",
		"icon": "🧠",
		"tiers": [
			{"name": "Standard Xeon 8-Core", "cost": 0, "compute": 0, "watts": 0, "heat": 0.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "Multi-Core EPYC 32C", "cost": 220, "compute": 10, "watts": 60, "heat": 2.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "Dual-Socket Pro 96C", "cost": 520, "compute": 24, "watts": 140, "heat": 4.5, "watt_mult": 1.0, "fault_mult": 0.95},
			{"name": "Enterprise 192-Core", "cost": 1150, "compute": 52, "watts": 240, "heat": 8.0, "watt_mult": 1.0, "fault_mult": 0.90},
		],
	},
	"gpu": {
		"label": "Grafikkarte (GPU)",
		"icon": "🎮",
		"tiers": [
			{"name": "Integrierte Grafik", "cost": 0, "compute": 0, "watts": 0, "heat": 0.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "RTX Compute 4090", "cost": 340, "compute": 18, "watts": 180, "heat": 6.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "Dual Tensor AI-GPU", "cost": 780, "compute": 44, "watts": 340, "heat": 11.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "Quad H200 AI-Cluster", "cost": 1650, "compute": 95, "watts": 560, "heat": 18.0, "watt_mult": 1.0, "fault_mult": 1.0},
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
			{"name": "Optane Ultra-Array", "cost": 820, "compute": 22, "watts": 45, "heat": 1.2, "watt_mult": 1.0, "fault_mult": 0.35},
		],
	},
	"cooling": {
		"label": "Server-Kühlung",
		"icon": "❄️",
		"tiers": [
			{"name": "Standard-Lüfter", "cost": 0, "compute": 0, "watts": 0, "heat": 0.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "High-Airflow Noctua", "cost": 140, "compute": 0, "watts": 15, "heat": -4.0, "watt_mult": 1.0, "fault_mult": 0.90},
			{"name": "Vapor-Chamber Pro", "cost": 340, "compute": 0, "watts": 30, "heat": -9.0, "watt_mult": 1.0, "fault_mult": 0.78},
			{"name": "Direct-Liquid Coldplate", "cost": 720, "compute": 0, "watts": 45, "heat": -16.0, "watt_mult": 1.0, "fault_mult": 0.62},
		],
	},
	"psu": {
		"label": "Netzteil (PSU)",
		"icon": "🔌",
		"tiers": [
			{"name": "80+ Bronze (Standard)", "cost": 0, "compute": 0, "watts": 0, "heat": 0.0, "watt_mult": 1.0, "fault_mult": 1.0},
			{"name": "80+ Gold Effizienz", "cost": 160, "compute": 0, "watts": 0, "heat": -1.0, "watt_mult": 0.88, "fault_mult": 0.90},
			{"name": "80+ Platinum Pro", "cost": 390, "compute": 0, "watts": 0, "heat": -2.2, "watt_mult": 0.76, "fault_mult": 0.75},
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
## Steckleisten am Stromkasten und Netzwerk-Verteiler am Router (im Shop unter "Klima & USV").
## Ohne Zubehör: 1 Steckdose am Stromkasten, 2 Netzwerkdosen am Router.
const BREAKER_BASE_SOCKETS := 1
const ROUTER_BASE_PORTS := 2
const POWER_STRIP_PRICE := 60
const POWER_STRIP_EXTRA := 3 # 4er-Leiste belegt selbst eine Dose: +3
const POWER_STRIP_MAX := 8
const NET_HUB_PRICE := 90
const NET_HUB_EXTRA := 3 # 4-Port-Verteiler belegt selbst einen Port: +3
const NET_HUB_MAX := 8
var power_strips: int = 0
var net_hubs: int = 0
signal accessories_changed
var ups_backup_active: bool = false
var avg_ups_charge: float = 0.0
var overload_timer: float = 0.0
var power_tier: int = 0
var router_tier: int = 0
## Erforschte Stufe pro Zweig aus RESEARCH_TREE (fehlender Eintrag = 0).
var research_levels: Dictionary = {}
var room_level: int = 0 # 0 = Garage, 1 = +Halle B, 2 = +Halle C Enterprise
## Zahl der erreichten Firmenwert-Meilensteine. -1 = alter Spielstand, wird beim nächsten Check still übernommen.
var company_milestones_reached: int = 0
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
var support_tickets: Dictionary = {}
var active_call: Dictionary = {}
var total_rental_income_per_cycle: float = 0.0
## Ruf der Firma (0-100). Bestimmt, wie viele Kunden ein Dienst anlockt und wie schnell sie kommen.
var reputation: float = 10.0
var _last_rep_tier: int = -1
const REPUTATION_START := 10.0
const MAX_SERVICES_PER_RACK := 4
const REPUTATION_LABELS: Array[String] = ["Unbekannt", "Lokal bekannt", "Gefragt", "Etabliert", "Marktführer"]
const REPUTATION_THRESHOLDS: Array[float] = [15.0, 35.0, 60.0, 85.0]
## Bedarf pro Nutzer, der bei mehreren Diensten nach Nutzerzahl gemittelt wird.
const _BLEND_KEYS: Array[String] = ["ram_gb_per_user", "cpu_per_user", "gpu_per_user", "storage_tb_per_user", "mbps_per_user", "pay_per_user"]
var checklist_opened_pc: bool = false
var checklist_ordered_anything: bool = false
var checklist_dismissed: bool = false
var extinguisher_held_by: int = 0

# Delivery Van State ("idle" | "arriving" | "unloading" | "departing")
var pending_delivery_items: Array = []
var van_cargo: Array = []
var van_phase: String = "idle"
var van_phase_time: float = 0.0
var van_cargo_count: int = 0
var _van_empty_accum: float = 0.0
var pending_delivery_count: int = 0

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
var _ups_beep_accum: float = 0.0
var _phone_ring_accum: float = 0.0
var _call_cooldown: float = 18.0
var _van_unload_accum: float = 0.0
var _delivery_slot_cursor: int = 0
# Spieluhr: der Host zählt in jedem Frame weiter, der Tageswechsel läuft im Simulations-Tick.
var _day_rollover_pending: bool = false
# Client: Abweichung zur Host-Uhr, die weich über mehrere Frames ausgeglichen wird.
var _time_correction: float = 0.0
const TIME_SNAP_THRESHOLD := 0.02
# Letzte gelesene Echtzeit (-1 = noch keine), damit Mitternacht als Tageswechsel erkannt wird.
var _last_real_time: float = -1.0
const TIME_CORRECTION_RATE := 2.0


func _process(delta: float) -> void:
	if not is_active or not NetworkManager.is_in_session:
		_last_real_time = -1.0
		return
	if not multiplayer.is_server():
		var corr := _time_correction * clampf(delta * TIME_CORRECTION_RATE, 0.0, 1.0)
		_time_correction -= corr
		time_of_day = fposmod(time_of_day + delta / DAY_LENGTH_SECONDS + corr, 1.0)
		if van_phase != "idle":
			van_phase_time += delta
		return

	# Dedizierter Server ohne verbundene Spieler: Welt pausiert (kein Geld, keine Ereignisse, kein Lieferwagen).
	if is_world_paused_for_empty_server():
		_last_real_time = -1.0
		return

	_update_delivery_van(delta)

	# Die Spieluhr läuft in Echtzeit: der Host übernimmt die Uhrzeit seines Rechners.
	var real_time := _real_time_of_day()
	if _last_real_time >= 0.0 and real_time + 0.5 < _last_real_time:
		_day_rollover_pending = true
	_last_real_time = real_time
	time_of_day = real_time

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


func _update_delivery_van(delta: float) -> void:
	match van_phase:
		"idle":
			if not pending_delivery_items.is_empty():
				van_cargo = _pack_van_cargo(pending_delivery_items)
				pending_delivery_items.clear()
				van_phase = "arriving"
				van_phase_time = 0.0
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
				post_event_f("🚚 Cloud Express ist angekommen (%d Pakete werden abgeladen)!", [van_trip_total], "good")
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
				var drop_t := VAN_DROP_TIME_HAND
				if van_trip_kind == "truck":
					drop_t = VAN_TRUCK_TILT_TIME + float(_van_trip_items.size()) * VAN_DROP_TIME_PER_CRATE_TRUCK
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
	van_trip_kind = "hand" if van_trip_count == 1 and not is_cart else "truck"
	var stand_offset := VAN_DROP_STAND_OFFSET_TRUCK if van_trip_kind == "truck" else VAN_DROP_STAND_OFFSET
	van_trip_target = _van_trip_stand_pos(_van_trip_items, stand_offset)
	var load_t := float(van_trip_count) * VAN_LOAD_TIME_PER_CRATE
	if van_trip_kind == "truck":
		load_t += VAN_TRUCK_FETCH_TIME
	_begin_van_trip_step("load", load_t)


## Nimmt die Kartons der nächsten Fahrt aus dem Laderaum. Ein Rollwagen fährt immer allein.
func _take_van_trip_items() -> Array:
	var items: Array = [van_cargo.pop_front()]
	if str(items[0]) == "cart":
		return items
	while not van_cargo.is_empty() and items.size() < VAN_TRIP_MAX_CRATES and str(van_cargo[0]) != "cart":
		items.append(van_cargo.pop_front())
	return items


## Liefert die Kartons ab, deren Zeitpunkt im Schritt "drop" erreicht ist.
func _drop_due_van_trip_items() -> void:
	var n := _van_trip_items.size()
	var due := 0
	if van_trip_time >= van_trip_duration:
		due = n
	elif van_trip_kind == "truck":
		due = clampi(floori((van_trip_time - VAN_TRUCK_TILT_TIME) / VAN_DROP_TIME_PER_CRATE_TRUCK), 0, n)
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


## Fasst bestellte Bauteile ("part:...") zu einem Sammelpaket zusammen, das als erstes ausgeliefert wird.
func _pack_van_cargo(items: Array) -> Array:
	var physical: Array = []
	_van_parcel_parts.clear()
	for entry in items:
		var s := str(entry)
		if s.begins_with("part:"):
			_van_parcel_parts.append(s.substr(5))
		else:
			physical.append(s)
	if not _van_parcel_parts.is_empty():
		physical.push_front(VAN_PARCEL_ITEM)
	return physical


func _deliver_parts_parcel() -> void:
	if _van_parcel_parts.is_empty():
		return
	for pid_v in _van_parcel_parts:
		var pid := str(pid_v)
		parts_inventory[pid] = int(parts_inventory.get(pid, 0)) + 1
	var n := _van_parcel_parts.size()
	_van_parcel_parts.clear()
	_broadcast_inventory()
	_rpc_play_sfx.rpc("pickup")
	post_event_f("📦 %d Hardware-Bauteil(e) ins Teile-Lager geliefert! Jetzt am Rack einbauen [E].", [n], "good")


func _cart_drop_pos(cart_count: int) -> Vector3:
	return Vector3(-1.1 + float(cart_count % 3) * 0.95, 0.0, 6.4)


func _delivery_slot_pos(index: int) -> Vector3:
	var col := index % 4
	var row := (index / 4) % 3
	return Vector3(-1.35 + float(col) * 0.9, 0.0, 5.6 + float(row) * 0.9)


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
	else:
		_spawn_crate_internal(item_type)
		_broadcast_crates()
		_rpc_play_sfx.rpc("drop")


func _broadcast_van_state() -> void:
	van_cargo_count = van_cargo.size()
	pending_delivery_count = pending_delivery_items.size()
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
	power_strips = 0
	net_hubs = 0
	breaker_on = true
	ups_backup_active = false
	avg_ups_charge = 0.0
	overload_timer = 0.0
	power_tier = 0
	router_tier = 0
	research_levels = {}
	room_level = 0
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
	_ups_beep_accum = 0.0
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

	# v1.0 Clean Empty Garage Start: no racks, no servers, no crates!
	# Player buys their very first Rack & Hardware from the Windows PC!
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
	for item in van_cargo:
		all_pending.append(str(item))
	for item in pending_delivery_items:
		all_pending.append(str(item))
	data["pending_delivery_items"] = all_pending
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
	var saved_finance: Variant = data.get("finance", {})
	FinanceManager.import_data(saved_finance if saved_finance is Dictionary else {})
	# Queue any items that were in transit when the game was saved
	var saved_pending: Variant = data.get("pending_delivery_items", [])
	if saved_pending is Array:
		for item in saved_pending:
			pending_delivery_items.append(str(item))
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
	breaker_fuses = _make_fuse_slots("ok")
	fuse_stock = 0
	power_fuse_stock = 0
	power_strips = 0
	net_hubs = 0
	shared_open_panels.clear()
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
	van_cargo.clear()
	van_phase = "idle"
	van_phase_time = 0.0
	van_cargo_count = 0
	pending_delivery_count = 0
	extinguisher_held_by = 0
	ddos_active = false
	ups_backup_active = false
	overload_timer = 0.0
	_sim_accum = 0.0
	_autosave_accum = 0.0
	_ups_beep_accum = 0.0
	_phone_ring_accum = 0.0
	_call_cooldown = 20.0
	_van_unload_accum = 0.0


func _alloc_id(prefix: String) -> String:
	var id := "%s_%d" % [prefix, _next_entity_num]
	_next_entity_num += 1
	return id


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


func _spawn_crate_internal(item_type: String) -> String:
	var cid := _alloc_id("crate")
	var pos := _delivery_slot_pos(_delivery_slot_cursor)
	_delivery_slot_cursor += 1
	crates[cid] = {
		"id": cid,
		"item_type": item_type,
		"pos": pos,
		"held_by": 0,
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
		"power_strips": power_strips,
		"net_hubs": net_hubs,
		"ups_backup_active": ups_backup_active,
		"avg_ups_charge": avg_ups_charge,
		"overload_timer": overload_timer,
		"power_tier": power_tier,
		"router_tier": router_tier,
		"research_levels": research_levels.duplicate(),
		"room_level": room_level,
		"company_milestones_reached": company_milestones_reached,
		"ai_platform_level": ai_platform_level,
		"ddos_active": ddos_active,
		"day_number": day_number,
		"time_of_day": time_of_day,
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
		"extinguisher_held_by": extinguisher_held_by,
		"van_phase": van_phase,
		"van_phase_time": van_phase_time,
		"van_cargo_count": van_cargo.size(),
		"pending_delivery_count": pending_delivery_items.size(),
		"checklist_opened_pc": checklist_opened_pc,
		"checklist_ordered_anything": checklist_ordered_anything,
		"open_panels": shared_open_panels.duplicate(),
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
	power_strips = clampi(int(snap.get("power_strips", 0)), 0, POWER_STRIP_MAX)
	net_hubs = clampi(int(snap.get("net_hubs", 0)), 0, NET_HUB_MAX)
	ups_backup_active = bool(snap.get("ups_backup_active", false))
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
	ai_platform_level = int(snap.get("ai_platform_level", 0))
	company_milestones_reached = clampi(int(snap.get("company_milestones_reached", -1)), -1, COMPANY_VALUE_MILESTONES.size())
	ddos_active = bool(snap.get("ddos_active", false))
	day_number = maxi(1, int(snap.get("day_number", 1)))
	time_of_day = clampf(float(snap.get("time_of_day", 0.36)), 0.0, 0.999)
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
	extinguisher_held_by = int(snap.get("extinguisher_held_by", 0))
	shared_open_panels = _sanitize_open_panels(snap.get("open_panels", {}))
	panel_states_changed.emit()
	van_phase = str(snap.get("van_phase", "idle"))
	van_phase_time = float(snap.get("van_phase_time", 0.0))
	van_cargo_count = int(snap.get("van_cargo_count", 0))
	pending_delivery_count = int(snap.get("pending_delivery_count", 0))
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
	if extinguisher_held_by == peer_id:
		extinguisher_held_by = 0
		_rpc_sync_extinguisher.rpc(0)


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

	var final_watts := maxi(40, int(roundf(watts * watt_mult)))
	var final_heat := maxf(1.5, heat)
	return {
		"compute": compute,
		"watts": final_watts,
		"heat": final_heat,
		"fault_mult": clampf(fault_mult, 0.15, 3.0),
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
		out["watts"] = int(out["watts"]) + int(st["watts"])
		if bool(st["psu_overloaded"]):
			out["psu_overloaded"] = true
		if not bool(st.get("complete", true)) and is_slot_upgradeable(itype):
			out["incomplete_servers"] = int(out.get("incomplete_servers", 0)) + 1
		if powered and networked and str(sd.get("state", "ok")) == "ok" and is_slot_upgradeable(itype) and bool(st.get("complete", true)):
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
			if str(slot["item_type"]) != "" and str(slot["state"]) == "ok":
				candidates.append(str(rid))
				break
	if candidates.is_empty():
		return

	var target := candidates[randi() % candidates.size()]
	var slots: Array = racks[target]["slots"]
	var ok_idx: Array[int] = []
	for i in range(slots.size()):
		var s: Dictionary = slots[i]
		if str(s["item_type"]) != "" and str(s["state"]) == "ok":
			ok_idx.append(i)
	ok_idx.shuffle()

	var hit := PackedStringArray()
	for j in range(mini(WATER_LEAK_MAX_SLOTS, ok_idx.size())):
		var slot: Dictionary = slots[ok_idx[j]]
		slot["state"] = "crashed"
		slot["repair_progress"] = 0.0
		hit.append(str(ok_idx[j] + 1))

	money = maxf(0.0, money - WATER_LEAK_COST)
	post_event_f("WASSERSCHADEN über %s! Slot %s ausgefallen, Trocknung kostet $%d. Mit [E] reparieren.", [
		target.to_upper(), ", ".join(hit), int(WATER_LEAK_COST)
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
	if kind == "ups" and ups_units.has(eid):
		return int(roundf(float(ITEM_CATALOG["ups"]["price"]) * SELL_REFUND_RATIO))
	if kind == "cart" and carts.has(eid):
		var total := int(ITEM_CATALOG["cart"]["price"])
		var c_items: Array = carts[eid].get("items", [])
		for it in c_items:
			total += int(ITEM_CATALOG.get(str(it), {}).get("price", 0))
		return int(roundf(float(total) * SELL_REFUND_RATIO))
	return 0


func get_player_held_crate(peer_id: int) -> Dictionary:
	for cid in crates.keys():
		var c: Dictionary = crates[cid]
		if int(c.get("held_by", 0)) == peer_id:
			return c
	return {}


func get_player_pushed_cart(peer_id: int) -> Dictionary:
	for cid in carts.keys():
		var c: Dictionary = carts[cid]
		if int(c.get("pushed_by", 0)) == peer_id:
			return c
	return {}


func is_player_holding_extinguisher(peer_id: int) -> bool:
	return extinguisher_held_by == peer_id


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


func get_max_ports(cable_type: String, endpoint_id: String) -> int:
	if cable_type == "power":
		if endpoint_id == WALL_BREAKER_ID:
			return BREAKER_BASE_SOCKETS + power_strips * POWER_STRIP_EXTRA
		if endpoint_id == HALL_C_BREAKER_ID:
			return 6 + power_tier * 2
		if racks.has(endpoint_id):
			return 2
		if coolers.has(endpoint_id):
			return 1
		if ups_units.has(endpoint_id):
			return 2 # Connect to breaker AND optionally daisy-chain out
		return 0
	else:
		if endpoint_id == WALL_ROUTER_ID:
			return ROUTER_BASE_PORTS + net_hubs * NET_HUB_EXTRA
		if endpoint_id == HALL_C_ROUTER_ID:
			return 4
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


func can_place_at(pos: Vector3, ignore_rack_id: String = "") -> bool:
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
	hardware += _catalog_price("ups") * float(ups_units.size())

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
	var idx := maxi(company_milestones_reached, 0)
	if idx >= COMPANY_VALUE_MILESTONES.size():
		return tr("Firmenwert: $%d  •  Endziel erreicht!") % value
	var m: Dictionary = COMPANY_VALUE_MILESTONES[idx]
	return tr("Firmenwert: $%d  •  Nächstes Ziel: $%d (%s)") % [value, int(m["value"]), tr(str(m["title"]))]


# ==============================================================================
# SIMULATION LOOP (HOST ONLY)
# ==============================================================================

func _run_simulation_step(dt: float) -> void:
	var prev_ups_backup := ups_backup_active
	_recalculate_networks_and_metrics()

	# 0. Day/Night Clock & kWh Meter
	var kw_now := float(total_watts) / 1000.0
	if breaker_on:
		daily_kwh += kw_now * (dt / DAY_LENGTH_SECONDS) * 24.0
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
		if bill > 0:
			# Die Stromrechnung wird nicht mehr sofort abgebucht. FinanceManager stellt daraus
			# eine Rechnung mit Fälligkeit aus, die in der Rechnungen-App bezahlt wird.
			_rpc_daily_bill.rpc(day_number, bill, billed_kwh)
			_rpc_play_sfx.rpc("bill")
			post_event_f("⚡ Tag %d Stromrechnung erhalten: $%d (%.1f kWh verbraucht).", [day_number - 1, bill, billed_kwh], "warn")
		else:
			post_event_f("☀ Tag %d beginnt – keine Stromkosten angefallen.", [day_number], "info")

	# 1. UPS Charging & Emergency Backup Discharging
	var ups_dirty := false
	var connected_ups_ids: Array[String] = []
	var active_backup_ids: Array[String] = []
	var charge_sum := 0.0

	for uid in ups_units.keys():
		var u: Dictionary = ups_units[uid]
		if bool(u.get("connected", false)):
			connected_ups_ids.append(uid)
			if not breaker_on and float(u["charge"]) > 0.2:
				active_backup_ids.append(uid)

	if breaker_on:
		for uid in connected_ups_ids:
			var u: Dictionary = ups_units[uid]
			u["discharging"] = false
			if float(u["charge"]) < 100.0:
				u["charge"] = minf(100.0, float(u["charge"]) + 3.8 * dt)
				ups_dirty = true
	else:
		if not active_backup_ids.is_empty():
			var load_drain := (1.15 + float(total_watts) / 2400.0) / float(active_backup_ids.size())
			for uid in active_backup_ids:
				var u: Dictionary = ups_units[uid]
				u["discharging"] = true
				u["charge"] = maxf(0.0, float(u["charge"]) - load_drain * dt)
				ups_dirty = true
			_ups_beep_accum += dt
			if _ups_beep_accum >= 4.0:
				_ups_beep_accum = 0.0
				_rpc_play_sfx.rpc("ups_beep")
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
		post_event("USV-BATTERIEN LEER! Vollständiger Blackout – Hauptsicherung einschalten!", "alert")
		ups_dirty = true

	if ups_dirty:
		_broadcast_ups()

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
			elif bool(rack["powered"]) and str(sd["state"]) == "ok":
				var stats := get_slot_stats(sd)
				rack_heat += float(stats["heat"])
				active_modules += 1
		var effective_rack_heat := maxf(0.0, rack_heat - rack_passive_cool)
		total_heat_gen += effective_rack_heat
		var local_hot_spot := float(maxi(0, active_modules - 1)) * 2.2 - rack_passive_cool * 0.6
		var target_rack_temp := clampf(room_temp + local_hot_spot + (14.0 if _rack_has_fire(rack) else 0.0), 16.0, 105.0)
		rack["temp"] = move_toward(float(rack["temp"]), target_rack_temp, dt * 3.0)

	for cid in coolers.keys():
		var cooler: Dictionary = coolers[cid]
		if bool(cooler["powered"]):
			var ctype := str(cooler.get("cooler_type", "cooler"))
			total_cooling += absf(float(ITEM_CATALOG[ctype]["heat"]))

	# Slight natural night cooling (-3°C at night)
	var night_bonus := -3.0 if (time_of_day < 0.22 or time_of_day > 0.80) else 0.0
	var target_room := clampf(22.0 + night_bonus + total_heat_gen - total_cooling, 15.0, 96.0)
	room_temp = move_toward(room_temp, target_room, dt * 2.0)

	# 4. Hardware Faults & Fires (modulated by NVMe/PSU/Cooling fault_mult!)
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
			elif st == "ok" and bool(rack["powered"]):
				var stats := get_slot_stats(slot)
				var fmult := float(stats["fault_mult"])
				if rtemp >= 80.0 and randf() < 0.030 * fmult:
					slot["state"] = "burning"
					slot["fire_level"] = 1.0
					racks_dirty = true
					post_event_f("BRAND in %s (Slot %d)! Feuerlöscher von der Wand holen!", [rid.to_upper(), i + 1], "alert")
					_rpc_play_sfx.rpc("alarm")
				elif rtemp >= 68.0 and randf() < 0.014 * fmult:
					slot["state"] = "crashed"
					slot["repair_progress"] = 0.0
					racks_dirty = true
					post_event_f("Überhitzung: %s Slot %d abgestürzt! Mit [E] reparieren.", [rid.to_upper(), i + 1], "warn")
					_rpc_play_sfx.rpc("alarm")
				elif bool(rack["networked"]) and randf() < 0.0012 * fmult:
					slot["state"] = "crashed"
					slot["repair_progress"] = 0.0
					racks_dirty = true
					post_event_f("Hardware-Fehler in %s Slot %d – Wartung [E] nötig.", [rid.to_upper(), i + 1], "warn")
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
				post_event("DDOS-ANGRIFF ERKANNT! Am Wand-Router [E] oder im Windows-PC abwehren!", "alert")
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
		var users_int := 0
		for svc in services:
			users_int += _update_service_users(svc as Dictionary, sat, online, dt, time_wave)
		users_int = maxi(1, users_int)
		_sync_rack_rental_fields(r)
		r["active_users"] = users_int
		# Ressourcenbedarf und Preis pro Nutzer: Mittel aller Dienste, gewichtet nach Nutzerzahl.
		prof = _blend_service_profiles(services)

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
			post_event_f("❌ %s hat %s gekündigt (dauerhafte Überlastung)! Hardware aufrüsten & neu vermieten.", [cname, rid.to_upper()], "alert")
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

	# Age existing tickets
	for tid in support_tickets.keys():
		support_tickets[tid]["age"] = float(support_tickets[tid].get("age", 0.0)) + dt

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


## Höchstzahl an Nutzern, die ein Dienst beim aktuellen Ruf anlockt.
func get_service_user_cap(service_type: String) -> int:
	if not HardwareCatalog.RENTAL_PROFILES.has(service_type):
		return 0
	var p: Dictionary = HardwareCatalog.RENTAL_PROFILES[service_type]
	var base := float(p.get("base_users", 0))
	var cap := float(p.get("max_users", 0)) * (0.12 + 0.88 * get_reputation_factor())
	return int(roundf(maxf(base * 0.5, cap)))


## Startnutzer eines neuen Dienstes: bei schlechtem Ruf nur eine Handvoll.
func _start_users_for(service_type: String) -> float:
	var p: Dictionary = HardwareCatalog.RENTAL_PROFILES[service_type]
	return maxf(1.0, roundf(float(p.get("base_users", 1)) * (0.15 + 0.35 * get_reputation_factor())))


## Nutzerzahl eines Dienstes fortschreiben. Gibt die gerundete Nutzerzahl zurück.
func _update_service_users(svc: Dictionary, sat: float, online: bool, dt: float, time_wave: float) -> int:
	var st := str(svc.get("type", ""))
	if not HardwareCatalog.RENTAL_PROFILES.has(st):
		return 0
	var p: Dictionary = HardwareCatalog.RENTAL_PROFILES[st]
	var base := float(p.get("base_users", 1))
	var cap := float(get_service_user_cap(st))
	var prev := float(svc.get("users", base))
	var cur := prev
	if not online:
		cur = maxf(base * 0.2, cur - 4.5 * dt)
	elif sat >= 72.0:
		if cur < cap:
			var growth := float(p.get("growth_rate", 1.0)) * time_wave * (0.35 + 0.65 * get_reputation_factor())
			cur = minf(cap, cur + growth * dt * 0.36)
		else:
			# Ruf gesunken: überzählige Kunden wandern langsam ab.
			cur = maxf(cap, cur - 1.0 * dt)
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
	var rid_up := rack_id.to_upper()
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
	}
	_rpc_play_sfx.rpc("ticket_notify")
	post_event_f("🎧 Neues Support-Ticket %s von %s: %s", [tid, cname, {"text": title, "args": title_args}], "warn")


## Liefert den Anruftext als Vorlage plus Werte ({text, args}).
func _describe_issue_call(rack_id: String, rack: Dictionary, issue_key: String) -> Dictionary:
	var users := int(rack.get("active_users", 0))
	var m: Dictionary = rack.get("metrics", {})
	var who := str(rack.get("rental_customer", ""))
	var rid_up := rack_id.to_upper()
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
	max_watts = int(POWER_TIERS[power_tier]["watts"])

	for rid in racks.keys():
		racks[rid]["powered"] = false
		racks[rid]["networked"] = false
	for cid in coolers.keys():
		coolers[cid]["powered"] = false
	for uid in ups_units.keys():
		ups_units[uid]["connected"] = false

	# First discover which UPS units are wired into the main breaker power graph
	var bus_sources: Array[String] = [WALL_BREAKER_ID]
	if room_level >= 2:
		bus_sources.append(HALL_C_BREAKER_ID)

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
			elif racks.has(other):
				bus_queue.append(other)

	# Determine if UPS backup is keeping the power bus alive during a breaker outage
	var has_charged_ups := false
	for uid in ups_units.keys():
		var u: Dictionary = ups_units[uid]
		if bool(u["connected"]) and float(u["charge"]) > 0.2:
			has_charged_ups = true
			break

	ups_backup_active = (not breaker_on) and has_charged_ups
	var power_alive := breaker_on or ups_backup_active

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
				if racks.has(other):
					racks[other]["powered"] = true
					p_queue.append(other)
				elif coolers.has(other):
					coolers[other]["powered"] = true
				elif ups_units.has(other):
					p_queue.append(other)

		# BFS Network from Wall Router (+ Hall C Router if unlocked)
		var n_visited: Dictionary = {WALL_ROUTER_ID: true}
		var n_queue: Array = [WALL_ROUTER_ID]
		if room_level >= 2:
			n_visited[HALL_C_ROUTER_ID] = true
			n_queue.append(HALL_C_ROUTER_ID)

		while not n_queue.is_empty():
			var curr := str(n_queue.pop_front())
			var can_forward := (
				curr == WALL_ROUTER_ID
				or curr == HALL_C_ROUTER_ID
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

	# Aggregate real hardware & network bandwidth metrics (GB RAM, TB Storage, CPU, GPU, Mbit/s, Watts)
	var watts := 0
	var compute := 0
	var bonus_sum := 0.0
	var sum_ram := 0
	var sum_cpu := 0
	var sum_gpu := 0
	var sum_sto := 0.0
	var sum_mbps := 0.0

	for rid in racks.keys():
		var rack: Dictionary = racks[rid]
		if not bool(rack["powered"]):
			continue
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
			if st == "ok":
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

	for cid in coolers.keys():
		if bool(coolers[cid]["powered"]):
			var ctype := str(coolers[cid].get("cooler_type", "cooler"))
			watts += int(ITEM_CATALOG[ctype]["watts"])

	# Charging UPS draws 120W while below 100%
	if breaker_on:
		for uid in ups_units.keys():
			var u: Dictionary = ups_units[uid]
			if bool(u["connected"]) and float(u["charge"]) < 99.5:
				watts += int(ITEM_CATALOG["ups"]["watts"])

	var req_compute := 0
	for cid in contracts.keys():
		if bool(contracts[cid]["active"]):
			req_compute += int(contracts[cid]["required_compute"])
			sum_mbps += float(contracts[cid].get("req_mbps", 15.0))

	var rt_d: Dictionary = ROUTER_TIERS[clampi(router_tier, 0, ROUTER_TIERS.size() - 1)]
	max_bandwidth_cu = int(rt_d["max_cu"])
	max_bandwidth_mbps = float(rt_d.get("max_mbps", 50.0))
	total_watts = watts
	total_ram_gb = sum_ram
	total_cpu_score = sum_cpu
	total_gpu_score = sum_gpu
	total_storage_tb = sum_sto
	used_bandwidth_mbps = sum_mbps
	raw_compute = compute
	total_compute = mini(compute, max_bandwidth_cu)
	used_compute = req_compute
	revenue_bonus_mult = 1.0 + minf(bonus_sum, 0.80)


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


func request_checkout_cart(entries: Array) -> void:
	_rpc_req_checkout_cart.rpc_id(1, entries)


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


func request_reply_ticket(ticket_id: String, action: String) -> void:
	_rpc_req_reply_ticket.rpc_id(1, ticket_id, action)


func request_answer_call() -> void:
	_rpc_req_answer_call.rpc_id(1)


func request_resolve_call(choice: String) -> void:
	_rpc_req_resolve_call.rpc_id(1, choice)


func request_connect_cable(cable_type: String, from_id: String, to_id: String) -> void:
	_rpc_req_connect_cable.rpc_id(1, cable_type, from_id, to_id)


func request_disconnect_cables_on(cable_type: String, endpoint_id: String) -> void:
	_rpc_req_disconnect_cables_on.rpc_id(1, cable_type, endpoint_id)


func request_toggle_breaker() -> void:
	_rpc_req_toggle_breaker.rpc_id(1)


func request_buy_fuse() -> void:
	_rpc_req_buy_fuse.rpc_id(1)


func request_buy_power_strip() -> void:
	_rpc_req_buy_accessory.rpc_id(1, "power_strip")


func request_buy_net_hub() -> void:
	_rpc_req_buy_accessory.rpc_id(1, "net_hub")


func request_insert_fuse(slot_idx: int) -> void:
	_rpc_req_insert_fuse.rpc_id(1, slot_idx)


func request_pickup_extinguisher() -> void:
	_rpc_req_pickup_extinguisher.rpc_id(1)


func request_return_extinguisher() -> void:
	_rpc_req_return_extinguisher.rpc_id(1)


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


@rpc("authority", "call_local", "reliable")
func _rpc_sync_panel(key: String, opened: bool) -> void:
	if not multiplayer.is_server():
		if opened:
			shared_open_panels[key] = true
		else:
			shared_open_panels.erase(key)
	panel_states_changed.emit()


func request_extinguish_slot(rack_id: String, slot_idx: int, amount: float) -> void:
	_rpc_req_extinguish_slot.rpc_id(1, rack_id, slot_idx, amount)


func request_repair_slot(rack_id: String, slot_idx: int, amount: float) -> void:
	_rpc_req_repair_slot.rpc_id(1, rack_id, slot_idx, amount)


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


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_buy_item(item_type: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not ITEM_CATALOG.has(item_type):
		return
	var price := float(ITEM_CATALOG[item_type]["price"])
	if money < price:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money -= price

	# Add to Delivery Van! If van is currently approaching, toss right into its cargo hold.
	if van_phase == "arriving" or van_phase == "unloading":
		van_cargo.append(item_type)
	else:
		pending_delivery_items.append(item_type)
		if van_phase == "idle":
			van_cargo = pending_delivery_items.duplicate()
			pending_delivery_items.clear()
			van_phase = "arriving"
			van_phase_time = 0.0
			_van_unload_accum = 0.0

	_broadcast_van_state()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("cash")
	post_event_f("%s bestellte %s — 🚚 Cloud Express liefert gleich!", [
		NetworkManager.get_player_name(peer_id), ITEM_CATALOG[item_type]["name"]
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
	_broadcast_crates()
	_rpc_play_sfx.rpc_id(peer_id, "pickup")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_drop_crate(drop_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	var held := get_player_held_crate(peer_id)
	if held.is_empty():
		return
	var cid := str(held["id"])
	var max_x := 5.0 if room_level == 0 else (11.8 if room_level == 1 else 20.8)
	var clamped := Vector3(clampf(drop_pos.x, -5.0, max_x), 0.0, clampf(drop_pos.z, -4.0, 8.8))
	crates[cid]["held_by"] = 0
	crates[cid]["pos"] = clamped
	_broadcast_crates()
	_rpc_play_sfx.rpc_id(peer_id, "drop")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_place_held_structure(pos: Vector3, rot_y: float) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	var held := get_player_held_crate(peer_id)
	if held.is_empty():
		return
	var item_type := str(held["item_type"])
	if str(ITEM_CATALOG[item_type]["category"]) != "placeable":
		return
	var snapped := Vector3(roundf(pos.x * 2.0) * 0.5, 0.0, roundf(pos.z * 2.0) * 0.5)
	if not can_place_at(snapped):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	crates.erase(str(held["id"]))
	if item_type == "rack" or item_type == "rack_pro":
		var rid := _alloc_id("rack")
		racks[rid] = _make_rack_data(rid, item_type, snapped, rot_y)
		_recalculate_networks_and_metrics()
		_broadcast_racks()
		post_event_f("%s hat %s (%s) aufgestellt.", [NetworkManager.get_player_name(peer_id), rid.to_upper(), ITEM_CATALOG[item_type]["name"]], "info")
	elif item_type == "cooler" or item_type == "chiller":
		var cid := _alloc_id("cooler")
		coolers[cid] = {
			"id": cid,
			"cooler_type": item_type,
			"pos": snapped,
			"rot_y": rot_y,
			"powered": false,
		}
		_recalculate_networks_and_metrics()
		_broadcast_coolers()
		post_event_f("%s hat %s aufgestellt (Stromkabel anschließen!).", [NetworkManager.get_player_name(peer_id), ITEM_CATALOG[item_type]["name"]], "info")
	elif item_type == "ups":
		var uid := _alloc_id("ups")
		ups_units[uid] = {
			"id": uid,
			"pos": snapped,
			"rot_y": rot_y,
			"connected": false,
			"charge": 25.0, # Ships with 25% factory pre-charge
			"discharging": false,
		}
		_recalculate_networks_and_metrics()
		_broadcast_ups()
		post_event_f("%s hat USV-Notstrom %s aufgestellt (mit Stromkabel [2] verbinden!).", [NetworkManager.get_player_name(peer_id), uid.to_upper()], "good")

	_broadcast_crates()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("place")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_relocate_rack(rack_id: String, pos: Vector3, rot_y: float) -> void:
	if not multiplayer.is_server():
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
	post_event_f("%s hat %s umgesetzt (Kabel neu anschließen!).", [NetworkManager.get_player_name(peer_id), rack_id.to_upper()], "info")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_sell_rack(rack_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not racks.has(rack_id):
		return
	var refund := get_rack_sell_value(rack_id)
	_disconnect_all_cables_of(rack_id)
	_clear_tickets_for_rack(rack_id)
	if not active_call.is_empty() and str(active_call.get("rack_id", "")) == rack_id:
		active_call.clear()
		_broadcast_call()
	racks.erase(rack_id)
	money += float(refund)
	_recalculate_networks_and_metrics()
	_broadcast_cables()
	_broadcast_racks()
	_broadcast_tickets()
	_broadcast_coolers()
	_broadcast_ups()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("sell")
	post_event_f("%s verkaufte %s für +$%d.", [NetworkManager.get_player_name(peer_id), rack_id.to_upper(), refund], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_pack_device(kind: String, entity_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if is_player_holding_anything(peer_id):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	var item_type := ""
	if kind == "cooler" and coolers.has(entity_id):
		item_type = str(coolers[entity_id].get("cooler_type", "cooler"))
		_disconnect_all_cables_of(entity_id)
		coolers.erase(entity_id)
		_broadcast_coolers()
	elif kind == "ups" and ups_units.has(entity_id):
		item_type = "ups"
		_disconnect_all_cables_of(entity_id)
		ups_units.erase(entity_id)
		_broadcast_ups()
	else:
		return

	var cid := _alloc_id("crate")
	crates[cid] = {"id": cid, "item_type": item_type, "pos": Vector3.ZERO, "held_by": peer_id}
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

	crates.erase(str(held["id"]))
	slots[slot_idx] = {
		"item_type": item_type,
		"state": "ok",
		"repair_progress": 0.0,
		"fire_level": 0.0,
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
		rack_id.to_upper(),
		slot_idx + 1,
	], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_remove_module(rack_id: String, slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if is_player_holding_anything(peer_id) or not racks.has(rack_id):
		_rpc_play_sfx.rpc_id(peer_id, "error")
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
	crates[cid] = {"id": cid, "item_type": item_type, "pos": Vector3.ZERO, "held_by": peer_id}
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
		NetworkManager.get_player_name(peer_id), rack_id.to_upper(), slot_idx + 1, refund
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
			post_event_f("%s nicht im Teile-Lager! Erst im Windows-PC-Shop bestellen.", [str(new_part["name"])], "warn")
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
		NetworkManager.get_player_name(peer_id), str(new_part["name"]), rack_id.to_upper(), slot_idx + 1
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
	if cost <= 0.0 or money < cost:
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
	if money < cost:
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
		rack_id.to_upper(),
		slot_idx + 1,
	], "good")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_checkout_cart(entries: Array) -> void:
	if not multiplayer.is_server() or entries.is_empty():
		return
	var peer_id := _get_sender_id()
	var total_cost := 0.0
	var queue_items: Array = []

	for raw in entries:
		var e: Dictionary = raw
		var kind := str(e.get("kind", "item")) # "item" | "part"
		var qty := clampi(int(e.get("qty", 1)), 1, 20)
		if kind == "item":
			var itype := str(e.get("id", ""))
			if not ITEM_CATALOG.has(itype):
				continue
			total_cost += float(ITEM_CATALOG[itype]["price"]) * float(qty)
			for _q in range(qty):
				queue_items.append(itype)
		elif kind == "part":
			var cat := str(e.get("cat", ""))
			var pid := str(e.get("id", ""))
			var pd := HardwareCatalog.get_part(cat, pid)
			if pd.is_empty() or int(pd.get("cost", 0)) <= 0:
				continue
			total_cost += float(pd["cost"]) * float(qty)
			for _q in range(qty):
				queue_items.append("part:" + pid)

	if queue_items.is_empty() or money < total_cost:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	money -= total_cost
	if not checklist_ordered_anything:
		checklist_ordered_anything = true
		_broadcast_checklist()
	for qi in queue_items:
		if van_phase == "arriving":
			van_cargo.append(qi)
		else:
			pending_delivery_items.append(qi)

	_broadcast_van_state()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("cash")
	post_event_f("🛒 %s bestellte %d Artikel ($%.0f) — Cloud Express Sprinter ist unterwegs!", [
		NetworkManager.get_player_name(peer_id), queue_items.size(), total_cost
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
		post_event_f("%s beendete alle Vermietungen von %s.", [pname, rack_id.to_upper()], "info")
	else:
		var prof: Dictionary = HardwareCatalog.RENTAL_PROFILES[rental_type]
		var idx := _find_service(services, rental_type)
		if idx >= 0:
			var gone: Dictionary = services[idx]
			services.remove_at(idx)
			post_event_f("%s beendete %s (%s) auf %s.", [pname, str(prof["short"]), str(gone.get("customer", "")), rack_id.to_upper()], "info")
		else:
			if services.size() >= MAX_SERVICES_PER_RACK:
				_rpc_play_sfx.rpc_id(peer_id, "error")
				post_event_f("%s hat schon %d Dienste. Beende erst einen, bevor du einen neuen startest.", [rack_id.to_upper(), MAX_SERVICES_PER_RACK], "warn")
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
				pname, rack_id.to_upper(), str(prof["short"]), cname, int(start_users), get_reputation_label()
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
				post_event_f("Problem bei %s besteht noch! Erst Hardware/Kabel/Router beheben.", [rid.to_upper()], "warn")
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
func _rpc_req_connect_cable(cable_type: String, from_id: String, to_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if cable_type != "power" and cable_type != "network":
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

	if count_cables_on(cable_type, from_id) >= get_max_ports(cable_type, from_id):
		post_event_f("Kein freier %s-Port an %s (Rack-Switch oder Upgrade nötig).", [
			"Strom" if cable_type == "power" else "Netzwerk", from_id.to_upper()
		], "warn")
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	if count_cables_on(cable_type, to_id) >= get_max_ports(cable_type, to_id):
		post_event_f("Kein freier %s-Port an %s.", [
			"Strom" if cable_type == "power" else "Netzwerk", to_id.to_upper()
		], "warn")
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return

	var cab_id := _alloc_id("cable")
	cables[cab_id] = {"id": cab_id, "cable_type": cable_type, "from_id": from_id, "to_id": to_id}
	_recalculate_networks_and_metrics()
	_broadcast_cables()
	_broadcast_racks()
	_broadcast_coolers()
	_broadcast_ups()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("cable")
	var label := "Stromkabel" if cable_type == "power" else "Netzwerkkabel"
	post_event_f("%s verband %s: %s ↔ %s", [NetworkManager.get_player_name(peer_id), label, from_id.to_upper(), to_id.to_upper()], "info")


func _is_valid_cable_endpoint(cable_type: String, endpoint_id: String) -> bool:
	if cable_type == "power":
		if endpoint_id == WALL_BREAKER_ID:
			return true
		if endpoint_id == HALL_C_BREAKER_ID and room_level >= 2:
			return true
		return racks.has(endpoint_id) or coolers.has(endpoint_id) or ups_units.has(endpoint_id)
	else:
		if endpoint_id == WALL_ROUTER_ID:
			return true
		if endpoint_id == HALL_C_ROUTER_ID and room_level >= 2:
			return true
		return racks.has(endpoint_id)


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


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_toggle_breaker() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
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
func _rpc_req_pickup_extinguisher() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if is_player_holding_anything(peer_id) or extinguisher_held_by != 0:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	extinguisher_held_by = peer_id
	_rpc_sync_extinguisher.rpc(extinguisher_held_by)
	_rpc_play_sfx.rpc_id(peer_id, "pickup")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_return_extinguisher() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if extinguisher_held_by != peer_id:
		return
	extinguisher_held_by = 0
	_rpc_sync_extinguisher.rpc(0)
	_rpc_play_sfx.rpc_id(peer_id, "drop")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_extinguish_slot(rack_id: String, slot_idx: int, amount: float) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if extinguisher_held_by != peer_id or not racks.has(rack_id):
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	if str(slot["state"]) != "burning":
		return
	slot["fire_level"] = maxf(0.0, float(slot["fire_level"]) - clampf(amount, 0.0, 0.5))
	if float(slot["fire_level"]) <= 0.0:
		slot["state"] = "crashed"
		slot["repair_progress"] = 0.0
		racks[rack_id]["temp"] = minf(float(racks[rack_id]["temp"]), 55.0)
		post_event_f("%s hat den Brand in %s Slot %d gelöscht! Jetzt reparieren [E].", [
			NetworkManager.get_player_name(peer_id), rack_id.to_upper(), slot_idx + 1
		], "good")
		_rpc_play_sfx.rpc("repair")
	_broadcast_racks()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_repair_slot(rack_id: String, slot_idx: int, amount: float) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	if not racks.has(rack_id):
		return
	var slots: Array = racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	if str(slot["state"]) != "crashed":
		return
	slot["repair_progress"] = minf(1.0, float(slot["repair_progress"]) + clampf(amount, 0.0, 1.0))
	if float(slot["repair_progress"]) >= 1.0:
		slot["state"] = "ok"
		slot["repair_progress"] = 0.0
		_recalculate_networks_and_metrics()
		_broadcast_sim_tick()
		post_event_f("%s hat %s Slot %d repariert & neugestartet!", [
			NetworkManager.get_player_name(peer_id), rack_id.to_upper(), slot_idx + 1
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
	if power_tier + 1 >= POWER_TIERS.size():
		return
	var next_tier: Dictionary = POWER_TIERS[power_tier + 1]
	var cost := float(next_tier["cost"])
	if money < cost:
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money -= cost
	power_fuse_stock = 1
	_broadcast_fuses()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("cash")
	post_event_f("%s hat eine Drehsicherung für %s gekauft. Einsetzen: Sicherungskasten, Steckplatz F2.", [
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
	var peer_id := _get_sender_id()
	var cart := get_player_pushed_cart(peer_id)
	if cart.is_empty():
		return
	var cid := str(cart["id"])
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
	var item_type := str(items.pop_back())
	var crate_id := _alloc_id("crate")
	crates[crate_id] = {"id": crate_id, "item_type": item_type, "pos": Vector3.ZERO, "held_by": peer_id}
	_broadcast_carts()
	_broadcast_crates()
	_rpc_play_sfx.rpc_id(peer_id, "pickup")


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
func _rpc_sync_extinguisher(holder_id: int) -> void:
	extinguisher_held_by = holder_id
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
	_rpc_sync_fuses.rpc(breaker_fuses, fuse_stock, power_fuse_stock)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_fuses(fuses: Array, stock: int, power_stock: int) -> void:
	if not multiplayer.is_server():
		breaker_fuses = _sanitize_fuses(fuses)
		fuse_stock = maxi(0, stock)
		power_fuse_stock = clampi(power_stock, 0, 1)
	fuses_changed.emit()


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


## Steckleiste (Stromkasten) oder Netzwerk-Verteiler (Router) kaufen. Wird sofort montiert.
@rpc("any_peer", "call_local", "reliable")
func _rpc_req_buy_accessory(kind: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _get_sender_id()
	var price := 0
	var at_max := false
	match kind:
		"power_strip":
			price = POWER_STRIP_PRICE
			at_max = power_strips >= POWER_STRIP_MAX
		"net_hub":
			price = NET_HUB_PRICE
			at_max = net_hubs >= NET_HUB_MAX
		_:
			return
	if at_max or money < float(price):
		_rpc_play_sfx.rpc_id(peer_id, "error")
		return
	money -= float(price)
	if kind == "power_strip":
		power_strips += 1
		post_event_f("%s hat eine Steckleiste am Stromkasten montiert (+%d Steckplätze).", [
			NetworkManager.get_player_name(peer_id), POWER_STRIP_EXTRA,
		], "good")
	else:
		net_hubs += 1
		post_event_f("%s hat einen Netzwerk-Verteiler am Router montiert (+%d Ports).", [
			NetworkManager.get_player_name(peer_id), NET_HUB_EXTRA,
		], "good")
	_rpc_sync_accessories.rpc(power_strips, net_hubs)
	_recalculate_networks_and_metrics()
	_broadcast_sim_tick()
	_rpc_play_sfx.rpc("cash")


@rpc("authority", "call_local", "reliable")
func _rpc_sync_accessories(strips: int, hubs: int) -> void:
	power_strips = clampi(strips, 0, POWER_STRIP_MAX)
	net_hubs = clampi(hubs, 0, NET_HUB_MAX)
	accessories_changed.emit()


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
	crates[cid] = {"id": cid, "item_type": OLD_FUSE_ITEM, "pos": Vector3.ZERO, "held_by": peer_id}
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
		}

	var packet := {
		"money": money,
		"breaker_on": breaker_on,
		"ups_backup_active": ups_backup_active,
		"avg_ups_charge": avg_ups_charge,
		"overload_timer": overload_timer,
		"power_tier": power_tier,
		"router_tier": router_tier,
		"research_levels": research_levels.duplicate(),
		"company_milestones_reached": company_milestones_reached,
		"ai_platform_level": ai_platform_level,
		"ddos_active": ddos_active,
		"day_number": day_number,
		"time_of_day": time_of_day,
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
	}
	_rpc_sync_sim_tick.rpc(packet)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_sim_tick(packet: Dictionary) -> void:
	if not multiplayer.is_server():
		money = float(packet["money"])
		breaker_on = bool(packet["breaker_on"])
		ups_backup_active = bool(packet["ups_backup_active"])
		avg_ups_charge = float(packet["avg_ups_charge"])
		overload_timer = float(packet["overload_timer"])
		power_tier = int(packet["power_tier"])
		router_tier = clampi(int(packet.get("router_tier", 0)), 0, ROUTER_TIERS.size() - 1)
		research_levels = _sanitize_research(packet.get("research_levels", {}))
		ai_platform_level = int(packet["ai_platform_level"])
		company_milestones_reached = int(packet.get("company_milestones_reached", company_milestones_reached))
		ddos_active = bool(packet["ddos_active"])
		day_number = int(packet["day_number"])
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
	state_updated.emit()
