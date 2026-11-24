"""Rendert ein 100 % echtes, KI-freies 3D-Studio-Key-Art (1920x1080) direkt aus
den echten PBR-Spielmodellen (rack_pro.glb, rack.glb, part_chassis_8bay.glb,
part_chassis_4bay.glb, part_chassis_switch.glb, ups.glb, repair_kit_case.glb)
in Blender 5.2 mit 50mm-Kamera, Tiefenschärfe (DOF), AgX-Filmic und Studio-Licht.
Speichert direkt nach:
  - assets/branding/title_keyart.png
  - assets/loading/loading_bg.png
  - launcher/Assets/loading_bg.png
"""
import math
import os
import shutil
import bpy
from mathutils import Euler, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MODELS = os.path.join(ROOT, "assets", "models")
OUT_KEYART = os.path.join(ROOT, "assets", "branding", "title_keyart.png")
OUT_LOADING = os.path.join(ROOT, "assets", "loading", "loading_bg.png")
OUT_LAUNCHER = os.path.join(ROOT, "launcher", "Assets", "loading_bg.png")


def import_glb(filename, loc=(0, 0, 0), rot_z_deg=0.0, scale=1.0):
    path = os.path.join(MODELS, filename)
    if not os.path.exists(path):
        print("WARN missing:", path)
        return None
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new_objs = [o for o in bpy.context.scene.objects if o not in before]
    parent = bpy.data.objects.new(f"INST_{filename}", None)
    bpy.context.scene.collection.objects.link(parent)
    for o in new_objs:
        if o.parent is None:
            o.parent = parent
    parent.location = loc
    parent.rotation_euler = (0.0, 0.0, math.radians(rot_z_deg))
    parent.scale = (scale, scale, scale)
    return parent


