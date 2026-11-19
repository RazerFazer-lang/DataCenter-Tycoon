extends Node
## Rauchtest für die UI: lädt die Hauptszene, öffnet HUD, Meldungen, Pause-Menü
## und Rack-/Geräte-Menü und beendet sich. Fehler erscheinen als SCRIPT ERROR im Log.


func _ready() -> void:
	print("SMOKE: start")
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		print("SMOKE: main.tscn nicht ladbar")
		get_tree().quit(1)
		return
	var main := packed.instantiate()
	add_child(main)
	await _frames(10)

	var hud := main.get_node_or_null("UI/HUD") as GameHUD
	if hud == null:
		print("SMOKE: HUD-Knoten fehlt")
	else:
		hud.visible = true
		hud.show_toast("Test-Meldung")
		await _frames(5)
		hud.show_toast("Test-Warnung", true)
		await _frames(20)
		print("SMOKE: Pause auf")
		hud.set_pause_visible(true)
		await _frames(30)
		hud.set_pause_visible(false)
		await _frames(30)
		print("SMOKE: HUD fertig")

	var rack := main.get_node_or_null("UI/RackInspectorUI") as RackInspectorUI
	if rack == null:
		print("SMOKE: RackInspectorUI-Knoten fehlt")
	else:
		if GameState.racks.is_empty():
			var rid: String = GameState._alloc_id("rack")
			GameState.racks[rid] = GameState._make_rack_data(rid, "rack", Vector3.ZERO, 0.0)
			GameState._recalculate_networks_and_metrics()
			print("SMOKE: Test-Rack angelegt: %s" % rid)
		var rack_ids: Array = GameState.racks.keys()
		print("SMOKE: racks=%d coolers=%d ups=%d carts=%d" % [rack_ids.size(), GameState.coolers.size(), GameState.ups_units.size(), GameState.carts.size()])
		if not rack_ids.is_empty():
			rack.open_rack(str(rack_ids[0]), 0)
			await _frames(5)
			for tab in ["overview", "hardware", "preview"]:
				print("SMOKE: Rack-Reiter %s" % tab)
				rack.set("_active_tab", tab)
				rack.call("_render_rack_view")
				await _frames(5)
			rack.close_inspector()
		print("SMOKE: Router")
		rack.open_device("router", "router")
		await _frames(5)
		rack.close_inspector()
		for pair in [["cooler", GameState.coolers], ["ups", GameState.ups_units], ["cart", GameState.carts]]:
			var dict: Dictionary = pair[1]
			if not dict.is_empty():
				print("SMOKE: Gerät %s" % str(pair[0]))
				rack.open_device(str(pair[0]), str(dict.keys()[0]))
				await _frames(5)
				rack.close_inspector()

	var term := _find_terminal(main)
	if term == null:
		print("SMOKE: TerminalUI-Knoten fehlt")
	else:
		term.visible = true
		for aid in TerminalUI.APP_ORDER:
			print("SMOKE: PC-App %s" % aid)
			term.call("_open_app", aid)
			await _frames(5)
		print("SMOKE: PC-Anruf")
		GameState.active_call = {"state": "ringing", "customer": "Testkunde", "rack_id": "rack_1", "message": "Test"}
		term.call("_refresh_all")
		await _frames(5)
		GameState.active_call["state"] = "active"
		term.call("_refresh_all")
		await _frames(5)
		GameState.active_call = {}
		term.call("_refresh_all")
		await _frames(5)
		term.visible = false
		print("SMOKE: PC fertig")

	print("SMOKE: Ende")
	get_tree().quit()


func _find_terminal(n: Node) -> TerminalUI:
	if n is TerminalUI:
		return n as TerminalUI
	for ch in n.get_children():
		var t := _find_terminal(ch)
		if t != null:
			return t
	return null


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame