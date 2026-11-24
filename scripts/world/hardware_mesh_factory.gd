class_name HardwareMeshFactory
extends RefCounted
## Builds authentic, realistic, non-neon 3D PC & Enterprise Server hardware assemblies:
## Motherboards (green/black PCB with capacitors, VRM heatsinks, CMOS battery, rear I/O),
## Real 3D CPUs (silver IHS + LGA socket + finned aluminum/copper heatpipe coolers),
## Real 3D GPUs (PCIe gold fingers, matte shroud, copper pipes, dual fans / Tesla AI accelerators),
## Real 3D RAM DIMM banks, M.2 NVMe SSDs, Hot-Swap PSUs, High-RPM Server Fan Walls,
## Workbench loose parts, and Handheld 3D Hardware Items!


## Ein Steckplatz ist leer, wenn die Bauteil-ID ein leerer String ist (neu gekaufte Mainboards).
## Fehlt der Schlüssel ganz, ist es ein alter Spielstand: dann wie früher ein Basisteil zeigen.
static func has_part(components: Dictionary, cat: String) -> bool:
	if not components.has(cat):
		return true
	var val: Variant = components[cat]
	if val is String:
		return not str(val).is_empty()
	return true


static func get_visual_tier(components: Dictionary, cat: String) -> int:
	if not components.has(cat):
		return 0
	var val: Variant = components[cat]
	if val is String:
		var pd := HardwareCatalog.get_part(cat, str(val))
		return clampi(int(pd.get("vtier", 0)), 0, 3)
	return clampi(int(val), 0, 3)


## Werte der Blender-Materialien "DCX_*", die MatLib nicht als feste Materialien kennt:
## [Farbe, Rauheit, Metall], dieselben Werte wie in den build_*-Funktionen.
const PART_MODEL_DCX_MATS := {
	"DCX_dark_steel": [Color(0.18, 0.19, 0.21), 0.38, 0.65],
	"DCX_etch": [Color(0.50, 0.51, 0.53), 0.55, 0.55],
	"DCX_dark_top": [Color(0.20, 0.21, 0.23), 0.40, 0.70],
	"DCX_shroud": [Color(0.16, 0.17, 0.19), 0.34, 0.62],
	"DCX_backplate": [Color(0.11, 0.12, 0.13), 0.40, 0.70],
	"DCX_blade_gpu": [Color(0.22, 0.23, 0.25), 0.58, 0.20],
	"DCX_label": [Color(0.80, 0.81, 0.83), 0.55, 0.25],
	"DCX_dark_al": [Color(0.22, 0.24, 0.27), 0.32, 0.72],
	"DCX_paper": [Color(0.86, 0.87, 0.89), 0.80, 0.0],
	"DCX_blade_fan": [Color(0.17, 0.18, 0.20), 0.60, 0.15],
	"DCX_shade": [Color(0.05, 0.05, 0.06), 0.85, 0.0],
	"DCX_handle_green": [Color(0.24, 0.56, 0.34), 0.42, 0.30],
}

## Nichtmetallische Blender-Materialien (Gummi, Schichtstoff, Griffe, LEDs):
## [Farbe, Rauheit, Leuchtkraft, Körnung]. Dieselben Farben wie MATS in build_hardware_parts.py.
const PART_MODEL_PLAIN_MATS := {
	"DCX_rubber_black": [Color(0.035, 0.035, 0.04), 0.92, 0.0, 0.0],
	"DCX_laminate": [Color(0.58, 0.58, 0.56), 0.62, 0.0, 0.07],
	"DCX_edge_band": [Color(0.20, 0.20, 0.21), 0.45, 0.0, 0.0],
	"DCX_grip_red": [Color(0.62, 0.08, 0.07), 0.35, 0.0, 0.0],
	"DCX_cord": [Color(0.06, 0.07, 0.07), 0.40, 0.0, 0.0],
	"DCX_led_green": [Color(0.25, 1.0, 0.45), 0.30, 2.2, 0.0],
	"DCX_led_blue": [Color(0.30, 0.55, 1.0), 0.30, 1.6, 0.0],
}

static var _part_mat_cache: Dictionary = {}


## Lädt ein in Blender gebautes Bauteil (tools/blender/build_hardware_parts.py) aus assets/models.
## Gibt null zurück, wenn die Datei fehlt; dann baut der Aufrufer das Teil wie bisher im Code.
## Objekte "Rotor_Z_*" / "Rotor_X_*" kommen als drehende Lüfter in out_fans.
static func _load_part_model(model_id: String, out_fans: Array = []) -> Node3D:
	if not ModelLoader.has_custom_model(model_id):
		return null
	var inst := ModelLoader.instantiate_custom_model(model_id)
	if inst == null:
		return null
	_prepare_part_model(inst, out_fans)
	return inst


static func _prepare_part_model(n: Node, out_fans: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var src := mi.mesh.surface_get_material(s)
				if src == null:
					continue
				var mat := _part_material(src.resource_name)
				if mat != null:
					mi.set_surface_override_material(s, mat)
		var node_name := str(mi.name)
		if node_name.begins_with("Rotor_"):
			if node_name.begins_with("Rotor_X"):
				mi.set_meta("spin_axis", "x")
			out_fans.append(mi)
	for c in n.get_children():
		_prepare_part_model(c, out_fans)


## "DCT_<id>" wird zu MatLib.get_mat(<id>), "DCX_*" zu gebürstetem Metall aus PART_MODEL_DCX_MATS.
static func _part_material(mat_name: String) -> Material:
	if _part_mat_cache.has(mat_name):
		return _part_mat_cache[mat_name] as Material
	var mat: Material = null
	if mat_name.begins_with("DCT_"):
		mat = MatLib.get_mat(mat_name.substr(4))
	elif PART_MODEL_DCX_MATS.has(mat_name):
		var p: Array = PART_MODEL_DCX_MATS[mat_name]
		mat = MatLib.make_brushed_metal(p[0] as Color, float(p[1]), float(p[2]))
	elif PART_MODEL_PLAIN_MATS.has(mat_name):
		mat = _make_plain_material(PART_MODEL_PLAIN_MATS[mat_name] as Array)
	_part_mat_cache[mat_name] = mat
	return mat


## Kunststoff, Gummi und Schichtstoff ohne Bürststruktur; LEDs leuchten, Körnung > 0 gibt eine feine Musterung.
static func _make_plain_material(p: Array) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var col := p[0] as Color
	m.albedo_color = col
	m.roughness = float(p[1])
	m.metallic = 0.0
	var glow := float(p[2])
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow
	var grain := float(p[3])
	if grain > 0.0:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.08
		noise.fractal_octaves = 3
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0 - grain, 1.0 - grain, 1.0 - grain))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.noise = noise
		tex.color_ramp = ramp
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(4.0, 4.0, 4.0)
	return m


## Werkbank mit ESD-Matte für die 3D-Vorschau; null, wenn das Modell fehlt.
static func build_preview_workbench() -> Node3D:
	return _load_part_model("prop_workbench")


