extends Node
## Zentrale Sicherheits-, Moderations-, Anti-Cheat- und Save-Integritätsschicht.
## Läuft als Autoload (SecurityGuard) und wird primär vom Host/Server durchgesetzt.

const NAME_MIN_LEN := 2
const NAME_MAX_LEN := 20
const CHAT_MAX_LEN := 160
const SAVE_SIG_SALT := "DCT_COOP_SAVE_INTEGRITY_V1::"

## Plausibilitätsgrenzen für Spielstände (Anti-Save-Tamper / Anti-NaN).
const MAX_MONEY := 50000000.0
const MIN_MONEY := -500000.0
const MAX_DAY := 99999

## Kuratierte Blockliste für riskante Namen, Beleidigungen und Hassrede (DE + EN).
## Wird nach Kleinschreibung + Umlaut- + Leetspeak-Normalisierung geprüft.
const BLOCKED_SUBSTRINGS: Array[String] = [
	# Extremismus / Hassrede
	"nazi", "hitler", "adolf", "sswaffen", "waffenss", "holocaust", "kzmanager",
	"gestapo", "reichsbuerger", "siegheil", "heilhitler", "whitepower", "kkk",
	"neger", "nigger", "nigga", "kanake", "kanacke", "judensau", "faggot",
	"schwuchtel", "tranny", "retard", "spast", "spasti", "behindert",
	# Schwere Beleidigungen & Vulgärsprache (DE)
	"hurensohn", "hurentochter", "fotze", "wichser", "wixxer", "wixer",
	"arschloch", "arschl", "arschfick", "fick", "ficker", "gefickt", "verfickt",
	"schlampe", "nutte", "hure", "bastard", "missgeburt", "drecksau",
	"scheisse", "scheiss", "pimmel", "schwanzlutscher", "kackbratze",
	"vollidiot", "penner", "pisser", "verpiss",
	# Schwere Beleidigungen & Vulgärsprache (EN)
	"fuck", "motherfucker", "shit", "bitch", "cunt", "dickhead", "asshole",
	"cocksucker", "whore", "slut", "bastard", "rape", "rapist", "pedo", "pedophile",
	"porn", "porno", "hentai", "suckmy", "killurself", "killyourself", "kys",
]

## Reservierte Begriffe, die Nicht-Hosts nicht als Namen verwenden dürfen (Impersonation-Schutz).
const IMPERSONATION_TERMS: Array[String] = [
	"admin", "administrator", "host", "server", "system", "sysadmin",
	"mod", "moderator", "dev", "developer", "support", "staff", "owner",
	"gm", "gamemaster", "official", "offiziell",
]

## Unsichtbare Unicode- und BiDi-Steuerzeichen, die Namen/Chat verzerren oder spoofen können.
const INVISIBLE_CODEPOINTS: Array[int] = [
	0x00AD, # Soft hyphen
	0x034F, # Combining grapheme joiner
	0x061C, # Arabic letter mark
	0x180E, # Mongolian vowel separator
	0x200B, 0x200C, 0x200D, 0x200E, 0x200F, # Zero-width & LRM/RLM
	0x202A, 0x202B, 0x202C, 0x202D, 0x202E, # BiDi embeddings/overrides
	0x2060, 0x2061, 0x2062, 0x2063, 0x2064, # Word joiner / invisible ops
	0x2066, 0x2067, 0x2068, 0x2069, # BiDi isolates
	0xFEFF, # BOM / ZWNBSP
]

## peer_id -> { bucket_name: Array[int] (timestamps in msec) }
var _rate_hits: Dictionary = {}


# ---------------------------------------------------------------- Text- & Namensfilter

## Entfernt Steuerzeichen, unsichtbare Unicode-Zeichen und mehrfache Leerzeichen.
func strip_invisible_and_controls(raw: String) -> String:
	var out := ""
	var prev_space := false
	for i in range(raw.length()):
		var cp := raw.unicode_at(i)
		if cp < 0x20 or cp == 0x7F or (cp >= 0x80 and cp <= 0x9F):
			if cp == 0x09 or cp == 0x0A or cp == 0x0D:
				if not prev_space:
					out += " "
					prev_space = true
			continue
		if INVISIBLE_CODEPOINTS.has(cp):
			continue
		var ch := raw.substr(i, 1)
		if ch == " ":
			if prev_space:
				continue
			prev_space = true
		else:
			prev_space = false
		out += ch
	return out.strip_edges()


## Normalisiert Text für die Filterprüfung (Kleinbuchstaben, Umlaute, Leetspeak).
func _normalize_for_filter(raw: String, strip_separators: bool = true) -> String:
	var s := strip_invisible_and_controls(raw).to_lower()
	s = s.replace("ä", "a").replace("ö", "o").replace("ü", "u").replace("ß", "s")
	s = s.replace("0", "o").replace("1", "i").replace("3", "e").replace("4", "a")
	s = s.replace("5", "s").replace("7", "t").replace("8", "b")
	s = s.replace("@", "a").replace("$", "s").replace("!", "i").replace("|", "i").replace("+", "t")
	var out := ""
	for i in range(s.length()):
		var ch := s.substr(i, 1)
		var is_alnum := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")
		if is_alnum:
			out += ch
		elif not strip_separators:
			out += " "
	return out


