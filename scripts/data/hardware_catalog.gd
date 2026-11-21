class_name HardwareCatalog
extends RefCounted
## v1.1 Authentic Enterprise & Retro Hardware Catalog (185 Parts across 6 Categories)
## Covers DDR2 -> DDR5 RAM, Dual-Core -> 128-Core CPUs, Onboard -> Dual H200 GPUs,
## 500 GB HDD -> 128 TB All-Flash NVMe, 350W -> 2400W Titanium PSUs, Air -> Liquid Cooling,
## plus 6 Rack Rental Service Profiles with real per-user resource demand & customer templates.

const CATEGORY_ORDER: Array[String] = ["cpu", "ram", "gpu", "storage", "cooling", "psu"]

const CATEGORY_META := {
	"cpu": {"label": "Prozessor (CPU)", "short": "CPU", "icon": "🧠"},
	"ram": {"label": "Arbeitsspeicher (RAM)", "short": "RAM", "icon": "🧩"},
	"gpu": {"label": "Grafikkarte (GPU)", "short": "GPU", "icon": "🎮"},
	"storage": {"label": "Speicher (HDD/SSD/NVMe)", "short": "Speicher", "icon": "💾"},
	"cooling": {"label": "Kühlung", "short": "Kühlung", "icon": "❄"},
	"psu": {"label": "Netzteil (PSU)", "short": "Netzteil", "icon": "🔌"},
}

const DEFAULT_PARTS := {
	"cpu": "cpu_celeron_2c",
	"ram": "ram_ddr2_2gb",
	"gpu": "gpu_onboard",
	"storage": "sto_hdd_500gb",
	"cooling": "cool_box_40mm",
	"psu": "psu_350w_std",
}

const CATEGORY_FILTERS := {
	"cpu": ["Alle", "Entry", "Server", "Enterprise"],
	"ram": ["Alle", "DDR2", "DDR3", "DDR4", "DDR5"],
	"gpu": ["Alle", "Entry", "RTX", "Datacenter"],
	"storage": ["Alle", "HDD", "SSD", "NVMe"],
	"cooling": ["Alle", "Luft", "Liquid"],
	"psu": ["Alle", "350–650W", "750–2400W"],
}

# Fresh empty/barebones Chassis start with minimal entry hardware so players buy real parts in the PC Shop!
const SERVER_DEFAULT_PARTS := {
	"web_server": {
		"cpu": "cpu_celeron_2c",
		"ram": "ram_ddr2_2gb",
		"gpu": "gpu_onboard",
		"storage": "sto_hdd_500gb",
		"cooling": "cool_box_40mm",
		"psu": "psu_350w_std",
	},
	"storage_server": {
		"cpu": "cpu_celeron_2c",
		"ram": "ram_ddr2_2gb",
		"gpu": "gpu_onboard",
		"storage": "sto_hdd_500gb",
		"cooling": "cool_box_40mm",
		"psu": "psu_350w_std",
	},
	"gpu_server": {
		"cpu": "cpu_celeron_2c",
		"ram": "ram_ddr2_2gb",
		"gpu": "gpu_onboard",
		"storage": "sto_hdd_500gb",
		"cooling": "cool_box_40mm",
		"psu": "psu_350w_std",
	},
}

