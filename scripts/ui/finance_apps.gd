class_name FinanceApps
extends RefCounted
## Inhalte der Finanz-Apps im PC: Personal, Bank und Rechnungen.
## Die Daten kommen aus FinanceManager. Buttons schicken nur Anfragen, der Host entscheidet.

const FinanceScript := preload("res://scripts/autoload/finance_manager.gd")

const COL_TEXT := Color(0.10, 0.14, 0.20)
const COL_MUTED := Color(0.38, 0.43, 0.50)
const COL_CARD := Color(1.0, 1.0, 1.0)
const COL_BORDER := Color(0.82, 0.85, 0.89)
const COL_ACCENT := Color(0.10, 0.46, 0.82)
const COL_GOOD := Color(0.13, 0.55, 0.30)
const COL_BAD := Color(0.78, 0.18, 0.15)
const COL_WARN := Color(0.85, 0.55, 0.08)
const STATEMENT_ROWS := 20
const PAID_ROWS := 10


# ---------------------------------------------------------------- Personal

static func render_staff(host: Control, feedback: String, feedback_ok: bool) -> void:
	var body := _scroll_body(host)
	_header(body, "people", "Personalverwaltung", "Stelle Mitarbeiter ein. Löhne werden zu jedem Tagesbeginn abgebucht.")
	_feedback_bar(body, feedback, feedback_ok)

	var team: Array = FinanceManager.get_employees_sorted()
	var wages: int = FinanceManager.get_daily_wage_total()
	var full: bool = team.size() >= FinanceScript.MAX_EMPLOYEES
	_stat_tiles(body, [
		["Team", "%d / %d" % [team.size(), FinanceScript.MAX_EMPLOYEES], COL_TEXT],
		["Löhne pro Tag", _money(float(wages)), COL_BAD if wages > 0 else COL_TEXT],
		["Kontostand", _money(GameState.money), COL_BAD if GameState.money < 0.0 else COL_GOOD],
	])

	_section(body, "Dein Team")
	if team.is_empty():
		var empty_card := _card(body)
		empty_card.add_child(_label("Noch niemand eingestellt. Support-Agenten beantworten Tickets, Buchhalter bezahlen deine Rechnungen, Techniker bauen und reparieren Server.", 13, COL_MUTED, true))
	for e_v in team:
		var e: Dictionary = e_v
		var eid := str(e["id"])
		var role := str(e["role"])
		var skill := int(e["skill"])
		var wage := int(e["wage"])
		var card := _card(body, COL_ACCENT)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		row.add_child(_icon(_role_icon(role), 30, COL_ACCENT))

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(_label(str(e["name"]), 15, COL_TEXT))
		info.add_child(_label(_t("%s  •  Erfahrung %d/5  •  seit Tag %d") % [_t(FinanceManager.get_role_title(role)), skill, int(e["hired_day"])], 12, COL_MUTED))
		info.add_child(_bar(float(skill) / 5.0, COL_ACCENT))
		info.add_child(_label(_work_text(role, skill, int(e["work_done"])), 12, COL_MUTED, true))
		if role == "technician":
			_technician_options(info, e)

		var right := VBoxContainer.new()
		right.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(right)
		var wage_lbl := _label(_t("%s / Tag") % _money(float(wage)), 14, COL_TEXT)
		wage_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(wage_lbl)
		var severance := float(wage * FinanceScript.SEVERANCE_DAYS)
		right.add_child(_button(_t("Entlassen (Abfindung %s)") % _money(severance), COL_BAD, func(): FinanceManager.request_fire(eid)))

	_section(body, "Bewerbungen")
	var cands: Array = FinanceManager.get_candidates()
	if cands.is_empty():
		var none_card := _card(body)
		none_card.add_child(_label("Zurzeit liegen keine Bewerbungen vor.", 13, COL_MUTED, true))
	for c_v in cands:
		var c: Dictionary = c_v
		var idx := int(c["pool_idx"])
		var role := str(c["role"])
		var skill := int(c["skill"])
		var wage := int(c["wage"])
		var r: Dictionary = FinanceScript.ROLES.get(role, {})
		var card := _card(body)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		row.add_child(_icon(_role_icon(role), 30, COL_MUTED))

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(_label("%s  —  %s" % [str(c["name"]), _t(FinanceManager.get_role_title(role))], 15, COL_TEXT))
		info.add_child(_label(_t("Erfahrung %d/5  •  Lohn %s pro Tag") % [skill, _money(float(wage))], 12, COL_MUTED))
		info.add_child(_bar(float(skill) / 5.0, COL_MUTED))
		info.add_child(_label(_t(str(r.get("desc", ""))), 12, COL_MUTED, true))

		var can_pay := GameState.money >= float(wage)
		var hire_btn := _button(_t("Einstellen (Startprämie %s)") % _money(float(wage)), COL_GOOD, func(): FinanceManager.request_hire(idx), not full and can_pay)
		if full:
			hire_btn.tooltip_text = _t("Das Team ist voll.")
		elif not can_pay:
			hire_btn.tooltip_text = _t("Zu wenig Geld für die Startprämie.")
		row.add_child(hire_btn)


static func _role_icon(role: String) -> String:
	var r: Dictionary = FinanceScript.ROLES.get(role, {})
	return str(r.get("icon", "people"))


static func _work_text(role: String, skill: int, done: int) -> String:
	if role == "support":
		var interval := maxf(FinanceScript.SUPPORT_MIN_INTERVAL, FinanceScript.SUPPORT_BASE_INTERVAL - FinanceScript.SUPPORT_SKILL_STEP * float(skill))
		return _t("Beantwortet etwa alle %d s ein offenes Ticket  •  %d Tickets beantwortet") % [int(interval), done]
	if role == "accounting":
		var when := _t("einen Tag vor Fälligkeit") if skill >= 3 else _t("am Fälligkeitstag")
		return _t("Bezahlt Rechnungen %s  •  %d Rechnungen bezahlt") % [when, done]
	if role == "technician":
		return _t("Arbeitsqualität etwa %d %%  •  %d Server fertig") % [40 + skill * 11, done]
	return ""


## Schicht und Aufgaben eines Technikers.
static func _technician_options(info: VBoxContainer, e: Dictionary) -> void:
	var eid := str(e["id"])
	var on_duty: bool = str(TechnicianManager.view.get("id", "")) == eid
	if on_duty:
		info.add_child(_label(_t("Gerade: %s") % str(TechnicianManager.view.get("text", "")), 12, COL_GOOD, true))
		_blocked_jobs(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	info.add_child(row)
	var night: bool = TechnicianManager.shift_of(e) == "night"
	row.add_child(_button(_t("Schicht: Nacht (18–6 Uhr)") if night else _t("Schicht: Tag (6–18 Uhr)"), COL_ACCENT,
		func(): TechnicianManager.request_set_shift(eid, "day" if night else "night")))
	for d in [["build", "Bauen"], ["repair", "Reparieren"], ["service", "Überholen"]]:
		var duty := str(d[0])
		var on: bool = TechnicianManager.has_duty(e, duty)
		row.add_child(_button(("✓ " if on else "✗ ") + _t(str(d[1])), COL_GOOD if on else COL_MUTED,
			func(): TechnicianManager.request_set_duty(eid, duty, not on)))


## Aufträge, an die der Techniker nicht herankam: was, wann er es wieder versucht, Knopf für sofort.
static func _blocked_jobs(info: VBoxContainer) -> void:
	var list: Array = TechnicianManager.view.get("blocked", []) if TechnicianManager.view.get("blocked", []) is Array else []
	if list.is_empty():
		return
	var since := float(Time.get_ticks_msec() - int(TechnicianManager.view.get("blocked_stamp", TechnicianManager.view.get("stamp", 0)))) / 1000.0
	var shown := 0
	for b_v in list:
		if not (b_v is Array) or (b_v as Array).size() < 3:
			continue
		var b: Array = b_v
		var left := int(ceilf(float(b[1]) - since))
		if left <= 0:
			continue
		var what := str(b[2]).strip_edges()
		var line := _t("Kommt nicht hin: %s") % str(b[0])
		if what != "":
			line += "  •  " + _t("wollte: %s") % what
		line += "  •  " + _t("neuer Versuch in %d s") % left
		info.add_child(_label(line, 12, COL_WARN, true))
		shown += 1
	if shown == 0:
		return
	info.add_child(_label("Meist steht etwas im Weg oder das Garagentor ist zu.", 11, COL_MUTED, true))
	var retry := _button(_t("Jetzt erneut versuchen"), COL_ACCENT, func(): TechnicianManager.request_retry_blocked())
	retry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_child(retry)


# ---------------------------------------------------------------- Bank

static func render_bank(host: Control, feedback: String, feedback_ok: bool) -> void:
	var body := _scroll_body(host)
	_header(body, "bank", "Hanse Direktbank", "Geschäftskonto deiner Firma, Kredite und Kontoauszug.")
	_feedback_bar(body, feedback, feedback_ok)

	var debt: float = FinanceManager.get_total_debt()
	var rates: float = FinanceManager.get_daily_loan_payments()
	_stat_tiles(body, [
		["Kontostand", _money(GameState.money), COL_BAD if GameState.money < 0.0 else COL_GOOD],
		["Restschuld gesamt", _money(debt), COL_BAD if debt > 0.0 else COL_TEXT],
		["Raten pro Tag", _money(rates), COL_TEXT],
	])

	# Bonität
	var score: int = FinanceManager.credit_score
	var score_ratio := float(score - FinanceScript.SCORE_MIN) / float(FinanceScript.SCORE_MAX - FinanceScript.SCORE_MIN)
	var score_col := COL_GOOD if score >= 680 else (COL_WARN if score >= 560 else COL_BAD)
	var score_card := _card(body, score_col)
	score_card.add_child(_label(_t("Bonität: %d  (%s)") % [score, _t(FinanceManager.get_score_label())], 15, COL_TEXT))
	score_card.add_child(_bar(score_ratio, score_col))
	score_card.add_child(_label(_t("Kreditrahmen %s  •  davon frei %s") % [
		_money(float(FinanceManager.get_credit_limit())), _money(FinanceManager.get_free_credit())
	], 13, COL_TEXT))
	score_card.add_child(_label("Pünktlich bezahlte Rechnungen und Raten verbessern die Bonität. Mahnungen, Inkasso und geplatzte Raten senken sie.", 12, COL_MUTED, true))
	score_card.add_child(_label(_t("Firmenstufe %d: Kreditrahmen +%d %%. Höhere Stufen schalten größere Kredite frei.") % [
		GameState.get_company_level(), int(roundf((FinanceManager.get_credit_level_factor() - 1.0) * 100.0))
	], 12, COL_MUTED, true))

	# Laufende Kredite
	_section(body, "Laufende Kredite")
	var loans: Array = FinanceManager.get_loans_sorted()
	if loans.is_empty():
		var empty_card := _card(body)
		empty_card.add_child(_label("Du hast keine laufenden Kredite.", 13, COL_MUTED, true))
	for l_v in loans:
		var ln: Dictionary = l_v
		var lid := str(ln["id"])
		var remaining := float(ln["remaining"])
		var total := maxf(1.0, float(ln["total_due"]))
		var missed := int(ln["missed"])
		var card := _card(body, COL_BAD if missed > 0 else COL_ACCENT)
		var top := HBoxContainer.new()
		card.add_child(top)
		var title := _label("%s  •  %s" % [_t(str(ln["title"])), lid], 15, COL_TEXT)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(title)
		top.add_child(_label(_t("Restschuld %s von %s") % [_money(remaining), _money(total)], 13, COL_TEXT))
		card.add_child(_bar(1.0 - remaining / total, COL_GOOD))
		card.add_child(_label(_t("Rate %s pro Tag  •  noch %d Tage  •  Zins %d %%  •  aufgenommen an Tag %d") % [
			_money(float(ln["daily_payment"])), int(ln["days_left"]), int(roundf(float(ln["rate"]) * 100.0)), int(ln["taken_day"])
		], 12, COL_MUTED, true))
		if missed > 0:
			card.add_child(_label(_t("%d Rate(n) geplatzt. Jede geplatzte Rate kostet %d %% Verzugszins.") % [
				missed, int(FinanceScript.LOAN_LATE_PENALTY_PCT * 100.0)
			], 12, COL_BAD, true))
		var cost: int = FinanceManager.get_loan_repay_cost(ln)
		var repay := _button(_t("Sondertilgung %s (%d %% Rabatt)") % [_money(float(cost)), int(FinanceScript.EARLY_REPAY_DISCOUNT * 100.0)],
			COL_ACCENT, func(): FinanceManager.request_repay_loan(lid), GameState.money >= float(cost))
		repay.size_flags_horizontal = Control.SIZE_SHRINK_END
		card.add_child(repay)

	# Angebote
	_section(body, "Kreditangebote")
	for o_v in FinanceScript.LOAN_OFFERS:
		var offer: Dictionary = o_v
		var oid := str(offer["id"])
		var reason: String = FinanceManager.get_offer_block_reason(offer)
		var card := _card(body)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(_label(_t("%s über %s") % [_t(str(offer["title"])), _money(float(offer["amount"]))], 15, COL_TEXT))
		info.add_child(_label(_t("Zins %d %%  •  Laufzeit %d Tage  •  Rückzahlung %s  •  Rate %s pro Tag") % [
			int(roundf(float(offer["rate"]) * 100.0)), int(offer["days"]),
			_money(float(FinanceManager.get_offer_total(offer))), _money(float(FinanceManager.get_offer_daily(offer)))
		], 12, COL_MUTED, true))
		var req := PackedStringArray()
		var min_level := int(offer.get("min_level", 1))
		if min_level > 1:
			req.append(_t("Ab Firmenstufe %d") % min_level)
		if int(offer["min_score"]) > 0:
			req.append(_t("Ab Bonität %d") % int(offer["min_score"]))
		if not req.is_empty():
			info.add_child(_label("  •  ".join(req), 12, COL_MUTED))
		if not reason.is_empty():
			info.add_child(_label(reason, 12, COL_BAD, true))
		row.add_child(_button("Kredit beantragen", COL_GOOD, func(): FinanceManager.request_take_loan(oid), reason.is_empty()))

	# Kontoauszug
	_section(body, "Kontoauszug")
	var st_card := _card(body)
	var entries: Array = FinanceManager.statement
	if entries.is_empty():
		st_card.add_child(_label("Noch keine Buchungen.", 13, COL_MUTED))
		return
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	st_card.add_child(grid)
	for head in ["Tag", "Buchung", "Betrag", "Saldo"]:
		grid.add_child(_label(str(head), 12, COL_MUTED))
	for i in range(mini(STATEMENT_ROWS, entries.size())):
		var en: Dictionary = entries[i]
		var amount := float(en["amount"])
		grid.add_child(_label(str(int(en["day"])), 12, COL_TEXT))
		var txt := _label(FinanceManager.format_text(str(en["text"]), en.get("args", [])), 12, COL_TEXT)
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.clip_text = true
		grid.add_child(txt)
		var amt := _label(("+" if amount >= 0.0 else "") + _money(amount), 12, COL_GOOD if amount >= 0.0 else COL_BAD)
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(amt)
		var bal := float(en["balance"])
		var bal_lbl := _label(_money(bal), 12, COL_BAD if bal < 0.0 else COL_TEXT)
		bal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(bal_lbl)


# ---------------------------------------------------------------- Rechnungen

static func render_bills(host: Control, feedback: String, feedback_ok: bool) -> void:
	var body := _scroll_body(host)
	_header(body, "invoice", "Rechnungen & Zahlungen", "Strom kommt täglich, Miete, Internet und Versicherung wöchentlich. Zahlst du zu spät, kommen Mahnungen und am Ende das Inkasso.")
	_feedback_bar(body, feedback, feedback_ok)

	var open_bills: Array = FinanceManager.get_open_bills()
	var open_total: float = FinanceManager.get_open_bills_total()
	var dunning: int = FinanceManager.get_dunning_count()
	var next_week: int = FinanceManager.get_next_weekly_day()
	_stat_tiles(body, [
		["Offene Rechnungen", str(open_bills.size()), COL_TEXT],
		["Summe offen", _money(open_total), COL_BAD if open_total > 0.0 else COL_TEXT],
		["Mahnungen", str(dunning), COL_BAD if dunning > 0 else COL_TEXT],
		["Nächste Wochenrechnungen", (_t("Tag %d") % next_week) if next_week >= 0 else "–", COL_TEXT],
	])

	var acc: Dictionary = FinanceManager.get_accountant()
	var acc_card := _card(body, COL_GOOD if not acc.is_empty() else COL_BORDER)
	var acc_row := HBoxContainer.new()
	acc_row.add_theme_constant_override("separation", 10)
	acc_card.add_child(acc_row)
	acc_row.add_child(_icon("people", 22, COL_GOOD if not acc.is_empty() else COL_MUTED))
	var acc_text := ""
	if acc.is_empty():
		acc_text = "Kein Buchhalter angestellt. In der Personal-App kannst du einen einstellen, der fällige Rechnungen automatisch bezahlt."
	else:
		acc_text = _t("%s bezahlt fällige Rechnungen automatisch, solange genug Geld auf dem Konto ist.") % str(acc["name"])
	acc_row.add_child(_label(acc_text, 13, COL_TEXT, true))
	if not open_bills.is_empty():
		var pay_all := _button(_t("Alle bezahlen (%s)") % _money(open_total), COL_ACCENT, func(): FinanceManager.request_pay_all(), GameState.money > 0.0)
		acc_row.add_child(pay_all)

	_section(body, "Offen")
	if open_bills.is_empty():
		var empty_card := _card(body)
		empty_card.add_child(_label("Alles bezahlt. Keine offenen Rechnungen.", 13, COL_MUTED, true))
	var today: int = GameState.day_number
	for b_v in open_bills:
		var b: Dictionary = b_v
		var bid := str(b["id"])
		var amount := float(b["amount"])
		var due := int(b["due_day"])
		var lvl := int(b["dunning"])
		var days_left := due - today
		var accent := COL_ACCENT
		if lvl > 0 or days_left < 0:
			accent = COL_BAD
		elif days_left <= 1:
			accent = COL_WARN
		var card := _card(body, accent)

		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 12)
		card.add_child(top)
		top.add_child(_icon(str(b.get("icon", "invoice")), 30, accent))
		var who := VBoxContainer.new()
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(who)
		who.add_child(_label(str(b["vendor"]), 15, COL_TEXT))
		who.add_child(_label(_t("%s  •  Rechnungsnummer %s") % [_t(str(b["title"])), bid], 12, COL_MUTED))
		var amt_box := VBoxContainer.new()
		top.add_child(amt_box)
		var amt_lbl := _label(_money(amount), 18, COL_TEXT)
		amt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amt_box.add_child(amt_lbl)
		if lvl > 0:
			var badge := _label(_t("%d. Mahnung") % lvl, 12, COL_BAD)
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			amt_box.add_child(badge)

		card.add_child(HSeparator.new())
		card.add_child(_label(_t("Rechnungsdatum: Tag %d   •   Fällig: Tag %d   •   %s") % [int(b["issued_day"]), due, _due_text(days_left)], 12, accent if accent != COL_ACCENT else COL_TEXT, true))
		var details: Array = b.get("details", [])
		for d in details:
			var d_txt: String = FinanceManager.format_text(str(d["text"]), d.get("args", [])) if d is Dictionary else FinanceManager.format_text(str(d))
			card.add_child(_label("•  " + d_txt, 12, COL_MUTED, true))

		var pay := _button("Jetzt bezahlen", COL_GOOD, func(): FinanceManager.request_pay_bill(bid), GameState.money >= amount)
		if GameState.money < amount:
			pay.tooltip_text = _t("Es fehlen %s.") % _money(amount - GameState.money)
		pay.size_flags_horizontal = Control.SIZE_SHRINK_END
		card.add_child(pay)

	_section(body, "Bezahlt")
	var paid: Array = FinanceManager.paid_bills
	var paid_card := _card(body)
	if paid.is_empty():
		paid_card.add_child(_label("Noch keine Rechnung bezahlt.", 13, COL_MUTED))
		return
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	paid_card.add_child(grid)
	for head in ["Tag", "Nr.", "Empfänger", "Betrag", "Bezahlt von"]:
		grid.add_child(_label(str(head), 12, COL_MUTED))
	for i in range(mini(PAID_ROWS, paid.size())):
		var p: Dictionary = paid[i]
		grid.add_child(_label(str(int(p.get("paid_day", 0))), 12, COL_TEXT))
		grid.add_child(_label(str(p["id"]), 12, COL_TEXT))
		var vendor := _label("%s (%s)" % [str(p["vendor"]), _t(str(p["title"]))], 12, COL_TEXT)
		vendor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vendor.clip_text = true
		grid.add_child(vendor)
		var amt := _label(_money(float(p["amount"])), 12, COL_TEXT)
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(amt)
		grid.add_child(_label(FinanceManager.format_text(str(p.get("paid_by", "")), p.get("paid_by_args", [])), 12, COL_MUTED))