static func build_open_server_chassis(item_type: String, components: Dictionary, out_fans: Array = [], broken_cat: String = "") -> Node3D:
	# Mainboards nutzen das passende 1U/2U/4U-Gehäuse.
	item_type = GameState.get_chassis_visual(item_type)
	var root := Node3D.new()
	var steel := MatLib.get_mat("galvanized_steel")
	var dark_steel := MatLib.make_brushed_metal(Color(0.18, 0.19, 0.21), 0.38, 0.65)
	var plastic := MatLib.get_mat("plastic_black")
	var pcb := MatLib.get_mat("pcb_black") if item_type == "gpu_server" else MatLib.get_mat("pcb_green")
	var gold := MatLib.get_mat("gold_contacts")
	var copper := MatLib.get_mat("copper_metal")
	var ic := MatLib.get_mat("ic_chip")
	var alu_fin := MatLib.get_mat("heatsink_aluminum")

	# 1. Blechwanne, Rack-Ohren und Laufwerkskäfig aus Blender (tools/blender/build_hardware_parts.py).
	var shell_id := "part_chassis_switch" if item_type == "net_switch" else ("part_chassis_8bay" if item_type == "storage_server" else "part_chassis_4bay")
	var shell := _load_part_model(shell_id)
	if shell != null:
		root.add_child(shell)
	else:
		_box(root, Vector3(0.0, 0.008, 0.0), Vector3(0.74, 0.016, 0.72), steel)
		# Side & rear sheet-metal walls
		_box(root, Vector3(-0.365, 0.072, 0.0), Vector3(0.014, 0.128, 0.72), steel)
		_box(root, Vector3(0.365, 0.072, 0.0), Vector3(0.014, 0.128, 0.72), steel)
		_box(root, Vector3(0.0, 0.072, -0.355), Vector3(0.74, 0.128, 0.014), steel)
		# Front rack-mount ears with mounting screw holes
		for sx in [-0.39, 0.39]:
			_box(root, Vector3(float(sx), 0.072, 0.352), Vector3(0.042, 0.128, 0.016), dark_steel)
			_box(root, Vector3(float(sx) * 1.03, 0.072, 0.376), Vector3(0.018, 0.09, 0.036), steel)
		# Front Drive Bay Cage / Faceplate
		_box(root, Vector3(0.0, 0.072, 0.305), Vector3(0.71, 0.124, 0.11), dark_steel)
	if item_type == "net_switch":
		# 24-Port Managed Ethernet Switch PCB & Front RJ45 Shielded Cages
		_box(root, Vector3(0.0, 0.022, -0.04), Vector3(0.66, 0.012, 0.50), MatLib.get_mat("pcb_green"))
		for c_i in range(8):
			var px := -0.28 + float(c_i) * 0.076
			_box(root, Vector3(px, 0.090, 0.364), Vector3(0.046, 0.032, 0.025), steel)
			_box(root, Vector3(px, 0.048, 0.364), Vector3(0.046, 0.032, 0.025), steel)
		# Main switching ASIC + aluminum finned heatsink inside
		_box(root, Vector3(0.0, 0.052, -0.02), Vector3(0.14, 0.048, 0.14), alu_fin)
		_box(root, Vector3(-0.22, 0.068, -0.18), Vector3(0.22, 0.088, 0.24), steel)
		return root

	# Realistic front hot-swap drive caddies (4 or 8 depending on model)
	var bay_count := 8 if item_type == "storage_server" else 4
	var bay_w := 0.068 if bay_count == 8 else 0.145
	var bay_step := 0.078 if bay_count == 8 else 0.165
	var start_x := -0.275 if bay_count == 8 else -0.245
	var stor_lvl := get_visual_tier(components, "storage")
	var caddy_prefix := "part_caddy_sff" if bay_count == 8 else "part_caddy_lff"
	for b in range(bay_count):
		var bx := start_x + float(b) * bay_step
		var populated := (b < 2 + stor_lvl * 2) or (item_type == "storage_server")
		if shell != null:
			# Blender-Schlitten passen nur in den Blender-Käfig; ohne ihn bleibt der Code-Aufbau.
			var caddy := _load_part_model(caddy_prefix if populated else caddy_prefix + "_blank")
			if caddy != null:
				caddy.position = Vector3(bx, 0.072, 0.362)
				root.add_child(caddy)
				continue
		_box(root, Vector3(bx, 0.072, 0.362), Vector3(bay_w, 0.092, 0.018), plastic)
		if populated:
			# Silver metal drive pull latch + small amber/green release button
			_box(root, Vector3(bx, 0.072, 0.373), Vector3(bay_w * 0.78, 0.022, 0.012), steel)
			_box(root, Vector3(bx + bay_w * 0.34, 0.072, 0.374), Vector3(0.016, 0.028, 0.014), copper)

	# 2. Realistic Server Motherboard PCB (with standoffs, Rear I/O ports, CMOS battery, Capacitors, Chipset)
	var mb := Node3D.new()
	mb.position = Vector3(-0.04, 0.022, -0.07)
	# Markierung für den Hover in der 3D-Vorschau. part_base: Bauteile auf der Platine haben Vorrang.
	mb.set_meta("part_cat", "mainboard")
	mb.set_meta("part_base", true)
	root.add_child(mb)
	var mb_id := "part_mainboard_ai" if item_type == "gpu_server" else "part_mainboard"
	if broken_cat == "mainboard":
		mb_id += "_broken"
	var mb_model := _load_part_model(mb_id)
	if mb_model != null:
		mb.add_child(mb_model)
	else:
		_build_mainboard_fallback(mb, pcb, steel, alu_fin, dark_steel, plastic, gold)

	# 3. REAL 3D CPU + LGA Socket + Upgraded Cooler (at center-left of motherboard)
	# Leere Steckplätze bleiben leer: nur eingebaute Teile werden gezeigt.
	if has_part(components, "cpu") or broken_cat == "cpu":
		var cpu_lvl := get_visual_tier(components, "cpu")
		var cpu_node := build_cpu_assembly(cpu_lvl, broken_cat == "cpu")
		# Der Sockel beginnt bei y = 0 und sitzt damit direkt auf der Platine (Oberseite 0.006).
		cpu_node.position = Vector3(-0.07, 0.006, -0.01)
		cpu_node.set_meta("part_cat", "cpu")
		mb.add_child(cpu_node)

	# 4. REAL 3D RAM DIMM Bank (right beside CPU!)
	if has_part(components, "ram") or broken_cat == "ram":
		var ram_lvl := get_visual_tier(components, "ram")
		var ram_node := build_ram_bank(ram_lvl, broken_cat == "ram")
		ram_node.position = Vector3(0.09, 0.008, -0.03)
		ram_node.set_meta("part_cat", "ram")
		mb.add_child(ram_node)

	# 5. REAL 3D GPU (Grafikkarte) in PCIe x16 Slot (left side of motherboard)
	if has_part(components, "gpu") or item_type == "gpu_server" or broken_cat == "gpu":
		var gpu_lvl := get_visual_tier(components, "gpu")
		if item_type == "gpu_server" and gpu_lvl == 0:
			gpu_lvl = 1 # GPU-AI server always has at least a visible GPU installed!
		var gpu_node := build_gpu_card(gpu_lvl, out_fans, broken_cat == "gpu")
		gpu_node.position = Vector3(-0.21, 0.008, 0.05)
		gpu_node.set_meta("part_cat", "gpu")
		mb.add_child(gpu_node)

	# 6. REAL 3D M.2 NVMe SSDs mounted directly on the Motherboard
	if has_part(components, "storage") or broken_cat == "storage":
		var nvme_node := build_storage_module(stor_lvl, broken_cat == "storage")
		nvme_node.position = Vector3(0.04, 0.008, 0.14)
		nvme_node.set_meta("part_cat", "storage")
		mb.add_child(nvme_node)

	# 7. REAL 3D Server Cooling Fan Wall (between drives & motherboard!)
	if has_part(components, "cooling") or broken_cat == "cooling":
		var cool_lvl := get_visual_tier(components, "cooling")
		var fan_wall := build_cooling_wall(cool_lvl, out_fans, broken_cat == "cooling")
		fan_wall.position = Vector3(-0.02, 0.018, 0.21)
		fan_wall.set_meta("part_cat", "cooling")
		root.add_child(fan_wall)

	# 8. REAL 3D Server PSU Unit (rear-right bay inside chassis!)
	if has_part(components, "psu") or broken_cat == "psu":
		var psu_lvl := get_visual_tier(components, "psu")
		var psu_node := build_psu_unit(psu_lvl, broken_cat == "psu")
		psu_node.position = Vector3(0.285, 0.018, -0.17)
		psu_node.set_meta("part_cat", "psu")
		root.add_child(psu_node)

	return root


