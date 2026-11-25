class_name PartThumbs
extends Node
## Kleine 3D-Vorschaubilder der Bauteile. Werden nacheinander gerendert und im Nutzerordner gemerkt.

const SIZE := Vector2i(192, 144)
const VERSION := 1
const DIR := "user://part_thumbs"

static var _inst: PartThumbs
static var _cache: Dictionary = {}

var _queue: Array[String] = []
var _wait := 0
var _cur := ""
var _vp: SubViewport
var _holder: Node3D
var _cam: Camera3D


## Textur sofort, falls vorhanden, sonst eine leere, die später gefüllt wird.
static func get_texture(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var img := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_cache[id] = tex
	if not PartModels.has_product(id):
		return tex
	var path := "%s/%s_%d.png" % [DIR, id, VERSION]
	if FileAccess.file_exists(path):
		var loaded := Image.load_from_file(path)
		if loaded != null and loaded.get_size() == SIZE:
			loaded.convert(Image.FORMAT_RGBA8)
			tex.update(loaded)
			return tex
	if DisplayServer.get_name() == "headless":
		return tex
	if _inst == null or not is_instance_valid(_inst):
		_inst = PartThumbs.new()
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
	_inst._queue.append(id)
	return tex


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.size = SIZE
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	PartViewer.build_studio(_vp)
	_holder = Node3D.new()
	_vp.add_child(_holder)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 1.12
	_cam.position = Vector3(1.6, 1.35, 1.9)
	_vp.add_child(_cam)
	_cam.look_at_from_position(_cam.position, Vector3.ZERO)
	_cam.current = true


func _process(_delta: float) -> void:
	if _cur != "":
		_wait -= 1
		if _wait > 0:
			return
		var img := _vp.get_texture().get_image()
		if img != null and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			if _cache.has(_cur):
				(_cache[_cur] as ImageTexture).update(img)
			img.save_png("%s/%s_%d.png" % [DIR, _cur, VERSION])
		_cur = ""
		for c in _holder.get_children():
			c.queue_free()
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if _queue.is_empty():
		return
	_cur = _queue.pop_front()
	var n := PartModels.product(_cur)
	if n == null:
		_cur = ""
		return
	var b := PartViewer.bounds(n)
	n.position = -b.get_center()
	var h := Node3D.new()
	h.scale = Vector3.ONE * (0.98 / maxf(0.02, b.size.length() * 0.86))
	if HardwareCatalog.find_part_category(_cur) == "gpu":
		h.rotation.y = -PI * 0.42
	elif HardwareCatalog.find_part_category(_cur) == "psu" and b.size.z > b.size.x * 1.6:
		h.rotation.y = PI * 0.75
	h.add_child(n)
	_holder.add_child(h)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_wait = 3
