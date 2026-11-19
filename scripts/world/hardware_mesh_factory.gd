class_name HardwareMeshFactory
extends RefCounted
## Builds authentic, realistic, non-neon 3D PC & Enterprise Server hardware assemblies:
## Motherboards (green/black PCB with capacitors, VRM heatsinks, CMOS battery, rear I/O),
## Real 3D CPUs (silver IHS + LGA socket + finned aluminum/copper heatpipe coolers),
## Real 3D GPUs (PCIe gold fingers, matte shroud, copper pipes, dual fans / Tesla AI accelerators),
## Real 3D RAM DIMM banks, M.2 NVMe SSDs, Hot-Swap PSUs, High-RPM Server Fan Walls,
## Workbench loose parts, and Handheld 3D Hardware Items!


static func get_visual_tier(components: Dictionary, cat: String) -> int:
	if not components.has(cat):
		return 0
	var val: Variant = components[cat]
	if val is String:
		var pd := HardwareCatalog.get_part(cat, str(val))
		return clampi(int(pd.get("vtier", 0)), 0, 3)
	return clampi(int(val), 0, 3)


static func build_open_server_chassis(item_type: String, components: Dictionary, out_fans: Array = []) -> Node3D:
	var root := Node3D.new()
	var steel := MatLib.get_mat("galvanized_steel")
	var dark_steel := MatLib.make_brushed_metal(Color(0.18, 0.19, 0.21), 0.38, 0.65)
	var plastic := MatLib.get_mat("plastic_black")
	var pcb := MatLib.get_mat("pcb_black") if item_type == "gpu_server" else MatLib.get_mat("pcb_green")
	var gold := MatLib.get_mat("gold_contacts")
	var copper := MatLib.get_mat("copper_metal")
	var ic := MatLib.get_mat("ic_chip")
	var alu_fin := MatLib.get_mat("heatsink_aluminum")

	# 1. Realistic 19-inch Galvanized Steel Open-Top 1U/2U Chassis Tray (W=0.76, D=0.72, H=0.14)
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
	for b in range(bay_count):
		var bx := start_x + float(b) * bay_step
		var populated := (b < 2 + stor_lvl * 2) or (item_type == "storage_server")
		_box(root, Vector3(bx, 0.072, 0.362), Vector3(bay_w, 0.092, 0.018), plastic)
		if populated:
			# Silver metal drive pull latch + small amber/green release button
			_box(root, Vector3(bx, 0.072, 0.373), Vector3(bay_w * 0.78, 0.022, 0.012), steel)
			_box(root, Vector3(bx + bay_w * 0.34, 0.072, 0.374), Vector3(0.016, 0.028, 0.014), copper)

	# 2. Realistic Server Motherboard PCB (with standoffs, Rear I/O ports, CMOS battery, Capacitors, Chipset)
	var mb := Node3D.new()
	mb.position = Vector3(-0.04, 0.022, -0.07)
	root.add_child(mb)
	_box(mb, Vector3.ZERO, Vector3(0.58, 0.012, 0.48), pcb)

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

	# 3. REAL 3D CPU + LGA Socket + Upgraded Cooler (at center-left of motherboard)
	var cpu_lvl := get_visual_tier(components, "cpu")
	var cpu_node := build_cpu_assembly(cpu_lvl)
	cpu_node.position = Vector3(-0.07, 0.008, -0.01)
	mb.add_child(cpu_node)

	# 4. REAL 3D RAM DIMM Bank (right beside CPU!)
	var ram_lvl := get_visual_tier(components, "ram")
	var ram_node := build_ram_bank(ram_lvl)
	ram_node.position = Vector3(0.09, 0.008, -0.03)
	mb.add_child(ram_node)

	# 5. REAL 3D GPU (Grafikkarte) in PCIe x16 Slot (left side of motherboard)
	var gpu_lvl := get_visual_tier(components, "gpu")
	if item_type == "gpu_server" and gpu_lvl == 0:
		gpu_lvl = 1 # GPU-AI server always has at least a visible GPU installed!
	var gpu_node := build_gpu_card(gpu_lvl, out_fans)
	gpu_node.position = Vector3(-0.21, 0.008, 0.05)
	mb.add_child(gpu_node)

	# 6. REAL 3D M.2 NVMe SSDs mounted directly on the Motherboard
	var nvme_node := build_storage_module(stor_lvl)
	nvme_node.position = Vector3(0.04, 0.008, 0.14)
	mb.add_child(nvme_node)

	# 7. REAL 3D Server Cooling Fan Wall (between drives & motherboard!)
	var cool_lvl := get_visual_tier(components, "cooling")
	var fan_wall := build_cooling_wall(cool_lvl, out_fans)
	fan_wall.position = Vector3(-0.02, 0.018, 0.21)
	root.add_child(fan_wall)

	# 8. REAL 3D Server PSU Unit (rear-right bay inside chassis!)
	var psu_lvl := get_visual_tier(components, "psu")
	var psu_node := build_psu_unit(psu_lvl)
	psu_node.position = Vector3(0.285, 0.018, -0.17)
	root.add_child(psu_node)

	return root


