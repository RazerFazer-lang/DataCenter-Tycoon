class_name BuildingPropFactory
extends RefCounted
## v0.7 Realistic Architectural & Workshop 3D Prop Factory.
## Eliminates blocky primitive placeholders by constructing detailed multi-part 3D furniture,
## heavy-duty workshop shelving (cantilever toolbox, slanted parts bins, flanged cable reels,
## compressed air duster, spare servers), ergonomic 5-caster office chair, articulated dual-monitor
## workstation desk with rolling pedestal, pegboard hardware workbench with bench PSU & hanging tools,
## overhead spiral HVAC ductwork, whiteboard with markers, and organic layered trees!


static func build_heavy_workshop_shelf() -> Node3D:
	var root := Node3D.new()
	var steel := MatLib.make_brushed_metal(Color(0.24, 0.25, 0.27), 0.44, 0.62)
	var galv := MatLib.get_mat("galvanized_steel")
	var wood := MatLib.get_mat("wood_desk")
	var card := MatLib.get_mat("cardboard")
	var plastic_blk := MatLib.get_mat("plastic_black")
	var red_paint := _mat(Color(0.74, 0.16, 0.13), 0.34, 0.44)
	var bin_blue := _mat(Color(0.18, 0.40, 0.62), 0.50, 0.06)
	var bin_grey := _mat(Color(0.36, 0.38, 0.40), 0.52, 0.08)
	var paper := _mat(Color(0.93, 0.92, 0.90), 0.80, 0.0)
	var yellow_cable := _mat(Color(0.84, 0.64, 0.14), 0.46, 0.04)
	var blue_cable := _mat(Color(0.18, 0.44, 0.72), 0.46, 0.04)
	var can_blue := _mat(Color(0.22, 0.48, 0.76), 0.30, 0.55)
	var rubber := _mat(Color(0.11, 0.11, 0.12), 0.84, 0.02)

	# 1. Real Slotted Angle-Iron L-Profile Uprights + Rubber Feet + Cross Braces
	for sx in [-0.26, 0.26]:
		for sz in [-0.76, 0.76]:
			var fx := float(sx)
			var fz := float(sz)
			var sx_in := -1.0 if sx > 0 else 1.0
			var sz_in := -1.0 if sz > 0 else 1.0
			# L-angle steel profile (two thin 8mm flanges instead of thick square blocks!)
			_box(root, Vector3(fx, 1.08, fz + sz_in * 0.018), Vector3(0.008, 2.14, 0.044), steel)
			_box(root, Vector3(fx + sx_in * 0.018, 1.08, fz), Vector3(0.044, 2.14, 0.008), steel)
			# Rubber foot pad
			_box(root, Vector3(fx, 0.015, fz), Vector3(0.056, 0.030, 0.056), rubber)

	# Side horizontal tie-bars & diagonal rear X-bracing struts
	for sz in [-0.76, 0.76]:
		for ty in [0.22, 0.82, 1.42, 2.02]:
			_box(root, Vector3(0.0, float(ty), float(sz)), Vector3(0.54, 0.032, 0.012), steel)
	var brace1 := _box(root, Vector3(-0.265, 1.12, 0.0), Vector3(0.008, 0.022, 2.05), galv)
	brace1.rotation_degrees.x = 46.0
	var brace2 := _box(root, Vector3(-0.265, 1.12, 0.0), Vector3(0.008, 0.022, 2.05), galv)
	brace2.rotation_degrees.x = -46.0

	# 2. Four Steel-Lipped Industrial Shelves (MDF/Oak deck inset inside C-channel steel beam!)
	for sy in [0.22, 0.82, 1.42, 2.02]:
		var fy := float(sy)
		_box(root, Vector3(0.0, fy + 0.008, 0.0), Vector3(0.51, 0.022, 1.50), wood)
		_box(root, Vector3(0.262, fy, 0.0), Vector3(0.014, 0.044, 1.54), steel)
		_box(root, Vector3(-0.262, fy, 0.0), Vector3(0.014, 0.044, 1.54), steel)
		_box(root, Vector3(0.0, fy - 0.012, -0.35), Vector3(0.50, 0.018, 0.024), steel)
		_box(root, Vector3(0.0, fy - 0.012, 0.35), Vector3(0.50, 0.018, 0.024), steel)

	# --- SHELF 1 (BOTTOM, Y=0.24): Spare 1U Server Chassis + Strapped Shipping Cartons ---
	var spare_srv := HardwareMeshFactory.build_open_server_chassis("web_server", {"cpu": 0, "ram": 1, "storage": 1})
	spare_srv.scale = Vector3(0.58, 0.58, 0.58)
	spare_srv.position = Vector3(0.02, 0.245, -0.36)
	spare_srv.rotation_degrees.y = 90.0
	root.add_child(spare_srv)
	# Two realistic strapped spare-parts shipping boxes on right side of bottom shelf
	_box(root, Vector3(0.0, 0.38, 0.36), Vector3(0.42, 0.26, 0.50), card)
	_box(root, Vector3(0.0, 0.38, 0.22), Vector3(0.43, 0.27, 0.016), plastic_blk)
	_box(root, Vector3(0.0, 0.38, 0.50), Vector3(0.43, 0.27, 0.016), plastic_blk)
	_box(root, Vector3(0.214, 0.40, 0.36), Vector3(0.006, 0.12, 0.18), paper)

	# --- SHELF 2 (MIDDLE, Y=0.84): Detailed Steel Cantilever Toolbox + 3 Slanted Open-Front Parts Bins ---
	var tb := Node3D.new()
	tb.position = Vector3(0.02, 0.842, -0.40)
	root.add_child(tb)
	# Lower toolbox chest + 2 drawer fronts with aluminum pulls
	_box(tb, Vector3(0.0, 0.11, 0.0), Vector3(0.32, 0.22, 0.52), red_paint)
	_box(tb, Vector3(0.162, 0.06, 0.0), Vector3(0.010, 0.072, 0.44), red_paint)
	_box(tb, Vector3(0.172, 0.06, 0.0), Vector3(0.012, 0.014, 0.18), galv)
	_box(tb, Vector3(0.162, 0.15, 0.0), Vector3(0.010, 0.072, 0.44), red_paint)
	_box(tb, Vector3(0.172, 0.15, 0.0), Vector3(0.012, 0.014, 0.18), galv)
	# Recessed hinged lid + dual chrome clasp latches + tubular carry handle
	_box(tb, Vector3(0.0, 0.238, 0.0), Vector3(0.33, 0.036, 0.53), red_paint)
	_box(tb, Vector3(0.166, 0.220, -0.15), Vector3(0.014, 0.044, 0.028), galv)
	_box(tb, Vector3(0.166, 0.220, 0.15), Vector3(0.014, 0.044, 0.028), galv)
	_box(tb, Vector3(0.0, 0.275, -0.11), Vector3(0.018, 0.045, 0.018), galv)
	_box(tb, Vector3(0.0, 0.275, 0.11), Vector3(0.018, 0.045, 0.018), galv)
	_cyl_z(tb, Vector3(0.0, 0.298, 0.0), 0.014, 0.24, rubber)

	# 3 Realistic Open-Front Industrial Parts Bins (hollow interior, lowered front lip, paper label + bolts!)
	var bin_zs: Array[float] = [0.06, 0.34, 0.60]
	for b_i in range(bin_zs.size()):
		var bin := Node3D.new()
		bin.position = Vector3(0.03, 0.842, bin_zs[b_i])
		root.add_child(bin)
		var bmat: Material = bin_blue if b_i < 2 else bin_grey
		# Bottom, back, left, right walls + low slanted front lip (hollow inside!)
		_box(bin, Vector3(0.0, 0.012, 0.0), Vector3(0.36, 0.020, 0.22), bmat)
		_box(bin, Vector3(-0.17, 0.095, 0.0), Vector3(0.020, 0.18, 0.22), bmat)
		_box(bin, Vector3(0.0, 0.095, -0.10), Vector3(0.36, 0.18, 0.020), bmat)
		_box(bin, Vector3(0.0, 0.095, 0.10), Vector3(0.36, 0.18, 0.020), bmat)
		_box(bin, Vector3(0.17, 0.052, 0.0), Vector3(0.020, 0.092, 0.22), bmat)
		# White printed SKU label on front lip
		_box(bin, Vector3(0.182, 0.055, 0.0), Vector3(0.004, 0.046, 0.12), paper)
		# Small pile of metallic cage-nuts/screws inside the bin
		for s_i in range(4):
			_cyl(bin, Vector3(-0.04 + float(s_i) * 0.04, 0.032, -0.03 + float(s_i % 2) * 0.06), 0.016, 0.018, galv)

	# --- SHELF 3 (UPPER, Y=1.44): 2 REAL Flanged Cable Reels on Steel Axle + Air Duster Can + Component Boxes ---
	# Horizontal dispenser steel axle rod with brackets
	_cyl_z(root, Vector3(0.0, 1.66, -0.22), 0.014, 0.86, galv)
	_box(root, Vector3(0.0, 1.55, -0.64), Vector3(0.22, 0.23, 0.022), steel)
	_box(root, Vector3(0.0, 1.55, 0.20), Vector3(0.22, 0.23, 0.022), steel)
	for r_i in range(2):
		var rz := -0.44 + float(r_i) * 0.42
		var cmat: Material = yellow_cable if r_i == 0 else blue_cable
		# Two thin wooden/dark flange side discs + recessed wound cable drum between them!
		_cyl_z(root, Vector3(0.0, 1.66, rz - 0.12), 0.185, 0.018, plastic_blk)
		_cyl_z(root, Vector3(0.0, 1.66, rz + 0.12), 0.185, 0.018, plastic_blk)
		for turn in range(5):
			var tz := rz - 0.088 + float(turn) * 0.044
			_cyl_z(root, Vector3(0.0, 1.66, tz), 0.148, 0.038, cmat)

	# Compressed Air Duster Can with spray trigger & thin red straw nozzle!
	var can := Node3D.new()
	can.position = Vector3(0.08, 1.442, 0.42)
	root.add_child(can)
	_cyl(can, Vector3(0.0, 0.11, 0.0), 0.036, 0.22, can_blue)
	_cyl(can, Vector3(0.0, 0.225, 0.0), 0.032, 0.020, galv)
	_box(can, Vector3(0.01, 0.255, 0.0), Vector3(0.048, 0.045, 0.026), plastic_blk)
	var straw := _cyl_x(can, Vector3(0.075, 0.262, 0.0), 0.003, 0.12, red_paint)
	straw.rotation_degrees.z = 82.0

	# Retail Motherboard & GPU Boxes standing neatly on right of Shelf 3
	_box(root, Vector3(-0.02, 1.59, 0.58), Vector3(0.32, 0.29, 0.075), _mat(Color(0.16, 0.18, 0.22), 0.42, 0.08))
	_box(root, Vector3(0.142, 1.62, 0.58), Vector3(0.006, 0.11, 0.055), paper)
	_box(root, Vector3(-0.02, 1.57, 0.67), Vector3(0.30, 0.25, 0.068), _mat(Color(0.22, 0.34, 0.24), 0.44, 0.08))

	# --- SHELF 4 (TOP, Y=2.04): Sealed Spare Equipment & Stacked Storage Drives ---
	_box(root, Vector3(0.0, 2.16, -0.34), Vector3(0.42, 0.22, 0.52), card)
	_box(root, Vector3(0.0, 2.16, -0.34), Vector3(0.43, 0.02, 0.53), plastic_blk)
	for hd in range(4):
		_box(root, Vector3(0.02, 2.06 + float(hd) * 0.038, 0.36), Vector3(0.18, 0.028, 0.26), galv)
		_box(root, Vector3(0.112, 2.06 + float(hd) * 0.038, 0.36), Vector3(0.006, 0.018, 0.16), paper)

	return root


