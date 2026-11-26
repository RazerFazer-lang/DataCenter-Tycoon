"""Zerlegt die Server-Bauteile aus build_hardware_parts.py in einzeln greifbare Teile fuer die Werkbank.

Aufruf:
    blender --background --factory-startup --python-exit-code 1 --python tools/blender/build_assembly_parts.py

Jede Datei asm_*.glb enthaelt benannte Objekte (z. B. "CPU", "Cooler", "Screw_0", "Stick_3", "Latch_2_0").
Der Objekt-Ursprung ist der Drehpunkt bzw. die Auflageflaeche; die Lage im Bauteil bleibt als Node-Position erhalten.

Die Dateien enthalten KEINE Texturen: WorkbenchPiece uebernimmt die PBR_*-Materialien zur Laufzeit aus den
vorhandenen part_*.glb. So waechst das Spiel nur um die Geometrie.
"""

import os
import sys
import traceback

import bpy
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import build_hardware_parts as H
import dct_paths

OUT_DIR = dct_paths.MODELS_DIR
C_INV = H.C.inverted()


def plain_material(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    if name in H.SOLID_MATS:
        return _orig_get_material(name)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    return mat


_orig_get_material = H.get_material


class SplitPart(H.Part):
    """Wie Part, verteilt die Geometrie aber auf frei waehlbare Gruppen (self.cur bzw. self.pick)."""

    def __init__(self):
        super().__init__()
        self.cur = None       # feste Gruppe, solange gesetzt (z. B. innerhalb einer Schraube)
        self.pick = None      # Funktion (info) -> Gruppenname
        self.idx = 0
        self.pivots = {}      # Gruppe -> Drehpunkt in Godot-Koordinaten
        self.dropped = set()
        self._info = {}
        self._screw_n = 0

    def _add(self, t, M, mat, group):
        if group == "Body":
            info = dict(self._info)
            info["idx"] = self.idx
            info["mat"] = mat
            info["center"] = M.translation
            group = self.cur if self.cur is not None else (self.pick(info) if self.pick else "Body")
        self.idx += 1
        if group not in self.groups:
            self.new_group(group, (0.0, 0.0, 0.0))
        super()._add(t, M, mat, group)

    def _with(self, kind, M, fn):
        # Nur der aeusserste Aufruf zaehlt (fins -> box, screw_head -> cyl).
        outer = "kind" not in self._info
        if outer:
            self._info = {"kind": kind, "M": M}
        try:
            fn()
        finally:
            if outer:
                self._info = {}

    def box(self, pos, size, mat, M=None, **kw):
        self._with("box", M, lambda: super(SplitPart, self).box(pos, size, mat, M, **kw))

    def cyl(self, pos, r, h, mat, M=None, **kw):
        self._with("cyl", M, lambda: super(SplitPart, self).cyl(pos, r, h, mat, M, **kw))

    def cable(self, pts, r, mat, M=None, **kw):
        self._with("cable", M, lambda: super(SplitPart, self).cable(pts, r, mat, M, **kw))

    def ring(self, M, r_in, r_out, depth, mat, **kw):
        self._with("ring", M, lambda: super(SplitPart, self).ring(M, r_in, r_out, depth, mat, **kw))

    def rotor(self, M, *a, **kw):
        self._with("rotor", M, lambda: super(SplitPart, self).rotor(M, *a, **kw))

    def fins(self, center, size, count, axis, mat, M=None, **kw):
        self._with("fins", M, lambda: super(SplitPart, self).fins(center, size, count, axis, mat, M, **kw))

    def screw_head(self, pos, r=0.0038, h=0.0022, mat=H.M_CHROME, M=None, axis="y", group="Body"):
        if self.cur is not None or not getattr(self, "split_screws", False):
            super().screw_head(pos, r=r, h=h, mat=mat, M=M, axis=axis, group=group)
            return
        self.cur = "Screw_%d" % self._screw_n
        self._screw_n += 1
        try:
            super().screw_head(pos, r=r, h=h, mat=mat, M=M, axis=axis, group=group)
        finally:
            self.cur = None

    def export_split(self, path):
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
                # Vom Generator selbst angelegte Gruppe (Rotor_*, Cable_*): Ursprung bleibt.
                origin = H.C @ g["origin"]
            else:
                if key in self.pivots:
                    origin = H.C @ Vector(self.pivots[key])
                else:
                    xs = [v.co for v in bm.verts]
                    lo = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
                    hi = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
                    # Mitte der Grundflaeche (Blender-Z ist Godot-Y)
                    origin = Vector(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, lo.z))
                for v in bm.verts:
                    v.co -= origin
            ngons = [f for f in bm.faces if len(f.verts) > 4]
            if ngons:
                H.bmesh.ops.triangulate(bm, faces=ngons)
            me = bpy.data.meshes.new(key)
            bm.to_mesh(me)
            bm.free()
            for name in g["mats"]:
                me.materials.append(plain_material(name))
            ob = bpy.data.objects.new(key, me)
            ob.location = origin
            bpy.context.scene.collection.objects.link(ob)
        bpy.ops.export_scene.gltf(
            filepath=path,
            export_format="GLB",
            export_yup=True,
            export_apply=True,
            export_normals=True,
            export_tangents=False,
            export_image_format="NONE",
        )
        return faces, names


