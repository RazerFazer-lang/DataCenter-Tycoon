"""Erzeugt geriggte First-Person-Ego-Arme (assets/models/fp_arms.glb) in Blender 5.2
mit vollständiger Finger-Artikulation (38 Bones) und 5 gebackenen NLA-Animationen:
  - extinguisher_idle   : Zweihändiger Feuerlöscher-Griff (Rechts am Tragegriff/Hebel, Links am Schlauch/Düse)
  - extinguisher_spray  : Auslösehebel wird von Fingern & Daumen gedrückt + leichter Druck-Rückstoß
  - hold_box_twohand    : Zweihändiges seitliches Tragen für Kartons, Server, Racks & 6er-Packs
  - hold_item_onehand   : Einhändiges Tragen (Handfläche oben) für Kits & Kleinteile
  - hold_cable          : Einhändiges Halten für Strom-/LAN-Kabelstecker

Alle Zielkoordinaten sind direkt im Godot-_held_root-Koordinatensystem definiert
und werden exakt via g2b(gx, gy, gz) = (gx, -gz, gy) für glTF export_yup=True umgerechnet.
"""
import math
import os
import bpy
import bmesh
from mathutils import Euler, Matrix, Quaternion, Vector

OUT_PATH = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models", "fp_arms.glb")
)

FOREARM_LEN = 0.44
HAND_LEN = 0.088


def g2b(gx, gy, gz):
    """Godot (X=rechts, Y=oben, -Z=vorn) -> Blender (X=rechts, +Y=vorn, +Z=oben)."""
    return Vector((gx, -gz, gy))


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


def _assign_verts_to_group(bm_verts, vert_weights, bone_name, weight=1.0):
    for v in bm_verts:
        vert_weights.setdefault(v.index, []).append((bone_name, weight))


def add_weighted_capsule(bm, p0, p1, r0, r1, mat_idx, bone_a, bone_b=None, segs=16, rings=4, vert_weights=None):
    """Organische Kapsel zwischen p0 und p1 mit weichem Skin-Blending entlang der Länge."""
    v0, v1 = Vector(p0), Vector(p1)
    d = v1 - v0
    length = d.length
    if length < 1e-6:
        return []
    z_axis = d.normalized()
    q = Vector((0.0, 0.0, 1.0)).rotation_difference(z_axis)
    rot_m = q.to_matrix().to_4x4()

    ring_verts = []
    ring_u = []

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
        ring_u.append(0.0)

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
        ring_u.append(u)

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
        ring_u.append(1.0)

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

    if vert_weights is not None:
        for row, u in zip(ring_verts, ring_u):
            for v in row:
                if bone_b is None:
                    vert_weights.append((v, bone_a, 1.0))
                else:
                    # Sanftes Blending nur im letzten Drittel zum nächsten Gelenk
                    wb = max(0.0, min(1.0, (u - 0.65) / 0.35))
                    wa = 1.0 - wb
                    if wa > 0.001:
                        vert_weights.append((v, bone_a, wa))
                    if wb > 0.001:
                        vert_weights.append((v, bone_b, wb))
    return ring_verts


def add_weighted_ellipsoid(bm, center, radii, rot_euler, mat_idx, bone_name, vert_weights, u_segs=18, v_rings=10):
    mtx = Matrix.Translation(center) @ Euler(rot_euler).to_matrix().to_4x4() @ Matrix.Diagonal((*radii, 1.0))
    res = bmesh.ops.create_uvsphere(bm, u_segments=u_segs, v_segments=v_rings, radius=1.0, matrix=mtx)
    for v in res["verts"]:
        vert_weights.append((v, bone_name, 1.0))
        for f in v.link_faces:
            f.material_index = mat_idx
            f.smooth = True


