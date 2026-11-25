class_name MarketApp
extends RefCounted
## Markt-App im PC: Marktanteile, Konkurrenz, eigene Preise, Werbung und Kunden zum Abwerben.
## Daten und Aktionen kommen aus MarketManager. state: {"tab": "overview", "service": "web", "msg": "", "ok": true}

const T := preload("res://scripts/ui/finance_apps.gd")
const COL_YOU := Color(0.10, 0.62, 0.92)
const COL_FREE := Color(0.55, 0.60, 0.68)
const TABS := [["overview", "Überblick"], ["prices", "Meine Preise"], ["ads", "Werbung"], ["leads", "Kunden abwerben"]]


static func render(host: Control, state: Dictionary, refresh: Callable) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	host.add_child(bar)
	var tab := str(state.get("tab", "overview"))
	for t in TABS:
		var tid := str(t[0])
		var txt := T._t(str(t[1]))
		if tid == "leads" and not MarketManager.leads.is_empty():
			txt += " (%d)" % MarketManager.leads.size()
		var sel := tab == tid
		var b := Button.new()
		b.text = txt
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		MailApp._flat(b, T.COL_ACCENT if sel else Color(0.90, 0.92, 0.95), T.COL_ACCENT if sel else Color(0.84, 0.87, 0.91), Color.WHITE if sel else T.COL_TEXT)
		b.pressed.connect(func():
			state["tab"] = tid
			state["msg"] = ""
			SfxManager.play("click", -12.0, 1.1)
			refresh.call()
		)
		bar.add_child(b)
	var body := T._scroll_body(host)
	T._feedback_bar(body, str(state.get("msg", "")), bool(state.get("ok", true)))
	if not MarketManager.poach.is_empty():
		_poach_card(body)
	match tab:
		"prices":
			_render_prices(body, refresh)
		"ads":
			_render_ads(body)
		"leads":
			_render_leads(body)
		_:
			_render_overview(body)


static func rival_color(rid: String) -> Color:
	return MarketManager.RIVALS[rid]["color"]


# ---------------------------------------------------------------- Überblick

static func _render_overview(body: VBoxContainer) -> void:
	var sh := MarketManager.get_total_shares()
	T._header(body, "market", "Markt & Konkurrenz", "Alle Firmen kämpfen um dieselben Kunden. Es zählen Preis, Ruf und Qualität. Zufriedene Kunden bleiben.")
	var card := T._card(body)
	var head := HBoxContainer.new()
	card.add_child(head)
	var l := T._label("Marktanteile (nach Umsatz)", 14, T.COL_TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	head.add_child(T._label(T._t("Du: %.1f %%") % (float(sh["you"]) * 100.0), 16, COL_YOU))
	card.add_child(share_bar(sh, 22.0))
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 16)
	card.add_child(legend)
	_legend(legend, COL_YOU, T._t("Du"), float(sh["you"]))
	for rid in MarketManager.RIVAL_ORDER:
		_legend(legend, rival_color(rid), MarketManager.rival_name(rid), float(sh[rid]))
	_legend(legend, COL_FREE, T._t("Noch frei"), float(sh["free"]))
	var w := MarketManager.level_weight()
	if w < 1.0:
		card.add_child(T._label("Du bist noch klein, die Konkurrenz beachtet dich kaum. Ab Firmenstufe 3 wird es ernst.", 12, T.COL_MUTED, true))

	T._section(body, "Konkurrenten")
	for rid in MarketManager.RIVAL_ORDER:
		_rival_card(body, rid)
	T._section(body, "Nachrichten")
	var nc := T._card(body)
	if MarketManager.news.is_empty():
		nc.add_child(T._label("Noch nichts passiert.", 13, T.COL_MUTED))
	for n_v in MarketManager.news:
		var n: Dictionary = n_v
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		nc.add_child(row)
		row.add_child(T._label(T._t("Tag %d") % int(n["day"]), 12, T.COL_MUTED))
		var rid := str(n.get("rival", ""))
		if MarketManager.RIVALS.has(rid):
			row.add_child(T._icon(str(MarketManager.RIVALS[rid]["icon"]), 15, rival_color(rid)))
		row.add_child(T._label(GameState.format_message(str(n["text"]), n.get("args", [])), 13, T.COL_TEXT, true))


