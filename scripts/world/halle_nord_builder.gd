class_name HalleNordBuilder
extends Node3D
## Halle Nord (seit v3.8): helle Rechenzentrumshalle 24 × 14 m mit drei Abschnitten, Technikecke,
## Büro mit PC, Shuttle-Kiosk und heller Sandwichfassade. Maße stehen in HalleNordLayout.
## Der Knoten liegt im Ursprung von Halle Nord; GarageBuilder baut ihn und reicht seine Helfer durch.



var g: GarageBuilder # (Helfer für Boxen, Labels, Interaktionsflächen, Feuerlöscher …)

var ceiling_lights: Array[SpotLight3D] = []
var daylight_fills: Array[OmniLight3D] = []
var sign_lbl: Label3D
var shuttle_lbl: Label3D
var noc_lbl: Label3D
var router_lbl: Label3D
var breaker_lbls: Array[Label3D] = []
var aisle_temp_lbls: Array[Label3D] = []
var noc_node: Node3D
var cold_aisle_node: Node3D
var campus: HalleNordCampus

var _partitions: Array[StaticBody3D] = []
var _section_nodes: Array = [[], [], []] # je Abschnitt: Knoten, die nur bei offenem Abschnitt da sind
var _section_lights: Array = [[], [], []]
var _core_ports: Array[Node3D] = []
var _barrier_pivot: Node3D
var _barrier_open: float = 0.0

var _floor_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _wainscot_mat: StandardMaterial3D
var _white_mat: StandardMaterial3D
var _ceiling_mat: StandardMaterial3D
var _steel_mat: StandardMaterial3D
var _dark_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _facade_mat: StandardMaterial3D
var _plinth_mat: StandardMaterial3D


func build(garage: GarageBuilder) -> void:
	g = garage
	_make_materials()
	_build_shell()
	_build_facade()
	_build_floor_markings()
	_build_lights()
	_build_partitions()
	_build_tech_corner()
	_build_section_breakers()
	_build_office()
	_build_kiosk_and_props()
	_build_cold_aisle_upgrade()
	_build_delivery_zone()
	_build_site_bounds()
	campus = HalleNordCampus.new()
	campus.name = "HalleNordCampus"
	add_child(campus)
	_barrier_pivot = campus.barrier_pivot
	sync_sections()


# ---------------------------------------------------------------- Materialien

func _make_materials() -> void:
	_floor_mat = (MatLib.get_mat("enterprise_floor").duplicate() as StandardMaterial3D)
	_floor_mat.albedo_color = Color(0.86, 0.88, 0.90)
	_floor_mat.roughness = 0.52
	# Glatte, helle Wandpaneele (kein Mauerwerk)
	_wall_mat = g._mat(Color(0.90, 0.91, 0.92), 0.72, 0.02)
	_wainscot_mat = g._mat(Color(0.56, 0.59, 0.63), 0.62, 0.15)
	_white_mat = g._mat(Color(0.95, 0.95, 0.96), 0.85, 0.0)
	_ceiling_mat = g._mat(Color(0.94, 0.95, 0.96), 0.9, 0.0)
	_ceiling_mat.emission_enabled = true
	_ceiling_mat.emission = Color(0.92, 0.94, 0.97)
	_ceiling_mat.emission_energy_multiplier = 0.22
	_steel_mat = MatLib.make_brushed_metal(Color(0.42, 0.45, 0.49), 0.40, 0.70)
	_dark_mat = g._mat(Color(0.16, 0.17, 0.19), 0.55, 0.30)
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.80, 0.90, 0.96, 0.22)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.roughness = 0.05
	_glass_mat.metallic = 0.2
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_facade_mat = g._mat(Color(0.80, 0.82, 0.84), 0.48, 0.25)
	_plinth_mat = g._mat(Color(0.24, 0.25, 0.27), 0.82, 0.05)