static func build_hardware_workbench() -> Node3D:
	var root := Node3D.new()
	var steel := MatLib.make_brushed_metal(Color(0.22, 0.24, 0.26), 0.44, 0.60)
	var galv := MatLib.get_mat("galvanized_steel")
	var wood := MatLib.get_mat("wood_desk")
	var perf := MatLib.get_mat("perforated_mesh")
	var plastic_blk := MatLib.get_mat("plastic_black")
	var red_h := _mat(Color(0.76, 0.18, 0.14), 0.45, 0.10)
	var blue_h := _mat(Color(0.18, 0.42, 0.68), 0.45, 0.10)
	var yel_h := _mat(Color(0.84, 0.64, 0.14), 0.45, 0.10)
	var lcd_mat := _mat(Color(0.52, 0.64, 0.54), 0.35, 0.05)

	# Heavy Steel Workbench Frame + Butcher-Block Oak Worktop + Lower Shelf
	_box(root, Vector3(0.0, 0.84, 0.0), Vector3(1.56, 0.055, 0.80), wood)
	_box(root, Vector3(0.0, 0.84, 0.402), Vector3(1.56, 0.058, 0.012), steel)
	for bx in [-0.72, 0.72]:
		for bz in [-0.34, 0.34]:
			_box(root, Vector3(float(bx), 0.41, float(bz)), Vector3(0.052, 0.82, 0.052), steel)
		_box(root, Vector3(float(bx), 0.22, 0.0), Vector3(0.044, 0.044, 0.68), steel)
	_box(root, Vector3(0.0, 0.22, 0.0), Vector3(1.42, 0.032, 0.62), wood)

	# Back Perforated Steel Pegboard Tool Panel + Uprights + Overhead Task Light Arm
	for px in [-0.72, 0.72]:
		_box(root, Vector3(float(px), 1.32, -0.37), Vector3(0.044, 0.92, 0.044), steel)
	_box(root, Vector3(0.0, 1.32, -0.37), Vector3(1.42, 0.76, 0.022), perf)
	_box(root, Vector3(0.0, 1.71, -0.37), Vector3(1.48, 0.036, 0.048), steel)
	# Overhead angled industrial workbench light canopy
	_box(root, Vector3(0.0, 1.78, -0.18), Vector3(1.18, 0.042, 0.16), steel)
	_box(root, Vector3(-0.56, 1.76, -0.27), Vector3(0.028, 0.028, 0.22), galv)
	_box(root, Vector3(0.56, 1.76, -0.27), Vector3(0.028, 0.028, 0.22), galv)
	var task_tube := StandardMaterial3D.new()
	task_tube.albedo_color = Color(0.98, 0.97, 0.94)
	task_tube.emission_enabled = true
	task_tube.emission = Color(0.98, 0.96, 0.92)
	task_tube.emission_energy_multiplier = 1.15
	_box(root, Vector3(0.0, 1.755, -0.18), Vector3(1.08, 0.016, 0.08), task_tube)

	# Real Hanging Hand Tools on the Pegboard (3 Screwdrivers, 3 Steel Wrenches, Pliers!)
	var sd_cols: Array[Material] = [red_h, blue_h, yel_h]
	for si in range(3):
		var sx := -0.52 + float(si) * 0.085
		_cyl(root, Vector3(sx, 1.48, -0.345), 0.013, 0.10, sd_cols[si])
		_cyl(root, Vector3(sx, 1.36, -0.345), 0.0038, 0.14, galv)
	for wi in range(3):
		var wx := -0.12 + float(wi) * 0.09
		var wh := 0.18 + float(wi) * 0.035
		_box(root, Vector3(wx, 1.42, -0.348), Vector3(0.018, wh, 0.008), galv)
		_cyl_z(root, Vector3(wx, 1.42 + wh * 0.5, -0.348), 0.020, 0.010, galv)
		_cyl_z(root, Vector3(wx, 1.42 - wh * 0.5, -0.348), 0.018, 0.010, galv)

	# Benchtop Lab DC Power Supply / Multimeter Unit on Left-Back Corner
	var psu := Node3D.new()
	psu.position = Vector3(-0.56, 0.95, -0.20)
	psu.rotation_degrees.y = 18.0
	root.add_child(psu)
	_box(psu, Vector3.ZERO, Vector3(0.24, 0.16, 0.24), _mat(Color(0.76, 0.77, 0.75), 0.48, 0.15))
	_box(psu, Vector3(0.0, 0.03, 0.122), Vector3(0.18, 0.06, 0.008), lcd_mat)
	_cyl_z(psu, Vector3(-0.055, -0.035, 0.126), 0.016, 0.018, plastic_blk)
	_cyl_z(psu, Vector3(0.005, -0.035, 0.126), 0.016, 0.018, plastic_blk)
	_cyl_z(psu, Vector3(0.065, -0.035, 0.124), 0.009, 0.014, red_h)
	_cyl_z(psu, Vector3(0.092, -0.035, 0.124), 0.009, 0.014, plastic_blk)

	# Full 3D ESD Mat + Open Server Motherboard + Loose 3D CPU + Dual-Fan GPU + RAM + Paste!
	var hw_display := HardwareMeshFactory.build_workbench_display()
	hw_display.position = Vector3(0.12, 0.870, 0.04)
	root.add_child(hw_display)

	return root