## Mainboard aus Codeteilen, falls part_mainboard.glb fehlt.
static func _build_mainboard_fallback(mb: Node3D, pcb: StandardMaterial3D, steel: StandardMaterial3D, alu_fin: StandardMaterial3D, dark_steel: StandardMaterial3D, plastic: StandardMaterial3D, gold: StandardMaterial3D) -> void:
	# Gleiche Platinengröße wie part_mainboard.glb: rechts bleibt Platz für das Netzteil.
	_box(mb, Vector3(-0.02, 0.0, 0.0), Vector3(0.54, 0.012, 0.48), pcb)
	# Rear I/O metallic port blocks (2x Gigabit RJ45, 4x USB, VGA)
	for io_i in range(4):
		_box(mb, Vector3(-0.22 + float(io_i) * 0.065, 0.028, -0.22), Vector3(0.044, 0.042, 0.048), steel)
	# VRM MOSFET bank & aluminum VRM heatsink along rear of CPU
	_box(mb, Vector3(-0.07, 0.026, -0.14), Vector3(0.16, 0.036, 0.032), alu_fin)
	# Silver CMOS CR2032 Coin Battery
	_cyl(mb, Vector3(0.21, 0.012, -0.16), 0.018, 0.008, steel)
	# Southbridge / PCH Chipset with black aluminum heatsink
	_box(mb, Vector3(0.18, 0.022, 0.04), Vector3(0.068, 0.028, 0.068), dark_steel)
	# Solid electrolytic capacitors row (realistic cylindrical aluminum cans)
	for cap_i in range(6):
		_cyl(mb, Vector3(-0.18 + float(cap_i) * 0.024, 0.018, -0.09), 0.007, 0.022, steel)
	# 24-pin ATX white/black motherboard power header
	_box(mb, Vector3(0.25, 0.018, -0.06), Vector3(0.024, 0.022, 0.095), plastic)
	_box(mb, Vector3(0.25, 0.028, -0.06), Vector3(0.016, 0.006, 0.088), gold)
	# SATA ports block
	for s_i in range(4):
		_box(mb, Vector3(0.24, 0.016, 0.12 + float(s_i) * 0.024), Vector3(0.036, 0.016, 0.016), plastic)


static func build_cpu_assembly(tier: int, broken: bool = false) -> Node3D:
	var model := _load_part_model("part_cpu_broken" if broken else ("part_cpu_t%d" % clampi(tier, 0, 3)))
	if model != null:
		return model
	var root := Node3D.new()
	var steel := MatLib.get_mat("galvanized_steel")
	var ihs := MatLib.get_mat("cpu_ihs")
	var gold := MatLib.get_mat("gold_contacts")
	var pcb := MatLib.get_mat("pcb_green")
	var alu_fin := MatLib.get_mat("heatsink_aluminum")
	var cu_fin := MatLib.get_mat("heatsink_copper")
	var copper := MatLib.get_mat("copper_metal")
	var plastic := MatLib.get_mat("plastic_black")
	var ic := MatLib.get_mat("ic_chip")
	var etch := MatLib.make_brushed_metal(Color(0.50, 0.51, 0.53), 0.55, 0.55)

	# LGA-Sockel: Kunststoffrahmen, goldenes Kontaktfeld, Trägerplatine und Heatspreader
	_box(root, Vector3(0.0, 0.006, 0.0), Vector3(0.115, 0.012, 0.115), plastic)
	_box(root, Vector3(0.0, 0.012, 0.0), Vector3(0.095, 0.005, 0.095), gold)
	_box(root, Vector3(0.0, 0.016, 0.0), Vector3(0.088, 0.006, 0.088), pcb)
	_box(root, Vector3(0.0, 0.022, 0.0), Vector3(0.072, 0.009, 0.072), ihs)
	# SMD-Kondensatoren auf der Trägerplatine vor und hinter dem Heatspreader
	var smd: Array = []
	for i in range(6):
		var o := -0.025 + float(i) * 0.010
		smd.append([Vector3(o, 0.0, -0.039), Vector3(0.004, 0.002, 0.003)])
		smd.append([Vector3(o, 0.0, 0.039), Vector3(0.004, 0.002, 0.003)])
	var smd_mi := merged_boxes(root, "cpu_smd", smd, ic)
	smd_mi.position.y = 0.020
	# Haltebügel mit Spannhebel, Hebelhaken und Scharnierachse
	_box(root, Vector3(0.0, 0.020, -0.048), Vector3(0.096, 0.008, 0.012), steel)
	_box(root, Vector3(0.0, 0.020, 0.048), Vector3(0.096, 0.008, 0.012), steel)
	_box(root, Vector3(0.062, 0.016, 0.0), Vector3(0.008, 0.008, 0.115), steel)
	_box(root, Vector3(0.068, 0.016, 0.058), Vector3(0.012, 0.006, 0.006), steel)
	_cyl_z(root, Vector3(-0.050, 0.016, 0.0), 0.004, 0.100, steel)

	if tier == 0:
		# Kleiner Passivkühler hinten. Der beschriftete Heatspreader bleibt vorne sichtbar.
		_box(root, Vector3(0.0, 0.027, 0.016), Vector3(0.046, 0.001, 0.018), etch)
		_box(root, Vector3(0.0, 0.0285, -0.022), Vector3(0.076, 0.004, 0.032), alu_fin)
		fin_stack(root, Vector3(0.0, 0.0375, -0.022), Vector3(0.076, 0.014, 0.032), 10, 0, alu_fin)
	elif tier == 1:
		# Aluminium-Kühlkörper mit 18 Rippen und vier gefederten Schrauben
		_box(root, Vector3(0.0, 0.030, 0.0), Vector3(0.105, 0.006, 0.105), alu_fin)
		fin_stack(root, Vector3(0.0, 0.051, 0.0), Vector3(0.105, 0.036, 0.105), 18, 0, alu_fin)
		for sx in [-0.048, 0.048]:
			for sz in [-0.048, 0.048]:
				_cyl(root, Vector3(float(sx), 0.071, float(sz)), 0.005, 0.006, steel)
	elif tier == 2:
		# Kupferboden, vier U-Heatpipes und ein Turm aus waagerechten Lamellen
		_box(root, Vector3(0.0, 0.032, 0.0), Vector3(0.096, 0.014, 0.096), copper)
		for hx in [-0.036, -0.012, 0.012, 0.036]:
			for hz in [-0.022, 0.022]:
				_cyl(root, Vector3(float(hx), 0.067, float(hz)), 0.004, 0.056, copper)
				_cyl(root, Vector3(float(hx), 0.0995, float(hz)), 0.0045, 0.004, copper)
		fin_stack(root, Vector3(0.0, 0.070, 0.0), Vector3(0.112, 0.050, 0.110), 14, 1, alu_fin)
		_box(root, Vector3(0.0, 0.097, 0.0), Vector3(0.112, 0.004, 0.110), MatLib.make_brushed_metal(Color(0.20, 0.21, 0.23), 0.40, 0.70))
	else:
		# Geschälter Kupferkühler mit 24 Rippen, Heatpipes oben und Montagebrücke
		_box(root, Vector3(0.0, 0.032, 0.0), Vector3(0.125, 0.014, 0.125), copper)
		fin_stack(root, Vector3(0.0, 0.066, 0.0), Vector3(0.122, 0.062, 0.120), 24, 0, cu_fin)
		for hx in [-0.044, -0.022, 0.0, 0.022, 0.044]:
			_cyl_z(root, Vector3(float(hx), 0.099, 0.0), 0.005, 0.110, copper)
		_box(root, Vector3(0.0, 0.100, 0.0), Vector3(0.126, 0.008, 0.046), steel)
		for sx in [-0.058, 0.058]:
			_cyl(root, Vector3(float(sx), 0.106, 0.0), 0.006, 0.006, steel)

	return root


