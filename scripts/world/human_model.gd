class_name HumanModel
extends Node3D
## Eigene Figur (human.glb): setzt Körper, Gesicht, Haare und Kleidung nach einem Aussehen zusammen.
## Blickt wie alle Figuren nach -Z. Bewegung kommt aus HumanRig.

const MODEL := "human"
const HAIR: Array[String] = ["", "Hair_Buzz", "Hair_Short", "Hair_Side", "Hair_Undercut", "Hair_Curly", "Hair_Afro", "Hair_Mohawk", "Hair_Bob", "Hair_Long", "Hair_Pony", "Hair_Bun"]
const HAIR_NAMES: Array[String] = ["Glatze", "Raspelkurz", "Kurz", "Seitenscheitel", "Undercut", "Locken", "Afro", "Irokese", "Mittellang", "Lang", "Pferdeschwanz", "Dutt"]
const BROWS: Array[String] = ["Brows_A", "Brows_B", "Brows_C"]
const BROW_NAMES: Array[String] = ["Normal", "Kräftig", "Fein"]
const BEARDS: Array[String] = ["", "Beard_Mustache", "Beard_Goatee", "Beard_Short", "Beard_Full"]
const BEARD_NAMES: Array[String] = ["Kein Bart", "Schnurrbart", "Kinnbart", "Kurzer Bart", "Vollbart"]
const TOPS: Array[String] = ["Top_Tee", "Top_Polo", "Top_Shirt", "Top_Sweater", "Top_Hoodie", "Top_Jacket", "Top_Work", "Top_Vest", "Top_Suit", "Top_Coat"]
const TOP_NAMES: Array[String] = ["T-Shirt", "Polo", "Hemd", "Pullover", "Kapuzenpulli", "Jacke", "Arbeitsjacke", "Warnweste", "Anzug", "Kittel"]
const BOTTOMS: Array[String] = ["Bottom_Jeans", "Bottom_Chino", "Bottom_Cargo", "Bottom_Work", "Bottom_Suit", "Bottom_Shorts"]
const BOTTOM_NAMES: Array[String] = ["Jeans", "Chino", "Cargohose", "Arbeitshose", "Anzughose", "Shorts"]
const SHOES: Array[String] = ["Shoes_Sneaker", "Shoes_Boot", "Shoes_Loafer", "Shoes_Safety"]
const SHOE_NAMES: Array[String] = ["Turnschuhe", "Stiefel", "Halbschuhe", "Sicherheitsschuhe"]
const HATS: Array[String] = ["", "Hat_Cap", "Hat_Beanie", "Hat_Helmet", "Hat_Headset"]
const HAT_NAMES: Array[String] = ["Nichts", "Kappe", "Mütze", "Helm", "Headset"]
const GLASSES: Array[String] = ["", "Glasses_Round", "Glasses_Square", "Glasses_Safety"]
const GLASSES_NAMES: Array[String] = ["Keine", "Rund", "Eckig", "Schutzbrille"]
const BUILDS: Array[String] = ["", "Body_Slim", "Body_Heavy", "Body_Strong"]
const BUILD_NAMES: Array[String] = ["Normal", "Schlank", "Kräftig", "Sportlich"]
const FACE_KEYS: Array[String] = ["jaw", "chin", "cheek", "nose", "long", "round", "brow", "lips", "ears", "neck"]
const FACE_SHAPES := {"jaw": "Face_Jaw", "chin": "Face_Chin", "cheek": "Face_Cheek", "nose": "Face_Nose", "long": "Face_Long", "round": "Face_Round", "brow": "Face_Brow", "lips": "Face_Lips", "ears": "Face_Ears", "neck": "Face_Neck"}
const FACE_NAMES := {"jaw": "Kiefer breit", "chin": "Kinn", "cheek": "Wangen", "nose": "Nase", "long": "Gesicht lang", "round": "Gesicht rund", "brow": "Stirnwulst", "lips": "Lippen", "ears": "Ohren", "neck": "Hals"}
const EXTRAS := {"badge": "Acc_Badge", "belt": "Acc_Belt", "backpack": "Acc_Backpack", "watch": "Acc_Watch", "gloves": "Acc_Gloves"}
const EXTRA_NAMES := {"badge": "Ausweis", "belt": "Werkzeuggürtel", "backpack": "Rucksack", "watch": "Uhr", "gloves": "Handschuhe", "logo": "Firmenlogo"}