func _box(pos: Vector3, size: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	return g._add_box_visual(self if parent == null else parent, pos, size, mat)


func _solid(pos: Vector3, size: Vector3, mat: Material, parent: Node3D = null) -> void:
	var p := self if parent == null else parent
	if mat != null:
		g._add_box_visual(p, pos, size, mat)
	g._add_collider_box(p, pos, size)


func _emissive(col: Color, energy: float) -> StandardMaterial3D:
	return BuildingPropFactory._emissive(col, energy)


# ---------------------------------------------------------------- Rohbau: Boden, Wände, Decke, Fensterband

func _build_shell() -> void:
	var sx := HalleNordLayout.SHELL_X
	var sz := HalleNordLayout.SHELL_Z
	var t := 0.25
	var h := HalleNordLayout.ROOF_Y
	# Boden (Doppelboden) und Decke
	_solid(Vector3(0.0, -0.1, 0.0), Vector3(sx * 2.0, 0.2, sz * 2.0), _floor_mat)
	_solid(Vector3(0.0, HalleNordLayout.CEILING_Y + 0.1, 0.0), Vector3(sx * 2.0, 0.2, sz * 2.0), _ceiling_mat)
	# Rückwand mit Fensterband (3,5 bis 4,3 m) für Tageslicht
	_solid(Vector3(0.0, 1.75, -sz), Vector3(sx * 2.0 + t, 3.5, t), _wall_mat)
	_solid(Vector3(0.0, (4.3 + h) * 0.5, -sz), Vector3(sx * 2.0 + t, h - 4.3, t), _wall_mat)
	g._add_collider_box(self, Vector3(0.0, 3.9, -sz), Vector3(sx * 2.0, 0.8, t))
	_box(Vector3(0.0, 3.9, -sz), Vector3(sx * 2.0, 0.8, 0.04), _glass_mat)
	for mx in range(-12, 13, 2):
		_box(Vector3(float(mx), 3.9, -sz), Vector3(0.08, 0.8, t + 0.02), _steel_mat)
	# Seitenwände
	_solid(Vector3(-sx, h * 0.5, 0.0), Vector3(t, h, sz * 2.0 + t), _wall_mat)
	_solid(Vector3(sx, h * 0.5, 0.0), Vector3(t, h, sz * 2.0 + t), _wall_mat)
	# Vorderwand mit Rolltor-Öffnung
	var d0 := HalleNordLayout.DOOR_X - HalleNordLayout.DOOR_W * 0.5
	var d1 := HalleNordLayout.DOOR_X + HalleNordLayout.DOOR_W * 0.5
	_solid(Vector3((-sx - t * 0.5 + d0) * 0.5, h * 0.5, sz), Vector3(d0 + sx + t * 0.5, h, t), _wall_mat)
	_solid(Vector3((d1 + sx + t * 0.5) * 0.5, h * 0.5, sz), Vector3(sx + t * 0.5 - d1, h, t), _wall_mat)
	_solid(Vector3(HalleNordLayout.DOOR_X, (HalleNordLayout.DOOR_H + h) * 0.5, sz), Vector3(HalleNordLayout.DOOR_W, h - HalleNordLayout.DOOR_H, t), _wall_mat)
	# Sockelleiste innen (dunkleres Grau bis 1,1 m)
	var wx := HalleNordLayout.WALL_X
	var wz := HalleNordLayout.WALL_Z
	_box(Vector3(0.0, 0.55, -wz + 0.012), Vector3(wx * 2.0, 1.1, 0.02), _wainscot_mat)
	_box(Vector3(-wx + 0.012, 0.55, 0.0), Vector3(0.02, 1.1, wz * 2.0), _wainscot_mat)
	_box(Vector3(wx - 0.012, 0.55, 0.0), Vector3(0.02, 1.1, wz * 2.0), _wainscot_mat)
	_box(Vector3((-wx + d0) * 0.5, 0.55, wz - 0.012), Vector3(d0 + wx, 1.1, 0.02), _wainscot_mat)
	_box(Vector3((d1 + wx) * 0.5, 0.55, wz - 0.012), Vector3(wx - d1, 1.1, 0.02), _wainscot_mat)
	# Paneelfugen der Wandverkleidung (waagerecht und alle 2 m senkrecht)
	var joint := g._mat(Color(0.78, 0.80, 0.82), 0.7, 0.0)
	_box(Vector3(0.0, 2.3, -wz + 0.012), Vector3(wx * 2.0, 0.02, 0.02), joint)
	_box(Vector3(-wx + 0.012, 2.3, 0.0), Vector3(0.02, 0.02, wz * 2.0), joint)
	_box(Vector3(wx - 0.012, 2.3, 0.0), Vector3(0.02, 0.02, wz * 2.0), joint)
	for jx in range(-10, 11, 2):
		_box(Vector3(float(jx), 2.3, -wz + 0.012), Vector3(0.02, 2.4, 0.02), joint)
	for jz in range(-6, 7, 2):
		_box(Vector3(-wx + 0.012, 2.3, float(jz)), Vector3(0.02, 2.4, 0.02), joint)
		_box(Vector3(wx - 0.012, 2.3, float(jz)), Vector3(0.02, 2.4, 0.02), joint)
	# Stahlstützen an den Abschnittsgrenzen
	for px in HalleNordLayout.PARTITION_X:
		for pz in [-wz + 0.12, wz - 0.12]:
			_box(Vector3(float(px), HalleNordLayout.CEILING_Y * 0.5, float(pz)), Vector3(0.24, HalleNordLayout.CEILING_Y, 0.24), _steel_mat)
	# Torzarge und eingerolltes Rolltor oben in der Öffnung
	for side in [d0 - 0.06, d1 + 0.06]:
		_box(Vector3(float(side), HalleNordLayout.DOOR_H * 0.5, sz - 0.18), Vector3(0.12, HalleNordLayout.DOOR_H, 0.12), _steel_mat)
	_box(Vector3(HalleNordLayout.DOOR_X, HalleNordLayout.DOOR_H + 0.22, wz - 0.24), Vector3(HalleNordLayout.DOOR_W + 0.3, 0.44, 0.44), _steel_mat)
	# Verdecker: drinnen fällt die Außenwelt weg, draußen das Innere (Fensterband und Tor bleiben frei)
	for o in [
		[Vector3(0.0, 1.75, -sz), Vector3(sx * 2.0, 3.5, 0.1)],
		[Vector3(-sx, h * 0.5, 0.0), Vector3(0.1, h, sz * 2.0)],
		[Vector3(sx, h * 0.5, 0.0), Vector3(0.1, h, sz * 2.0)],
		[Vector3((-sx + d0) * 0.5, h * 0.5, sz), Vector3(d0 + sx, h, 0.1)],
		[Vector3((d1 + sx) * 0.5, h * 0.5, sz), Vector3(sx - d1, h, 0.1)],
		[Vector3(0.0, HalleNordLayout.CEILING_Y + 0.1, 0.0), Vector3(sx * 2.0, 0.1, sz * 2.0)],
	]:
		var occ := OccluderInstance3D.new()
		var bo := BoxOccluder3D.new()
		bo.size = o[1]
		occ.occluder = bo
		occ.position = o[0]
		add_child(occ)


# ---------------------------------------------------------------- Fassade außen

func _build_facade() -> void:
	var sx := HalleNordLayout.SHELL_X + 0.155
	var sz := HalleNordLayout.SHELL_Z + 0.155
	var h := HalleNordLayout.ROOF_Y
	var d0 := HalleNordLayout.DOOR_X - HalleNordLayout.DOOR_W * 0.5
	var d1 := HalleNordLayout.DOOR_X + HalleNordLayout.DOOR_W * 0.5
	var joint := g._mat(Color(0.58, 0.61, 0.64), 0.6, 0.2)
	# Helle Sandwichpaneele über dunklem Sockel
	var ph := 0.6
	var fh := h - ph
	var fy := ph + fh * 0.5
	_box(Vector3(0.0, fy, -sz), Vector3(sx * 2.0, fh, 0.06), _facade_mat)
	_box(Vector3(-sx, fy, 0.0), Vector3(0.06, fh, sz * 2.0), _facade_mat)
	_box(Vector3(sx, fy, 0.0), Vector3(0.06, fh, sz * 2.0), _facade_mat)
	_box(Vector3((-sx + d0) * 0.5, fy, sz), Vector3(d0 + sx, fh, 0.06), _facade_mat)
	_box(Vector3((d1 + sx) * 0.5, fy, sz), Vector3(sx - d1, fh, 0.06), _facade_mat)
	_box(Vector3(HalleNordLayout.DOOR_X, (HalleNordLayout.DOOR_H + h) * 0.5, sz), Vector3(HalleNordLayout.DOOR_W, h - HalleNordLayout.DOOR_H, 0.06), _facade_mat)
	# Sockel
	_box(Vector3(0.0, ph * 0.5, -sz), Vector3(sx * 2.0 + 0.04, ph, 0.08), _plinth_mat)
	_box(Vector3(-sx, ph * 0.5, 0.0), Vector3(0.08, ph, sz * 2.0 + 0.04), _plinth_mat)
	_box(Vector3(sx, ph * 0.5, 0.0), Vector3(0.08, ph, sz * 2.0 + 0.04), _plinth_mat)
	_box(Vector3((-sx + d0) * 0.5, ph * 0.5, sz), Vector3(d0 + sx, ph, 0.08), _plinth_mat)
	_box(Vector3((d1 + sx) * 0.5, ph * 0.5, sz), Vector3(sx - d1, ph, 0.08), _plinth_mat)
	# Waagerechte Paneelfugen
	for jy in [1.6, 2.6, 3.6]:
		_box(Vector3(0.0, float(jy), -sz - 0.035), Vector3(sx * 2.0, 0.025, 0.012), joint)
		_box(Vector3(-sx - 0.035, float(jy), 0.0), Vector3(0.012, 0.025, sz * 2.0), joint)
		_box(Vector3(sx + 0.035, float(jy), 0.0), Vector3(0.012, 0.025, sz * 2.0), joint)
		_box(Vector3((-sx + d0) * 0.5, float(jy), sz + 0.035), Vector3(d0 + sx, 0.025, 0.012), joint)
		_box(Vector3((d1 + sx) * 0.5, float(jy), sz + 0.035), Vector3(sx - d1, 0.025, 0.012), joint)
	# Dach mit dunkler Attika
	_box(Vector3(0.0, h + 0.06, 0.0), Vector3(sx * 2.0, 0.12, sz * 2.0), g._mat(Color(0.46, 0.48, 0.50), 0.9, 0.0))
	for e in [
		[Vector3(0.0, h + 0.2, -sz), Vector3(sx * 2.0 + 0.1, 0.4, 0.14)],
		[Vector3(0.0, h + 0.2, sz), Vector3(sx * 2.0 + 0.1, 0.4, 0.14)],
		[Vector3(-sx, h + 0.2, 0.0), Vector3(0.14, 0.4, sz * 2.0)],
		[Vector3(sx, h + 0.2, 0.0), Vector3(0.14, 0.4, sz * 2.0)],
	]:
		_box(e[0], e[1], _plinth_mat)
	# Vordach über dem Rolltor
	_box(Vector3(HalleNordLayout.DOOR_X, HalleNordLayout.DOOR_H + 0.35, sz + 0.65), Vector3(HalleNordLayout.DOOR_W + 1.2, 0.12, 1.3), _plinth_mat)
	# Beleuchtetes Firmenschild über dem Vordach
	_box(Vector3(HalleNordLayout.DOOR_X, 4.45, sz + 0.05), Vector3(5.6, 0.62, 0.06), _dark_mat)
	sign_lbl = Label3D.new()
	sign_lbl.text = "MEIN DATACENTER — HALLE NORD"
	sign_lbl.font_size = 40
	sign_lbl.pixel_size = 0.0042
	sign_lbl.outline_size = 0
	sign_lbl.modulate = Color(0.96, 0.98, 1.0)
	sign_lbl.position = Vector3(HalleNordLayout.DOOR_X, 4.45, sz + 0.09)
	sign_lbl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sign_lbl)
	# Wandleuchte über dem Tor
	var door_light := OmniLight3D.new()
	door_light.position = Vector3(HalleNordLayout.DOOR_X, 3.3, sz + 1.2)
	door_light.light_color = Color(1.0, 0.93, 0.82)
	door_light.light_energy = 0.9
	door_light.omni_range = 8.0
	add_child(door_light)