def build_arm_geometry_and_bones(side, side_sign, bm, vert_weights, ebones, root_bone):
    """Baut eine komplette Arm- & Hand-Kette im neutralen Rest-Pose-Zustand:
    side = 'R' (side_sign = +1.0) oder 'L' (side_sign = -1.0).
    Rest-Pose: Unterarm liegt entlang +Y (Blender vorn), Handfläche zeigt nach unten (-Z Blender / -Y Godot),
    Finger zeigen gerade nach vorn (+Y Blender / -Z Godot), Daumen liegt innen (-side_sign * X).
    """
    base_x = side_sign * 0.28
    elbow = Vector((base_x, -FOREARM_LEN, 0.0))
    wrist = Vector((base_x, 0.0, 0.0))
    knuckle_mid = Vector((base_x, HAND_LEN, 0.0))

    # --- Bones anlegen ---
    b_fore = ebones.new(f"{side}_forearm")
    b_fore.head = elbow
    b_fore.tail = wrist
    b_fore.parent = root_bone
    b_fore.roll = 0.0

    b_hand = ebones.new(f"{side}_hand")
    b_hand.head = wrist
    b_hand.tail = knuckle_mid
    b_hand.parent = b_fore
    b_hand.use_connect = True
    b_hand.roll = 0.0

    # --- Arm- & Hand-Mesh (direkt um die Rest-Pose-Bones!) ---
    # 1. Jackenärmel (vom Ellbogen bis kurz vors Handgelenk)
    sleeve_end = elbow.lerp(wrist, 0.84)
    add_weighted_capsule(bm, elbow, sleeve_end, 0.058, 0.042, 1, f"{side}_forearm", None, segs=22, rings=6, vert_weights=vert_weights)
    # 2. Ärmel-Bündchen (Cuff)
    cuff_start = elbow.lerp(wrist, 0.80)
    cuff_end = elbow.lerp(wrist, 0.90)
    add_weighted_capsule(bm, cuff_start, cuff_end, 0.044, 0.040, 2, f"{side}_forearm", None, segs=20, rings=2, vert_weights=vert_weights)
    # 3. Nacktes Handgelenk (weicher Übergang zum Hand-Bone)
    wrist_start = elbow.lerp(wrist, 0.86)
    add_weighted_capsule(bm, wrist_start, wrist + Vector((0.0, 0.012, 0.0)), 0.028, 0.026, 0, f"{side}_forearm", f"{side}_hand", segs=18, rings=3, vert_weights=vert_weights)

    # 4. Handfläche (anatomisch geformter Handrücken + Daumenballen + Außenkante)
    palm_c = wrist + Vector((0.0, 0.048, 0.0))
    add_weighted_ellipsoid(bm, palm_c, (0.043, 0.048, 0.017), (0.0, 0.0, 0.0), 0, f"{side}_hand", vert_weights)
    # Daumenballen (innen)
    thenar_c = wrist + Vector((-side_sign * 0.026, 0.030, -0.005))
    add_weighted_ellipsoid(bm, thenar_c, (0.022, 0.030, 0.016), (0.0, 0.0, side_sign * 0.25), 0, f"{side}_hand", vert_weights)
    # Handkante (außen)
    hypothenar_c = wrist + Vector((side_sign * 0.030, 0.042, -0.003))
    add_weighted_ellipsoid(bm, hypothenar_c, (0.015, 0.040, 0.014), (0.0, 0.0, 0.0), 0, f"{side}_hand", vert_weights)

    # 5. Vier artikulierte Finger (Zeige-, Mittel-, Ring-, Kleinfinger — je 3 Bones!)
    finger_specs = [
        # (name, x_offset_from_center_signed_for_R, y_start, l1, l2, l3, r_base)
        ("index",  -0.029, 0.088, 0.035, 0.023, 0.018, 0.0094),
        ("middle", -0.009, 0.092, 0.039, 0.026, 0.019, 0.0096),
        ("ring",    0.011, 0.089, 0.036, 0.024, 0.018, 0.0090),
        ("pinky",   0.029, 0.082, 0.028, 0.019, 0.016, 0.0078),
    ]
    for fname, fx_r, fy, l1, l2, l3, rb in finger_specs:
        fx = side_sign * fx_r
        p0 = wrist + Vector((fx, fy, 0.0))
        p1 = p0 + Vector((0.0, l1, 0.0))
        p2 = p1 + Vector((0.0, l2, 0.0))
        p3 = p2 + Vector((0.0, l3, 0.0))

        bn1 = f"{side}_{fname}_1"
        bn2 = f"{side}_{fname}_2"
        bn3 = f"{side}_{fname}_3"

        eb1 = ebones.new(bn1)
        eb1.head, eb1.tail = p0, p1
        eb1.parent = b_hand
        eb1.roll = 0.0

        eb2 = ebones.new(bn2)
        eb2.head, eb2.tail = p1, p2
        eb2.parent = eb1
        eb2.use_connect = True
        eb2.roll = 0.0

        eb3 = ebones.new(bn3)
        eb3.head, eb3.tail = p2, p3
        eb3.parent = eb2
        eb3.use_connect = True
        eb3.roll = 0.0

        add_weighted_capsule(bm, p0, p1, rb, rb * 0.88, 0, bn1, bn2, segs=12, rings=2, vert_weights=vert_weights)
        add_weighted_capsule(bm, p1, p2, rb * 0.86, rb * 0.76, 0, bn2, bn3, segs=12, rings=2, vert_weights=vert_weights)
        add_weighted_capsule(bm, p2, p3, rb * 0.74, rb * 0.60, 0, bn3, None, segs=10, rings=2, vert_weights=vert_weights)
        # Fingernagel auf dem Handrücken (+Z in Blender Rest-Pose)
        nail_p = p2.lerp(p3, 0.62) + Vector((0.0, 0.0, rb * 0.44))
        add_weighted_ellipsoid(bm, nail_p, (rb * 0.46, rb * 0.56, rb * 0.16), (0.0, 0.0, 0.0), 3, bn3, vert_weights, u_segs=10, v_rings=6)

    # 6. Opponierbarer Daumen (2 Bones, innen an der Hand)
    t0 = wrist + Vector((-side_sign * 0.036, 0.036, -0.004))
    t1 = t0 + Vector((-side_sign * 0.022, 0.028, -0.006))
    t2 = t1 + Vector((-side_sign * 0.008, 0.028, -0.002))

    tb1 = ebones.new(f"{side}_thumb_1")
    tb1.head, tb1.tail = t0, t1
    tb1.parent = b_hand
    tb1.roll = 0.0

    tb2 = ebones.new(f"{side}_thumb_2")
    tb2.head, tb2.tail = t1, t2
    tb2.parent = tb1
    tb2.use_connect = True
    tb2.roll = 0.0

    add_weighted_capsule(bm, t0, t1, 0.0122, 0.0105, 0, f"{side}_thumb_1", f"{side}_thumb_2", segs=12, rings=2, vert_weights=vert_weights)
    add_weighted_capsule(bm, t1, t2, 0.0102, 0.0082, 0, f"{side}_thumb_2", None, segs=12, rings=2, vert_weights=vert_weights)


