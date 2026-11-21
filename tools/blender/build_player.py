"""Baut das Co-op-Spielermodell fuer DataCenter Tycoon und exportiert es nach assets/models/player.glb.

Aufruf ohne GUI:
    blender --background --factory-startup --python tools/blender/build_player.py -- <projektordner>

Masse in GODOT-Koordinaten (X rechts, Y oben, Front -Z). g() rechnet nach Blender um (X, -Z, Y),
der glTF-Export mit export_yup dreht zurueck. Boden bei Y = 0, Gesamthoehe ca. 1,72 m.

Gelenke (Empties), die scripts/world/player_controller.gd per Name sucht und um X dreht:
    Pivot_LegL / Pivot_LegR   Huefte,   Y = 0.70
    Pivot_ArmL / Pivot_ArmR   Schulter, Y = 1.26
    Pivot_Head                Kopf,     Y = 1.52
Alle Teile haengen nach -Y vom Gelenk. Das Material "DCT_Jacket" toent das Spiel in der Spielerfarbe.
Erzeugt ausserdem tools/blender/dct_player.blend und zwei Vorschaubilder preview_player_*.png.
"""
import os
import sys

import bmesh
import bpy
from mathutils import Vector


def _project_root():
    if "--" in sys.argv:
        args = sys.argv[sys.argv.index("--") + 1:]
        if args and os.path.isfile(os.path.join(args[0], "project.godot")):
            return os.path.abspath(args[0])
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        return os.path.normpath(os.path.join(here, "..", ".."))
    except NameError:
        raise RuntimeError("Projektordner unbekannt. Aufruf mit: -- <projektordner>")


ROOT = _project_root()
TOOLS_DIR = os.path.join(ROOT, "tools", "blender")
OUT_GLB = os.path.join(ROOT, "assets", "models", "player.glb")
OUT_BLEND = os.path.join(TOOLS_DIR, "dct_player.blend")
COLLECTION = "DCT_Player"


# ---------------------------------------------------------------------------
# Godot -> Blender
# ---------------------------------------------------------------------------

def g(x, y, z):
    return Vector((x, -z, y))


def gs(sx, sy, sz):
    return Vector((sx, sz, sy))


# ---------------------------------------------------------------------------
# Bausteine
# ---------------------------------------------------------------------------

def make_mat(name, rgb, rough, metal=0.0):
    m = bpy.data.materials.new(name)
    try:
        if not m.use_nodes:
            m.use_nodes = True
    except AttributeError:
        pass
    if m.node_tree is not None:
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf is not None:
            bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
            bsdf.inputs["Roughness"].default_value = rough
            bsdf.inputs["Metallic"].default_value = metal
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    m.roughness = rough
    m.metallic = metal
    return m


def empty(name, parent, pos):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_type = "PLAIN_AXES"
    ob.empty_display_size = 0.08
    COLL.objects.link(ob)
    ob.parent = parent
    ob.location = g(*pos)
    return ob


def _finish(name, bm, mat, parent, pos, smooth_mode):
    bm.normal_update()
    for f in bm.faces:
        if smooth_mode == "all":
            f.smooth = True
        elif smooth_mode == "sides":
            f.smooth = abs(f.normal.z) < 0.5
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    COLL.objects.link(ob)
    ob.parent = parent
    ob.location = g(*pos)
    return ob