const TONES: Array[Color] = [Color("f6ddcb"), Color("eec5a6"), Color("e0aa84"), Color("c98d63"), Color("a9704a"), Color("865234"), Color("5f3a26"), Color("43291c")]
const EYES: Array[Color] = [Color("5a7fa8"), Color("3f6f5a"), Color("6b4a2c"), Color("3b2717"), Color("8a8f94"), Color("7d6a38"), Color("4c8fb8"), Color("2a2a2e")]
const HAIRS: Array[Color] = [Color("17120f"), Color("33221a"), Color("5a3a24"), Color("8a5a32"), Color("b98a4a"), Color("dcbf84"), Color("a3472a"), Color("8f9398"), Color("e6e6e2"), Color("2f5fae"), Color("7a3fb0"), Color("c43f7a")]
const CLOTHES: Array[Color] = [Color("1a1c20"), Color("3a3f46"), Color("7d838b"), Color("c9cdd2"), Color("f0f0ec"), Color("1e2f52"), Color("2f5fae"), Color("5f93cf"), Color("16595f"), Color("2a8f8a"), Color("1f4a2c"), Color("4c8a3c"), Color("9ab84a"), Color("e2c23a"), Color("e8862a"), Color("c4452a"), Color("8a1f24"), Color("a83f6a"), Color("5f3a8a"), Color("4a3324"), Color("8a6a44"), Color("c9ae7e")]

## Grenzen der Zahlenfelder (Auswahl) – alles andere sind Regler 0..100.
const CHOICES := {"tone": 8, "eyes": 8, "hair": 12, "hair_col": 12, "brows": 3, "beard": 5, "build": 4, "top": 10, "bottom": 6, "shoes": 4, "hat": 5, "glasses": 4,
	"top_a": 22, "top_b": 22, "bottom_a": 22, "shoe_a": 22, "acc_a": 22}
const FLAGS: Array[String] = ["badge", "belt", "backpack", "watch", "gloves", "logo"]
const DEFAULT := {"v": 2, "height": 50, "build": 0, "amount": 50, "fem": 0, "tone": 1, "eyes": 0, "hair": 2, "hair_col": 2, "brows": 0, "beard": 0, "top": 4, "top_a": 6, "top_b": 3, "bottom": 0, "bottom_a": 5,
	"shoes": 0, "shoe_a": 1, "hat": 0, "glasses": 0, "acc_a": 14, "badge": 1, "belt": 0, "backpack": 0, "watch": 1, "gloves": 0, "logo": 1,
	"jaw": 20, "chin": 20, "cheek": 10, "nose": 15, "long": 0, "round": 0, "brow": 10, "lips": 25, "ears": 0, "neck": 20}

static var _mats: Dictionary = {}
static var _fabric: NoiseTexture2D
static var _skin_n: NoiseTexture2D

var look: Dictionary = {}
var keep_all := false
var skeleton: Skeleton3D
var rig: HumanRig
var _parts: Dictionary = {}
var _root: Node3D
var _logo: Label3D
var _blink_meshes: Array = []
## Bewegung selbst steuern (Ich-Arme).
var manual := false
var _skip := 0
var _acc := 0.0


static func create(p_look: Dictionary = {}, p_keep_all: bool = false) -> HumanModel:
	var h := HumanModel.new()
	h.keep_all = p_keep_all
	h._load()
	h.apply(p_look if not p_look.is_empty() else DEFAULT)
	return h