# ---------------------------------------------------------------- Boden: vorgezeichnete Rack-Reihen und Kaltgänge

## Reihen je Abschnitt: [z der Reihenmitte, x von, x bis]. Zwischen zwei Reihen liegt ein Kaltgang.
func _rows(section: int) -> Array:
	match section:
		0:
			return [[-4.3, -7.8, -4.5], [-1.7, -11.2, -4.5], [1.3, -10.9, -4.5]]
		1:
			return [[-4.3, -3.5, 3.5], [-1.7, -3.5, 3.5], [1.3, -3.5, 3.5], [3.9, -3.5, 3.5]]
	return [[-4.3, 4.5, 11.3], [-1.7, 4.5, 11.3], [1.3, 4.5, 11.3], [3.9, 4.5, 11.3]]


func _build_floor_markings() -> void:
	var line := g._mat(Color(0.70, 0.73, 0.77), 0.7, 0.0)
	var perf := (MatLib.get_mat("perforated_mesh").duplicate() as StandardMaterial3D)
	perf.albedo_color = Color(0.62, 0.66, 0.70)
	for s in range(3):
		var parent := self if s == 0 else _section_node(s)
		var rows := _rows(s)
		for r in rows:
			var z := float(r[0])
			var x0 := float(r[1])
			var x1 := float(r[2])
			var row_len := x1 - x0
			var cx := (x0 + x1) * 0.5
			# Rahmen der Rack-Reihe (1 m tief)
			_box(Vector3(cx, 0.004, z - 0.5), Vector3(row_len, 0.004, 0.04), line, parent)
			_box(Vector3(cx, 0.004, z + 0.5), Vector3(row_len, 0.004, 0.04), line, parent)
			_box(Vector3(x0, 0.004, z), Vector3(0.04, 0.004, 1.0), line, parent)
			_box(Vector3(x1, 0.004, z), Vector3(0.04, 0.004, 1.0), line, parent)
		# Lochplatten in den Kaltgängen zwischen Reihe A/B und C/D
		for pair in [[0, 1], [2, 3]]:
			if int(pair[1]) >= rows.size():
				continue
			var ra: Array = rows[pair[0]]
			var rb: Array = rows[pair[1]]
			var az := (float(ra[0]) + float(rb[0])) * 0.5
			var ax0 := maxf(float(ra[1]), float(rb[1]))
			var ax1 := minf(float(ra[2]), float(rb[2]))
			var tx := ax0 + 0.5
			while tx < ax1 - 0.3:
				_box(Vector3(tx, 0.003, az), Vector3(0.58, 0.004, 0.58), perf, parent)
				tx += 1.2