static func build_office_chair() -> Node3D:
	var root := Node3D.new()
	var chrome := MatLib.get_mat("galvanized_steel")
	var dark_metal := MatLib.make_brushed_metal(Color(0.16, 0.17, 0.19), 0.42, 0.58)
	var fabric := _mat(Color(0.18, 0.19, 0.21), 0.86, 0.02)
	var mesh_back := MatLib.get_mat("perforated_mesh")
	var rubber := _mat(Color(0.10, 0.10, 0.11), 0.82, 0.02)

	# 1. Realistic 5-Star Swivel Base with 5 Cylindrical Rolling Caster Wheels!
	_cyl(root, Vector3(0.0, 0.12, 0.0), 0.036, 0.09, dark_metal)
	for i in range(5):
		var ang := float(i) * (TAU / 5.0)
		var arm := Node3D.new()
		arm.rotation.y = ang
		root.add_child(arm)
		var leg := _box(arm, Vector3(0.0, 0.092, 0.14), Vector3(0.036, 0.026, 0.28), dark_metal)
		leg.rotation_degrees.x = 7.0
		# Caster fork & dual wheel cylinder
		_cyl(arm, Vector3(0.0, 0.058, 0.265), 0.012, 0.035, chrome)
		_cyl_x(arm, Vector3(0.0, 0.030, 0.265), 0.028, 0.034, rubber)

	# 2. Chrome Pneumatic Gas-Lift Piston + Bellows + Tilt Mechanism Box
	_cyl(root, Vector3(0.0, 0.26, 0.0), 0.024, 0.26, chrome)
	_cyl(root, Vector3(0.0, 0.20, 0.0), 0.032, 0.14, rubber)
	_box(root, Vector3(0.0, 0.415, 0.02), Vector3(0.18, 0.055, 0.22), dark_metal)

	# 3. Contoured Ergonomic Seat Cushion (base shell + plush rounded waterfall cushion)
	_box(root, Vector3(0.0, 0.455, 0.0), Vector3(0.46, 0.028, 0.45), dark_metal)
	_box(root, Vector3(0.0, 0.482, 0.01), Vector3(0.48, 0.056, 0.44), fabric)
	_cyl_x(root, Vector3(0.0, 0.478, -0.21), 0.028, 0.48, fabric)

	# 4. Curved Spine Bar + Mesh Backrest Frame + Lumbar Bar + Headrest
	_box(root, Vector3(0.0, 0.56, 0.24), Vector3(0.072, 0.24, 0.032), dark_metal)
	var spine := _box(root, Vector3(0.0, 0.44, 0.15), Vector3(0.072, 0.032, 0.22), dark_metal)
	spine.rotation_degrees.x = -12.0

	var back := Node3D.new()
	back.position = Vector3(0.0, 0.80, 0.23)
	back.rotation_degrees.x = -7.0
	root.add_child(back)
	# Perimeter ergonomic frame + breathable mesh center + lumbar support + headrest!
	_box(back, Vector3(-0.21, 0.0, 0.0), Vector3(0.036, 0.54, 0.034), dark_metal)
	_box(back, Vector3(0.21, 0.0, 0.0), Vector3(0.036, 0.54, 0.034), dark_metal)
	_box(back, Vector3(0.0, 0.26, 0.0), Vector3(0.45, 0.038, 0.036), dark_metal)
	_box(back, Vector3(0.0, -0.26, 0.0), Vector3(0.45, 0.038, 0.036), dark_metal)
	_box(back, Vector3(0.0, 0.0, -0.004), Vector3(0.40, 0.49, 0.016), mesh_back)
	_box(back, Vector3(0.0, -0.10, -0.016), Vector3(0.38, 0.075, 0.022), fabric)
	# Headrest neck & curved cushion
	_box(back, Vector3(0.0, 0.31, 0.005), Vector3(0.06, 0.08, 0.022), dark_metal)
	_box(back, Vector3(0.0, 0.38, -0.008), Vector3(0.26, 0.11, 0.048), fabric)

	# 5. Dual T-Armrests with Soft Pads
	for ax in [-0.265, 0.265]:
		var fx := float(ax)
		_box(root, Vector3(fx * 0.72, 0.445, 0.0), Vector3(0.14, 0.026, 0.036), dark_metal)
		_box(root, Vector3(fx, 0.545, 0.0), Vector3(0.030, 0.21, 0.038), dark_metal)
		_box(root, Vector3(fx, 0.658, -0.02), Vector3(0.064, 0.026, 0.26), rubber)

	return root


static func build_terminal_desk_details(root: Node3D) -> void:
	var wood := MatLib.get_mat("wood_desk")
	var metal := MatLib.make_brushed_metal(Color(0.16, 0.17, 0.19), 0.40, 0.60)
	var galv := MatLib.get_mat("galvanized_steel")
	var pad := _mat(Color(0.13, 0.14, 0.16), 0.88, 0.0)
	var key_mat := _mat(Color(0.24, 0.25, 0.27), 0.66, 0.04)
	var key_light := _mat(Color(0.36, 0.37, 0.39), 0.62, 0.04)
	var mug_mat := _mat(Color(0.88, 0.87, 0.84), 0.28, 0.04)
	var coffee := _mat(Color(0.12, 0.07, 0.04), 0.12, 0.02)

	# 1. Under-Desk 3-Drawer Steel Rolling Pedestal Cabinet (Right Side)
	var ped := Node3D.new()
	ped.position = Vector3(0.64, 0.0, 0.02)
	root.add_child(ped)
	_box(ped, Vector3(0.0, 0.34, 0.0), Vector3(0.42, 0.60, 0.56), metal)
	for dy in [0.14, 0.34, 0.53]:
		_box(ped, Vector3(0.0, float(dy), 0.284), Vector3(0.38, 0.165, 0.012), _mat(Color(0.22, 0.23, 0.25), 0.46, 0.45))
		_box(ped, Vector3(0.0, float(dy) + 0.02, 0.298), Vector3(0.14, 0.014, 0.016), galv)
	for cx in [-0.16, 0.16]:
		for cz in [-0.22, 0.22]:
			_cyl_x(ped, Vector3(float(cx), 0.024, float(cz)), 0.022, 0.026, pad)

	# 2. Articulated Dual-Monitor Steel Desk Clamp Arm (replaces floating blocks!)
	_box(root, Vector3(-0.34, 0.815, -0.40), Vector3(0.10, 0.06, 0.10), metal)
	_cyl(root, Vector3(-0.34, 1.06, -0.40), 0.020, 0.48, galv)
	# Horizontal jointed arm reaching to primary monitor (-0.10, 1.24, -0.18) & side monitor (-0.74, 1.20, -0.08)
	_box(root, Vector3(-0.22, 1.22, -0.30), Vector3(0.28, 0.032, 0.032), metal)
	_box(root, Vector3(-0.54, 1.20, -0.26), Vector3(0.44, 0.032, 0.032), metal)

	# 3. Sculpted Mechanical Keyboard (angled aluminum wedge + 5 sculpted keycap clusters!)
	var kb := Node3D.new()
	kb.position = Vector3(-0.18, 0.830, 0.16)
	kb.rotation_degrees.x = 5.5
	root.add_child(kb)
	_box(kb, Vector3.ZERO, Vector3(0.44, 0.020, 0.145), metal)
	for row in range(4):
		var rz := -0.044 + float(row) * 0.026
		_box(kb, Vector3(-0.04, 0.015, rz), Vector3(0.28, 0.012, 0.019), key_mat)
		_box(kb, Vector3(0.155, 0.015, rz), Vector3(0.075, 0.012, 0.019), key_light)
	# Spacebar + Escape accent key
	_box(kb, Vector3(-0.04, 0.015, 0.052), Vector3(0.15, 0.012, 0.019), key_light)
	_box(kb, Vector3(-0.195, 0.015, -0.044), Vector3(0.022, 0.013, 0.019), _mat(Color(0.76, 0.24, 0.18), 0.55, 0.05))

	# 4. Sculpted Ergonomic Mouse (rounded sphere shell + scroll wheel)
	var mouse := Node3D.new()
	mouse.position = Vector3(0.19, 0.828, 0.16)
	root.add_child(mouse)
	var ms := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.042
	sph.height = 0.064
	ms.mesh = sph
	ms.scale = Vector3(0.82, 0.58, 1.38)
	ms.material_override = metal
	ms.position = Vector3(0.0, 0.012, 0.0)
	mouse.add_child(ms)
	_cyl_x(mouse, Vector3(0.0, 0.026, -0.026), 0.008, 0.008, galv)

	# 5. Articulated Architect Desk Lamp (Left Back Corner)
	var lamp := Node3D.new()
	lamp.position = Vector3(-0.80, 0.818, -0.28)
	lamp.rotation_degrees.y = -32.0
	root.add_child(lamp)
	_cyl(lamp, Vector3(0.0, 0.014, 0.0), 0.078, 0.024, metal)
	var arm1 := _cyl(lamp, Vector3(0.0, 0.16, -0.03), 0.008, 0.30, galv)
	arm1.rotation_degrees.x = -14.0
	var arm2 := _cyl(lamp, Vector3(0.0, 0.34, 0.06), 0.008, 0.26, galv)
	arm2.rotation_degrees.x = 58.0
	var shade := MeshInstance3D.new()
	var scm := CylinderMesh.new()
	scm.top_radius = 0.028
	scm.bottom_radius = 0.075
	scm.height = 0.10
	shade.mesh = scm
	shade.material_override = metal
	shade.position = Vector3(0.0, 0.37, 0.17)
	shade.rotation_degrees.x = 24.0
	lamp.add_child(shade)

	# 6. Ceramic Coffee Mug with real C-Handle & Coffee Liquid Inside!
	var mug := Node3D.new()
	mug.position = Vector3(-0.68, 0.818, 0.22)
	root.add_child(mug)
	_cyl(mug, Vector3(0.0, 0.048, 0.0), 0.040, 0.096, mug_mat)
	_cyl(mug, Vector3(0.0, 0.090, 0.0), 0.034, 0.016, coffee)
	# Curved handle loop on side of mug
	_box(mug, Vector3(0.044, 0.070, 0.0), Vector3(0.022, 0.010, 0.012), mug_mat)
	_box(mug, Vector3(0.052, 0.048, 0.0), Vector3(0.010, 0.052, 0.012), mug_mat)
	_box(mug, Vector3(0.044, 0.026, 0.0), Vector3(0.022, 0.010, 0.012), mug_mat)

	# 7. Gaming-PC-Tower: hohles Gehäuse mit Glas-Seitenwand (zeigt zum Schreibtisch, -X),
	# damit Mainboard, Kühler, RAM, Grafikkarte und RGB-Lüfter tatsächlich sichtbar sind.
	var pc := Node3D.new()
	pc.position = Vector3(0.68, 0.818, -0.10)
	root.add_child(pc)
	var case_mat := MatLib.make_brushed_metal(Color(0.07, 0.07, 0.08), 0.42, 0.55)
	var shroud := MatLib.make_brushed_metal(Color(0.12, 0.12, 0.13), 0.36, 0.70)
	var fins := MatLib.get_mat("heatsink_aluminum")
	var pcb := MatLib.get_mat("pcb_black")
	var perf := MatLib.get_mat("perforated_mesh")
	var fan_dark := _mat(Color(0.04, 0.04, 0.05), 0.55, 0.10)
	var rgb_a := _emissive(Color(0.15, 0.75, 1.0), 1.8)
	var rgb_b := _emissive(Color(0.55, 0.30, 1.0), 1.8)
	var case_glass := StandardMaterial3D.new()
	case_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	case_glass.albedo_color = Color(0.06, 0.07, 0.09, 0.22)
	case_glass.roughness = 0.04
	case_glass.metallic_specular = 0.9

	# Gummifüße
	for fx in [-0.10, 0.10]:
		for fz in [-0.19, 0.19]:
			_cyl(pc, Vector3(float(fx), 0.012, float(fz)), 0.018, 0.022, pad)

	# Gehäuse-Schale: Boden, Deckel, rechte Wand, Rückwand, Glasrahmen und Glasscheibe
	_box(pc, Vector3(0.0, 0.029, 0.0), Vector3(0.24, 0.014, 0.46), case_mat)
	_box(pc, Vector3(0.0, 0.493, 0.0), Vector3(0.24, 0.014, 0.46), case_mat)
	_box(pc, Vector3(0.113, 0.26, 0.0), Vector3(0.014, 0.45, 0.46), case_mat)
	_box(pc, Vector3(0.0, 0.26, -0.223), Vector3(0.212, 0.45, 0.014), case_mat)
	_box(pc, Vector3(-0.113, 0.26, 0.222), Vector3(0.014, 0.45, 0.016), case_mat)
	_box(pc, Vector3(-0.113, 0.26, -0.222), Vector3(0.014, 0.45, 0.016), case_mat)
	_box(pc, Vector3(-0.115, 0.26, 0.0), Vector3(0.006, 0.45, 0.428), case_glass)

	# Front: Mesh-Gitter mit senkrechten LED-Streifen, dahinter drei RGB-Lüfter
	_box(pc, Vector3(0.0, 0.26, 0.226), Vector3(0.212, 0.45, 0.008), perf)
	_box(pc, Vector3(-0.108, 0.26, 0.232), Vector3(0.006, 0.42, 0.006), rgb_a)
	_box(pc, Vector3(0.108, 0.26, 0.232), Vector3(0.006, 0.42, 0.006), rgb_a)
	for fy in [0.18, 0.295, 0.41]:
		_rgb_fan(pc, Vector3(0.0, float(fy), 0.200), 0.055, 0.025, rgb_a, fan_dark, shroud)

	# Mainboard auf der Innenseite der rechten Wand
	_box(pc, Vector3(0.103, 0.29, -0.03), Vector3(0.006, 0.40, 0.36), pcb)

	# CPU-Turmkühler mit RGB-Lüfter und Abdeckkappe
	_box(pc, Vector3(0.050, 0.37, -0.06), Vector3(0.09, 0.11, 0.05), fins)
	_box(pc, Vector3(0.003, 0.37, -0.06), Vector3(0.004, 0.11, 0.05), shroud)
	_box(pc, Vector3(0.000, 0.37, -0.06), Vector3(0.002, 0.012, 0.04), rgb_b)
	_rgb_fan(pc, Vector3(0.050, 0.37, -0.022), 0.048, 0.020, rgb_b, fan_dark, shroud)

	# Zwei RAM-Riegel mit leuchtender Oberkante
	for rz in [0.005, 0.018]:
		_box(pc, Vector3(0.078, 0.37, float(rz)), Vector3(0.044, 0.13, 0.008), fan_dark)
		_box(pc, Vector3(0.053, 0.37, float(rz)), Vector3(0.006, 0.13, 0.008), rgb_a)

	# Grafikkarte: Kühler-Shroud, Backplate, LED-Streifen zur Glasseite, zwei Lüfter unten
	_box(pc, Vector3(0.035, 0.225, -0.03), Vector3(0.13, 0.05, 0.28), shroud)
	_box(pc, Vector3(0.035, 0.252, -0.03), Vector3(0.13, 0.004, 0.28), fan_dark)
	_box(pc, Vector3(-0.031, 0.235, -0.03), Vector3(0.003, 0.010, 0.24), rgb_a)
	for gz in [-0.09, 0.03]:
		_cyl(pc, Vector3(0.035, 0.198, float(gz)), 0.038, 0.004, fan_dark)

	# Netzteil-Abdeckung mit Leuchtstreifen
	_box(pc, Vector3(0.0, 0.078, 0.0), Vector3(0.212, 0.084, 0.43), shroud)
	_box(pc, Vector3(-0.107, 0.078, 0.05), Vector3(0.002, 0.012, 0.12), rgb_b)

	# Hecklüfter
	_rgb_fan(pc, Vector3(0.02, 0.37, -0.200), 0.050, 0.025, rgb_b, fan_dark, shroud)

	# Deckel: Lüftungsgitter, leuchtender Power-Button, USB-Port
	_box(pc, Vector3(0.0, 0.501, -0.04), Vector3(0.17, 0.002, 0.30), perf)
	_cyl(pc, Vector3(-0.07, 0.503, 0.18), 0.009, 0.006, rgb_a)
	_box(pc, Vector3(-0.02, 0.502, 0.18), Vector3(0.016, 0.006, 0.010), _mat(Color(0.16, 0.44, 0.78), 0.4, 0.2))

	# Schwaches Innenlicht ohne Schatten: färbt Hardware und Tischplatte leicht ein, kostet kaum GPU-Zeit.
	var case_light := OmniLight3D.new()
	case_light.position = Vector3(0.0, 0.30, 0.0)
	case_light.light_color = Color(0.45, 0.55, 1.0)
	case_light.light_energy = 0.35
	case_light.omni_range = 0.45
	case_light.shadow_enabled = false
	pc.add_child(case_light)