## Reduziert wiederholte Buchstaben (z. B. "fuuuuck" -> "fuck").
func _collapse_repeats(s: String, max_repeat: int = 1) -> String:
	if s.is_empty():
		return ""
	var out := ""
	var last := ""
	var run := 0
	for i in range(s.length()):
		var ch := s.substr(i, 1)
		if ch == last:
			run += 1
			if run <= max_repeat:
				out += ch
		else:
			last = ch
			run = 1
			out += ch
	return out


## Prüft, ob ein Text einen blockierten Begriff enthält (inkl. Leetspeak & Buchstaben-Streckung).
func contains_blocked_term(raw: String) -> bool:
	var norm := _normalize_for_filter(raw, true)
	if norm.is_empty():
		return false
	var collapsed1 := _collapse_repeats(norm, 1)
	var collapsed2 := _collapse_repeats(norm, 2)
	for term in BLOCKED_SUBSTRINGS:
		if norm.contains(term) or collapsed1.contains(term) or collapsed2.contains(term):
			return true
	return false


## Prüft, ob ein Spielername versucht, Host/Admin/System zu imitieren.
func is_impersonation_name(raw: String) -> bool:
	var norm := _normalize_for_filter(raw, true)
	if norm.is_empty():
		return false
	for term in IMPERSONATION_TERMS:
		if norm == term or norm.begins_with(term) and norm.length() <= term.length() + 2:
			return true
	return false


## Bereinigt einen Spielernamen serverseitig: Längenlimit, Steuerzeichen, Filter, Impersonation & Duplikate.
func sanitize_player_name(raw: String, existing_names: Array = [], is_host: bool = false, fallback: String = "Techniker") -> String:
	var clean := strip_invisible_and_controls(raw).left(NAME_MAX_LEN).strip_edges()
	var invalid := clean.length() < NAME_MIN_LEN \
		or contains_blocked_term(clean) \
		or (not is_host and is_impersonation_name(clean))
	if invalid:
		clean = "Host" if is_host else fallback
	return _deduplicate_name(clean, existing_names)


func _deduplicate_name(candidate: String, existing_names: Array) -> String:
	var lower_set := {}
	for n in existing_names:
		lower_set[str(n).to_lower()] = true
	if not lower_set.has(candidate.to_lower()):
		return candidate
	for idx in range(2, 99):
		var suffix := " #%d" % idx
		var base := candidate.left(NAME_MAX_LEN - suffix.length()).strip_edges()
		var attempt := base + suffix
		if not lower_set.has(attempt.to_lower()):
			return attempt
	return candidate.left(NAME_MAX_LEN - 4) + " #99"


## Bereinigt freie Bezeichnungen (Rack-Namen, Welt-/Firmennamen).
func sanitize_label(raw: String, max_len: int = 24, fallback: String = "") -> String:
	var clean := strip_invisible_and_controls(raw).left(max_len).strip_edges()
	if clean.is_empty():
		return fallback
	if contains_blocked_term(clean):
		return fallback
	return clean


## Filtert eine Chat-Nachricht: entfernt Steuerzeichen, begrenzt Länge und zensiert blockierte Wörter mit ***.
func filter_chat_message(raw: String) -> String:
	var clean := strip_invisible_and_controls(raw).left(CHAT_MAX_LEN).strip_edges()
	if clean.is_empty():
		return ""
	var words := clean.split(" ", false)
	var out_words: Array[String] = []
	var censored_any := false
	for w in words:
		if contains_blocked_term(w):
			out_words.append("***")
			censored_any = true
		else:
			out_words.append(w)
	var joined := " ".join(out_words)
	# Zweiter Durchgang gegen getrennte Schreibweisen wie "f u c k" oder "n a z i".
	if not censored_any and contains_blocked_term(joined):
		return "[Nachricht gefiltert]"
	return joined


# ---------------------------------------------------------------- Anti-Cheat: Rate-Limit & Zahlenprüfung

func is_finite_float(v: float) -> bool:
	return not is_nan(v) and not is_inf(v)


func is_finite_vec3(v: Vector3, max_abs: float = 10000.0) -> bool:
	return is_finite_float(v.x) and is_finite_float(v.y) and is_finite_float(v.z) \
		and absf(v.x) <= max_abs and absf(v.y) <= max_abs and absf(v.z) <= max_abs


## Sliding-Window Rate-Limiter pro Peer und Kategorie.
## Gibt true zurück, wenn der Aufruf erlaubt ist; false, wenn das Limit überschritten wurde.
func check_rate_limit(peer_id: int, bucket: String, max_hits: int, window_sec: float, exempt_host: bool = true) -> bool:
	if exempt_host and peer_id <= 1:
		return true
	var now := Time.get_ticks_msec()
	var window_ms := int(window_sec * 1000.0)
	if not _rate_hits.has(peer_id):
		_rate_hits[peer_id] = {}
	var peer_buckets: Dictionary = _rate_hits[peer_id]
	var hits: Array = peer_buckets.get(bucket, [])
	var kept: Array = []
	for t in hits:
		if now - int(t) <= window_ms:
			kept.append(t)
	if kept.size() >= max_hits:
		peer_buckets[bucket] = kept
		return false
	kept.append(now)
	peer_buckets[bucket] = kept
	return true