static func build_gpu_card(tier: int, out_fans: Array = [], broken: bool = false) -> Node3D:
	var model := _load_part_model("part_gpu_broken" if broken else ("part_gpu_t%d" % clampi(tier, 0, 3)), out_fans)
	if model != null:
		return model
	var root := Node3D.new()
	var plastic := MatLib.get_mat("plastic_black")
	var steel := MatLib.get_mat("galvanized_steel")
	var shroud := MatLib.make_brushed_metal(Color(0.16, 0.17, 0.19), 0.34, 0.62)
	var backplate := MatLib.make_brushed_metal(Color(0.11, 0.12, 0.13), 0.40, 0.70)
	var blade_mat := MatLib.make_brushed_metal(Color(0.22, 0.23, 0.25), 0.58, 0.20)
	var label_mat := MatLib.make_brushed_metal(Color(0.80, 0.81, 0.83), 0.55, 0.25)
	var pcb_b := MatLib.get_mat("pcb_black")
	var gold := MatLib.get_mat("gold_contacts")
	var copper := MatLib.get_mat("copper_metal")
	var alu_fin := MatLib.get_mat("heatsink_aluminum")
	var cu_fin := MatLib.get_mat("heatsink_copper")
	var ic := MatLib.get_mat("ic_chip")

	# PCIe-x16-Steckplatz auf dem Mainboard (immer vorhanden)
	_box(root, Vector3(0.0, 0.010, 0.0), Vector3(0.020, 0.016, 0.165), plastic)
	_box(root, Vector3(0.0, 0.016, 0.0), Vector3(0.008, 0.006, 0.155), gold)
	_box(root, Vector3(0.0, 0.012, 0.092), Vector3(0.024, 0.016, 0.018), steel)

	if tier <= 0:
		return root

	var cards := 2 if tier >= 3 else 1
	for c_idx in range(cards):
		var cx := float(c_idx) * 0.056
		var card := Node3D.new()
		card.position = Vector3(cx, 0.022, 0.0)
		root.add_child(card)

		var card_len := 0.21 if tier == 1 else (0.28 if tier == 2 else 0.31)
		var card_h := 0.072 if tier == 1 else 0.088
		var half_len := card_len * 0.5
		var mid_h := card_h * 0.5

		# Leiterplatte, Kontaktleiste mit Codierkerbe und Rückplatte
		_box(card, Vector3(0.0, mid_h, 0.0), Vector3(0.008, card_h, card_len), pcb_b)
		_box(card, Vector3(0.0, 0.002, -0.034), Vector3(0.009, 0.012, 0.082), gold)
		_box(card, Vector3(0.0, 0.002, 0.040), Vector3(0.009, 0.012, 0.030), gold)
		_box(card, Vector3(-0.0055, mid_h, 0.004), Vector3(0.003, card_h - 0.004, card_len - 0.012), backplate)

		# Slotblech mit Display-Anschlüssen und Lüftungsschlitzen
		var bracket_z := -half_len - 0.004
		_box(card, Vector3(0.012, mid_h, bracket_z), Vector3(0.036, card_h + 0.012, 0.008), steel)
		var io: Array = []
		for p in range(3):
			io.append([Vector3(0.002, 0.014 + float(p) * 0.014, 0.0), Vector3(0.012, 0.007, 0.003)])
		for v in range(4):
			io.append([Vector3(0.022, 0.012 + float(v) * 0.013, 0.0), Vector3(0.010, 0.004, 0.003)])
		var io_mi := merged_boxes(card, "gpu_io", io, plastic)
		io_mi.position = Vector3(0.0, 0.0, bracket_z - 0.004)

		if tier >= 3:
			# Passiver KI-Beschleuniger: geschlossene Haube, Kupferlamellen am Lufteinlass
			_box(card, Vector3(0.016, mid_h, -0.024), Vector3(0.026, card_h - 0.006, card_len - 0.056), shroud)
			fin_stack(card, Vector3(0.016, mid_h, half_len - 0.028), Vector3(0.026, card_h - 0.012, 0.048), 10, 1, cu_fin)
			_box(card, Vector3(0.016, card_h - 0.004, half_len - 0.028), Vector3(0.026, 0.004, 0.048), shroud)
			_box(card, Vector3(0.016, 0.004, half_len - 0.028), Vector3(0.026, 0.004, 0.048), shroud)
			_box(card, Vector3(0.016, card_h + 0.002, 0.0), Vector3(0.026, 0.006, card_len * 0.72), copper)
			_box(card, Vector3(0.0295, mid_h, -0.05), Vector3(0.001, 0.018, 0.08), label_mat)
			_box(card, Vector3(0.010, card_h + 0.008, -half_len + 0.025), Vector3(0.018, 0.012, 0.024), plastic)
		else:
			# Aktive Karte: Lamellen zwischen Platine und Haube, Haube mit runden Lüfteröffnungen
			var face_x := 0.027
			var fan_r := 0.027 if tier == 1 else 0.034
			var fan_zs: Array[float] = []
			if tier == 1:
				fan_zs.append(0.0)
			else:
				fan_zs.append(-0.068)
				fan_zs.append(0.068)

			fin_stack(card, Vector3(0.015, mid_h, 0.0), Vector3(0.018, card_h - 0.006, card_len - 0.020), 16 if tier == 1 else 22, 2, alu_fin)

			_box(card, Vector3(face_x, card_h - 0.004, 0.0), Vector3(0.006, 0.008, card_len - 0.010), shroud)
			_box(card, Vector3(face_x, 0.004, 0.0), Vector3(0.006, 0.008, card_len - 0.010), shroud)
			var inner_h := card_h - 0.016
			var cut_half := fan_r + 0.002
			var seg_start := -half_len + 0.005
			for fz in fan_zs:
				var seg_end := fz - cut_half
				if seg_end > seg_start:
					_box(card, Vector3(face_x, mid_h, (seg_start + seg_end) * 0.5), Vector3(0.006, inner_h, seg_end - seg_start), shroud)
				seg_start = fz + cut_half
			var last_end := half_len - 0.005
			if last_end > seg_start:
				_box(card, Vector3(face_x, mid_h, (seg_start + last_end) * 0.5), Vector3(0.006, inner_h, last_end - seg_start), shroud)

			for fz in fan_zs:
				_cyl_x(card, Vector3(face_x - 0.001, mid_h, fz), fan_r + 0.002, 0.004, plastic)
				var rotor := fan_rotor(card, Vector3(face_x + 0.005, mid_h, fz), fan_r, 9, true, blade_mat, steel)
				out_fans.append(rotor)

			# Heatpipes an der Oberkante, Typenschild und 8-Pin-Stromanschlüsse
			for hp in range(2 if tier == 1 else 3):
				_cyl_z(card, Vector3(0.010 + float(hp) * 0.006, card_h + 0.001, -card_len * 0.10), 0.0032, card_len * 0.50, copper)
			_box(card, Vector3(face_x + 0.0035, mid_h, half_len - 0.018), Vector3(0.001, 0.010, 0.020), label_mat)
			var plug_count := 1 if tier == 1 else 2
			for pc in range(plug_count):
				var pz := half_len * 0.60 + float(pc) * 0.026
				_box(card, Vector3(0.012, card_h + 0.006, pz), Vector3(0.016, 0.012, 0.022), plastic)
				_box(card, Vector3(0.012, card_h + 0.0125, pz), Vector3(0.010, 0.001, 0.016), ic)

	# NVLink-Brücke zwischen den beiden KI-Karten
	if tier >= 3:
		_box(root, Vector3(0.038, 0.114, 0.06), Vector3(0.072, 0.012, 0.058), steel)
		_box(root, Vector3(0.038, 0.121, 0.06), Vector3(0.050, 0.002, 0.036), label_mat)

	return root