const PARTS := {
	"cpu": [
		{"id": "cpu_celeron_2c", "name": "Celeron G1840 (2C • 2.8 GHz)", "tag": "Budget", "vtier": 0, "cost": 0, "cpu_score": 12, "compute": 4, "watts": 45, "heat": 1.5, "fault_mult": 1.0},
		{"id": "cpu_pentium_g4560", "name": "Pentium G4560 (2C/4T • 3.5 GHz)", "tag": "Budget", "vtier": 0, "cost": 40, "cpu_score": 17, "compute": 6, "watts": 54, "heat": 2.0, "fault_mult": 1.0},
		{"id": "cpu_c2q_4c", "name": "Core 2 Quad Q6600 (4C • 2.4 GHz)", "tag": "Legacy", "vtier": 0, "cost": 65, "cpu_score": 22, "compute": 8, "watts": 85, "heat": 3.0, "fault_mult": 1.0},
		{"id": "cpu_athlon_3000g", "name": "Athlon 3000G (2C/4T • 3.5 GHz)", "tag": "Budget", "vtier": 0, "cost": 80, "cpu_score": 26, "compute": 9, "watts": 35, "heat": 1.6, "fault_mult": 0.99},
		{"id": "cpu_i3_10100", "name": "Core i3-10100 (4C/8T • 4.3 GHz)", "tag": "Entry", "vtier": 0, "cost": 95, "cpu_score": 30, "compute": 11, "watts": 65, "heat": 2.6, "fault_mult": 0.97},
		{"id": "cpu_xeon_4c", "name": "Xeon X3440 (4C/8T • 2.9 GHz)", "tag": "Entry", "vtier": 0, "cost": 110, "cpu_score": 34, "compute": 12, "watts": 95, "heat": 3.5, "fault_mult": 0.96},
		{"id": "cpu_xeon_e3_1230", "name": "Xeon E3-1230 v6 (4C/8T • 3.9 GHz)", "tag": "Entry", "vtier": 0, "cost": 135, "cpu_score": 41, "compute": 14, "watts": 72, "heat": 3.0, "fault_mult": 0.95},
		{"id": "cpu_ryzen5_5600", "name": "Ryzen 5 5600 (6C/12T • 4.4 GHz)", "tag": "Mid", "vtier": 1, "cost": 160, "cpu_score": 48, "compute": 17, "watts": 65, "heat": 2.9, "fault_mult": 0.95},
		{"id": "cpu_i5_6c", "name": "Core i5-10400 (6C/12T • 4.3 GHz)", "tag": "Mid", "vtier": 1, "cost": 175, "cpu_score": 52, "compute": 18, "watts": 75, "heat": 3.2, "fault_mult": 0.95},
		{"id": "cpu_i7_12700", "name": "Core i7-12700 (12C/20T • 4.9 GHz)", "tag": "Mid", "vtier": 1, "cost": 210, "cpu_score": 64, "compute": 22, "watts": 125, "heat": 4.4, "fault_mult": 0.93},
		{"id": "cpu_xeon_e2388g", "name": "Xeon E-2388G (8C/16T • 5.1 GHz)", "tag": "Server", "vtier": 1, "cost": 225, "cpu_score": 68, "compute": 23, "watts": 95, "heat": 4.0, "fault_mult": 0.92},
		{"id": "cpu_xeon_6c", "name": "Xeon E5-2630 v3 (8C/16T • 3.2 GHz)", "tag": "Server", "vtier": 1, "cost": 240, "cpu_score": 72, "compute": 25, "watts": 95, "heat": 4.2, "fault_mult": 0.92},
		{"id": "cpu_epyc_7302p", "name": "EPYC 7302P (16C/32T • 3.3 GHz)", "tag": "Server", "vtier": 1, "cost": 290, "cpu_score": 84, "compute": 29, "watts": 155, "heat": 5.0, "fault_mult": 0.91},
		{"id": "cpu_xeon_silver_4314", "name": "Xeon Silver 4314 (16C/32T • 3.4 GHz)", "tag": "Server", "vtier": 1, "cost": 320, "cpu_score": 92, "compute": 32, "watts": 135, "heat": 5.0, "fault_mult": 0.90},
		{"id": "cpu_xeon_14c", "name": "Xeon E5-2680 v4 (14C/28T • 3.3 GHz)", "tag": "Server", "vtier": 1, "cost": 360, "cpu_score": 105, "compute": 36, "watts": 120, "heat": 5.5, "fault_mult": 0.90},
		{"id": "cpu_ryzen9_5950x", "name": "Ryzen 9 5950X (16C/32T • 4.9 GHz)", "tag": "High-Clock", "vtier": 2, "cost": 430, "cpu_score": 125, "compute": 42, "watts": 105, "heat": 6.0, "fault_mult": 0.89},
		{"id": "cpu_i9_14900k", "name": "Core i9-14900K (24C/32T • 6.0 GHz)", "tag": "High-Clock", "vtier": 2, "cost": 495, "cpu_score": 142, "compute": 47, "watts": 253, "heat": 9.0, "fault_mult": 0.86},
		{"id": "cpu_ryzen9_16c", "name": "Ryzen 9 7950X (16C/32T • 5.7 GHz)", "tag": "High-Clock", "vtier": 2, "cost": 540, "cpu_score": 155, "compute": 50, "watts": 165, "heat": 7.5, "fault_mult": 0.88},
		{"id": "cpu_xeon_w5_3435x", "name": "Xeon w5-3435X (16C/32T • 4.7 GHz)", "tag": "High-Clock", "vtier": 2, "cost": 640, "cpu_score": 178, "compute": 57, "watts": 270, "heat": 8.5, "fault_mult": 0.87},
		{"id": "cpu_epyc_4564p", "name": "EPYC 4564P (16C/32T • 5.7 GHz)", "tag": "Server", "vtier": 2, "cost": 700, "cpu_score": 190, "compute": 61, "watts": 170, "heat": 7.4, "fault_mult": 0.86},
		{"id": "cpu_epyc_24c", "name": "EPYC 7413P (24C/48T • 3.6 GHz)", "tag": "Enterprise", "vtier": 2, "cost": 790, "cpu_score": 210, "compute": 68, "watts": 180, "heat": 8.0, "fault_mult": 0.85},
		{"id": "cpu_tr_7970x", "name": "Threadripper 7970X (32C/64T • 5.3 GHz)", "tag": "Enterprise", "vtier": 2, "cost": 960, "cpu_score": 245, "compute": 78, "watts": 350, "heat": 11.0, "fault_mult": 0.84},
		{"id": "cpu_xeon_gold_6548y", "name": "Xeon Gold 6548Y+ (32C/64T • 4.1 GHz)", "tag": "Enterprise", "vtier": 2, "cost": 1080, "cpu_score": 268, "compute": 85, "watts": 250, "heat": 10.0, "fault_mult": 0.83},
		{"id": "cpu_xeon_32c", "name": "Xeon Gold 6430 (32C/64T • 3.4 GHz)", "tag": "Enterprise", "vtier": 2, "cost": 1180, "cpu_score": 290, "compute": 92, "watts": 240, "heat": 10.5, "fault_mult": 0.82},
		{"id": "cpu_epyc_9354", "name": "EPYC 9354 Genoa (32C/64T • 3.8 GHz)", "tag": "Enterprise", "vtier": 2, "cost": 1420, "cpu_score": 330, "compute": 104, "watts": 280, "heat": 11.5, "fault_mult": 0.81},
		{"id": "cpu_tr_pro_7985wx", "name": "Threadripper PRO 7985WX (64C/128T)", "tag": "Datacenter", "vtier": 3, "cost": 1720, "cpu_score": 395, "compute": 122, "watts": 350, "heat": 13.0, "fault_mult": 0.80},
		{"id": "cpu_epyc_64c", "name": "EPYC 9554 Genoa (64C/128T • 3.7 GHz)", "tag": "Datacenter", "vtier": 3, "cost": 1950, "cpu_score": 440, "compute": 135, "watts": 310, "heat": 13.5, "fault_mult": 0.78},
		{"id": "cpu_xeon_6780e", "name": "Xeon 6780E Sierra Forest (144C)", "tag": "Datacenter", "vtier": 3, "cost": 2300, "cpu_score": 500, "compute": 152, "watts": 330, "heat": 13.8, "fault_mult": 0.76},
		{"id": "cpu_xeon_64c", "name": "Xeon Platinum 8592+ (64C/128T)", "tag": "Datacenter", "vtier": 3, "cost": 2650, "cpu_score": 560, "compute": 165, "watts": 340, "heat": 14.5, "fault_mult": 0.74},
		{"id": "cpu_epyc_9654", "name": "EPYC 9654 Genoa (96C/192T)", "tag": "Datacenter", "vtier": 3, "cost": 3200, "cpu_score": 650, "compute": 190, "watts": 360, "heat": 15.5, "fault_mult": 0.73},
		{"id": "cpu_xeon_6980p", "name": "Xeon 6980P Granite Rapids (128C)", "tag": "Flagship", "vtier": 3, "cost": 3800, "cpu_score": 740, "compute": 212, "watts": 500, "heat": 17.5, "fault_mult": 0.71},
		{"id": "cpu_epyc_128c", "name": "EPYC 9754 Bergamo (128C/256T)", "tag": "Flagship", "vtier": 3, "cost": 4200, "cpu_score": 820, "compute": 230, "watts": 360, "heat": 16.5, "fault_mult": 0.70},
	],
	"ram": [
		{"id": "ram_ddr2_2gb", "name": "2 GB DDR2-667 Value", "tag": "DDR2", "vtier": 0, "cost": 0, "ram_gb": 2, "compute": 1, "watts": 8, "heat": 0.4, "fault_mult": 1.0},
		{"id": "ram_ddr2_4gb", "name": "4 GB DDR2-800 ECC Kit", "tag": "DDR2", "vtier": 0, "cost": 35, "ram_gb": 4, "compute": 2, "watts": 12, "heat": 0.5, "fault_mult": 0.98},
		{"id": "ram_ddr2_6gb", "name": "6 GB DDR2-800 Triple-Kit", "tag": "DDR2", "vtier": 0, "cost": 45, "ram_gb": 6, "compute": 3, "watts": 14, "heat": 0.6, "fault_mult": 0.97},
		{"id": "ram_ddr2_8gb", "name": "8 GB DDR2-1066 Server Kit", "tag": "DDR2", "vtier": 0, "cost": 60, "ram_gb": 8, "compute": 4, "watts": 16, "heat": 0.8, "fault_mult": 0.96},
		{"id": "ram_ddr2_16gb", "name": "16 GB DDR2-667 FB-DIMM Server", "tag": "DDR2", "vtier": 0, "cost": 95, "ram_gb": 16, "compute": 5, "watts": 28, "heat": 1.4, "fault_mult": 0.95},
		{"id": "ram_ddr3_4gb", "name": "4 GB DDR3-1066 Value", "tag": "DDR3", "vtier": 1, "cost": 50, "ram_gb": 4, "compute": 3, "watts": 10, "heat": 0.5, "fault_mult": 0.97},
		{"id": "ram_ddr3_8gb", "name": "8 GB DDR3-1333 Non-ECC", "tag": "DDR3", "vtier": 1, "cost": 75, "ram_gb": 8, "compute": 6, "watts": 14, "heat": 0.7, "fault_mult": 0.96},
		{"id": "ram_ddr3_12gb", "name": "12 GB DDR3-1600 Triple-Channel", "tag": "DDR3", "vtier": 1, "cost": 98, "ram_gb": 12, "compute": 8, "watts": 16, "heat": 0.8, "fault_mult": 0.95},
		{"id": "ram_ddr3_16gb", "name": "16 GB DDR3-1600 ECC Server", "tag": "DDR3", "vtier": 1, "cost": 120, "ram_gb": 16, "compute": 10, "watts": 18, "heat": 0.9, "fault_mult": 0.94},
		{"id": "ram_ddr3_24gb", "name": "24 GB DDR3-1600 ECC Hexa-Kit", "tag": "DDR3", "vtier": 1, "cost": 150, "ram_gb": 24, "compute": 12, "watts": 21, "heat": 1.0, "fault_mult": 0.93},
		{"id": "ram_ddr3_32gb", "name": "32 GB DDR3-1866 Reg-ECC", "tag": "DDR3", "vtier": 1, "cost": 185, "ram_gb": 32, "compute": 15, "watts": 24, "heat": 1.2, "fault_mult": 0.91},
		{"id": "ram_ddr3_64gb", "name": "64 GB DDR3-1866 LRDIMM", "tag": "DDR3", "vtier": 1, "cost": 280, "ram_gb": 64, "compute": 22, "watts": 34, "heat": 1.7, "fault_mult": 0.89},
		{"id": "ram_ddr3_96gb", "name": "96 GB DDR3-1600 Reg-ECC", "tag": "DDR3", "vtier": 1, "cost": 390, "ram_gb": 96, "compute": 27, "watts": 42, "heat": 2.1, "fault_mult": 0.87},
		{"id": "ram_ddr4_8gb", "name": "8 GB DDR4-2133 Value", "tag": "DDR4", "vtier": 2, "cost": 85, "ram_gb": 8, "compute": 8, "watts": 12, "heat": 0.6, "fault_mult": 0.94},
		{"id": "ram_ddr4_16gb", "name": "16 GB DDR4-2400 Non-ECC", "tag": "DDR4", "vtier": 2, "cost": 140, "ram_gb": 16, "compute": 13, "watts": 14, "heat": 0.8, "fault_mult": 0.93},
		{"id": "ram_ddr4_32gb", "name": "32 GB DDR4-2666 ECC", "tag": "DDR4", "vtier": 2, "cost": 230, "ram_gb": 32, "compute": 20, "watts": 20, "heat": 1.1, "fault_mult": 0.90},
		{"id": "ram_ddr4_48gb", "name": "48 GB DDR4-2933 ECC", "tag": "DDR4", "vtier": 2, "cost": 290, "ram_gb": 48, "compute": 25, "watts": 24, "heat": 1.3, "fault_mult": 0.89},
		{"id": "ram_ddr4_64gb", "name": "64 GB DDR4-3200 Reg-ECC", "tag": "DDR4", "vtier": 2, "cost": 350, "ram_gb": 64, "compute": 30, "watts": 28, "heat": 1.5, "fault_mult": 0.88},
		{"id": "ram_ddr4_96gb", "name": "96 GB DDR4-3200 ECC Hexa-Kit", "tag": "DDR4", "vtier": 2, "cost": 470, "ram_gb": 96, "compute": 37, "watts": 34, "heat": 1.8, "fault_mult": 0.86},
		{"id": "ram_ddr4_128gb", "name": "128 GB DDR4-3200 Quad-Channel", "tag": "DDR4", "vtier": 2, "cost": 590, "ram_gb": 128, "compute": 44, "watts": 40, "heat": 2.1, "fault_mult": 0.85},
		{"id": "ram_ddr4_192gb", "name": "192 GB DDR4-3200 RDIMM", "tag": "DDR4", "vtier": 2, "cost": 780, "ram_gb": 192, "compute": 53, "watts": 47, "heat": 2.5, "fault_mult": 0.83},
		{"id": "ram_ddr4_256gb", "name": "256 GB DDR4-3600 LRDIMM", "tag": "DDR4", "vtier": 2, "cost": 980, "ram_gb": 256, "compute": 62, "watts": 54, "heat": 2.8, "fault_mult": 0.82},
		{"id": "ram_ddr4_384gb", "name": "384 GB DDR4-2933 LRDIMM", "tag": "DDR4", "vtier": 2, "cost": 1350, "ram_gb": 384, "compute": 74, "watts": 66, "heat": 3.4, "fault_mult": 0.80},
		{"id": "ram_ddr4_512gb", "name": "512 GB DDR4-3200 Octa LRDIMM", "tag": "DDR4", "vtier": 2, "cost": 1780, "ram_gb": 512, "compute": 84, "watts": 80, "heat": 4.2, "fault_mult": 0.79},
		{"id": "ram_ddr5_16gb", "name": "16 GB DDR5-4800 Value", "tag": "DDR5", "vtier": 3, "cost": 170, "ram_gb": 16, "compute": 18, "watts": 13, "heat": 0.7, "fault_mult": 0.90},
		{"id": "ram_ddr5_32gb", "name": "32 GB DDR5-4800 Non-ECC", "tag": "DDR5", "vtier": 3, "cost": 260, "ram_gb": 32, "compute": 26, "watts": 16, "heat": 0.9, "fault_mult": 0.88},
		{"id": "ram_ddr5_64gb", "name": "64 GB DDR5-5200 ECC", "tag": "DDR5", "vtier": 3, "cost": 480, "ram_gb": 64, "compute": 42, "watts": 24, "heat": 1.3, "fault_mult": 0.85},
		{"id": "ram_ddr5_96gb", "name": "96 GB DDR5-5600 ECC", "tag": "DDR5", "vtier": 3, "cost": 690, "ram_gb": 96, "compute": 55, "watts": 30, "heat": 1.7, "fault_mult": 0.84},
		{"id": "ram_ddr5_128gb", "name": "128 GB DDR5-4800 ECC", "tag": "DDR5", "vtier": 3, "cost": 890, "ram_gb": 128, "compute": 66, "watts": 36, "heat": 2.0, "fault_mult": 0.82},
		{"id": "ram_ddr5_192gb", "name": "192 GB DDR5-5600 RDIMM", "tag": "DDR5", "vtier": 3, "cost": 1180, "ram_gb": 192, "compute": 82, "watts": 44, "heat": 2.4, "fault_mult": 0.80},
		{"id": "ram_ddr5_256gb", "name": "256 GB DDR5-5600 RDIMM", "tag": "DDR5", "vtier": 3, "cost": 1520, "ram_gb": 256, "compute": 96, "watts": 52, "heat": 2.8, "fault_mult": 0.78},
		{"id": "ram_ddr5_384gb", "name": "384 GB DDR5-6000 RDIMM", "tag": "DDR5", "vtier": 3, "cost": 2150, "ram_gb": 384, "compute": 122, "watts": 64, "heat": 3.4, "fault_mult": 0.76},
		{"id": "ram_ddr5_512gb", "name": "512 GB DDR5-6400 Octa-Channel", "tag": "DDR5", "vtier": 3, "cost": 2850, "ram_gb": 512, "compute": 145, "watts": 76, "heat": 4.0, "fault_mult": 0.74},
	],
	"gpu": [
		{"id": "gpu_onboard", "name": "Integrierte IPMI-Grafik (VGA)", "tag": "Onboard", "vtier": 0, "cost": 0, "gpu_score": 4, "vram_gb": 0, "compute": 0, "watts": 0, "heat": 0.0, "fault_mult": 1.0},
		{"id": "gpu_gt710", "name": "GeForce GT 710 (2 GB)", "tag": "Entry", "vtier": 0, "cost": 45, "gpu_score": 9, "vram_gb": 2, "compute": 3, "watts": 19, "heat": 0.9, "fault_mult": 1.0},
		{"id": "gpu_gt1030", "name": "GeForce GT 1030 (2 GB)", "tag": "Entry", "vtier": 0, "cost": 95, "gpu_score": 16, "vram_gb": 2, "compute": 6, "watts": 35, "heat": 1.8, "fault_mult": 1.0},
		{"id": "gpu_quadro_p400", "name": "Quadro P400 (2 GB)", "tag": "Entry", "vtier": 0, "cost": 120, "gpu_score": 22, "vram_gb": 2, "compute": 8, "watts": 30, "heat": 1.4, "fault_mult": 0.98},
		{"id": "gpu_gtx1650", "name": "GeForce GTX 1650 (4 GB)", "tag": "Classic", "vtier": 1, "cost": 150, "gpu_score": 30, "vram_gb": 4, "compute": 11, "watts": 75, "heat": 2.8, "fault_mult": 0.98},
		{"id": "gpu_gtx1060", "name": "GeForce GTX 1060 (6 GB)", "tag": "Classic", "vtier": 1, "cost": 180, "gpu_score": 38, "vram_gb": 6, "compute": 14, "watts": 120, "heat": 4.2, "fault_mult": 0.98},
		{"id": "gpu_tesla_p4", "name": "Tesla P4 Inference (8 GB)", "tag": "Encode", "vtier": 1, "cost": 220, "gpu_score": 46, "vram_gb": 8, "compute": 17, "watts": 75, "heat": 3.0, "fault_mult": 0.95},
		{"id": "gpu_arc_a380", "name": "Intel Arc A380 (6 GB)", "tag": "Encode", "vtier": 1, "cost": 240, "gpu_score": 50, "vram_gb": 6, "compute": 18, "watts": 75, "heat": 2.9, "fault_mult": 0.96},
		{"id": "gpu_gtx1660ti", "name": "GeForce GTX 1660 Ti (6 GB)", "tag": "Encode", "vtier": 1, "cost": 260, "gpu_score": 56, "vram_gb": 6, "compute": 20, "watts": 125, "heat": 4.5, "fault_mult": 0.96},
		{"id": "gpu_rtx2060", "name": "GeForce RTX 2060 (6 GB)", "tag": "Mid-AI", "vtier": 1, "cost": 320, "gpu_score": 72, "vram_gb": 6, "compute": 26, "watts": 160, "heat": 5.6, "fault_mult": 0.95},
		{"id": "gpu_t4", "name": "NVIDIA T4 Tensor (16 GB)", "tag": "Enterprise", "vtier": 1, "cost": 380, "gpu_score": 84, "vram_gb": 16, "compute": 31, "watts": 70, "heat": 2.9, "fault_mult": 0.90},
		{"id": "gpu_rtx3060", "name": "GeForce RTX 3060 (12 GB)", "tag": "Mid-AI", "vtier": 1, "cost": 420, "gpu_score": 95, "vram_gb": 12, "compute": 34, "watts": 170, "heat": 6.2, "fault_mult": 0.95},
		{"id": "gpu_rtx3070", "name": "GeForce RTX 3070 (8 GB)", "tag": "Mid-AI", "vtier": 1, "cost": 500, "gpu_score": 115, "vram_gb": 8, "compute": 40, "watts": 220, "heat": 7.4, "fault_mult": 0.94},
		{"id": "gpu_rtx4060ti", "name": "GeForce RTX 4060 Ti (16 GB)", "tag": "Mid-AI", "vtier": 1, "cost": 560, "gpu_score": 125, "vram_gb": 16, "compute": 44, "watts": 165, "heat": 5.8, "fault_mult": 0.94},
		{"id": "gpu_rtx_a4000", "name": "NVIDIA RTX A4000 (16 GB)", "tag": "Enterprise", "vtier": 2, "cost": 650, "gpu_score": 140, "vram_gb": 16, "compute": 50, "watts": 140, "heat": 5.4, "fault_mult": 0.90},
		{"id": "gpu_rtx4070ti", "name": "GeForce RTX 4070 Ti (12 GB)", "tag": "Fast", "vtier": 2, "cost": 740, "gpu_score": 165, "vram_gb": 12, "compute": 56, "watts": 240, "heat": 8.0, "fault_mult": 0.92},
		{"id": "gpu_rtx3090", "name": "GeForce RTX 3090 (24 GB)", "tag": "Prosumer", "vtier": 2, "cost": 980, "gpu_score": 210, "vram_gb": 24, "compute": 70, "watts": 350, "heat": 11.5, "fault_mult": 0.91},
		{"id": "gpu_rtx4080s", "name": "GeForce RTX 4080 Super (16 GB)", "tag": "Fast", "vtier": 2, "cost": 1050, "gpu_score": 225, "vram_gb": 16, "compute": 76, "watts": 320, "heat": 10.5, "fault_mult": 0.91},
		{"id": "gpu_rtx4090", "name": "GeForce RTX 4090 (24 GB)", "tag": "Prosumer", "vtier": 2, "cost": 1350, "gpu_score": 280, "vram_gb": 24, "compute": 92, "watts": 410, "heat": 13.0, "fault_mult": 0.90},
		{"id": "gpu_a40", "name": "NVIDIA A40 Datacenter (48 GB)", "tag": "Enterprise", "vtier": 2, "cost": 1550, "gpu_score": 300, "vram_gb": 48, "compute": 100, "watts": 300, "heat": 10.5, "fault_mult": 0.86},
		{"id": "gpu_rtx6000_ada", "name": "RTX 6000 Ada Generation (48 GB)", "tag": "Enterprise", "vtier": 2, "cost": 1750, "gpu_score": 330, "vram_gb": 48, "compute": 110, "watts": 300, "heat": 10.0, "fault_mult": 0.85},
		{"id": "gpu_rtx5090", "name": "GeForce RTX 5090 (32 GB)", "tag": "Prosumer", "vtier": 2, "cost": 1950, "gpu_score": 360, "vram_gb": 32, "compute": 118, "watts": 575, "heat": 17.0, "fault_mult": 0.88},
		{"id": "gpu_l40s", "name": "NVIDIA L40S Datacenter (48 GB)", "tag": "Enterprise", "vtier": 2, "cost": 2250, "gpu_score": 410, "vram_gb": 48, "compute": 132, "watts": 350, "heat": 11.5, "fault_mult": 0.84},
		{"id": "gpu_mi210", "name": "AMD Instinct MI210 (64 GB HBM2e)", "tag": "AI-Core", "vtier": 3, "cost": 2800, "gpu_score": 480, "vram_gb": 64, "compute": 148, "watts": 300, "heat": 12.0, "fault_mult": 0.82},
		{"id": "gpu_a100", "name": "NVIDIA A100 SXM (80 GB HBM2e)", "tag": "AI-Core", "vtier": 3, "cost": 3600, "gpu_score": 620, "vram_gb": 80, "compute": 185, "watts": 420, "heat": 14.5, "fault_mult": 0.80},
		{"id": "gpu_h100_pcie", "name": "NVIDIA H100 PCIe (80 GB HBM2e)", "tag": "AI-Core", "vtier": 3, "cost": 4500, "gpu_score": 760, "vram_gb": 80, "compute": 222, "watts": 350, "heat": 14.5, "fault_mult": 0.79},
		{"id": "gpu_h100", "name": "NVIDIA H100 NVLink (80 GB HBM3)", "tag": "Hyperscale", "vtier": 3, "cost": 5400, "gpu_score": 920, "vram_gb": 80, "compute": 265, "watts": 620, "heat": 19.5, "fault_mult": 0.78},
		{"id": "gpu_mi300x", "name": "AMD Instinct MI300X (192 GB HBM3)", "tag": "Hyperscale", "vtier": 3, "cost": 6400, "gpu_score": 1050, "vram_gb": 192, "compute": 300, "watts": 750, "heat": 21.5, "fault_mult": 0.77},
		{"id": "gpu_h200", "name": "NVIDIA H200 SXM (141 GB HBM3e)", "tag": "Hyperscale", "vtier": 3, "cost": 7200, "gpu_score": 1180, "vram_gb": 141, "compute": 330, "watts": 700, "heat": 22.0, "fault_mult": 0.76},
		{"id": "gpu_b200", "name": "NVIDIA B200 Blackwell (192 GB HBM3e)", "tag": "Hyperscale", "vtier": 3, "cost": 8200, "gpu_score": 1350, "vram_gb": 192, "compute": 375, "watts": 1000, "heat": 25.5, "fault_mult": 0.76},
		{"id": "gpu_h200_dual", "name": "Dual H200 SXM Cluster (282 GB)", "tag": "Flagship", "vtier": 3, "cost": 8900, "gpu_score": 1500, "vram_gb": 282, "compute": 410, "watts": 980, "heat": 27.0, "fault_mult": 0.75},
	],
	"storage": [
		{"id": "sto_hdd_500gb", "name": "500 GB SATA HDD (5400 RPM)", "tag": "HDD", "vtier": 0, "cost": 0, "storage_tb": 0.5, "io_mult": 0.8, "compute": 1, "watts": 8, "heat": 0.5, "revenue_bonus": 0.0, "fault_mult": 1.0},
		{"id": "sto_hdd_1tb", "name": "1 TB SATA HDD (7200 RPM)", "tag": "HDD", "vtier": 0, "cost": 35, "storage_tb": 1.0, "io_mult": 0.9, "compute": 1, "watts": 9, "heat": 0.6, "revenue_bonus": 0.005, "fault_mult": 0.99},
		{"id": "sto_hdd_2tb", "name": "2 TB SATA HDD (7200 RPM)", "tag": "HDD", "vtier": 0, "cost": 55, "storage_tb": 2.0, "io_mult": 1.0, "compute": 2, "watts": 10, "heat": 0.7, "revenue_bonus": 0.01, "fault_mult": 0.98},
		{"id": "sto_hdd_4tb", "name": "4 TB SATA NAS HDD (5400 RPM)", "tag": "HDD", "vtier": 0, "cost": 85, "storage_tb": 4.0, "io_mult": 1.0, "compute": 3, "watts": 11, "heat": 0.8, "revenue_bonus": 0.015, "fault_mult": 0.97},
		{"id": "sto_sas_600gb_15k", "name": "600 GB SAS HDD (15K RPM)", "tag": "SAS", "vtier": 1, "cost": 95, "storage_tb": 0.6, "io_mult": 1.5, "compute": 3, "watts": 12, "heat": 0.9, "revenue_bonus": 0.015, "fault_mult": 0.95},
		{"id": "sto_sas_4tb", "name": "4 TB Enterprise SAS HDD (10K)", "tag": "SAS", "vtier": 1, "cost": 115, "storage_tb": 4.0, "io_mult": 1.3, "compute": 4, "watts": 14, "heat": 1.0, "revenue_bonus": 0.02, "fault_mult": 0.94},
		{"id": "sto_hdd_8tb", "name": "8 TB Helium HDD (7200 RPM)", "tag": "HDD", "vtier": 1, "cost": 150, "storage_tb": 8.0, "io_mult": 1.1, "compute": 4, "watts": 13, "heat": 1.0, "revenue_bonus": 0.025, "fault_mult": 0.95},
		{"id": "sto_sas_10tb", "name": "10 TB SAS-3 Enterprise HDD", "tag": "SAS", "vtier": 1, "cost": 190, "storage_tb": 10.0, "io_mult": 1.35, "compute": 5, "watts": 15, "heat": 1.1, "revenue_bonus": 0.03, "fault_mult": 0.93},
		{"id": "sto_nas_12tb", "name": "12 TB NAS RAID-5 HDD Array", "tag": "RAID", "vtier": 1, "cost": 220, "storage_tb": 12.0, "io_mult": 1.4, "compute": 6, "watts": 26, "heat": 1.8, "revenue_bonus": 0.04, "fault_mult": 0.92},
		{"id": "sto_hdd_20tb", "name": "20 TB Exos Helium HDD", "tag": "HDD", "vtier": 1, "cost": 320, "storage_tb": 20.0, "io_mult": 1.2, "compute": 7, "watts": 15, "heat": 1.2, "revenue_bonus": 0.05, "fault_mult": 0.92},
		{"id": "sto_raid_48tb", "name": "48 TB 8-Bay RAID-6 HDD Array", "tag": "RAID", "vtier": 2, "cost": 640, "storage_tb": 48.0, "io_mult": 1.6, "compute": 12, "watts": 62, "heat": 3.6, "revenue_bonus": 0.09, "fault_mult": 0.88},
		{"id": "sto_ssd_240gb", "name": "240 GB SATA Boot-SSD", "tag": "SSD", "vtier": 1, "cost": 45, "storage_tb": 0.24, "io_mult": 1.7, "compute": 3, "watts": 3, "heat": 0.2, "revenue_bonus": 0.008, "fault_mult": 0.95},
		{"id": "sto_ssd_480gb", "name": "480 GB SATA Datacenter SSD", "tag": "SSD", "vtier": 1, "cost": 70, "storage_tb": 0.48, "io_mult": 1.85, "compute": 4, "watts": 4, "heat": 0.3, "revenue_bonus": 0.012, "fault_mult": 0.94},
		{"id": "sto_ssd_1tb", "name": "1 TB SATA Enterprise SSD", "tag": "SSD", "vtier": 1, "cost": 110, "storage_tb": 1.0, "io_mult": 2.0, "compute": 6, "watts": 6, "heat": 0.4, "revenue_bonus": 0.02, "fault_mult": 0.92},
		{"id": "sto_ssd_2tb", "name": "2 TB SATA Enterprise SSD", "tag": "SSD", "vtier": 1, "cost": 170, "storage_tb": 2.0, "io_mult": 2.15, "compute": 8, "watts": 8, "heat": 0.5, "revenue_bonus": 0.03, "fault_mult": 0.91},
		{"id": "sto_ssd_4tb", "name": "4 TB Datacenter SATA SSD", "tag": "SSD", "vtier": 1, "cost": 260, "storage_tb": 4.0, "io_mult": 2.3, "compute": 11, "watts": 10, "heat": 0.7, "revenue_bonus": 0.04, "fault_mult": 0.90},
		{"id": "sto_ssd_7tb", "name": "7.68 TB SATA Read-Intensive SSD", "tag": "SSD", "vtier": 2, "cost": 420, "storage_tb": 7.68, "io_mult": 2.4, "compute": 14, "watts": 12, "heat": 0.8, "revenue_bonus": 0.06, "fault_mult": 0.88},
		{"id": "sto_sas_ssd_15tb", "name": "15.36 TB SAS-4 Enterprise SSD", "tag": "SSD", "vtier": 2, "cost": 780, "storage_tb": 15.36, "io_mult": 2.8, "compute": 20, "watts": 16, "heat": 1.1, "revenue_bonus": 0.09, "fault_mult": 0.85},
		{"id": "sto_nvme3_512gb", "name": "512 GB M.2 NVMe PCIe 3.0", "tag": "NVMe Gen3", "vtier": 2, "cost": 75, "storage_tb": 0.512, "io_mult": 2.8, "compute": 7, "watts": 5, "heat": 0.4, "revenue_bonus": 0.015, "fault_mult": 0.92},
		{"id": "sto_nvme3_1tb", "name": "1 TB M.2 NVMe PCIe 3.0", "tag": "NVMe Gen3", "vtier": 2, "cost": 120, "storage_tb": 1.0, "io_mult": 3.0, "compute": 9, "watts": 7, "heat": 0.6, "revenue_bonus": 0.02, "fault_mult": 0.91},
		{"id": "sto_nvme3_2tb", "name": "2 TB M.2 NVMe PCIe 3.0", "tag": "NVMe Gen3", "vtier": 2, "cost": 195, "storage_tb": 2.0, "io_mult": 3.2, "compute": 12, "watts": 9, "heat": 0.8, "revenue_bonus": 0.03, "fault_mult": 0.90},
		{"id": "sto_nvme4_4tb", "name": "4 TB M.2 NVMe PCIe 4.0", "tag": "NVMe Gen4", "vtier": 2, "cost": 300, "storage_tb": 4.0, "io_mult": 3.8, "compute": 17, "watts": 12, "heat": 1.0, "revenue_bonus": 0.045, "fault_mult": 0.88},
		{"id": "sto_nvme4_8tb", "name": "8 TB M.2 NVMe PCIe 4.0 Pro", "tag": "NVMe Gen4", "vtier": 2, "cost": 460, "storage_tb": 8.0, "io_mult": 4.2, "compute": 22, "watts": 16, "heat": 1.4, "revenue_bonus": 0.06, "fault_mult": 0.86},
		{"id": "sto_nvme4_15tb", "name": "15.36 TB U.2 NVMe PCIe 4.0", "tag": "NVMe Gen4", "vtier": 2, "cost": 720, "storage_tb": 15.36, "io_mult": 4.6, "compute": 29, "watts": 22, "heat": 1.8, "revenue_bonus": 0.08, "fault_mult": 0.84},
		{"id": "sto_nvme4_24tb", "name": "24 TB NVMe U.2 RAID-10", "tag": "NVMe RAID", "vtier": 2, "cost": 960, "storage_tb": 24.0, "io_mult": 5.0, "compute": 36, "watts": 28, "heat": 2.2, "revenue_bonus": 0.10, "fault_mult": 0.82},
		{"id": "sto_nvme4_30tb", "name": "30.72 TB U.3 NVMe PCIe 4.0", "tag": "NVMe Gen4", "vtier": 2, "cost": 1240, "storage_tb": 30.72, "io_mult": 5.3, "compute": 42, "watts": 30, "heat": 2.4, "revenue_bonus": 0.115, "fault_mult": 0.81},
		{"id": "sto_nvme5_15tb", "name": "15.36 TB E3.S NVMe PCIe 5.0", "tag": "NVMe Gen5", "vtier": 3, "cost": 1450, "storage_tb": 15.36, "io_mult": 6.0, "compute": 46, "watts": 25, "heat": 2.2, "revenue_bonus": 0.12, "fault_mult": 0.80},
		{"id": "sto_nvme5_30tb", "name": "30.72 TB E3.S NVMe PCIe 5.0", "tag": "NVMe Gen5", "vtier": 3, "cost": 1650, "storage_tb": 30.72, "io_mult": 6.2, "compute": 50, "watts": 32, "heat": 2.6, "revenue_bonus": 0.13, "fault_mult": 0.79},
		{"id": "sto_nvme5_64tb", "name": "64 TB PCIe 5.0 Enterprise NVMe", "tag": "NVMe Gen5", "vtier": 3, "cost": 1850, "storage_tb": 64.0, "io_mult": 6.5, "compute": 56, "watts": 42, "heat": 3.2, "revenue_bonus": 0.14, "fault_mult": 0.78},
		{"id": "sto_nvme5_122tb", "name": "122.88 TB E3.L NVMe PCIe 5.0", "tag": "NVMe Gen5", "vtier": 3, "cost": 2900, "storage_tb": 122.88, "io_mult": 7.2, "compute": 72, "watts": 30, "heat": 3.0, "revenue_bonus": 0.18, "fault_mult": 0.76},
		{"id": "sto_allflash_128tb", "name": "128 TB All-Flash SAN Cluster", "tag": "Flagship", "vtier": 3, "cost": 3400, "storage_tb": 128.0, "io_mult": 8.0, "compute": 82, "watts": 58, "heat": 4.2, "revenue_bonus": 0.20, "fault_mult": 0.74},
	],
	"cooling": [
		{"id": "cool_box_40mm", "name": "Standard 40mm Box-Lüfter", "tag": "Stock", "vtier": 0, "cost": 0, "compute": 0, "watts": 8, "heat": 0.0, "fault_mult": 1.0},
		{"id": "cool_sunon_40mm_hs", "name": "40mm High-Speed Sunon-Lüfter", "tag": "Air", "vtier": 0, "cost": 20, "compute": 0, "watts": 9, "heat": -0.6, "fault_mult": 0.99},
		{"id": "cool_slim_60mm", "name": "Slim 60mm Server-Lüfter", "tag": "Air", "vtier": 0, "cost": 30, "compute": 0, "watts": 10, "heat": -1.0, "fault_mult": 0.99},
		{"id": "cool_alu_tower", "name": "Alu-Tower-Kühler 92mm", "tag": "Air", "vtier": 0, "cost": 50, "compute": 0, "watts": 12, "heat": -1.8, "fault_mult": 0.98},
		{"id": "cool_dual_80mm", "name": "Dual 80mm Kugellager-Lüfter", "tag": "Air", "vtier": 0, "cost": 65, "compute": 0, "watts": 14, "heat": -2.5, "fault_mult": 0.96},
		{"id": "cool_dual_92mm", "name": "Dual 92mm PWM-Lüfter", "tag": "Air", "vtier": 0, "cost": 85, "compute": 0, "watts": 15, "heat": -3.2, "fault_mult": 0.95},
		{"id": "cool_blower_1u", "name": "1U Radial-Blower Kühler", "tag": "Airflow", "vtier": 0, "cost": 105, "compute": 0, "watts": 20, "heat": -4.0, "fault_mult": 0.94},
		{"id": "cool_tower_120", "name": "Single-Tower 120mm Heatpipe", "tag": "Copper", "vtier": 1, "cost": 120, "compute": 0, "watts": 16, "heat": -4.5, "fault_mult": 0.93},
		{"id": "cool_copper_hp", "name": "Vollkupfer-Heatpipe Kühler", "tag": "Copper", "vtier": 1, "cost": 140, "compute": 0, "watts": 18, "heat": -5.0, "fault_mult": 0.92},
		{"id": "cool_ducted_shroud", "name": "Luftleit-Shroud + 4× 60mm", "tag": "Airflow", "vtier": 1, "cost": 160, "compute": 0, "watts": 22, "heat": -5.5, "fault_mult": 0.91},
		{"id": "cool_2u_active", "name": "2U Active Heatpipe-Block", "tag": "Copper", "vtier": 1, "cost": 175, "compute": 0, "watts": 20, "heat": -6.0, "fault_mult": 0.90},
		{"id": "cool_dual_tower", "name": "Dual-Tower 140mm Kühler", "tag": "Copper", "vtier": 1, "cost": 210, "compute": 0, "watts": 21, "heat": -6.8, "fault_mult": 0.88},
		{"id": "cool_noctua", "name": "Noctua Industrial 3000 RPM", "tag": "Silent-Pro", "vtier": 1, "cost": 240, "compute": 0, "watts": 22, "heat": -7.5, "fault_mult": 0.86},
		{"id": "cool_noctua_nhu14s", "name": "Noctua NH-U14S DX-4677", "tag": "Silent-Pro", "vtier": 1, "cost": 280, "compute": 0, "watts": 18, "heat": -8.5, "fault_mult": 0.85},
		{"id": "cool_hotswap_fans", "name": "4× Hot-Swap Redundant Fan Kit", "tag": "Airflow", "vtier": 2, "cost": 330, "compute": 0, "watts": 30, "heat": -9.5, "fault_mult": 0.83},
		{"id": "cool_fanwall", "name": "6× High-Static Fan Wall 1U", "tag": "Airflow", "vtier": 2, "cost": 390, "compute": 0, "watts": 36, "heat": -11.0, "fault_mult": 0.82},
		{"id": "cool_fanwall_8x", "name": "8× 80mm Fan Wall 2U", "tag": "Airflow", "vtier": 2, "cost": 460, "compute": 0, "watts": 44, "heat": -12.5, "fault_mult": 0.80},
		{"id": "cool_vapor_2u", "name": "Vapor-Chamber 2U Hochleistungs-Block", "tag": "Vapor", "vtier": 2, "cost": 540, "compute": 0, "watts": 40, "heat": -13.5, "fault_mult": 0.78},
		{"id": "cool_vapor", "name": "Vapor-Chamber Server-Block", "tag": "Vapor", "vtier": 2, "cost": 620, "compute": 0, "watts": 42, "heat": -15.0, "fault_mult": 0.76},
		{"id": "cool_rear_door", "name": "Rear-Door Wärmetauscher (Luft)", "tag": "Airflow", "vtier": 2, "cost": 720, "compute": 0, "watts": 48, "heat": -16.5, "fault_mult": 0.74},
		{"id": "cool_aio_240", "name": "AIO Liquid 240mm Radiator", "tag": "Liquid", "vtier": 3, "cost": 760, "compute": 0, "watts": 40, "heat": -17.0, "fault_mult": 0.72},
		{"id": "cool_aio_360", "name": "AIO Liquid 360mm Radiator", "tag": "Liquid", "vtier": 3, "cost": 880, "compute": 0, "watts": 48, "heat": -18.5, "fault_mult": 0.70},
		{"id": "cool_aio_liquid", "name": "All-in-One Liquid Coldplate", "tag": "Liquid", "vtier": 3, "cost": 980, "compute": 0, "watts": 55, "heat": -20.0, "fault_mult": 0.68},
		{"id": "cool_custom_loop", "name": "Custom-Loop Kupfer-Wasserblock", "tag": "Liquid", "vtier": 3, "cost": 1120, "compute": 0, "watts": 58, "heat": -21.5, "fault_mult": 0.66},
		{"id": "cool_cdu_inrack", "name": "In-Rack CDU Liquid-Kreislauf", "tag": "Liquid", "vtier": 3, "cost": 1280, "compute": 0, "watts": 62, "heat": -23.0, "fault_mult": 0.64},
		{"id": "cool_coldplate_gpu", "name": "Direct-Liquid CPU+GPU Coldplates", "tag": "Liquid", "vtier": 3, "cost": 1420, "compute": 0, "watts": 66, "heat": -25.0, "fault_mult": 0.62},
		{"id": "cool_two_phase", "name": "Zweiphasen-Direct-Chip Kühlung", "tag": "Liquid", "vtier": 3, "cost": 1550, "compute": 0, "watts": 68, "heat": -26.5, "fault_mult": 0.60},
		{"id": "cool_direct_liquid", "name": "Direct-to-Chip Dual-Loop Liquid", "tag": "Flagship", "vtier": 3, "cost": 1650, "compute": 0, "watts": 72, "heat": -28.0, "fault_mult": 0.58},
	],
	"psu": [
		{"id": "psu_350w_std", "name": "350W Standard ATX (75%)", "tag": "350W", "vtier": 0, "cost": 0, "psu_max_watts": 350, "watt_mult": 1.12, "heat": 1.0, "fault_mult": 1.08},
		{"id": "psu_400w_std", "name": "400W Standard ATX (78%)", "tag": "400W", "vtier": 0, "cost": 35, "psu_max_watts": 400, "watt_mult": 1.08, "heat": 0.7, "fault_mult": 1.04},
		{"id": "psu_450w_white", "name": "450W 80+ White", "tag": "450W", "vtier": 0, "cost": 65, "psu_max_watts": 450, "watt_mult": 1.04, "heat": 0.4, "fault_mult": 1.0},
		{"id": "psu_450w_bronze", "name": "450W 80+ Bronze", "tag": "450W", "vtier": 0, "cost": 80, "psu_max_watts": 450, "watt_mult": 1.0, "heat": 0.1, "fault_mult": 0.97},
		{"id": "psu_500w_white", "name": "500W 80+ White Server", "tag": "500W", "vtier": 0, "cost": 90, "psu_max_watts": 500, "watt_mult": 1.01, "heat": 0.0, "fault_mult": 0.98},
		{"id": "psu_550w_bronze", "name": "550W 80+ Bronze", "tag": "550W", "vtier": 0, "cost": 115, "psu_max_watts": 550, "watt_mult": 0.98, "heat": -0.4, "fault_mult": 0.95},
		{"id": "psu_600w_bronze", "name": "600W 80+ Bronze Modular", "tag": "600W", "vtier": 0, "cost": 145, "psu_max_watts": 600, "watt_mult": 0.96, "heat": -0.6, "fault_mult": 0.93},
		{"id": "psu_550w_gold", "name": "550W 80+ Gold SFX", "tag": "550W", "vtier": 0, "cost": 160, "psu_max_watts": 550, "watt_mult": 0.93, "heat": -0.8, "fault_mult": 0.91},
		{"id": "psu_650w_silver", "name": "650W 80+ Silver Server", "tag": "650W", "vtier": 1, "cost": 175, "psu_max_watts": 650, "watt_mult": 0.93, "heat": -0.8, "fault_mult": 0.91},
		{"id": "psu_650w_gold", "name": "650W 80+ Gold Kompakt", "tag": "650W", "vtier": 1, "cost": 210, "psu_max_watts": 650, "watt_mult": 0.90, "heat": -1.0, "fault_mult": 0.89},
		{"id": "psu_650w_plat", "name": "650W 80+ Platinum Server", "tag": "650W", "vtier": 1, "cost": 230, "psu_max_watts": 650, "watt_mult": 0.88, "heat": -1.1, "fault_mult": 0.87},
		{"id": "psu_750w_gold", "name": "750W 80+ Gold Effizienz", "tag": "750W", "vtier": 1, "cost": 245, "psu_max_watts": 750, "watt_mult": 0.88, "heat": -1.3, "fault_mult": 0.86},
		{"id": "psu_750w_plat", "name": "750W 80+ Platinum SFX", "tag": "750W", "vtier": 1, "cost": 295, "psu_max_watts": 750, "watt_mult": 0.84, "heat": -1.5, "fault_mult": 0.84},
		{"id": "psu_800w_red", "name": "800W Redundant 1U Gold", "tag": "800W", "vtier": 1, "cost": 310, "psu_max_watts": 800, "watt_mult": 0.87, "heat": -1.4, "fault_mult": 0.82},
		{"id": "psu_850w_gold", "name": "850W 80+ Gold Modular", "tag": "850W", "vtier": 1, "cost": 340, "psu_max_watts": 850, "watt_mult": 0.85, "heat": -1.6, "fault_mult": 0.83},
		{"id": "psu_850w_plat", "name": "850W 80+ Platinum Redundant", "tag": "850W", "vtier": 1, "cost": 395, "psu_max_watts": 850, "watt_mult": 0.81, "heat": -1.8, "fault_mult": 0.80},
		{"id": "psu_900w_plat", "name": "900W 80+ Platinum Hot-Swap", "tag": "900W", "vtier": 2, "cost": 410, "psu_max_watts": 900, "watt_mult": 0.82, "heat": -1.9, "fault_mult": 0.79},
		{"id": "psu_1000w_plat", "name": "1000W 80+ Platinum Pro", "tag": "1000W", "vtier": 2, "cost": 490, "psu_max_watts": 1000, "watt_mult": 0.80, "heat": -2.2, "fault_mult": 0.76},
		{"id": "psu_1000w_tit", "name": "1000W 80+ Titanium Kompakt", "tag": "1000W", "vtier": 2, "cost": 590, "psu_max_watts": 1000, "watt_mult": 0.76, "heat": -2.4, "fault_mult": 0.73},
		{"id": "psu_1100w_plat", "name": "1100W Redundant Platinum", "tag": "1100W", "vtier": 2, "cost": 640, "psu_max_watts": 1100, "watt_mult": 0.78, "heat": -2.4, "fault_mult": 0.72},
		{"id": "psu_1200w_red", "name": "1200W Redundant Hot-Swap Plat.", "tag": "1200W", "vtier": 2, "cost": 720, "psu_max_watts": 1200, "watt_mult": 0.77, "heat": -2.6, "fault_mult": 0.70},
		{"id": "psu_1300w_plat", "name": "1300W 80+ Platinum Modular", "tag": "1300W", "vtier": 2, "cost": 820, "psu_max_watts": 1300, "watt_mult": 0.76, "heat": -2.8, "fault_mult": 0.68},
		{"id": "psu_1200w_tit", "name": "1200W 80+ Titanium Hot-Swap", "tag": "1200W", "vtier": 2, "cost": 860, "psu_max_watts": 1200, "watt_mult": 0.73, "heat": -2.9, "fault_mult": 0.66},
		{"id": "psu_1400w_red", "name": "1400W Dual Hot-Swap Platinum", "tag": "1400W", "vtier": 3, "cost": 920, "psu_max_watts": 1400, "watt_mult": 0.74, "heat": -3.0, "fault_mult": 0.66},
		{"id": "psu_1600w_tit", "name": "1600W 80+ Titanium Server", "tag": "1600W", "vtier": 3, "cost": 1080, "psu_max_watts": 1600, "watt_mult": 0.71, "heat": -3.2, "fault_mult": 0.62},
		{"id": "psu_1600w_red", "name": "1600W Dual-Redundant Platinum", "tag": "1600W", "vtier": 3, "cost": 1180, "psu_max_watts": 1600, "watt_mult": 0.72, "heat": -3.3, "fault_mult": 0.60},
		{"id": "psu_1800w_tit", "name": "1800W 80+ Titanium Redundant", "tag": "1800W", "vtier": 3, "cost": 1260, "psu_max_watts": 1800, "watt_mult": 0.69, "heat": -3.4, "fault_mult": 0.59},
		{"id": "psu_2000w_tit", "name": "2000W 80+ Titanium Server", "tag": "2000W", "vtier": 3, "cost": 1420, "psu_max_watts": 2000, "watt_mult": 0.68, "heat": -3.6, "fault_mult": 0.57},
		{"id": "psu_2200w_red", "name": "2200W Redundant Titanium N+1", "tag": "2200W", "vtier": 3, "cost": 1590, "psu_max_watts": 2200, "watt_mult": 0.66, "heat": -3.8, "fault_mult": 0.54},
		{"id": "psu_2400w_dual", "name": "2400W Dual-Redundant Titanium", "tag": "2400W", "vtier": 3, "cost": 1750, "psu_max_watts": 2400, "watt_mult": 0.65, "heat": -4.0, "fault_mult": 0.52},
	],
}

