extends Node
## Verlauf von Kontostand, Stromverbrauch und Raumtemperatur für die Diagramme der Monitor-App.
## Läuft bei jedem Spieler und liest nur Werte, die der Sim-Tick ohnehin synchronisiert.

signal sample_added

## Abstand zwischen zwei Messpunkten in Sekunden.
const SAMPLE_INTERVAL := 5.0
## 360 Punkte * 5 s = 30 Minuten Verlauf.
const MAX_SAMPLES := 360
const SERIES: Array[String] = ["money", "watts", "temp"]

var _data: Dictionary = {}
var _last_ms: int = -1


func _ready() -> void:
	clear()
	GameState.state_updated.connect(_on_state_updated)
	GameState.world_snapshot_loaded.connect(clear)


func clear() -> void:
	for key in SERIES:
		_data[key] = PackedFloat64Array()
	_last_ms = -1
	sample_added.emit()


## Verlauf für den Spielstand. Packed-Arrays werden zu normalen Arrays, damit JSON sie sauber schreibt.
func export_data() -> Dictionary:
	var out: Dictionary = {}
	for key in SERIES:
		out[key] = Array(get_series(key))
	return out


## Stellt den Verlauf aus einem Spielstand wieder her. Fehlende oder kaputte Reihen bleiben leer.
func import_data(data: Variant) -> void:
	clear()
	if not (data is Dictionary):
		return
	var d: Dictionary = data
	for key in SERIES:
		var raw: Variant = d.get(key, [])
		if not (raw is Array):
			continue
		var arr := PackedFloat64Array()
		for v in raw:
			if v is float or v is int:
				arr.append(float(v))
		if arr.size() > MAX_SAMPLES:
			arr = arr.slice(arr.size() - MAX_SAMPLES)
		_data[key] = arr
	sample_added.emit()


## Messwerte einer Reihe, älteste zuerst. Unbekannte Reihen liefern ein leeres Array.
func get_series(key: String) -> PackedFloat64Array:
	return _data.get(key, PackedFloat64Array())


func _on_state_updated() -> void:
	var now := Time.get_ticks_msec()
	if _last_ms >= 0 and now - _last_ms < int(SAMPLE_INTERVAL * 1000.0):
		return
	_last_ms = now
	_push("money", float(GameState.money))
	_push("watts", float(GameState.total_watts))
	_push("temp", float(GameState.room_temp))
	sample_added.emit()


func _push(key: String, value: float) -> void:
	var arr: PackedFloat64Array = _data.get(key, PackedFloat64Array())
	arr.append(value)
	while arr.size() > MAX_SAMPLES:
		arr.remove_at(0)
	_data[key] = arr