static func _legend(parent: Control, col: Color, name: String, share: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var dot := Control.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.draw.connect(func(): dot.draw_circle(Vector2(6, 6), 5.0, col))
	row.add_child(dot)
	row.add_child(T._label("%s  %.1f %%" % [name, share * 100.0], 12, T.COL_TEXT))


static func share_bar(sh: Dictionary, h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.draw.connect(func():
		var x := 0.0
		var parts: Array = [["you", COL_YOU]]
		for rid in MarketManager.RIVAL_ORDER:
			parts.append([rid, rival_color(rid)])
		parts.append(["free", Color(0.55, 0.60, 0.68, 0.35)])
		for p in parts:
			var pw := c.size.x * float(sh.get(p[0], 0.0))
			if pw > 0.5:
				c.draw_rect(Rect2(x, 0, maxf(1.0, pw - 1.0), h), p[1])
			x += pw
	)
	return c


static func logo(rid: String, px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, px)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col := rival_color(rid)
	c.draw.connect(func():
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.25)
		sb.set_corner_radius_all(int(px * 0.24))
		sb.border_color = col.lightened(0.25)
		sb.set_border_width_all(1)
		c.draw_style_box(sb, Rect2(0, 0, px, px))
		UIStyle.draw_icon(c, str(MarketManager.RIVALS[rid]["icon"]), Rect2(px * 0.2, px * 0.2, px * 0.6, px * 0.6), Color.WHITE)
	)
	return c


static func _rival_card(body: VBoxContainer, rid: String) -> void:
	var r: Dictionary = MarketManager.rivals[rid]
	var d: Dictionary = MarketManager.RIVALS[rid]
	var card := T._card(body, rival_color(rid))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	row.add_child(logo(rid, 46.0))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 1)
	row.add_child(v)
	v.add_child(T._label("%s  •  %s" % [str(d["name"]), T._t(str(d["kind"]))], 15, T.COL_TEXT))
	v.add_child(T._label(str(d["motto"]), 12, T.COL_MUTED))
	if str(r["state"]) == "pleite":
		v.add_child(T._label("Pleite. Sucht einen neuen Investor.", 13, T.COL_BAD))
		return
	var strong: Array = []
	for s in (d["spec"] as Dictionary).keys():
		strong.append(T._t(str(HardwareCatalog.RENTAL_PROFILES[str(s)]["short"])))
	v.add_child(T._label(T._t("Stark bei: %s") % ", ".join(strong), 12, T.COL_MUTED, true))
	var state_txt := ""
	if int(r.get("outage_until", 0)) >= GameState.day_number:
		state_txt = "Kämpft mit einem Ausfall"
	elif int(r.get("war_until", 0)) >= GameState.day_number:
		state_txt = "Preiskampf läuft"
	elif int(r.get("ad_until", 0)) >= GameState.day_number:
		state_txt = "Werbekampagne läuft"
	if state_txt != "":
		v.add_child(T._label(state_txt, 12, T.COL_WARN))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 1)
	row.add_child(g)
	var tr_v := float(r.get("trend", 0.0))
	for pair in [
		["Kunden", "%d %s" % [int(MarketManager.rival_users(rid)), "▲" if tr_v > 0.15 else ("▼" if tr_v < -0.15 else "•")], T.COL_GOOD if tr_v > 0.15 else (T.COL_BAD if tr_v < -0.15 else T.COL_TEXT)],
		["Preise", "%d %%" % int(roundf(float(r["price"]) * 100.0)), T.COL_TEXT],
		["Qualität", "%d" % int(r["quality"]), T.COL_TEXT],
		["Ruf", "%d" % int(r["rep"]), T.COL_TEXT],
	]:
		g.add_child(T._label(str(pair[0]), 12, T.COL_MUTED))
		var vl := T._label(str(pair[1]), 13, pair[2])
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.custom_minimum_size = Vector2(80, 0)
		g.add_child(vl)


