class_name HalleNordLayout
extends RefCounted
## Maße und feste Einbauten von Halle Nord (seit v3.8: 24 × 14 m, drei Abschnitte).
## Alle Werte sind lokal zu GameState.HALLE_NORD_ORIGIN (x quer, z: Rückwand -7, Rolltor +7).
## Halle, Platzierung, Wege und Geräte lesen ihre Zahlen nur hier, damit nichts auseinanderläuft.

## Innenseite der Außenwände.
const WALL_X := 11.86
const WALL_Z := 6.86
## Mitte der Außenwände (Wandstärke 0,25 m).
const SHELL_X := 12.0
const SHELL_Z := 7.0
const CEILING_Y := 4.6
const ROOF_Y := 5.0
## Abschnitte quer zur Halle: [x von, x bis]. Abschnitt 1 ist beim Kauf dabei.
const SECTIONS := [[-11.86, -4.0], [-4.0, 4.0], [4.0, 11.86]]
## Trennwände vor Abschnitt 2 und 3.
const PARTITION_X := [-4.0, 4.0]
const PARTITION_T := 0.22
const MAX_SECTIONS := 3

## Rolltor in der Vorderwand.
const DOOR_X := -7.0
const DOOR_W := 3.8
const DOOR_H := 3.6

## Technikecke hinten links (Verteiler Abschnitt 1, Core-Switch, USV).
const TECH_MIN := Vector2(-11.86, -6.86)
const TECH_MAX := Vector2(-8.2, -3.7)
## Büro vorne links mit dem PC.
const OFFICE_MIN := Vector2(-11.86, 3.5)
const OFFICE_MAX := Vector2(-9.3, 6.86)

## Stromverteiler je Abschnitt (Mitte der Front an der Rückwand) und Steckdosen je Verteiler.
const BREAKER_POS := [Vector3(-10.9, 0.0, -6.66), Vector3(0.0, 0.0, -6.66), Vector3(8.0, 0.0, -6.66)]
const BREAKER_W := 1.4
const BREAKER_D := 0.4
const BREAKER_PORTS := [16, 12, 12]
## Leistung je offenem Abschnitt.
const WATTS_PER_SECTION := 4500
## Core-Switch-Schrank in der Technikecke; Ports: Grundausstattung + je weiterer Abschnitt.
const CORE_POS := Vector3(-9.1, 0.0, -6.36)
const CORE_PORTS_BASE := 16
const CORE_PORTS_PER_SECTION := 12
const CORE_COLS := 10

## PC-Tisch im Büro (mit Blick zur Hallenmitte) und Shuttle-Kiosk neben dem Rolltor.
const DESK_POS := Vector3(-11.4, 0.0, 5.3)
const DESK_YAW := 90.0
const KIOSK_POS := Vector3(-4.55, 0.0, 6.45)
const KIOSK_YAW := 180.0
## Ersatzteilregal an der Westwand.
const SHELF_POS := Vector3(-11.5, 0.0, 0.0)

## Ankunft mit dem Shuttle: draußen vor dem Rolltor, Blick aufs Tor.
const ARRIVAL := Vector3(-2.8, 0.12, 9.4)
const ARRIVAL_YAW := 1.09

## Feste Einbauten als Rechtecke [Mitte x, Mitte z, halbe Breite, halbe Tiefe].
## Hier darf nichts hingestellt werden und Figuren laufen drumherum.
const SOLID := [
	[-10.03, -5.28, 1.85, 1.60], # Technikecke
	[-10.58, 5.18, 1.30, 1.70], # Büro
	[-4.55, 6.45, 0.45, 0.42], # Shuttle-Kiosk
	[-11.5, 0.0, 0.36, 0.82], # Ersatzteilregal
	[0.0, -6.55, 0.80, 0.40], # Verteiler Abschnitt 2
	[8.0, -6.55, 0.80, 0.40], # Verteiler Abschnitt 3
]
## Frei zu haltende Wege (nur für Geräte, nicht für Figuren): vor dem Rolltor, vor Büro- und Technik-Tür,
## vor den Verteilern.
const KEEP_FREE := [
	[-7.0, 5.6, 2.3, 1.4],
	[-9.8, -3.2, 0.9, 0.6],
	[-8.8, 4.4, 0.6, 0.7],
	[0.0, -5.7, 1.0, 0.55],
	[8.0, -5.7, 1.0, 0.55],
]