def make_mat(name, rgba, rough=0.5, metal=0.0, emit_col=None, emit_str=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit_col is not None and emit_str > 0.0:
        bsdf.inputs["Emission Color"].default_value = emit_col
        bsdf.inputs["Emission Strength"].default_value = emit_str
    return m


def add_box(name, loc, dims, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = dims
    ob.data.materials.append(mat)
    return ob


def build_and_render():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    # --- Render Engine: Blender 5.2 EEVEE Next + AgX Filmic ---
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1080
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"

    if hasattr(scene.eevee, "taa_render_samples"):
        scene.eevee.taa_render_samples = 48
    if hasattr(scene.eevee, "use_raytracing"):
        scene.eevee.use_raytracing = True

    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    scene.view_settings.exposure = -0.35

    # --- Dunkle Studio-Welt (#06080B) ---
    world = bpy.data.worlds.new("DCT_Studio_World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.012, 0.016, 0.022, 1.0)
        bg.inputs["Strength"].default_value = 0.35

    # --- Realistische Rechenzentrum-Architektur (Doppelboden, Rückwand, Kabeltrasse) ---
    mat_floor = make_mat("Studio_RaisedFloor", (0.045, 0.050, 0.058, 1.0), rough=0.34, metal=0.18)
    mat_tile_line = make_mat("Studio_TileGap", (0.018, 0.020, 0.024, 1.0), rough=0.75, metal=0.05)
    mat_wall = make_mat("Studio_Wall", (0.030, 0.034, 0.040, 1.0), rough=0.82, metal=0.05)
    mat_tray = make_mat("Studio_CableTray", (0.08, 0.09, 0.10, 1.0), rough=0.45, metal=0.78)
    mat_strip_cool = make_mat("Studio_LED_Cool", (0.85, 0.92, 1.0, 1.0), rough=0.2, emit_col=(0.82, 0.90, 1.0, 1.0), emit_str=5.5)
    mat_led_green = make_mat("LED_G", (0.2, 0.9, 0.4, 1.0), rough=0.2, emit_col=(0.22, 0.95, 0.42, 1.0), emit_str=8.0)
    mat_led_amber = make_mat("LED_A", (0.95, 0.65, 0.15, 1.0), rough=0.2, emit_col=(0.98, 0.68, 0.18, 1.0), emit_str=7.5)
    mat_led_blue = make_mat("LED_B", (0.25, 0.65, 1.0, 1.0), rough=0.2, emit_col=(0.25, 0.68, 1.0, 1.0), emit_str=7.0)

    # Boden + Doppelboden-Fugen
    add_box("Floor_Base", (0.0, 4.0, -0.05), (14.0, 18.0, 0.10), mat_floor)
    for gx in range(-5, 6):
        add_box(f"GridX_{gx}", (gx * 0.65, 4.0, 0.001), (0.008, 16.0, 0.002), mat_tile_line)
    for gy in range(-2, 18):
        add_box(f"GridY_{gy}", (0.0, gy * 0.65, 0.001), (12.0, 0.008, 0.002), mat_tile_line)

    # Decke, Rückwand & Seitenwände
    add_box("Ceiling", (0.0, 4.0, 3.35), (14.0, 18.0, 0.10), mat_wall)
    add_box("BackWall", (0.0, 11.5, 1.65), (14.0, 0.15, 3.4), mat_wall)
    add_box("LeftWall", (-4.8, 4.0, 1.65), (0.15, 18.0, 3.4), mat_wall)
    add_box("RightWall", (4.8, 4.0, 1.65), (0.15, 18.0, 3.4), mat_wall)

    # Überkopf-Kabeltrassen + Decken-Lichtbänder
    add_box("CableTray_R", (1.25, 4.5, 2.55), (0.42, 14.0, 0.06), mat_tray)
    add_box("CableTray_L", (-1.55, 4.5, 2.55), (0.42, 14.0, 0.06), mat_tray)
    for ly in [1.2, 3.8, 6.4, 9.0]:
        add_box(f"LightFixture_{ly}", (-0.15, ly, 3.24), (0.14, 1.45, 0.04), mat_strip_cool)

    # --- ECHTE SPIEL-MODELS: Zwei Reihen unserer echten Racks mit echten Server-Einschüben! ---
    # Rechte Hero-Reihe (nah an der Kamera, leicht eingedreht für Tiefe)
    rack_slot_ys = [0.34, 0.64, 0.94, 1.24, 1.54, 1.84]
    chassis_cycle = ["part_chassis_8bay.glb", "part_chassis_4bay.glb", "part_chassis_8bay.glb", "part_chassis_switch.glb", "part_chassis_8bay.glb", "part_chassis_4bay.glb"]

    for idx in range(5):
        ry = 1.6 + idx * 1.18
        model_name = "rack_pro.glb" if idx % 2 == 0 else "rack.glb"
        import_glb(model_name, loc=(1.18, ry, 0.0), rot_z_deg=90.0)
        # Echte Server-Einschübe + dezente echte LED-Punkte an der Rack-Front
        for s_i, sz in enumerate(rack_slot_ys):
            if idx < 3 or s_i % 2 == 0:
                import_glb(chassis_cycle[(idx + s_i) % len(chassis_cycle)], loc=(1.18, ry, sz), rot_z_deg=90.0)
            led_m = mat_led_green if (idx + s_i) % 5 != 0 else (mat_led_amber if s_i == 2 else mat_led_blue)
            add_box(f"LED_R_{idx}_{s_i}", (0.76, ry - 0.19 + (s_i % 2) * 0.03, sz + 0.04), (0.008, 0.016, 0.008), led_m)
            add_box(f"LED_R2_{idx}_{s_i}", (0.76, ry - 0.15 + (s_i % 2) * 0.03, sz + 0.04), (0.008, 0.010, 0.008), mat_led_green)

    # Linke Reihe (etwas weiter zurück, erzeugt echte Servergang-Tiefe ohne KI-Symmetrie!)
    for idx in range(5):
        ry = 2.4 + idx * 1.18
        model_name = "rack_pro.glb" if idx % 2 == 1 else "rack.glb"
        import_glb(model_name, loc=(-1.48, ry, 0.0), rot_z_deg=-90.0)
        for s_i, sz in enumerate(rack_slot_ys):
            if idx < 2 or s_i % 2 == 1:
                import_glb(chassis_cycle[(idx + s_i + 1) % len(chassis_cycle)], loc=(-1.48, ry, sz), rot_z_deg=-90.0)
            led_m = mat_led_green if (idx + s_i) % 4 != 0 else mat_led_blue
            add_box(f"LED_L_{idx}_{s_i}", (-1.06, ry + 0.18, sz + 0.04), (0.008, 0.016, 0.008), led_m)

    # Echte Detail-Props im Vordergrund: USV + Pelican-Repair-Kit-Koffer
    import_glb("ups.glb", loc=(1.18, 0.55, 0.0), rot_z_deg=90.0)
    import_glb("repair_kit_case.glb", loc=(0.48, 1.38, 0.0), rot_z_deg=26.0, scale=1.0)

    # --- Professionelle 3-Punkt-Studio-Ausleuchtung (realistisch, NICHT neon-bunt!) ---
    # 1. Kühle neutrale Decken-Flächenleuchten über dem Gang
    for idx, ly in enumerate([1.2, 4.2, 7.6]):
        ld = bpy.data.lights.new(f"CeilingArea_{idx}", type="AREA")
        ld.shape = "RECTANGLE"
        ld.size = 0.35
        ld.size_y = 1.6
        ld.energy = 115.0 if idx == 0 else (85.0 if idx == 1 else 55.0)
        ld.color = (0.86, 0.92, 1.0)
        lo = bpy.data.objects.new(f"CeilingArea_{idx}", ld)
        scene.collection.objects.link(lo)
        lo.location = (-0.15, ly, 3.12)
        lo.rotation_euler = (0.0, 0.0, 0.0)

    # 2. Dezentes warmes Wartungs-Rim-Light hinten rechts (realistisches Industriewärme-Highlight auf gebürstetem Stahl)
    l_warm = bpy.data.lights.new("WarmServiceKey", type="AREA")
    l_warm.shape = "RECTANGLE"
    l_warm.size = 1.2
    l_warm.size_y = 1.8
    l_warm.energy = 160.0
    l_warm.color = (1.0, 0.80, 0.56)
    lo_w = bpy.data.objects.new("WarmServiceKey", l_warm)
    scene.collection.objects.link(lo_w)
    lo_w.location = (-0.35, 9.2, 1.65)
    lo_w.rotation_euler = (math.radians(82.0), 0.0, math.radians(-165.0))

    # 3. Subtiles Hero-Streiflicht auf die vorderste Rack-Kante & den Koffer
    l_rim = bpy.data.lights.new("HeroEdge", type="AREA")
    l_rim.shape = "RECTANGLE"
    l_rim.size = 0.6
    l_rim.size_y = 1.4
    l_rim.energy = 42.0
    l_rim.color = (0.95, 0.96, 1.0)
    lo_r = bpy.data.objects.new("HeroEdge", l_rim)
    scene.collection.objects.link(lo_r)
    lo_r.location = (-0.65, 0.55, 1.45)
    lo_r.rotation_euler = (math.radians(74.0), 0.0, math.radians(-58.0))

    # --- 50mm-Kamera mit echtem Depth-of-Field (leicht asymmetrisch, filmisch!) ---
    cam_data = bpy.data.cameras.new("StudioCam")
    cam_data.lens = 42.0
    cam_data.dof.use_dof = True
    cam_data.dof.focus_distance = 2.65
    cam_data.dof.aperture_fstop = 2.8
    cam_obj = bpy.data.objects.new("StudioCam", cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    cam_pos = Vector((-0.42, -0.58, 1.18))
    cam_target = Vector((0.36, 2.85, 1.02))
    cam_obj.location = cam_pos
    direction = cam_target - cam_pos
    cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    os.makedirs(os.path.dirname(OUT_KEYART), exist_ok=True)
    scene.render.filepath = OUT_KEYART
    bpy.ops.render.render(write_still=True)

    # Kopiere das echte 3D-Studio-Key-Art auch für LoadingScreen & Launcher!
    shutil.copyfile(OUT_KEYART, OUT_LOADING)
    shutil.copyfile(OUT_KEYART, OUT_LAUNCHER)
    print("RENDERED_STUDIO_KEYART:", OUT_KEYART, f"{os.path.getsize(OUT_KEYART)/1024:.1f} KB")


if __name__ == "__main__":
    build_and_render()
