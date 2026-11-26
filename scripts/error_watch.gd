class_name ErrorWatch
extends Logger
## Schreibt beim ersten Auftreten jedes Engine-Fehlers eine Zeile Spielkontext ins Log
## (Standort, Sitzung, offene Fenster). Engine-Fehler wie „Parameter "material" is null“ nennen
## sonst nur die Engine-Datei; mit dem Kontext lässt sich ein Spieler-Log nachstellen.
## Wird aus beliebigen Threads aufgerufen: hier nur zählen, Text erst im Haupt-Thread bauen.

const MAX_REPORTS := 24

var _mutex := Mutex.new()
var _seen: Dictionary = {}
var _reports := 0
## Liefert den Kontext-Text (läuft im Haupt-Thread).
var context_provider: Callable = Callable()
## Zuletzt gemeldete Kontextzeile (für Tests).
var last_report: String = ""


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var key := "%s:%d" % [file.get_file(), line]
	_mutex.lock()
	var first := not _seen.has(key) and _reports < MAX_REPORTS
	_seen[key] = int(_seen.get(key, 0)) + 1
	if first:
		_reports += 1
	_mutex.unlock()
	if first:
		var what := rationale if not rationale.is_empty() else code
		_report.call_deferred(key, function, what)


func _report(key: String, function: String, what: String) -> void:
	var ctx := str(context_provider.call()) if context_provider.is_valid() else ""
	last_report = "[Fehlerkontext] %s (%s): %s | %s" % [key, function, what.left(120), ctx]
	print(last_report)


func count_of(file_and_line: String) -> int:
	_mutex.lock()
	var n := int(_seen.get(file_and_line, 0))
	_mutex.unlock()
	return n