def _basis_from_forward_and_up(forward_b: Vector, up_b: Vector) -> Matrix:
    """Erzeugt eine 3x3-Rotationsmatrix, deren +Y-Achse entlang forward_b und +Z-Achse entlang up_b zeigt."""
    y = forward_b.normalized()
    x = y.cross(up_b).normalized()
    if x.length < 1e-5:
        x = y.cross(Vector((0.0, 0.0, 1.0))).normalized()
    z = x.cross(y).normalized()
    return Matrix((
        (x.x, y.x, z.x),
        (x.y, y.y, z.y),
        (x.z, y.z, z.z),
    ))


def pose_arm(arm_obj, side, wrist_g, elbow_g, hand_fwd_g, hand_back_up_g,
             finger_curls, thumb_angles):
    """Setzt einen kompletten Arm millimetergenau im Godot-_held_root-Koordinatensystem!
    - wrist_g: Handgelenk-Position (Godot)
    - elbow_g: Ellbogen-Richtungspunkt (Godot; Unterarm läuft von elbow_g -> wrist_g)
    - hand_fwd_g: Richtung Handgelenk -> Fingerknöchel (Godot)
    - hand_back_up_g: Richtung des Handrückens (+Z im Bone-Space, Godot)
    - finger_curls: Dict { 'index': (c1, c2, c3), ... } in Grad (positiv = nach innen/Handfläche beugen)
    - thumb_angles: ((rx1, ry1, rz1), (rx2, ry2, rz2)) in Grad
    """
    pbones = arm_obj.pose.bones
    wrist_b = g2b(*wrist_g)
    elbow_dir_b = (wrist_b - g2b(*elbow_g)).normalized()
    elbow_b = wrist_b - elbow_dir_b * FOREARM_LEN

    # Forearm-Matrix im Armature-Space (+Y zeigt von elbow_b -> wrist_b)
    fore_up_hint = g2b(*hand_back_up_g)
    fore_rot = _basis_from_forward_and_up(elbow_dir_b, fore_up_hint)
    fore_mtx = Matrix.Translation(elbow_b) @ fore_rot.to_4x4()

    pb_fore = pbones[f"{side}_forearm"]
    pb_fore.matrix = fore_mtx
    bpy.context.view_layer.update()

    # Hand-Matrix im Armature-Space (Head liegt automatisch bei wrist_b!)
    hand_rot = _basis_from_forward_and_up(g2b(*hand_fwd_g), g2b(*hand_back_up_g))
    hand_mtx = Matrix.Translation(wrist_b) @ hand_rot.to_4x4()
    pb_hand = pbones[f"{side}_hand"]
    pb_hand.matrix = hand_mtx
    bpy.context.view_layer.update()

    # Finger beugen (im lokalen Bone-Space dreht -X die Finger in Richtung Handfläche [-Z])
    for fname, curls in finger_curls.items():
        for idx, deg in enumerate(curls, start=1):
            pb = pbones[f"{side}_{fname}_{idx}"]
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = Euler((math.radians(-deg), 0.0, 0.0), "XYZ")

    # Daumen positionieren
    for idx, angs in enumerate(thumb_angles, start=1):
        pb = pbones[f"{side}_thumb_{idx}"]
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = Euler(tuple(math.radians(a) for a in angs), "XYZ")

    bpy.context.view_layer.update()