# ---------------------------------------------------------------- Licht

func _build_lights() -> void:
	var panel := _emissive(Color(0.98, 0.98, 1.0), 2.4)
	for s in range(3):
		var parent := self if s == 0 else _section_node(s)
		var cx := (float(HalleNordLayout.SECTIONS[s][0]) + float(HalleNordLayout.SECTIONS[s][1])) * 0.5
		# LED-Deckenfelder
		for px in [cx - 2.0, cx + 2.0]:
			for pz in [-4.5, -1.5, 1.5, 4.5]:
				_box(Vector3(float(px), HalleNordLayout.CEILING_Y - 0.01, float(pz)), Vector3(1.2, 0.03, 0.6), panel, parent)
		for lz in [-2.6, 2.6]:
			var sp := SpotLight3D.new()
			sp.position = Vector3(cx, HalleNordLayout.CEILING_Y - 0.15, float(lz))
			sp.rotation_degrees.x = -90.0
			sp.light_color = Color(1.0, 0.98, 0.95)
			sp.light_energy = 2.1
			sp.spot_range = 8.5
			sp.spot_angle = 76.0
			sp.spot_attenuation = 1.0
			sp.shadow_enabled = false
			add_child(sp)
			ceiling_lights.append(sp)
			(_section_lights[s] as Array).append(sp)
		var day := OmniLight3D.new()
		day.position = Vector3(cx, 3.9, -5.4)
		day.light_color = Color(0.93, 0.96, 1.0)
		day.light_energy = 0.5
		day.omni_range = 9.0
		add_child(day)
		daylight_fills.append(day)
		(_section_lights[s] as Array).append(day)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-6.0, 2.8, 0.0)
	fill.light_color = Color(0.98, 0.97, 0.95)
	fill.light_energy = 0.3
	fill.omni_range = 14.0
	add_child(fill)
	var rp := ReflectionProbe.new()
	rp.position = Vector3(0.0, 2.3, 0.0)
	rp.size = Vector3(HalleNordLayout.SHELL_X * 2.0, HalleNordLayout.CEILING_Y, HalleNordLayout.SHELL_Z * 2.0)
	rp.box_projection = true
	rp.interior = true
	rp.intensity = 0.8
	rp.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	rp.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(rp)
	g._reflection_probes.append(rp)


# ---------------------------------------------------------------- Abschnitte: Trennwände und Inhalte

func _section_node(s: int) -> Node3D:
	var arr: Array = _section_nodes[s]
	if arr.is_empty():
		var n := Node3D.new()
		n.name = "Abschnitt%d" % (s + 1)
		add_child(n)
		arr.append(n)
	return arr[0]


func _build_partitions() -> void:
	var panel := g._mat(Color(0.82, 0.84, 0.86), 0.55, 0.35)
	var rib := g._mat(Color(0.66, 0.69, 0.72), 0.5, 0.4)
	var depth := HalleNordLayout.WALL_Z * 2.0
	for i in range(2):
		var wall := StaticBody3D.new()
		wall.name = "TrennwandAbschnitt%d" % (i + 2)
		wall.collision_layer = 1
		wall.collision_mask = 0
		wall.position = Vector3(float(HalleNordLayout.PARTITION_X[i]), HalleNordLayout.CEILING_Y * 0.5, 0.0)
		add_child(wall)
		g._add_box_visual(wall, Vector3.ZERO, Vector3(HalleNordLayout.PARTITION_T, HalleNordLayout.CEILING_Y, depth), panel)
		for rz in range(-6, 7, 1):
			g._add_box_visual(wall, Vector3(-HalleNordLayout.PARTITION_T * 0.5 - 0.01, 0.0, float(rz)), Vector3(0.02, HalleNordLayout.CEILING_Y, 0.05), rib)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(HalleNordLayout.PARTITION_T, HalleNordLayout.CEILING_Y, depth)
		col.shape = shape
		wall.add_child(col)
		var occ := OccluderInstance3D.new()
		var bo := BoxOccluder3D.new()
		bo.size = Vector3(HalleNordLayout.PARTITION_T, HalleNordLayout.CEILING_Y, depth)
		occ.occluder = bo
		wall.add_child(occ)
		var meta: Dictionary = GameState.BUILDING_UPGRADE_CATALOG["upg_nord_section_%d" % (i + 2)]
		var lbl := Label3D.new()
		lbl.text = tr("ABSCHNITT %d — NOCH ZU\nAm PC in Halle Nord ausbauen ($%d, ab Firmenstufe %d)") % [i + 2, int(meta["price"]), int(meta["req_level"])]
		lbl.font_size = 34
		lbl.pixel_size = 0.0045
		lbl.outline_size = 0
		lbl.modulate = Color(0.22, 0.28, 0.36)
		lbl.position = Vector3(-HalleNordLayout.PARTITION_T * 0.5 - 0.03, -0.4, 0.0)
		lbl.rotation_degrees.y = -90.0
		wall.add_child(lbl)
		_partitions.append(wall)


## Offene Abschnitte zeigen, gesperrte hinter der Trennwand verstecken.
func sync_sections() -> void:
	var n := maxi(1, HalleNordLayout.sections())
	for i in range(_partitions.size()):
		var closed := n <= i + 1
		_partitions[i].visible = closed
		for c in _partitions[i].get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).set_deferred("disabled", not closed or not GameState.halle_nord_owned)
	for s in range(1, 3):
		var open := s < n
		for node in _section_nodes[s]:
			(node as Node3D).visible = open
			g._set_collisions_enabled_recursive(node, open and GameState.halle_nord_owned)
		for li in _section_lights[s]:
			(li as Light3D).visible = open
	for i in range(_core_ports.size()):
		_core_ports[i].visible = i < HalleNordLayout.core_ports(n)


# ---------------------------------------------------------------- Technikecke: Verteiler 1, Core-Switch, USV