func clear_peer(peer_id: int) -> void:
	_rate_hits.erase(peer_id)


func clear_all_rate_limits() -> void:
	_rate_hits.clear()


# ---------------------------------------------------------------- Savegame-Integrität

## Erzeugt kanonisches JSON mit sortierten Schlüsseln, damit SHA-256 deterministisch bleibt.
func _canonical_json(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var d: Dictionary = value
			var keys := d.keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
			var parts: Array[String] = []
			for k in keys:
				parts.append("%s:%s" % [JSON.stringify(str(k)), _canonical_json(d[k])])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY:
			var arr: Array = value
			var parts: Array[String] = []
			for item in arr:
				parts.append(_canonical_json(item))
			return "[%s]" % ",".join(parts)
		TYPE_FLOAT:
			var f := float(value)
			if not is_finite_float(f):
				return "0"
			# Einheitliche Darstellung für ganze Floats (JSON.parse macht ints oft zu floats).
			if is_equal_approx(f, roundf(f)) and absf(f) < 9007199254740991.0:
				return str(int(roundf(f)))
			return "%.4f" % f
		_:
			return JSON.stringify(value)


func compute_save_signature(serialized_state: Dictionary) -> String:
	return (SAVE_SIG_SALT + _canonical_json(serialized_state)).sha256_text()


## Prüft die Signatur (falls vorhanden) und korrigiert unplausible Werte im Save-State.
## Rückgabe: { "status": "valid" | "unsigned" | "tampered", "sanitized_changes": int }
func verify_and_sanitize_save(root: Dictionary, deserialized_state: Dictionary) -> Dictionary:
	var status := "unsigned"
	if root.has("_sig") and root.has("state") and root["state"] is Dictionary:
		var expected := compute_save_signature(root["state"] as Dictionary)
		var actual := str(root.get("_sig", ""))
		status = "valid" if actual == expected else "tampered"

	var changes := 0
	changes += _clamp_float_field(deserialized_state, "money", MIN_MONEY, MAX_MONEY, 1200.0)
	changes += _clamp_float_field(deserialized_state, "reputation", 0.0, 100.0, 50.0)
	changes += _clamp_float_field(deserialized_state, "time_of_day", 0.0, 0.999, 0.36)
	changes += _clamp_float_field(deserialized_state, "room_temp", 10.0, 95.0, 22.0)
	changes += _clamp_int_field(deserialized_state, "room_level", 0, 2, 0)
	changes += _clamp_int_field(deserialized_state, "power_tier", 0, 10, 0)
	changes += _clamp_int_field(deserialized_state, "router_tier", 0, 10, 0)
	changes += _clamp_int_field(deserialized_state, "ai_platform_level", 0, 10, 0)
	changes += _clamp_int_field(deserialized_state, "day_number", 1, MAX_DAY, 1)
	changes += _clamp_int_field(deserialized_state, "fuse_stock", 0, 99, 0)
	changes += _clamp_int_field(deserialized_state, "power_fuse_stock", 0, 1, 0)
	changes += _clamp_int_field(deserialized_state, "power_strips", 0, 20, 0)
	changes += _clamp_int_field(deserialized_state, "net_hubs", 0, 20, 0)

	# Rack-Namen im Save ebenfalls säubern
	if deserialized_state.has("racks") and deserialized_state["racks"] is Dictionary:
		var racks_dict: Dictionary = deserialized_state["racks"]
		for rk_v in racks_dict.values():
			if rk_v is Dictionary:
				var rk: Dictionary = rk_v
				var cname := str(rk.get("custom_name", ""))
				if not cname.is_empty():
					var safe_cname := sanitize_label(cname, 24, "")
					if safe_cname != cname:
						rk["custom_name"] = safe_cname
						changes += 1

	return {
		"status": status,
		"sanitized_changes": changes,
	}


func _clamp_float_field(d: Dictionary, key: String, lo: float, hi: float, fallback: float) -> int:
	if not d.has(key):
		return 0
	var raw := float(d[key])
	if not is_finite_float(raw):
		d[key] = fallback
		return 1
	var clamped := clampf(raw, lo, hi)
	if not is_equal_approx(clamped, raw):
		d[key] = clamped
		return 1
	return 0


func _clamp_int_field(d: Dictionary, key: String, lo: int, hi: int, fallback: int) -> int:
	if not d.has(key):
		return 0
	var raw_v: Variant = d[key]
	if typeof(raw_v) != TYPE_INT and typeof(raw_v) != TYPE_FLOAT:
		d[key] = fallback
		return 1
	var raw := int(raw_v)
	var clamped := clampi(raw, lo, hi)
	if clamped != raw:
		d[key] = clamped
		return 1
	return 0