static func build_cpu_assembly(tier: int) -> Node3D:
	var root := Node3D.new()
	var steel := MatLib.get_mat("galvanized_steel")
	var ihs := MatLib.get_mat("cpu_ihs")
	var gold := MatLib.get_mat("gold_contacts")
	var pcb := MatLib.get_mat("pcb_green")
	var alu_fin := MatLib.get_mat("heatsink_aluminum")
	var cu_fin := MatLib.get_mat("heatsink_copper")
	var copper := MatLib.get_mat("copper_metal")
	var plastic := MatLib.get_mat("plastic_black")

	# Realistic LGA Server Socket Frame + Gold Pin Bed + Retention Lever
	_box(root, Vector3(0.0, 0.006, 0.0), Vector3(0.115, 0.012, 0.115), plastic)
	_box(root, Vector3(0.0, 0.012, 0.0), Vector3(0.095, 0.005, 0.095), gold)
	# CPU Green Substrate + Polished Metallic Silver IHS (Integrated Heat Spreader!)
	_box(root, Vector3(0.0, 0.016, 0.0), Vector3(0.088, 0.006, 0.088), pcb)
	_box(root, Vector3(0.0, 0.022, 0.0), Vector3(0.072, 0.009, 0.072), ihs)
	# Silver LGA Locking Bracket & Side Tension Lever
	_box(root, Vector3(0.0, 0.020, -0.048), Vector3(0.096, 0.008, 0.012), steel)
	_box(root, Vector3(0.0, 0.020, 0.048), Vector3(0.096, 0.008, 0.012), steel)
	_box(root, Vector3(0.062, 0.016, 0.0), Vector3(0.008, 0.008, 0.115), steel)

	if tier == 0:
		# Tier 0: Exposed CPU IHS + low-profile aluminum fin cooler offset slightly or slim open-frame mount so the real CPU is clearly visible!
		_box(root, Vector3(0.0, 0.030, -0.022), Vector3(0.076, 0.014, 0.032), alu_fin)
	elif tier == 1:
		# Tier 1: Precision Aluminum Server Heatsink with 4 steel mounting screws
		_box(root, Vector3(0.0, 0.046, 0.0), Vector3(0.105, 0.042, 0.105), alu_fin)
		for sx in [-0.048, 0.048]:
			for sz in [-0.048, 0.048]:
				_cyl(root, Vector3(float(sx), 0.068, float(sz)), 0.006, 0.012, steel)
	elif tier == 2:
		# Tier 2: Copper Base + 4 Copper Heatpipes + Tall Finned Tower Heatsink
		_box(root, Vector3(0.0, 0.032, 0.0), Vector3(0.096, 0.014, 0.096), copper)
		_box(root, Vector3(0.0, 0.062, 0.0), Vector3(0.112, 0.056, 0.110), alu_fin)
		for hx in [-0.036, -0.012, 0.012, 0.036]:
			_cyl(root, Vector3(float(hx), 0.092, 0.0), 0.006, 0.018, copper)
	else:
		# Tier 3: Enterprise Dual-Socket Skived Copper Server CPU Heatsink Array!
		_box(root, Vector3(0.0, 0.032, 0.0), Vector3(0.125, 0.014, 0.125), copper)
		_box(root, Vector3(0.0, 0.066, 0.0), Vector3(0.122, 0.062, 0.120), cu_fin)
		for hx in [-0.044, -0.022, 0.0, 0.022, 0.044]:
			_cyl(root, Vector3(float(hx), 0.099, -0.03), 0.006, 0.016, copper)
			_cyl(root, Vector3(float(hx), 0.099, 0.03), 0.006, 0.016, copper)
		_box(root, Vector3(0.0, 0.100, 0.0), Vector3(0.126, 0.008, 0.046), steel)

	return root