static func build_ram_bank(tier: int, broken: bool = false) -> Node3D:
	var model := _load_part_model("part_ram_broken" if broken else ("part_ram_t%d" % clampi(tier, 0, 3)))
	if model != null:
		return model
	var root := Node3D.new()
	var plastic := MatLib.get_mat("plastic_black")
	var pcb := MatLib.get_mat("pcb_green")
	var ic := MatLib.get_mat("ic_chip")
	var gold := MatLib.get_mat("gold_contacts")
	var steel := MatLib.get_mat("galvanized_steel")
	var dark_al := MatLib.make_brushed_metal(Color(0.22, 0.24, 0.27), 0.32, 0.72)
	var paper := MatLib.make_brushed_metal(Color(0.86, 0.87, 0.89), 0.80, 0.0)

	# Halteklammern an beiden Enden, leicht nach außen geklappt
	var clip_parts: Array = [
		[Vector3(0.0, 0.004, -0.078), Vector3(0.010, 0.020, 0.008), Basis(Vector3.RIGHT, deg_to_rad(-12.0))],
		[Vector3(0.0, 0.004, 0.078), Vector3(0.010, 0.020, 0.008), Basis(Vector3.RIGHT, deg_to_rad(12.0))],
	]
	var gold_parts: Array = [
		[Vector3(0.0, -0.0195, -0.026), Vector3(0.0018, 0.005, 0.080)],
		[Vector3(0.0, -0.0195, 0.042), Vector3(0.0018, 0.005, 0.048)],
	]
	var chip_parts: Array = []
	for c in range(8):
		var cz := -0.056 + float(c) * 0.016
		chip_parts.append([Vector3(0.0014, 0.004, cz), Vector3(0.0012, 0.012, 0.011)])
		chip_parts.append([Vector3(-0.0014, 0.004, cz), Vector3(0.0012, 0.012, 0.011)])
	var spreader_h := 0.036 if tier <= 1 else 0.040
	var spreader_parts: Array = [
		[Vector3(0.0018, 0.002, 0.0), Vector3(0.0012, spreader_h, 0.134)],
		[Vector3(-0.0018, 0.002, 0.0), Vector3(0.0012, spreader_h, 0.134)],
	]
	if tier >= 2:
		# Kühlrippen auf der Oberkante des Heatspreaders
		for r in range(12):
			spreader_parts.append([Vector3(0.0, 0.024, -0.060 + float(r) * 0.011), Vector3(0.0048, 0.006 if tier == 2 else 0.010, 0.005)])

	var populated := clampi(2 + tier * 2, 2, 8)
	for i in range(8):
		var rx := -0.063 + float(i) * 0.018
		_box(root, Vector3(rx, 0.008, 0.0), Vector3(0.009, 0.012, 0.148), plastic)
		var clips := merged_boxes(root, "dimm_clips", clip_parts, steel)
		clips.position = Vector3(rx, 0.008, 0.0)

		if i >= populated:
			continue
		var stick := Node3D.new()
		stick.position = Vector3(rx, 0.034, 0.0)
		root.add_child(stick)
		_box(stick, Vector3.ZERO, Vector3(0.0016, 0.044, 0.138), pcb)
		merged_boxes(stick, "dimm_gold", gold_parts, gold)
		if tier == 0:
			# Blankes Modul: acht Speicherchips pro Seite und Typenaufkleber
			merged_boxes(stick, "dimm_chips", chip_parts, ic)
			_box(stick, Vector3(0.0015, 0.015, -0.03), Vector3(0.0004, 0.008, 0.040), paper)
		else:
			merged_boxes(stick, "dimm_spreader_%d" % tier, spreader_parts, dark_al if tier == 1 else steel)
			_box(stick, Vector3(0.0025, 0.0, -0.02), Vector3(0.0003, 0.014, 0.060), paper)
			if tier >= 3:
				_box(stick, Vector3(0.0, 0.0225, 0.0), Vector3(0.0052, 0.003, 0.134), dark_al)

	return root