static func _due_text(days_left: int) -> String:
	if days_left < 0:
		return _t("überfällig seit %d Tag(en)") % -days_left
	if days_left == 0:
		return _t("heute fällig")
	if days_left == 1:
		return _t("morgen fällig")
	return _t("fällig in %d Tagen") % days_left


# ---------------------------------------------------------------- Bausteine

static func _money(v: float) -> String:
	return FinanceScript.format_money(v)


## Übersetzt eine Vorlage, bevor Werte eingesetzt werden. Labels und Buttons
## übersetzen nur ihren fertigen Text, eine Formatvorlage fänden sie nicht.
static func _t(text: String) -> String:
	return String(TranslationServer.translate(text))


static func _scroll_body(host: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + str(side), 14)
	scroll.add_child(margin)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	return body


static func _label(text: String, font_size: int, col: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = TranslationServer.translate(text)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func _card(parent: Control, accent: Color = Color(0, 0, 0, 0)) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_CARD
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	if accent.a > 0.0:
		sb.border_color = accent
		sb.border_width_left = 4
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	return v


static func _header(parent: Control, icon_kind: String, title: String, subtitle: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	row.add_child(_icon(icon_kind, 36, COL_ACCENT))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(_label(title, 20, COL_TEXT))
	v.add_child(_label(subtitle, 12, COL_MUTED, true))


static func _section(parent: Control, text: String) -> void:
	var l := _label(text, 15, COL_TEXT)
	parent.add_child(l)


static func _feedback_bar(parent: Control, msg: String, ok: bool) -> void:
	if msg.is_empty():
		return
	var card := _card(parent, COL_GOOD if ok else COL_BAD)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	row.add_child(_icon("check" if ok else "warn", 18, COL_GOOD if ok else COL_BAD))
	row.add_child(_label(msg, 13, COL_TEXT, true))


static func _stat_tiles(parent: Control, items: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	for it_v in items:
		var it: Array = it_v
		var card := _card(row)
		card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(_label(str(it[0]), 12, COL_MUTED))
		var col: Color = it[2]
		card.add_child(_label(str(it[1]), 18, col))


static func _bar(ratio: float, col: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.step = 0.001
	pb.value = clampf(ratio, 0.0, 1.0)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 8)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.88, 0.90, 0.93)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(4)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fill)
	return pb


static func _icon(kind: String, px: int, col: Color) -> Control:
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.modulate = col
	ic.draw.connect(func(): UIStyle.draw_icon(ic, kind, Rect2(Vector2.ZERO, ic.size), Color.WHITE))
	return ic


static func _button(text: String, bg: Color, on_press: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.15)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.86, 0.87, 0.89)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", COL_MUTED)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(func(): SfxManager.play("click", -8.0, 1.0))
	b.pressed.connect(on_press)
	return b