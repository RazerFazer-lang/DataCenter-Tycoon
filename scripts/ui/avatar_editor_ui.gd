class_name AvatarEditorUI
extends Control
## Figuren-Editor im Spiel (Pausemenü, Spind): Fenster über der Welt.

signal closed

var panel: SkinEditorPanel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open() -> void:
	if panel == null:
		_build()
	visible = true
	panel.set_preview_active(true)


func close() -> void:
	if not visible:
		return
	visible = false
	panel.set_preview_active(false)
	closed.emit()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.022, 0.026, 0.72)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(980, 620)
	card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_DARK, UIStyle.COL_BORDER, UIStyle.MAX_RADIUS, 1, 22, 18))
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "DEINE FIGUR"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyle.style_label(t, 22, UIStyle.COL_TEXT_MAIN)
	head.add_child(t)
	var done := Button.new()
	done.text = "FERTIG"
	done.custom_minimum_size = Vector2(130, 38)
	UIStyle.style_button(done, Color(0.74, 0.49, 0.12), Color(0.96, 0.72, 0.24))
	done.pressed.connect(close)
	head.add_child(done)
	panel = SkinEditorPanel.new()
	v.add_child(panel)