# ---------------------------------------------------------------- Preise

static func _render_prices(body: VBoxContainer, refresh: Callable) -> void:
	T._header(body, "coin", "Meine Preise", "Günstig bringt mehr neue Kunden, teuer mehr Gewinn pro Kunde. Über 115 % wandern mit der Zeit Kunden ab.")
	var own: Array[String] = []
	var rest: Array[String] = []
	for s in MarketManager.services_list():
		if MarketManager.player_users(s) > 0.0:
			own.append(s)
		else:
			rest.append(s)
	T._section(body, "Deine Dienste")
	if own.is_empty():
		T._card(body).add_child(T._label("Du vermietest noch keinen Dienst. Öffne ein Rack und wähle einen Mietvertrag.", 13, T.COL_MUTED, true))
	for s in own:
		_price_card(body, s, refresh)
	T._section(body, "Weitere Dienste")
	for s in rest:
		_price_card(body, s, refresh)


static func _price_card(body: VBoxContainer, s: String, refresh: Callable) -> void:
	var p: Dictionary = HardwareCatalog.RENTAL_PROFILES[s]
	var price := MarketManager.get_price(s)
	var card := T._card(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	row.add_child(v)
	v.add_child(T._label(T._t(str(p["label"])), 14, T.COL_TEXT))
	v.add_child(T._label(T._t("$%.2f pro Nutzer  •  Markt im Schnitt %d %%  •  Neue Kunden: %s") % [
		float(p["pay_per_user"]) * price, int(roundf(MarketManager.market_price(s) * 100.0)), T._t(MarketManager.outlook_label(s))], 12, T.COL_MUTED, true))
	v.add_child(share_bar(MarketManager.get_shares(s), 8.0))
	var minus := T._button("–", Color(0.46, 0.51, 0.60), func():
		MarketManager.request_set_price(s, price - MarketManager.PRICE_STEP)
		refresh.call()
	, price > MarketManager.PRICE_MIN + 0.001)
	row.add_child(minus)
	var pl := T._label("%d %%" % int(roundf(price * 100.0)), 18, T.COL_GOOD if price < 0.99 else (T.COL_WARN if price > 1.151 else T.COL_TEXT))
	pl.custom_minimum_size = Vector2(64, 0)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pl)
	row.add_child(T._button("+", Color(0.46, 0.51, 0.60), func():
		MarketManager.request_set_price(s, price + MarketManager.PRICE_STEP)
		refresh.call()
	, price < MarketManager.PRICE_MAX - 0.001))


# ---------------------------------------------------------------- Werbung

