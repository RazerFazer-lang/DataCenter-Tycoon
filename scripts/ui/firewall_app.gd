class_name FirewallApp
extends RefCounted
## PC-App „Firewall“ (GAME-06): Regeln vorher setzen, bei einem Angriff den Verkehr ansehen und die
## Angreifer blocken. Daten und Aktionen kommen aus CyberManager. state: {"msg": "", "ok": true}

const T := preload("res://scripts/ui/finance_apps.gd")


static func render(host: Control, state: Dictionary, _refresh: Callable) -> void:
	var body := T._scroll_body(host)
	T._header(body, "net", T._t("Verion Firewall"), T._t("Regeln senken das Risiko schon vorher. Läuft ein Angriff, sieh dir die Quellen an und blocke die Angreifer, bevor die Zeit abläuft."))
	T._feedback_bar(body, str(state.get("msg", "")), bool(state.get("ok", true)))
	var a: Dictionary = Cyber.attack
	var adm: Dictionary = Cyber.admin()
	T._stat_tiles(body, [
		[T._t("Lage"), T._t("ANGRIFF") if not a.is_empty() else T._t("ruhig"), T.COL_BAD if not a.is_empty() else T.COL_GOOD],
		[T._t("Abgewehrt"), str(int(Cyber.stats.get("won", 0))), T.COL_GOOD],
		[T._t("Durchgekommen"), str(int(Cyber.stats.get("lost", 0))), T.COL_BAD if int(Cyber.stats.get("lost", 0)) > 0 else T.COL_TEXT],
		[T._t("Netzwerk-Admin"), str(adm.get("name", "–")) if not adm.is_empty() else T._t("keiner"), T.COL_TEXT],
	])
	if not a.is_empty():
		_attack(body, a)
	for rid in Cyber.encrypted.keys():
		var ec := T._card(body, T.COL_BAD)
		ec.add_child(T._label(T._t("%s ist verschlüsselt, noch %d s bis zur Wiederherstellung.") % [GameState.get_rack_display_name(str(rid)), ceili(float(Cyber.encrypted[rid]))], 13, T.COL_BAD, true))
	T._section(body, T._t("Regeln"))
	for id in Cyber.RULE_ORDER:
		var r: Dictionary = Cyber.RULES[id]
		var on := Cyber.has_rule(id)
		var card := T._card(body, T.COL_ACCENT if on else Color(0, 0, 0, 0))
		var top := HBoxContainer.new()
		card.add_child(top)
		var nm := T._label(T._t(str(r["name"])), 15, T.COL_TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		if int(r["cost"]) > 0:
			top.add_child(T._label(T._t("%s am Tag") % T._money(float(r["cost"])), 12, T.COL_MUTED))
		var rid2: String = id
		var b := T._button(T._t("Aus") if on else T._t("An"), T.COL_MUTED if on else T.COL_ACCENT, func(): Cyber.request_set_rule(rid2, not on))
		top.add_child(b)
		card.add_child(T._label(T._t(str(r["desc"])), 12, T.COL_MUTED, true))
	if adm.is_empty():
		var ac := T._card(body)
		ac.add_child(T._label(T._t("Ein Netzwerk-Admin (App Personal) blockt Angreifer von selbst. Je erfahrener, desto schneller und genauer."), 12, T.COL_MUTED, true))
	if not Cyber.history.is_empty():
		T._section(body, T._t("Letzte Angriffe"))
		var hc := T._card(body)
		for i in range(Cyber.history.size() - 1, -1, -1):
			var h: Dictionary = Cyber.history[i]
			var ok := str(h["result"]) != "durchgekommen"
			hc.add_child(T._label(T._t("Tag %d  •  %s  •  %s") % [int(h["day"]), T._t(str(Cyber.KINDS.get(str(h["kind"]), {}).get("name", ""))), T._t(str(h["result"]))], 12, T.COL_GOOD if ok else T.COL_BAD))


static func _attack(body: VBoxContainer, a: Dictionary) -> void:
	var k: Dictionary = Cyber.KINDS.get(str(a["kind"]), {})
	var card := T._card(body, T.COL_BAD)
	var top := HBoxContainer.new()
	card.add_child(top)
	var nm := T._label(T._t(str(k.get("name", ""))), 17, T.COL_BAD)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	top.add_child(T._label(T._t("noch %d s  •  %d Angreifer offen") % [ceili(float(a["left"])), Cyber.bad_left()], 13, T.COL_TEXT))
	card.add_child(T._bar(float(a["left"]) / maxf(1.0, float(a["total"])), T.COL_BAD))
	var hint := {
		"ddos": "Viele Anfragen von wenigen Quellen legen den Uplink lahm. Achte auf sehr hohe Raten und auffällige Muster.",
		"bruteforce": "Jemand probiert Passwörter an den Admin-Zugängen. Läuft die Zeit ab, ist er drin.",
		"ransom": "Ein Schadprogramm versucht, ein Rack zu verschlüsseln. Blocke es, bevor es fertig ist.",
	}
	card.add_child(T._label(T._t(str(hint.get(str(a["kind"]), ""))), 12, T.COL_MUTED, true))
	card.add_child(T._label(T._t("Echte Kunden zu sperren kostet Zufriedenheit. Das Muster verrät die Angreifer, die Rate allein nicht immer."), 12, T.COL_WARN, true))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	card.add_child(grid)
	for h in ["Quelle", "Land", "Anfragen/s", "Muster", ""]:
		grid.add_child(T._label(T._t(h), 12, T.COL_MUTED))
	for s in a.get("sources", []):
		var blocked := bool(s["blocked"])
		var col := T.COL_MUTED if blocked else T.COL_TEXT
		grid.add_child(T._label(str(s["ip"]), 12, col))
		grid.add_child(T._label(T._t(str(s["country"])), 12, col))
		grid.add_child(T._label(str(int(s["rps"])), 12, col))
		grid.add_child(T._label(T._t(str(s["pattern"])), 12, col))
		if blocked:
			grid.add_child(T._label(T._t("gesperrt"), 12, T.COL_MUTED))
		else:
			var sid := str(s["id"])
			grid.add_child(T._button(T._t("Blocken"), T.COL_BAD, func(): Cyber.request_block(sid)))