static func build_storage_module(tier: int, broken: bool = false) -> Node3D:
	var model := _load_part_model("part_storage_broken" if broken else ("part_storage_t%d" % clampi(tier, 0, 3)))
	if model != null:
		return model
	var root := Node3D.new()
	var pcb_b := MatLib.get_mat("pcb_black")
	var ic := MatLib.get_mat("ic_chip")
	var gold := MatLib.get_mat("gold_contacts")
	var steel := MatLib.get_mat("galvanized_steel")
	var alu_fin := MatLib.get_mat("heatsink_aluminum")
	var cu_fin := MatLib.get_mat("heatsink_copper")
	var plastic := MatLib.get_mat("plastic_black")
	var paper := MatLib.make_brushed_metal(Color(0.86, 0.87, 0.89), 0.80, 0.0)

	var drive_count := clampi(1 + tier, 1, 3)
	for i in range(drive_count):
		var mz := -0.032 + float(i) * 0.034
		# M.2-Steckplatz, Platine mit Kerbe in der Kontaktleiste, Abstandsbolzen mit Schraube
		_box(root, Vector3(-0.056, 0.009, mz), Vector3(0.014, 0.012, 0.026), plastic)
		_box(root, Vector3(0.002, 0.011, mz), Vector3(0.101, 0.0016, 0.022), pcb_b)
		_box(root, Vector3(-0.0505, 0.011, mz - 0.004), Vector3(0.008, 0.0018, 0.012), gold)
		_box(root, Vector3(-0.0505, 0.011, mz + 0.0075), Vector3(0.008, 0.0018, 0.005), gold)
		_cyl(root, Vector3(0.050, 0.008, mz), 0.004, 0.006, steel)
		_cyl(root, Vector3(0.050, 0.0125, mz), 0.0035, 0.002, steel)
		if tier >= 2:
			# Kühlkörper mit Längsrippen (Kupfer ab Stufe 3)
			var sink_mat := cu_fin if tier >= 3 else alu_fin
			var fin_h := 0.008 if tier >= 3 else 0.006
			_box(root, Vector3(0.004, 0.0135, mz), Vector3(0.088, 0.0034, 0.023), sink_mat)
			fin_stack(root, Vector3(0.004, 0.0152 + fin_h * 0.5, mz), Vector3(0.088, fin_h, 0.023), 5, 2, sink_mat)
		else:
			# Controller mit Metalldeckel, DRAM-Cache, zwei NAND-Bausteine und Aufkleber
			_box(root, Vector3(-0.030, 0.0125, mz), Vector3(0.014, 0.0016, 0.014), steel)
			_box(root, Vector3(-0.014, 0.0125, mz), Vector3(0.008, 0.0014, 0.010), ic)
			_box(root, Vector3(0.008, 0.0128, mz), Vector3(0.022, 0.002, 0.017), ic)
			_box(root, Vector3(0.034, 0.0128, mz), Vector3(0.020, 0.002, 0.017), ic)
			_box(root, Vector3(0.014, 0.0142, mz), Vector3(0.050, 0.0004, 0.016), paper)

	return root


static func build_cooling_wall(tier: int, out_fans: Array = [], broken: bool = false) -> Node3D:
	var model := _load_part_model("part_cooling_broken" if broken else ("part_cooling_t%d" % clampi(tier, 0, 3)), out_fans)
	if model != null:
		return model
	var root := Node3D.new()
	var plastic := MatLib.get_mat("plastic_black")
	var steel := MatLib.get_mat("galvanized_steel")
	var copper := MatLib.get_mat("copper_metal")
	var cu_fin := MatLib.get_mat("heatsink_copper")
	var blade_mat := MatLib.make_brushed_metal(Color(0.17, 0.18, 0.20), 0.60, 0.15)
	var shade := MatLib.make_brushed_metal(Color(0.05, 0.05, 0.06), 0.85, 0.0)

	# Lüftergehäuse: quadratischer Rahmen mit Motorstreben auf der Rückseite
	var frame_parts: Array = [
		[Vector3(0.0, 0.042, 0.0), Vector3(0.095, 0.008, 0.042)],
		[Vector3(0.0, -0.042, 0.0), Vector3(0.095, 0.008, 0.042)],
		[Vector3(-0.0435, 0.0, 0.0), Vector3(0.008, 0.076, 0.042)],
		[Vector3(0.0435, 0.0, 0.0), Vector3(0.008, 0.076, 0.042)],
		[Vector3(0.0, 0.0, -0.018), Vector3(0.110, 0.004, 0.004), Basis(Vector3.BACK, deg_to_rad(45.0))],
		[Vector3(0.0, 0.0, -0.018), Vector3(0.110, 0.004, 0.004), Basis(Vector3.BACK, deg_to_rad(-45.0))],
	]
	# Fingerschutz vorne, Eckschrauben und Griff zum Tauschen im laufenden Betrieb
	var guard_parts: Array = [
		[Vector3(0.0, -0.020, 0.0215), Vector3(0.080, 0.0016, 0.0016)],
		[Vector3(0.0, 0.0, 0.0215), Vector3(0.080, 0.0016, 0.0016)],
		[Vector3(0.0, 0.020, 0.0215), Vector3(0.080, 0.0016, 0.0016)],
		[Vector3(0.0, 0.0, 0.0215), Vector3(0.0016, 0.078, 0.0016)],
		[Vector3(0.0, 0.049, 0.012), Vector3(0.030, 0.004, 0.008)],
	]
	for sx in [-0.040, 0.040]:
		for sy in [-0.039, 0.039]:
			guard_parts.append([Vector3(float(sx), float(sy), 0.0215), Vector3(0.005, 0.005, 0.002)])

	var fan_count := clampi(3 + tier, 3, 5)
	var spacing := 0.115
	var start_x := -float(fan_count - 1) * spacing * 0.5
	for i in range(fan_count):
		var fan := Node3D.new()
		fan.position = Vector3(start_x + float(i) * spacing, 0.048, 0.0)
		root.add_child(fan)
		merged_boxes(fan, "fan80_frame", frame_parts, plastic)
		merged_boxes(fan, "fan80_guard", guard_parts, steel)
		_cyl_z(fan, Vector3(0.0, 0.0, -0.019), 0.040, 0.002, shade)
		_cyl_z(fan, Vector3(0.0, 0.0, -0.010), 0.013, 0.014, plastic)
		var rotor := fan_rotor(fan, Vector3(0.0, 0.0, 0.006), 0.037, 7, false, blade_mat, steel)
		out_fans.append(rotor)

	if tier >= 3:
		# Wasserkühlung: Kupferradiator mit 70 Lamellen, Endkammern und zwei Schläuchen
		fin_stack(root, Vector3(0.0, 0.048, -0.034), Vector3(0.56, 0.080, 0.024), 70, 0, cu_fin)
		_box(root, Vector3(0.0, 0.090, -0.034), Vector3(0.56, 0.004, 0.026), copper)
		_box(root, Vector3(0.0, 0.006, -0.034), Vector3(0.56, 0.004, 0.026), copper)
		_box(root, Vector3(-0.288, 0.048, -0.034), Vector3(0.016, 0.092, 0.030), plastic)
		_box(root, Vector3(0.288, 0.048, -0.034), Vector3(0.016, 0.092, 0.030), plastic)
		_cyl_z(root, Vector3(-0.08, 0.096, -0.11), 0.009, 0.18, plastic)
		_cyl_z(root, Vector3(-0.05, 0.096, -0.11), 0.009, 0.18, plastic)
		_cyl(root, Vector3(-0.08, 0.096, -0.03), 0.011, 0.014, copper)
		_cyl(root, Vector3(-0.05, 0.096, -0.03), 0.011, 0.014, copper)

	return root


static func build_psu_unit(tier: int, broken: bool = false) -> Node3D:
	var model := _load_part_model("part_psu_broken" if broken else ("part_psu_t%d" % clampi(tier, 0, 3)))
	if model != null:
		return model
	var root := Node3D.new()
	var plastic := MatLib.get_mat("plastic_black")
	var copper := MatLib.get_mat("copper_metal")

	if tier >= 2:
		# Zwei redundante Hot-Swap-Netzteile, davor die Verteilerplatine
		for u in range(2):
			_psu_module(root, Vector3(-0.034 + float(u) * 0.068, 0.0, 0.0), Vector3(0.060, 0.094, 0.32), true)
		_box(root, Vector3(0.0, 0.048, 0.166), Vector3(0.130, 0.080, 0.010), MatLib.get_mat("pcb_green"))
	else:
		_psu_module(root, Vector3.ZERO, Vector3(0.125, 0.092, 0.30), false)

	# Kabelstrang zum 24-Pin-Anschluss des Mainboards
	_cyl_z(root, Vector3(-0.04, 0.032, 0.165), 0.010, 0.08, plastic)
	_cyl_z(root, Vector3(-0.02, 0.038, 0.165), 0.008, 0.08, copper)
	_box(root, Vector3(-0.03, 0.035, 0.208), Vector3(0.034, 0.016, 0.012), plastic)

	return root


