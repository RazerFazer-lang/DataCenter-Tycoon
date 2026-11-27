class_name WhatsNew
extends RefCounted
## Versionen und Changelog (REL-06): Vergleich, Auswahl und Kennungen. Angezeigt wird alles im Reiter
## CHANGELOG des Hauptmenüs (ChangelogPage). Die Einträge kommen aus res://version.json, derselben Datei,
## aus der der Launcher seine Patchnotes liest.

## So viele Versionen zeigt das Fenster höchstens (die neuesten zuerst).
const MAX_VERSIONS := 3
const SOURCE := "res://version.json"


## "v3.4.0" oder "3.4" -> [3, 4, 0]. Unbrauchbares wird zu 0.
static func parse_version(v: String) -> Array[int]:
	var out: Array[int] = []
	var clean := v.strip_edges().trim_prefix("v").trim_prefix("V")
	for part in clean.split("."):
		var digits := ""
		for ch in part:
			if ch >= "0" and ch <= "9":
				digits += ch
			else:
				break
		out.append(int(digits) if not digits.is_empty() else 0)
	while out.size() < 3:
		out.append(0)
	return out


## -1, 0 oder 1 wie bei einem Vergleich a < b, a == b, a > b.
static func compare(a: String, b: String) -> int:
	var pa := parse_version(a)
	var pb := parse_version(b)
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i] if i < pa.size() else 0
		var y := pb[i] if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0


static func load_changelog(path: String = SOURCE) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("changelog", []) is Array):
		return []
	return (parsed as Dictionary)["changelog"]


## Einträge, die neuer sind als after und höchstens upto, neueste zuerst. after "" = alle bis upto.
static func entries_between(changelog: Array, after: String, upto: String, limit: int = MAX_VERSIONS) -> Array:
	var out: Array = []
	for e in changelog:
		if not (e is Dictionary):
			continue
		var v := str((e as Dictionary).get("version", ""))
		if v.is_empty() or compare(v, upto) > 0:
			continue
		if not after.is_empty() and compare(v, after) <= 0:
			continue
		out.append(e)
	out.sort_custom(func(x, y): return compare(str(x["version"]), str(y["version"])) > 0)
	return out.slice(0, limit)


## Nach einem Update einmal zeigen. Wer das Spiel zum ersten Mal startet, bekommt nichts zu sehen.
## Ältere Versionen kannten den Wert noch nicht: Wer schon Spielstände hat, sieht die neue Version.
static func should_show(last_seen: String, current: String, returning_player: bool) -> bool:
	if last_seen.strip_edges().is_empty():
		return returning_player
	return compare(current, last_seen) > 0


## Text eines Eintrags in Kennzeichnung und Text zerlegen: "[CO-OP] Text" -> ["CO-OP", "Text"].
static func split_item(item: String) -> Array[String]:
	var s := item.strip_edges()
	if s.begins_with("["):
		var close := s.find("]")
		if close > 1:
			return [s.substr(1, close - 1).strip_edges(), s.substr(close + 1).strip_edges()]
	return ["", s]