# ---------------------------------------------------------------------------
# Zerlegung der einzelnen Kategorien
# ---------------------------------------------------------------------------

def split_mainboard(P, build):
    P.split_screws = True

    def pick(i):
        if i.get("kind") == "cyl" and i["mat"] == H.M_GOLD and i["center"].y < 0.0:
            return "Standoffs"
        return "Board"

    P.pick = pick
    build(P)


def split_cpu(P, build, broken):
    real = H._captive_screw
    counter = [0]

    def captive(p, x, y, z):
        p.cur = "Screw_%d" % counter[0]
        counter[0] += 1
        try:
            real(p, x, y, z)
        finally:
            p.cur = None

    def pick(i):
        n = i["idx"]
        if broken:
            return "Socket" if n < 5 else ("CPU" if n < 8 else "Cooler")
        if n < 6 or n in (41, 43):
            return "Socket"
        if n < 37:
            return "CPU"
        if n < 41:
            return "Frame"
        if n == 42:
            return "Lever"
        return "Cooler"

    if not broken:
        # Orientierungsmarken: goldenes Dreieck auf der CPU und an der passenden Sockelecke
        P.cur = "CPU"
        P.cyl((-0.0385, 0.0102, 0.0385), 0.0060, 0.0014, H.M_LED_AMBER, seg=3)
        P.cyl((-0.0225, 0.0153, 0.0225), 0.0085, 0.0006, H.M_LED_AMBER, seg=3)
        P.cur = "Socket"
        P.cyl((-0.0600, 0.0068, 0.0600), 0.0095, 0.0024, H.M_LED_AMBER, seg=3)
        P.cur = None
        P.idx = 0
    P.pick = pick
    P.pivots = {"Lever": (0.056, 0.0055, -0.054), "Frame": (-0.054, 0.0052, 0.0)}
    H._captive_screw = captive
    try:
        build(P)
    finally:
        H._captive_screw = real
    if broken:
        P.dropped.add("Socket")


def split_ram(P, build, broken):
    real = H._dimm_latch

    def latch(p, x, z, closed):
        i = round((x + 0.063) / 0.018)
        key = "Latch_%d_%d" % (i, 0 if z < 0.0 else 1)
        p.cur = key
        p.pivots[key] = (x, 0.003, z)
        try:
            real(p, x, z, True)
        finally:
            p.cur = None

    def pick(i):
        m = i.get("M")
        if m is None:
            return "Slots"
        return "Stick_%d" % max(0, min(7, round((m.translation.x + 0.063) / 0.018)))

    P.pick = pick
    H._dimm_latch = latch
    try:
        build(P)
    finally:
        H._dimm_latch = real
    if broken:
        for k in list(P.order):
            if k not in ("Stick_2", "Stick_3"):
                P.dropped.add(k)