static func build_hvac_ceiling_ducts(parent: Node3D) -> void:
	var galv := MatLib.get_mat("galvanized_steel")
	var strap := MatLib.make_brushed_metal(Color(0.32, 0.34, 0.36), 0.45, 0.65)
	var grille := MatLib.get_mat("perforated_mesh")

	# Main Overhead Galvanized Spiral HVAC Air Duct running across Garage + Hall B + Hall C!
	_cyl_x(parent, Vector3(8.0, 3.44, 2.75), 0.20, 25.4, galv)
	for jx in [-3.5, 0.5, 4.5, 8.5, 12.5, 16.5, 20.0]:
		var fx := float(jx)
		# Flanged collar ring + dual ceiling suspension straps
		_cyl_x(parent, Vector3(fx, 3.44, 2.75), 0.222, 0.045, strap)
		_box(parent, Vector3(fx, 3.66, 2.56), Vector3(0.024, 0.38, 0.012), strap)
		_box(parent, Vector3(fx, 3.66, 2.94), Vector3(0.024, 0.38, 0.012), strap)
		# Downward square air diffuser register box
		_box(parent, Vector3(fx, 3.22, 2.75), Vector3(0.32, 0.08, 0.28), galv)
		_box(parent, Vector3(fx, 3.175, 2.75), Vector3(0.28, 0.014, 0.24), grille)