## Lokale Position zu einer Weltposition (nur x/z).
static func local(pos: Vector3) -> Vector3:
	return pos - GameState.HALLE_NORD_ORIGIN


## Weltposition liegt am Standort Halle Nord (Halle, Hof und Umgebung).
static func is_nord(pos: Vector3) -> bool:
	return pos.z < -100.0


## Anzahl offener Abschnitte (0, solange die Halle nicht fertig ist).
static func sections() -> int:
	if not GameState.halle_nord_owned:
		return 0
	var n := 1
	if GameState.has_building_upgrade("upg_nord_section_2"):
		n += 1
		if GameState.has_building_upgrade("upg_nord_section_3"):
			n += 1
	return n


## Innere Grenze nach Osten: Trennwand des nächsten gesperrten Abschnitts oder die Außenwand.
static func open_max_x(n_sections: int = -1) -> float:
	var n := sections() if n_sections < 0 else n_sections
	if n <= 1:
		return PARTITION_X[0] - PARTITION_T * 0.5
	if n == 2:
		return PARTITION_X[1] - PARTITION_T * 0.5
	return WALL_X


## Abschnitt (0..2) zu einer lokalen x-Position.
static func section_of_x(lx: float) -> int:
	if lx < PARTITION_X[0]:
		return 0
	if lx < PARTITION_X[1]:
		return 1
	return 2


## Punkt (lokal) liegt im begehbaren, offenen Innenraum.
static func inside_local(lx: float, lz: float, margin: float = 0.0) -> bool:
	return lx > -WALL_X + margin and lx < open_max_x() - margin and lz > -WALL_Z + margin and lz < WALL_Z - margin


## Spieler-/Kameraposition (Welt) ist im Gebäude (für Akustik, Schritte, Himmel).
static func in_building(pos: Vector3) -> bool:
	var l := local(pos)
	return absf(l.x) < SHELL_X + 0.1 and absf(l.z) < SHELL_Z + 0.1 and pos.y < ROOF_Y + 0.5


## Rechteck (lokal, Mitte + halbe Größe) trifft einen festen Einbau.
static func hits_solid(c: Vector2, half: Vector2) -> bool:
	for b in SOLID:
		if absf(c.x - float(b[0])) < half.x + float(b[2]) and absf(c.y - float(b[1])) < half.y + float(b[3]):
			return true
	return false


static func hits_keep_free(c: Vector2, half: Vector2) -> bool:
	for b in KEEP_FREE:
		if absf(c.x - float(b[0])) < half.x + float(b[2]) and absf(c.y - float(b[1])) < half.y + float(b[3]):
			return true
	return false


## Darf ein Gerät mit diesem Grundriss (lokal) hier stehen?
static func can_stand(c: Vector2, half: Vector2) -> bool:
	if c.x - half.x < -WALL_X + 0.05 or c.x + half.x > open_max_x() - 0.05:
		return false
	if c.y - half.y < -WALL_Z + 0.05 or c.y + half.y > WALL_Z - 0.05:
		return false
	return not hits_solid(c, half) and not hits_keep_free(c, half)


## Steckdosen am Verteiler eines Abschnitts.
static func breaker_ports(section_idx: int) -> int:
	return int(BREAKER_PORTS[clampi(section_idx, 0, 2)])


static func core_ports(n_sections: int = -1) -> int:
	var n := sections() if n_sections < 0 else n_sections
	return CORE_PORTS_BASE + CORE_PORTS_PER_SECTION * maxi(0, n - 1)


## Weltposition der Steckdose i am Verteiler eines Abschnitts.
static func breaker_socket(section_idx: int, i: int) -> Vector3:
	var p: Vector3 = BREAKER_POS[clampi(section_idx, 0, 2)]
	var n := breaker_ports(section_idx)
	var per_row := 8
	var row := i / per_row
	var col := i % per_row
	var cols_in_row := mini(per_row, n - row * per_row)
	var x := p.x + (float(col) - float(cols_in_row - 1) * 0.5) * 0.15
	return GameState.HALLE_NORD_ORIGIN + Vector3(x, 0.98 - float(row) * 0.2, p.z + BREAKER_D * 0.5 + 0.035)


## Weltposition des Ports i am Core-Switch (Patchfeld vorne am Schrank).
static func core_socket(i: int) -> Vector3:
	var row := i / CORE_COLS
	var col := i % CORE_COLS
	return GameState.HALLE_NORD_ORIGIN + CORE_POS + Vector3(-0.27 + float(col) * 0.06, 1.62 - float(row) * 0.13, 0.52)