func _build_tech_corner() -> void:
	var frame := g._mat(Color(0.30, 0.33, 0.37), 0.5, 0.5)
	var hgt := 2.6
	var zf := HalleNordLayout.TECH_MAX.y
	var xf := HalleNordLayout.TECH_MAX.x
	var z_back := HalleNordLayout.TECH_MIN.y
	# Brüstung + Glas wie beim Büro: vorne mit Tür (x -10,3 bis -9,3), seitlich zur Halle
	for seg in [[HalleNordLayout.TECH_MIN.x, -10.3], [-9.3, xf]]:
		var a := float(seg[0])
		var b := float(seg[1])
		_solid(Vector3((a + b) * 0.5, 0.5, zf), Vector3(b - a, 1.0, 0.1), _white_mat)
		_box(Vector3((a + b) * 0.5, 1.75, zf), Vector3(b - a, 1.5, 0.03), _glass_mat)
		g._add_collider_box(self, Vector3((a + b) * 0.5, 1.75, zf), Vector3(b - a, 1.5, 0.05))
		_box(Vector3((a + b) * 0.5, hgt, zf), Vector3(b - a, 0.2, 0.1), frame)
	_solid(Vector3(xf, 0.5, (z_back + zf) * 0.5), Vector3(0.1, 1.0, zf - z_back), _white_mat)
	_box(Vector3(xf, 1.75, (z_back + zf) * 0.5), Vector3(0.03, 1.5, zf - z_back), _glass_mat)
	g._add_collider_box(self, Vector3(xf, 1.75, (z_back + zf) * 0.5), Vector3(0.05, 1.5, zf - z_back))
	_box(Vector3(xf, hgt, (z_back + zf) * 0.5), Vector3(0.1, 0.2, zf - z_back), frame)
	_box(Vector3(-9.8, 2.3, zf), Vector3(1.0, 0.4, 0.1), frame)
	for px in [-10.3, -9.3, xf]:
		_box(Vector3(float(px), hgt * 0.5, zf), Vector3(0.08, hgt, 0.08), frame)
	var tl: Label3D = g._add_small_label(self, Vector3(-9.8, 2.35, zf + 0.06), "TECHNIK", 30, 0.0035, Color(0.20, 0.26, 0.34))
	tl.double_sided = true
	# Verteiler Abschnitt 1
	_build_breaker(0, self)
	# Core-Switch-Schrank (42U) mit Patchfeld
	var core := Node3D.new()
	core.position = HalleNordLayout.CORE_POS
	add_child(core)
	_solid(Vector3(0.0, 1.05, 0.0), Vector3(0.8, 2.1, 1.0), _dark_mat, core)
	_box(Vector3(0.0, 1.05, 0.505), Vector3(0.72, 2.0, 0.01), g._mat(Color(0.10, 0.11, 0.12), 0.4, 0.5), core)
	var jack := g._mat(Color(0.05, 0.05, 0.06), 0.6, 0.1)
	var max_ports := HalleNordLayout.CORE_PORTS_BASE + HalleNordLayout.CORE_PORTS_PER_SECTION * (HalleNordLayout.MAX_SECTIONS - 1)
	for i in range(max_ports):
		var p := HalleNordLayout.core_socket(i) - GameState.HALLE_NORD_ORIGIN - HalleNordLayout.CORE_POS
		var j := g._add_box_visual(core, p, Vector3(0.044, 0.04, 0.02), jack)
		_core_ports.append(j)
	var led := _emissive(Color(0.2, 0.95, 0.4), 1.6)
	for r in range(5):
		_box(Vector3(0.28, 1.62 - float(r) * 0.13, 0.515), Vector3(0.02, 0.012, 0.004), led, core)
	router_lbl = g._add_small_label(core, Vector3(0.0, 2.2, 0.52), "CORE-SWITCH\nPorts: 0 / 16", 22, 0.0022, Color(0.30, 0.55, 0.85))
	var na: Area3D = g._make_interact_area(Vector3(0.9, 2.0, 0.6), {"interact_type": "net_port", "entity_id": GameState.HALL_NORD_ROUTER_ID})
	na.position = Vector3(0.0, 1.1, 0.6)
	core.add_child(na)
	# USV-Schränke an der Westwand
	for uz in [-5.55, -4.6]:
		_solid(Vector3(-11.55, 0.9, float(uz)), Vector3(0.6, 1.8, 0.88), g._mat(Color(0.86, 0.87, 0.88), 0.6, 0.2))
		_box(Vector3(-11.24, 1.45, float(uz)), Vector3(0.01, 0.16, 0.3), _emissive(Color(0.25, 0.7, 1.0), 1.0))
	g._add_small_label(self, Vector3(-11.23, 1.72, -5.08), "USV", 26, 0.003, Color(0.25, 0.30, 0.36)).rotation_degrees.y = 90.0
	# Kabeltrasse von der Technikecke an der Rückwand entlang zu den anderen Verteilern
	var tray := g._mat(Color(0.92, 0.72, 0.12), 0.5, 0.35)
	_box(Vector3(0.0, 3.25, -HalleNordLayout.WALL_Z + 0.25), Vector3(HalleNordLayout.WALL_X * 2.0 - 0.4, 0.08, 0.35), tray)
	for bx in [-8.0, 0.0, 8.0]:
		_box(Vector3(float(bx), 3.25 + 0.6, -HalleNordLayout.WALL_Z + 0.25), Vector3(0.04, 1.2, 0.04), _steel_mat)


