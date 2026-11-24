"""Erzeugt eine realistische, organisch geformte 3D-First-Person-Hand mit Unterarm & Jackenärmel
(assets/models/fp_hand.glb) als Ersatz für die alte eckige Box-Hand in player_controller.gd.
Ursprung (0,0,0) = Handfläche (Greifpunkt), Finger zeigen nach vorn (-Z in Godot -> +Y in Blender),
Unterarm läuft nach hinten (+Z in Godot -> -Y in Blender).
"""
import math
import os
import bpy
import bmesh
from mathutils import Euler, Matrix, Vector

OUT_PATH = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models", "fp_hand.glb")
)


def make_mat(name, rgba, rough, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.25
    return m


def add_capsule(bm, p0, p1, r0, r1, segs=16, rings=4, mat_idx=0):
    """Organische, weich abgerundete Kapsel zwischen p0 und p1 mit Radius-Verlauf r0 -> r1."""
    v0, v1 = Vector(p0), Vector(p1)
    d = v1 - v0
    length = d.length
    if length < 1e-6:
        return
    z_axis = d.normalized()
    q = Vector((0.0, 0.0, 1.0)).rotation_difference(z_axis)
    rot_m = q.to_matrix().to_4x4()

    ring_verts = []
    # Unterer Pol + Kappe
    cap_steps = 3
    for k in range(cap_steps):
        ang = -math.pi * 0.5 + (math.pi * 0.5) * (k / cap_steps)
        rr = max(r0 * math.cos(ang), 1e-4)
        zz = r0 * math.sin(ang)
        row = []
        for s in range(segs):
            a = 2.0 * math.pi * s / segs
            pt = v0 + (rot_m @ Vector((rr * math.cos(a), rr * math.sin(a), zz)))
            row.append(bm.verts.new(pt))
        ring_verts.append(row)

    # Schaft-Ringe
    for r in range(rings + 1):
        u = r / rings
        rr = r0 + (r1 - r0) * u
        zz = length * u
        row = []
        for s in range(segs):
            a = 2.0 * math.pi * s / segs
            pt = v0 + (rot_m @ Vector((rr * math.cos(a), rr * math.sin(a), zz)))
            row.append(bm.verts.new(pt))
        ring_verts.append(row)

    # Obere Kappe
    for k in range(1, cap_steps + 1):
        ang = (math.pi * 0.5) * (k / cap_steps)
        rr = max(r1 * math.cos(ang), 1e-4)
        zz = length + r1 * math.sin(ang)
        row = []
        for s in range(segs):
            a = 2.0 * math.pi * s / segs
            pt = v0 + (rot_m @ Vector((rr * math.cos(a), rr * math.sin(a), zz)))
            row.append(bm.verts.new(pt))
        ring_verts.append(row)

    faces = []
    for ri in range(len(ring_verts) - 1):
        r_a = ring_verts[ri]
        r_b = ring_verts[ri + 1]
        for s in range(segs):
            sn = (s + 1) % segs
            f = bm.faces.new((r_a[s], r_a[sn], r_b[sn], r_b[s]))
            f.material_index = mat_idx
            f.smooth = True
            faces.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=faces)


def add_ellipsoid(bm, center, radii, rot_euler=(0.0, 0.0, 0.0), u_segs=20, v_rings=12, mat_idx=0):
    mtx = Matrix.Translation(center) @ Euler(rot_euler).to_matrix().to_4x4() @ Matrix.Diagonal((*radii, 1.0))
    res = bmesh.ops.create_uvsphere(bm, u_segments=u_segs, v_segments=v_rings, radius=1.0, matrix=mtx)
    for v in res["verts"]:
        for f in v.link_faces:
            f.material_index = mat_idx
            f.smooth = True


