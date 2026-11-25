class_name UnpackFx
extends Node3D
## Auspack-Animation: Karton öffnet sich, das Gerät wächst heraus, der Karton rutscht an seinen Ablageplatz.
## Reine Anzeige auf jedem Rechner. Der leere Karton selbst kommt danach vom Server.

const TOTAL := 2.1

var _t := 0.0
var _device: Node3D
var _carton: Node3D
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _sounds := 0


func start(device: Node3D, kind: String, carton_pos: Vector3) -> void:
	_device = device
	_from = Vector3(device.global_position.x, maxf(0.0, device.global_position.y if device.global_position.y < 0.2 else 0.0), device.global_position.z)
	_to = carton_pos
	_carton = CartonFactory.build(kind)
	add_child(_carton)
	_carton.global_position = _from
	_carton.rotation.y = device.rotation.y
	_device.scale = Vector3.ONE * 0.02
	_device.visible = false
	SfxManager.play("tape_rip", -6.0, randf_range(0.94, 1.06))


func _process(delta: float) -> void:
	_t += delta
	if not is_instance_valid(_device) or not is_instance_valid(_carton):
		_finish()
		return
	# 0,25–0,95 s Klappen auf
	CartonFactory.set_open(_carton, clampf((_t - 0.25) / 0.70, 0.0, 1.0))
	if _sounds == 0 and _t > 0.30:
		_sounds = 1
		SfxManager.play("carton_open", -5.0, randf_range(0.95, 1.08))
	# 0,8–1,7 s Gerät kommt heraus: erst hoch, dann volle Größe mit leichtem Nachfedern
	var g := clampf((_t - 0.80) / 0.90, 0.0, 1.0)
	if g > 0.0:
		_device.visible = true
		var e := 1.0 - pow(1.0 - g, 3.0)
		var bounce := 1.0 + sin(g * PI) * 0.06
		_device.scale = Vector3(maxf(0.05, e), maxf(0.05, e * bounce), maxf(0.05, e))
	if _sounds == 1 and g >= 1.0:
		_sounds = 2
		SfxManager.play("part_set", -4.0, 0.7)
	# ab 1,0 s rutscht der Karton zur Seite
	var m := clampf((_t - 1.00) / 0.85, 0.0, 1.0)
	var ms := m * m * (3.0 - 2.0 * m)
	_carton.global_position = _from.lerp(_to, ms) + Vector3.UP * sin(ms * PI) * 0.16
	_carton.rotation.z = sin(ms * PI) * 0.10
	if _t >= TOTAL:
		_finish()


func _finish() -> void:
	if is_instance_valid(_device):
		_device.scale = Vector3.ONE
		_device.visible = true
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_device):
		_device.scale = Vector3.ONE
		_device.visible = true