def split_gpu(P, build, broken):
    real = H._pcie_slot

    def slot(p, x, *a, **kw):
        p.cur = "Slot_%d" % round(x / 0.056)
        try:
            real(p, x, *a, **kw)
        finally:
            p.cur = None

    def pick(i):
        m = i.get("M")
        if m is None:
            return "Bridge"
        return "Card_%d" % (1 if m.translation.x > 0.045 else 0)

    P.pick = pick
    H._pcie_slot = slot
    try:
        build(P)
    finally:
        H._pcie_slot = real
    if broken:
        P.dropped.add("Slot_0")


def split_storage(P, build, broken):
    P.split_screws = not broken

    def pick(i):
        m = i.get("M")
        z = m.translation.z if m is not None else i["center"].z
        n = max(0, min(2, round((z + 0.032) / 0.034)))
        if i["mat"] in (H.M_PLASTIC, H.M_CAVITY):
            return "Slots"
        if i.get("kind") == "cyl" and i["mat"] == H.M_GOLD:
            return "Slots"
        return "SSD_%d" % n

    P.pick = pick
    build(P)
    if broken:
        for k in list(P.order):
            if k != "SSD_0":
                P.dropped.add(k)


# ---------------------------------------------------------------------------
# Deckel, Werkzeuge, Stecker, Kleinteile
# ---------------------------------------------------------------------------

def build_lid(P):
    P.cur = "Lid"
    P.pivots["Lid"] = (0.0, 0.0, 0.0)
    P.box((0.0, 0.0, 0.0), (0.750, 0.0020, 0.640), H.M_STEEL, bevel=0.0, uv_scale=0.22)
    # Hohe Haube: PCIe-Stecker und Kabelbogen brauchen Platz ueber dem 132-mm-Blech.
    for sx in (-0.3745, 0.3745):
        P.box((sx, -0.0115, 0.0), (0.0018, 0.023, 0.640), H.M_STEEL, bevel=0.0, uv_scale=0.22)
    P.box((0.0, -0.0115, -0.3205), (0.750, 0.023, 0.0018), H.M_STEEL, bevel=0.0, uv_scale=0.22)
    P.box((0.0, -0.0115, 0.3195), (0.750, 0.023, 0.0018), H.M_STEEL, bevel=0.0, uv_scale=0.22)
    # Praegungen und Entriegelung
    for z in (-0.20, 0.02, 0.22):
        P.box((0.0, 0.0012, z), (0.56, 0.0010, 0.012), H.M_STEEL, bevel=0.0003)
    P.box((0.0, 0.0016, -0.262), (0.150, 0.0012, 0.052), H.M_DARK_STEEL, bevel=0.0004)
    P.box((0.0, 0.0054, -0.262), (0.110, 0.0065, 0.024), H.M_LATCH_GREEN, bevel=0.0012)
    P.box((0.21, 0.0012, -0.262), (0.110, 0.0004, 0.052), H.M_PAPER, bevel=0.0)
    for k in range(4):
        P.box((0.21, 0.0016, -0.278 + k * 0.011), (0.090 - 0.012 * (k % 2), 0.0002, 0.0026), H.M_IC, bevel=0.0)