def box(name, parent, pos, size, mat, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    s = gs(*size)
    for v in bm.verts:
        v.co = Vector((v.co.x * s.x, v.co.y * s.y, v.co.z * s.z))
    ob = _finish(name, bm, mat, parent, pos, "none")
    if bevel > 0.0:
        mod = ob.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    return ob


def cyl(name, parent, x, z, top_y, bottom_y, r_top, r_bottom, mat, segments=18):
    """Senkrechter Zylinder/Kegelstumpf zwischen bottom_y und top_y (Godot Y)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=segments,
        radius1=r_bottom, radius2=r_top, depth=top_y - bottom_y,
    )
    return _finish(name, bm, mat, parent, (x, (top_y + bottom_y) * 0.5, z), "sides")


def ellipsoid(name, parent, pos, radii, mat, upper_half=False):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=22, v_segments=14, radius=1.0)
    if upper_half:
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -1e-4], context="VERTS")
    r = gs(*radii)
    for v in bm.verts:
        v.co = Vector((v.co.x * r.x, v.co.y * r.y, v.co.z * r.z))
    return _finish(name, bm, mat, parent, pos, "all")


# ---------------------------------------------------------------------------
# Modell
# ---------------------------------------------------------------------------

def build():
    jacket = make_mat("DCT_Jacket", (0.22, 0.72, 0.98), 0.55, 0.05)
    pants = make_mat("DCT_Pants", (0.15, 0.17, 0.21), 0.78)
    belt = make_mat("DCT_Belt", (0.10, 0.11, 0.12), 0.55, 0.2)
    boot = make_mat("DCT_Boot", (0.20, 0.15, 0.11), 0.6)
    sole = make_mat("DCT_Sole", (0.05, 0.05, 0.05), 0.85)
    skin = make_mat("DCT_Skin", (0.88, 0.72, 0.60), 0.6)
    stripe = make_mat("DCT_Reflect", (0.82, 0.84, 0.86), 0.25, 0.4)
    metal = make_mat("DCT_Metal", (0.70, 0.71, 0.73), 0.3, 0.9)
    badge = make_mat("DCT_Badge", (0.95, 0.95, 0.93), 0.4)
    pack = make_mat("DCT_Pack", (0.24, 0.27, 0.31), 0.6, 0.1)
    pack_dark = make_mat("DCT_PackDark", (0.14, 0.15, 0.17), 0.65)
    glass = make_mat("DCT_Glass", (0.10, 0.12, 0.14), 0.12, 0.4)

    root = bpy.data.objects.new("player", None)
    root.empty_display_type = "ARROWS"
    root["dct_model_id"] = "player"
    COLL.objects.link(root)

    # Becken, Guertel
    box("Pelvis", root, (0.0, 0.77, 0.0), (0.36, 0.16, 0.22), pants, 0.03)
    box("Belt", root, (0.0, 0.85, 0.0), (0.40, 0.06, 0.245), belt, 0.01)
    box("Buckle", root, (0.0, 0.85, -0.124), (0.07, 0.045, 0.012), metal, 0.004)

    # Oberkoerper mit Arbeitsjacke
    box("Torso", root, (0.0, 1.08, 0.0), (0.42, 0.46, 0.24), jacket, 0.06)
    box("Yoke", root, (0.0, 1.27, 0.0), (0.46, 0.10, 0.25), jacket, 0.045)
    box("Stripe", root, (0.0, 1.00, 0.0), (0.43, 0.035, 0.25), stripe)
    box("Zipper", root, (0.0, 1.08, -0.122), (0.012, 0.40, 0.006), metal)
    box("Badge", root, (0.10, 1.17, -0.124), (0.07, 0.045, 0.006), badge)
    cyl("Collar", root, 0.0, 0.0, 1.37, 1.30, 0.085, 0.10, jacket)
    cyl("Neck", root, 0.0, 0.0, 1.43, 1.30, 0.055, 0.058, skin)

    # Rucksack mit Gurten
    box("Backpack", root, (0.0, 1.08, 0.17), (0.30, 0.38, 0.11), pack, 0.03)
    box("BackpackPocket", root, (0.0, 0.98, 0.232), (0.24, 0.14, 0.03), pack_dark, 0.01)
    box("Strap_L", root, (-0.10, 1.12, -0.124), (0.04, 0.34, 0.008), pack_dark)
    box("Strap_R", root, (0.10, 1.12, -0.124), (0.04, 0.34, 0.008), pack_dark)

    # Beine (Gelenk an der Huefte)
    for side, x in (("L", -0.10), ("R", 0.10)):
        piv = empty("Pivot_Leg" + side, root, (x, 0.70, 0.0))
        ellipsoid("Hip_" + side, piv, (0.0, 0.0, 0.0), (0.09, 0.09, 0.09), pants)
        cyl("Leg_" + side, piv, 0.0, 0.0, 0.0, -0.62, 0.085, 0.065, pants)
        box("KneePad_" + side, piv, (0.0, -0.30, -0.072), (0.10, 0.10, 0.03), belt, 0.012)
        box("Boot_" + side, piv, (0.0, -0.655, -0.035), (0.12, 0.09, 0.25), boot, 0.025)
        box("Sole_" + side, piv, (0.0, -0.69, -0.035), (0.125, 0.02, 0.255), sole, 0.005)

    # Arme (Gelenk an der Schulter)
    for side, x in (("L", -0.29), ("R", 0.29)):
        piv = empty("Pivot_Arm" + side, root, (x, 1.26, 0.0))
        ellipsoid("Shoulder_" + side, piv, (0.0, 0.0, 0.0), (0.075, 0.075, 0.075), jacket)
        cyl("Arm_" + side, piv, 0.0, 0.0, 0.0, -0.46, 0.065, 0.055, jacket)
        cyl("Cuff_" + side, piv, 0.0, 0.0, -0.44, -0.48, 0.059, 0.059, belt)
        ellipsoid("Hand_" + side, piv, (0.0, -0.53, -0.01), (0.045, 0.06, 0.05), skin)

    # Kopf mit Kappe und Schutzbrille
    head = empty("Pivot_Head", root, (0.0, 1.52, 0.0))
    ellipsoid("Head", head, (0.0, 0.0, 0.0), (0.135, 0.155, 0.145), skin)
    ellipsoid("Nose", head, (0.0, -0.02, -0.14), (0.022, 0.032, 0.028), skin)
    ellipsoid("Ear_L", head, (-0.135, 0.0, 0.0), (0.02, 0.04, 0.03), skin)
    ellipsoid("Ear_R", head, (0.135, 0.0, 0.0), (0.02, 0.04, 0.03), skin)
    ellipsoid("Cap", head, (0.0, 0.045, 0.005), (0.145, 0.12, 0.155), jacket, upper_half=True)
    ellipsoid("CapBrim", head, (0.0, 0.05, -0.17), (0.12, 0.012, 0.08), jacket)
    box("Glasses", head, (0.0, 0.025, -0.14), (0.22, 0.05, 0.03), glass, 0.01)
    box("Temple_L", head, (-0.125, 0.03, -0.07), (0.01, 0.015, 0.14), belt)
    box("Temple_R", head, (0.125, 0.03, -0.07), (0.01, 0.015, 0.14), belt)
    return root


def export_glb():
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB,
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_apply=True,
        export_extras=True,
    )


def render_previews():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = 700
    scene.render.resolution_y = 900
    world = bpy.data.worlds.new("PreviewWorld")
    world.color = (0.18, 0.20, 0.23)
    scene.world = world

    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 55
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((0.0, 0.0, 0.88))
    shots = (
        ("preview_player_front.png", Vector((1.5, 3.1, 1.35))),
        ("preview_player_back.png", Vector((-1.4, -3.0, 1.45))),
    )
    for file_name, loc in shots:
        cam.location = loc
        cam.rotation_euler = (target - loc).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(TOOLS_DIR, file_name)
        bpy.ops.render.render(write_still=True)
        print("DCT preview", scene.render.filepath)


def main():
    global COLL
    bpy.ops.wm.read_factory_settings(use_empty=True)
    COLL = bpy.data.collections.new(COLLECTION)
    bpy.context.scene.collection.children.link(COLL)

    build()
    export_glb()
    verts = sum(len(o.data.vertices) for o in COLL.objects if o.type == "MESH")
    print(f"DCT player.glb {os.path.getsize(OUT_GLB) / 1024.0:.1f} KB, {verts} Vertices -> {OUT_GLB}")

    render_previews()
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    print("DCT blend", OUT_BLEND)


COLL = None

if __name__ == "__main__":
    main()