static func build_whiteboard_tray(wb: Node3D) -> void:
	var alu := MatLib.get_mat("galvanized_steel")
	var white := _mat(Color(0.92, 0.92, 0.90), 0.4, 0.05)
	var cap_blk := _mat(Color(0.12, 0.12, 0.13), 0.4, 0.05)
	var cap_red := _mat(Color(0.78, 0.16, 0.14), 0.4, 0.05)
	var cap_blu := _mat(Color(0.16, 0.40, 0.72), 0.4, 0.05)
	var felt := _mat(Color(0.22, 0.24, 0.26), 0.85, 0.0)

	# Extruded aluminum marker rail at bottom of whiteboard
	_box(wb, Vector3(0.0, -0.52, 0.055), Vector3(1.62, 0.024, 0.075), alu)
	_box(wb, Vector3(0.0, -0.502, 0.090), Vector3(1.62, 0.026, 0.012), alu)

	# 3 Cylindrical Whiteboard Markers with colored caps
	var caps: Array[Material] = [cap_blk, cap_red, cap_blu]
	for i in range(3):
		var mx := -0.45 + float(i) * 0.18
		_cyl_x(wb, Vector3(mx, -0.498, 0.055), 0.010, 0.11, white)
		_cyl_x(wb, Vector3(mx + 0.058, -0.498, 0.055), 0.011, 0.032, caps[i])

	# Magnetic felt whiteboard eraser
	_box(wb, Vector3(0.38, -0.488, 0.056), Vector3(0.13, 0.032, 0.048), cap_blu)
	_box(wb, Vector3(0.38, -0.504, 0.056), Vector3(0.13, 0.012, 0.048), felt)


