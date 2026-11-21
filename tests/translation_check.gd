extends SceneTree
## Prüft, ob die englische Übersetzung geladen wird und der deutsche Fallback greift.
## Aufruf: godot --headless --path . --script res://tests/translation_check.gd

const CASES := {
	"HAUPTMENÜ": "MAIN MENU",
	"Sprache": "Language",
	"Speichern": "Save",
	"SPEICHERN": "SAVE",
	"Fenster": "Windowed",
	"Verbinde mit %s:%d...": "Connecting to %s:%d...",
	"TAG %d": "DAY %d",
	"Ankunft in %d s  •  %d Artikel": "Arriving in %d s  •  %d items",
	"%s  •  Tag %d, %s Uhr": "%s  •  Day %d, %s",
	"%s hat die Hauptsicherung EINGESCHALTET.": "%s switched the main breaker ON.",
	"%s hat Vertrag '%s' gekündigt.": "%s cancelled contract '%s'.",
	"[E] Hauptsicherung AUSSCHALTEN": "[E] switch main breaker OFF",
	"Trägt: %s  •  [Q] Ablegen": "Carrying: %s  •  [Q] put down",
}


func _init() -> void:
	var failures := 0

	TranslationServer.set_locale("en")
	for key in CASES.keys():
		var got := String(TranslationServer.translate(key))
		if got != CASES[key]:
			printerr("FEHLER en: '%s' -> '%s' (erwartet '%s')" % [key, got, CASES[key]])
			failures += 1

	TranslationServer.set_locale("de")
	for key in CASES.keys():
		var got := String(TranslationServer.translate(key))
		if got != key:
			printerr("FEHLER de: '%s' -> '%s' (erwartet unverändert)" % [key, got])
			failures += 1

	failures += _check_csv("res://translations/strings.csv")

	print("Ergebnis: %d Fehler" % failures)
	quit(1 if failures > 0 else 0)


## Prüft jede CSV-Zeile: Übersetzung kommt an und die Platzhalter stimmen überein.
func _check_csv(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("FEHLER: %s nicht lesbar (%s)" % [path, error_string(FileAccess.get_open_error())])
		return 1
	var header := f.get_csv_line()
	var en_col := header.find("en")
	if en_col < 1:
		printerr("FEHLER: Spalte 'en' fehlt in %s" % path)
		return 1

	var spec := RegEx.new()
	# GDScript-Formatierung: Flags - + 0, Breite/Präzision als Zahl oder *, kein Leerzeichen-Flag.
	spec.compile("%[-+0]*(?:\\d+|\\*)?(?:\\.(?:\\d+|\\*))?[scdoxXfv%]")

	TranslationServer.set_locale("en")
	var failures := 0
	var rows := 0
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() <= en_col or row[0].is_empty():
			continue
		rows += 1
		var key: String = row[0]
		var want: String = row[en_col]
		if want.is_empty():
			printerr("FEHLER csv: '%s' hat keine englische Übersetzung" % key.c_escape())
			failures += 1
			continue
		var got := String(TranslationServer.translate(key))
		if got != want:
			printerr("FEHLER csv: '%s' -> '%s' (erwartet '%s')" % [key.c_escape(), got.c_escape(), want.c_escape()])
			failures += 1
		var key_specs := _specs(spec, key)
		var want_specs := _specs(spec, want)
		if key_specs != want_specs:
			printerr("FEHLER Platzhalter: '%s' %s vs. '%s' %s" % [key.c_escape(), str(key_specs), want.c_escape(), str(want_specs)])
			failures += 1
	print("CSV: %d Einträge geprüft" % rows)
	return failures


func _specs(re: RegEx, s: String) -> PackedStringArray:
	var out := PackedStringArray()
	for m in re.search_all(s):
		out.append(m.get_string())
	return out