def build_tools(P):
    # Schraubendreher: Spitze im Ursprung, Griff nach oben
    P.cur = "Screwdriver"
    P.pivots["Screwdriver"] = (0.0, 0.0, 0.0)
    P.cyl((0.0, 0.0030, 0.0), 0.0008, 0.0060, H.M_CHROME, seg=12, r2=0.0022)
    P.cyl((0.0, 0.0560, 0.0), 0.0024, 0.1000, H.M_CHROME, seg=16)
    P.cyl((0.0, 0.1090, 0.0), 0.0052, 0.0080, H.M_DARK_STEEL, seg=18)
    P.cyl((0.0, 0.1175, 0.0), 0.0070, 0.0100, H.M_PLASTIC, seg=20, r2=0.0110)
    P.cyl((0.0, 0.1510, 0.0), 0.0112, 0.0580, H.M_GRIP_RED, seg=20)
    for k in range(6):
        a = k * H.math.pi / 3.0
        P.box((0.0108 * H.math.cos(a), 0.1500, 0.0108 * H.math.sin(a)), (0.0030, 0.0500, 0.0030), H.M_RUBBER,
              rot=H.Ry(-k * 60.0), bevel=0.0006)
    P.cyl((0.0, 0.1830, 0.0), 0.0102, 0.0070, H.M_PLASTIC, seg=20, r2=0.0080)
    P.cyl((0.0, 0.1875, 0.0), 0.0072, 0.0030, H.M_CHROME, seg=20)

    # Waermeleitpaste-Spritze: Spitze im Ursprung
    P.cur = "Syringe"
    P.pivots["Syringe"] = (0.0, 0.0, 0.0)
    P.cyl((0.0, 0.0080, 0.0), 0.0011, 0.0160, H.M_PLASTIC_GREY, seg=12, r2=0.0020)
    P.cyl((0.0, 0.0190, 0.0), 0.0030, 0.0070, H.M_PLASTIC, seg=14, r2=0.0068)
    P.cyl((0.0, 0.0560, 0.0), 0.0070, 0.0680, H.M_SYRINGE, seg=20)
    P.box((0.0, 0.0560, 0.0071), (0.0090, 0.0400, 0.0006), H.M_PAPER, bevel=0.0)
    P.box((0.0, 0.0620, 0.0075), (0.0070, 0.0100, 0.0004), H.M_USB_BLUE, bevel=0.0)
    P.box((0.0, 0.0905, 0.0), (0.0240, 0.0026, 0.0120), H.M_PLASTIC, bevel=0.0006)
    P.cyl((0.0, 0.1120, 0.0), 0.0030, 0.0420, H.M_PLASTIC_GREY, seg=12)
    P.cyl((0.0, 0.1340, 0.0), 0.0078, 0.0026, H.M_PLASTIC_GREY, seg=18)

    # Akkuschrauber: Bitspitze im Ursprung, Griff nach oben/hinten
    P.cur = "PowerDriver"
    P.pivots["PowerDriver"] = (0.0, 0.0, 0.0)
    P.cyl((0.0, 0.0040, 0.0), 0.0008, 0.0080, H.M_CHROME, seg=12, r2=0.0024)
    P.cyl((0.0, 0.0180, 0.0), 0.0030, 0.0220, H.M_CHROME, seg=6)
    P.cyl((0.0, 0.0380, 0.0), 0.0078, 0.0200, H.M_DARK_STEEL, seg=20, r2=0.0110)
    P.cyl((0.0, 0.0560, 0.0), 0.0130, 0.0180, H.M_LED_AMBER, seg=24)
    P.cyl((0.0, 0.0900, 0.0), 0.0190, 0.0520, H.M_PLASTIC, seg=28)
    P.cyl((0.0, 0.0900, 0.0), 0.0196, 0.0120, H.M_GRIP_RED, seg=28)
    P.cyl((0.0, 0.1200, 0.0), 0.0180, 0.0100, H.M_RUBBER, seg=28, r2=0.0120)
    P.box((0.0, 0.0960, 0.0480), (0.0260, 0.0320, 0.0780), H.M_PLASTIC, rot=H.Rx(-8.0), bevel=0.0060)
    P.box((0.0, 0.0960, 0.0480), (0.0268, 0.0180, 0.0520), H.M_RUBBER, rot=H.Rx(-8.0), bevel=0.0050)
    P.box((0.0, 0.1000, 0.0980), (0.0400, 0.0560, 0.0300), H.M_GUNMETAL, bevel=0.0050)
    P.box((0.0, 0.0720, 0.0220), (0.0100, 0.0120, 0.0120), H.M_GRIP_RED, bevel=0.0020)
    P.box((0.0205, 0.1000, 0.0980), (0.0010, 0.0300, 0.0180), H.M_PAPER, bevel=0.0)

    # Dosierpistole fuer Waermeleitpaste
    P.cur = "PasteGun"
    P.pivots["PasteGun"] = (0.0, 0.0, 0.0)
    P.cyl((0.0, 0.0100, 0.0), 0.0012, 0.0200, H.M_PLASTIC_GREY, seg=12, r2=0.0024)
    P.cyl((0.0, 0.0240, 0.0), 0.0040, 0.0100, H.M_PLASTIC, seg=16, r2=0.0090)
    P.cyl((0.0, 0.0640, 0.0), 0.0100, 0.0700, H.M_SYRINGE, seg=24)
    P.cyl((0.0, 0.1080, 0.0), 0.0125, 0.0200, H.M_USB_BLUE, seg=24)
    P.box((0.0, 0.1080, 0.0320), (0.0180, 0.0220, 0.0600), H.M_PLASTIC, rot=H.Rx(-10.0), bevel=0.0050)
    P.box((0.0, 0.0860, 0.0240), (0.0080, 0.0160, 0.0120), H.M_GRIP_RED, bevel=0.0020)
    P.cyl((0.0, 0.1400, 0.0), 0.0034, 0.0480, H.M_CHROME, seg=12)

    # Antistatik-Pinzette: Spitzen im Ursprung
    P.cur = "Tweezers"
    P.pivots["Tweezers"] = (0.0, 0.0, 0.0)
    for s in (-1.0, 1.0):
        P.box((s * 0.0016, 0.0200, 0.0), (0.0012, 0.0400, 0.0022), H.M_CHROME, rot=H.Rz(s * -2.2), bevel=0.0)
        P.box((s * 0.0050, 0.0720, 0.0), (0.0014, 0.0680, 0.0080), H.M_DARK_STEEL, rot=H.Rz(s * -3.4), bevel=0.0)
        P.box((s * 0.0052, 0.0680, 0.0), (0.0020, 0.0300, 0.0086), H.M_RUBBER, rot=H.Rz(s * -3.4), bevel=0.0004)
    P.box((0.0, 0.1090, 0.0), (0.0120, 0.0100, 0.0080), H.M_DARK_STEEL, bevel=0.0010)

    # Werkzeugeinsatz (Schaumstoff in flacher Schale)
    P.cur = "ToolTray"
    P.pivots["ToolTray"] = (0.0, 0.0, 0.0)
    P.box((0.0, 0.0030, 0.0), (0.150, 0.0060, 0.270), H.M_DARK_STEEL, bevel=0.0012)
    P.box((0.0, 0.0080, 0.0), (0.140, 0.0060, 0.260), H.M_RUBBER, bevel=0.0012)
    for x in (-0.045, 0.0, 0.045):
        P.box((x, 0.0108, 0.0), (0.026, 0.0006, 0.215), H.M_CAVITY, bevel=0.0)

    # Schraube M3: Unterseite des Kopfes im Ursprung, Gewinde nach unten
    P.cur = "ScrewM3"
    P.pivots["ScrewM3"] = (0.0, 0.0, 0.0)
    H.Part.screw_head(P, (0.0, 0.0016, 0.0), r=0.0052, h=0.0032, mat=H.M_CHROME)
    P.cyl((0.0, -0.0040, 0.0), 0.0024, 0.0080, H.M_STEEL, seg=12)

    # Stecker: Unterseite im Ursprung
    def plug(key, sx, sy, sz, rows_x, rows_z, pitch):
        P.cur = key
        P.pivots[key] = (0.0, 0.0, 0.0)
        P.box((0.0, sy * 0.5, 0.0), (sx, sy, sz), H.M_PLASTIC, bevel=0.0008)
        P.box((sx * 0.5 + 0.0012, sy * 0.45, 0.0), (0.0024, sy * 0.8, min(0.016, sz * 0.5)), H.M_PLASTIC_GREY, bevel=0.0)
        for a in range(rows_x):
            for b in range(rows_z):
                px = (a - (rows_x - 1) * 0.5) * pitch
                pz = (b - (rows_z - 1) * 0.5) * pitch
                P.cyl((px, sy + 0.0016, pz), pitch * 0.30, 0.0034, H.M_RUBBER, seg=8)

    plug("PlugATX", 0.0170, 0.0150, 0.0900, 2, 12, 0.0072)
    plug("PlugEPS", 0.0210, 0.0140, 0.0120, 4, 2, 0.0050)
    plug("PlugPCIE", 0.0110, 0.0130, 0.0215, 2, 4, 0.0050)
    plug("PlugPWM", 0.0110, 0.0090, 0.0060, 4, 1, 0.0026)

    # Pruefanschluss vorn, Stecker des Pruefkabels, Einschalter (Vorderseite = +Y im Ursprung)
    P.cur = "DiagPort"
    P.pivots["DiagPort"] = (0.0, 0.0, 0.0)
    P.box((0.0, 0.0006, 0.0), (0.030, 0.0040, 0.046), H.M_GUNMETAL, bevel=0.0008)
    P.box((0.0, 0.0030, -0.006), (0.018, 0.0016, 0.020), H.M_USB_BLUE, bevel=0.0004)
    P.box((0.0, 0.0039, -0.006), (0.012, 0.0006, 0.014), H.M_CAVITY, bevel=0.0)
    P.cyl((0.0, 0.0034, 0.014), 0.0026, 0.0020, H.M_LED_BLUE, seg=12)

    P.cur = "PlugDiag"
    P.pivots["PlugDiag"] = (0.0, 0.0, 0.0)
    P.box((0.0, 0.0030, -0.006), (0.012, 0.0060, 0.014), H.M_CHROME, bevel=0.0004)
    P.box((0.0, 0.0180, -0.006), (0.020, 0.0250, 0.022), H.M_USB_BLUE, bevel=0.0020)
    for k in range(3):
        P.box((0.0, 0.0130 + k * 0.0050, -0.006), (0.0210, 0.0016, 0.0230), H.M_RUBBER, bevel=0.0)
    P.cyl((0.0, 0.0340, -0.006), 0.0044, 0.0080, H.M_RUBBER, seg=12)

    P.cur = "PowerButton"
    P.pivots["PowerButton"] = (0.0, 0.0, 0.0)
    P.box((0.0, 0.0006, 0.0), (0.030, 0.0040, 0.046), H.M_GUNMETAL, bevel=0.0008)
    P.cyl((0.0, 0.0030, 0.006), 0.0092, 0.0030, H.M_CHROME, seg=24)
    P.cyl((0.0, 0.0042, 0.006), 0.0076, 0.0034, H.M_PLASTIC, seg=24)
    P.box((0.0, 0.0060, 0.0036), (0.0012, 0.0004, 0.0050), H.M_PAPER, bevel=0.0)

    # Multimeter (liegt, Anzeige nach oben) und Pruefspitzen (Spitzen im Ursprung)
    P.cur = "Multimeter"
    P.pivots["Multimeter"] = (0.0, 0.0, 0.0)
    P.box((0.0, 0.0150, 0.0), (0.084, 0.0300, 0.160), H.M_LATCH_AMBER if hasattr(H, "M_LATCH_AMBER") else H.M_GRIP_RED, bevel=0.0050)
    P.box((0.0, 0.0305, 0.0), (0.070, 0.0030, 0.146), H.M_PLASTIC, bevel=0.0010)
    P.box((0.0, 0.0324, -0.044), (0.058, 0.0012, 0.038), H.M_PLASTIC_GREY, bevel=0.0)
    P.cyl((0.0, 0.0350, 0.022), 0.0180, 0.0070, H.M_PLASTIC_GREY, seg=28)
    P.box((0.0, 0.0392, 0.016), (0.0040, 0.0020, 0.0220), H.M_PAPER, bevel=0.0)
    for x, m in ((-0.018, H.M_CAVITY), (0.0, H.M_CAVITY), (0.018, H.M_GRIP_RED)):
        P.cyl((x, 0.0330, 0.060), 0.0058, 0.0030, m, seg=16)

    P.cur = "Probes"
    P.pivots["Probes"] = (0.0, 0.0, 0.0)
    for s, m in ((-1.0, H.M_RUBBER), (1.0, H.M_GRIP_RED)):
        mm = H.T((s * 0.0030, 0.0, 0.0)) @ H.Rz(s * -14.0)
        P.cyl((0.0, 0.0090, 0.0), 0.0005, 0.0180, H.M_CHROME, mm, seg=10, r2=0.0011)
        P.cyl((0.0, 0.0200, 0.0), 0.0040, 0.0050, m, mm, seg=14)
        P.cyl((0.0, 0.0640, 0.0), 0.0044, 0.0860, m, mm, seg=14)
        P.cyl((0.0, 0.1120, 0.0), 0.0028, 0.0120, m, mm, seg=10)

    # Haltewinkel fuer das Netzteil (mit zwei Schraubloechern)
    P.cur = "PsuBracket"
    P.pivots["PsuBracket"] = (0.0, 0.0, 0.0)
    P.box((0.0, 0.0012, 0.0), (0.126, 0.0024, 0.022), H.M_STEEL, bevel=0.0)
    P.box((0.0, 0.0090, -0.0105), (0.126, 0.0180, 0.0018), H.M_STEEL, bevel=0.0)
    for x in (-0.046, 0.046):
        P.cyl((x, 0.0026, 0.001), 0.0036, 0.0006, H.M_CAVITY, seg=14)

    # Platine des Netzwerk-Switch (fuer dessen Reparatur)
    P.cur = "SwitchBoard"
    P.pivots["SwitchBoard"] = (0.0, 0.0, 0.0)
    P.box((0.0, 0.0030, 0.0), (0.64, 0.0036, 0.46), H.M_PCB_SUB_G, bevel=0.0)
    P.box((0.0, 0.0120, 0.02), (0.14, 0.0140, 0.14), H.M_IC, bevel=0.0010)
    P.fins((0.0, 0.0300, 0.02), (0.136, 0.0240, 0.136), 12, 0, H.M_ALU)
    for k in range(6):
        P.box((-0.24 + k * 0.096, 0.0080, 0.16), (0.040, 0.0080, 0.032), H.M_IC, bevel=0.0006)
        P.cyl((-0.25 + k * 0.030, 0.0120, -0.18), 0.0060, 0.0150, H.M_ALU, seg=14)
    P.cur = None