static func build_realistic_tree(parent: Node3D, pos: Vector3) -> void:
	var trunk_mat := _mat(Color(0.32, 0.24, 0.17), 0.92, 0.0)
	var leaf_dark := _mat(Color(0.18, 0.34, 0.15), 0.88, 0.0)
	var leaf_mid := _mat(Color(0.24, 0.42, 0.18), 0.86, 0.0)
	var leaf_light := _mat(Color(0.30, 0.48, 0.21), 0.84, 0.0)

	# Tapered trunk + 3 angled branches
	var trunk := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.13
	tc.bottom_radius = 0.24
	tc.height = 2.3
	trunk.mesh = tc
	trunk.material_override = trunk_mat
	trunk.position = pos + Vector3(0.0, 1.15, 0.0)
	parent.add_child(trunk)

	var branch_offsets: Array = [
		{"off": Vector3(-0.38, 2.15, 0.22), "rot": Vector3(14.0, 0.0, 32.0)},
		{"off": Vector3(0.40, 2.25, -0.18), "rot": Vector3(-12.0, 0.0, -34.0)},
		{"off": Vector3(0.08, 2.30, 0.34), "rot": Vector3(28.0, 0.0, -8.0)},
	]
	for bo in branch_offsets:
		var bd: Dictionary = bo
		var br := _cyl(parent, pos + (bd["off"] as Vector3), 0.065, 1.05, trunk_mat)
		br.rotation_degrees = bd["rot"]

	# Multi-cluster organic layered foliage canopy (5 overlapping varied lobes!)
	var clusters: Array = [
		{"p": Vector3(0.0, 2.95, 0.0), "r": 1.15, "m": leaf_dark},
		{"p": Vector3(-0.78, 2.60, 0.35), "r": 0.92, "m": leaf_mid},
		{"p": Vector3(0.82, 2.70, -0.28), "r": 0.96, "m": leaf_mid},
		{"p": Vector3(0.12, 2.65, 0.72), "r": 0.85, "m": leaf_dark},
		{"p": Vector3(0.18, 3.65, -0.12), "r": 0.88, "m": leaf_light},
	]
	for cl in clusters:
		var cd: Dictionary = cl
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = float(cd["r"])
		sm.height = float(cd["r"]) * 1.55
		sm.radial_segments = 14
		sm.rings = 8
		mi.mesh = sm
		mi.material_override = cd["m"]
		mi.position = pos + (cd["p"] as Vector3)
		parent.add_child(mi)


