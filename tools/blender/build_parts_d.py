"""Blender 5.2: eigenes 3D-Modell fuer jedes Bauteil des Katalogs (Paket D, Roadmap 1).

  hw_<id>.glb   Produkt, so wie man es kauft und in der Hand haelt (Ursprung Mitte der Grundflaeche)
  hwm_<id>.glb  Einbauvariante im Server, zerlegt wie asm_*.glb (gleiche Knotennamen, Lage wie part_*.glb)

Die Dateien enthalten keine Texturen. PBR_*-Materialien kommen zur Laufzeit aus part_*.glb,
HW_*-Materialien (Farbe, Metall, Rauheit) stecken fertig in der Datei, HWL_* leuchten.
Knoten: Rotor_X_* / Rotor_Y_* / Rotor_Z_* drehen sich, Label_* sind Flaechen fuer Aufschriften
(Ausrichtung des Knotens: +Z zeigt nach aussen, Skalierung.x/.y = Breite/Hoehe), Flow_* fuehrt Wasser.

Aufruf: blender --background --factory-startup --python tools/blender/build_parts_d.py -- <catalog.json> [id ...]
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_hardware_parts as H
import build_assembly_parts as A

OUT = A.OUT_DIR
T, Rx, Ry, Rz = H.T, H.Rx, H.Ry, H.Rz
V = Vector


# ---------------------------------------------------------------- Materialien

def hw(hexcol, metal=0.3, rough=0.42, emit=0.0):
    rgb = tuple(int(hexcol[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    name = "%s_%s_%d_%d%s" % ("HWL" if emit > 0 else "HW", hexcol, round(metal * 100), round(rough * 100), "_%d" % round(emit * 10) if emit > 0 else "")
    H.SOLID_MATS[name] = (rgb, metal, rough, 0.0, emit)
    return name


BLACK = hw("0c0d0f", 0.1, 0.5)
WHITE = hw("e8eaec", 0.05, 0.45)
PAPER = hw("f2f1ec", 0.0, 0.8)
GLASS = hw("20242a", 0.2, 0.08)
TIN = hw("b9bdc2", 0.95, 0.28)
NICKEL = hw("c9ccd1", 0.95, 0.22)
TUBE = {"blue": hw("2f8de0", 0.0, 0.2), "red": hw("e0503a", 0.0, 0.2), "clear": hw("9fd4ff", 0.0, 0.1), "black": hw("15171a", 0.0, 0.6), "green": hw("35c98a", 0.0, 0.2)}
BADGE = {"basis": hw("b8bcc4", 0.2, 0.5), "bronze": hw("b06a35", 0.8, 0.35), "silber": hw("c4c9d0", 0.9, 0.28), "gold": hw("d9ab3c", 0.9, 0.28), "platin": hw("d8dee6", 0.95, 0.18), "titan": hw("5d6672", 0.9, 0.25), "standard": hw("8a8f98", 0.2, 0.6)}
PCB = {"green": H.M_PCB_SUB_G, "black": H.M_PCB_SUB_B, "blue": hw("123a7a", 0.06, 0.36), "red": hw("7a1418", 0.06, 0.36), "white": hw("dfe3e8", 0.06, 0.4)}


class P2(A.SplitPart):
    """Baukasten mit Materialtausch und Beschriftungsflaechen."""

    def __init__(self):
        super().__init__()
        self.remap = {}
        self.labels = []
        self.split_screws = False

    def _add(self, t, M, mat, group):
        super()._add(t, M, self.remap.get(mat, mat), group)

    def label(self, name, pos, w, h, normal="z", M=None, up=None):
        """Merkt eine Beschriftungsflaeche. normal: Richtung, in die die Schrift zeigt."""
        rot = {"z": H.I4, "-z": Ry(180), "x": Ry(90), "-x": Ry(-90), "y": Rx(-90), "-y": Rx(90), "yz": Ry(90) @ Rx(0)}[normal]
        mm = (M if M is not None else H.I4) @ T(V(pos)) @ rot
        if up is not None:
            mm = mm @ Rz(up)
        self.labels.append((name, mm, w, h))

    def write(self, name):
        faces, names = self.export_prepare()
        for ln, mm, w, h in self.labels:
            e = bpy.data.objects.new("Label_" + ln, None)
            e.matrix_world = H.C @ mm @ Matrix.Diagonal((w, h, 1.0, 1.0))
            # Blender->glTF dreht die Achsen: Beschriftung zeigt im Spiel nach lokal +Z.
            e.matrix_world = H.C @ mm @ H.C.inverted() @ Matrix.Diagonal((w, 1.0, h, 1.0))
            bpy.context.scene.collection.objects.link(e)
        path = os.path.join(OUT, name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True, export_normals=True,
                                  export_tangents=False, export_image_format="NONE")
        return faces, os.path.getsize(path)

    def export_prepare(self):
        faces = 0
        names = []
        for key in self.order:
            g = self.groups[key]
            bm = g["bm"]
            if len(bm.faces) == 0 or key in self.dropped:
                bm.free()
                continue
            faces += len(bm.faces)
            names.append(key)
            if g["origin"].length > 1e-9:
                origin = H.C @ g["origin"]
            elif key == "Body":
                origin = V((0, 0, 0))
            else:
                if key in self.pivots:
                    origin = H.C @ V(self.pivots[key])
                else:
                    xs = [v.co for v in bm.verts]
                    lo = V((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
                    hi = V((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
                    origin = V(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, lo.z))
                for v in bm.verts:
                    v.co -= origin
            ngons = [f for f in bm.faces if len(f.verts) > 4]
            if ngons:
                H.bmesh.ops.triangulate(bm, faces=ngons)
            me = bpy.data.meshes.new(key)
            bm.to_mesh(me)
            bm.free()
            for mname in g["mats"]:
                me.materials.append(solid_or_plain(mname))
            ob = bpy.data.objects.new(key, me)
            ob.location = origin
            bpy.context.scene.collection.objects.link(ob)
        return faces, names


def solid_or_plain(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    if name.startswith("HW"):
        rgb, metal, rough, _c, emit = H.SOLID_MATS[name]
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        b = mat.node_tree.nodes["Principled BSDF"]
        lin = tuple(H.srgb_to_linear(c) for c in rgb)
        b.inputs["Base Color"].default_value = (*lin, 1.0)
        b.inputs["Metallic"].default_value = metal
        b.inputs["Roughness"].default_value = rough
        if emit > 0:
            b.inputs["Emission Color"].default_value = (*lin, 1.0)
            b.inputs["Emission Strength"].default_value = emit
        return mat
    return A.plain_material(name)


def rnd(pid, lo, hi, salt=0):
    h = 2166136261
    for c in pid + str(salt):
        h = ((h ^ ord(c)) * 16777619) & 0xFFFFFFFF
    return lo + (hi - lo) * ((h >> 7) % 1000) / 999.0


def pickv(pid, opts, salt=0):
    return opts[int(rnd(pid, 0, len(opts) - 0.001, salt))]


# ---------------------------------------------------------------- CPU

def cpu_family(p):
    n = p["name"]
    for key in ("Rackline", "Werkstatt", "Tempo", "Start", "Server", "Studio", "Dichte", "Spitze", "Office", "Quad", "Basis"):
        if key in n:
            return key
    return "Basis"


CPU_LOOK = {
    # w, d, Substrat, IHS-Form, Akzent
    "Basis": (0.0375, 0.0375, "green", "notch", "3c74c8"), "Quad": (0.0375, 0.0375, "green", "round", "2c5a9c"),
    "Office": (0.0375, 0.045, "green", "wing", "2f6fd0"), "Server": (0.052, 0.045, "green", "step", "2454a8"),
    "Studio": (0.058, 0.0505, "black", "step", "7a3fc0"), "Dichte": (0.061, 0.0775, "green", "bar", "17909a"),
    "Spitze": (0.0655, 0.084, "black", "bar", "c08a1c"), "Start": (0.040, 0.040, "green", "round", "d06a2a"),
    "Tempo": (0.040, 0.040, "black", "octo", "d8552a"), "Werkstatt": (0.0585, 0.0755, "green", "plate", "c4372f"),
    "Rackline": (0.0585, 0.0755, "green", "plate", "e07b22"),
}


def cpu_chip(P, p, w, d, y0, scale=1.0, grp=None):
    """Prozessor: Substrat, Kondensatoren, Deckel je Familie. y0 = Unterkante Substrat."""
    fam = cpu_family(p)
    _w, _d, sub, shape, acc = CPU_LOOK[fam]
    pid = p["id"]
    kw = {} if grp is None else {"group": grp}
    th = 0.0014 * scale
    P.box((0, y0 + th / 2, 0), (w, th, d), PCB[sub], bevel=0.0003, **kw)
    P.box((0, y0 - 0.0001, 0), (w * 0.93, 0.0003, d * 0.93), H.M_GOLD, bevel=0.0, **kw)
    iw, idd = w * 0.80, d * 0.80
    top = y0 + th
    ih = 0.0026 * scale
    tier = int(p["vtier"])
    lid = NICKEL if rnd(pid, 0, 1) > 0.4 else H.M_ALU
    if shape == "notch":
        P.box((0, top + ih / 2, 0), (iw, ih, idd), lid, bevel=0.0010, **kw)
        P.box((0, top + ih * 0.25, 0), (iw + 0.0034, ih * 0.5, idd * 0.55), lid, bevel=0.0006, **kw)
    elif shape == "round":
        P.box((0, top + ih * 0.3, 0), (iw, ih * 0.6, idd), lid, bevel=0.0016, **kw)
        P.box((0, top + ih * 0.7, 0), (iw * 0.88, ih * 0.6, idd * 0.88), lid, bevel=0.0012, **kw)
    elif shape == "wing":
        P.box((0, top + ih * 0.30, 0), (iw, ih * 0.6, idd * 0.96), lid, bevel=0.0005, **kw)
        P.box((0, top + ih * 0.72, 0), (iw * 0.86, ih * 0.7, idd * 0.82), lid, bevel=0.0008, **kw)
        for s in (-1, 1):
            P.box((s * iw * 0.47, top + ih * 0.15, 0), (iw * 0.10, ih * 0.3, idd * 1.05), lid, bevel=0.0003, **kw)
    elif shape == "octo":
        for a in (0, 90):
            P.box((0, top + ih / 2, 0), (iw, ih, idd * 0.46), lid, rot=Ry(a), bevel=0.0006, **kw)
        P.box((0, top + ih / 2, 0), (iw * 0.78, ih, idd * 0.78), lid, bevel=0.0006, **kw)
    elif shape == "plate":
        P.box((0, top + ih * 0.4, 0), (iw * 1.06, ih * 0.8, idd * 1.04), lid, bevel=0.0008, **kw)
        P.box((0, top + ih * 0.86, 0), (iw * 0.94, ih * 0.5, idd * 0.92), NICKEL, bevel=0.0005, **kw)
        P.box((0, y0 + th / 2, 0), (w * 1.04, th * 0.7, d * 0.30), hw(acc, 0.2, 0.5), bevel=0.0004, **kw)
    elif shape == "bar":
        P.box((0, top + ih * 0.35, 0), (iw * 1.06, ih * 0.7, idd * 1.06), lid, bevel=0.0006, **kw)
        n = 4 if fam == "Dichte" else 3
        for i in range(n):
            z = (i - (n - 1) / 2) * idd * 0.98 / n
            P.box((0, top + ih * 0.8, z), (iw * 0.96, ih * 0.4, idd * 0.86 / n), NICKEL, bevel=0.0004, **kw)
    else:
        P.box((0, top + ih * 0.35, 0), (iw * 1.04, ih * 0.7, idd * 1.04), lid, bevel=0.0007, **kw)
        P.box((0, top + ih * 0.78, 0), (iw * 0.80, ih * 0.6, idd * 0.80), lid, bevel=0.0007, **kw)
    # Kondensatoren rund um den Deckel, Muster je Modell
    nx = 3 + tier + int(rnd(pid, 0, 3, 2))
    for s in (-1, 1):
        for i in range(nx):
            u = (i - (nx - 1) / 2) / nx
            if rnd(pid, 0, 1, 10 + i) > 0.2:
                P.box((u * w * 0.8, top + 0.0003 * scale, s * d * 0.455), (0.0011 * scale, 0.0007 * scale, 0.0018 * scale), H.M_IC if i % 2 else H.M_CAP_BLUE, bevel=0.0, **kw)
            if rnd(pid, 0, 1, 30 + i) > 0.35:
                P.box((s * w * 0.455, top + 0.0003 * scale, u * d * 0.8), (0.0018 * scale, 0.0007 * scale, 0.0011 * scale), TIN, bevel=0.0, **kw)
    # Ecke mit Dreieck und Modellpunkt
    P.cyl((-w * 0.455, top + 0.0002 * scale, d * 0.455), 0.0016 * scale, 0.0005 * scale, H.M_GOLD, seg=3, **kw)
    P.box((iw * 0.30, top + ih + 0.00022 * scale, -idd * 0.32), (iw * 0.24, 0.0004 * scale, 0.0016 * scale), hw(acc, 0.3, 0.4), bevel=0.0, **kw)
    return top + ih + 0.0003 * scale, iw, idd


def cpu_product(P, p):
    w, d = CPU_LOOK[cpu_family(p)][:2]
    top, iw, idd = cpu_chip(P, p, w, d, 0.0003)
    P.label("name", (0, top + 0.0002, 0.0), iw * 0.80, idd * 0.46, "y")


def cpu_mount(P, p):
    """Einbau: Sockel und Kuehler des Tiers, Prozessor und Kuehler in eigener Ausfuehrung."""
    tier = int(p["vtier"])
    pid = p["id"]
    fam = cpu_family(p)
    acc = CPU_LOOK[fam][4]
    sub = PCB[CPU_LOOK[fam][2]]
    alu = pickv(pid, [H.M_ALU, NICKEL, H.M_ALU, hw("8f959d", 0.85, 0.34)], 3)
    cu = pickv(pid, [H.M_COPPER, hw("c8743c", 0.95, 0.24), NICKEL], 4) if tier > 0 else H.M_COPPER
    top = pickv(pid, [H.M_DARK_STEEL, H.M_GUNMETAL, hw("17191d", 0.5, 0.4), hw("3a3f47", 0.8, 0.34)], 5)
    P.remap = {H.M_PCB_SUB_G: sub, H.M_ALU: alu, H.M_COPPER: cu, H.M_DARK_STEEL: top}
    extras = []

    def build(q):
        H.build_cpu(q, tier)
        # Eigene Details am Kuehler
        q.remap = {}
        q.pick = None
        q.cur = "Cooler"
        y = [0.0416, 0.0700, 0.1024, 0.0968][tier]
        wide = [0.036, 0.048, 0.052, 0.046][tier]
        a = hw(acc, 0.5, 0.32)
        q.box((0, y, 0.0), (wide * rnd(pid, 0.6, 1.0, 6), 0.0010, 0.010 + rnd(pid, 0, 0.010, 7)), a, bevel=0.0003)
        st = int(rnd(pid, 0, 3.99, 8))
        if st == 1:
            for s in (-1, 1):
                q.box((s * wide * 0.80, y, 0), (0.004, 0.0012, 0.060), a, bevel=0.0003)
        elif st == 2:
            for i in range(3):
                q.box((0, y, -0.026 + 0.026 * i), (wide * 1.4, 0.0009, 0.0024), a, bevel=0.0)
        elif st == 3:
            for sx in (-1, 1):
                for sz in (-1, 1):
                    q.cyl((sx * wide * 0.9, y + 0.0004, sz * 0.034), 0.0050, 0.0016, a, seg=14)
        if tier >= 2 and rnd(pid, 0, 1, 9) > 0.45:
            q.box((0, y + 0.0004, -0.040), (wide * 1.2, 0.0014, 0.0030), hw(acc, 0.0, 0.3, 1.6), bevel=0.0)
        q.cur = None

    real_pick = {}
    A.split_cpu(P, build, False)
    P.label("name", (0, 0.0154, 0.0), 0.052, 0.030, "y")


# ---------------------------------------------------------------- RAM

def ram_look(p):
    n, pid, tier = p["name"], p["id"], int(p["vtier"])
    gb = int(p.get("ram_gb", 8)) if "ram_gb" in p else int("".join(c for c in pid.split("_")[-1] if c.isdigit()) or 8)
    ecc = any(k in n for k in ("ECC", "RDIMM", "LRDIMM", "FB-DIMM", "Server"))
    style = "bare"
    if "FB-DIMM" in n:
        style = "fb"
    elif "LRDIMM" in n or "RDIMM" in n:
        style = "lr"
    elif "Quad-Channel" in n or "Octa" in n or "Hexa" in n:
        style = pickv(pid, ["fins", "wave", "bar"], 1)
    elif "Value" in n or gb <= 4:
        style = "bare"
    elif ecc:
        style = pickv(pid, ["clip", "flat", "bare"], 2)
    else:
        style = pickv(pid, ["comb", "flat", "wave"], 3)
    pcb = "green" if (tier <= 1 or (ecc and rnd(pid, 0, 1, 4) > 0.3)) else pickv(pid, ["black", "blue", "black", "red"], 5)
    col = pickv(pid, ["2b3038", "a4a9b0", "8c1d20", "1d3f86", "2d6a3a", "b9822a", "5a2d82", "1c1e22"], 6 + tier)
    kit = 8 if "Octa" in n else 6 if "Hexa" in n else 4 if "Quad" in n else 3 if "Triple" in n else 2
    chips = 4 if gb / kit <= 1 else 8 if gb / kit <= 8 else 16
    return {"gb": gb, "ecc": ecc, "style": style, "pcb": pcb, "col": col, "kit": kit, "chips": chips, "rgb": style in ("bar", "wave") and not ecc or "Octa" in n}


def ram_stick(P, p, L, M=None, grp="Body", h=0.031, base=0.006):
    """Ein Riegel im Raum der Einbauvariante: x dick, y hoch, z lang. M verschiebt ihn."""
    m = M if M is not None else H.I4
    mc = hw(L["col"], 0.75, 0.34)
    ln = 0.133
    kw = {"group": grp}
    P.box((0, base + h / 2, 0), (0.0014, h, ln), PCB[L["pcb"]], m, bevel=0.0, **kw)
    key = {0: -0.004, 1: 0.004, 2: 0.0065, 3: -0.0065}[int(p["vtier"])]
    for z0, z1 in ((-0.0655, key - 0.0015), (key + 0.0015, 0.0655)):
        P.box((0, base + 0.0025, (z0 + z1) / 2), (0.0016, 0.005, z1 - z0), H.M_GOLD, m, bevel=0.0, **kw)
    n = L["chips"]
    rows = 2 if n == 16 else 1
    per = 8 if n >= 8 else 4
    if L["ecc"]:
        per += 1
    for side in (-1, 1):
        for r in range(rows):
            for i in range(per):
                z = (i - (per - 1) / 2) * (0.118 / per)
                cy = base + (0.0165 if rows == 1 else (0.0115 + 0.0110 * r))
                P.box((side * 0.0011, cy, z), (0.0010, 0.0088 if rows == 1 else 0.0078, min(0.0105, 0.095 / per)), H.M_IC, m, bevel=0.0, **kw)
    P.box((0.0010, base + 0.0250, -0.020), (0.0007, 0.0030, 0.0045), H.M_IC, m, bevel=0.0, **kw)
    if int(p["vtier"]) >= 3:
        P.box((0.0012, base + 0.020, 0.0), (0.0012, 0.0085, 0.0070), H.M_IC, m, bevel=0.0, **kw)
        for i in range(3):
            P.box((0.0011, base + 0.0255, 0.008 + 0.005 * i), (0.0009, 0.003, 0.003), TIN, m, bevel=0.0, **kw)
    st = L["style"]
    top = base + h
    if st == "bare":
        P.box((-0.0017, base + 0.0165, -0.028), (0.0003, 0.011, 0.050), PAPER, m, bevel=0.0, **kw)
    elif st == "lr":
        for s in (-1, 1):
            P.box((s * 0.0018, base + 0.0265, 0), (0.0012, 0.0070, 0.126), H.M_IC, m, bevel=0.0, **kw)
            for i in range(9):
                P.box((s * 0.0021, base + 0.0075, (i - 4) * 0.0135), (0.0010, 0.0036, 0.0080), H.M_IC, m, bevel=0.0, **kw)
        P.box((0.0024, base + 0.0265, -0.020), (0.0003, 0.0062, 0.056), PAPER, m, bevel=0.0, **kw)
        P.box((-0.0024, base + 0.0265, 0.040), (0.0003, 0.0062, 0.020), hw(L["col"], 0.1, 0.6), m, bevel=0.0, **kw)
    elif st == "fb":
        P.box((0.0038, base + 0.0165, 0), (0.0042, 0.024, 0.126), TIN, m, bevel=0.0008, **kw)
        P.box((-0.0024, base + 0.0165, 0), (0.0012, 0.024, 0.126), TIN, m, bevel=0.0003, **kw)
        P.box((0.0062, base + 0.0165, 0.004), (0.0010, 0.016, 0.040), H.M_ALU, m, bevel=0.0003, **kw)
    elif st == "clip":
        for s in (-1, 1):
            P.box((s * 0.0024, base + 0.018, 0), (0.0009, 0.021, 0.128), H.M_ALU, m, bevel=0.0, **kw)
        for z in (-0.044, 0, 0.044):
            P.box((0, top - 0.004, z), (0.0066, 0.005, 0.007), H.M_CHROME, m, bevel=0.0, **kw)
    else:
        sh = 0.026 if st in ("flat", "comb") else 0.029
        for s in (-1, 1):
            P.box((s * 0.0026, base + 0.0065 + sh / 2, 0), (0.0013, sh, 0.130), mc, m, bevel=0.0003, **kw)
            for g in range(3):
                P.box((s * 0.0034, base + 0.012 + g * 0.006, 0.030), (0.0004, 0.0014, 0.050 - 0.010 * g), TIN, m, bevel=0.0, **kw)
        t2 = base + 0.0065 + sh
        if st == "comb":
            P.fins((0, t2 + 0.003, 0), (0.0064, 0.006, 0.126), 22, 2, mc, m, fill_ratio=0.5, **kw)
        elif st == "fins":
            P.box((0, t2 + 0.0006, 0), (0.0062, 0.0014, 0.128), mc, m, bevel=0.0, **kw)
            P.fins((0, t2 + 0.0052, 0), (0.0062, 0.008, 0.122), 14, 2, mc, m, fill_ratio=0.46, **kw)
        elif st == "wave":
            for i in range(7):
                P.box((0, t2 + 0.0012 + 0.0028 * abs(math.sin(i * 0.9)), (i - 3) * 0.018), (0.0062, 0.0040 + 0.0050 * abs(math.sin(i * 0.9)), 0.0175), mc, m, bevel=0.0005, **kw)
        elif st == "bar":
            P.box((0, t2 + 0.0016, 0), (0.0066, 0.0034, 0.130), mc, m, bevel=0.0005, **kw)
        if L["rgb"]:
            P.box((0, t2 + (0.0052 if st == "bar" else 0.0100 if st == "fins" else 0.0086), 0), (0.0050, 0.0030, 0.122), hw(pickv(p["id"], ["3aa0ff", "8a4dff", "28d8a0", "ff5a3c"], 9), 0.0, 0.3, 1.6), m, bevel=0.0006, **kw)
    P.label("name", (0.0037 if st not in ("bare", "lr", "fb") else 0.0066 if st == "fb" else (0.0027 if st == "lr" else 0.0018), base + (0.0265 if st == "lr" else 0.0165), -0.026), 0.060, 0.0062 if st == "lr" else 0.012, "x", m) if grp in ("Body", "Stick_0") else None


def ram_product(P, p):
    L = ram_look(p)
    n = L["kit"]
    for i in range(n):
        ram_stick(P, p, L, T(V(((i - (n - 1) / 2) * 0.020, -0.006, 0))), "Body" if i == n - 1 else "Stick_%d" % (i + 1))
    if n > 2:
        P.labels = P.labels[-1:]


def ram_mount(P, p):
    tier = int(p["vtier"])
    L = ram_look(p)
    real_populated = min(2 + tier * 2, 8)

    def build(q):
        # Nur Steckplaetze und Hebel aus dem Grundmodell, Riegel kommen in eigener Ausfuehrung.
        for i in range(8):
            rx = -0.063 + i * 0.018
            slot_m = H.M_PLASTIC if (i % 2 == 0) else pickv(p["id"], [H.M_GUNMETAL, hw("1d3a70", 0.0, 0.5), hw("4a4d52", 0.0, 0.5)], 11)
            q.box((rx, 0.0042, 0.0), (0.0076, 0.0122, 0.146), slot_m, bevel=0.0005)
            q.box((rx, 0.0104, 0.0), (0.0022, 0.0005, 0.138), H.M_CAVITY, bevel=0.0)
            for z in (-0.071, 0.071):
                H._dimm_latch(q, rx, z, i < real_populated)
        for i in range(real_populated):
            g = "Stick_%d" % i
            q.cur = g
            ram_stick(q, p, L, T(V((-0.063 + i * 0.018, 0, 0))), "Body")
            q.cur = None

    A.split_ram(P, build, False)
    P.labels = P.labels[:1]


# ---------------------------------------------------------------- GPU

def gpu_look(p):
    n, pid, tier = p["name"], p["id"], int(p["vtier"])
    if "Blick" in n:
        style = "mini"
    elif "Plan" in n:
        style = "blower"
    elif "Stream" in n or "Tensor" in n:
        style = "passive_low"
    elif "Halle" in n:
        style = "passive"
    elif "Kern" in n or "Rechner" in n:
        style = "module"
    elif "Grafik" in n:
        style = "axial"
    else:
        style = "axial"
    col = {"Blick": "2d6b36", "Plan": "14171b", "Stream": "1d2126", "Tensor": "1b2a22", "Halle": "20242b", "Kern": "23262b", "Rechner": "2a1d18", "Grafik": "16335e", "Bild": "22262c", "Strahl": "17191d"}
    body = next((c for k, c in col.items() if k in n), "1b1e22")
    if style == "axial":
        body = pickv(pid, ["17191d", "22262c", "2c3138", "e4e6e9", "191f2b", "301a1c"], 1)
    acc = pickv(pid, ["6fbf3a", "3aa0ff", "ff6a2a", "b84dff", "28d8b0", "ffcc33", "ff4060"], 2)
    if "Rechner" in n:
        acc = "ff6a2a"
    if "Kern" in n or "Halle" in n or "Plan" in n:
        acc = pickv(pid, ["8fd63c", "a8c94a", "d9ab3c"], 3)
    w = int(p["watts"])
    fans = 0
    if style == "axial":
        fans = 1 if tier == 1 and w < 130 else 2 if w < 260 else 3
    elif style == "mini":
        fans = 0 if w < 25 else 1
    return {"style": style, "body": body, "acc": acc, "fans": fans, "w": w, "pipes": 2 + min(4, w // 110)}


def gpu_card(P, p, L, card_len, card_h, M, rot_base, origin, thick=0.030):
    """Karte wie in build_gpu: x = Dicke (Luefterseite +X), y = Hoehe, z = Laenge (-Z = Slotblech)."""
    pid, tier, st = p["id"], int(p["vtier"]), L["style"]
    body = hw(L["body"], 0.35 if st != "module" else 0.8, 0.40 if st != "module" else 0.30)
    acc = hw(L["acc"], 0.3, 0.35)
    glow = hw(L["acc"], 0.0, 0.3, 1.8)
    half, mid = card_len / 2, card_h / 2
    rotor_i = rot_base
    P.box((0, mid, 0), (0.0032, card_h, card_len), PCB["black" if tier > 0 else "green"], M, bevel=0.0)
    cz = -0.155 + half
    for z0, z1 in ((-0.146, -0.128), (-0.122, 0.004)):
        P.box((0, 0.005, (z0 + z1) / 2 - cz), (0.0036, 0.008, z1 - z0), H.M_GOLD, M, bevel=0.0)
    if st != "mini":
        bp = body if rnd(pid, 0, 1, 4) > 0.4 else H.M_GUNMETAL
        P.box((-0.0034, mid + 0.003, 0.002), (0.0018, card_h - 0.008, card_len - 0.010), bp, M, bevel=0.0005)
        for v in range(4 + int(rnd(pid, 0, 5, 5))):
            P.box((-0.0044, mid + 0.003, half - 0.030 - v * 0.009), (0.0006, card_h * rnd(pid, 0.35, 0.6, 6), 0.0038), H.M_CAVITY, M, bevel=0.0)
        if rnd(pid, 0, 1, 7) > 0.35:
            P.box((-0.0045, mid + 0.004, -half + card_len * 0.35), (0.0005, 0.0030, card_len * 0.34), acc, M, bevel=0.0)
        P.label("back", (-0.0047, mid + 0.020, -half + card_len * 0.30), card_len * 0.36, 0.016, "-x", M)
    # Slotblech
    bz = -half - 0.003
    P.box((0.012, mid + 0.004, bz), (0.036, card_h + 0.010, 0.0022), H.M_STEEL if st != "module" else H.M_DARK_STEEL, M, bevel=0.0)
    P.box((0.012, card_h + 0.009, bz + 0.006), (0.036, 0.0022, 0.012), H.M_STEEL, M, bevel=0.0)
    if st in ("axial", "blower", "mini"):
        for q in range(4 if st != "mini" else 2):
            py = 0.016 + q * 0.016
            if py < card_h - 0.008:
                P.box((0.004, py, bz - 0.0016), (0.0105, 0.0068, 0.0012), H.M_CAVITY if q % 3 else H.M_USB_BLUE, M, bevel=0.0)
        P.box((0.022, mid, bz - 0.0012), (0.011, card_h * 0.72, 0.0008), H.M_HONEY_DARK, M, bevel=0.0, uv_scale=0.045)
    else:
        P.fins((0.016, mid, bz - 0.0012), (0.018, card_h * 0.8, 0.0014), 8, 1, H.M_CAVITY, M, fill_ratio=0.5)
    fx = thick - 0.003
    blade = pickv(pid, [H.M_BLADE_GPU, hw("0f1114", 0.1, 0.5), hw("3a3f46", 0.2, 0.45), hw("c9ccd1", 0.1, 0.5)], 8)
    if st == "mini":
        sink = pickv(pid, [H.M_ALU, hw("2d6b36", 0.6, 0.4), hw("1d3f86", 0.6, 0.4), BLACK], 9)
        P.fins((0.009, mid, 0.0), (0.014, card_h * 0.72, card_len * 0.55), 12, 2, sink, M, fill_ratio=0.42)
        P.box((0.0025, mid, 0.0), (0.003, card_h * 0.74, card_len * 0.57), sink, M, bevel=0.0004)
        for k in range(4):
            P.box((0.0022, 0.016 + 0.014 * (k % 2), half - 0.02 - 0.016 * (k // 2)), (0.0012, 0.010, 0.011), H.M_IC, M, bevel=0.0)
        if L["fans"]:
            P.ring(M @ T((0.017, mid, 0)) @ Ry(90), 0.021, 0.0235, 0.004, BLACK, seg=28)
            key = "Rotor_X_%d" % rotor_i
            rotor_i += 1
            o = origin + V((0.0165, mid, 0.0))
            P.new_group(key, o)
            P.rotor(T(o) @ Ry(90), 0.020, 9, blade, H.M_GUNMETAL, group=key, hub_ratio=0.36, depth_ratio=0.24, sweep=0.7, cap_mat=acc)
        P.label("side", (0.0026, mid, -half + 0.03), 0.034, 0.012, "x", M)
        return rotor_i
    if st in ("passive", "passive_low"):
        P.box((fx - 0.009, mid, -0.004), (0.020, card_h - 0.004, card_len - 0.034), body, M, bevel=0.0012)
        for e in (-1, 1):
            P.fins((fx - 0.009, mid, e * (half - 0.014)), (0.0185, card_h - 0.010, 0.024), 12, 1, H.M_ALU if st == "passive" else H.M_COPPER, M, fill_ratio=0.45)
        n = 2 + int(rnd(pid, 0, 4, 10))
        for k in range(n):
            P.box((fx + 0.0013, mid + (k - (n - 1) / 2) * 0.012, 0), (0.0008, 0.0030, card_len * 0.62), acc if k == n // 2 else H.M_DARK_STEEL, M, bevel=0.0)
        P.box((fx + 0.0014, card_h - 0.012, -half + 0.05), (0.0008, 0.006, 0.022), glow, M, bevel=0.0)
        P.label("side", (fx + 0.0022, mid, -0.01), card_len * 0.45, 0.020, "x", M)
    elif st == "blower":
        P.box((fx - 0.008, mid, -0.006), (0.022, card_h - 0.004, card_len - 0.012), body, M, bevel=0.0016)
        fz = half - 0.044
        r = min(0.030, card_h * 0.40)
        P.cyl((fx + 0.0030, mid, fz), r + 0.002, 0.0012, H.M_CAVITY, M, axis="x", seg=36)
        P.ring(M @ T((fx + 0.0034, mid, fz)) @ Ry(90), r + 0.001, r + 0.004, 0.0026, H.M_GUNMETAL, seg=36)
        key = "Rotor_X_%d" % rotor_i
        rotor_i += 1
        o = origin + V((fx + 0.002, mid, fz))
        P.new_group(key, o)
        P.rotor(T(o) @ Ry(90), r - 0.001, 26, blade, H.M_GUNMETAL, group=key, hub_ratio=0.52, depth_ratio=0.20, sweep=0.25, cap_mat=acc)
        for k in range(3):
            P.box((fx + 0.0033, 0.012 + k * 0.006, -half + card_len * 0.35), (0.0008, 0.0018, card_len * 0.40), H.M_GUNMETAL, M, bevel=0.0)
        P.box((fx + 0.0033, card_h - 0.010, -half + card_len * 0.30), (0.0008, 0.0026, card_len * 0.30), glow if tier >= 2 else acc, M, bevel=0.0)
        P.label("side", (fx + 0.0038, mid + 0.008, -half + card_len * 0.32), card_len * 0.40, 0.020, "x", M)
    elif st == "module":
        gold = hw("d9ab3c", 0.95, 0.24)
        P.box((fx - 0.009, mid, -0.012), (0.022, card_h - 0.004, card_len - 0.050), body, M, bevel=0.0016)
        iz = half - 0.026
        fin = [H.M_COPPER, gold, NICKEL, hw("2a2d32", 0.8, 0.35), hw("8c1d20", 0.7, 0.35)][int(p.get("i", 0)) % 5]
        P.fins((fx - 0.009, mid, iz), (0.022, card_h - 0.010, 0.046), 10 + int(rnd(pid, 0, 8, 12)), 1, fin, M, fill_ratio=0.45)
        P.box((fx - 0.009, card_h - 0.003, iz), (0.022, 0.004, 0.048), body, M, bevel=0.0)
        P.box((fx - 0.009, card_h + 0.0016, -0.012), (0.020, 0.0030, card_len * rnd(pid, 0.35, 0.66, 13)), pickv(pid, [gold, acc, H.M_GUNMETAL], 14), M, bevel=0.0006)
        k = int(p.get("i", 0)) % 4
        face = fx + 0.0023
        if k == 0:
            P.box((face, mid, -0.030), (0.0010, card_h * 0.60, card_len * 0.40), gold, M, bevel=0.0006)
        elif k == 1:
            for i in range(5):
                P.box((face, mid, -half + 0.050 + 0.026 * i), (0.0010, card_h * 0.62, 0.0040), gold, M, rot=Rx(22), bevel=0.0)
        elif k == 2:
            P.ring(M @ T((face, mid, -0.030)) @ Ry(90), 0.022, 0.026, 0.0012, gold, seg=40)
            P.ring(M @ T((face, mid, -0.030)) @ Ry(90), 0.014, 0.016, 0.0012, acc, seg=40)
        else:
            for i in range(3):
                P.box((face, mid + (i - 1) * 0.020, -0.030), (0.0010, 0.0032, card_len * 0.50), gold if i != 1 else acc, M, bevel=0.0)
        P.box((face + 0.0004, 0.012, -half + 0.060), (0.0008, 0.0030, 0.060), glow, M, bevel=0.0)
        for i in range(2):
            P.box((0, card_h + 0.0016, -half + 0.040 + i * 0.030), (0.0036, 0.0032, 0.022), H.M_GOLD, M, bevel=0.0)
        P.label("side", (face + 0.0012, mid + card_h * 0.36, 0.030), card_len * 0.34, 0.012, "x", M)
    else:  # axial
        n = L["fans"]
        fan_r = min((card_len - 0.020) / n * 0.46, card_h * 0.44)
        cut = fan_r + 0.0022
        zs = [(i - (n - 1) / 2) * (card_len - 0.016) / n for i in range(n)]
        if n == 1:
            zs = [0.012]
        P.fins((0.012, mid, 0), (0.014, card_h - 0.008, card_len - 0.024), 16 + 4 * n, 2, pickv(pid, [H.M_ALU, NICKEL, hw("2a2d32", 0.8, 0.35)], 16), M, fill_ratio=0.42)
        P.box((fx, card_h - 0.004, 0), (0.0055, 0.0085, card_len - 0.006), body, M, bevel=0.0010)
        P.box((fx, 0.004, 0), (0.0055, 0.0085, card_len - 0.006), body, M, bevel=0.0010)
        seg = -half + 0.003
        for fz in zs:
            e = fz - cut
            if e > seg + 0.001:
                P.box((fx, mid, (seg + e) / 2), (0.0055, card_h - 0.014, e - seg), body, M, bevel=0.0010)
            seg = fz + cut
        if half - 0.003 > seg + 0.001:
            P.box((fx, mid, (seg + half - 0.003) / 2), (0.0055, card_h - 0.014, half - 0.003 - seg), body, M, bevel=0.0010)
        look = int(p.get("i", 0)) % 5
        for fz in zs:
            P.ring(M @ T((fx, mid, fz)) @ Ry(90), fan_r + 0.001, cut, 0.0055, body, square=True, seg=32)
            if look in (1, 3):
                P.ring(M @ T((fx + 0.0030, mid, fz)) @ Ry(90), fan_r + 0.0006, fan_r + 0.0022, 0.0012, acc if look == 1 else glow, seg=40)
            key = "Rotor_X_%d" % rotor_i
            rotor_i += 1
            o = origin + V((fx - 0.003, mid, fz))
            P.new_group(key, o)
            P.rotor(T(o) @ Ry(90), fan_r - 0.001, 7 + int(rnd(pid, 0, 6, 18)), blade, H.M_GUNMETAL, group=key, hub_ratio=rnd(pid, 0.28, 0.38, 19), depth_ratio=0.22, sweep=rnd(pid, 0.5, 0.9, 20), cap_mat=acc if look % 2 else H.M_CHROME)
        if look == 0:
            P.box((fx + 0.0032, card_h - 0.004, 0), (0.0010, 0.0026, card_len - 0.030), acc, M, bevel=0.0)
        elif look == 2:
            for s in (-1, 1):
                P.box((fx + 0.0032, mid, s * (half - 0.016)), (0.0010, card_h * 0.7, 0.0040), acc, M, rot=Rx(s * 24), bevel=0.0)
        elif look == 4:
            for i in range(2):
                P.box((fx + 0.0032, mid + (i * 2 - 1) * card_h * 0.36, 0), (0.0010, 0.0032, card_len * 0.50), acc, M, bevel=0.0)
        P.box((0.016, card_h + 0.0012, -half + card_len * 0.36), (0.0120, 0.0030, card_len * 0.30), glow, M, bevel=0.0006)
        for hp in range(L["pipes"]):
            px = 0.006 + hp * 0.0034
            za, zb = -card_len * 0.18 + hp * 0.008, card_len * 0.24 - hp * 0.010
            P.cable([(px, mid - 0.012, za), (px, card_h + 0.002, za - 0.014), (px, card_h + 0.002, zb), (px, card_h - 0.010, zb + 0.012)], 0.0024, H.M_COPPER if rnd(pid, 0, 1, 21) > 0.4 else NICKEL, M, seg=10)
        P.label("side", (0.016, card_h + 0.0032, -half + card_len * 0.36), card_len * 0.28, 0.009, "y", M, 90)
    # Stromanschluesse
    n_pc = 1 if L["w"] < 230 else 2
    if L["w"] <= 75 and not L.get("mount"):
        n_pc = 0
    for pc in range(n_pc):
        pz = half - 0.030 - pc * 0.024
        if st in ("module",):
            pz = half - 0.014 - pc * 0.022
        P.box((0.009, card_h + 0.0055, pz), (0.0105, 0.0115, 0.0215), H.M_PLASTIC, M, bevel=0.0006)
        for r_ in range(2):
            for k in range(4):
                P.box((0.0065 + r_ * 0.005, card_h + 0.0114, pz - 0.0075 + k * 0.005), (0.0034, 0.0005, 0.0034), H.M_CAVITY, M, bevel=0.0)
    return rotor_i


def gpu_dims(p, L):
    """Einbaumasse: Hoehe je Stufe fest (Schrauben und Stecker der Werkbank), Laenge je Modell."""
    tier = max(1, int(p["vtier"]))
    base = {1: 0.21, 2: 0.28, 3: 0.31}[tier]
    h = 0.072 if tier == 1 else 0.088
    return base, h


def gpu_product(P, p):
    if p["id"] == "gpu_onboard":
        P.box((0, 0.0012, 0), (0.046, 0.0024, 0.030), PCB["green"], bevel=0.0003)
        P.box((0.004, 0.0034, 0.0), (0.014, 0.0020, 0.014), H.M_IC, bevel=0.0004)
        P.box((-0.018, 0.0055, 0.0), (0.016, 0.0070, 0.026), H.M_VGA_BLUE, bevel=0.0006)
        P.box((-0.026, 0.0055, 0.0), (0.003, 0.0086, 0.031), H.M_CHROME, bevel=0.0004)
        for i in range(5):
            P.cyl((0.016, 0.0030, -0.011 + 0.0055 * i), 0.0012, 0.0020, TIN, seg=10)
        P.label("name", (0.004, 0.0046, 0.0), 0.012, 0.008, "y")
        return
    L = gpu_look(p)
    ln = {"mini": 0.146, "passive_low": 0.168}.get(L["style"], 0.0)
    base, h = gpu_dims(p, L)
    if ln == 0.0:
        ln = base * rnd(p["id"], 0.88, 1.0, 22)
    if L["style"] in ("mini", "passive_low"):
        h = 0.056
    if L["style"] == "axial" and int(p["vtier"]) == 2 and L["w"] >= 350:
        ln = 0.300
        h = 0.098
    cards = 2 if "Duo" in p["name"] else 1
    rot = 0
    for c in range(cards):
        o = V((c * 0.050 - (cards - 1) * 0.025, 0.004, 0.0))
        rot = gpu_card(P, p, L, ln, h, T(o), rot, o, 0.036 if L["w"] >= 400 and L["style"] == "axial" else 0.030)
    if cards == 2:
        P.box((0.0, h + 0.012, -0.030), (0.070, 0.0075, 0.060), H.M_GUNMETAL, bevel=0.0012)
        P.box((0.0, h + 0.0160, -0.030), (0.046, 0.0010, 0.030), H.M_GOLD, bevel=0.0)


def gpu_mount(P, p):
    p = dict(p)
    if p["id"] == "gpu_onboard":
        return False
    tier = int(p["vtier"])
    L = gpu_look(p)
    L["mount"] = True
    if tier <= 0:
        # Kleine Karten sitzen im selben Steckplatz, zaehlen aber wie Onboard-Grafik (keine Montage).
        def build0(q):
            H._pcie_slot(q, 0.0)
            o = V((0, 0.006, -0.155 + 0.073))
            gpu_card(q, p, L, 0.146, 0.056, T(o), 0, o)
        A.split_gpu(P, build0, False)
        return True
    base, h = gpu_dims(p, L)
    cards = 2 if tier >= 3 else 1

    def build(q):
        rot = 0
        for c in range(cards):
            cx = c * 0.056
            H._pcie_slot(q, cx)
            o = V((cx, 0.006, -0.155 + base / 2))
            rot = gpu_card(q, p, L, base, h, T(o), rot, o)
        if tier >= 3:
            by = 0.006 + h + 0.006
            q.box((0.028, by, -0.100), (0.068, 0.0065, 0.052), H.M_GUNMETAL, bevel=0.0012)
            q.box((0.028, by + 0.0035, -0.100), (0.044, 0.0006, 0.024), H.M_GOLD, bevel=0.0)

    A.split_gpu(P, build, False)
    P.labels = P.labels[:3]
    return True


# ---------------------------------------------------------------- Speicher

def sto_kind(p):
    n, pid = p["name"], p["id"]
    if "allflash" in pid:
        return "node"
    if "raid_48" in pid:
        return "box8"
    if "nas_12" in pid:
        return "box4"
    if "24tb" in pid:
        return "u2x2"
    if "E3.L" in n:
        return "e3l"
    if "E3.S" in n or "nvme5" in pid:
        return "e3s"
    if "U.2" in n or "U.3" in n:
        return "u2"
    if "M.2" in n:
        return "m2"
    if "SSD" in n:
        return "ssd"
    if "15K" in n:
        return "hdd25"
    return "hdd"


def drive35(P, p, M=None, grp="Body"):
    pid = p["id"]
    col = pickv(pid, ["9aa0a8", "c2c6cc", "6e747c", "31363d"], 1)
    P.box((0, 0.013, 0), (0.1016, 0.026, 0.147), hw("3a3e44", 0.6, 0.4), M, bevel=0.0012, group=grp)
    P.box((0, 0.0262, 0), (0.0960, 0.0012, 0.1400), hw(col, 0.85, 0.28), M, bevel=0.0004, group=grp)
    P.cyl((0.002, 0.0270, -0.020), 0.034, 0.0010, hw(col, 0.9, 0.22), M, seg=48, group=grp)
    P.cyl((0.002, 0.0277, -0.020), 0.010, 0.0010, H.M_CHROME, M, seg=28, group=grp)
    P.cyl((-0.032, 0.0270, 0.052), 0.009, 0.0010, H.M_CHROME, M, seg=24, group=grp)
    lab = pickv(pid, ["f2f1ec", "2d6b36", "1d3f86", "8c1d20", "1c1e22", "b9822a"], 2)
    P.box((0.006, 0.0280, 0.024), (0.080, 0.0003, 0.070), PAPER, M, bevel=0.0, group=grp)
    P.box((0.006, 0.0282, -0.004), (0.080, 0.0003, 0.013), hw(lab, 0.1, 0.5), M, bevel=0.0, group=grp)
    for sx in (-1, 1):
        for z in (-0.060, 0.0, 0.060):
            P.cyl((sx * 0.0510, 0.0075, z), 0.0022, 0.0008, H.M_CAVITY, M, axis="x", seg=12, group=grp)
    for sx in (-0.042, 0.042):
        for sz in (-0.064, 0.064):
            P.screw_head((sx, 0.0268, sz), r=0.0026, h=0.0012, mat=H.M_CHROME, M=M, group=grp)
    P.box((0.018, 0.0055, -0.0738), (0.044, 0.0070, 0.004), H.M_PLASTIC, M, bevel=0.0004, group=grp)
    P.box((0.018, 0.0055, -0.0752), (0.038, 0.0016, 0.0024), H.M_GOLD, M, bevel=0.0, group=grp)
    if "Helium" in p["name"]:
        P.cyl((0.036, 0.0275, 0.060), 0.005, 0.0014, hw("3aa0ff", 0.4, 0.3), M, seg=20, group=grp)
    P.label("name", (0.006, 0.0286, 0.030), 0.072, 0.040, "y", M)


def drive25(P, p, th=0.007, col=None, M=None, grp="Body", lab=True):
    pid = p["id"]
    c = col or pickv(pid, ["23262b", "b4b8be", "31363d", "1b1d20", "5a6068"], 3)
    P.box((0, th / 2, 0), (0.0698, th, 0.1002), hw(c, 0.7, 0.35), M, bevel=0.0010, group=grp)
    P.box((0, th + 0.0001, 0.004), (0.058, 0.0004, 0.076), PAPER if rnd(pid, 0, 1, 4) > 0.5 else hw("16181b", 0.2, 0.5), M, bevel=0.0, group=grp)
    a = pickv(pid, ["3aa0ff", "28d8a0", "ff6a2a", "b84dff", "d9ab3c", "8c1d20"], 5)
    P.box((-0.024, th + 0.0004, 0.004), (0.0060, 0.0004, 0.076), hw(a, 0.2, 0.45), M, bevel=0.0, group=grp)
    P.box((0.0, th * 0.5, -0.0502), (0.040, min(0.0050, th * 0.8), 0.003), H.M_PLASTIC, M, bevel=0.0002, group=grp)
    P.box((0.0, th * 0.5, -0.0514), (0.036, 0.0012, 0.002), H.M_GOLD, M, bevel=0.0, group=grp)
    for sx in (-0.031, 0.031):
        for sz in (-0.044, 0.044):
            P.screw_head((sx, th, sz), r=0.0018, h=0.0008, mat=H.M_CHROME, M=M, group=grp)
    if th > 0.010:
        for k in range(8):
            P.box((0.030, th + 0.0003, -0.030 + 0.009 * k), (0.008, 0.0008, 0.0030), H.M_CAVITY, M, bevel=0.0, group=grp)
    if lab:
        P.label("name", (0.004, th + 0.0007, 0.006), 0.044, 0.056, "y", M)


def m2_board(P, p, M=None, grp="Body"):
    pid = p["id"]
    big = int("".join(c for c in pid.split("_")[-1] if c.isdigit()) or 1)
    gen4 = "nvme4" in pid
    ln = 0.080 if not gen4 else 0.110
    P.box((0, 0.0012, 0), (ln, 0.0010, 0.022), PCB[pickv(pid, ["black", "blue", "green", "black"], 6)], M, bevel=0.0, group=grp)
    P.box((-ln / 2 + 0.0015, 0.0012, -0.003), (0.0032, 0.0012, 0.013), H.M_GOLD, M, bevel=0.0, group=grp)
    P.box((-ln / 2 + 0.0015, 0.0012, 0.0085), (0.0032, 0.0012, 0.004), H.M_GOLD, M, bevel=0.0, group=grp)
    for k in range(2 if ln < 0.1 else 4):
        P.box((-ln / 2 + 0.040 + k * 0.018, 0.0024, 0), (0.0145, 0.0014, 0.018), H.M_IC, M, bevel=0.0, group=grp)
    P.box((-ln / 2 + 0.017, 0.0024, 0), (0.013, 0.0014, 0.013), H.M_CHROME, M, bevel=0.0, group=grp)
    if gen4 or big >= 2:
        c = pickv(pid, ["1b1d20", "b4b8be", "8c1d20", "1d3f86"], 7)
        P.box((0.002, 0.0040, 0), (ln - 0.012, 0.0018, 0.0225), hw(c, 0.8, 0.32), M, bevel=0.0004, group=grp)
        P.fins((0.002, 0.0068, 0), (ln - 0.014, 0.0042, 0.0220), 5 + int(rnd(pid, 0, 4, 8)), 2, hw(c, 0.8, 0.32), M, fill_ratio=0.48, group=grp)
        P.label("name", (0.002, 0.0092, 0.0), ln * 0.6, 0.012, "y", M)
    else:
        P.box((0.006, 0.0033, 0), (ln * 0.62, 0.0003, 0.019), PAPER, M, bevel=0.0, group=grp)
        P.label("name", (0.006, 0.0036, 0.0), ln * 0.55, 0.014, "y", M)


def sto_product(P, p):
    k, pid = sto_kind(p), p["id"]
    if k == "hdd":
        drive35(P, p)
    elif k == "hdd25":
        drive25(P, p, 0.015, "8f959d")
    elif k == "ssd":
        drive25(P, p, 0.015 if "SAS" in p["name"] else 0.007)
    elif k == "m2":
        m2_board(P, p)
    elif k == "u2":
        drive25(P, p, 0.015, pickv(pid, ["23262b", "3a3f46", "1d2430"], 9))
        for i in range(9):
            P.box((-0.0352, 0.0075, -0.040 + 0.010 * i), (0.0014, 0.010, 0.0030), H.M_GUNMETAL, bevel=0.0)
    elif k == "u2x2":
        for i in range(4):
            drive25(P, p, 0.015, "23262b", T((0.0, 0.004 + 0.018 * i, 0)), "Body", i == 3)
        for s in (-1, 1):
            P.box((s * 0.0375, 0.038, 0), (0.003, 0.076, 0.104), H.M_STEEL, bevel=0.0004)
        P.box((0, 0.0015, 0), (0.078, 0.003, 0.104), H.M_STEEL, bevel=0.0004)
    elif k in ("e3s", "e3l"):
        ln = 0.1128 if k == "e3s" else 0.1422
        th = 0.0075 if "15tb" in pid else 0.0168
        c = pickv(pid, ["2a2d32", "b4b8be", "17191d", "3b2f1c"], 10)
        P.box((0, th / 2, 0), (0.076, th, ln), hw(c, 0.8, 0.32), bevel=0.0010)
        P.fins((0, th + 0.0008, -0.006), (0.070, 0.0024, ln - 0.030), 12 + int(rnd(pid, 0, 10, 11)), 0, hw(c, 0.8, 0.30), fill_ratio=0.45)
        P.box((0, th * 0.5, ln / 2 + 0.003), (0.078, th + 0.004, 0.006), BLACK, bevel=0.0008)
        P.box((0.026, th * 0.5, ln / 2 + 0.0066), (0.012, 0.0022, 0.0010), hw("28d8a0", 0.0, 0.3, 1.8), bevel=0.0)
        P.box((0, th * 0.5, -ln / 2 - 0.001), (0.046, 0.0016, 0.004), H.M_GOLD, bevel=0.0)
        P.label("name", (0, th * 0.5, ln / 2 + 0.0064), 0.040, 0.006, "z")
    elif k in ("box4", "box8"):
        n = 4 if k == "box4" else 8
        cols = 2 if k == "box4" else 4
        w = 0.112 * cols + 0.02
        h = 0.032 * (n // cols) + 0.04
        P.box((0, h / 2, -0.004), (w, h, 0.20), hw("24272c", 0.5, 0.42), bevel=0.003)
        for i in range(n):
            x = (i % cols - (cols - 1) / 2) * 0.112
            y = 0.030 + 0.034 * (i // cols)
            P.box((x, y, 0.098), (0.106, 0.030, 0.008), BLACK, bevel=0.0008)
            P.box((x + 0.030, y, 0.1030), (0.036, 0.018, 0.004), H.M_GUNMETAL, bevel=0.0006)
            P.box((x - 0.040, y + 0.008, 0.1026), (0.004, 0.0024, 0.0010), hw("28d8a0" if i % 3 else "3aa0ff", 0.0, 0.3, 1.8), bevel=0.0)
            P.fins((x - 0.020, y, 0.1022), (0.030, 0.020, 0.0010), 5, 1, H.M_CAVITY, fill_ratio=0.5)
        P.box((0, h + 0.002, 0), (w * 0.8, 0.002, 0.14), H.M_HONEY_DARK, bevel=0.0, uv_scale=0.045)
        P.label("name", (0, h - 0.012, 0.0975), w * 0.6, 0.012, "z")
    else:
        P.box((0, 0.022, 0), (0.44, 0.044, 0.30), hw("1b1e22", 0.6, 0.38), bevel=0.002)
        for i in range(24):
            x = (i - 11.5) * 0.0172
            P.box((x, 0.022, 0.152), (0.0155, 0.036, 0.006), H.M_GUNMETAL if i % 2 else BLACK, bevel=0.0006)
            P.box((x, 0.036, 0.1556), (0.006, 0.0016, 0.0010), hw("28d8a0" if i % 5 else "3aa0ff", 0.0, 0.3, 1.8), bevel=0.0)
        for s in (-1, 1):
            P.box((s * 0.232, 0.022, 0.146), (0.024, 0.044, 0.004), H.M_ALU, bevel=0.0006)
        P.box((0, 0.0448, 0.02), (0.30, 0.0016, 0.16), H.M_DARK_STEEL, bevel=0.0004)
        P.box((0, 0.0460, -0.08), (0.36, 0.0012, 0.0040), hw("ff6a2a", 0.0, 0.3, 1.6), bevel=0.0)
        P.label("name", (0, 0.0460, 0.02), 0.26, 0.06, "y")


def sto_mount(P, p):
    tier, pid = int(p["vtier"]), p["id"]
    c = pickv(pid, ["1b1d20", "b4b8be", "8c1d20", "1d3f86", "2d6b36", "b9822a"], 12)
    sink = hw(c, 0.8, 0.32)
    P.remap = {H.M_PCB_SUB_B: PCB[pickv(pid, ["black", "blue", "green"], 13)], H.M_GUNMETAL: sink, H.M_COPPER: sink if rnd(pid, 0, 1, 14) > 0.4 else H.M_COPPER,
               H.M_NVME_LBL: hw(pickv(pid, ["f2f1ec", "16181b", "2d6b36", "1d3f86"], 15), 0.05, 0.55)}

    def build(q):
        H.build_storage(q, tier)
        n = min(1 + tier, 3)
        a = hw(pickv(pid, ["3aa0ff", "28d8a0", "ff6a2a", "b84dff", "d9ab3c"], 16), 0.1, 0.4)
        ln = 0.080 if tier <= 1 else 0.110
        for i in range(n):
            q.cur = "SSD_%d" % i
            q.box((-0.056 + ln * 0.62, [0.0060, 0.0065, 0.0128, 0.0138][tier], -0.032 + i * 0.034), (0.010, 0.0006, 0.018), a, bevel=0.0)
            q.box((-0.056 + 0.010, 0.0046, -0.032 + i * 0.034 + 0.008), (0.0022, 0.0010, 0.0016), hw("28d8a0", 0.0, 0.3, 2.0), bevel=0.0)
            q.cur = None

    A.split_storage(P, build, False)


# ---------------------------------------------------------------- Kuehlung

def fan(P, x, y, z, size, depth, col, blades, key, led=None, axis="z", frame=BLACK):
    """Luefter mit Rahmen; axis = Achse, um die er sich dreht."""
    rot = {"z": H.I4, "y": Rx(-90), "x": Ry(90)}[axis]
    M = T((x, y, z)) @ rot
    r = size * 0.47
    P.ring(M, r, size * 0.5, depth, frame, square=True, seg=36)
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.cyl((sx * size * 0.43, sy * size * 0.43, depth / 2 + 0.0003), size * 0.030, 0.0008, H.M_CHROME, M, axis="z", seg=10)
    P.cyl((0, 0, -depth * 0.42), size * 0.18, depth * 0.12, frame, M, axis="z", seg=24)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        P.box((r * 0.62 * math.cos(a), r * 0.62 * math.sin(a), -depth * 0.42), (r * 0.80, size * 0.030, depth * 0.10), frame, M, rot=Rz(45 + 90 * k), bevel=0.0)
    if led:
        P.ring(M @ T((0, 0, depth / 2)), r * 0.985, r * 1.035, 0.0016, led, seg=40)
    o = V((x, y, z))
    name = "Rotor_%s_%s" % (axis.upper(), key)
    P.new_group(name, o)
    P.rotor(T(o) @ rot, r * 0.95, blades, col, frame, group=name, hub_ratio=0.36, depth_ratio=min(0.5, depth / size * 1.3), sweep=0.65, cap_mat=H.M_ALU)


def tower(P, w, h, d, n_pipes, fins, fmat, pmat, cap):
    P.box((0, 0.005, 0), (0.044, 0.010, 0.044), H.M_COPPER, bevel=0.0010)
    P.box((0, 0.0005, 0), (0.038, 0.0012, 0.038), NICKEL, bevel=0.0)
    y0 = 0.032
    P.fins((0, y0 + h / 2, 0), (w, h, d), fins, 1, fmat, fill_ratio=0.36)
    for i in range(n_pipes):
        z = (i - (n_pipes - 1) / 2) * (d * 0.8 / max(1, n_pipes - 1) if n_pipes > 1 else 0)
        P.cable([(-w * 0.34, y0 + h + 0.004, z), (-w * 0.34, 0.020, z), (-0.014, 0.0065, z * 0.6), (0.014, 0.0065, z * 0.6), (w * 0.34, 0.020, z), (w * 0.34, y0 + h + 0.004, z)], 0.0030, pmat, seg=10)
        for s in (-1, 1):
            P.cyl((s * w * 0.34, y0 + h + 0.005, z), 0.0036, 0.0030, pmat, seg=12)
    P.box((0, y0 + h + 0.0012, 0), (w, 0.0024, d), cap, bevel=0.0006)


def cool_product(P, p):
    pid, n, tier = p["id"], p["name"], int(p["vtier"])
    led = hw(pickv(pid, ["3aa0ff", "28d8a0", "ff6a2a", "b84dff"], 1), 0.0, 0.3, 1.6)
    blade = pickv(pid, [H.M_BLADE_FAN, hw("2a2d32", 0.1, 0.5), hw("c9ccd1", 0.05, 0.5), hw("7a5030", 0.05, 0.55)], 2)
    if pid == "cool_box_40mm":
        P.fins((0, 0.016, 0), (0.060, 0.026, 0.060), 14, 0, H.M_ALU, fill_ratio=0.42)
        P.box((0, 0.003, 0), (0.062, 0.006, 0.062), H.M_ALU, bevel=0.0008)
        fan(P, 0, 0.037, 0, 0.052, 0.014, blade, 7, "0", None, "y")
    elif pid == "cool_sunon_40mm_hs":
        fan(P, 0, 0.022, 0, 0.040, 0.028, blade, 5, "0")
        P.cable([(0.018, 0.006, -0.012), (0.04, 0.004, -0.02), (0.06, 0.004, 0.01)], 0.0016, H.M_CABLE, seg=8)
    elif pid == "cool_slim_60mm":
        fan(P, 0, 0.031, 0, 0.060, 0.015, blade, 7, "0")
        P.cable([(0.026, 0.006, -0.006), (0.05, 0.004, -0.02), (0.07, 0.004, 0.02)], 0.0016, H.M_CABLE, seg=8)
    elif pid == "cool_alu_tower":
        tower(P, 0.090, 0.070, 0.044, 2, 24, H.M_ALU, H.M_ALU, H.M_ALU)
        fan(P, 0, 0.068, 0.036, 0.088, 0.022, blade, 9, "0")
    elif pid in ("cool_dual_80mm", "cool_dual_92mm"):
        s = 0.080 if "80" in pid else 0.092
        for i in (-1, 1):
            fan(P, i * (s * 0.5 + 0.003), s * 0.5 + 0.004, 0, s, 0.025, blade, 9 if i < 0 else 9, str((i + 1) // 2), led if "92" in pid else None)
        P.box((0, 0.002, 0), (s * 2 + 0.012, 0.004, 0.028), H.M_DARK_STEEL, bevel=0.0004)
    elif pid == "cool_blower_1u":
        P.box((0, 0.014, 0), (0.094, 0.028, 0.094), BLACK, bevel=0.003)
        P.cyl((0, 0.0285, 0.008), 0.034, 0.0012, H.M_CAVITY, seg=40)
        o = V((0, 0.028, 0.008))
        P.new_group("Rotor_Y_0", o)
        P.rotor(T(o) @ Rx(-90), 0.032, 28, blade, BLACK, group="Rotor_Y_0", hub_ratio=0.5, depth_ratio=0.22, sweep=0.2, cap_mat=H.M_ALU)
        P.fins((0, 0.014, -0.056), (0.086, 0.024, 0.030), 20, 0, H.M_COPPER, fill_ratio=0.4)
    elif pid == "cool_tower_120":
        tower(P, 0.120, 0.104, 0.050, 4, 40, H.M_ALU, H.M_COPPER, H.M_DARK_STEEL)
        fan(P, 0, 0.084, 0.040, 0.120, 0.025, blade, 9, "0")
    elif pid == "cool_copper_hp":
        tower(P, 0.100, 0.080, 0.060, 5, 34, H.M_COPPER, H.M_COPPER, H.M_COPPER)
        fan(P, 0, 0.073, 0.044, 0.092, 0.025, blade, 9, "0")
    elif pid == "cool_ducted_shroud":
        P.box((0, 0.034, -0.060), (0.258, 0.064, 0.100), hw("22262b", 0.1, 0.5), bevel=0.004)
        P.box((0, 0.034, -0.112), (0.120, 0.052, 0.040), hw("22262b", 0.1, 0.5), bevel=0.004)
        for i in range(4):
            fan(P, (i - 1.5) * 0.063, 0.034, 0.004, 0.060, 0.025, blade, 7, str(i))
        P.box((0, 0.0668, -0.060), (0.14, 0.0008, 0.04), hw("ff6a2a", 0.1, 0.5), bevel=0.0)
    elif pid == "cool_2u_active":
        P.box((0, 0.006, 0), (0.092, 0.012, 0.092), H.M_COPPER, bevel=0.0012)
        P.fins((0, 0.036, 0), (0.090, 0.048, 0.076), 26, 0, H.M_ALU, fill_ratio=0.4)
        for i in range(4):
            P.cable([((i - 1.5) * 0.02, 0.010, -0.044), ((i - 1.5) * 0.02, 0.056, -0.048), ((i - 1.5) * 0.02, 0.060, 0.0), ((i - 1.5) * 0.02, 0.056, 0.048), ((i - 1.5) * 0.02, 0.010, 0.044)], 0.0030, H.M_COPPER, seg=10)
        fan(P, 0, 0.038, 0.056, 0.070, 0.025, blade, 9, "0")
    elif pid == "cool_dual_tower":
        for s in (-1, 1):
            P.fins((0, 0.032 + 0.052, s * 0.044), (0.136, 0.104, 0.042), 42, 1, H.M_ALU, fill_ratio=0.34)
            P.box((0, 0.139, s * 0.044), (0.136, 0.004, 0.042), hw("17191d", 0.6, 0.35), bevel=0.0008)
        P.box((0, 0.005, 0), (0.046, 0.010, 0.046), H.M_COPPER, bevel=0.001)
        for i in range(6):
            x = (i - 2.5) * 0.020
            P.cable([(x, 0.138, -0.044), (x, 0.028, -0.044), (x * 0.4, 0.008, -0.016), (x * 0.4, 0.008, 0.016), (x, 0.028, 0.044), (x, 0.138, 0.044)], 0.0030, NICKEL, seg=10)
        fan(P, 0, 0.086, 0.0, 0.136, 0.025, blade, 9, "0", None)
    elif pid in ("cool_noctua", "cool_noctua_nhu14s"):
        tan, brown = hw("c9b48c", 0.02, 0.6), hw("6a4028", 0.02, 0.55)
        if pid == "cool_noctua":
            fan(P, 0, 0.062, 0, 0.120, 0.025, brown, 7, "0", None, "z", hw("1b1d20", 0.05, 0.6))
            for sx in (-1, 1):
                for sy in (-1, 1):
                    P.box((sx * 0.054, 0.062 + sy * 0.054, 0), (0.014, 0.014, 0.027), brown, bevel=0.001)
        else:
            tower(P, 0.140, 0.116, 0.044, 6, 44, H.M_ALU, NICKEL, NICKEL)
            fan(P, 0, 0.090, 0.038, 0.138, 0.025, brown, 7, "0", None, "z", tan)
    elif pid == "cool_hotswap_fans":
        for i in range(4):
            x = (i - 1.5) * 0.068
            fan(P, x, 0.036, 0, 0.062, 0.040, blade, 7, str(i))
            P.box((x, 0.072, 0.010), (0.040, 0.006, 0.014), H.M_LATCH_GREEN, bevel=0.001)
            P.box((x, 0.0025, 0), (0.064, 0.005, 0.044), H.M_STEEL, bevel=0.0004)
    elif pid == "cool_fanwall":
        for i in range(6):
            fan(P, (i - 2.5) * 0.043, 0.023, 0, 0.040, 0.056, blade, 5, str(i))
        for y in (0.001, 0.0455):
            P.box((0, y, 0), (0.264, 0.002, 0.062), H.M_DARK_STEEL, bevel=0.0003)
    elif pid == "cool_fanwall_8x":
        for i in range(8):
            fan(P, (i % 4 - 1.5) * 0.084, 0.044 + (i // 4) * 0.084, 0, 0.080, 0.038, blade, 9, str(i), led if i % 4 == 0 else None)
        for x in (-0.170, 0.170):
            P.box((x, 0.086, 0), (0.003, 0.172, 0.044), H.M_DARK_STEEL, bevel=0.0004)
        P.box((0, 0.001, 0), (0.343, 0.003, 0.044), H.M_DARK_STEEL, bevel=0.0004)
        P.box((0, 0.172, 0), (0.343, 0.003, 0.044), H.M_DARK_STEEL, bevel=0.0004)
    elif pid in ("cool_vapor_2u", "cool_vapor"):
        big = pid == "cool_vapor_2u"
        h = 0.052 if big else 0.030
        P.box((0, 0.005, 0), (0.108, 0.010, 0.078), H.M_COPPER, bevel=0.0012)
        P.fins((0, 0.010 + h / 2, 0), (0.106, h, 0.076), 34 if big else 26, 0, H.M_COPPER if big else NICKEL, fill_ratio=0.42)
        P.box((0, 0.011 + h, 0), (0.108, 0.002, 0.030), H.M_GUNMETAL, bevel=0.0005)
        P.box((0, 0.0124 + h, 0), (0.060, 0.0008, 0.016), hw("d9ab3c", 0.9, 0.25), bevel=0.0)
        for sx in (-0.047, 0.047):
            for sz in (-0.032, 0.032):
                P.cyl((sx, 0.016, sz), 0.004, 0.012, H.M_STEEL, seg=14)
    elif pid == "cool_rear_door":
        P.box((0, 0.150, 0), (0.200, 0.300, 0.030), hw("1b1e22", 0.5, 0.4), bevel=0.004)
        P.fins((0, 0.155, 0.016), (0.172, 0.250, 0.010), 44, 0, H.M_ALU, fill_ratio=0.4)
        for i in range(3):
            fan(P, 0.0, 0.066 + 0.090 * i, 0.026, 0.080, 0.018, blade, 9, str(i))
        P.box((0.090, 0.160, 0.020), (0.006, 0.060, 0.012), H.M_CHROME, bevel=0.001)
        for c, x in (("blue", -0.060), ("red", 0.060)):
            P.cable([(x, 0.300, 0), (x, 0.322, 0), (x, 0.330, -0.03)], 0.0060, TUBE[c], seg=12)
    else:
        radiators(P, p, blade, led)
    P.label("name", (0, 0.0, 0.0), 0.06, 0.012, "y")
    P.labels = []


def hose(P, pts, col, r=0.0052, flow=True):
    P.cable(pts, r, TUBE[col], seg=12, subdiv=8, group="Body")
    if flow:
        key = "Flow_%d" % len([k for k in P.order if k.startswith("Flow_")])
        P.new_group(key, (0.0, 0.0, 0.0))
        P.cable(pts, r * 1.04, hw("8fd0ff", 0.0, 0.1), seg=12, subdiv=8, group=key, uv_pitch=0.02)


def block(P, x, z, s=0.056, top=None, y=0.0):
    P.box((x, y + 0.003, z), (s, 0.006, s), H.M_COPPER, bevel=0.0008)
    P.box((x, y + 0.012, z), (s * 0.98, 0.013, s * 0.98), top or GLASS, bevel=0.0024)
    P.cyl((x, y + 0.0190, z), s * 0.34, 0.0012, hw("3aa0ff", 0.0, 0.3, 1.2), seg=36)
    for e in (-1, 1):
        P.cyl((x + e * s * 0.24, y + 0.024, z), 0.0056, 0.012, H.M_CHROME, seg=18)


def radiators(P, p, blade, led):
    pid = p["id"]
    if pid in ("cool_aio_240", "cool_aio_360", "cool_aio_liquid"):
        n = {"cool_aio_240": 2, "cool_aio_360": 3, "cool_aio_liquid": 1}[pid]
        w = 0.122 * n + 0.026
        P.box((0, 0.062, -0.030), (w, 0.124, 0.006), H.M_DARK_STEEL, bevel=0.0006)
        P.fins((0, 0.062, -0.030), (w - 0.030, 0.112, 0.026), 30 * n, 0, hw("22252a", 0.6, 0.4), fill_ratio=0.4)
        for s in (-1, 1):
            P.box((s * (w / 2 - 0.008), 0.062, -0.030), (0.016, 0.124, 0.030), H.M_DARK_STEEL, bevel=0.0012)
        for i in range(n):
            fan(P, (i - (n - 1) / 2) * 0.122, 0.062, 0.0, 0.120, 0.025, blade, 9, str(i), led)
        block(P, 0.02, 0.110, 0.060, BLACK)
        c = "black" if pid != "cool_aio_liquid" else "blue"
        hose(P, [(0.034, 0.026, 0.110), (0.060, 0.070, 0.100), (w / 2 - 0.004, 0.070, 0.030), (w / 2 - 0.006, 0.100, -0.016)], c)
        hose(P, [(0.006, 0.026, 0.110), (0.030, 0.090, 0.104), (w / 2 + 0.016, 0.050, 0.040), (w / 2 - 0.006, 0.024, -0.016)], c)
    elif pid == "cool_custom_loop":
        block(P, -0.070, 0.03, 0.064, hw("c8743c", 0.95, 0.22))
        block(P, 0.010, 0.03, 0.064, hw("c8743c", 0.95, 0.22))
        P.cyl((0.090, 0.060, -0.02), 0.030, 0.120, GLASS, seg=36)
        P.new_group("Flow_0", (0, 0, 0))
        P.cyl((0.090, 0.050, -0.02), 0.0285, 0.094, hw("8fd0ff", 0.0, 0.1), seg=36, group="Flow_0")
        for y in (0.004, 0.122):
            P.cyl((0.090, y, -0.02), 0.032, 0.010, H.M_DARK_STEEL, seg=36)
        hose(P, [(-0.054, 0.026, 0.03), (-0.050, 0.060, 0.02), (-0.014, 0.060, 0.02), (-0.006, 0.026, 0.03)], "clear")
        hose(P, [(0.026, 0.026, 0.03), (0.040, 0.070, 0.02), (0.070, 0.120, 0.0), (0.084, 0.130, -0.02)], "clear")
        hose(P, [(-0.086, 0.026, 0.03), (-0.100, 0.060, -0.02), (0.0, 0.020, -0.06), (0.070, 0.012, -0.04)], "clear")
    elif pid == "cool_cdu_inrack":
        P.box((0, 0.088, 0), (0.43, 0.176, 0.26), hw("23272c", 0.5, 0.4), bevel=0.004)
        P.box((0, 0.088, 0.131), (0.42, 0.166, 0.004), hw("2d333a", 0.4, 0.4), bevel=0.002)
        P.box((-0.12, 0.120, 0.134), (0.11, 0.060, 0.004), GLASS, bevel=0.001)
        P.box((-0.12, 0.120, 0.1364), (0.098, 0.048, 0.0008), hw("3aa0ff", 0.0, 0.2, 1.0), bevel=0.0)
        for i in range(2):
            P.cyl((0.05 + 0.10 * i, 0.070, 0.136), 0.034, 0.010, H.M_GUNMETAL, axis="z", seg=40)
            o = V((0.05 + 0.10 * i, 0.070, 0.1425))
            P.new_group("Rotor_Z_%d" % i, o)
            P.rotor(T(o), 0.028, 6, H.M_ALU, H.M_GUNMETAL, group="Rotor_Z_%d" % i, hub_ratio=0.4, depth_ratio=0.2, sweep=0.5, cap_mat=H.M_CHROME)
        hose(P, [(-0.18, 0.05, 0.13), (-0.18, 0.05, 0.19), (-0.10, 0.03, 0.22), (0.02, 0.03, 0.20)], "blue", 0.008)
        hose(P, [(-0.14, 0.04, 0.13), (-0.14, 0.04, 0.18), (-0.06, 0.015, 0.20), (0.06, 0.015, 0.18)], "red", 0.008)
    elif pid == "cool_coldplate_gpu":
        block(P, -0.08, 0, 0.060, H.M_GUNMETAL)
        P.box((0.060, 0.006, 0), (0.150, 0.012, 0.080), H.M_COPPER, bevel=0.0012)
        P.box((0.060, 0.016, 0), (0.146, 0.010, 0.076), H.M_GUNMETAL, bevel=0.0018)
        for i in range(6):
            P.box((0.010 + 0.020 * i, 0.0216, 0), (0.010, 0.0014, 0.060), NICKEL, bevel=0.0)
        hose(P, [(-0.066, 0.026, 0), (-0.05, 0.05, 0.01), (-0.02, 0.05, 0.02), (0.0, 0.026, 0.02)], "blue")
        hose(P, [(-0.094, 0.026, 0), (-0.11, 0.06, 0.01), (-0.10, 0.03, 0.07), (0.0, 0.02, 0.08)], "red")
    elif pid == "cool_two_phase":
        P.box((0, 0.005, 0), (0.120, 0.010, 0.090), H.M_COPPER, bevel=0.0012)
        P.box((0, 0.030, 0), (0.114, 0.040, 0.084), GLASS, bevel=0.004)
        P.new_group("Flow_0", (0, 0, 0))
        P.box((0, 0.022, 0), (0.106, 0.022, 0.076), hw("35c98a", 0.0, 0.1), bevel=0.001, group="Flow_0")
        for i in range(10):
            P.cyl((rnd(pid, -0.045, 0.045, 40 + i), 0.034 + rnd(pid, 0, 0.010, 60 + i), rnd(pid, -0.032, 0.032, 80 + i)), 0.0024, 0.0024, WHITE, seg=10)
        P.box((0, 0.052, 0), (0.118, 0.004, 0.088), H.M_GUNMETAL, bevel=0.001)
        hose(P, [(0.04, 0.054, 0.0), (0.05, 0.085, 0.0), (0.10, 0.085, 0.0), (0.11, 0.02, 0.0)], "green")
        hose(P, [(-0.04, 0.054, 0.0), (-0.05, 0.085, 0.0), (-0.10, 0.085, 0.0), (-0.11, 0.02, 0.0)], "green")
    else:
        for i in range(2):
            block(P, (i * 2 - 1) * 0.055, 0, 0.066, hw("d9ab3c", 0.9, 0.25))
        P.box((0, 0.012, -0.085), (0.24, 0.024, 0.030), H.M_GUNMETAL, bevel=0.002)
        P.box((0, 0.012, -0.125), (0.24, 0.024, 0.030), H.M_GUNMETAL, bevel=0.002)
        for i in range(4):
            x = (i - 1.5) * 0.054
            P.cyl((x, 0.028, -0.085), 0.007, 0.012, H.M_CHROME, seg=18)
            P.cyl((x, 0.028, -0.125), 0.007, 0.012, H.M_CHROME, seg=18)
        hose(P, [(-0.071, 0.026, 0), (-0.081, 0.060, -0.02), (-0.081, 0.050, -0.07), (-0.081, 0.034, -0.085)], "blue")
        hose(P, [(-0.039, 0.026, 0), (-0.027, 0.066, -0.03), (-0.027, 0.060, -0.10), (-0.027, 0.034, -0.125)], "red")
        hose(P, [(0.039, 0.026, 0), (0.027, 0.060, -0.02), (0.027, 0.050, -0.07), (0.027, 0.034, -0.085)], "blue")
        hose(P, [(0.071, 0.026, 0), (0.081, 0.066, -0.03), (0.081, 0.060, -0.10), (0.081, 0.034, -0.125)], "red")


def cool_mount(P, p):
    tier, pid = int(p["vtier"]), p["id"]
    frame = hw(pickv(pid, ["0c0d0f", "1c1f24", "24303f", "2a2320", "32363c"], 20), 0.1, 0.5)
    blade = pickv(pid, [H.M_BLADE_FAN, hw("6a4028", 0.02, 0.55) if "noctua" in pid else hw("3a3f46", 0.1, 0.5), hw("c9ccd1", 0.05, 0.5), hw("1d3a70", 0.05, 0.5)], 21)
    latch = hw(pickv(pid, ["299a52", "c8452e", "2f78d0", "d9a72c"], 22), 0.08, 0.38)
    if "noctua" in pid:
        blade = hw("6a4028", 0.02, 0.55)
        frame = hw("c9b48c", 0.02, 0.6)
    P.remap = {H.M_PLASTIC: frame, H.M_BLADE_FAN: blade, H.M_LATCH_GREEN: latch, H.M_DARK_STEEL: pickv(pid, [H.M_DARK_STEEL, H.M_GUNMETAL, hw("3a3f47", 0.8, 0.34)], 23)}
    if tier >= 3:
        P.remap[H.M_COPPER] = pickv(pid, [H.M_COPPER, NICKEL, hw("22252a", 0.6, 0.4)], 24)
    P.split_screws = False
    H.build_cooling(P, tier)
    P.remap = {}
    n = min(3 + tier, 5)
    sx = -(n - 1) * 0.115 / 2
    glow = hw(pickv(pid, ["3aa0ff", "28d8a0", "ff6a2a", "b84dff", "ffcc33"], 25), 0.0, 0.3, 1.6)
    if rnd(pid, 0, 1, 26) > 0.45 and tier >= 1:
        for i in range(n):
            P.ring(T((sx + i * 0.115, 0.048, 0.0196)), 0.0425, 0.0440, 0.0016, glow, seg=36)
    if tier >= 3:
        w = (n - 1) * 0.115 + 0.114 - 0.024
        tx = w / 2 + 0.008
        px = w / 2 - 0.012
        for k, pts in enumerate(([(tx, 0.070, -0.059), (tx, 0.070, -0.084), (px, 0.068, -0.086), (px, 0.050, -0.086)], [(tx, 0.026, -0.059), (tx, 0.026, -0.090), (px, 0.026, -0.086)])):
            key = "Flow_%d" % k
            P.new_group(key, (0, 0, 0))
            P.cable(pts, 0.0054, hw("8fd0ff", 0.0, 0.1), seg=12, group=key, uv_pitch=0.02)


# ---------------------------------------------------------------- Netzteile

def psu_look(p):
    n = p["name"]
    b = "standard"
    for k, key in (("Titan", "titan"), ("Platin", "platin"), ("Gold", "gold"), ("Silber", "silber"), ("Bronze", "bronze"), ("Basis", "basis")):
        if k in n:
            b = key
            break
    kind = "atx"
    if "Dual" in n or "N+1" in n:
        kind = "dual"
    elif "Redundant" in n or "Hot-Swap" in n or "Server" in n and int(p["vtier"]) >= 1:
        kind = "crps"
    elif "SFX" in n or "Kompakt" in n:
        kind = "sfx"
    return kind, b


def psu_product(P, p):
    kind, b = psu_look(p)
    pid = p["id"]
    body = hw(pickv(pid, ["1b1e22", "2a2e34", "a8adb4", "23262b", "16181c"], 1), 0.6, 0.38)
    bd = BADGE[b]
    blade = pickv(pid, [H.M_BLADE_FAN, hw("2a2d32", 0.1, 0.5), hw("c9ccd1", 0.05, 0.5)], 2)
    if kind in ("atx", "sfx"):
        w, h, d = (0.150, 0.086, 0.140 + (int(p["vtier"]) * 0.02)) if kind == "atx" else (0.125, 0.0635, 0.100)
        P.box((0, h / 2, 0), (w, h, d), body, bevel=0.0024)
        s = min(0.120 if kind == "atx" else 0.086, d * 0.90)
        P.cyl((0, h + 0.0004, 0), s * 0.49, 0.0010, H.M_CAVITY, seg=48)
        for k in range(5):
            P.ring(T((0, h + 0.0016, 0)) @ Rx(-90), s * (0.10 + 0.09 * k), s * (0.10 + 0.09 * k) + 0.0012, 0.0012, H.M_CHROME if rnd(pid, 0, 1, 3) > 0.5 else BLACK, seg=40)
        o = V((0, h - 0.006, 0))
        P.new_group("Rotor_Y_0", o + V((0, 0.0068, 0)))
        P.rotor(T(o + V((0, 0.0068, 0))) @ Rx(-90), s * 0.46, 9 if kind == "atx" else 7, blade, BLACK, group="Rotor_Y_0", hub_ratio=0.34, depth_ratio=0.06, sweep=0.6, cap_mat=bd)
        for ang in (0, 60, 120):
            P.box((0, h + 0.0018, 0), (s * 0.98, 0.0010, 0.0012), H.M_CHROME, rot=Ry(ang), bevel=0.0)
        P.box((w * 0.28, h * 0.5, -d / 2 - 0.0006), (w * 0.36, h * 0.72, 0.0012), H.M_HONEY_DARK, bevel=0.0, uv_scale=0.045)
        H._c14_inlet(P, -w * 0.28, h * 0.36, -d / 2)
        P.box((-w * 0.28, h * 0.74, -d / 2 - 0.002), (0.014, 0.014, 0.004), H.M_PLASTIC, bevel=0.0)
        P.box((-w * 0.28, h * 0.77, -d / 2 - 0.0044), (0.009, 0.006, 0.0018), H.M_GRIP_RED, bevel=0.0)
        if "Modular" in p["name"] or "Pro" in p["name"] or "Plus" in p["name"]:
            for r in range(2):
                for c in range(4):
                    P.box(((c - 1.5) * 0.030, h * (0.30 + 0.38 * r), d / 2 + 0.0008), (0.022, 0.011, 0.0020), H.M_CAVITY, bevel=0.0)
                    P.box(((c - 1.5) * 0.030, h * (0.30 + 0.38 * r), d / 2 + 0.0006), (0.025, 0.014, 0.0012), BLACK, bevel=0.0)
        else:
            for k in range(6):
                P.cable([((k - 2.5) * 0.006 - w * 0.2, h * 0.5 + (k % 2) * 0.006, d / 2 - 0.002), ((k - 2.5) * 0.006 - w * 0.2, h * 0.5, d / 2 + 0.03), ((k - 2.5) * 0.008 - w * 0.1, 0.008, d / 2 + 0.06), ((k - 2.5) * 0.008, 0.006, d / 2 + 0.09)], 0.0026, H.M_CABLE, seg=8)
            P.box((0, 0.008, d / 2 + 0.096), (0.052, 0.012, 0.020), H.M_PLASTIC, bevel=0.0006)
        for s2 in (-1, 1):
            P.box((s2 * (w / 2 + 0.0004), h * 0.52, 0), (0.0008, h * 0.62, d * 0.72), hw("101215", 0.2, 0.5), bevel=0.0)
            P.box((s2 * (w / 2 + 0.0010), h * 0.28, 0), (0.0008, h * 0.10, d * 0.72), bd, bevel=0.0)
        P.label("name", (w / 2 + 0.0016, h * 0.56, 0), d * 0.64, h * 0.34, "x")
    else:
        n = 2 if kind == "dual" else 1
        w, h, d = 0.0735, 0.040, 0.185
        if "1U" in p["name"]:
            w = 0.054
        for i in range(n):
            x = (i - (n - 1) / 2) * (w + 0.004)
            P.box((x, h / 2, 0), (w, h, d), H.M_STEEL if rnd(pid, 0, 1, 4) > 0.35 else body, bevel=0.0014, uv_scale=0.18)
            P.box((x, h + 0.0003, 0.02), (w * 0.8, 0.0006, d * 0.5), PAPER, bevel=0.0)
            P.box((x, h + 0.0006, -0.052), (w * 0.8, 0.0008, 0.012), bd, bevel=0.0)
            fz = -d / 2
            P.box((x, h / 2, fz - 0.001), (w - 0.002, h - 0.002, 0.002), H.M_DARK_STEEL, bevel=0.0)
            s = h * 0.92
            fan(P, x - w * 0.16, h / 2, fz + 0.012, s, 0.020, blade, 7, str(i))
            for k in (0.3, 0.7, 0.98):
                P.ring(T((x - w * 0.16, h / 2, fz - 0.0022)), s * 0.47 * k, s * 0.47 * k + 0.0010, 0.0010, H.M_CHROME, seg=28)
            P.cable([(x + w * 0.22, h * 0.2, fz), (x + w * 0.22, h * 0.2, fz - 0.018), (x + w * 0.22, h * 0.8, fz - 0.018), (x + w * 0.22, h * 0.8, fz)], 0.0022, H.M_DARK_STEEL, seg=10)
            P.box((x + w * 0.38, h * 0.5, fz - 0.004), (0.008, 0.016, 0.008), hw(pickv(pid, ["299a52", "c8452e", "2f78d0", "d9772c"], 5), 0.08, 0.38), bevel=0.0008)
            P.cyl((x + w * 0.34, h * 0.86, fz - 0.0014), 0.0016, 0.0012, hw("28d8a0", 0.0, 0.3, 2.0), axis="z", seg=12)
            P.box((x, h * 0.35, d / 2 + 0.006), (w * 0.7, 0.0030, 0.012), PCB["green"], bevel=0.0)
            for k in range(10):
                P.box((x + (k - 4.5) * w * 0.064, h * 0.35 + 0.0017, d / 2 + 0.007), (w * 0.045, 0.0004, 0.009), H.M_GOLD, bevel=0.0)
        if n == 2:
            tw = 2 * w + 0.016
            for s2 in (-1, 1):
                P.box((s2 * tw / 2, h / 2, 0.01), (0.002, h + 0.004, d - 0.03), H.M_STEEL, bevel=0.0003)
            P.box((0, -0.001, 0.01), (tw, 0.002, d - 0.03), H.M_STEEL, bevel=0.0003)
        P.label("name", ((-(n - 1) / 2) * (w + 0.004), h + 0.0010, 0.02), w * 0.72, d * 0.42, "y")


def psu_mount(P, p):
    tier, pid = int(p["vtier"]), p["id"]
    kind, b = psu_look(p)
    P.remap = {H.M_STEEL: pickv(pid, [H.M_STEEL, hw("2a2e34", 0.6, 0.38), hw("a8adb4", 0.8, 0.32), H.M_STEEL], 10),
               H.M_PSU_LBL_STD: hw(pickv(pid, ["101215", "f2f1ec", "1a2330"], 11), 0.1, 0.5), H.M_PSU_LBL_PRO: hw(pickv(pid, ["101215", "1a2330", "f2f1ec"], 12), 0.1, 0.5),
               H.M_LATCH_GREEN: hw(pickv(pid, ["299a52", "c8452e", "2f78d0", "d9772c"], 5), 0.08, 0.38)}
    H.build_psu(P, tier)
    P.remap = {}
    bd = BADGE[b]
    if tier >= 2:
        for u in range(2):
            x = -0.034 + u * 0.068
            P.box((x, 0.0962, 0.050), (0.052, 0.0012, 0.010), bd, bevel=0.0)
            P.box((x, 0.0962, 0.153), (0.052, 0.0012, 0.004), bd, bevel=0.0)
        P.label("name", (-0.034, 0.0966, 0.105), 0.080, 0.040, "y", None, 90)
    else:
        P.box((0, 0.0950, 0.054), (0.108, 0.0012, 0.008), bd, bevel=0.0)
        P.label("name", (0, 0.0955, 0.098), 0.100, 0.056, "y")


# ---------------------------------------------------------------- Ablauf

PRODUCT = {"cpu": cpu_product, "ram": ram_product, "gpu": gpu_product, "storage": sto_product, "cooling": cool_product, "psu": psu_product}
MOUNT = {"cpu": cpu_mount, "ram": ram_mount, "gpu": gpu_mount, "storage": sto_mount, "cooling": cool_mount, "psu": psu_mount}


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    cat = json.load(open(args[0], encoding="utf8"))
    only = set(args[1:])
    H.get_material = A.plain_material
    total = 0
    n = 0
    for c in cat:
        for i, p in enumerate(cat[c]):
            p["i"] = i
            if only and p["id"] not in only and c not in only:
                continue
            for kind, table, prefix in (("P", PRODUCT, "hw_"), ("M", MOUNT, "hwm_")):
                H.clear_scene()
                q = P2()
                res = table[c](q, p)
                if res is False:
                    continue
                faces, size = q.write(prefix + p["id"])
                total += size
                n += 1
                print("TEIL %s%s %d Flaechen %d KB" % (prefix, p["id"], faces, size // 1024))
    print("TEILE FERTIG %d Dateien %.1f MB" % (n, total / 1048576.0))


if __name__ == "__main__":
    main()