JOBS = []
for _name, _mat in (("asm_mainboard", H.M_MB_GREEN), ("asm_mainboard_ai", H.M_MB_BLACK)):
    JOBS.append((_name, lambda P, m=_mat: split_mainboard(P, lambda p: H.build_mainboard(p, m))))
for _name, _ai in (("asm_mainboard_broken", False), ("asm_mainboard_ai_broken", True)):
    JOBS.append((_name, lambda P, a=_ai: split_mainboard(P, lambda p: H.build_mainboard_broken(p, a))))
for _t in range(4):
    JOBS.append(("asm_cpu_t%d" % _t, lambda P, t=_t: split_cpu(P, lambda p: H.build_cpu(p, t), False)))
    JOBS.append(("asm_ram_t%d" % _t, lambda P, t=_t: split_ram(P, lambda p: H.build_ram(p, t), False)))
    JOBS.append(("asm_storage_t%d" % _t, lambda P, t=_t: split_storage(P, lambda p: H.build_storage(p, t), False)))
    if _t > 0:
        JOBS.append(("asm_gpu_t%d" % _t, lambda P, t=_t: split_gpu(P, lambda p: H.build_gpu(p, t), False)))
JOBS += [
    ("asm_cpu_broken", lambda P: split_cpu(P, H.build_cpu_broken, True)),
    ("asm_ram_broken", lambda P: split_ram(P, H.build_ram_broken, True)),
    ("asm_gpu_broken", lambda P: split_gpu(P, H.build_gpu_broken, True)),
    ("asm_storage_broken", lambda P: split_storage(P, H.build_storage_broken, True)),
    ("asm_lid", build_lid),
    ("asm_tools", build_tools),
]


def main():
    H.get_material = plain_material
    for name, build in JOBS:
        H.clear_scene()
        P = SplitPart()
        P.split_screws = False
        build(P)
        faces, names = P.export_split(os.path.join(OUT_DIR, name + ".glb"))
        print("ASM %s: %d Flaechen | %s" % (name, faces, ", ".join(names)))
    print("ASM DONE: %d Dateien" % len(JOBS))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