static func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


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


## Runder Lüfter mit Blickrichtung Z: schmaler leuchtender Ring, 7 schräg gestellte Rotorblätter, Nabe in der Mitte.
static func _rgb_fan(parent: Node3D, pos: Vector3, rad: float, depth: float, ring: Material, blades: Material, hub: Material) -> void:
	var fan := Node3D.new()
	fan.position = pos
	parent.add_child(fan)

	var ring_mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = rad * 0.86
	tm.outer_radius = rad
	tm.rings = 32
	tm.ring_segments = 8
	ring_mi.mesh = tm
	ring_mi.material_override = ring
	ring_mi.rotation_degrees.x = 90.0
	fan.add_child(ring_mi)

	var blade_count := 7
	var bm := BoxMesh.new()
	bm.size = Vector3(rad * 0.58, rad * 0.30, 0.002)
	for i in range(blade_count):
		var pivot := Node3D.new()
		pivot.rotation.z = TAU * float(i) / float(blade_count)
		fan.add_child(pivot)
		var blade := MeshInstance3D.new()
		blade.mesh = bm
		blade.material_override = blades
		blade.position = Vector3(rad * 0.52, 0.0, 0.0)
		blade.rotation_degrees.x = 28.0
		pivot.add_child(blade)

	_disc_z(fan, Vector3.ZERO, rad * 0.30, depth, hub)


static func _disc_z(parent: Node3D, pos: Vector3, rad: float, depth: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rad
	cm.bottom_radius = rad
	cm.height = depth
	cm.radial_segments = 32
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees.x = 90.0
	parent.add_child(mi)
	return mi


static func _emissive(col: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(col.darkened(0.6), 0.4, 0.0)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


static func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m