static func _render_ads(body: VBoxContainer) -> void:
	T._header(body, "flag", "Werbung", "Kampagnen bringen einige Spieltage lang mehr neue Kunden. Zwei können gleichzeitig laufen.")
	T._stat_tiles(body, [
		["Laufende Werbung", "%d / %d" % [MarketManager.campaigns.size(), MarketManager.CAMPAIGNS_MAX], T.COL_TEXT],
		["Mehr neue Kunden", "+%d %%" % int(roundf(MarketManager.ad_boost() * 100.0)), T.COL_GOOD],
		["Kontostand", T._money(GameState.money), T.COL_TEXT],
	])
	for k in MarketManager.CAMPAIGNS.keys():
		var c: Dictionary = MarketManager.CAMPAIGNS[k]
		var left := 0
		for run in MarketManager.campaigns:
			if str((run as Dictionary)["kind"]) == str(k):
				left = int((run as Dictionary)["days_left"])
		var card := T._card(body, T.COL_GOOD if left > 0 else Color(0, 0, 0, 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		v.add_child(T._label(str(c["name"]), 15, T.COL_TEXT))
		v.add_child(T._label(str(c["desc"]), 12, T.COL_MUTED, true))
		v.add_child(T._label(T._t("+%d %% neue Kunden für %d Tage") % [int(float(c["boost"]) * 100.0), int(c["days"])], 12, T.COL_GOOD))
		var lvl_ok: bool = GameState.get_company_level() >= int(c["level"])
		if left > 0:
			row.add_child(T._label(T._t("Läuft noch %d Tag(e)") % left, 13, T.COL_GOOD))
		elif not lvl_ok:
			row.add_child(T._label(T._t("Ab Firmenstufe %d") % int(c["level"]), 13, T.COL_MUTED))
		else:
			row.add_child(T._button(T._t("Starten ($%d)") % int(c["cost"]), T.COL_GOOD, func(): MarketManager.request_campaign(str(k)),
				GameState.money >= float(c["cost"]) and MarketManager.campaigns.size() < MarketManager.CAMPAIGNS_MAX))


# ---------------------------------------------------------------- Abwerben

static func _poach_card(body: VBoxContainer) -> void:
	var p: Dictionary = MarketManager.poach
	var card := T._card(body, T.COL_BAD)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	row.add_child(logo(str(p["rival"]), 40.0))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(T._label(T._t("%s will %s abwerben!") % [MarketManager.rival_name(str(p["rival"])), str(p["customer"])], 15, T.COL_BAD))
	v.add_child(T._label(T._t("%s ist unzufrieden. Noch %d Sekunden: Rabatt geben oder die Zufriedenheit über 72 %% bringen.") % [
		GameState.get_rack_display_name(str(p["rack_id"])), int(float(p["left"]))], 12, T.COL_MUTED, true))
	row.add_child(T._button(T._t("Treuerabatt ($%d)") % int(p["cost"]), T.COL_GOOD, MarketManager.request_counter_poach, GameState.money >= float(p["cost"])))


static func _render_leads(body: VBoxContainer) -> void:
	T._header(body, "people", "Kunden abwerben", "Diese Kunden sind mit der Konkurrenz unzufrieden. Mit einer Wechselprämie kommen sie vielleicht zu dir.")
	if MarketManager.leads.is_empty():
		T._card(body).add_child(T._label("Gerade sucht niemand einen neuen Anbieter. Nach Ausfällen und Pannen der Konkurrenz lohnt sich ein Blick.", 13, T.COL_MUTED, true))
	for lid in MarketManager.leads.keys():
		var l: Dictionary = MarketManager.leads[lid]
		var s := str(l["service"])
		var ready: bool = MarketManager.has_running_service(s)
		var card := T._card(body, rival_color(str(l["rival"])))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		row.add_child(logo(str(l["rival"]), 40.0))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		v.add_child(T._label(T._t("%s (bisher %s)") % [str(l["customer"]), MarketManager.rival_name(str(l["rival"]))], 15, T.COL_TEXT))
		v.add_child(T._label(T._t("%s  •  %d Nutzer  •  Angebot bis Tag %d") % [T._t(str(HardwareCatalog.RENTAL_PROFILES[s]["short"])), int(l["users"]), int(l["until_day"])], 12, T.COL_MUTED))
		if not ready:
			v.add_child(T._label("Dafür brauchst du ein laufendes Rack mit diesem Dienst.", 12, T.COL_WARN, true))
		row.add_child(T._label(T._t("Chance %d %%") % int(MarketManager.lead_chance(l) * 100.0), 14, T.COL_TEXT))
		row.add_child(T._button(T._t("Angebot ($%d)") % int(l["cost"]), T.COL_GOOD, func(): MarketManager.request_lead_offer(str(lid)), ready and GameState.money >= float(l["cost"])))