static func build_gpu_card(tier: int, out_fans: Array = []) -> Node3D:
	var root := Node3D.new()
	var plastic := MatLib.get_mat("plastic_black")
	var steel := MatLib.get_mat("galvanized_steel")
	var shroud := MatLib.make_brushed_metal(Color(0.16, 0.17, 0.19), 0.34, 0.62)
	var pcb_b := MatLib.get_mat("pcb_black")
	var gold := MatLib.get_mat("gold_contacts")
	var copper := MatLib.get_mat("copper_metal")
	var alu_fin := MatLib.get_mat("heatsink_aluminum")
	var cu_fin := MatLib.get_mat("heatsink_copper")

	# PCIe x16 Slot on Motherboard (always present!)
	_box(root, Vector3(0.0, 0.010, 0.0), Vector3(0.020, 0.016, 0.165), plastic)
	_box(root, Vector3(0.0, 0.016, 0.0), Vector3(0.008, 0.006, 0.155), gold)
	# Retention latch at front end of PCIe slot
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
		# Matte black GPU PCB + Gold PCIe Edge Fingers + Metal Rear I/O Bracket
		_box(card, Vector3(0.0, card_h * 0.5, 0.0), Vector3(0.008, card_h, card_len), pcb_b)
		_box(card, Vector3(0.0, 0.002, -0.01), Vector3(0.009, 0.012, 0.13), gold)
		_box(card, Vector3(0.012, card_h * 0.5, -card_len * 0.5 - 0.004), Vector3(0.036, card_h + 0.012, 0.008), steel)

		if tier >= 3:
			# Enterprise Passive Copper/Steel AI Accelerator (H100 / A100 Server Form Factor)
			_box(card, Vector3(0.016, card_h * 0.5, 0.0), Vector3(0.026, card_h - 0.006, card_len - 0.008), shroud)
			_box(card, Vector3(0.016, card_h * 0.5, card_len * 0.42), Vector3(0.028, card_h - 0.014, 0.048), cu_fin)
			_box(card, Vector3(0.016, card_h + 0.002, 0.0), Vector3(0.026, 0.006, card_len * 0.72), copper)
		else:
			# Active Workstation GPU (Matte Metal Shroud + Internal Fin Stack + Spinning Axial Fans!)
			_box(card, Vector3(0.016, card_h * 0.5, 0.0), Vector3(0.024, card_h - 0.006, card_len - 0.010), shroud)
			_box(card, Vector3(0.012, card_h + 0.002, 0.0), Vector3(0.018, 0.007, card_len * 0.76), alu_fin)
			# Exposed copper heatpipe along top edge
			_cyl_z(card, Vector3(0.022, card_h - 0.004, 0.0), 0.0045, card_len * 0.78, copper)
			var fan_count := 2 if tier >= 2 else 1
			for fi in range(fan_count):
				var fz := 0.0 if fan_count == 1 else (-0.062 + float(fi) * 0.124)
				_cyl_x(card, Vector3(0.028, card_h * 0.5, fz), 0.030, 0.006, plastic)
				var rotor := Node3D.new()
				rotor.position = Vector3(0.031, card_h * 0.5, fz)
				rotor.set_meta("spin_axis", "x")
				card.add_child(rotor)
				_box(rotor, Vector3.ZERO, Vector3(0.004, 0.052, 0.010), steel)
				_box(rotor, Vector3.ZERO, Vector3(0.004, 0.010, 0.052), steel)
				out_fans.append(rotor)
			# 8-Pin PCIe Power Plug on top front edge
			_box(card, Vector3(0.010, card_h + 0.008, card_len * 0.34), Vector3(0.018, 0.014, 0.024), plastic)

	# NVLink Metal Bridge connecting twin AI GPUs at Tier 3!
	if tier >= 3:
		_box(root, Vector3(0.038, 0.114, 0.06), Vector3(0.072, 0.012, 0.058), steel)

	return root