def keyframe_all_bones(arm_obj, frame):
    bpy.context.scene.frame_set(frame)
    for pb in arm_obj.pose.bones:
        pb.keyframe_insert(data_path="location", frame=frame)
        if pb.rotation_mode == "QUATERNION":
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
        else:
            pb.keyframe_insert(data_path="rotation_euler", frame=frame)


def build_action(arm_obj, name, keyframes_fn, total_frames):
    """Erstellt eine benannte Action, setzt alle Keyframes und schiebt sie als NLA-Track ein."""
    act = bpy.data.actions.new(name=name)
    if arm_obj.animation_data is None:
        arm_obj.animation_data_create()
    arm_obj.animation_data.action = act

    # Alle Pose-Bones zurücksetzen
    for pb in arm_obj.pose.bones:
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
        pb.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()

    keyframes_fn(arm_obj)

    track = arm_obj.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 1, act)
    strip.frame_end = total_frames
    arm_obj.animation_data.action = None
    return act


def build_fp_arms():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 30
    coll = scene.collection

    # Materialien (exakt die gleichen Namen wie in player_controller._refresh_fp_hand_skin!)
    mat_skin = make_mat("DCT_FP_Skin", (0.76, 0.54, 0.40, 1.0), rough=0.58, metal=0.0)
    mat_sleeve = make_mat("DCT_FP_Sleeve", (0.14, 0.28, 0.52, 1.0), rough=0.84, metal=0.0)
    mat_cuff = make_mat("DCT_FP_Cuff", (0.09, 0.16, 0.28, 1.0), rough=0.88, metal=0.0)
    mat_nail = make_mat("DCT_FP_Nail", (0.86, 0.72, 0.65, 1.0), rough=0.32, metal=0.0)

    # 1. Armature erzeugen
    arm_data = bpy.data.armatures.new("FP_Arms_Armature")
    arm_obj = bpy.data.objects.new("FP_Arms_Rig", arm_data)
    coll.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    ebones = arm_data.edit_bones

    root_bone = ebones.new("root")
    root_bone.head = Vector((0.0, 0.0, 0.0))
    root_bone.tail = Vector((0.0, 0.08, 0.0))

    bm = bmesh.new()
    vert_weights = []

    build_arm_geometry_and_bones("R", +1.0, bm, vert_weights, ebones, root_bone)
    build_arm_geometry_and_bones("L", -1.0, bm, vert_weights, ebones, root_bone)

    bpy.ops.object.mode_set(mode="OBJECT")

    # 2. Mesh erzeugen & Vertex-Groups exakt zuweisen
    me = bpy.data.meshes.new("FP_Arms_Mesh")
    bm.verts.ensure_lookup_table()
    # Vor bm.to_mesh die Vert-Indizes sichern!
    indexed_weights = [(v.index, bname, w) for (v, bname, w) in vert_weights]
    bm.to_mesh(me)
    bm.free()

    for m in (mat_skin, mat_sleeve, mat_cuff, mat_nail):
        me.materials.append(m)

    mesh_obj = bpy.data.objects.new("FP_Arms_Body", me)
    coll.objects.link(mesh_obj)
    mesh_obj.parent = arm_obj

    vgroups = {}
    for b in arm_data.bones:
        vgroups[b.name] = mesh_obj.vertex_groups.new(name=b.name)
    for vidx, bname, w in indexed_weights:
        vgroups[bname].add([vidx], w, "ADD")

    arm_mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    arm_mod.object = arm_obj

    # 3. Pose-Mode für die 5 Animationen!
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")

    # --- ANIMATION 1: extinguisher_idle (millimetergenauer Zweihand-Griff) ---
    # Rechte Hand greift von rechts-hinten um den Tragegriff (0, 0.293, 0.04) & Auslösehebel (0, 0.325, 0.04)
    # Linke Hand greift von links-unten fest um Schlauch & Löschdüse (0, 0.0, -0.205)
    def anim_extinguisher_idle(ao):
        for frame, breath in [(1, 0.0), (20, 0.004), (40, 0.0)]:
            pose_arm(
                ao, "R",
                wrist_g=(0.040, 0.292 + breath, 0.100),
                elbow_g=(0.28, -0.02, 0.56),
                hand_fwd_g=(-0.18, 0.05, -0.98),
                hand_back_up_g=(0.76, 0.64, 0.08),
                finger_curls={
                    "index":  (66, 78, 54),
                    "middle": (70, 82, 58),
                    "ring":   (72, 82, 58),
                    "pinky":  (66, 76, 52),
                },
                thumb_angles=((-22, 24, -34), (-18, 0, 0)),
            )
            pose_arm(
                ao, "L",
                wrist_g=(-0.040, -0.024 + breath * 0.7, -0.186),
                elbow_g=(-0.34, -0.22, 0.32),
                hand_fwd_g=(0.26, 0.10, -0.96),
                hand_back_up_g=(-0.74, -0.66, -0.10),
                finger_curls={
                    "index":  (76, 86, 62),
                    "middle": (80, 90, 64),
                    "ring":   (78, 88, 62),
                    "pinky":  (72, 82, 56),
                },
                thumb_angles=((-32, -18, 40), (-26, 0, 0)),
            )
            keyframe_all_bones(ao, frame)

    build_action(arm_obj, "extinguisher_idle", anim_extinguisher_idle, 40)

    # --- ANIMATION 2: extinguisher_spray (Hebel drücken + leichter CO2-Rückstoß) ---
    def anim_extinguisher_spray(ao):
        frames = [
            (1,  0.000,  0.000),
            (5,  0.002, -0.002),
            (9, -0.002,  0.001),
            (13, 0.002,  0.002),
            (17, 0.000,  0.000),
        ]
        for frame, jx, jy in frames:
            pose_arm(
                ao, "R",
                wrist_g=(0.038 + jx, 0.286 + jy, 0.104),
                elbow_g=(0.28, -0.03, 0.56),
                hand_fwd_g=(-0.20, 0.02, -0.98),
                hand_back_up_g=(0.72, 0.68, 0.08),
                finger_curls={
                    "index":  (80, 92, 64),
                    "middle": (84, 94, 66),
                    "ring":   (84, 94, 66),
                    "pinky":  (78, 88, 62),
                },
                thumb_angles=((-36, 26, -38), (-28, 0, 0)),
            )
            pose_arm(
                ao, "L",
                wrist_g=(-0.038 - jx * 0.7, -0.022 + jy * 0.7, -0.182),
                elbow_g=(-0.34, -0.22, 0.32),
                hand_fwd_g=(0.26, 0.12, -0.95),
                hand_back_up_g=(-0.74, -0.66, -0.10),
                finger_curls={
                    "index":  (80, 90, 64),
                    "middle": (84, 92, 66),
                    "ring":   (82, 90, 64),
                    "pinky":  (76, 84, 58),
                },
                thumb_angles=((-36, -18, 42), (-28, 0, 0)),
            )
            keyframe_all_bones(ao, frame)

    build_action(arm_obj, "extinguisher_spray", anim_extinguisher_spray, 17)

    # --- ANIMATION 3: hold_box_twohand (Kartons, Server, Racks, 6er-Packs) ---
    def anim_hold_box_twohand(ao):
        for frame, b in [(1, 0.0), (20, 0.005), (40, 0.0)]:
            pose_arm(
                ao, "R",
                wrist_g=(0.250, -0.015 + b, 0.095),
                elbow_g=(0.44, -0.24, 0.54),
                hand_fwd_g=(-0.08, 0.12, -0.99),
                hand_back_up_g=(0.95, 0.22, 0.0),
                finger_curls={
                    "index":  (28, 32, 22),
                    "middle": (30, 34, 24),
                    "ring":   (32, 36, 24),
                    "pinky":  (30, 34, 22),
                },
                thumb_angles=((-10, 14, -18), (-10, 0, 0)),
            )
            pose_arm(
                ao, "L",
                wrist_g=(-0.250, -0.015 + b, 0.095),
                elbow_g=(-0.44, -0.24, 0.54),
                hand_fwd_g=(0.08, 0.12, -0.99),
                hand_back_up_g=(-0.95, 0.22, 0.0),
                finger_curls={
                    "index":  (28, 32, 22),
                    "middle": (30, 34, 24),
                    "ring":   (32, 36, 24),
                    "pinky":  (30, 34, 22),
                },
                thumb_angles=((-10, -14, 18), (-10, 0, 0)),
            )
            keyframe_all_bones(ao, frame)

    build_action(arm_obj, "hold_box_twohand", anim_hold_box_twohand, 40)

    # --- ANIMATION 4: hold_item_onehand (Repair Kits & Einzelteile) ---
    def anim_hold_item_onehand(ao):
        for frame, b in [(1, 0.0), (20, 0.004), (40, 0.0)]:
            pose_arm(
                ao, "R",
                wrist_g=(0.018, -0.095 + b, 0.105),
                elbow_g=(0.26, -0.32, 0.55),
                hand_fwd_g=(-0.06, 0.08, -0.99),
                hand_back_up_g=(0.14, -0.98, -0.08), # Handfläche nach oben!
                finger_curls={
                    "index":  (22, 26, 18),
                    "middle": (24, 28, 20),
                    "ring":   (26, 30, 20),
                    "pinky":  (24, 28, 18),
                },
                thumb_angles=((-12, 12, -20), (-12, 0, 0)),
            )
            # Linker Arm außerhalb der Kamera geparkt
            pose_arm(
                ao, "L",
                wrist_g=(-0.60, -0.85, 0.35),
                elbow_g=(-0.75, -1.15, 0.65),
                hand_fwd_g=(0.0, -0.3, -0.95),
                hand_back_up_g=(-1.0, 0.0, 0.0),
                finger_curls={"index": (20, 20, 15), "middle": (20, 20, 15), "ring": (20, 20, 15), "pinky": (20, 20, 15)},
                thumb_angles=((0, 0, 0), (0, 0, 0)),
            )
            keyframe_all_bones(ao, frame)

    build_action(arm_obj, "hold_item_onehand", anim_hold_item_onehand, 40)

    # --- ANIMATION 5: hold_cable (Strom- & LAN-Kabelstecker) ---
    def anim_hold_cable(ao):
        for frame, b in [(1, 0.0), (20, 0.003), (40, 0.0)]:
            pose_arm(
                ao, "R",
                wrist_g=(0.045, -0.075 + b, 0.125),
                elbow_g=(0.28, -0.30, 0.56),
                hand_fwd_g=(-0.18, 0.16, -0.97),
                hand_back_up_g=(0.82, 0.55, 0.10),
                finger_curls={
                    "index":  (52, 64, 42),
                    "middle": (64, 76, 52),
                    "ring":   (70, 82, 55),
                    "pinky":  (72, 84, 56),
                },
                thumb_angles=((-26, 20, -34), (-20, 0, 0)),
            )
            pose_arm(
                ao, "L",
                wrist_g=(-0.60, -0.85, 0.35),
                elbow_g=(-0.75, -1.15, 0.65),
                hand_fwd_g=(0.0, -0.3, -0.95),
                hand_back_up_g=(-1.0, 0.0, 0.0),
                finger_curls={"index": (20, 20, 15), "middle": (20, 20, 15), "ring": (20, 20, 15), "pinky": (20, 20, 15)},
                thumb_angles=((0, 0, 0), (0, 0, 0)),
            )
            keyframe_all_bones(ao, frame)

    build_action(arm_obj, "hold_cable", anim_hold_cable, 40)

    bpy.ops.object.mode_set(mode="OBJECT")

    # Export als GLB mit NLA-Animationen
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    arm_obj.select_set(True)
    mesh_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj

    bpy.ops.export_scene.gltf(
        filepath=OUT_PATH,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_nla_strips=True,
        export_nla_strips_merged_animation_name="",
    )
    print("EXPORTED_FP_ARMS:", OUT_PATH, f"{os.path.getsize(OUT_PATH) / 1024.0:.1f} KB")


if __name__ == "__main__":
    build_fp_arms()