## Ein Netzteilgehäuse: Lochblech oben, Aufkleber an der Seite, hinten Lüfter mit Gitter,
## Kaltgerätebuchse und je nach Bauart Hot-Swap-Griff oder Netzschalter.
static func _psu_module(parent: Node3D, offset: Vector3, size: Vector3, hot_swap: bool) -> void:
	var steel := MatLib.get_mat("galvanized_steel")
	var perf := MatLib.get_mat("perforated_mesh")
	var plastic := MatLib.get_mat("plastic_black")
	var handle_mat := MatLib.make_brushed_metal(Color(0.24, 0.56, 0.34), 0.42, 0.30)
	var shade := MatLib.make_brushed_metal(Color(0.05, 0.05, 0.06), 0.85, 0.0)
	var paper := MatLib.make_brushed_metal(Color(0.86, 0.87, 0.89), 0.80, 0.0)
	var blade_mat := MatLib.make_brushed_metal(Color(0.17, 0.18, 0.20), 0.60, 0.15)

	var half := size * 0.5
	var cy := 0.048
	_box(parent, offset + Vector3(0.0, cy, 0.0), size, steel)
	_box(parent, offset + Vector3(0.0, cy + half.y + 0.0015, 0.02), Vector3(size.x - 0.010, 0.003, size.z * 0.70), perf)
	_box(parent, offset + Vector3(half.x + 0.0005, cy, 0.03), Vector3(0.001, size.y * 0.5, size.z * 0.35), paper)

	var rear := offset + Vector3(0.0, 0.0, -half.z)
	var fan_r := minf(size.x, size.y) * 0.36
	var fan_c := rear + Vector3(0.0, cy + size.y * 0.12, -0.001)
	_cyl_z(parent, fan_c, fan_r + 0.002, 0.002, shade)
	var blades := Node3D.new()
	blades.position = fan_c + Vector3(0.0, 0.0, -0.004)
	parent.add_child(blades)
	fan_blades(blades, fan_r, 7, blade_mat, steel)
	var guard: Array = []
	for g in range(3):
		guard.append([Vector3(0.0, (float(g) - 1.0) * fan_r * 0.55, 0.0), Vector3(fan_r * 2.0, 0.0016, 0.0016)])
	guard.append([Vector3.ZERO, Vector3(0.0016, fan_r * 2.0, 0.0016)])
	var guard_mi := merged_boxes(parent, "psu_guard_%.4f" % fan_r, guard, steel)
	guard_mi.position = fan_c + Vector3(0.0, 0.0, -0.010)

	if hot_swap:
		var handle_parts: Array = [
			[Vector3(-0.022, 0.0, -0.008), Vector3(0.005, 0.006, 0.016)],
			[Vector3(0.022, 0.0, -0.008), Vector3(0.005, 0.006, 0.016)],
			[Vector3(0.0, 0.0, -0.0165), Vector3(0.050, 0.006, 0.005)],
		]
		var handle := merged_boxes(parent, "psu_handle", handle_parts, steel)
		handle.position = rear + Vector3(0.0, 0.010, 0.0)
		_box(parent, rear + Vector3(-0.012, 0.024, -0.003), Vector3(0.018, 0.014, 0.006), plastic)
		_box(parent, rear + Vector3(0.018, 0.024, -0.003), Vector3(0.010, 0.012, 0.006), handle_mat)
	else:
		_box(parent, rear + Vector3(-0.048, 0.020, -0.003), Vector3(0.022, 0.016, 0.006), plastic)
		_box(parent, rear + Vector3(-0.048, 0.050, -0.003), Vector3(0.010, 0.014, 0.006), plastic)


## Builds a realistic 3D Workbench hardware display (loose Motherboard, CPU in ESD tray,
## GPU card, RAM sticks, M.2 NVMe SSD, thermal paste syringe & screwdriver!)
static func build_workbench_display() -> Node3D:
	var root := Node3D.new()
	var esd := MatLib.get_mat("esd_mat")
	var pcb_g := MatLib.get_mat("pcb_green")
	var ihs := MatLib.get_mat("cpu_ihs")
	var gold := MatLib.get_mat("gold_contacts")
	var steel := MatLib.get_mat("galvanized_steel")
	var plastic := MatLib.get_mat("plastic_black")
	var handle_red := MatLib.make_brushed_metal(Color(0.76, 0.20, 0.16), 0.45, 0.15)

	# Anti-Static Blue-Grey ESD Workbench Mat
	_box(root, Vector3(0.0, 0.004, 0.0), Vector3(1.18, 0.008, 0.62), esd)

	# 1. Loose Open Server Motherboard on Left of Mat (with visible LGA CPU + RAM)
	var mb_demo := build_open_server_chassis("web_server", {"cpu": 0, "gpu": 0, "ram": 1, "storage": 1, "cooling": 0, "psu": 0})
	mb_demo.scale = Vector3(0.58, 0.58, 0.58)
	mb_demo.position = Vector3(-0.28, 0.010, -0.02)
	mb_demo.rotation_degrees.y = 8.0
	root.add_child(mb_demo)

	# 2. Loose 3D CPU sitting face-up on ESD Tray (clearly showing silver IHS + green PCB!)
	var cpu_tray := Node3D.new()
	cpu_tray.position = Vector3(0.18, 0.010, 0.14)
	cpu_tray.rotation_degrees.y = -14.0
	root.add_child(cpu_tray)
	_box(cpu_tray, Vector3(0.0, 0.005, 0.0), Vector3(0.12, 0.010, 0.12), plastic)
	_box(cpu_tray, Vector3(0.0, 0.013, 0.0), Vector3(0.075, 0.006, 0.075), pcb_g)
	_box(cpu_tray, Vector3(0.0, 0.019, 0.0), Vector3(0.058, 0.008, 0.058), ihs)
	_box(cpu_tray, Vector3(0.026, 0.024, 0.026), Vector3(0.010, 0.002, 0.010), gold)

	# 3. Loose 3D Dual-Fan GPU Card resting flat on Right Side of Mat!
	var gpu_demo := build_gpu_card(2)
	gpu_demo.scale = Vector3(1.15, 1.15, 1.15)
	gpu_demo.position = Vector3(0.36, 0.032, -0.08)
	gpu_demo.rotation_degrees = Vector3(0.0, 22.0, -90.0)
	root.add_child(gpu_demo)

	# 4. Loose 3D RAM Sticks + M.2 NVMe SSD
	var ram_demo := build_ram_bank(1)
	ram_demo.scale = Vector3(1.1, 1.1, 1.1)
	ram_demo.position = Vector3(0.14, 0.010, -0.16)
	ram_demo.rotation_degrees.y = 90.0
	root.add_child(ram_demo)

	# 5. Screwdriver + Thermal Paste Syringe
	var sd := Node3D.new()
	sd.position = Vector3(0.42, 0.018, 0.19)
	sd.rotation_degrees.y = 65.0
	root.add_child(sd)
	_cyl_z(sd, Vector3(0.0, 0.0, -0.05), 0.013, 0.10, handle_red)
	_cyl_z(sd, Vector3(0.0, 0.0, 0.06), 0.0035, 0.13, steel)

	var paste := Node3D.new()
	paste.position = Vector3(0.02, 0.014, 0.20)
	paste.rotation_degrees.y = -32.0
	root.add_child(paste)
	_cyl_z(paste, Vector3(0.0, 0.0, 0.0), 0.009, 0.095, steel)
	_cyl_z(paste, Vector3(0.0, 0.0, 0.06), 0.004, 0.030, plastic)

	return root