func _load() -> void:
	_root = ModelLoader.instantiate_custom_model(MODEL)
	if _root == null:
		_root = Node3D.new()
	_root.rotation.y = PI
	add_child(_root)
	for s in _root.find_children("*", "Skeleton3D", true, false):
		skeleton = s as Skeleton3D
	for m in _root.find_children("*", "MeshInstance3D", true, false):
		_parts[str(m.name)] = m
		(m as MeshInstance3D).visible = false
	if skeleton != null:
		rig = HumanRig.new()
		rig.setup(self, skeleton)


func _process(delta: float) -> void:
	if rig == null or manual or not is_visible_in_tree():
		return
	# Weit weg oder hinter der Kamera reichen weniger Schritte je Sekunde.
	_acc += delta
	_skip -= 1
	if _skip > 0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var to := global_position - cam.global_position
		var dist := to.length()
		var behind := dist > 4.0 and to.dot(-cam.global_basis.z) < -1.0
		_skip = 1 if dist < 14.0 and not behind else (2 if dist < 30.0 and not behind else 5)
	rig.update(minf(_acc, 0.15))
	_acc = 0.0


## Weltgeschwindigkeit an die Figur geben.
func move(world_vel: Vector3) -> void:
	if rig == null:
		return
	var l := global_basis.orthonormalized().inverse() * world_vel
	rig.velocity = Vector2(-l.x, -l.z)


## Höhe der Augen über dem Boden (je nach Körpergröße).
func eye_height() -> float:
	return 1.655 * _root.scale.y


func root_scale() -> float:
	return _root.scale.y


## Aussehen prüfen: fehlende Felder ergänzen, Werte begrenzen. Versteht auch das alte Format.
static func sanitize(raw: Variant) -> Dictionary:
	var d: Dictionary = raw if raw is Dictionary else {}
	var out := DEFAULT.duplicate()
	if int(d.get("v", 1)) < 2 if typeof(d.get("v", 1)) in [TYPE_INT, TYPE_FLOAT] else true:
		d = _from_old(d)
	for k in DEFAULT.keys():
		var v: Variant = d.get(k, DEFAULT[k])
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			v = DEFAULT[k]
		var hi := 100
		if CHOICES.has(k):
			hi = int(CHOICES[k]) - 1
		elif FLAGS.has(k):
			hi = 1
		out[k] = clampi(int(v), 0, hi)
	out["v"] = 2
	return out


## Altes Aussehen (bis v2.9): Jacke, Hose, Haut, Haare, Schuhe, Akzent, Kopfbedeckung, Brille.
static func _from_old(d: Dictionary) -> Dictionary:
	var out := DEFAULT.duplicate()
	if d.is_empty():
		return out
	var gi := func(k: String, hi: int) -> int:
		var v: Variant = d.get(k, 0)
		return clampi(int(v), 0, hi) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0
	out["top_a"] = [6, 15, 13, 5, 10, 1, 4, 9, 18][gi.call("jacket", 8)]
	out["bottom_a"] = [1, 5, 20, 0, 11][gi.call("pants", 4)]
	out["tone"] = [0, 2, 3, 5, 6][gi.call("tone", 4)]
	out["hair_col"] = clampi(gi.call("hair", 8), 0, 11)
	out["acc_a"] = [9, 13, 11, 15, 18, 4][gi.call("accent", 5)]
	var hw: int = gi.call("headwear", 5)
	out["hat"] = [0, 0, 1, 2, 4, 1][hw]
	out["hair"] = 4 if hw == 1 else 2
	out["glasses"] = [0, 2, 3][gi.call("glasses", 2)]
	return out