static func build_ram_bank(tier: int) -> Node3D:
	var root := Node3D.new()
	var plastic := MatLib.get_mat("plastic_black")
	var pcb := MatLib.get_mat("pcb_green")
	var ic := MatLib.get_mat("ic_chip")
	var gold := MatLib.get_mat("gold_contacts")
	var steel := MatLib.get_mat("galvanized_steel")
	var dark_al := MatLib.make_brushed_metal(Color(0.22, 0.24, 0.27), 0.32, 0.72)

	var populated := clampi(2 + tier * 2, 2, 8)
	for i in range(8):
		var rx := -0.063 + float(i) * 0.018
		# DIMM Slot Base + White/Grey Retention Clips at both ends
		_box(root, Vector3(rx, 0.008, 0.0), Vector3(0.009, 0.012, 0.148), plastic)
		_box(root, Vector3(rx, 0.012, -0.078), Vector3(0.010, 0.018, 0.010), steel)
		_box(root, Vector3(rx, 0.012, 0.078), Vector3(0.010, 0.018, 0.010), steel)

		if i < populated:
			var stick_mat: Material = pcb
			if tier == 1:
				stick_mat = dark_al
			elif tier >= 2:
				stick_mat = steel
			_box(root, Vector3(rx, 0.034, 0.0), Vector3(0.005, 0.044, 0.138), stick_mat)
			_box(root, Vector3(rx, 0.014, 0.0), Vector3(0.006, 0.006, 0.130), gold)
			# Visible Black DRAM Memory ICs on bare Tier 0 sticks
			if tier == 0:
				for c in range(4):
					_box(root, Vector3(rx + 0.003, 0.034, -0.048 + float(c) * 0.032), Vector3(0.003, 0.018, 0.020), ic)

	return root


static func build_storage_module(tier: int) -> Node3D:
	var root := Node3D.new()
	var pcb_b := MatLib.get_mat("pcb_black")
	var ic := MatLib.get_mat("ic_chip")
	var gold := MatLib.get_mat("gold_contacts")
	var steel := MatLib.get_mat("galvanized_steel")
	var alu_fin := MatLib.get_mat("heatsink_aluminum")
	var cu_fin := MatLib.get_mat("heatsink_copper")
	var plastic := MatLib.get_mat("plastic_black")

	var drive_count := clampi(1 + tier, 1, 3)
	for i in range(drive_count):
		var mz := -0.032 + float(i) * 0.034
		# M.2 2280 Slot Connector + Standoff Screw
		_box(root, Vector3(-0.056, 0.009, mz), Vector3(0.014, 0.012, 0.026), plastic)
		_box(root, Vector3(0.0, 0.011, mz), Vector3(0.105, 0.005, 0.024), pcb_b)
		_box(root, Vector3(-0.048, 0.012, mz), Vector3(0.010, 0.006, 0.022), gold)
		_cyl(root, Vector3(0.050, 0.014, mz), 0.004, 0.006, steel)
		if tier >= 3:
			_box(root, Vector3(0.004, 0.018, mz), Vector3(0.088, 0.012, 0.023), cu_fin)
		elif tier >= 2:
			_box(root, Vector3(0.004, 0.017, mz), Vector3(0.088, 0.010, 0.023), alu_fin)
		else:
			# Visible NAND Flash Packages + Silver Controller Chip!
			_box(root, Vector3(-0.024, 0.015, mz), Vector3(0.018, 0.005, 0.016), steel)
			_box(root, Vector3(0.008, 0.015, mz), Vector3(0.024, 0.005, 0.018), ic)
			_box(root, Vector3(0.034, 0.015, mz), Vector3(0.020, 0.005, 0.018), ic)

	return root