# ==============================================================================
# RACK RENTAL PROFILES (Player chooses purpose & self-assesses live hardware load!)
# ==============================================================================
const RENTAL_ORDER: Array[String] = ["none", "web", "game", "storage", "stream", "database", "ai"]

const RENTAL_PROFILES := {
	"none": {
		"label": "Nicht vermietet (Standby)",
		"short": "Standby",
		"icon": "⏸",
		"desc": "Liefert freie Leistung für Großkunden-Verträge & AI-Cluster. Keine eigenen Miet-User.",
		"base_users": 0,
		"max_users": 0,
		"growth_rate": 0.0,
		"pay_per_user": 0.0,
		"cpu_per_user": 0.0,
		"ram_gb_per_user": 0.0,
		"gpu_per_user": 0.0,
		"storage_tb_per_user": 0.0,
		"mbps_per_user": 0.0,
		"customers": [],
	},
	"web": {
		"label": "Webhosting & Online-Shops",
		"short": "Webhosting",
		"icon": "🌐",
		"desc": "Viele gleichzeitige Seitenbesucher. Achte auf ausreichend RAM (GB) & stabile CPU!",
		"base_users": 28,
		"max_users": 900,
		"growth_rate": 4.2,
		"pay_per_user": 0.56,
		"cpu_per_user": 0.42,
		"ram_gb_per_user": 0.14,
		"gpu_per_user": 0.0,
		"storage_tb_per_user": 0.008,
		"mbps_per_user": 0.45,
		"customers": ["ShopNova GmbH", "PixelBäcker AG", "KlickMarkt24", "WebKraft Studio", "NordicStore EU"],
	},
	"game": {
		"label": "Multiplayer Game-Server",
		"short": "Game-Server",
		"icon": "🎮",
		"desc": "Hohe CPU-Last & RAM pro Spieler. Spieler reagieren empfindlich auf Lags & langsamen Router!",
		"base_users": 22,
		"max_users": 550,
		"growth_rate": 3.4,
		"pay_per_user": 1.20,
		"cpu_per_user": 1.15,
		"ram_gb_per_user": 0.36,
		"gpu_per_user": 0.05,
		"storage_tb_per_user": 0.012,
		"mbps_per_user": 1.10,
		"customers": ["NordicFrag Clan", "BlockCraft Realms", "ApexArena Hosting", "Valhalla RP", "CyberLeague EU"],
	},
	"storage": {
		"label": "Cloud-Storage & Backups",
		"short": "Cloud-Storage",
		"icon": "💾",
		"desc": "Kunden laden ständig Terabytes hoch. Achte auf große HDD/SSD/NVMe-Kapazität (TB) & RAM!",
		"base_users": 18,
		"max_users": 480,
		"growth_rate": 2.8,
		"pay_per_user": 1.40,
		"cpu_per_user": 0.45,
		"ram_gb_per_user": 0.28,
		"gpu_per_user": 0.0,
		"storage_tb_per_user": 0.16,
		"mbps_per_user": 1.40,
		"customers": ["SafeVault Cloud", "BackupPro GmbH", "ArchivMedia AG", "DriveSync Europe", "DocuGuard"],
	},
	"stream": {
		"label": "Video-Streaming & Transcoding",
		"short": "Streaming",
		"icon": "📺",
		"desc": "Live-Streams brauchen hohe Internet-Bandbreite (Mbit/Gbit!), GPU-Encoding & soliden RAM.",
		"base_users": 24,
		"max_users": 650,
		"growth_rate": 3.6,
		"pay_per_user": 1.50,
		"cpu_per_user": 0.85,
		"ram_gb_per_user": 0.32,
		"gpu_per_user": 0.72,
		"storage_tb_per_user": 0.045,
		"mbps_per_user": 2.60,
		"customers": ["StreamPulse TV", "CineFlow 4K", "LiveCast Pro", "PixelTube Media", "SportStream DE"],
	},
	"database": {
		"label": "Enterprise Datenbank-Cluster",
		"short": "Datenbank",
		"icon": "🗄",
		"desc": "Braucht massiv RAM (DDR4/DDR5 empfohlen!), schnelle NVMe & starke Multi-Core-CPUs.",
		"base_users": 18,
		"max_users": 420,
		"growth_rate": 2.6,
		"pay_per_user": 2.45,
		"cpu_per_user": 1.45,
		"ram_gb_per_user": 1.10,
		"gpu_per_user": 0.0,
		"storage_tb_per_user": 0.09,
		"mbps_per_user": 2.20,
		"customers": ["EuroPay Core", "FinLedger AG", "MedData Systems", "LogiChain ERP", "BankGrid DE"],
	},
	"ai": {
		"label": "KI / LLM GPU-Hosting",
		"short": "KI-Hosting",
		"icon": "🤖",
		"desc": "Höchste Miete! Braucht massiv GPU-Power & VRAM, viel RAM, starke Netzteile & gute Kühlung.",
		"base_users": 14,
		"max_users": 360,
		"growth_rate": 2.4,
		"pay_per_user": 4.25,
		"cpu_per_user": 1.25,
		"ram_gb_per_user": 1.40,
		"gpu_per_user": 3.20,
		"storage_tb_per_user": 0.08,
		"mbps_per_user": 3.40,
		"customers": ["VektorLabs AI", "Synthetix Corp", "DeepPrompt GmbH", "NeuralForge EU", "Helios Vision"],
	},
}