## Zufälliges, stimmiges Aussehen für Passanten.
static func random_look(sd: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = sd * 7919 + 13
	var d := DEFAULT.duplicate()
	d["fem"] = [0, 0, 85, 100, 20][r.randi() % 5]
	var fem: bool = int(d["fem"]) > 50
	d["height"] = r.randi_range(25, 62) if fem else r.randi_range(35, 90)
	d["build"] = r.randi() % 4
	d["amount"] = r.randi_range(15, 75)
	d["tone"] = r.randi() % 8
	d["eyes"] = r.randi() % 8
	d["hair"] = [8, 9, 10, 11, 5, 9, 8][r.randi() % 7] if fem else [0, 1, 2, 3, 4, 5, 2, 3, 6][r.randi() % 9]
	d["hair_col"] = r.randi() % 9
	d["brows"] = 2 if fem else r.randi() % 2
	d["beard"] = 0 if fem else [0, 0, 1, 2, 3, 4, 0][r.randi() % 7]
	d["top"] = [0, 1, 2, 3, 4, 5, 5][r.randi() % 7]
	d["top_a"] = r.randi() % 22
	d["top_b"] = [3, 4, 0, 1][r.randi() % 4]
	d["bottom"] = [0, 0, 1, 2, 5][r.randi() % 5]
	d["bottom_a"] = [0, 1, 5, 6, 19, 20, 2][r.randi() % 7]
	d["shoes"] = [0, 0, 1, 2][r.randi() % 4]
	d["shoe_a"] = [0, 1, 4, 19, 15][r.randi() % 5]
	d["hat"] = [0, 0, 0, 1, 2][r.randi() % 5]
	d["glasses"] = [0, 0, 0, 1, 2][r.randi() % 5]
	d["acc_a"] = r.randi() % 22
	d["badge"] = 0
	d["logo"] = 0
	d["backpack"] = 1 if r.randf() < 0.22 else 0
	for k in FACE_KEYS:
		d[k] = r.randi_range(0, 70)
	d["long"] = 0 if r.randf() < 0.5 else r.randi_range(0, 80)
	d["round"] = 0 if int(d["long"]) > 10 else r.randi_range(0, 80)
	return d


## Berufe mit fester Kleidung, Gesicht und Körper zufällig nach sd.
static func job_look(job: String, sd: int = 0) -> Dictionary:
	var d := random_look(sd + job.hash() % 1000)
	d["backpack"] = 0
	d["glasses"] = d["glasses"] if int(d["glasses"]) < 3 else 0
	match job:
		"delivery":
			d.merge({"top": 7, "top_a": 8, "acc_a": 14, "bottom": 3, "bottom_a": 1, "shoes": 3, "shoe_a": 19, "hat": 1 if sd % 2 == 0 else 3, "gloves": 1, "belt": 0}, true)
		"technician":
			d.merge({"top": 6, "top_a": 6, "top_b": 0, "bottom": 3, "bottom_a": 0, "shoes": 3, "shoe_a": 0, "hat": 0, "belt": 1, "badge": 1, "acc_a": 13}, true)
		"builder":
			d.merge({"top": 7, "top_a": 1, "acc_a": 13, "bottom": 3, "bottom_a": 20, "shoes": 3, "shoe_a": 20, "hat": 3, "gloves": 1, "belt": 1}, true)
		"guard":
			d.merge({"top": 2, "top_a": 5, "top_b": 4, "bottom": 2, "bottom_a": 0, "shoes": 1, "shoe_a": 0, "hat": 1, "acc_a": 5, "badge": 1, "belt": 1}, true)
		"thief":
			d.merge({"top": 4, "top_a": 0, "top_b": 0, "bottom": 2, "bottom_a": 0, "shoes": 0, "shoe_a": 0, "hat": 2, "acc_a": 0, "gloves": 1, "badge": 0, "watch": 0, "beard": 3 if int(d["fem"]) < 50 else 0}, true)
	return d


func apply(p_look: Variant) -> void:
	look = sanitize(p_look)
	if skeleton == null:
		return
	var show := {"Face": true, "Eyes": true, "Lids": true, "Lips": true, "MouthIn": true}
	show[BROWS[look["brows"]]] = true
	var hat := HATS[look["hat"]]
	var hair := HAIR[look["hair"]]
	# Unter Helm und Mütze verschwindet das Haar (außer langem), unter der Kappe bleibt es flach.
	if hat in ["Hat_Helmet", "Hat_Beanie"] and not (hair in ["Hair_Bob", "Hair_Long"]):
		hair = ""
	elif hat == "Hat_Cap" and not (hair in ["", "Hair_Bob", "Hair_Long", "Hair_Pony"]):
		hair = "Hair_Buzz"
	for n in [hair, hat, BEARDS[look["beard"]], GLASSES[look["glasses"]], TOPS[look["top"]], BOTTOMS[look["bottom"]], SHOES[look["shoes"]]]:
		if n != "":
			show[n] = true
	for k in EXTRAS.keys():
		if int(look[k]) == 1:
			show[EXTRAS[k]] = true
	if not show.has("Acc_Gloves"):
		show["Hands"] = true
	if TOPS[look["top"]] in ["Top_Tee", "Top_Polo"]:
		show["Arms"] = true
	if BOTTOMS[look["bottom"]] == "Bottom_Shorts":
		show["Legs"] = true
	for n in _parts.keys():
		var mi: MeshInstance3D = _parts[n]
		if not is_instance_valid(mi):
			continue
		mi.visible = show.has(n)
		if mi.visible:
			_tint(mi)
			_shape(mi)
		elif not keep_all:
			mi.queue_free()
	if not keep_all:
		for n in _parts.keys():
			if not show.has(n):
				_parts.erase(n)
	if _parts.has("Hair_Buzz"):
		_set_key(_parts["Hair_Buzz"], "Under_Hat", 1.0 if hat == "Hat_Cap" else 0.0)
	_root.scale = Vector3.ONE * lerpf(0.90, 1.07, float(look["height"]) / 100.0)
	_blink_meshes.clear()
	for n in ["Face", "Lids", "Lips", "MouthIn", "Beard_Short", "Beard_Full", "Beard_Goatee"] + BROWS:
		if _parts.has(n) and (_parts[n] as MeshInstance3D).visible:
			_blink_meshes.append(_parts[n])
	_update_logo()


func _update_logo() -> void:
	var want := int(look["logo"]) == 1 and not (TOPS[look["top"]] in ["Top_Suit"])
	if not want:
		if _logo != null:
			_logo.visible = false
		return
	if _logo == null:
		var at := BoneAttachment3D.new()
		at.bone_name = "Spine2"
		skeleton.add_child(at)
		_logo = Label3D.new()
		_logo.font_size = 40
		_logo.pixel_size = 0.00034
		_logo.outline_size = 6
		_logo.width = 300
		_logo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_logo.visibility_range_end = 9.0
		at.add_child(_logo)
	if _logo != null:
		var rest := skeleton.get_bone_global_rest(skeleton.find_bone("Spine2"))
		var grow: float = 0.012 if TOPS[look["top"]] in ["Top_Tee", "Top_Polo", "Top_Shirt"] else 0.032
		_logo.transform = rest.affine_inverse() * Transform3D(Basis(Vector3.RIGHT, -0.10) * Basis(Vector3.UP, 0.22), Vector3(0.070, 1.362, 0.092 + grow))
	_logo.visible = true
	var nm := str(GameState.current_save_name)
	_logo.text = nm.to_upper().substr(0, 22) if nm != "" else "DCT"
	var lum := CLOTHES[look["top_a"]].get_luminance()
	_logo.modulate = Color(0.08, 0.09, 0.11) if lum > 0.45 else Color(0.95, 0.96, 0.97)
	_logo.outline_modulate = Color(0, 0, 0, 0)


func _color_for(mat: String) -> Color:
	match mat:
		"Skin":
			return TONES[look["tone"]]
		"Lip":
			var tn := TONES[look["tone"]]
			return tn.lerp(Color(0.62, 0.22, 0.24), 0.34 + 0.14 * float(look["fem"]) / 100.0)
		"Eye_Iris":
			return EYES[look["eyes"]]
		"Hair":
			return HAIRS[look["hair_col"]]
		"Top_A":
			return CLOTHES[look["top_a"]]
		"Top_B":
			return CLOTHES[look["top_b"]]
		"Top_C":
			return CLOTHES[look["top_a"]].darkened(0.55)
		"Bottom_A":
			return CLOTHES[look["bottom_a"]]
		"Bottom_B":
			return CLOTHES[look["bottom_a"]].darkened(0.5)
		"Shoe_A":
			return CLOTHES[look["shoe_a"]]
		"Shoe_B":
			return CLOTHES[look["shoe_a"]].lerp(Color(0.92, 0.92, 0.90), 0.8) if CLOTHES[look["shoe_a"]].get_luminance() < 0.6 else Color(0.22, 0.23, 0.25)
		"Acc_A":
			return CLOTHES[look["acc_a"]]
	return Color(-1, 0, 0)


func _tint(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(s) as StandardMaterial3D
		if src == null:
			continue
		var nm := src.resource_name
		var col := _color_for(nm)
		if col.r < 0.0:
			col = src.albedo_color
		var key := "%s|%s" % [nm, col.to_html(false)]
		if not _mats.has(key):
			_mats[key] = _make(nm, src, col)
		mi.set_surface_override_material(s, _mats[key])


static func _make(nm: String, src: StandardMaterial3D, col: Color) -> StandardMaterial3D:
	var m := src.duplicate() as StandardMaterial3D
	m.resource_name = nm
	m.albedo_color = col
	m.vertex_color_use_as_albedo = nm == "Skin" or nm == "Hair"
	m.vertex_color_is_srgb = true
	if nm.begins_with("Top_") or nm.begins_with("Bottom_") or nm == "Acc_A":
		m.normal_enabled = true
		m.normal_texture = _noise(false)
		m.normal_scale = 0.35
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * 9.0
		m.roughness = 0.88
	elif nm == "Skin":
		m.normal_enabled = true
		m.normal_texture = _noise(true)
		m.normal_scale = 0.12
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * 14.0
		m.roughness = 0.58
		m.rim_enabled = true
		# Kein Subsurface Scattering: Godot legt dafür bei JEDEM Material im Spiel eine zweite Pipeline an (+1,3 GB RAM).
		m.rim = 0.18
		m.rim_tint = 0.6
	elif nm == "Hair":
		m.roughness = 0.55
		m.rim_enabled = true
		m.rim = 0.35
		m.rim_tint = 0.7
	elif nm.begins_with("Eye_"):
		m.roughness = 0.12
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	elif nm == "Glass":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.6, 0.7, 0.8, 0.16)
		m.roughness = 0.03
		m.metallic = 0.0
	return m


static func _noise(skin: bool) -> NoiseTexture2D:
	if skin and _skin_n != null:
		return _skin_n
	if not skin and _fabric != null:
		return _fabric
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR if skin else FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.16 if skin else 0.22
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 3.0
	t.noise = n
	if skin:
		_skin_n = t
	else:
		_fabric = t
	return t


func _set_key(mi: MeshInstance3D, key: String, v: float) -> void:
	var i := mi.find_blend_shape_by_name(key)
	if i >= 0:
		mi.set_blend_shape_value(i, v)


func _shape(mi: MeshInstance3D) -> void:
	var amt := float(look["amount"]) / 100.0
	for i in range(1, BUILDS.size()):
		_set_key(mi, BUILDS[i], amt if int(look["build"]) == i else 0.0)
	_set_key(mi, "Body_Fem", float(look["fem"]) / 100.0)
	if str(mi.name) in ["Face", "Lips"]:
		for k in FACE_KEYS:
			_set_key(mi, FACE_SHAPES[k], float(look[k]) / 100.0)


## Mimik: Werte 0..1 für Blink, Mouth_Open, Smile, Frown, Brow_Up, Brow_Angry, Squint.
func face(key: String, v: float) -> void:
	for mi in _blink_meshes:
		if is_instance_valid(mi):
			_set_key(mi, key, v)