func _build_breaker(idx: int, parent: Node3D) -> void:
	var root := Node3D.new()
	root.position = HalleNordLayout.BREAKER_POS[idx]
	parent.add_child(root)
	var body := g._mat(Color(0.84, 0.85, 0.86), 0.55, 0.2)
	_solid(Vector3(0.0, 1.0, 0.0), Vector3(HalleNordLayout.BREAKER_W, 2.0, HalleNordLayout.BREAKER_D), body, root)
	_box(Vector3(0.0, 1.45, HalleNordLayout.BREAKER_D * 0.5 + 0.005), Vector3(HalleNordLayout.BREAKER_W - 0.1, 0.9, 0.01), g._mat(Color(0.74, 0.76, 0.78), 0.5, 0.2), root)
	var sock := g._mat(Color(0.10, 0.32, 0.72), 0.5, 0.1)
	for i in range(HalleNordLayout.breaker_ports(idx)):
		var p := HalleNordLayout.breaker_socket(idx, i) - GameState.HALLE_NORD_ORIGIN - (HalleNordLayout.BREAKER_POS[idx] as Vector3)
		_box(p - Vector3(0.0, 0.0, 0.02), Vector3(0.1, 0.12, 0.05), sock, root)
	var lbl: Label3D = g._add_small_label(root, Vector3(0.0, 1.62, HalleNordLayout.BREAKER_D * 0.5 + 0.02), "VERTEILER %d" % (idx + 1), 22, 0.0024, Color(0.12, 0.16, 0.22))
	breaker_lbls.append(lbl)
	var a: Area3D = g._make_interact_area(Vector3(HalleNordLayout.BREAKER_W + 0.1, 2.0, 0.6), {"interact_type": "power_port", "entity_id": GameState.HALL_NORD_BREAKER_IDS[idx]})
	a.position = Vector3(0.0, 1.0, HalleNordLayout.BREAKER_D * 0.5 + 0.2)
	root.add_child(a)


func _build_section_breakers() -> void:
	for idx in [1, 2]:
		_build_breaker(idx, _section_node(idx))


# ---------------------------------------------------------------- Büro mit PC (NOC-Ausbau hier drin)

func _build_office() -> void:
	var x0 := HalleNordLayout.OFFICE_MIN.x
	var x1 := HalleNordLayout.OFFICE_MAX.x
	var z0 := HalleNordLayout.OFFICE_MIN.y
	var z1 := HalleNordLayout.OFFICE_MAX.y
	var top := 2.7
	var frame := g._mat(Color(0.30, 0.33, 0.37), 0.45, 0.6)
	# Nordwand: Brüstung, Glas, Rahmen
	_solid(Vector3((x0 + x1) * 0.5, 0.45, z0), Vector3(x1 - x0, 0.9, 0.1), _white_mat)
	_box(Vector3((x0 + x1) * 0.5, 1.7, z0), Vector3(x1 - x0, 1.6, 0.03), _glass_mat)
	g._add_collider_box(self, Vector3((x0 + x1) * 0.5, 1.7, z0), Vector3(x1 - x0, 1.6, 0.05))
	_box(Vector3((x0 + x1) * 0.5, 2.6, z0), Vector3(x1 - x0, 0.2, 0.1), frame)
	# Ostwand zur Halle mit Tür (z 3,6 bis 4,5) und Glas
	var dz0 := 3.6
	var dz1 := 4.5
	_solid(Vector3(x1, 0.45, (dz1 + z1) * 0.5), Vector3(0.1, 0.9, z1 - dz1), _white_mat)
	_box(Vector3(x1, 1.7, (dz1 + z1) * 0.5), Vector3(0.03, 1.6, z1 - dz1), _glass_mat)
	g._add_collider_box(self, Vector3(x1, 1.7, (dz1 + z1) * 0.5), Vector3(0.05, 1.6, z1 - dz1))
	_box(Vector3(x1, 2.6, (z0 + z1) * 0.5), Vector3(0.1, 0.2, z1 - z0), frame)
	_box(Vector3(x1, 2.3, (dz0 + dz1) * 0.5), Vector3(0.1, 0.4, dz1 - dz0), frame)
	for pz in [z0, dz1, z1 - 0.05]:
		_box(Vector3(x1, top * 0.5, float(pz)), Vector3(0.08, top, 0.08), frame)
	# Decke des Büros
	_box(Vector3((x0 + x1) * 0.5, top + 0.05, (z0 + z1) * 0.5), Vector3(x1 - x0, 0.1, z1 - z0), _white_mat)
	var ol := OmniLight3D.new()
	ol.position = Vector3((x0 + x1) * 0.5, top - 0.3, (z0 + z1) * 0.5)
	ol.light_color = Color(1.0, 0.95, 0.88)
	ol.light_energy = 0.7
	ol.omni_range = 3.6
	add_child(ol)
	var office_sign: Label3D = g._add_small_label(self, Vector3(x1 + 0.06, 2.45, (dz1 + z1) * 0.5), "BÜRO", 30, 0.0035, Color(0.20, 0.26, 0.34))
	office_sign.rotation_degrees.y = 90.0
	# PC-Tisch mit Live-Bildschirm
	var desk := Node3D.new()
	desk.name = "NordPcDesk"
	desk.position = HalleNordLayout.DESK_POS
	desk.rotation_degrees.y = HalleNordLayout.DESK_YAW
	add_child(desk)
	desk.add_to_group("pc_desk")
	var desk_m := ModelLoader.instantiate_custom_model("terminal_desk")
	if desk_m != null:
		desk.add_child(desk_m)
		g._dress_desk(desk_m)
		g._add_desk_collider(desk)
	else:
		g._build_desk_procedural(desk)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.82, 0.44)
	quad.mesh = qm
	quad.name = "PcScreenQuad"
	quad.material_override = g._pc_main_mat
	quad.position = Vector3(-0.10, 1.24, -0.1595)
	desk.add_child(quad)
	g._add_status_quad(desk)
	var ta: Area3D = g._make_interact_area(Vector3(1.85, 1.25, 1.05), {"interact_type": "terminal", "entity_id": "terminal_nord"})
	ta.position = Vector3(0.0, 1.15, 0.0)
	desk.add_child(ta)
	# NOC-Ausbau: 3 Monitore über dem Tisch, Live-Tafel und Kaffeebar
	noc_node = Node3D.new()
	noc_node.name = "NocAusbau"
	add_child(noc_node)
	var tel: Material = MatLib.get_telemetry_screen_material()
	for i in range(3):
		var mz := 4.62 + float(i) * 0.68
		_box(Vector3(x0 + 0.05, 1.95, mz), Vector3(0.04, 0.42, 0.64), _dark_mat, noc_node)
		var scr := MeshInstance3D.new()
		var sq := QuadMesh.new()
		sq.size = Vector2(0.6, 0.38)
		scr.mesh = sq
		scr.material_override = tel
		scr.position = Vector3(x0 + 0.075, 1.95, mz)
		scr.rotation_degrees.y = 90.0
		noc_node.add_child(scr)
	noc_lbl = g._add_small_label(noc_node, Vector3(x0 + 0.08, 2.45, 5.3), "NOC LIVE  •  HALLE NORD", 20, 0.0021, Color(0.20, 0.42, 0.70))
	noc_lbl.rotation_degrees.y = 90.0
	_solid(Vector3(-9.75, 0.45, 6.5), Vector3(0.7, 0.9, 0.62), g._mat(Color(0.30, 0.24, 0.18), 0.6, 0.0), noc_node)
	var coffee := ModelLoader.instantiate_custom_model("prop_coffee_machine")
	if coffee != null:
		coffee.position = Vector3(-9.75, 0.905, 6.55)
		coffee.rotation_degrees.y = -90.0
		noc_node.add_child(coffee)
		coffee.add_child(CoffeeMachineFx.make("nord"))