## Builds a realistic 3D handheld / crate-interior hardware model for ANY catalog item!
static func build_item_visual(item_type: String) -> Node3D:
	if item_type == "old_fuse":
		var blown := ModelLoader.instantiate_custom_model("fuse_d02_blown")
		if blown != null:
			return blown
	if GameState.is_slot_upgradeable(item_type) or item_type == "net_switch":
		var comps := {"cpu": 1, "gpu": (1 if GameState.get_chassis_visual(item_type) == "gpu_server" else 0), "ram": 1, "storage": 1, "cooling": 0, "psu": 0}
		var srv := build_open_server_chassis(item_type, comps)
		srv.scale = Vector3(0.76, 0.76, 0.76)
		return srv

	# Larger floor equipment (rack, rack_pro, cooler, chiller, ups, cart): realistic packaged hardware crate with metal straps!
	var root := Node3D.new()
	var card := MatLib.get_mat("cardboard")
	var strap := MatLib.get_mat("plastic_black")
	var label_paper := MatLib.make_brushed_metal(Color(0.92, 0.92, 0.90), 0.72, 0.0)
	var cat: Dictionary = GameState.ITEM_CATALOG.get(item_type, {"color": Color(0.4, 0.45, 0.5)})
	var badge_mat := StandardMaterial3D.new()
	badge_mat.albedo_color = (cat["color"] as Color).lerp(Color(0.32, 0.34, 0.36), 0.35)
	badge_mat.roughness = 0.55

	_box(root, Vector3(0.0, 0.18, 0.0), Vector3(0.56, 0.36, 0.56), card)
	# Steel/polypropylene industrial packaging straps
	_box(root, Vector3(-0.16, 0.18, 0.0), Vector3(0.022, 0.372, 0.572), strap)
	_box(root, Vector3(0.16, 0.18, 0.0), Vector3(0.022, 0.372, 0.572), strap)
	_box(root, Vector3(0.0, 0.18, 0.0), Vector3(0.572, 0.372, 0.022), strap)
	# Printed white shipping spec sheet + muted category tag
	_box(root, Vector3(-0.08, 0.22, 0.284), Vector3(0.24, 0.16, 0.008), label_paper)
	_box(root, Vector3(-0.08, 0.17, 0.288), Vector3(0.18, 0.04, 0.006), badge_mat)
	_box(root, Vector3(-0.08, 0.22, -0.284), Vector3(0.24, 0.16, 0.008), label_paper)
	return root


static func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Zwischenspeicher für zusammengefügte Meshes. Gleiche Form ergibt dasselbe Mesh,
## damit volle Racks nicht tausende Einzel-Meshes für Rippen und Lüfterblätter erzeugen.
static var _merged_cache: Dictionary = {}


## Fügt viele Quader zu einem einzigen Mesh zusammen.
## parts: Array aus [Vector3 Position, Vector3 Größe] oder [Position, Größe, Basis].
## cache_key muss die Form eindeutig beschreiben, weil das Mesh danach wiederverwendet wird.
static func merged_boxes(parent: Node3D, cache_key: String, parts: Array, mat: Material) -> MeshInstance3D:
	var mesh := _merged_cache.get(cache_key) as Mesh
	if mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in parts:
			var p: Array = part
			var bm := BoxMesh.new()
			bm.size = p[1]
			var rot: Basis = p[2] if p.size() > 2 else Basis.IDENTITY
			st.append_from(bm, 0, Transform3D(rot, p[0]))
		mesh = st.commit()
		_merged_cache[cache_key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Kühlrippen: count dünne Platten, gleichmäßig entlang einer Achse verteilt (0 = X, 1 = Y, 2 = Z).
static func fin_stack(parent: Node3D, center: Vector3, size: Vector3, count: int, axis: int, mat: Material) -> MeshInstance3D:
	var n := maxi(count, 1)
	var span: float = size[axis]
	var pitch := span / float(n)
	var fin_size := size
	fin_size[axis] = pitch * 0.38
	var parts: Array = []
	for i in range(n):
		var offset := Vector3.ZERO
		offset[axis] = -span * 0.5 + (float(i) + 0.5) * pitch
		parts.append([offset, fin_size])
	var key := "fins_%d_%d_%.4f_%.4f_%.4f" % [axis, n, size.x, size.y, size.z]
	var mi := merged_boxes(parent, key, parts, mat)
	mi.position = center
	return mi


## Nabe und angestellte Lüfterblätter um die lokale Z-Achse von parent.
static func fan_blades(parent: Node3D, radius: float, blade_count: int, blade_mat: Material, hub_mat: Material) -> void:
	var parts: Array = []
	var blade_len := radius * 0.66
	var blade_w := radius * 0.44
	var pitch_rad := deg_to_rad(28.0)
	var dist := radius * 0.30 + blade_len * 0.5
	for i in range(blade_count):
		var ang := TAU * float(i) / float(blade_count)
		var rot := Basis(Vector3.BACK, ang) * Basis(Vector3.RIGHT, pitch_rad)
		parts.append([Vector3(cos(ang), sin(ang), 0.0) * dist, Vector3(blade_len, blade_w, radius * 0.04), rot])
	merged_boxes(parent, "blades_%d_%.4f" % [blade_count, radius], parts, blade_mat)
	_cyl_z(parent, Vector3.ZERO, radius * 0.30, radius * 0.24, hub_mat)


## Drehbares Lüfterrad. Dreht um Z oder mit axis_x um X (Meta "spin_axis", ausgewertet in rack_prop).
static func fan_rotor(parent: Node3D, pos: Vector3, radius: float, blade_count: int, axis_x: bool, blade_mat: Material, hub_mat: Material) -> Node3D:
	var rotor := Node3D.new()
	rotor.position = pos
	parent.add_child(rotor)
	var holder := Node3D.new()
	if axis_x:
		rotor.set_meta("spin_axis", "x")
		holder.rotation_degrees.y = 90.0
	rotor.add_child(holder)
	fan_blades(holder, radius, blade_count, blade_mat, hub_mat)
	return rotor


static func _cyl(parent: Node3D, pos: Vector3, rad: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rad
	cm.bottom_radius = rad
	cm.height = height
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cyl_z(parent: Node3D, pos: Vector3, rad: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := _cyl(parent, pos, rad, height, mat)
	mi.rotation_degrees.x = 90.0
	return mi


static func _cyl_x(parent: Node3D, pos: Vector3, rad: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := _cyl(parent, pos, rad, height, mat)
	mi.rotation_degrees.z = 90.0
	return mi
