"""Rendert die exportierten .glb-Bauteile an den exakten HardwareMeshFactory-Positionen in Blender
fuer schnelles visuelles Pruefen aus Rueckansicht (User-Screenshot), Frontansicht & High-Tier-Setup."""

import math
import os
import sys
import bpy
from mathutils import Euler, Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", "assets", "models"))
OUT_DIR = os.path.join(SCRIPT_DIR, "_pbr_cache")


def clear_all():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def godot_to_blender(pos):
    x, y, z = pos
    return Vector((x, -z, y))


def import_glb(name, godot_pos=(0, 0, 0), parent=None):
    path = os.path.join(MODELS_DIR, name + ".glb")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    added = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in added if o.parent is None]
    holder = bpy.data.objects.new(name + "_holder", None)
    bpy.context.scene.collection.objects.link(holder)
    holder.location = godot_to_blender(godot_pos)
    if parent is not None:
        holder.parent = parent
    for r in roots:
        r.parent = holder
    return holder


def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"

    # Studio-Himmel (aehnlich rack_inspector_ui.gd ProceduralSkyMaterial)
    world = bpy.data.worlds.new("Studio")
    scene.world = world
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Color"].default_value = (0.18, 0.21, 0.25, 1.0)
    bg.inputs["Strength"].default_value = 0.75
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])

    # 3-Punkt Studio-Beleuchtung wie in rack_inspector_ui.gd
    def add_area(name, loc, rot_deg, energy, size, color):
        ld = bpy.data.lights.new(name, type="AREA")
        ld.energy = energy
        ld.size = size
        ld.color = color
        lo = bpy.data.objects.new(name, ld)
        lo.location = loc
        lo.rotation_euler = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ")
        scene.collection.objects.link(lo)

    add_area("Key", (0.85, -0.95, 1.35), (42, 0, 38), 110.0, 0.9, (1.0, 0.97, 0.93))
    add_area("Fill", (-0.95, 0.75, 0.95), (50, 0, -135), 42.0, 1.1, (0.84, 0.91, 1.0))
    add_area("Rim", (0.0, 1.15, 0.95), (48, 0, 180), 55.0, 1.0, (0.95, 0.97, 1.0))

    cam_d = bpy.data.cameras.new("Cam")
    cam_d.lens = 45.0
    cam_o = bpy.data.objects.new("Cam", cam_d)
    scene.collection.objects.link(cam_o)
    scene.camera = cam_o
    return cam_o


def aim_camera(cam, pos_godot, target_godot=(0.0, 0.05, 0.0)):
    p = godot_to_blender(pos_godot)
    t = godot_to_blender(target_godot)
    cam.location = p
    direction = t - p
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def build_server(is_ai=False, tiers=None):
    if tiers is None:
        tiers = {"cpu": 0, "ram": 0, "gpu": 0, "storage": 0, "cooling": 0, "psu": 0}
    import_glb("prop_workbench", (0, 0, 0))
    chassis_id = "part_chassis_4bay" if is_ai else "part_chassis_8bay"
    import_glb(chassis_id, (0, 0, 0))

    bays = 4 if is_ai else 8
    start_x = -0.245 if bays == 4 else -0.275
    step = 0.165 if bays == 4 else 0.078
    caddy = "part_caddy_lff" if bays == 4 else "part_caddy_sff"
    for b in range(bays):
        import_glb(caddy, (start_x + b * step, 0.072, 0.362))

    mb = import_glb("part_mainboard_ai" if is_ai else "part_mainboard", (-0.04, 0.022, -0.07))
    import_glb(f"part_cpu_t{tiers['cpu']}", (-0.07, 0.006, -0.01), parent=mb)
    import_glb(f"part_ram_t{tiers['ram']}", (0.09, 0.008, -0.03), parent=mb)
    import_glb(f"part_gpu_t{tiers['gpu']}", (-0.21, 0.008, 0.05), parent=mb)
    import_glb(f"part_storage_t{tiers['storage']}", (0.04, 0.008, 0.14), parent=mb)
    import_glb(f"part_cooling_t{tiers['cooling']}", (-0.02, 0.018, 0.21))
    import_glb(f"part_psu_t{tiers['psu']}", (0.285, 0.018, -0.17))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    # 1) Exakte User-Ansicht (T0 Storage-Server von hinten-oben + von vorne-oben)
    clear_all()
    cam = setup_scene()
    build_server(is_ai=False, tiers={"cpu": 0, "ram": 0, "gpu": 0, "storage": 0, "cooling": 0, "psu": 0})

    aim_camera(cam, (0.0, 0.86, -0.96), (0.0, 0.04, 0.02))
    bpy.context.scene.render.filepath = os.path.join(OUT_DIR, "verify_rear_t0.png")
    bpy.ops.render.render(write_still=True)

    aim_camera(cam, (0.0, 0.78, 1.12), (0.0, 0.04, 0.0))
    bpy.context.scene.render.filepath = os.path.join(OUT_DIR, "verify_front_t0.png")
    bpy.ops.render.render(write_still=True)

    # 2) Voll ausgebauter AI-Pro-Server (Tier 3 mit Dual-GPU, Kupfer-Wakue, Dual-HotSwap-PSU!)
    clear_all()
    cam = setup_scene()
    build_server(is_ai=True, tiers={"cpu": 3, "ram": 3, "gpu": 3, "storage": 3, "cooling": 3, "psu": 3})
    aim_camera(cam, (0.48, 0.74, -0.82), (0.0, 0.05, 0.0))
    bpy.context.scene.render.filepath = os.path.join(OUT_DIR, "verify_ai_pro_t3.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEWS RENDERED OK")


if __name__ == "__main__":
    main()