static func get_category_parts(cat: String) -> Array:
	if PARTS.has(cat):
		return PARTS[cat]
	return []


static func get_part(cat: String, part_id: String) -> Dictionary:
	if PARTS.has(cat):
		var arr: Array = PARTS[cat]
		for p in arr:
			var pd: Dictionary = p
			if str(pd["id"]) == part_id:
				return pd
		if not arr.is_empty():
			return arr[0]
	return {}


static func get_part_index(cat: String, part_id: String) -> int:
	if PARTS.has(cat):
		var arr: Array = PARTS[cat]
		for i in range(arr.size()):
			if str((arr[i] as Dictionary)["id"]) == part_id:
				return i
	return 0


static func make_default_components(server_type: String) -> Dictionary:
	if SERVER_DEFAULT_PARTS.has(server_type):
		return (SERVER_DEFAULT_PARTS[server_type] as Dictionary).duplicate(true)
	return DEFAULT_PARTS.duplicate(true)


static func normalize_components(raw_upgrades: Dictionary, server_type: String = "web_server") -> Dictionary:
	# Supports BOTH v1.0 string part IDs and legacy v0.1-v0.8 integer tier indices!
	var res := make_default_components(server_type)
	for cat in CATEGORY_ORDER:
		if not raw_upgrades.has(cat):
			continue
		var val: Variant = raw_upgrades[cat]
		if val is String:
			var pid := str(val)
			var found := false
			for p in get_category_parts(cat):
				if str((p as Dictionary)["id"]) == pid:
					res[cat] = pid
					found = true
					break
			if not found:
				res[cat] = DEFAULT_PARTS[cat]
		elif val is int or val is float:
			var legacy_tier := clampi(int(val), 0, 3)
			var arr := get_category_parts(cat)
			if not arr.is_empty():
				var mapped_idx := clampi(int(roundf(float(legacy_tier) / 3.0 * float(arr.size() - 1))), 0, arr.size() - 1)
				res[cat] = str((arr[mapped_idx] as Dictionary)["id"])
	return res