# ---------------------------------------------------------------- Kiosk, Regal, Sicherheit

func _build_kiosk_and_props() -> void:
	var kiosk := Node3D.new()
	kiosk.position = HalleNordLayout.KIOSK_POS
	kiosk.rotation_degrees.y = HalleNordLayout.KIOSK_YAW
	add_child(kiosk)
	var k_m := ModelLoader.instantiate_custom_model("halle_nord_shuttle_kiosk")
	if k_m != null:
		kiosk.add_child(k_m)
	else:
		_box(Vector3(0.0, 0.8, 0.0), Vector3(0.6, 1.6, 0.3), _dark_mat, kiosk)
	shuttle_lbl = g._add_small_label(kiosk, Vector3(0.0, 1.37, 0.135), "SHUTTLE\n[E] → Garage\n(oder Taste [T])", 20, 0.0019, Color(0.92, 0.98, 1.0))
	shuttle_lbl.rotation_degrees.x = -12.0
	var ka: Area3D = g._make_interact_area(Vector3(0.8, 1.7, 0.7), {"interact_type": "shuttle_teleport", "entity_id": "shuttle_nord"})
	ka.position = Vector3(0.0, 0.9, 0.2)
	kiosk.add_child(ka)
	g._add_collider_box(kiosk, Vector3(0.0, 0.8, -0.04), Vector3(0.62, 1.6, 0.30))
	# Ersatzteilregal an der Westwand
	var shelf := BuildingPropFactory.build_heavy_workshop_shelf()
	shelf.position = HalleNordLayout.SHELF_POS
	add_child(shelf)
	g._add_collider_box(self, HalleNordLayout.SHELF_POS + Vector3(0.0, 1.07, 0.0), Vector3(0.56, 2.14, 1.56))
	# Feuerlöscher, Erste Hilfe, Uhr, Notausgang
	g._build_extinguisher_station(self, "nord", Vector3(-HalleNordLayout.WALL_X + 0.06, 1.22, -2.4), 90.0)
	var aid := Node3D.new()
	aid.position = Vector3(-HalleNordLayout.WALL_X + 0.06, 1.55, 2.4)
	aid.rotation_degrees.y = 90.0
	add_child(aid)
	_box(Vector3.ZERO, Vector3(0.42, 0.42, 0.1), g._mat(Color(0.05, 0.55, 0.28), 0.5, 0.05), aid)
	_box(Vector3(0.0, 0.0, 0.055), Vector3(0.24, 0.07, 0.01), _white_mat, aid)
	_box(Vector3(0.0, 0.0, 0.055), Vector3(0.07, 0.24, 0.01), _white_mat, aid)
	var clock := Node3D.new()
	clock.position = Vector3(-6.0, 3.0, -HalleNordLayout.WALL_Z + 0.04)
	add_child(clock)
	var face := BuildingPropFactory._cyl_z(clock, Vector3.ZERO, 0.24, 0.05, _white_mat)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	BuildingPropFactory._cyl_z(clock, Vector3(0.0, 0.0, -0.005), 0.26, 0.04, _dark_mat)
	_box(Vector3(0.0, 0.07, 0.03), Vector3(0.018, 0.15, 0.006), _dark_mat, clock)
	_box(Vector3(0.08, 0.0, 0.032), Vector3(0.17, 0.014, 0.006), _dark_mat, clock)
	var exit_mat := _emissive(Color(0.12, 0.88, 0.38), 1.6)
	_box(Vector3(HalleNordLayout.DOOR_X, HalleNordLayout.DOOR_H + 0.62, HalleNordLayout.WALL_Z - 0.04), Vector3(0.62, 0.22, 0.05), exit_mat)
	var ex: Label3D = g._add_small_label(self, Vector3(HalleNordLayout.DOOR_X, HalleNordLayout.DOOR_H + 0.62, HalleNordLayout.WALL_Z - 0.07), "NOTAUSGANG", 22, 0.0024, Color(1, 1, 1))
	ex.rotation_degrees.y = 180.0
	# Altpapiertonne draußen neben dem Tor
	g._build_paper_bin(self, "nord", Vector3(-2.4, 0.0, HalleNordLayout.SHELL_Z + 0.9), 0.0)


# ---------------------------------------------------------------- Ausbau Kaltgang: LED-Führung und Anzeigen

func _build_cold_aisle_upgrade() -> void:
	cold_aisle_node = Node3D.new()
	cold_aisle_node.name = "KaltgangAusbau"
	add_child(cold_aisle_node)
	var glow := _emissive(Color(0.25, 0.62, 1.0), 1.4)
	for s in range(3):
		var parent := cold_aisle_node
		if s > 0:
			parent = Node3D.new()
			cold_aisle_node.add_child(parent)
			(_section_nodes[s] as Array).append(parent)
		var rows := _rows(s)
		for pair in [[0, 1], [2, 3]]:
			if int(pair[1]) >= rows.size():
				continue
			var ra: Array = rows[pair[0]]
			var rb: Array = rows[pair[1]]
			var az := (float(ra[0]) + float(rb[0])) * 0.5
			var ax0 := maxf(float(ra[1]), float(rb[1]))
			var ax1 := minf(float(ra[2]), float(rb[2]))
			for off in [-0.62, 0.62]:
				_box(Vector3((ax0 + ax1) * 0.5, 0.006, az + float(off)), Vector3(ax1 - ax0, 0.004, 0.035), glow, parent)
		var cx := (float(HalleNordLayout.SECTIONS[s][0]) + float(HalleNordLayout.SECTIONS[s][1])) * 0.5
		var dx := cx + (2.4 if s == 0 else -2.2)
		_box(Vector3(dx, 2.3, -HalleNordLayout.WALL_Z + 0.03), Vector3(1.1, 0.34, 0.04), _dark_mat, parent)
		aisle_temp_lbls.append(g._add_small_label(parent, Vector3(dx, 2.3, -HalleNordLayout.WALL_Z + 0.06), "KALTGANG 22.0 °C", 22, 0.0022, Color(0.55, 0.85, 1.0)))


