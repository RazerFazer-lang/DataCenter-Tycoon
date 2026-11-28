extends SceneTree
## Setzt Vorher-/Nachher-Bilder aus tests/_shots_halle2 paarweise nebeneinander (für den Vergleich).
## Aufruf: godot --headless --path . --script res://tests/halle2_collage.gd

const DIR := "res://tests/_shots_halle2"
const PAIRS := [
	["nord_innen_tor", "Innen vom Tor"],
	["nord_innen_ost", "Innen Richtung Osten"],
	["nord_aussen_front", "Einfahrt"],
	["nord_aussen_schraeg", "Gelände schräg"],
	["nord_luft", "Luftbild"],
]


func _initialize() -> void:
	var w := 640
	var h := 360
	var out := Image.create(w * 2 + 12, (h + 8) * PAIRS.size() + 4, false, Image.FORMAT_RGB8)
	out.fill(Color(0.08, 0.09, 0.10))
	var y := 4
	for pr in PAIRS:
		for i in range(2):
			var tag := "vorher" if i == 0 else "nachher"
			var img := Image.load_from_file(ProjectSettings.globalize_path("%s/%s_%s.jpg" % [DIR, tag, pr[0]]))
			if img == null:
				continue
			img.resize(w, h, Image.INTERPOLATE_BILINEAR)
			out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(4 + i * (w + 4), y))
		y += h + 8
	var path := ProjectSettings.globalize_path("%s/vergleich.jpg" % DIR)
	out.save_jpg(path, 0.88)
	print("COLLAGE ", path)
	quit(0)