static func pick_customer_name(rental_type: String, seed_val: int) -> String:
	if not RENTAL_PROFILES.has(rental_type):
		return "Kunde"
	var list: Array = RENTAL_PROFILES[rental_type]["customers"]
	if list.is_empty():
		return ""
	return str(list[absi(seed_val) % list.size()])


static func is_stock_default_part(part_id: String) -> bool:
	for k in DEFAULT_PARTS.keys():
		if str(DEFAULT_PARTS[k]) == part_id:
			return true
	return false


static func find_part_category(part_id: String) -> String:
	for cat in CATEGORY_ORDER:
		for p in get_category_parts(cat):
			if str((p as Dictionary)["id"]) == part_id:
				return cat
	return ""


static func matches_filter(cat: String, pd: Dictionary, flt: String) -> bool:
	if flt == "Alle" or flt.is_empty():
		return true
	var tag := str(pd.get("tag", ""))
	var name_l := str(pd.get("name", "")).to_lower()
	match cat:
		"ram":
			return tag == flt
		"storage":
			if flt == "HDD":
				return tag == "HDD" or tag == "SAS" or tag == "RAID"
			if flt == "SSD":
				return tag == "SSD"
			return tag.begins_with("NVMe") or tag == "Flagship"
		"cpu":
			if flt == "Entry":
				return tag == "Budget" or tag == "Legacy" or tag == "Entry" or tag == "Mid"
			if flt == "Server":
				return tag == "Server" or tag == "High-Clock"
			return tag == "Enterprise" or tag == "Datacenter" or tag == "Flagship"
		"gpu":
			if flt == "Entry":
				return tag == "Onboard" or tag == "Entry" or tag == "Classic" or tag == "Encode"
			if flt == "RTX":
				return name_l.contains("rtx")
			return tag == "Enterprise" or tag == "AI-Core" or tag == "Hyperscale" or tag == "Flagship"
		"cooling":
			if flt == "Liquid":
				return tag == "Liquid" or tag == "Flagship"
			return tag != "Liquid" and tag != "Flagship"
		"psu":
			var pw := int(pd.get("psu_max_watts", 350))
			if flt == "350–650W":
				return pw <= 650
			return pw >= 750
	return true