# ---------------------------------------------------------------- Lieferzone vor dem Rolltor

func _build_delivery_zone() -> void:
	for sp in DeliveryPlan.SMALL_PALLETS:
		var pal := ModelLoader.instantiate_custom_model("euro_pallet")
		if pal != null:
			pal.position = DeliveryPlan.NORD_OFFSET - GameState.HALLE_NORD_ORIGIN + Vector3(sp.x, 0.0, sp.y)
			add_child(pal)
	var yellow := g._mat(Color(0.95, 0.74, 0.12), 0.55, 0.05)
	var z0 := HalleNordLayout.SHELL_Z + 0.6
	var z1 := HalleNordLayout.SHELL_Z + 3.4
	var x := HalleNordLayout.DOOR_X
	_box(Vector3(x, 0.012, z0), Vector3(4.2, 0.015, 0.10), yellow)
	_box(Vector3(x, 0.012, z1), Vector3(4.2, 0.015, 0.10), yellow)
	_box(Vector3(x - 2.05, 0.012, (z0 + z1) * 0.5), Vector3(0.10, 0.015, z1 - z0), yellow)
	_box(Vector3(x + 2.05, 0.012, (z0 + z1) * 0.5), Vector3(0.10, 0.015, z1 - z0), yellow)
	var dz: Label3D = g._add_small_label(self, Vector3(x, 0.02, z1 - 0.5), "LIEFERZONE", 48, 0.0055, Color(0.98, 0.82, 0.26, 0.9))
	dz.rotation_degrees = Vector3(-90.0, 0.0, 0.0)


# ---------------------------------------------------------------- Unsichtbare Geländegrenze (Zaun)

func _build_site_bounds() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for spec in [
		[Vector3(0.8, 2.0, 16.4), Vector3(52.0, 4.0, 0.4)], # vorne (auch die Einfahrt: der Hof ist das Gelände)
		[Vector3(0.8, 2.0, -12.8), Vector3(52.0, 4.0, 0.4)],
		[Vector3(-25.2, 2.0, 1.8), Vector3(0.4, 4.0, 29.4)],
		[Vector3(26.8, 2.0, 1.8), Vector3(0.4, 4.0, 29.4)],
	]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = spec[1] as Vector3
		cs.shape = bs
		cs.position = spec[0] as Vector3
		body.add_child(cs)


# ---------------------------------------------------------------- Laufende Anzeigen

func refresh_labels() -> void:
	if not GameState.halle_nord_owned:
		return
	for i in range(breaker_lbls.size()):
		var bid := GameState.HALL_NORD_BREAKER_IDS[i]
		breaker_lbls[i].text = tr("VERTEILER %d\n%d W  •  Steckdosen: %d / %d") % [
			i + 1, HalleNordLayout.WATTS_PER_SECTION, GameState.count_cables_on("power", bid), GameState.get_max_ports("power", bid)]
	if router_lbl != null:
		router_lbl.text = tr("CORE-SWITCH\nPorts: %d / %d") % [
			GameState.count_cables_on("network", GameState.HALL_NORD_ROUTER_ID), GameState.get_max_ports("network", GameState.HALL_NORD_ROUTER_ID)]
	if shuttle_lbl != null:
		shuttle_lbl.text = tr("SHUTTLE\n[E] → Garage\n(oder Taste [T])")
	for tl in aisle_temp_lbls:
		tl.text = "KALTGANG  %.1f °C" % GameState.nord_room_temp


func refresh_company(cname: String) -> void:
	if sign_lbl != null:
		sign_lbl.text = cname.left(18) + " — HALLE NORD"
	if noc_lbl != null and GameState.is_active and GameState.halle_nord_owned:
		var nord_racks := 0
		for rid in GameState.racks.keys():
			if HalleNordLayout.is_nord(GameState.racks[rid]["pos"] as Vector3):
				nord_racks += 1
		noc_lbl.text = tr("NOC LIVE  •  HALLE NORD\nRacks: %d   Temperatur: %.1f °C\nWartungshinweise: %d   %s") % [
			nord_racks, GameState.nord_room_temp, GameState.get_maintenance_warnings().size(),
			tr("ALLES OK") if GameState.breaker_on else tr("STROMAUSFALL!")]


func sync_upgrades() -> void:
	var noc_on := GameState.has_building_upgrade("upg_noc_suite")
	noc_node.visible = noc_on
	g._set_collisions_enabled_recursive(noc_node, noc_on and GameState.halle_nord_owned)
	cold_aisle_node.visible = GameState.has_building_upgrade("upg_cold_aisle_pro")
	if campus != null:
		campus.sync_building_upgrades()
	sync_sections()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _barrier_pivot == null or not _barrier_pivot.is_visible_in_tree():
		return
	# Schranke öffnet für Lieferwagen und Spieler in der Nähe
	var want := false
	if GameState.van_site == "halle_nord" and GameState.van_phase != "idle":
		want = true
	var lp := get_tree().get_first_node_in_group("local_player") as Node3D
	if lp != null and lp.global_position.distance_to(_barrier_pivot.global_position + Vector3(-4.0, 0.0, 0.0)) < 7.0:
		want = true
	_barrier_open = move_toward(_barrier_open, 1.0 if want else 0.0, delta * 0.8)
	var e := _barrier_open * _barrier_open * (3.0 - 2.0 * _barrier_open)
	_barrier_pivot.rotation_degrees.z = -84.0 * e
