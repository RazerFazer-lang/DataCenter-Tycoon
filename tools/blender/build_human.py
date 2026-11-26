"""Blender 5.2: eigene, leicht stilisierte Menschen (Paket D, Roadmap 3).

  human.glb  Ein Skelett, darauf viele austauschbare Teile:
    Head, Eyes, Lids, Brows_*, Hair_*, Beard_*, Hands, Arms, Legs, Torso-Kleidung Top_*, Hosen Bottom_*, Schuhe Shoes_*,
    Kopfbedeckung Hat_*, Brillen Glasses_*, Zubehoer Acc_*
  Formen (Shape Keys): Koerper Body_Slim/Body_Heavy/Body_Strong/Body_Fem auf allen Koerperteilen,
    Gesicht Face_* auf Head, dazu Blink, Mouth_Open, Smile, Brow_Up.
  Materialien: Skin, Eye_White, Eye_Iris, Eye_Pupil, Hair, Lip, Top_A/B/C, Bottom_A/B, Shoe_A/B, Acc_A/B, Metal, Reflect, Glass, Dark.

Blick nach +Z (Spiel), Fuesse auf y = 0, Groesse 1,80 m, Ruhehaltung: Arme 45 Grad abgesenkt.
Aufruf: blender --background --factory-startup --python tools/blender/build_human.py
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import dct_paths  # noqa: E402

OUT = os.path.join(dct_paths.MODELS_DIR, "human.glb")
V = Vector


def g(x, y, z):
    return V((x, -z, y))


def back(co):
    """Blender -> Spiel (x, y, z)."""
    return (co.x, co.z, -co.y)


# ---------------------------------------------------------------- Skelett

A = math.radians(45)
SH = (0.163, 1.436, -0.012)
EL = (SH[0] + 0.272 * math.cos(A), SH[1] - 0.272 * math.sin(A), -0.014)
WR = (EL[0] + 0.252 * math.cos(A), EL[1] - 0.252 * math.sin(A), 0.004)
FB = (WR[0] + 0.088 * math.cos(A), WR[1] - 0.088 * math.sin(A), 0.008)
FT = (FB[0] + 0.050 * math.cos(A), FB[1] - 0.050 * math.sin(A), 0.010)
FE = (FT[0] + 0.040 * math.cos(A), FT[1] - 0.040 * math.sin(A), 0.011)

BONES = [
    ("Hips", None, (0, 0.965, 0.0), (0, 1.06, 0.0)),
    ("Spine", "Hips", (0, 1.06, 0.0), (0, 1.20, 0.004)),
    ("Spine1", "Spine", (0, 1.20, 0.004), (0, 1.335, -0.004)),
    ("Spine2", "Spine1", (0, 1.335, -0.004), (0, 1.480, -0.014)),
    ("Neck", "Spine2", (0, 1.470, -0.014), (0, 1.550, -0.004)),
    ("Head", "Neck", (0, 1.550, -0.004), (0, 1.778, 0.0)),
    ("Jaw", "Head", (0, 1.616, 0.020), (0, 1.566, 0.080)),
]
for side, s in (("Left", 1), ("Right", -1)):
    def m(p, s=s):
        return (p[0] * s, p[1], p[2])
    BONES += [
        (side + "Shoulder", "Spine2", m((0.028, 1.440, -0.008)), m(SH)),
        (side + "Arm", side + "Shoulder", m(SH), m(EL)),
        (side + "ForeArm", side + "Arm", m(EL), m(WR)),
        (side + "Hand", side + "ForeArm", m(WR), m(FB)),
        (side + "Fingers1", side + "Hand", m(FB), m(FT)),
        (side + "Fingers2", side + "Fingers1", m(FT), m(FE)),
        (side + "Thumb1", side + "Hand", m((WR[0] + 0.030, WR[1] - 0.012, 0.030)), m((WR[0] + 0.070, WR[1] - 0.046, 0.052))),
        (side + "Thumb2", side + "Thumb1", m((WR[0] + 0.070, WR[1] - 0.046, 0.052)), m((WR[0] + 0.092, WR[1] - 0.070, 0.056))),
        (side + "UpLeg", "Hips", m((0.094, 0.930, 0.0)), m((0.100, 0.500, 0.008))),
        (side + "Leg", side + "UpLeg", m((0.100, 0.500, 0.008)), m((0.103, 0.092, -0.022))),
        (side + "Foot", side + "Leg", m((0.103, 0.092, -0.022)), m((0.106, 0.028, 0.090))),
        (side + "Toe", side + "Foot", m((0.106, 0.028, 0.090)), m((0.108, 0.022, 0.160))),
    ]
BONE_SEG = {n: (g(*a), g(*b)) for n, p, a, b in BONES}


def build_armature():
    ad = bpy.data.armatures.new("Rig")
    ob = bpy.data.objects.new("Rig", ad)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for n, p, a, b in BONES:
        e = ad.edit_bones.new(n)
        e.head = g(*a)
        e.tail = g(*b)
        e.roll = 0.0
        if p:
            e.parent = eb[p]
        eb[n] = e
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


# ---------------------------------------------------------------- Materialien

MATS = {}


def mat(name, rgb=(0.8, 0.8, 0.8), rough=0.6, metal=0.0, emit=0.0):
    if name in MATS:
        return MATS[name]
    mm = bpy.data.materials.new(name)
    mm.use_nodes = True
    b = mm.node_tree.nodes["Principled BSDF"]
    lin = tuple(c ** 2.2 for c in rgb)
    b.inputs["Base Color"].default_value = (*lin, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*lin, 1.0)
        b.inputs["Emission Strength"].default_value = emit
    MATS[name] = mm
    return mm


def all_mats():
    mat("Skin", (0.93, 0.76, 0.64), 0.55)
    mat("Eye_White", (0.95, 0.95, 0.94), 0.25)
    mat("Eye_Iris", (0.30, 0.45, 0.62), 0.20)
    mat("Eye_Pupil", (0.02, 0.02, 0.02), 0.08)
    mat("Hair", (0.22, 0.14, 0.08), 0.62)
    mat("Mouth", (0.22, 0.06, 0.06), 0.6)
    mat("Lip", (0.80, 0.48, 0.44), 0.42)
    mat("Teeth", (0.94, 0.93, 0.90), 0.3)
    mat("Top_A", (0.20, 0.34, 0.60), 0.85)
    mat("Top_B", (0.86, 0.87, 0.88), 0.85)
    mat("Top_C", (0.10, 0.11, 0.13), 0.7)
    mat("Bottom_A", (0.17, 0.22, 0.32), 0.88)
    mat("Bottom_B", (0.10, 0.11, 0.13), 0.7)
    mat("Shoe_A", (0.16, 0.16, 0.18), 0.6)
    mat("Shoe_B", (0.90, 0.90, 0.88), 0.7)
    mat("Acc_A", (0.90, 0.50, 0.10), 0.6)
    mat("Acc_B", (0.10, 0.10, 0.11), 0.55)
    mat("Metal", (0.72, 0.74, 0.77), 0.25, 0.95)
    mat("Reflect", (0.88, 0.90, 0.86), 0.25, 0.35, 0.25)
    mat("Glass", (0.12, 0.14, 0.17), 0.05, 0.2)
    mat("Dark", (0.05, 0.05, 0.06), 0.6)


# ---------------------------------------------------------------- Volumen -> Netz

_UNIT = {}


def unit_sphere(seg):
    if seg not in _UNIT:
        rings = seg // 2 + 1
        vs = [(0.0, 0.0, 1.0)]
        fs = []
        for r in range(1, rings):
            a = math.pi * r / rings
            for k in range(seg):
                b = 2 * math.pi * k / seg
                vs.append((math.sin(a) * math.cos(b), math.sin(a) * math.sin(b), math.cos(a)))
        vs.append((0.0, 0.0, -1.0))
        last = len(vs) - 1
        for k in range(seg):
            fs.append((0, 1 + k, 1 + (k + 1) % seg))
            for r in range(rings - 2):
                o = 1 + r * seg
                fs.append((o + k, o + seg + k, o + seg + (k + 1) % seg, o + (k + 1) % seg))
            o = 1 + (rings - 2) * seg
            fs.append((last, o + (k + 1) % seg, o + k))
        _UNIT[seg] = ([V(v) for v in vs], fs)
    return _UNIT[seg]


class Blob:
    """Vereinigung aus Kugeln, Ellipsoiden und Kapseln, per Voxel-Remesh zu einer glatten Haut."""

    def __init__(self):
        self.vs = []
        self.fs = []

    def _sphere(self, mx, seg):
        vs, fs = unit_sphere(seg)
        o = len(self.vs)
        self.vs += [mx @ v for v in vs]
        self.fs += [tuple(o + i for i in f) for f in fs]

    def ell(self, c, r, rot=(0, 0, 0), seg=20):
        mx = Matrix.Translation(g(*c)) @ (Matrix.Rotation(math.radians(rot[1]), 4, "Z") @ Matrix.Rotation(math.radians(rot[0]), 4, "X") @ Matrix.Rotation(math.radians(-rot[2]), 4, "Y")) @ Matrix.Diagonal((r[0], r[2], r[1], 1.0))
        self._sphere(mx, seg)
        return self

    def sph(self, c, r, seg=14):
        self._sphere(Matrix.Translation(g(*c)) @ Matrix.Diagonal((r, r, r, 1.0)), seg)
        return self

    def cap(self, a, ra, b, rb, seg=18, n=4):
        """Kapsel mit veraenderlichem Radius."""
        a, b = V(a), V(b)
        d = b - a
        q = V((0, 1, 0)).rotation_difference(d.normalized()) if d.length > 1e-6 else Matrix.Identity(3).to_quaternion()
        self.sph(tuple(a), ra, seg)
        self.sph(tuple(b), rb, seg)
        o = len(self.vs)
        for i in range(n + 1):
            t = i / n
            c = a + d * t
            r = ra + (rb - ra) * t
            for k in range(seg):
                an = 2 * math.pi * k / seg
                p = q @ V((math.cos(an) * r, 0, math.sin(an) * r)) + c
                self.vs.append(g(p.x, p.y, p.z))
        for i in range(n):
            for k in range(seg):
                self.fs.append((o + i * seg + k, o + i * seg + (k + 1) % seg, o + (i + 1) * seg + (k + 1) % seg, o + (i + 1) * seg + k))
        self.fs.append(tuple(o + k for k in range(seg))[::-1])
        self.fs.append(tuple(o + n * seg + k for k in range(seg)))
        return self

    def chain(self, pts):
        for (a, ra), (b, rb) in zip(pts, pts[1:]):
            self.cap(a, ra, b, rb)
        return self

    def mesh(self, name, voxel=0.008, smooth=6, factor=0.5, faces=None):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.vs, [], self.fs)
        me.update()
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        r = ob.modifiers.new("r", "REMESH")
        r.mode = "VOXEL"
        r.voxel_size = voxel
        r.adaptivity = 0.0
        if smooth:
            sm = ob.modifiers.new("s", "SMOOTH")
            sm.factor = factor
            sm.iterations = smooth
        return apply_mods(ob, faces)


def apply_mods(ob, faces=None):
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    ob.modifiers.clear()
    old = ob.data
    ob.data = me
    bpy.data.meshes.remove(old)
    if faces and len(me.polygons) * 2 > faces:
        d = ob.modifiers.new("d", "DECIMATE")
        d.ratio = faces / (len(me.polygons) * 2.0)
        return apply_mods(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def edit(ob, fn):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    fn(bm)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    return ob


def bis(ob, planes):
    """Saubere Schnittkanten einziehen: [(Punkt, Normale)] in Spielkoordinaten."""
    def fn(bm):
        for co, no in planes:
            bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), dist=0.00005, plane_co=g(*co), plane_no=g(*no))
    return edit(ob, fn)


def ypl(*ys):
    return [((0, y, 0), (0, 1, 0)) for y in ys]


def xpl(*xs):
    return [((s * x, 0, 0), (1, 0, 0)) for x in xs for s in (-1, 1)]


def armpl(*ts):
    """Ebenen quer zum Arm, t in Metern ab Schulter."""
    out = []
    for t in ts:
        for s in (-1, 1):
            d = (s * math.cos(A), -math.sin(A), 0)
            out.append(((SH[0] * s + d[0] * t, SH[1] + d[1] * t, 0), d))
    return out


def deci(ob, faces):
    n = len(ob.data.polygons) * 2
    if faces and n > faces:
        d = ob.modifiers.new("d", "DECIMATE")
        d.ratio = faces / float(n)
        apply_mods(ob)
    return ob


def arm_len():
    return (V((WR[0], WR[1], 0)) - V((SH[0], SH[1], 0))).length


def cut(ob, keep):
    """Nur Flaechen behalten, deren Mitte keep(x, y, z) erfuellt (Spielkoordinaten)."""
    def fn(bm):
        dele = [f for f in bm.faces if not keep(*back(f.calc_center_median()))]
        bmesh.ops.delete(bm, geom=dele, context="FACES")
    return edit(ob, fn)


def move(ob, fn):
    """Jeden Punkt verschieben: fn(x, y, z, normal) -> (x, y, z)."""
    me = ob.data
    ns = [v.normal.copy() for v in me.vertices]
    for v, n in zip(me.vertices, ns):
        x, y, z = back(v.co)
        v.co = g(*fn(x, y, z, back(n)))
    me.update()
    return ob


def wrinkle(ob, spots, amp=0.004):
    """Falten an Gelenken: spots = [(Punkt, Achse, Radius, Staerke)]."""
    def fn(x, y, z, n):
        p = V((x, y, z))
        off = 0.0
        for c, ax, r, s in spots:
            d = p - V(c)
            q = d.length / r
            if q < 1.0:
                t = d.dot(V(ax).normalized()) / r
                off += s * (1 - q * q) * math.sin(t * 11.0 + noise.noise(p * 22.0) * 3.0)
        off += 0.35 * noise.noise(p * 14.0)
        return (x + n[0] * off * amp, y + n[1] * off * amp, z + n[2] * off * amp)
    return move(ob, fn)


def solidify(ob, t=0.006):
    s = ob.modifiers.new("so", "SOLIDIFY")
    s.thickness = t
    s.offset = -1.0
    return apply_mods(ob)


def set_mats(ob, names, pick=None):
    ob.data.materials.clear()
    for n in names:
        ob.data.materials.append(mat(n))
    if pick:
        for p in ob.data.polygons:
            c = back(p.center)
            p.material_index = pick(*c)
    return ob


def box(name, parts, matname, bevel=0.004):
    """parts: [(center, size, rot)] in Spielkoordinaten."""
    bm = bmesh.new()
    for it in parts:
        c, s = it[0], it[1]
        rot = it[2] if len(it) > 2 else (0, 0, 0)
        mx = Matrix.Translation(g(*c)) @ Matrix.Rotation(math.radians(rot[1]), 4, "Z") @ Matrix.Rotation(math.radians(rot[0]), 4, "X") @ Matrix.Rotation(math.radians(-rot[2]), 4, "Y") @ Matrix.Diagonal((s[0], s[2], s[1], 1.0))
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        bmesh.ops.transform(t, matrix=mx, verts=t.verts)
        if bevel:
            bmesh.ops.bevel(t, geom=list(t.edges), offset=min(bevel, min(s) * 0.3), segments=2, profile=0.6, affect="EDGES")
        me = bpy.data.meshes.new("t")
        t.to_mesh(me)
        t.free()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    set_mats(ob, [matname])
    return ob


def tube(name, pts, r, matname, seg=10):
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        a = V(pts[max(0, i - 1)])
        b = V(pts[min(len(pts) - 1, i + 1)])
        q = V((0, 1, 0)).rotation_difference((b - a).normalized())
        row = []
        for k in range(seg):
            an = 2 * math.pi * k / seg
            o = q @ V((math.cos(an) * r, 0, math.sin(an) * r)) + V(p)
            row.append(bm.verts.new(g(*o)))
        rings.append(row)
    for i in range(len(rings) - 1):
        for k in range(seg):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % seg], rings[i + 1][(k + 1) % seg], rings[i + 1][k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    set_mats(ob, [matname])
    return ob


def join(name, obs):
    obs = [o for o in obs if o is not None]
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


# ---------------------------------------------------------------- Gewichte und Formen

SIDE_BONES = ("Shoulder", "Arm", "ForeArm", "Hand", "Fingers1", "Fingers2", "Thumb1", "Thumb2", "UpLeg", "Leg", "Foot", "Toe")
GROUPS = {
    "head": ["Head", "Neck"],
    "top": ["Hips", "Spine", "Spine1", "Spine2", "Neck", "LeftShoulder", "LeftArm", "LeftForeArm", "RightShoulder", "RightArm", "RightForeArm"],
    "bottom": ["Hips", "Spine", "LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg"],
    "arms": ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"],
    "hands": ["LeftForeArm", "LeftHand", "LeftFingers1", "LeftFingers2", "LeftThumb1", "LeftThumb2", "RightForeArm", "RightHand", "RightFingers1", "RightFingers2", "RightThumb1", "RightThumb2"],
    "shoes": ["LeftLeg", "LeftFoot", "LeftToe", "RightLeg", "RightFoot", "RightToe"],
}
RAD = {"Hips": 0.10, "Spine": 0.11, "Spine1": 0.12, "Spine2": 0.12, "Neck": 0.05, "Head": 0.09, "Jaw": 0.03, "Shoulder": 0.055, "Arm": 0.045, "ForeArm": 0.035, "Hand": 0.022,
       "Fingers1": 0.012, "Fingers2": 0.010, "Thumb1": 0.010, "Thumb2": 0.008, "UpLeg": 0.075, "Leg": 0.05, "Foot": 0.035, "Toe": 0.025}


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


def weights(ob, rig, bones, rigid=None, power=4.0):
    vgs = {}
    for v in ob.data.vertices:
        x, y, z = back(v.co)
        if rigid:
            b = rigid if isinstance(rigid, str) else rigid(x, y, z)
            w = {b: 1.0}
        else:
            w = {}
            for b in bones:
                if b.startswith("Left") and x < -0.004 or b.startswith("Right") and x > 0.004:
                    # Beine trennen streng nach Seite, oben darf es weich sein
                    continue
                a, e = BONE_SEG[b]
                key = b.replace("Left", "").replace("Right", "")
                d = max(0.003, seg_dist(v.co, a, e) - RAD[key] * 0.55)
                w[b] = 1.0 / (d ** power)
            top = sorted(w.items(), key=lambda kv: -kv[1])[:4]
            s = sum(k[1] for k in top)
            w = {k: q / s for k, q in top if q / s > 0.015}
            s = sum(w.values())
            w = {k: q / s for k, q in w.items()}
        for b, q in w.items():
            if b not in vgs:
                vgs[b] = ob.vertex_groups.new(name=b)
            vgs[b].add([v.index], q, "REPLACE")
    ob.parent = rig
    md = ob.modifiers.new("Armature", "ARMATURE")
    md.object = rig


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def arm_mask(x, y):
    """1 am Rumpf, 0 am Arm."""
    ax = abs(x)
    line = 1.46 - (ax - 0.15)
    return 1.0 - smoothstep(0.0, 0.05, ax - 0.165) if y > 1.0 else 1.0


def limb_axis(x, y):
    """Naechster Punkt der Armachse (Spiel)."""
    s = 1 if x >= 0 else -1
    a, b = V((SH[0] * s, SH[1], SH[2])), V((WR[0] * s, WR[1], WR[2]))
    p = V((x, y, 0))
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return a + ab * t


def body_shape(kind, x, y, z):
    m = arm_mask(x, y) if y > 1.02 else 1.0
    cx, cz = 0.0, 0.0
    sx = sz = 1.0
    dz = 0.0
    if y > 0.86 and m > 0.0:
        if kind == "Slim":
            sx = 1 - 0.10 * m
            sz = 1 - 0.14 * m
        elif kind == "Heavy":
            b = math.exp(-((y - 1.10) / 0.15) ** 2)
            c = math.exp(-((y - 1.32) / 0.14) ** 2)
            sx = 1 + (0.16 + 0.22 * b + 0.06 * c) * m
            sz = 1 + (0.10 + 0.34 * b) * m
            dz = 0.034 * b * m * (1 if z > 0 else 0.25)
        elif kind == "Strong":
            c = math.exp(-((y - 1.37) / 0.10) ** 2)
            b = math.exp(-((y - 1.12) / 0.10) ** 2)
            sx = 1 + (0.13 * c - 0.02 * b) * m
            sz = 1 + 0.16 * c * m
        elif kind == "Fem":
            w = math.exp(-((y - 1.14) / 0.075) ** 2)
            hip = math.exp(-((y - 0.95) / 0.09) ** 2)
            sh = math.exp(-((y - 1.43) / 0.08) ** 2)
            ch = math.exp(-((y - 1.325) / 0.055) ** 2)
            sx = 1 + (-0.13 * w + 0.08 * hip - 0.11 * sh) * m
            sz = 1 + (-0.10 * w + 0.05 * hip) * m
            side = math.exp(-((abs(x) - 0.075) / 0.05) ** 2)
            dz = 0.034 * ch * side * m * (1 if z > 0.02 else 0)
        x, z = x * sx, z * sz + dz
    if y > 1.0 and m < 1.0:
        a = limb_axis(x, y)
        k = {"Slim": 0.86, "Heavy": 1.15, "Strong": 1.20, "Fem": 0.86}[kind]
        k = 1 + (k - 1) * (1 - m)
        o = V((x, y, z)) - a
        n = a + o * k
        if kind == "Fem":
            n.x -= 0.014 * (1 if x > 0 else -1) * (1 - m)
        x, y, z = n
    elif y <= 0.90:
        s = 1 if x >= 0 else -1
        ax = 0.098 * s
        k = {"Slim": 0.90, "Heavy": 1.14, "Strong": 1.09, "Fem": 0.97}[kind]
        k = 1 + (k - 1) * smoothstep(0.05, 0.30, y)
        x, z = ax + (x - ax) * k, z * k
        if kind == "Fem":
            hip = math.exp(-((y - 0.86) / 0.12) ** 2)
            x += 0.010 * s * hip
    return x, y, z


HEAD_DY = 0.024


def lower(ob):
    """Kopf naeher an die Schultern setzen (auch in allen Formen)."""
    def f(co):
        x, y, z = back(co)
        return g(x, y - HEAD_DY * smoothstep(1.46, 1.54, y), z)
    if ob.data.shape_keys:
        for kb in ob.data.shape_keys.key_blocks:
            for d in kb.data:
                d.co = f(d.co)
    for v in ob.data.vertices:
        v.co = f(v.co)
    ob.data.update()


def add_shapes(ob, kinds=("Slim", "Heavy", "Strong", "Fem")):
    if ob.data.shape_keys is None:
        ob.shape_key_add(name="Basis")
    for k in kinds:
        sk = ob.shape_key_add(name="Body_" + k)
        for v in ob.data.vertices:
            sk.data[v.index].co = g(*body_shape(k, *back(v.co)))


def shape(ob, name, fn):
    if ob.data.shape_keys is None:
        ob.shape_key_add(name="Basis")
    sk = ob.shape_key_add(name=name)
    for v in ob.data.vertices:
        sk.data[v.index].co = g(*fn(*back(v.co)))


def vcol(ob, fn):
    """Punktfarben (multiplizieren die Materialfarbe)."""
    me = ob.data
    ca = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    for lp in me.loops:
        c = fn(*back(me.vertices[lp.vertex_index].co))
        ca.data[lp.index].color_srgb = (c[0], c[1], c[2], 1.0)


# ---------------------------------------------------------------- Kopf

EYE = (0.0315, 1.672, 0.0665)
EYE_R = 0.0152


def gauss(d2, s):
    return math.exp(-d2 / (s * s))


def head_base():
    b = Blob()
    b.ell((0, 1.716, -0.014), (0.0775, 0.0960, 0.0960))
    b.ell((0, 1.662, 0.026), (0.0640, 0.0860, 0.0620))
    b.ell((0, 1.606, 0.030), (0.0490, 0.0380, 0.0520))
    b.ell((0, 1.586, 0.060), (0.0235, 0.0205, 0.0220))
    for s in (-1, 1):
        b.ell((s * 0.0400, 1.640, 0.050), (0.0260, 0.0250, 0.0230))
        b.ell((s * 0.0490, 1.618, 0.006), (0.0120, 0.0260, 0.0260))
        b.ell((s * 0.0805, 1.668, -0.012), (0.0105, 0.0310, 0.0190), (0, s * 22, s * -6))
        b.sph((s * 0.0115, 1.6410, 0.0985), 0.0086)
    b.ell((0, 1.699, 0.072), (0.0540, 0.0135, 0.0185))
    b.cap((0, 1.692, 0.083), 0.0082, (0, 1.646, 0.1055), 0.0118)
    b.ell((0, 1.6060, 0.0740), (0.0230, 0.0120, 0.0090))
    b.cap((0, 1.450, -0.022), 0.0640, (0, 1.600, -0.012), 0.0560)
    b.cap((0, 1.430, -0.026), 0.0800, (0, 1.470, -0.022), 0.0620)
    ob = b.mesh("Face", 0.0042, 5, 0.5, 10500)

    def sockets(x, y, z, n):
        for s in (-1, 1):
            d2 = (x - s * EYE[0]) ** 2 + ((y - EYE[1]) * 1.25) ** 2
            if z > 0.03 and d2 < 0.0012:
                z -= 0.0125 * gauss(d2, 0.0165)
        # Lippenspalt und Philtrum
        if z > 0.05 and abs(x) < 0.026:
            z -= 0.0030 * gauss(((y - 1.6062) ** 2) * 2, 0.0060) * gauss(x * x, 0.020)
            z -= 0.0016 * gauss(x * x, 0.004) * gauss((y - 1.624) ** 2, 0.009)
        # Nasenloecher
        for s in (-1, 1):
            d2 = (x - s * 0.0085) ** 2 + (y - 1.6335) ** 2 + (z - 0.098) ** 2
            y += 0.0035 * gauss(d2, 0.0052)
        # Ohrmuschel
        for s in (-1, 1):
            d2 = (x - s * 0.090) ** 2 + (y - 1.670) ** 2 + (z + 0.006) ** 2
            if d2 < 0.0006:
                x -= s * 0.0050 * gauss(d2, 0.0120)
        return x, y, z
    move(ob, sockets)
    set_mats(ob, ["Skin", "Mouth"])

    def col(x, y, z):
        c = [1.0, 1.0, 1.0]
        lip = 0.0
        if False:
            lip = smoothstep(0.0265, 0.016, abs(x)) * gauss(((y - 1.606) * 1.0) ** 2, 0.0068)
        cheek = 0.0
        for s in (-1, 1):
            cheek += gauss((x - s * 0.044) ** 2 + (y - 1.640) ** 2, 0.022) if z > 0.02 else 0
        nose = gauss(x * x + (y - 1.644) ** 2, 0.014) if z > 0.085 else 0
        ear = 0.6 if abs(x) > 0.083 else 0.0
        eye = 0.0
        for s in (-1, 1):
            eye += gauss((x - s * EYE[0]) ** 2 + ((y - EYE[1]) * 1.3) ** 2, 0.019) if z > 0.03 else 0
        under = smoothstep(1.592, 1.565, y) * smoothstep(1.50, 1.55, y) * 0.10
        c[0] *= 1 - 0.14 * lip - 0.12 * eye - under
        c[1] *= 1 - 0.30 * lip - 0.045 * cheek - 0.05 * nose - 0.06 * ear - 0.13 * eye - under * 1.1
        c[2] *= 1 - 0.27 * lip - 0.040 * cheek - 0.045 * nose - 0.05 * ear - 0.13 * eye - under * 1.1
        return c
    vcol(ob, col)
    return ob


def face_keys(ob):
    def jaw_open(x, y, z):
        k = smoothstep(1.6065, 1.600, y) * smoothstep(-0.02, 0.05, z) * smoothstep(1.50, 1.565, y)
        return x * (1 - 0.06 * k), y - 0.020 * k, z - 0.006 * k
    shape(ob, "Mouth_Open", jaw_open)

    def smile(x, y, z):
        k = 0.0
        for s in (-1, 1):
            k += gauss((x - s * 0.022) ** 2 + (y - 1.607) ** 2, 0.014) * (1 if z > 0.05 else 0)
        ck = 0.0
        for s in (-1, 1):
            ck += gauss((x - s * 0.042) ** 2 + (y - 1.634) ** 2, 0.022) * (1 if z > 0.02 else 0)
        return x * (1 + 0.16 * k), y + 0.0060 * k + 0.0030 * ck, z - 0.0030 * k + 0.0028 * ck
    shape(ob, "Smile", smile)

    def frown(x, y, z):
        k = 0.0
        for s in (-1, 1):
            k += gauss((x - s * 0.023) ** 2 + (y - 1.606) ** 2, 0.012) * (1 if z > 0.05 else 0)
        return x, y - 0.0050 * k, z
    shape(ob, "Frown", frown)
    fs = {
        "Face_Jaw": lambda x, y, z: (x * (1 + 0.16 * gauss((y - 1.604) ** 2, 0.036) * smoothstep(-0.06, 0.0, z)), y, z),
        "Face_Chin": lambda x, y, z: (x, y - 0.012 * gauss((y - 1.585) ** 2 + x * x, 0.030) * smoothstep(0.02, 0.05, z), z + 0.007 * gauss((y - 1.585) ** 2 + x * x, 0.030) * smoothstep(0.02, 0.05, z)),
        "Face_Cheek": lambda x, y, z: (x * (1 + 0.12 * gauss((y - 1.636) ** 2, 0.030) * smoothstep(0.0, 0.04, z)), y, z + 0.006 * gauss((y - 1.632) ** 2 + (abs(x) - 0.045) ** 2, 0.026) * smoothstep(0.0, 0.04, z)),
        "Face_Nose": lambda x, y, z: (x * (1 + 0.18 * gauss((y - 1.643) ** 2 + x * x, 0.020) * smoothstep(0.085, 0.10, z)), y - 0.002 * gauss(x * x + (y - 1.65) ** 2, 0.02), z + 0.011 * gauss(x * x + (y - 1.648) ** 2, 0.017) * smoothstep(0.07, 0.09, z)),
        "Face_Long": lambda x, y, z: (x * 0.965, y + (y - 1.665) * 0.10 * smoothstep(1.55, 1.60, y), z),
        "Face_Round": lambda x, y, z: (x * (1 + 0.075 * smoothstep(1.56, 1.62, y)), y - (y - 1.665) * 0.06 * smoothstep(1.55, 1.60, y), z * (1 + 0.02 * smoothstep(1.56, 1.62, y))),
        "Face_Brow": lambda x, y, z: (x, y - 0.0035 * gauss((y - 1.698) ** 2, 0.012) * smoothstep(0.04, 0.06, z), z + 0.0065 * gauss((y - 1.698) ** 2, 0.012) * smoothstep(0.04, 0.06, z)),
        "Face_Lips": lambda x, y, z: (x * (1 + 0.12 * gauss((y - 1.606) ** 2, 0.010) * smoothstep(0.06, 0.07, z)), y + (y - 1.6062) * 0.5 * gauss((y - 1.606) ** 2, 0.010) * gauss(x * x, 0.02) * smoothstep(0.06, 0.07, z), z + 0.0040 * gauss((y - 1.606) ** 2, 0.010) * gauss(x * x, 0.02) * smoothstep(0.06, 0.07, z)),
        "Face_Ears": lambda x, y, z: (x + (0.010 if x > 0 else -0.010) * smoothstep(0.076, 0.088, abs(x)) * smoothstep(1.60, 1.64, y), y, z),
        "Face_Neck": lambda x, y, z: (x * (1 + 0.16 * smoothstep(1.59, 1.55, y)), y, z * (1 + 0.10 * smoothstep(1.59, 1.55, y))),
    }
    for k, f in fs.items():
        shape(ob, k, f)


def mouth():
    """Lippen als eigene Koerper, dahinter Mundhoehle und Zaehne."""
    up = Blob()
    pts = [(-0.0238, 1.6088, 0.0735, 0.0016), (-0.014, 1.6096, 0.0808, 0.0032), (-0.005, 1.6106, 0.0842, 0.0040), (0.0, 1.6094, 0.0846, 0.0036), (0.005, 1.6106, 0.0842, 0.0040), (0.014, 1.6096, 0.0808, 0.0032), (0.0238, 1.6088, 0.0735, 0.0016)]
    up.chain([((p[0], p[1], p[2]), p[3]) for p in pts])
    lo = Blob()
    pts = [(-0.0228, 1.6080, 0.0735, 0.0016), (-0.013, 1.6034, 0.0798, 0.0040), (0.0, 1.6008, 0.0826, 0.0050), (0.013, 1.6034, 0.0798, 0.0040), (0.0228, 1.6080, 0.0735, 0.0016)]
    lo.chain([((p[0], p[1], p[2]), p[3]) for p in pts])
    a, b = up.mesh("l", 0.0013, 3, 0.45, 700), lo.mesh("l", 0.0013, 3, 0.45, 600)
    ob = join("Lips", [a, b])
    set_mats(ob, ["Lip"])
    face_keys(ob)
    cav = Blob()
    cav.ell((0, 1.6040, 0.0660), (0.0180, 0.0070, 0.0100))
    c = cav.mesh("c", 0.002, 1, 0.3, 300)
    set_mats(c, ["Mouth"])
    th = box("t", [((0, 1.6088, 0.0735), (0.026, 0.0050, 0.0060))], "Teeth", 0.0015)
    c2 = join("MouthIn", [c, th])
    shape(c2, "Mouth_Open", lambda x, y, z: (x, y - 0.012 * smoothstep(1.6065, 1.600, y), z))
    return [ob, c2]


def eyes():
    obs = []
    for s in (-1, 1):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=24, radius=EYE_R, matrix=Matrix.Translation(g(s * EYE[0], EYE[1], EYE[2])) @ Matrix.Rotation(math.radians(90), 4, "X"))
        me = bpy.data.meshes.new("e")
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new("e", me)
        bpy.context.scene.collection.objects.link(ob)

        def pick(x, y, z, s=s):
            d = math.hypot(x - s * EYE[0], y - EYE[1])
            if z < EYE[2]:
                return 0
            return 2 if d < 0.0036 else 1 if d < 0.0080 else 0
        set_mats(ob, ["Eye_White", "Eye_Iris", "Eye_Pupil"], pick)
        for p in me.polygons:
            p.use_smooth = True
        obs.append(ob)
    return join("Eyes", obs)


def lids():
    """Augenlider als Kugelschale, Blink dreht sie zu."""
    obs = []
    for s in (-1, 1):
        for top in (True, False):
            bm = bmesh.new()
            rows = []
            r = EYE_R + 0.0012
            a0, a1 = (100, 17) if top else (-95, -31)
            for i in range(9):
                el = math.radians(a0 + (a1 - a0) * i / 8.0)
                row = []
                for k in range(15):
                    az = math.radians(-82 + 164 * k / 14.0)
                    # Schale um die x-Achse des Auges
                    x = r * math.sin(az)
                    rr = r * math.cos(az)
                    y, z = rr * math.sin(el), rr * math.cos(el)
                    row.append(bm.verts.new(g(s * EYE[0] + x, EYE[1] + y, EYE[2] + z)))
                rows.append(row)
            for i in range(8):
                for k in range(14):
                    f = (rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k])
                    bm.faces.new(f if not top else f[::-1])
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            me = bpy.data.meshes.new("l")
            bm.to_mesh(me)
            bm.free()
            ob = bpy.data.objects.new("l", me)
            bpy.context.scene.collection.objects.link(ob)
            sd = ob.modifiers.new("so", "SOLIDIFY")
            sd.thickness = 0.0016
            sd.offset = 1.0
            apply_mods(ob)
            obs.append(ob)
    ob = join("Lids", obs)
    set_mats(ob, ["Skin"])

    def col(x, y, z):
        t = smoothstep(1.670, 1.690, y)
        edge = gauss((y - EYE[1] - 0.0052) ** 2, 0.0030) if z > EYE[2] + 0.010 else 0
        return (0.92 - 0.62 * edge, 0.85 - 0.62 * edge, 0.83 - 0.62 * edge)
    vcol(ob, col)

    def blink(x, y, z):
        s = 1 if x > 0 else -1
        dy, dz = y - EYE[1], z - EYE[2]
        el = math.atan2(dy, dz)
        rr = math.hypot(dy, dz)
        e0, e1 = (100, 17) if el > -0.05 else (-95, -31)
        f = (math.degrees(el) - e0) / (e1 - e0)
        f = max(0.0, min(1.0, f))
        tgt = -12.0
        el2 = math.radians(e0 + (tgt - e0) * f)
        return x, EYE[1] + rr * math.sin(el2), EYE[2] + rr * math.cos(el2)
    shape(ob, "Blink", blink)

    def narrow(x, y, z):
        b = blink(x, y, z)
        return tuple(a + (c - a) * 0.35 for a, c in zip((x, y, z), b))
    shape(ob, "Squint", narrow)
    return ob


def brows():
    out = []
    for name, th, arch, ang in (("Brows_A", 0.0042, 0.004, 0.0), ("Brows_B", 0.0058, 0.002, -0.002), ("Brows_C", 0.0032, 0.006, 0.001)):
        obs = []
        for s in (-1, 1):
            pts = []
            for i in range(9):
                t = i / 8.0
                x = 0.013 + 0.034 * t
                y = 1.6985 + arch * math.sin(t * math.pi * 0.85) - 0.004 * t * t + ang * (1 - t) * 2
                z = 0.0915 - 0.017 * t * t - 0.002 * t
                pts.append((s * x, y, z))
            b = Blob()
            for i, p in enumerate(pts):
                t = i / 8.0
                r = th * (0.75 + 0.45 * math.sin(min(1.0, t * 1.6) * math.pi * 0.5)) * (1.0 - 0.75 * t ** 3)
                b.ell(p, (0.0062, max(0.0020, r * 0.8), 0.0028), (0, -s * 26 * t, s * -14 * t))
            obs.append(b.mesh("b", 0.0016, 2, 0.4, 500))
        ob = join(name, obs)
        set_mats(ob, ["Hair"])
        shape(ob, "Brow_Up", lambda x, y, z: (x, y + 0.0065, z - 0.0005))
        shape(ob, "Brow_Angry", lambda x, y, z: (x, y - 0.0060 * (1 - smoothstep(0.012, 0.045, abs(x))) + 0.001, z))
        out.append(ob)
    return out


# ---------------------------------------------------------------- Haare

def hair_cap(b, k=1.0, back_low=1.615, vol=0.0):
    b.ell((0, 1.722 + vol * 0.4, -0.016), (0.0830 * k, 0.0985 * k + vol, 0.1010 * k))
    b.ell((0, 1.690, -0.046), (0.0770 * k, 0.0820, 0.0760 * k))


def hairline(x, y, z, front=1.742, side=1.672, rear=1.600):
    """Haaransatz: vorn hoch, vor dem Ohr Koteletten, hinten tief."""
    if z > 0.030:
        lim = front - 0.010 * (abs(x) / 0.06) ** 2
    elif z > -0.004:
        t = (0.030 - z) / 0.034
        lim = front + (side - front) * t
    else:
        t = min(1.0, (-0.004 - z) / 0.060)
        lim = side + (rear - side) * t
        if abs(x) > 0.072 and z > -0.034:
            lim = max(lim, 1.700)
    return y > lim


def strands(ob, freq, amp, dirn=(0, 0, 1)):
    def fn(x, y, z, n):
        p = V((x, y, z))
        ang = math.atan2(x, 0.12 + abs(z) * 0.2)
        t = math.sin(ang * freq + noise.noise(p * 9.0) * 2.2) * 0.6 + noise.noise(V((x * 60, y * 14, z * 14))) * 0.6
        return x + n[0] * t * amp, y + n[1] * t * amp, z + n[2] * t * amp
    return move(ob, fn)


def hairs():
    out = []

    def done(name, ob, faces=None):
        ob.name = name
        ob.data.name = name
        set_mats(ob, ["Hair"])
        vcol(ob, lambda x, y, z: tuple([0.72 + 0.28 * smoothstep(1.62, 1.80, y) + 0.06 * noise.noise(V((x * 70, y * 20, z * 20)))] * 3))
        out.append(ob)

    # Kurz
    b = Blob(); hair_cap(b)
    for i in range(16):
        a = i / 15.0 * math.pi
        b.ell((0.058 * math.cos(a), 1.770 + 0.012 * math.sin(a * 3), 0.062 - 0.008 * abs(math.cos(a))), (0.018, 0.014, 0.022), (-30, 20 * math.cos(a), 0))
    ob = cut(b.mesh("h", 0.0046, 2, 0.4, 3200), lambda x, y, z: hairline(x, y, z))
    done("Hair_Short", solidify(strands(ob, 26, 0.0022), 0.004))
    # Raspel
    b = Blob(); b.ell((0, 1.718, -0.015), (0.0795, 0.0975, 0.0980)); b.ell((0, 1.690, -0.046), (0.0735, 0.080, 0.071))
    done("Hair_Buzz", solidify(cut(b.mesh("h", 0.005, 3, 0.5, 2200), lambda x, y, z: hairline(x, y, z, 1.745)), 0.002))
    shape(out[-1], "Under_Hat", lambda x, y, z: (x * (1 - 0.06 * smoothstep(1.715, 1.75, y)), y - (y - 1.72) * 0.16 * smoothstep(1.715, 1.75, y), z * (1 - 0.06 * smoothstep(1.715, 1.75, y))))
    # Undercut: oben lang
    b = Blob(); b.ell((0, 1.755, 0.000), (0.064, 0.066, 0.092)); b.ell((0, 1.788, 0.040), (0.050, 0.034, 0.060), (-18, 0, 0)); b.ell((0.012, 1.800, 0.066), (0.042, 0.022, 0.034), (-30, 0, 10))
    top = cut(b.mesh("h", 0.0046, 3, 0.4, 2600), lambda x, y, z: y > 1.742 and (z < 0.066 or y > 1.760))
    b = Blob(); b.ell((0, 1.716, -0.015), (0.0790, 0.0965, 0.0975)); b.ell((0, 1.690, -0.046), (0.073, 0.079, 0.0705))
    side = cut(b.mesh("h", 0.006, 3, 0.5, 1400), lambda x, y, z: hairline(x, y, z, 1.745))
    done("Hair_Undercut", join("h", [solidify(strands(top, 30, 0.003), 0.004), solidify(side, 0.0018)]))
    # Seitenscheitel
    b = Blob(); hair_cap(b, 1.0)
    for i in range(12):
        t = i / 11.0
        b.ell((-0.052 + 0.100 * t, 1.786 - 0.020 * abs(t - 0.35), 0.056 + 0.012 * math.sin(t * 3)), (0.022, 0.018, 0.030), (-26, 34 * (t - 0.3), -24))
    ob = cut(b.mesh("h", 0.0046, 2, 0.4, 3200), lambda x, y, z: hairline(x, y, z, 1.738, 1.676))
    done("Hair_Side", solidify(strands(ob, 34, 0.0026), 0.004))
    # Locken
    b = Blob()
    random.seed(4)
    for i in range(150):
        a = random.uniform(0, 2 * math.pi)
        e = math.acos(random.uniform(-0.45, 1.0))
        x, y, z = 0.082 * math.sin(e) * math.cos(a), 1.722 + 0.100 * math.cos(e), -0.016 + 0.098 * math.sin(e) * math.sin(a)
        if hairline(x, y, z, 1.748, 1.676, 1.625):
            b.sph((x, y, z), random.uniform(0.013, 0.019))
    done("Hair_Curly", b.mesh("h", 0.0048, 2, 0.4, 5200))
    # Afro
    b = Blob()
    for i in range(230):
        a = random.uniform(0, 2 * math.pi)
        e = math.acos(random.uniform(-0.35, 1.0))
        x, y, z = 0.104 * math.sin(e) * math.cos(a), 1.742 + 0.112 * math.cos(e), -0.022 + 0.112 * math.sin(e) * math.sin(a)
        if hairline(x * 0.8, y - 0.012, z * 0.86, 1.752, 1.684, 1.640):
            b.sph((x, y, z), random.uniform(0.018, 0.026))
    done("Hair_Afro", b.mesh("h", 0.0065, 2, 0.4, 4800))
    # Mittellang
    b = Blob(); hair_cap(b, 1.02)
    for s in (-1, 1):
        for i in range(5):
            x = s * (0.076 + 0.006 * math.sin(i))
            z = 0.020 - 0.026 * i
            b.chain([((x * 0.96, 1.740, z), 0.020), ((x * 1.06, 1.670, z - 0.004), 0.019), ((x * 1.02, 1.590 + 0.006 * i, z - 0.004), 0.013)])
    for i in range(7):
        x = -0.060 + 0.020 * i
        b.chain([((x, 1.720, -0.092), 0.022), ((x * 1.1, 1.640, -0.102), 0.021), ((x * 1.08, 1.560, -0.092), 0.014)])
    ob = cut(b.mesh("h", 0.005, 2, 0.4, 4600), lambda x, y, z: (hairline(x, y, z, 1.742, 1.672, 1.50) if abs(x) < 0.066 or z > 0.02 and y > 1.70 else True) and not (z > 0.052 and y < 1.735))
    done("Hair_Bob", solidify(strands(ob, 40, 0.0026), 0.003))
    # Lang
    b = Blob(); hair_cap(b, 1.02)
    for s in (-1, 1):
        for i in range(5):
            x = s * (0.077 + 0.005 * math.sin(i * 1.3))
            z = 0.016 - 0.027 * i
            b.chain([((x * 0.96, 1.740, z), 0.020), ((x * 1.08, 1.650, z - 0.004), 0.020), ((x * 1.16, 1.540, z - 0.010), 0.020), ((x * 1.22, 1.430 + 0.01 * i, z * 0.6 - 0.024), 0.014), ((x * 1.2, 1.370 + 0.012 * i, z * 0.5 - 0.020), 0.007)])
    for i in range(8):
        x = -0.066 + 0.0188 * i
        b.chain([((x, 1.720, -0.092), 0.022), ((x * 1.12, 1.620, -0.108), 0.022), ((x * 1.22, 1.480, -0.122), 0.021), ((x * 1.20, 1.340, -0.128), 0.010)])
    ob = cut(b.mesh("h", 0.0055, 2, 0.4, 5600), lambda x, y, z: (hairline(x, y, z, 1.742, 1.672, 1.30) if abs(x) < 0.066 or z > 0.02 and y > 1.70 else True) and not (z > 0.052 and y < 1.735))
    done("Hair_Long", solidify(strands(ob, 44, 0.0028), 0.003))
    # Pferdeschwanz
    b = Blob(); b.ell((0, 1.720, -0.016), (0.0808, 0.0985, 0.0995)); b.ell((0, 1.690, -0.046), (0.0745, 0.081, 0.0735))
    cap = cut(b.mesh("h", 0.005, 2, 0.4, 2400), lambda x, y, z: hairline(x, y, z, 1.744, 1.678, 1.612))
    b = Blob(); b.chain([((0, 1.752, -0.104), 0.020), ((0, 1.752, -0.140), 0.026), ((0.004, 1.690, -0.168), 0.032), ((0.0, 1.600, -0.160), 0.028), ((-0.004, 1.520, -0.146), 0.012)])
    tail = b.mesh("h", 0.005, 2, 0.4, 1500)
    band = tube("h", [(0, 1.756, -0.112), (0, 1.754, -0.122)], 0.0235, "Acc_A", 18)
    ob = join("h", [solidify(strands(cap, 40, 0.0020), 0.003), strands(tail, 60, 0.0030)])
    done("Hair_Pony", ob)
    # Dutt
    b = Blob(); b.ell((0, 1.720, -0.016), (0.0808, 0.0985, 0.0995)); b.ell((0, 1.690, -0.046), (0.0745, 0.081, 0.0735))
    cap = cut(b.mesh("h", 0.005, 2, 0.4, 2400), lambda x, y, z: hairline(x, y, z, 1.744, 1.678, 1.612))
    b = Blob(); b.ell((0, 1.808, -0.066), (0.038, 0.030, 0.038)); b.ell((0, 1.800, -0.064), (0.030, 0.034, 0.030))
    done("Hair_Bun", join("h", [solidify(strands(cap, 40, 0.0020), 0.003), strands(b.mesh("h", 0.004, 2, 0.4, 900), 40, 0.0030)]))
    # Iro
    b = Blob()
    for i in range(12):
        t = i / 11.0
        a = math.radians(-18 + 150 * t)
        y, z = 1.716 + 0.104 * math.sin(a), -0.014 + 0.104 * math.cos(a)
        b.cap((0, y, z), 0.014, (0, y + 0.036 * math.sin(a), z + 0.036 * math.cos(a)), 0.006)
    b2 = Blob(); b2.ell((0, 1.716, -0.015), (0.0785, 0.0965, 0.0972)); b2.ell((0, 1.690, -0.046), (0.073, 0.079, 0.0702))
    s2 = cut(b2.mesh("h", 0.006, 3, 0.5, 1400), lambda x, y, z: hairline(x, y, z, 1.748))
    done("Hair_Mohawk", join("h", [cut(b.mesh("h", 0.0046, 2, 0.4, 2000), lambda x, y, z: y > 1.735 or z < -0.04), solidify(s2, 0.0016)]))
    return out


def beards():
    out = []

    def shell(name, grow, keep, faces=1500, st=0.0):
        b = Blob()
        b.ell((0, 1.662, 0.026), (0.0640 + grow * 0.4, 0.0860, 0.0620 + grow * 0.3))
        b.ell((0, 1.606, 0.030), (0.0490 + grow, 0.0380 + grow, 0.0520 + grow))
        b.ell((0, 1.586, 0.060), (0.0235 + grow, 0.0205 + grow, 0.0220 + grow))
        for s in (-1, 1):
            b.ell((s * 0.0520, 1.612, 0.008), (0.0150 + grow * 0.8, 0.0280 + grow * 0.5, 0.0280 + grow * 0.5))
            b.ell((s * 0.0400, 1.640, 0.050), (0.0260, 0.0250, 0.0230))
        if st > 0:
            b.ell((0, 1.556 - st * 0.4, 0.052), (0.036, 0.036 + st, 0.030))
        ob = cut(b.mesh("b", 0.0042, 4, 0.5, faces), keep)
        strands(ob, 30, 0.0014)
        ob = solidify(ob, 0.002)
        ob.name = name
        set_mats(ob, ["Hair"])
        shape(ob, "Mouth_Open", lambda x, y, z: (x, y - 0.020 * smoothstep(1.6065, 1.600, y), z - 0.006 * smoothstep(1.6065, 1.600, y)))
        out.append(ob)

    def mouth(x, y, z):
        return z > 0.062 and abs(x) < 0.027 and 1.5935 < y < 1.6165

    shell("Beard_Short", 0.0030, lambda x, y, z: y < 1.628 - 0.2 * max(0.0, z - 0.02) + 0.35 * max(0.0, abs(x) - 0.048) and z > -0.004 and y > 1.556 and not mouth(x, y, z) and not (z > 0.07 and abs(x) < 0.006 and y > 1.612 and y < 1.622))
    shell("Beard_Full", 0.0085, lambda x, y, z: y < 1.632 - 0.2 * max(0.0, z - 0.02) + 0.4 * max(0.0, abs(x) - 0.046) and z > -0.006 and y > 1.500 and not mouth(x, y, z), 2000, 0.020)
    shell("Beard_Goatee", 0.0050, lambda x, y, z: abs(x) < 0.028 and z > 0.045 and y < 1.624 and y > 1.556 and not mouth(x, y, z), 900)
    b = Blob()
    for s in (-1, 1):
        b.chain([((s * 0.003, 1.6205, 0.0905), 0.0046), ((s * 0.016, 1.6190, 0.0870), 0.0050), ((s * 0.029, 1.6120, 0.0790), 0.0024)])
    ob = b.mesh("Beard_Mustache", 0.0018, 2, 0.4, 700)
    set_mats(ob, ["Hair"])
    out.append(ob)
    return out


# ---------------------------------------------------------------- Koerper (Haut)

def mirror_pts(pts, s):
    return [((p[0] * s, p[1], p[2]), r) for p, r in pts]


def lerp3(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def arm_chain(grow=0.0, upto=1.0):
    """Arm von der Schulter zum Handgelenk: Muskelform."""
    pts = [(SH, 0.0500), (lerp3(SH, EL, 0.28), 0.0490), (lerp3(SH, EL, 0.62), 0.0455), (EL, 0.0390),
           (lerp3(EL, WR, 0.22), 0.0405), (lerp3(EL, WR, 0.60), 0.0335), (lerp3(EL, WR, 1.0), 0.0265)]
    out = [(p, r + grow) for p, r in pts]
    return out[: max(2, int(round(len(out) * upto)))]


def arms_skin():
    obs = []
    for s in (-1, 1):
        b = Blob()
        b.chain(mirror_pts(arm_chain(), s))
        b.cap((WR[0] * s, WR[1], WR[2]), 0.0262, ((WR[0] + 0.02) * s, WR[1] - 0.02, WR[2]), 0.0260)
        obs.append(b.mesh("a", 0.0075, 4, 0.5, 1500))
    ob = join("Arms", obs)
    set_mats(ob, ["Skin"])
    vcol(ob, lambda x, y, z: (1, 0.985, 0.98))
    return ob


def hand(s):
    b = Blob()
    d = V((math.cos(A), -math.sin(A), 0.0))        # laengs
    up = V((math.sin(A), math.cos(A), 0.0))        # Handruecken (nach oben aussen)
    f = V((0, 0, 1))                                # Daumenseite vorn
    w = V(WR)

    def pt(l, side, h):
        p = w + d * l + f * side + up * h
        return (p.x * s, p.y, p.z)
    b.cap(pt(-0.012, 0.0, 0.0), 0.0262, pt(0.012, 0.002, 0.0), 0.0250)
    for i, (sd, l0) in enumerate(((0.030, 0.088), (0.011, 0.092), (-0.009, 0.088), (-0.027, 0.079))):
        b.cap(pt(0.020, sd * 0.62, 0.001), 0.0165, pt(l0, sd, 0.002), 0.0112)
        ln = (0.036, 0.041, 0.038, 0.030)[i]
        r = (0.0094, 0.0096, 0.0092, 0.0082)[i]
        b.cap(pt(l0, sd, 0.002), r * 1.10, pt(l0 + ln, sd * 1.06, -0.004), r * 0.96)
        b.cap(pt(l0 + ln, sd * 1.06, -0.004), r * 0.96, pt(l0 + ln * 1.95, sd * 1.10, -0.016), r * 0.80)
    b.cap(pt(0.022, 0.020, -0.006), 0.0185, pt(0.046, 0.040, -0.012), 0.0135)
    b.cap(pt(0.046, 0.040, -0.012), 0.0128, pt(0.074, 0.052, -0.016), 0.0105)
    b.cap(pt(0.074, 0.052, -0.016), 0.0103, pt(0.098, 0.057, -0.020), 0.0085)
    b.ell(pt(0.050, -0.004, -0.008), (0.030, 0.030, 0.028))
    return b.mesh("h", 0.0032, 3, 0.45, 2000)


def hands():
    ob = join("Hands", [hand(1), hand(-1)])
    set_mats(ob, ["Skin"])
    vcol(ob, lambda x, y, z: (1, 0.96, 0.945))
    return ob


LEG = [((0.092, 0.920, -0.004), 0.0900), ((0.097, 0.760, 0.004), 0.0820), ((0.100, 0.600, 0.008), 0.0640), ((0.100, 0.500, 0.010), 0.0560),
       ((0.101, 0.400, -0.010), 0.0570), ((0.102, 0.260, -0.016), 0.0460), ((0.103, 0.120, -0.020), 0.0365), ((0.103, 0.080, -0.020), 0.0370)]


def legs_skin():
    obs = []
    for s in (-1, 1):
        b = Blob()
        b.chain(mirror_pts(LEG[2:], s))
        obs.append(b.mesh("l", 0.009, 4, 0.5, 1200))
    ob = join("Legs", obs)
    set_mats(ob, ["Skin"])
    vcol(ob, lambda x, y, z: (1, 0.985, 0.98))
    return ob


# ---------------------------------------------------------------- Kleidung oben

def torso(b, gr=0.0, hem=0.90, neck=True):
    b.ell((0, 1.360, -0.004), (0.143 + gr, 0.130, 0.098 + gr))
    b.ell((0, 1.300, 0.020), (0.132 + gr, 0.090, 0.092 + gr))
    b.ell((0, 1.200, 0.004), (0.130 + gr, 0.130, 0.090 + gr))
    b.ell((0, 1.080, 0.002), (0.134 + gr, 0.120, 0.094 + gr))
    b.ell((0, 0.980, -0.004), (0.146 + gr, 0.100, 0.104 + gr))
    for s in (-1, 1):
        b.cap((s * 0.060, 1.462, -0.016), 0.044 + gr * 0.6, (SH[0] * s, SH[1] - 0.004, SH[2]), 0.0500 + gr * 0.7)
        b.ell((s * 0.066, 1.352, 0.050), (0.066 + gr, 0.056, 0.046 + gr))
        b.ell((s * 0.090, 1.370, -0.050), (0.074 + gr, 0.090, 0.048 + gr))
    if neck:
        b.cap((0, 1.450, -0.022), 0.062 + gr * 0.5, (0, 1.505, -0.018), 0.058 + gr * 0.5)


def top_mesh(name, gr, sleeve, hem, faces=5200, wr=1.0, sleeve_gr=None, neck_y=1.492, voxel=0.0072, open_front=None, cuff=0.0, planes=()):
    """sleeve: 0 keine, 0.4 kurz, 1 lang. hem: untere Kante."""
    b = Blob()
    torso(b, gr)
    sg = gr if sleeve_gr is None else sleeve_gr
    for s in (-1, 1):
        ch = arm_chain(sg)
        if cuff:
            ch[-1] = (ch[-1][0], ch[-1][1] + cuff)
        b.chain(mirror_pts(ch, s))
    ob = deci(b.mesh(name, voxel, 5, 0.5, None), faces * 1.35 if faces else None)
    spots = []
    for s in (-1, 1):
        spots += [((EL[0] * s, EL[1], EL[2]), (s * 0.7, -0.7, 0), 0.085, 1.0), ((0.150 * s, 1.36, 0.0), (s * 0.8, 0.5, 0.2), 0.095, 0.8), ((0.11 * s, 1.07, 0.02), (0.2 * s, 1, 0), 0.10, 0.6)]
    wrinkle(ob, spots, 0.0040 * wr)
    al = arm_len()
    bis(ob, ypl(hem, neck_y) + (armpl(al * sleeve) if sleeve > 0.0 else xpl(0.168)) + list(planes))
    if open_front:
        bis(ob, xpl(*[open_front(y) for y in (1.46, 1.36, 1.25, 1.1, 0.95)]))

    def keep(x, y, z):
        if y < hem and abs(x) < 0.24:
            return False
        if y > neck_y and abs(x) < 0.085:
            return False
        p = V((abs(x), y, 0))
        a, e = V((SH[0], SH[1], 0)), V((WR[0], WR[1], 0))
        t = (p - a).dot(e - a) / (e - a).length_squared
        off = (p - a).dot(V((math.sin(A), math.cos(A), 0)))
        if t > sleeve and abs(x) > 0.2:
            return False
        if sleeve <= 0.0 and abs(x) > 0.168:
            return False
        if open_front and z > 0.0 and abs(x) < open_front(y):
            return False
        return True
    cut(ob, keep)
    return solidify(ob, 0.0045)


def collar_ring(y=1.494, r=0.066, h=0.026, flare=0.012, matname="Top_A", open_a=0.0, th=0.008):
    bm = bmesh.new()
    rows = []
    n = 36
    for i, (dy, dr) in enumerate(((0, 0), (h * 0.6, flare * 0.1), (h, flare * 0.5))):
        row = []
        for k in range(n + 1):
            an = math.radians(90 + open_a + (360 - 2 * open_a) * k / n)
            row.append(bm.verts.new(g(math.cos(an) * (r + dr), y + dy + 0.010 * -math.sin(an), math.sin(an) * (r + dr) * 0.98 - 0.020)))
        rows.append(row)
    for i in range(2):
        for k in range(n):
            bm.faces.new((rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k]))
    me = bpy.data.meshes.new("c")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("c", me)
    bpy.context.scene.collection.objects.link(ob)
    s = ob.modifiers.new("so", "SOLIDIFY")
    s.thickness = th
    s.offset = 0
    apply_mods(ob)
    set_mats(ob, [matname])
    return ob


def front_z(y):
    return 0.094 + 0.020 * gauss((y - 1.345) ** 2, 0.09) - 0.008 * gauss((y - 1.15) ** 2, 0.08)


def tops():
    out = []
    # T-Shirt
    ob = top_mesh("Top_Tee", 0.010, 0.40, 0.925)
    set_mats(ob, ["Top_A"])
    out.append((join("Top_Tee", [ob, collar_ring(1.486, 0.064, 0.010, 0.002, "Top_B", 0, 0.006)]), "top", True))
    # Polo
    ob = top_mesh("Top_Polo", 0.011, 0.42, 0.925, planes=armpl(0.185))
    set_mats(ob, ["Top_A", "Top_B"], lambda x, y, z: 1 if abs(x) > 0.255 and V((abs(x) - SH[0], y - SH[1], 0)).dot(V((math.cos(A), -math.sin(A), 0))) > 0.185 else 0)
    bt = box("b", [((0, 1.455, front_z(1.455) - 0.026), (0.020, 0.070, 0.006), (-14, 0, 0))], "Top_A", 0.002)
    kn = box("b", [((0, 1.470 - 0.024 * i, front_z(1.46) - 0.028 + 0.007 * i), (0.006, 0.006, 0.004)) for i in range(2)], "Top_B", 0.001)
    out.append((join("Top_Polo", [ob, bt, kn, collar_ring(1.488, 0.066, 0.030, 0.040, "Top_A", 16)]), "top", True))
    # Hemd
    ob = top_mesh("Top_Shirt", 0.011, 0.985, 0.915, cuff=0.004)
    set_mats(ob, ["Top_A"])
    bt = [((0.0, 1.440 - 0.062 * i, front_z(1.44 - 0.062 * i) + 0.016), (0.018, 0.064, 0.005)) for i in range(8)]
    kn = [((0.0, 1.430 - 0.062 * i, front_z(1.43 - 0.062 * i) + 0.0205), (0.007, 0.007, 0.004)) for i in range(8)]
    pk = [((0.072, 1.335, 0.108), (0.070, 0.074, 0.006), (4, 20, 0))]
    out.append((join("Top_Shirt", [ob, box("b", bt, "Top_A", 0.002), box("b", kn, "Top_B", 0.001), box("b", pk, "Top_A", 0.003), collar_ring(1.488, 0.066, 0.034, 0.046, "Top_A", 20)]), "top", True))
    # Hoodie
    ob = top_mesh("Top_Hoodie", 0.026, 0.985, 0.890, wr=1.5, sleeve_gr=0.020, neck_y=1.500, cuff=0.006, planes=ypl(0.925) + armpl(arm_len() - 0.056))
    set_mats(ob, ["Top_A", "Top_B"], lambda x, y, z: 1 if y < 0.925 and abs(x) < 0.22 or V((abs(x) - SH[0], y - SH[1], 0)).dot(V((math.cos(A), -math.sin(A), 0))) > arm_len() - 0.056 else 0)
    b = Blob()
    b.ell((0, 1.500, -0.086), (0.104, 0.080, 0.052), (24, 0, 0))
    for s in (-1, 1):
        b.chain([((s * 0.088, 1.500, -0.060), 0.030), ((s * 0.078, 1.505, 0.012), 0.024), ((s * 0.032, 1.470, 0.070), 0.015)])
    hood = b.mesh("h", 0.007, 4, 0.5, 1500)
    set_mats(hood, ["Top_A"])
    pk = box("p", [((0, 1.050, 0.126), (0.220, 0.110, 0.020), (-3, 0, 0))], "Top_A", 0.010)
    st = [tube("s", [(s * 0.030, 1.476, 0.088), (s * 0.033, 1.420, 0.120), (s * 0.034, 1.350, 0.132)], 0.0036, "Top_B", 8) for s in (-1, 1)]
    out.append((join("Top_Hoodie", [ob, hood, pk] + st), "top", True))
    # Pullover
    ob = top_mesh("Top_Sweater", 0.018, 0.985, 0.905, wr=1.2, cuff=0.004, planes=ypl(0.94, 1.262, 1.300))

    def stripes(x, y, z):
        if y < 0.94 and abs(x) < 0.22:
            return 1
        return 1 if 1.262 < y < 1.300 and abs(x) < 0.19 else 0
    set_mats(ob, ["Top_A", "Top_B"], stripes)
    out.append((join("Top_Sweater", [ob, collar_ring(1.486, 0.066, 0.018, 0.004, "Top_B", 0, 0.010)]), "top", True))
    # Jacke, offen ueber Shirt
    ob = top_mesh("Top_Jacket", 0.030, 0.985, 0.900, wr=1.3, sleeve_gr=0.020, neck_y=1.506, open_front=lambda y: 0.030 + 0.034 * smoothstep(1.25, 1.48, y), cuff=0.004, planes=ypl(0.930))
    set_mats(ob, ["Top_A", "Top_C"], lambda x, y, z: 1 if y < 0.930 and abs(x) < 0.22 else 0)
    inn = top_mesh("i", 0.010, 0.10, 0.930, 2600)
    set_mats(inn, ["Top_B"])
    zips = [tube("z", [(s * (0.031 + 0.034 * smoothstep(1.25, 1.48, y)), y, front_z(y) + 0.030) for y in (0.905, 1.0, 1.1, 1.2, 1.3, 1.4, 1.47)], 0.0040, "Metal", 8) for s in (-1, 1)]
    pk = box("p", [((s * 0.105, 1.040, 0.104), (0.066, 0.012, 0.012), (0, s * 30, s * 20)) for s in (-1, 1)], "Top_C", 0.003)
    out.append((join("Top_Jacket", [ob, inn, pk, collar_ring(1.490, 0.076, 0.036, 0.020, "Top_A", 26, 0.012)] + zips), "top", True))
    # Arbeitsjacke mit Reflexstreifen
    ob = top_mesh("Top_Work", 0.026, 0.985, 0.885, wr=1.4, sleeve_gr=0.020, neck_y=1.504, cuff=0.004, planes=ypl(1.085, 1.125, 1.36) + armpl(0.11, 0.325, 0.362))

    def refl(x, y, z):
        if 1.085 < y < 1.125 and abs(x) < 0.20:
            return 2
        p = V((abs(x) - SH[0], y - SH[1], 0))
        t = p.dot(V((math.cos(A), -math.sin(A), 0)))
        if abs(x) > 0.22 and 0.325 < t < 0.362:
            return 2
        if y > 1.36 and t < 0.11:
            return 1
        return 0
    set_mats(ob, ["Top_A", "Top_C", "Reflect"], refl)
    zp = tube("z", [(0, y, front_z(y) + 0.028) for y in (0.890, 1.0, 1.1, 1.2, 1.3, 1.4, 1.48)], 0.0048, "Metal", 8)
    pk = box("p", [((s * 0.080, 1.320, 0.128), (0.080, 0.086, 0.014), (4, s * 18, 0)) for s in (-1, 1)] + [((s * 0.092, 0.985, 0.112), (0.094, 0.090, 0.014), (-4, s * 16, 0)) for s in (-1, 1)], "Top_A", 0.004)
    fl = box("p", [((s * 0.080, 1.362, 0.134), (0.084, 0.022, 0.014), (4, s * 18, 0)) for s in (-1, 1)], "Top_C", 0.003)
    out.append((join("Top_Work", [ob, zp, pk, fl, collar_ring(1.490, 0.076, 0.040, 0.014, "Top_C", 12, 0.012)]), "top", True))
    # Warnweste ueber Langarm
    ob = top_mesh("Top_Vest", 0.028, 0.0, 0.900, 3600, wr=0.8, open_front=lambda y: 0.004, planes=ypl(1.075, 1.125, 1.195, 1.235) + xpl(0.078, 0.112))

    def vest(x, y, z):
        if 1.075 < y < 1.125 or 1.195 < y < 1.235:
            return 1
        return 1 if 0.078 < abs(x) < 0.112 and y > 1.235 else 0
    set_mats(ob, ["Acc_A", "Reflect"], vest)
    inn = top_mesh("i", 0.010, 0.985, 0.915, 4200)
    set_mats(inn, ["Top_A"])
    out.append((join("Top_Vest", [ob, inn, collar_ring(1.486, 0.064, 0.012, 0.002, "Top_A", 0, 0.008)]), "top", True))
    # Anzug
    ob = top_mesh("Top_Suit", 0.022, 0.975, 0.860, wr=0.7, sleeve_gr=0.013, neck_y=1.500, open_front=lambda y: 0.062 * smoothstep(1.16, 1.48, y) + 0.004)
    set_mats(ob, ["Top_A"])
    inn = top_mesh("i", 0.009, 1.0, 0.930, 3800)
    set_mats(inn, ["Top_B"])
    lap = box("l", [((s * 0.066, 1.385, 0.118), (0.034, 0.150, 0.010), (8, s * 26, s * 22)) for s in (-1, 1)], "Top_A", 0.003)
    tie = box("t", [((0, 1.462, 0.074), (0.030, 0.026, 0.018), (-20, 0, 0)), ((0, 1.370, 0.110), (0.036, 0.160, 0.008), (-9, 0, 0)), ((0, 1.235, 0.124), (0.046, 0.130, 0.008), (2, 0, 0))], "Top_C", 0.004)
    kn = box("k", [((0.012, 1.12 - 0.075 * i, 0.122), (0.012, 0.012, 0.008)) for i in range(2)], "Top_C", 0.002)
    out.append((join("Top_Suit", [ob, inn, lap, tie, kn, collar_ring(1.488, 0.063, 0.032, 0.030, "Top_B", 16)]), "top", True))
    # Laborkittel
    ob = top_mesh("Top_Coat", 0.026, 0.985, 0.60, 5600, wr=1.0, neck_y=1.502, open_front=lambda y: 0.010 + 0.052 * smoothstep(1.20, 1.48, y) + 0.030 * smoothstep(0.95, 0.60, y))
    set_mats(ob, ["Top_A"])
    b = Blob()
    b.chain([((0, 0.98, -0.004), 0.150), ((0, 0.80, -0.004), 0.158), ((0, 0.62, -0.004), 0.166)])
    sk = cut(b.mesh("k", 0.010, 3, 0.5, None), lambda x, y, z: 0.62 < y < 0.97 and not (z > 0.0 and abs(x) < 0.012 + 0.030 * smoothstep(0.95, 0.60, y)))
    wrinkle(sk, [((0.1 * s, 0.75, 0.0), (1, 0, 0), 0.2, 0.8) for s in (-1, 1)], 0.006)
    move(sk, lambda x, y, z, n: (x, y, z * 0.80))
    sk = solidify(sk, 0.005)
    set_mats(sk, ["Top_A"])
    inn = top_mesh("i", 0.010, 0.2, 0.930, 2600)
    set_mats(inn, ["Top_B"])
    pk = box("p", [((s * 0.094, 0.930, 0.126), (0.094, 0.110, 0.012), (0, s * 16, 0)) for s in (-1, 1)] + [((0.075, 1.330, 0.124), (0.074, 0.080, 0.010), (4, 18, 0))], "Top_A", 0.004)
    out.append((join("Top_Coat", [ob, sk, inn, pk, collar_ring(1.490, 0.074, 0.034, 0.040, "Top_A", 30, 0.010)]), "coat", True))
    return out


# ---------------------------------------------------------------- Kleidung unten

def bottom_mesh(name, gr, hem, flare=0.0, wr=1.0, faces=4200, planes=()):
    b = Blob()
    b.ell((0, 0.955, -0.006), (0.140 + gr * 0.8, 0.095, 0.100 + gr * 0.8))
    b.ell((0, 0.880, -0.008), (0.146 + gr, 0.090, 0.106 + gr))
    for s in (-1, 1):
        b.ell((s * 0.066, 0.890, -0.052), (0.070 + gr, 0.080, 0.062 + gr))
        ch = []
        for p, r in LEG:
            k = smoothstep(0.55, 0.06, p[1])
            ch.append((p, r + gr + flare * k))
        ch.append(((0.104, 0.030, -0.018), 0.040 + gr + flare))
        b.chain(mirror_pts(ch, s))
    ob = deci(b.mesh(name, 0.0080, 5, 0.5, None), faces * 1.3)
    spots = []
    for s in (-1, 1):
        spots += [((0.10 * s, 0.50, 0.01), (0, 1, 0), 0.11, 0.9), ((0.10 * s, 0.11, 0.0), (0, 1, 0), 0.13, 1.1), ((0.06 * s, 0.84, 0.06), (s, 0.6, 0), 0.12, 0.8)]
    wrinkle(ob, spots, 0.0046 * wr)
    bis(ob, ypl(hem, 1.002) + list(planes))
    cut(ob, lambda x, y, z: hem < y < 1.002)
    return solidify(ob, 0.0045)


def belt():
    bm = bmesh.new()
    n = 40
    rows = []
    for y in (0.966, 0.998):
        rows.append([bm.verts.new(g(math.cos(2 * math.pi * k / n) * 0.1560, y, math.sin(2 * math.pi * k / n) * 0.1170 - 0.006)) for k in range(n)])
    for k in range(n):
        bm.faces.new((rows[0][k], rows[0][(k + 1) % n], rows[1][(k + 1) % n], rows[1][k]))
    me = bpy.data.meshes.new("b")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("b", me)
    bpy.context.scene.collection.objects.link(ob)
    sd = ob.modifiers.new("so", "SOLIDIFY")
    sd.thickness = 0.006
    sd.offset = 0
    apply_mods(ob)
    set_mats(ob, ["Bottom_B"])
    return join("b", [ob, box("k", [((0, 0.982, 0.1125), (0.040, 0.034, 0.010))], "Metal", 0.004)])


def bottoms():
    out = []
    ob = bottom_mesh("Bottom_Jeans", 0.010, 0.050, 0.010)
    set_mats(ob, ["Bottom_A", "Bottom_B"], lambda x, y, z: 0)
    pk = box("p", [((s * 0.070, 0.880, -0.112), (0.072, 0.080, 0.008), (8, 0, 0)) for s in (-1, 1)], "Bottom_A", 0.003)
    out.append(join("Bottom_Jeans", [ob, pk, belt()]))
    ob = bottom_mesh("Bottom_Chino", 0.011, 0.060, 0.006, 0.8)
    set_mats(ob, ["Bottom_A"])
    out.append(join("Bottom_Chino", [ob, belt()]))
    ob = bottom_mesh("Bottom_Cargo", 0.020, 0.045, 0.010, 1.4)
    set_mats(ob, ["Bottom_A"])
    pk = box("p", [((s * 0.190, 0.640, 0.004), (0.030, 0.150, 0.110), (0, 0, s * 2)) for s in (-1, 1)], "Bottom_A", 0.010)
    fl = box("p", [((s * 0.196, 0.705, 0.004), (0.026, 0.036, 0.116), (0, 0, s * 2)) for s in (-1, 1)], "Bottom_B", 0.006)
    out.append(join("Bottom_Cargo", [ob, pk, fl, belt()]))
    ob = bottom_mesh("Bottom_Work", 0.020, 0.045, 0.010, 1.2, planes=ypl(0.235, 0.275, 0.42, 0.60))

    def wk(x, y, z):
        if 0.235 < y < 0.275:
            return 2
        return 1 if 0.42 < y < 0.60 and z > 0.02 else 0
    set_mats(ob, ["Bottom_A", "Bottom_B", "Reflect"], wk)
    pd = box("p", [((s * 0.102, 0.505, 0.088), (0.092, 0.150, 0.020), (-4, 0, 0)) for s in (-1, 1)], "Bottom_B", 0.008)
    pk = box("p", [((s * 0.188, 0.660, 0.004), (0.028, 0.140, 0.100)) for s in (-1, 1)], "Bottom_A", 0.008)
    out.append(join("Bottom_Work", [ob, pd, pk, belt()]))
    ob = bottom_mesh("Bottom_Suit", 0.008, 0.055, 0.004, 0.5)
    set_mats(ob, ["Bottom_A"])
    cr = [tube("c", [(s * 0.100, 0.82, 0.092), (s * 0.101, 0.52, 0.078), (s * 0.103, 0.12, 0.036)], 0.0022, "Bottom_A", 6) for s in (-1, 1)]
    out.append(join("Bottom_Suit", [ob, belt()] + cr))
    ob = bottom_mesh("Bottom_Shorts", 0.018, 0.520, 0.012, 1.0, 3000)
    set_mats(ob, ["Bottom_A"])
    out.append(join("Bottom_Shorts", [ob, belt()]))
    return out


# ---------------------------------------------------------------- Schuhe

def shoe(kind, s):
    obs = []
    b = Blob()
    x = 0.105 * s
    b.chain([((x, 0.058, -0.052), 0.040), ((x, 0.056, 0.030), 0.041), ((x * 1.01, 0.046, 0.110), 0.039), ((x * 1.015, 0.040, 0.152), 0.032)])
    b.ell((x, 0.040, 0.040), (0.046, 0.034, 0.130))
    hi = {"sneaker": 0.105, "boot": 0.200, "loafer": 0.075, "safety": 0.160}[kind]
    if hi > 0.08:
        b.chain([((x, 0.070, -0.026), 0.046), ((0.103 * s, hi, -0.022), 0.045)])
    up = b.mesh("s", 0.0062, 4, 0.5, None)
    bis(up, ypl(hi - 0.004))
    cut(up, lambda px, py, pz: py < hi - 0.004 and not (kind == "loafer" and py > 0.066 and -0.04 < pz < 0.040))
    move(up, lambda px, py, pz, n: (px, max(0.020, py), pz))
    d = up.modifiers.new("d", "DECIMATE")
    d.ratio = min(1.0, 1500.0 / (len(up.data.polygons) * 2.0))
    apply_mods(up)
    up = solidify(up, 0.004)
    set_mats(up, ["Shoe_A", "Shoe_B"], lambda px, py, pz: 1 if (kind == "safety" and pz > 0.105) or (kind == "sneaker" and (pz > 0.122 or (0.0 < pz < 0.03 and py > 0.05 and abs(abs(px) - 0.105) > 0.03))) else 0)
    obs.append(up)
    sb = Blob()
    sb.chain([((x, 0.018, -0.060), 0.034), ((x, 0.018, 0.020), 0.036), ((x * 1.01, 0.018, 0.105), 0.041), ((x * 1.015, 0.018, 0.150), 0.034)])
    so = sb.mesh("s", 0.007, 3, 0.5, 700)
    th = 0.020 if kind in ("loafer",) else 0.028
    move(so, lambda px, py, pz, n: (px, min(th, max(0.0, py)), pz))
    set_mats(so, ["Shoe_B" if kind == "sneaker" else "Dark"])
    obs.append(so)
    if kind != "loafer":
        n = 4 if kind == "sneaker" else 6
        for i in range(n):
            t = i / (n - 1.0)
            y = 0.094 + (0.0 if kind == "sneaker" else max(0.0, t - 0.4) * 0.14)
            z = 0.078 - 0.060 * t
            obs.append(tube("l", [(x - 0.020, y, z), (x, y + 0.006, z + 0.003), (x + 0.020, y, z)], 0.0030, "Shoe_B" if kind != "boot" else "Dark", 6))
    return obs


def shoes():
    out = []
    for name, kind in (("Shoes_Sneaker", "sneaker"), ("Shoes_Boot", "boot"), ("Shoes_Loafer", "loafer"), ("Shoes_Safety", "safety")):
        out.append(join(name, shoe(kind, 1) + shoe(kind, -1)))
    return out


# ---------------------------------------------------------------- Kopfbedeckung, Brillen, Zubehoer

def lathe(name, prof, kx, kz, zc, seg=40):
    bm = bmesh.new()
    rows = []
    for r, y in prof:
        if r < 1e-5:
            rows.append([bm.verts.new(g(0, y, zc))])
        else:
            rows.append([bm.verts.new(g(math.cos(2 * math.pi * k / seg) * r * kx, y, math.sin(2 * math.pi * k / seg) * r * kz + zc)) for k in range(seg)])
    for a, b in zip(rows, rows[1:]):
        for k in range(seg):
            if len(a) == 1:
                bm.faces.new((a[0], b[k], b[(k + 1) % seg]))
            else:
                bm.faces.new((a[k], b[k], b[(k + 1) % seg], a[(k + 1) % seg]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    return ob


def hats():
    out = []
    b = Blob(); b.ell((0, 1.728, -0.012), (0.0880, 0.0930, 0.1060))
    c = cut(bis(b.mesh("h", 0.006, 3, 0.5, 1600), ypl(1.728)), lambda x, y, z: y > 1.728)
    set_mats(c, ["Acc_A"])
    b = Blob(); b.ell((0, 1.732, 0.122), (0.070, 0.010, 0.066), (12, 0, 0))
    p = b.mesh("p", 0.005, 2, 0.4, 600)
    set_mats(p, ["Acc_B"])
    out.append(join("Hat_Cap", [c, p, box("k", [((0, 1.822, -0.012), (0.014, 0.008, 0.014))], "Acc_B", 0.003)]))
    b = Blob(); b.ell((0, 1.742, -0.016), (0.0900, 0.1000, 0.1080)); b.ell((0, 1.830, -0.028), (0.034, 0.028, 0.036))
    c = cut(bis(b.mesh("h", 0.0055, 2, 0.5, 2800), [((0, 1.712, 0), (0, 1, 0.16)), ((0, 1.746, 0), (0, 1, 0.16))]), lambda x, y, z: y + 0.16 * z > 1.712)

    def knit(x, y, z, n):
        a = math.atan2(x, z)
        t = math.sin(a * 46) * 0.0012 + (0.004 if y + 0.16 * z < 1.7465 else 0)
        return x + n[0] * t, y + n[1] * t, z + n[2] * t
    move(c, knit)
    set_mats(c, ["Acc_A", "Acc_B"], lambda x, y, z: 1 if y + 0.16 * z < 1.7465 else 0)
    out.append(join("Hat_Beanie", [c]))
    b = Blob(); b.ell((0, 1.742, -0.012), (0.1060, 0.1040, 0.1260)); b.ell((0, 1.752, 0.10), (0.084, 0.012, 0.050), (14, 0, 0)); b.ell((0, 1.742, -0.012), (0.122, 0.012, 0.142))
    for x in (-0.028, 0, 0.028):
        b.chain([((x, 1.800, 0.092), 0.008), ((x, 1.845, 0.030), 0.009), ((x, 1.848, -0.040), 0.009), ((x, 1.800, -0.112), 0.008)])
    b.vs, b.fs = [], []
    c = lathe("h", [(0.000, 1.854), (0.040, 1.850), (0.072, 1.834), (0.092, 1.806), (0.101, 1.772), (0.103, 1.748), (0.104, 1.742), (0.124, 1.736), (0.126, 1.732), (0.122, 1.730), (0.100, 1.734)], 1.0, 1.18, -0.012, 48)
    move(c, lambda x, y, z, n: (x, y - 0.006 * smoothstep(0.09, 0.14, z), z + 0.030 * smoothstep(1.745, 1.735, y) * smoothstep(0.06, 0.13, z)))
    set_mats(c, ["Acc_A"])
    rb = [tube("r", [(x, 1.838 - 0.6 * abs(x), 0.076), (x, 1.858 - 0.3 * abs(x), 0.030), (x, 1.860 - 0.3 * abs(x), -0.040), (x, 1.836 - 0.6 * abs(x), -0.098)], 0.0072, "Acc_A", 8) for x in (-0.030, 0.0, 0.030)]
    c = join("h", [c] + rb)
    st = [tube("s", [(s * 0.094, 1.740, 0.010), (s * 0.078, 1.640, 0.016), (s * 0.046, 1.575, 0.028), (0, 1.558, 0.036)], 0.0032, "Dark", 8) for s in (-1, 1)]
    out.append(join("Hat_Helmet", [c] + st))
    parts = [tube("s", [(s0 * 0.0, 1.0, 0) for s0 in ()] or [(-0.096, 1.690, -0.006), (-0.088, 1.770, -0.010), (-0.050, 1.822, -0.012), (0, 1.838, -0.012), (0.050, 1.822, -0.012), (0.088, 1.770, -0.010), (0.096, 1.690, -0.006)], 0.0062, "Acc_B", 10)]
    for s in (-1, 1):
        b = Blob(); b.ell((s * 0.098, 1.668, -0.008), (0.016, 0.036, 0.030))
        e = b.mesh("e", 0.005, 2, 0.4, 500)
        set_mats(e, ["Acc_B"])
        parts.append(e)
        parts.append(box("k", [((s * 0.113, 1.668, -0.008), (0.006, 0.040, 0.032))], "Acc_A", 0.003))
    parts.append(tube("m", [(0.104, 1.650, 0.010), (0.092, 1.612, 0.060), (0.050, 1.598, 0.096)], 0.0030, "Acc_B", 8))
    b = Blob(); b.ell((0.044, 1.597, 0.099), (0.011, 0.008, 0.008)); mi = b.mesh("m", 0.003, 1, 0.3, 200); set_mats(mi, ["Dark"]); parts.append(mi)
    out.append(join("Hat_Headset", parts))
    return out


def glasses():
    out = []
    for name, w, h, rr, th, lens in (("Glasses_Round", 0.026, 0.024, 1.0, 0.0022, "Glass"), ("Glasses_Square", 0.030, 0.020, 0.35, 0.0030, "Glass"), ("Glasses_Safety", 0.040, 0.026, 0.6, 0.0026, "Glass")):
        parts = []
        for s in (-1, 1):
            cx = s * (0.0325 if name != "Glasses_Safety" else 0.034)
            pts = []
            n = 28
            for k in range(n + 1):
                a = 2 * math.pi * k / n
                e = 2.0 / (2.0 + (1 - rr) * 6)
                x = math.copysign(abs(math.cos(a)) ** e, math.cos(a)) * w
                y = math.copysign(abs(math.sin(a)) ** e, math.sin(a)) * h
                pts.append((cx + x, 1.6715 + y, 0.1005 - 5.2 * (abs(cx + x) - 0.02) ** 2))
            parts.append(tube("f", pts, th, "Acc_B" if name != "Glasses_Safety" else "Acc_A", 8))
            bm = bmesh.new()
            vs = [bm.verts.new(g(p[0], p[1], p[2] - 0.0006)) for p in pts[:-1]]
            bm.faces.new(vs)
            me = bpy.data.meshes.new("l")
            bm.to_mesh(me)
            bm.free()
            lo = bpy.data.objects.new("l", me)
            bpy.context.scene.collection.objects.link(lo)
            set_mats(lo, [lens])
            parts.append(lo)
            parts.append(tube("b", [(s * (abs(cx) + w), 1.676, 0.0865 if name != "Glasses_Safety" else 0.080), (s * 0.078, 1.678, 0.040), (s * 0.084, 1.676, -0.010), (s * 0.084, 1.662, -0.030)], th * 0.9, "Acc_B", 8))
        parts.append(tube("n", [(-0.0075, 1.675, 0.1020), (0, 1.679, 0.1055), (0.0075, 1.675, 0.1020)], th, "Acc_B", 8))
        out.append(join(name, parts))
    return out


def accessories():
    out = []
    # Umhaengeband mit Ausweis
    parts = []
    for s in (-1, 1):
        parts.append(tube("l", [(s * 0.070, 1.500, -0.040), (s * 0.078, 1.480, 0.030), (s * 0.052, 1.400, 0.118), (s * 0.010, 1.265, 0.140)], 0.0044, "Acc_A", 8))
    parts.append(box("k", [((0, 1.215, 0.1430), (0.058, 0.086, 0.005))], "Top_B", 0.002))
    parts.append(box("k", [((0, 1.236, 0.1462), (0.052, 0.016, 0.002)), ((-0.014, 1.206, 0.1462), (0.020, 0.026, 0.002))], "Acc_A", 0.0))
    out.append((join("Acc_Badge", parts), "Spine2"))
    # Werkzeugguertel
    parts = [box("k", [((s * 0.168, 0.930, 0.020), (0.050, 0.110, 0.100), (0, 0, 0)) for s in (-1, 1)] + [((0.10 * s, 0.940, 0.108), (0.070, 0.070, 0.040)) for s in (-1, 1)], "Acc_B", 0.008)]
    parts.append(tube("h", [(0.186, 0.99, 0.02), (0.192, 0.84, 0.03)], 0.010, "Metal", 10))
    parts.append(tube("h", [(-0.186, 0.99, 0.00), (-0.188, 0.93, 0.0)], 0.013, "Acc_A", 10))
    b2 = belt()
    move(b2, lambda x, y, z, n: (x * 1.07, y, z * 1.10))
    set_mats(b2, ["Acc_B"])
    parts.append(b2)
    out.append((join("Acc_Belt", parts), "Hips"))
    # Rucksack
    b = Blob(); b.ell((0, 1.280, -0.180), (0.130, 0.190, 0.072)); b.ell((0, 1.190, -0.220), (0.100, 0.095, 0.052))
    bp = b.mesh("r", 0.009, 3, 0.5, 1600)
    set_mats(bp, ["Acc_A", "Acc_B"], lambda x, y, z: 1 if y < 1.20 or z < -0.225 else 0)
    st = [tube("s", [(s * 0.085, 1.440, -0.130), (s * 0.098, 1.500, -0.030), (s * 0.104, 1.420, 0.096), (s * 0.118, 1.280, 0.108), (s * 0.140, 1.160, 0.020), (s * 0.110, 1.140, -0.120)], 0.0120, "Acc_B", 10) for s in (-1, 1)]
    out.append((join("Acc_Backpack", [bp] + st), "Spine2"))
    # Uhr
    parts = []
    for s in (1,):
        d = V((math.cos(A), -math.sin(A), 0))
        c = V(WR) - d * 0.030
        n = 24
        u = V((math.sin(A), math.cos(A), 0))
        pts = []
        for k in range(n + 1):
            an = 2 * math.pi * k / n
            o = c + u * math.cos(an) * 0.0325 + V((0, 0, 1)) * math.sin(an) * 0.0325
            pts.append(tuple(o))
        parts.append(tube("w", pts, 0.0060, "Acc_B", 8))
        o = c + u * 0.035
        parts.append(box("w", [((o.x, o.y, o.z), (0.030, 0.012, 0.032), (0, 0, 45))], "Dark", 0.003))
    out.append((join("Acc_Watch", parts), "LeftForeArm"))
    return out


def gloves():
    obs = []
    for s in (1, -1):
        o = hand(s)
        move(o, lambda x, y, z, n: (x + n[0] * 0.0030, y + n[1] * 0.0030, z + n[2] * 0.0030))
        obs.append(o)
    ob = join("Acc_Gloves", obs)
    set_mats(ob, ["Acc_A", "Acc_B"], lambda x, y, z: 1 if V((abs(x) - WR[0], y - WR[1], 0)).length < 0.055 else 0)
    return ob


# ---------------------------------------------------------------- Ablauf

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    all_mats()
    rig = build_armature()
    n = 0

    def reg(ob, grp, shapes=True, rigid=None):
        nonlocal n
        if grp == "head":
            lower(ob)
        if shapes:
            add_shapes(ob)
        weights(ob, rig, GROUPS.get(grp, []), rigid)
        n += len(ob.data.polygons)
        print("FIGUR %s %d Flaechen" % (ob.name, len(ob.data.polygons)))

    hd = head_base()
    face_keys(hd)
    lower(hd)
    for v in ():
        pass
    weights(hd, rig, GROUPS["head"], lambda x, y, z: "Head" if y > 1.575 else ("Neck" if y > 1.50 else "Spine2"))
    # Hals weich mischen
    hd.vertex_groups.clear()
    hd.modifiers.clear()
    for vv in hd.data.vertices:
        x, y, z = back(vv.co)
        wh = smoothstep(1.522, 1.578, y) if z < 0.03 else smoothstep(1.528, 1.553, y)
        wn = (1 - wh) * smoothstep(1.445, 1.500, y)
        ws = max(0.0, 1 - wh - wn)
        for nme, w in (("Head", wh), ("Neck", wn), ("Spine2", ws)):
            if w > 0.01:
                vg = hd.vertex_groups.get(nme) or hd.vertex_groups.new(name=nme)
                vg.add([vv.index], w, "REPLACE")
    hd.parent = rig
    md = hd.modifiers.new("Armature", "ARMATURE")
    md.object = rig
    print("FIGUR Head %d" % len(hd.data.polygons))
    e = eyes()
    reg(e, "head", False, "Head")
    reg(lids(), "head", False, "Head")
    for o in mouth():
        reg(o, "head", False, "Head")
    for o in brows() + hairs() + beards() + hats() + glasses():
        reg(o, "head", False, (lambda x, y, z: "Head" if y > 1.52 else ("Neck" if y > 1.46 else "Spine2")) if o.name in ("Hair_Long",) else "Head")
    reg(arms_skin(), "arms")
    reg(hands(), "hands", False)
    reg(gloves(), "hands", False)
    reg(legs_skin(), "bottom")
    for ob, grp, _s in tops():
        reg(ob, "top" if grp == "top" else "coat")
    for ob in bottoms():
        reg(ob, "bottom")
    for ob in shoes():
        reg(ob, "shoes", False)
    for ob, bone in accessories():
        reg(ob, "", False, bone)
    GROUPS["coat"] = GROUPS["top"]
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_apply=False, export_skins=True, export_morph=True,
                              export_morph_normal=False, export_animations=False, export_vertex_color="ACTIVE", export_all_vertex_colors=True, export_rest_position_armature=True)
    print("FIGUR FERTIG %d Flaechen, %.1f MB" % (n, os.path.getsize(OUT) / 1048576.0))


GROUPS["coat"] = GROUPS["top"] + ["LeftUpLeg", "RightUpLeg"]

if __name__ == "__main__":
    main()