static func get_part_strength_pct(cat: String, pd: Dictionary) -> float:
	match cat:
		"cpu":
			return clampf(float(pd.get("cpu_score", 0)) / 820.0 * 100.0, 4.0, 100.0)
		"ram":
			return clampf(log(maxf(1.0, float(pd.get("ram_gb", 2)))) / log(512.0) * 100.0, 8.0, 100.0)
		"gpu":
			return clampf(float(pd.get("gpu_score", 0)) / 1500.0 * 100.0, 2.0, 100.0)
		"storage":
			return clampf(log(maxf(0.5, float(pd.get("storage_tb", 0.5))) + 0.5) / log(128.5) * 100.0, 6.0, 100.0)
		"cooling":
			return clampf(absf(float(pd.get("heat", 0.0))) / 28.0 * 100.0, 6.0, 100.0)
		"psu":
			return clampf(float(pd.get("psu_max_watts", 350)) / 2400.0 * 100.0, 14.0, 100.0)
	return 10.0


static func format_speed_mbps(mbps: float) -> String:
	if mbps >= 1000.0:
		var g := mbps / 1000.0
		if absf(g - roundf(g)) < 0.05:
			return "%.0f Gbit/s" % g
		return "%.1f Gbit/s" % g
	return "%.0f Mbit/s" % mbps