def build_fp_hand():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    coll = bpy.context.scene.collection

    mat_skin = make_mat("DCT_FP_Skin", (0.76, 0.54, 0.40, 1.0), rough=0.60, metal=0.0)
    mat_sleeve = make_mat("DCT_FP_Sleeve", (0.14, 0.28, 0.52, 1.0), rough=0.84, metal=0.0)
    mat_cuff = make_mat("DCT_FP_Cuff", (0.09, 0.16, 0.28, 1.0), rough=0.88, metal=0.0)
    mat_nail = make_mat("DCT_FP_Nail", (0.86, 0.72, 0.65, 1.0), rough=0.32, metal=0.0)

    bm = bmesh.new()

    # Koordinaten in Blender (export_yup=True wandelt Blender +Y -> Godot -Z [vorn], +Z -> +Y [oben], +X -> +X [rechts]):
    # 1. Handfläche (konturierte ovale Hand mit leicht gewölbtem Handrücken & Daumenballen)
    add_ellipsoid(bm, (0.0, 0.008, -0.004), (0.044, 0.052, 0.019), rot_euler=(0.08, -0.10, 0.0), mat_idx=0)
    # Daumenballen (innen/links für rechte Hand)
    add_ellipsoid(bm, (-0.028, -0.008, -0.006), (0.022, 0.032, 0.017), rot_euler=(0.15, 0.25, 0.35), mat_idx=0)
    # Handkante außen
    add_ellipsoid(bm, (0.030, 0.005, -0.005), (0.016, 0.044, 0.015), rot_euler=(0.05, -0.15, 0.0), mat_idx=0)

    # 2. Vier natürlich leicht gebeugte Finger (Zeige-, Mittel-, Ring-, Kleinfinger — greifen unter/seitlich an das Objekt)
    fingers = [
        # (x_base, y_base, len1, len2, len3, r_base, splay_z)
        (-0.029, 0.052, 0.034, 0.023, 0.018, 0.0096,  0.07), # Zeigefinger
        (-0.009, 0.056, 0.038, 0.026, 0.019, 0.0098,  0.01), # Mittelfinger
        ( 0.011, 0.053, 0.035, 0.024, 0.018, 0.0092, -0.04), # Ringfinger
        ( 0.029, 0.046, 0.028, 0.019, 0.016, 0.0080, -0.10), # Kleinfinger
    ]
    for fx, fy, l1, l2, l3, rb, splay in fingers:
        p0 = Vector((fx, fy, -0.002))
        # Sanft nach oben gebogene Halte-Haltung (wie beim Tragen eines Servers / Kartons)
        d1 = Vector((math.sin(splay), math.cos(splay) * 0.96, 0.26)).normalized()
        p1 = p0 + d1 * l1
        d2 = Vector((math.sin(splay) * 0.6, math.cos(splay) * 0.80, 0.58)).normalized()
        p2 = p1 + d2 * l2
        d3 = Vector((math.sin(splay) * 0.3, math.cos(splay) * 0.62, 0.78)).normalized()
        p3 = p2 + d3 * l3
        add_capsule(bm, p0, p1, rb, rb * 0.88, segs=14, rings=2, mat_idx=0)
        add_capsule(bm, p1, p2, rb * 0.86, rb * 0.76, segs=12, rings=2, mat_idx=0)
        add_capsule(bm, p2, p3, rb * 0.74, rb * 0.62, segs=12, rings=2, mat_idx=0)
        # Dezenter Fingernagel
        nail_p = p2.lerp(p3, 0.65) + Vector((0.0, 0.001, -rb * 0.42))
        add_ellipsoid(bm, nail_p, (rb * 0.48, rb * 0.58, rb * 0.18), rot_euler=(-0.7, 0.0, -splay), u_segs=10, v_rings=6, mat_idx=3)

    # 3. Opponierbarer Daumen (links innen an der rechten Hand, leicht nach oben/vorn gelegt)
    t0 = Vector((-0.036, -0.004, 0.002))
    t1 = Vector((-0.056,  0.024, 0.014))
    t2 = Vector((-0.062,  0.052, 0.028))
    add_capsule(bm, t0, t1, 0.0125, 0.0108, segs=14, rings=2, mat_idx=0)
    add_capsule(bm, t1, t2, 0.0105, 0.0086, segs=12, rings=2, mat_idx=0)

    # 4. Handgelenk & nackter Unterarm-Ansatz (schlanke realistische Proportionen)
    w0 = Vector((0.002, -0.044, -0.006))
    w1 = Vector((0.009, -0.102, -0.014))
    add_capsule(bm, w0, w1, 0.025, 0.028, segs=18, rings=3, mat_idx=0)

    # 5. Arbeitsjacken-Bündchen & schlanker Unterarm-Ärmel
    c0 = Vector((0.009, -0.094, -0.013))
    c1 = Vector((0.014, -0.128, -0.019))
    add_capsule(bm, c0, c1, 0.031, 0.033, segs=20, rings=2, mat_idx=2)

    s0 = Vector((0.014, -0.122, -0.018))
    s1 = Vector((0.055, -0.680, -0.145))
    add_capsule(bm, s0, s1, 0.034, 0.048, segs=22, rings=6, mat_idx=1)

    me = bpy.data.meshes.new("FP_Hand_Mesh")
    bm.to_mesh(me)
    bm.free()
    for m in (mat_skin, mat_sleeve, mat_cuff, mat_nail):
        me.materials.append(m)

    ob = bpy.data.objects.new("FP_RightHand", me)
    coll.objects.link(ob)

    # Leichter Subsurf-Feinschliff für organische Hautübergänge
    sub = ob.modifiers.new("Subsurf", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(
        filepath=OUT_PATH,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
    )
    print("EXPORTED_FP_HAND:", OUT_PATH, f"{os.path.getsize(OUT_PATH) / 1024.0:.1f} KB")


if __name__ == "__main__":
    build_fp_hand()