static func build_cooling_wall(tier: int, out_fans: Array = []) -> Node3D:
	var root := Node3D.new()
	var plastic := MatLib.get_mat("plastic_black")
	var steel := MatLib.get_mat("galvanized_steel")
	var copper := MatLib.get_mat("copper_metal")
	var cu_fin := MatLib.get_mat("heatsink_copper")

	var fan_count := clampi(3 + tier, 3, 5)
	var spacing := 0.115
	var start_x := -float(fan_count - 1) * spacing * 0.5
	for i in range(fan_count):
		var fx := start_x + float(i) * spacing
		_box(root, Vector3(fx, 0.048, 0.0), Vector3(0.095, 0.092, 0.042), plastic)
		# Fan circular recess & spinning multi-blade rotor
		var rotor := Node3D.new()
		rotor.position = Vector3(fx, 0.048, 0.023)
		root.add_child(rotor)
		_box(rotor, Vector3.ZERO, Vector3(0.072, 0.014, 0.006), steel)
		_box(rotor, Vector3.ZERO, Vector3(0.014, 0.072, 0.006), steel)
		var diag := _box(rotor, Vector3.ZERO, Vector3(0.068, 0.012, 0.006), steel)
		diag.rotation_degrees.z = 45.0
		out_fans.append(rotor)

	if tier >= 3:
		# Liquid Cooling Copper Radiator Manifold + Dual Braided Black Coolant Tubes!
		_box(root, Vector3(0.0, 0.048, -0.034), Vector3(0.56, 0.088, 0.024), cu_fin)
		_cyl_z(root, Vector3(-0.08, 0.096, -0.11), 0.009, 0.18, plastic)
		_cyl_z(root, Vector3(-0.05, 0.096, -0.11), 0.009, 0.18, plastic)
		_cyl(root, Vector3(-0.08, 0.096, -0.03), 0.011, 0.014, copper)
		_cyl(root, Vector3(-0.05, 0.096, -0.03), 0.011, 0.014, copper)

	return root


static func build_psu_unit(tier: int) -> Node3D:
	var root := Node3D.new()
	var steel := MatLib.get_mat("galvanized_steel")
	var perf := MatLib.get_mat("perforated_mesh")
	var plastic := MatLib.get_mat("plastic_black")
	var copper := MatLib.get_mat("copper_metal")
	var handle_mat := MatLib.make_brushed_metal(Color(0.24, 0.56, 0.34), 0.42, 0.30)

	var is_redundant := (tier >= 2)
	if is_redundant:
		# Dual Hot-Swap Redundant Enterprise Server PSUs!
		for u in range(2):
			var ux := -0.034 + float(u) * 0.068
			_box(root, Vector3(ux, 0.048, 0.0), Vector3(0.060, 0.094, 0.32), steel)
			_box(root, Vector3(ux, 0.096, 0.0), Vector3(0.052, 0.005, 0.24), perf)
			# Rear hot-swap pull handle
			_box(root, Vector3(ux, 0.048, -0.172), Vector3(0.046, 0.024, 0.020), handle_mat)
	else:
		_box(root, Vector3(0.0, 0.048, 0.0), Vector3(0.125, 0.092, 0.30), steel)
		_box(root, Vector3(0.0, 0.095, 0.0), Vector3(0.105, 0.006, 0.22), perf)
		_box(root, Vector3(0.0, 0.048, -0.156), Vector3(0.056, 0.036, 0.014), plastic)

	# Braided Power Cable Harness routing to motherboard 24-pin header
	_cyl_z(root, Vector3(-0.04, 0.032, 0.165), 0.010, 0.08, plastic)
	_cyl_z(root, Vector3(-0.02, 0.038, 0.165), 0.008, 0.08, copper)

	return root


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
	if item_type == "web_server" or item_type == "storage_server" or item_type == "gpu_server" or item_type == "net_switch":
		var comps := {"cpu": 1, "gpu": (1 if item_type == "gpu_server" else 0), "ram": 1, "storage": 1, "cooling": 0, "psu": 0}
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
