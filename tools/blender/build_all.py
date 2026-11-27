"""Baut alle aktuellen Blender-Modelle mit einem Befehl (Roadmap TEC-06).

    tools\\blender\\build_all.ps1 [Optionen]
    blender -b --factory-startup --python tools/blender/build_all.py -- [Optionen]

Jeder Generator laeuft in einem eigenen, frischen Blender-Prozess (--factory-startup) in der festen
Reihenfolge von GENERATORS. Danach folgen Vorschaubilder, ein Kontaktbogen je Generator und ein
Vergleich mit assets/models. Optionen, Ausgabeordner und Fallen: tools/blender/README.md.
"""
import argparse
import ast
import hashlib
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import time

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
ASSETS_MODELS = os.path.join(ROOT, "assets", "models")
ASSETS_TEXTURES = os.path.join(ROOT, "assets", "textures")
REPO_CACHE = os.path.join(HERE, "_pbr_cache")
DEFAULT_SIDE = os.path.join(HERE, "_build")
CATALOG_GD = os.path.join(ROOT, "scripts", "data", "hardware_catalog.gd")


class Gen:
    def __init__(self, name, scripts=None, note="", post=False, catalog=False, needs=None):
        self.name = name
        self.scripts = scripts or [name + ".py"]
        self.note = note
        self.post = post          # bearbeitet Dateien eines frueheren Generators nach
        self.catalog = catalog    # bekommt die Bauteilliste aus hardware_catalog.gd als JSON
        self.needs = needs        # laeuft nur, wenn dieser Generator im selben Lauf dabei ist


# Feste Reihenfolge. Spaetere Generatoren ueberschreiben gleichnamige Dateien frueherer.
GENERATORS = [
    Gen("build_racks", note="rack, rack_pro (+ dct_racks.blend)"),
    Gen("build_utilities", scripts=["build_utilities.py", "export_models.py"],
        note="Sicherungskasten, Sicherungen, Feuerloescher, Router t0-t4, ups, hall_c_subpanel"),
    Gen("build_desk", note="terminal_desk"),
    Gen("build_hardware_parts", note="part_* und prop_workbench"),
    Gen("build_assembly_parts", note="asm_* (Werkbank-Einzelteile)"),
    Gen("build_parts_d", catalog=True, note="hw_*/hwm_* je Katalog-Bauteil"),
    Gen("build_workshop_models", note="workshop_workbench, repair_kit_case, bulk_pack_crate, delivery_build_box"),
    Gen("build_decor_props", note="halle_nord_stocked_shelf; seine 6 decor_* ueberschreibt build_paket_c"),
    Gen("build_paket_a", note="carton_*, paper_bin, power_strip, lan_strip, ups_small/cabinet/container"),
    Gen("build_paket_c", note="Regale, euro_pallet, decor_*"),
    Gen("build_delivery_c", note="deliver_van/truck/heavy, forklift, pallet_jack, sack_truck"),
    Gen("build_own_hall_and_props", note="own_hall_*, garage_door_panel_*, hall_c_subpanel_*, ..."),
    Gen("cut_back_door", post=True, needs="build_own_hall_and_props", note="schneidet die Hintertuer in own_hall_interior/exterior"),
    Gen("build_halle_nord", note="halle_nord_* (7 Modelle)"),
    Gen("build_halle_nord_interior", note="halle_nord_interior"),
    Gen("build_exterior_world", note="ext_* Gebaeude, Hecke, Gras, Strassen-Props"),
    Gen("build_exterior_vehicles", note="ext_car_*"),
    Gen("build_living_horizon", note="Windrad, Mast, Kran, Kraftwerk, ext_forklift, Fahnenmast, Auflieger"),
    Gen("build_human", note="human"),
    Gen("build_nature_d", note="Baeume, Buesche, Voegel, Tiere (+ Blatt-Texturen)"),
    Gen("build_outdoor_d", note="Spind, Tor, Tuer, Garten, Lampen, Pflanzen"),
    Gen("build_gameplay_g", note="decor_diesel_gen (Notstromaggregat, GAME-01)"),
]

# Nicht in der Liste, mit Grund (Regel: aktuell ist, was heute in assets/models liegt).
EXCLUDED = {
    "build_delivery_van.py": "nur noch Hilfsbibliothek (delivery_van.glb nutzt das Spiel nicht mehr)",
    "build_strip_props.py": "ueberholt: power_strip/lan_strip kommen aus build_paket_a.py",
    "build_player.py": "player.glb gibt es seit v3.0.0 nicht mehr (Figuren: build_human.py)",
    "build_characters.py": "player.glb/delivery_driver.glb gibt es seit v3.0.0 nicht mehr",
    "build_fp_arms.py": "fp_arms.glb liegt nicht mehr in assets/models",
    "build_fp_hand.py": "fp_hand.glb liegt nicht mehr in assets/models",
    "build_routers.py": "Modul von build_utilities.py",
    "build_hall_c.py": "Modul von build_utilities.py",
    "export_models.py": "laeuft zusammen mit build_utilities.py",
    "build_all.py": "dieses Skript",
}

BG = (0.20, 0.21, 0.23)
SHEET_MAX = 64          # Modelle je Kontaktbogen-Seite
PAIRS_MAX = 120         # alt/neu-Paare im Vergleichsbogen


def log(msg=""):
    print(msg, flush=True)


def same_path(a, b):
    return os.path.normcase(os.path.abspath(a)) == os.path.normcase(os.path.abspath(b))


def rel(path, base):
    try:
        return os.path.relpath(path, base).replace("\\", "/")
    except ValueError:
        return path


# ---------------------------------------------------------------- glb lesen (ohne Blender)

def glb_json(path):
    with open(path, "rb") as f:
        magic, _ver, _length, clen, ctype = struct.unpack("<IIIII", f.read(20))
        if magic != 0x46546C67 or ctype != 0x4E4F534A:
            raise ValueError("kein glb")
        return json.loads(f.read(clen).decode("utf8"))


def _glb_bin(path):
    data = open(path, "rb").read()
    off = 12
    while off + 8 <= len(data):
        clen, ctype = struct.unpack("<II", data[off:off + 8])
        if ctype == 0x004E4942:
            return data[off + 8:off + 8 + clen]
        off += 8 + clen
    return b""


_FILE_HASH = {}


def image_hashes(path, js):
    """(Name, sha1[:10]) je Bild. Verweise nach textures/shared tragen den Hash schon im Dateinamen."""
    res, data = [], None
    for i, im in enumerate(js.get("images", [])):
        name = im.get("name") or "bild%d" % i
        h = "?"
        if "uri" in im:
            m = re.search(r"_([0-9a-f]{10})\.[A-Za-z]+$", im["uri"])
            if m:
                h = m.group(1)
            else:
                f = os.path.normpath(os.path.join(os.path.dirname(path), im["uri"]))
                if f not in _FILE_HASH and os.path.isfile(f):
                    _FILE_HASH[f] = sha1(f)[:10]
                h = _FILE_HASH.get(f, "fehlt")
        elif "bufferView" in im:
            if data is None:
                data = _glb_bin(path)
            bv = js["bufferViews"][im["bufferView"]]
            o = bv.get("byteOffset", 0)
            h = hashlib.sha1(data[o:o + bv["byteLength"]]).hexdigest()[:10]
        res.append((name, h))
    return sorted(res)


def _local_matrix(n):
    if "matrix" in n:
        return np.array(n["matrix"], dtype=np.float64).reshape(4, 4).T
    t = n.get("translation", (0, 0, 0))
    x, y, z, w = n.get("rotation", (0, 0, 0, 1))
    s = n.get("scale", (1, 1, 1))
    r = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])
    m = np.identity(4)
    m[:3, :3] = r * np.array(s)
    m[:3, 3] = t
    return m


def glb_stats(path):
    js = glb_json(path)
    nodes = js.get("nodes", [])
    meshes = js.get("meshes", [])
    acc = js.get("accessors", [])
    st = {
        "size": os.path.getsize(path), "nodes": len(nodes), "meshes": len(meshes),
        "materials": len(js.get("materials", [])), "images": len(js.get("images", [])),
        "skins": len(js.get("skins", [])), "mesh_nodes": 0, "prims": 0, "verts": 0, "tris": 0,
        "node_names": sorted(n.get("name", "") for n in nodes),
        "mat_names": sorted(m.get("name", "") for m in js.get("materials", [])),
        "bbox": None, "img_hashes": image_hashes(path, js),
    }
    children = {c for n in nodes for c in n.get("children", [])}
    scene = (js.get("scenes") or [{}])[js.get("scene", 0)] if js.get("scenes") else {}
    roots = scene.get("nodes") or [i for i in range(len(nodes)) if i not in children]
    lo = np.full(3, np.inf)
    hi = np.full(3, -np.inf)
    stack = [(i, np.identity(4)) for i in roots]
    while stack:
        i, parent = stack.pop()
        n = nodes[i]
        mw = parent @ _local_matrix(n)
        if "mesh" in n:
            st["mesh_nodes"] += 1
            for p in meshes[n["mesh"]].get("primitives", []):
                st["prims"] += 1
                pa = acc[p["attributes"]["POSITION"]]
                st["verts"] += pa["count"]
                st["tris"] += (acc[p["indices"]]["count"] if "indices" in p else pa["count"]) // 3
                if "min" in pa and "max" in pa:
                    a, b = pa["min"], pa["max"]
                    for cx in (a[0], b[0]):
                        for cy in (a[1], b[1]):
                            for cz in (a[2], b[2]):
                                w = mw @ np.array((cx, cy, cz, 1.0))
                                lo = np.minimum(lo, w[:3])
                                hi = np.maximum(hi, w[:3])
        stack.extend((c, mw) for c in n.get("children", []))
    if np.isfinite(lo).all():
        st["bbox"] = [[round(float(v), 4) for v in lo], [round(float(v), 4) for v in hi]]
    return st


def compare_stats(old, new):
    """Liefert (Stufe, Gruende). Stufe: gleich | leicht | deutlich."""
    reasons = []
    strong = False

    def pct(a, b):
        return (b - a) * 100.0 / a if a else (100.0 if b else 0.0)

    for key, label in (("verts", "Vertices"), ("tris", "Dreiecke")):
        if old[key] != new[key]:
            p = pct(old[key], new[key])
            reasons.append("%s %d -> %d (%+.1f %%)" % (label, old[key], new[key], p))
            strong = strong or abs(p) > 1.0
    for key, label in (("nodes", "Knoten"), ("mesh_nodes", "Mesh-Knoten"), ("prims", "Primitive"),
                       ("materials", "Materialien"), ("images", "Bilder"), ("skins", "Skins")):
        if old[key] != new[key]:
            reasons.append("%s %d -> %d" % (label, old[key], new[key]))
            strong = strong or key in ("nodes", "mesh_nodes", "materials", "skins")
    so, sn = set(old["node_names"]), set(new["node_names"])
    if so != sn:
        miss, add = sorted(so - sn), sorted(sn - so)
        if miss:
            reasons.append("Knoten fehlen: " + ", ".join(miss[:6]) + (" ..." if len(miss) > 6 else ""))
        if add:
            reasons.append("neue Knoten: " + ", ".join(add[:6]) + (" ..." if len(add) > 6 else ""))
        strong = True
    mo, mn = set(old["mat_names"]), set(new["mat_names"])
    if mo != mn:
        reasons.append("Materialnamen anders (%d fehlen, %d neu)" % (len(mo - mn), len(mn - mo)))
    if old["bbox"] and new["bbox"]:
        d = max(abs(a - b) for i in range(2) for a, b in zip(old["bbox"][i], new["bbox"][i]))
        if d > 0.001:
            reasons.append("BBox-Abweichung %.3f m" % d)
            strong = strong or d > 0.01
    elif old["bbox"] != new["bbox"]:
        reasons.append("BBox nur in einer Fassung")
        strong = True
    if old["images"] == new["images"] and old["img_hashes"] != new["img_hashes"]:
        ho, hn = dict(old["img_hashes"]), dict(new["img_hashes"])
        diff = sorted(k for k in set(ho) | set(hn) if ho.get(k) != hn.get(k))
        reasons.append("Bildinhalt anders: " + ", ".join(diff[:5]) + (" ..." if len(diff) > 5 else ""))
    sp = pct(old["size"], new["size"])
    if abs(sp) > 5.0:
        reasons.append("Groesse %.0f -> %.0f KB (%+.0f %%)" % (old["size"] / 1024.0, new["size"] / 1024.0, sp))
    if not reasons:
        return "gleich", reasons
    return ("deutlich" if strong else "leicht"), reasons


# ---------------------------------------------------------------- Bauteilliste fuer build_parts_d

def _strip_gd(src):
    """Entfernt #-Kommentare ausserhalb von Strings und uebersetzt true/false/null."""
    out, i, q = [], 0, None
    while i < len(src):
        c = src[i]
        if q:
            out.append(c)
            if c == "\\" and i + 1 < len(src):
                out.append(src[i + 1])
                i += 1
            elif c == q:
                q = None
        elif c in "\"'":
            q = c
            out.append(c)
        elif c == "#":
            while i < len(src) and src[i] != "\n":
                i += 1
            continue
        else:
            out.append(c)
        i += 1
    text = "".join(out)
    parts = re.split(r'("(?:\\.|[^"\\])*")', text)
    for k in range(0, len(parts), 2):
        parts[k] = re.sub(r"\btrue\b", "True", re.sub(r"\bfalse\b", "False", re.sub(r"\bnull\b", "None", parts[k])))
    return "".join(parts)


def write_catalog(path):
    src = open(CATALOG_GD, encoding="utf8").read()
    m = re.search(r"^const PARTS\s*:?=\s*\{", src, re.M)
    if not m:
        raise RuntimeError("const PARTS nicht gefunden in " + CATALOG_GD)
    end = re.search(r"^\}", src[m.end():], re.M)
    body = "{" + src[m.end():m.end() + end.start()] + "}"
    parts = ast.literal_eval(_strip_gd(body))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf8") as f:
        json.dump(parts, f, ensure_ascii=False, indent=1)
    return sum(len(v) for v in parts.values())


# ---------------------------------------------------------------- Vorschau-Worker (eigener Blender-Prozess)

def _scene(w, h, note, font):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    world = bpy.data.worlds.new("Vorschau")
    world.color = BG
    sc.world = world
    r = sc.render
    r.engine = "BLENDER_WORKBENCH"
    r.resolution_x, r.resolution_y, r.resolution_percentage = w, h, 100
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_cavity = True
    sh.show_shadows = False
    r.use_stamp = True
    for a in dir(r):
        if a.startswith("use_stamp_"):
            try:
                setattr(r, a, False)
            except (AttributeError, TypeError):
                pass
    r.use_stamp_note = True
    r.stamp_note_text = note
    r.stamp_font_size = font
    r.stamp_foreground = (1.0, 1.0, 1.0, 1.0)
    r.stamp_background = (0.0, 0.0, 0.0, 0.7)
    cam_data = bpy.data.cameras.new("Vorschau")
    cam_data.lens_unit = "FOV"
    cam_data.angle = math.radians(30.0)
    cam = bpy.data.objects.new("Vorschau", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc


def _render(sc, png):
    os.makedirs(os.path.dirname(png), exist_ok=True)
    sc.render.filepath = png
    bpy.ops.render.render(write_still=True)


def render_glb(glb, png, label, size):
    sc = _scene(size, size, label, max(11, size // 20))
    bpy.ops.import_scene.gltf(filepath=glb)
    dg = bpy.context.evaluated_depsgraph_get()
    lo = np.full(3, np.inf)
    hi = np.full(3, -np.inf)
    for ob in sc.objects:
        if ob.type not in {"MESH", "CURVE", "FONT", "SURFACE"} or not ob.visible_get():
            continue  # z. B. Knochenform "Icosphere" des glTF-Imports
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        n = len(me.vertices) if me else 0
        if n:
            co = np.empty(n * 3, dtype=np.float32)
            me.vertices.foreach_get("co", co)
            mw = np.array(ev.matrix_world, dtype=np.float64)
            co = co.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3]
            lo = np.minimum(lo, co.min(axis=0))
            hi = np.maximum(hi, co.max(axis=0))
        ev.to_mesh_clear()
    if not np.isfinite(lo).all():
        sc.render.stamp_note_text = label + " (ohne Geometrie)"
        lo, hi = np.zeros(3) - 0.5, np.zeros(3) + 0.5
    center = Vector(((lo + hi) * 0.5).tolist())
    radius = max(float(np.linalg.norm(hi - lo)) * 0.5, 0.005)
    cam = sc.camera
    cam_data = cam.data
    dist = radius / math.sin(cam_data.angle * 0.5) * 1.03
    cam.location = center + Vector((0.55, -1.0, 0.6)).normalized() * dist
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam_data.clip_start = max((dist - radius) * 0.5, 0.0005)
    cam_data.clip_end = dist + radius * 2.0
    _render(sc, png)


def run_worker(job_path):
    job = json.load(open(job_path, encoding="utf8"))
    size = job["size"]
    errors = {}
    for it in job.get("items", []):
        try:
            render_glb(it["glb"], it["png"], it["label"], size)
        except Exception as exc:  # noqa: BLE001 - Vorschau darf den Lauf nicht stoppen
            errors[it["png"]] = "%s: %s" % (type(exc).__name__, exc)
            try:
                _render(_scene(size, size, "FEHLER " + it["label"], max(11, size // 20)), it["png"])
            except Exception:  # noqa: BLE001
                pass
    for hd in job.get("headers", []):
        try:
            _render(_scene(hd["width"], hd["height"], hd["text"], hd["font"]), hd["png"])
        except Exception as exc:  # noqa: BLE001
            errors[hd["png"]] = "%s: %s" % (type(exc).__name__, exc)
    with open(job_path + ".result.json", "w", encoding="utf8") as f:
        json.dump({"errors": errors}, f, indent=1)


# ---------------------------------------------------------------- Kontaktboegen (im Hauptprozess)

def load_png(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    return np.flipud(a.reshape(h, w, 4))


def save_png(path, arr):
    h, w = arr.shape[:2]
    img = bpy.data.images.new("Bogen", w, h, alpha=False)
    img.pixels.foreach_set(np.ascontiguousarray(np.flipud(arr)).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def compose_sheet(tiles, cols, tile, header, out_png, pad=4):
    rows = max(1, math.ceil(len(tiles) / cols))
    hh = 0
    head = None
    if header and os.path.isfile(header):
        head = load_png(header)
        hh = head.shape[0]
    width = cols * tile + (cols + 1) * pad
    height = hh + rows * tile + (rows + 1) * pad
    canvas = np.empty((height, width, 4), dtype=np.float32)
    canvas[...] = (0.12, 0.12, 0.13, 1.0)
    if head is not None:
        canvas[:hh, :min(width, head.shape[1])] = head[:, :width]
    for i, t in enumerate(tiles):
        if not t or not os.path.isfile(t):
            continue
        im = load_png(t)
        r, c = divmod(i, cols)
        y = hh + pad + r * (tile + pad)
        x = pad + c * (tile + pad)
        th, tw = min(tile, im.shape[0]), min(tile, im.shape[1])
        canvas[y:y + th, x:x + tw] = im[:th, :tw]
    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    save_png(out_png, canvas)


# ---------------------------------------------------------------- Hauptablauf

def parse_args(argv):
    ap = argparse.ArgumentParser(prog="build_all", description="Baut alle aktuellen Blender-Modelle.")
    ap.add_argument("--out", default=ASSETS_MODELS, help="Zielordner der .glb (Standard: assets/models)")
    ap.add_argument("--only", default="", help="nur diese Generatoren, z. B. build_desk,build_racks")
    ap.add_argument("--no-previews", action="store_true", help="keine Vorschaubilder")
    ap.add_argument("--clean", action="store_true", help="alte .glb im Zielordner vorher loeschen (nicht fuer assets/models)")
    ap.add_argument("--fresh-cache", action="store_true", help="mit leerem PBR-Cache starten (nur mit --out)")
    ap.add_argument("--jobs", type=int, default=4, help="parallele Blender-Prozesse fuer Vorschaubilder")
    ap.add_argument("--size", type=int, default=256, help="Kantenlaenge eines Vorschaubilds in Pixel")
    ap.add_argument("--timeout", type=float, default=60.0, help="Minuten je Generator")
    ap.add_argument("--list", action="store_true", help="Generatorliste zeigen und beenden")
    ap.add_argument("--worker", default="", help=argparse.SUPPRESS)
    return ap.parse_args(argv)


def unlisted_scripts():
    known = {g.name + ".py" for g in GENERATORS} | set(EXCLUDED)
    return sorted(f for f in os.listdir(HERE) if f.startswith("build_") and f.endswith(".py") and f not in known)


def print_list():
    log("Generatoren (Reihenfolge):")
    for i, g in enumerate(GENERATORS, 1):
        log("  %2d. %-26s %s" % (i, g.name, g.note))
    log("Nicht in der Liste:")
    for f, why in EXCLUDED.items():
        log("      %-26s %s" % (f, why))
    for f in unlisted_scripts():
        log("      %-26s UNBEKANNT - bitte in GENERATORS oder EXCLUDED eintragen" % f)


def snapshot(folder, pattern=".glb", recursive=False):
    res = {}
    if not os.path.isdir(folder):
        return res
    if recursive:
        for base, _dirs, files in os.walk(folder):
            for f in files:
                p = os.path.join(base, f)
                st = os.stat(p)
                res[rel(p, folder)] = (st.st_mtime_ns, st.st_size)
    else:
        for f in os.listdir(folder):
            if f.lower().endswith(pattern):
                st = os.stat(os.path.join(folder, f))
                res[f] = (st.st_mtime_ns, st.st_size)
    return res


def sha1(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run_generator(g, idx, total, ctx):
    blender = bpy.app.binary_path
    cmd = [blender, "-b", "--factory-startup", "--python-exit-code", "1",
           "--python-expr", "import sys; sys.dont_write_bytecode = True"]
    for s in g.scripts:
        cmd += ["--python", os.path.join(HERE, s)]
    if g.catalog:
        cmd += ["--", ctx["catalog"]]
    log_path = os.path.join(ctx["logs"], g.name + ".log")
    before = snapshot(ctx["out"])
    tex_before = snapshot(ctx["tex_dir"], recursive=True)
    log("[%2d/%d] %-26s ..." % (idx, total, g.name))
    t0 = time.time()
    status, detail = "ok", ""
    if g.catalog and not ctx.get("catalog_ok"):
        status, detail = "FEHLER", "Bauteilliste fehlt: " + ctx.get("catalog_err", "?")
        code = None
    else:
        with open(log_path, "w", encoding="utf8", errors="replace") as lf:
            lf.write("# " + subprocess.list2cmdline(cmd) + "\n")
            lf.flush()
            try:
                code = subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT, env=ctx["env"], cwd=ROOT,
                                      timeout=ctx["timeout"]).returncode
            except subprocess.TimeoutExpired:
                code = None
                status, detail = "FEHLER", "Zeitlimit ueberschritten"
    secs = time.time() - t0
    after = snapshot(ctx["out"])
    written = sorted(n for n, v in after.items() if before.get(n) != v)
    tex_after = snapshot(ctx["tex_dir"], recursive=True)
    textures = sorted(n for n, v in tex_after.items() if tex_before.get(n) != v)
    text = open(log_path, encoding="utf8", errors="replace").read() if os.path.isfile(log_path) else ""
    tracebacks = text.count("Traceback (most recent call last)")
    if status == "ok":
        if code != 0:
            status, detail = "FEHLER", "Exit-Code %s" % code
        elif not written:
            status, detail = "FEHLER", "keine .glb geschrieben"
    if status != "ok" and text:
        tail = [ln for ln in text.splitlines() if ln.strip()][-6:]
        detail += " | " + " / ".join(t.strip()[:160] for t in tail)
    res = {"name": g.name, "status": status, "detail": detail, "secs": secs, "written": written,
           "textures": textures, "log": log_path, "tracebacks": tracebacks, "post": g.post, "note": g.note}
    msg = "       %s  %.1f s, %d Modell(e)" % (status, secs, len(written))
    if textures:
        msg += ", %d Textur(en)" % len(textures)
    if tracebacks and status == "ok":
        msg += ", WARNUNG: %d Traceback(s) im Log" % tracebacks
    log(msg)
    if written:
        shown = ", ".join(n[:-4] for n in written[:12])
        log("       " + shown + (" ... (+%d)" % (len(written) - 12) if len(written) > 12 else ""))
    if status != "ok":
        log("       " + detail[:600])
        log("       Log: " + log_path)
    return res


def run_previews(items, headers, ctx):
    """Verteilt die Bilder auf mehrere Blender-Prozesse."""
    jobs = max(1, min(ctx["jobs"], len(items) or 1))
    chunks = [items[i::jobs] for i in range(jobs)]
    work = os.path.join(ctx["side_build"], "previews")
    os.makedirs(work, exist_ok=True)
    procs = []
    for i, ch in enumerate(chunks):
        jp = os.path.join(work, "job_%d.json" % i)
        with open(jp, "w", encoding="utf8") as f:
            json.dump({"size": ctx["size"], "items": ch, "headers": headers if i == 0 else []}, f)
        lp = open(os.path.join(work, "job_%d.log" % i), "w", encoding="utf8", errors="replace")
        cmd = [bpy.app.binary_path, "-b", "--factory-startup", "--python-exit-code", "1",
               "--python", os.path.abspath(__file__), "--", "--worker", jp]
        procs.append((subprocess.Popen(cmd, stdout=lp, stderr=subprocess.STDOUT, env=ctx["env"], cwd=ROOT), lp, jp))
    errors = {}
    for p, lp, jp in procs:
        try:
            p.wait(timeout=ctx["timeout"] * 2)
        except subprocess.TimeoutExpired:
            p.kill()
            errors[jp] = "Zeitlimit"
        lp.close()
        rp = jp + ".result.json"
        if os.path.isfile(rp):
            errors.update(json.load(open(rp, encoding="utf8"))["errors"])
        elif p.returncode != 0:
            errors[jp] = "Worker Exit-Code %s" % p.returncode
    return errors


def main(argv):
    a = parse_args(argv)
    if a.worker:
        run_worker(a.worker)
        return 0
    if a.list:
        print_list()
        return 0

    t_start = time.time()
    out = os.path.abspath(a.out)
    default_mode = same_path(out, ASSETS_MODELS)
    side = DEFAULT_SIDE if default_mode else out
    side_build = DEFAULT_SIDE if default_mode else os.path.join(out, "_build")
    previews_dir = os.path.join(side, "_previews")
    report_path = os.path.join(side, "_report.md")
    logs = os.path.join(side_build, "logs")
    os.makedirs(out, exist_ok=True)
    os.makedirs(logs, exist_ok=True)

    names = [n.strip().removesuffix(".py") for n in a.only.split(",") if n.strip()]
    known = {g.name: g for g in GENERATORS}
    unknown = [n for n in names if n not in known]
    if unknown:
        log("Unbekannte Generatoren: %s (Liste: --list)" % ", ".join(unknown))
        return 2
    selected = [g for g in GENERATORS if not names or g.name in names]
    partial = bool(names)

    env = dict(os.environ)
    env["DCT_MODELS_OUT"] = out
    if default_mode:
        tex_dir = env.get("DCT_TEXTURES_OUT") or ASSETS_TEXTURES
        cache_dir = env.get("DCT_PBR_CACHE") or REPO_CACHE
        work_dir = env.get("DCT_WORK_OUT") or HERE
    else:
        tex_dir = os.path.join(side_build, "textures")
        cache_dir = os.path.join(side_build, "pbr_cache")
        work_dir = os.path.join(side_build, "work")
        env.update(DCT_TEXTURES_OUT=tex_dir, DCT_PBR_CACHE=cache_dir, DCT_WORK_OUT=work_dir)
        for d in (tex_dir, cache_dir, work_dir):
            os.makedirs(d, exist_ok=True)

    log("Modell-Build: %d Generator(en), Blender %s" % (len(selected), bpy.app.version_string))
    log("  Modelle   : " + out)
    log("  Texturen  : " + tex_dir)
    log("  PBR-Cache : " + cache_dir)
    log("  Nebenbei  : " + work_dir)
    log("  Bericht   : " + report_path)
    if default_mode:
        log("  ACHTUNG: Ziel ist assets/models, vorhandene Modelle werden ueberschrieben.")
    for f in unlisted_scripts():
        log("  WARNUNG: %s steht weder in GENERATORS noch in EXCLUDED." % f)

    if a.clean:
        if default_mode:
            log("--clean ist fuer assets/models gesperrt.")
            return 2
        removed = 0
        for f in os.listdir(out):
            if f.lower().endswith(".glb"):
                os.remove(os.path.join(out, f))
                removed += 1
        log("  %d alte .glb im Zielordner geloescht." % removed)

    if not default_mode:
        if a.fresh_cache:
            log("  PBR-Cache startet leer (--fresh-cache).")
        else:
            copied = 0
            for f in os.listdir(REPO_CACHE):
                src, dst = os.path.join(REPO_CACHE, f), os.path.join(cache_dir, f)
                if os.path.isfile(src) and not os.path.exists(dst):
                    shutil.copy2(src, dst)
                    copied += 1
            log("  PBR-Cache aus tools/blender/_pbr_cache vorbelegt (%d Dateien kopiert)." % copied)

    # Referenz vor dem Bau einlesen (im Standardmodus werden die Dateien gleich ueberschrieben)
    ref = {}
    for f in sorted(os.listdir(ASSETS_MODELS)):
        if f.lower().endswith(".glb"):
            try:
                ref[f[:-4]] = glb_stats(os.path.join(ASSETS_MODELS, f))
            except Exception as exc:  # noqa: BLE001
                log("  Referenz %s nicht lesbar: %s" % (f, exc))

    ctx = {"out": out, "logs": logs, "env": env, "timeout": a.timeout * 60.0, "tex_dir": tex_dir,
           "side_build": side_build, "jobs": a.jobs, "size": a.size}
    if any(g.catalog for g in selected):
        ctx["catalog"] = os.path.join(work_dir if not default_mode else side_build, "hardware_catalog.json")
        try:
            n = write_catalog(ctx["catalog"])
            ctx["catalog_ok"] = True
            log("  Bauteilliste: %d Teile aus scripts/data/hardware_catalog.gd -> %s" % (n, ctx["catalog"]))
        except Exception as exc:  # noqa: BLE001
            ctx["catalog_err"] = "%s: %s" % (type(exc).__name__, exc)
            log("  Bauteilliste FEHLER: " + ctx["catalog_err"])

    log("")
    results = []
    t_build = time.time()
    sel_names = {g.name for g in selected}
    for i, g in enumerate(selected, 1):
        if g.needs and g.needs not in sel_names:
            log("[%2d/%d] %-26s uebersprungen (braucht %s im selben Lauf)" % (i, len(selected), g.name, g.needs))
            results.append({"name": g.name, "status": "uebersprungen", "detail": "braucht " + g.needs,
                            "secs": 0.0, "written": [], "textures": [], "log": os.path.join(logs, g.name + ".log"),
                            "tracebacks": 0, "post": g.post, "note": g.note})
            continue
        results.append(run_generator(g, i, len(selected), ctx))
    build_secs = time.time() - t_build

    # Wer hat welche Datei zuletzt geschrieben?
    owner, overwritten = {}, []
    for r in results:
        for f in r["written"]:
            name = f[:-4]
            if name in owner and not r["post"] and owner[name] != r["name"]:
                overwritten.append((name, owner[name], r["name"]))
            if not r["post"] or name not in owner:
                owner[name] = r["name"]
    post_touched = {f[:-4]: r["name"] for r in results if r["post"] for f in r["written"]}
    produced = {}
    for name in sorted(owner):
        try:
            produced[name] = glb_stats(os.path.join(out, name + ".glb"))
        except Exception as exc:  # noqa: BLE001
            log("  %s.glb nicht lesbar: %s" % (name, exc))
    stale = sorted(f[:-4] for f in os.listdir(out) if f.lower().endswith(".glb") and f[:-4] not in owner)

    # Vergleich
    cmp = {}
    for name, st in produced.items():
        if name in ref:
            cmp[name] = compare_stats(ref[name], st)
    only_new = sorted(n for n in produced if n not in ref)
    only_ref = sorted(n for n in ref if n not in produced) if not partial else []

    # Vorschaubilder
    preview_errors, sheets, pair_sheets = {}, [], []
    t_prev = time.time()
    if not a.no_previews and produced:
        if os.path.isdir(previews_dir):
            shutil.rmtree(previews_dir)
        thumbs = os.path.join(previews_dir, "_einzeln")
        size = a.size
        items = [{"glb": os.path.join(out, n + ".glb"), "png": os.path.join(thumbs, "neu", n + ".png"), "label": n}
                 for n in produced]
        pairs = [n for n, (lvl, _r) in sorted(cmp.items(), key=lambda kv: (kv[1][0] != "deutlich", kv[0]))
                 if lvl != "gleich" and any(not x.startswith("Groesse") for x in cmp[n][1])]
        pairs = pairs[:PAIRS_MAX] if not default_mode else []
        items += [{"glb": os.path.join(ASSETS_MODELS, n + ".glb"), "png": os.path.join(thumbs, "alt", n + ".png"),
                   "label": "alt: " + n} for n in pairs]
        # Seiten der Kontaktboegen planen
        by_gen = {}
        for n in produced:
            by_gen.setdefault(owner[n], []).append(n)
        headers, plan = [], []
        pad = 4
        for r in results:
            names_g = by_gen.get(r["name"], [])
            if not names_g:
                continue
            pages = [names_g[i:i + SHEET_MAX] for i in range(0, len(names_g), SHEET_MAX)]
            for pi, page in enumerate(pages, 1):
                cols = min(8, max(4, len(page)))
                width = cols * size + (cols + 1) * pad
                suffix = "" if len(pages) == 1 else "_%d" % pi
                hp = os.path.join(previews_dir, "_einzeln", "kopf", r["name"] + suffix + ".png")
                text = "%s  -  %d Modell(e)%s" % (r["name"], len(names_g),
                                                  "  -  Seite %d/%d" % (pi, len(pages)) if len(pages) > 1 else "")
                headers.append({"png": hp, "text": text, "width": width, "height": 34, "font": 18})
                plan.append((os.path.join(previews_dir, r["name"] + suffix + ".png"),
                             [os.path.join(thumbs, "neu", n + ".png") for n in page], cols, hp))
        pair_pages = [pairs[i:i + 24] for i in range(0, len(pairs), 24)]
        for pi, page in enumerate(pair_pages, 1):
            suffix = "" if len(pair_pages) == 1 else "_%d" % pi
            width = 6 * size + 7 * pad
            hp = os.path.join(previews_dir, "_einzeln", "kopf", "_vergleich" + suffix + ".png")
            headers.append({"png": hp, "text": "Vergleich alt (assets/models) | neu  -  %d Modell(e)%s" % (
                len(pairs), "  -  Seite %d/%d" % (pi, len(pair_pages)) if len(pair_pages) > 1 else ""),
                "width": width, "height": 34, "font": 18})
            tiles = []
            for n in page:
                tiles += [os.path.join(thumbs, "alt", n + ".png"), os.path.join(thumbs, "neu", n + ".png")]
            plan.append((os.path.join(previews_dir, "_vergleich" + suffix + ".png"), tiles, 6, hp))
        log("")
        log("Vorschau: %d Bilder in %d Prozessen ..." % (len(items), max(1, min(a.jobs, len(items)))))
        preview_errors = run_previews(items, headers, ctx)
        for out_png, tiles, cols, hp in plan:
            try:
                compose_sheet(tiles, cols, size, hp, out_png, pad)
                (pair_sheets if os.path.basename(out_png).startswith("_vergleich") else sheets).append(out_png)
            except Exception as exc:  # noqa: BLE001
                preview_errors[out_png] = "%s: %s" % (type(exc).__name__, exc)
        log("Vorschau fertig: %d Kontaktboegen, %d Vergleichsboegen, %d Fehler (%.0f s)" % (
            len(sheets), len(pair_sheets), len(preview_errors), time.time() - t_prev))
    prev_secs = time.time() - t_prev

    # Texturen und Cache (nur bei umgeleiteter Ausgabe vergleichbar)
    tex_cmp, cache_cmp = None, None
    if not default_mode:
        tex_cmp = {"gleich": [], "anders": [], "neu": []}
        for relp in sorted(snapshot(tex_dir, recursive=True)):
            ap = os.path.join(ASSETS_TEXTURES, relp)
            if not os.path.isfile(ap):
                tex_cmp["neu"].append(relp)
            else:
                tex_cmp["gleich" if sha1(ap) == sha1(os.path.join(tex_dir, relp)) else "anders"].append(relp)
        cache_cmp = {"gleich": 0, "anders": [], "neu": []}
        for f in sorted(os.listdir(cache_dir)):
            rp = os.path.join(REPO_CACHE, f)
            if not os.path.isfile(rp):
                cache_cmp["neu"].append(f)
            elif os.path.getsize(rp) == os.path.getsize(os.path.join(cache_dir, f)) and \
                    sha1(rp) == sha1(os.path.join(cache_dir, f)):
                cache_cmp["gleich"] += 1
            else:
                cache_cmp["anders"].append(f)

    failed = [r for r in results if r["status"] == "FEHLER"]
    total_secs = time.time() - t_start
    write_report(report_path, {
        "out": out, "default_mode": default_mode, "partial": partial, "results": results, "owner": owner,
        "overwritten": overwritten, "post_touched": post_touched, "produced": produced, "ref": ref, "cmp": cmp,
        "only_new": only_new, "only_ref": only_ref, "stale": stale, "sheets": sheets, "pair_sheets": pair_sheets,
        "preview_errors": preview_errors, "tex_cmp": tex_cmp, "cache_cmp": cache_cmp, "tex_dir": tex_dir,
        "cache_dir": cache_dir, "work_dir": work_dir, "build_secs": build_secs, "prev_secs": prev_secs,
        "total_secs": total_secs, "side": side, "no_previews": a.no_previews,
    })

    counts = {"gleich": 0, "leicht": 0, "deutlich": 0}
    for lvl, _r in cmp.values():
        counts[lvl] += 1
    log("")
    log("Fertig in %.1f min: %d/%d Generatoren ok, %d Modelle gebaut." % (
        total_secs / 60.0, sum(r["status"] == "ok" for r in results), len(results), len(produced)))
    log("Vergleich mit assets/models: %d gleich, %d leicht abweichend, %d deutlich abweichend, "
        "%d nur neu, %d nur in assets." % (counts["gleich"], counts["leicht"], counts["deutlich"], len(only_new),
                                          len(only_ref)))
    for r in failed:
        log("  FEHLER %s: %s" % (r["name"], r["detail"][:300]))
    log("Bericht: " + report_path)
    if sheets:
        log("Kontaktboegen: " + previews_dir)
    if default_mode:
        log("Danach: node tools/dedupe_glb_textures.js und godot --headless --path . -s res://tools/build_merge_cache.gd")
    return 1 if failed else 0


def _fmt_kb(n):
    return "%.0f" % (n / 1024.0)


def _bbox_txt(b):
    if not b:
        return "-"
    return "%.2f x %.2f x %.2f" % tuple(b[1][i] - b[0][i] for i in range(3))


def write_report(path, d):
    side = d["side"]
    L = []
    w = L.append
    w("# Modell-Build %s" % time.strftime("%Y-%m-%d %H:%M"))
    w("")
    w("- Ausgabe: `%s`%s" % (d["out"], " (assets/models, Dateien ueberschrieben)" if d["default_mode"] else ""))
    w("- Vergleich mit: `assets/models` (Stand vor dem Lauf)")
    w("- Blender %s, Dauer gesamt %.1f min (Bauen %.1f min, Vorschau %.1f min)" % (
        bpy.app.version_string, d["total_secs"] / 60, d["build_secs"] / 60, d["prev_secs"] / 60))
    w("- Texturen: `%s`, PBR-Cache: `%s`, Nebenprodukte: `%s`" % (d["tex_dir"], d["cache_dir"], d["work_dir"]))
    if d["partial"]:
        w("- Teil-Lauf (--only): Liste 'nur in assets' entfaellt.")
    w("")
    w("## Generatoren")
    w("")
    w("| # | Generator | Status | Zeit | Modelle | Hinweis |")
    w("|---|---|---|---|---|---|")
    for i, r in enumerate(d["results"], 1):
        hint = r["detail"] if r["status"] != "ok" else ""
        if r["tracebacks"] and r["status"] == "ok":
            hint = "%d Traceback(s) im Log" % r["tracebacks"]
        if r["textures"]:
            hint = (hint + "; " if hint else "") + "%d Textur(en)" % len(r["textures"])
        w("| %d | %s | %s | %.0f s | %d | %s |" % (i, r["name"], r["status"], r["secs"], len(r["written"]),
                                                  hint.replace("|", "/")[:400]))
    w("")
    w("Logs: `%s`" % rel(os.path.dirname(d["results"][0]["log"]), side) if d["results"] else "")
    w("")
    if d["overwritten"]:
        w("Von einem spaeteren Generator ueberschrieben (der letzte gilt):")
        w("")
        for name, first, last in d["overwritten"]:
            w("- `%s`: %s -> **%s**" % (name, first, last))
        w("")
    if d["post_touched"]:
        w("Nachbearbeitet: " + ", ".join("`%s` (%s)" % kv for kv in sorted(d["post_touched"].items())))
        w("")
    w("Nicht in der Liste:")
    w("")
    for f, why in EXCLUDED.items():
        w("- `%s`: %s" % (f, why))
    for f in unlisted_scripts():
        w("- `%s`: **unbekannt**, bitte einordnen" % f)
    w("")

    cmp = d["cmp"]
    groups = {"gleich": [], "leicht": [], "deutlich": []}
    for n, (lvl, reasons) in sorted(cmp.items()):
        groups[lvl].append((n, reasons))
    w("## Vergleich mit assets/models")
    w("")
    w("| erzeugt | in assets | gleich | leicht abweichend | deutlich abweichend | nur neu | nur in assets |")
    w("|---|---|---|---|---|---|---|")
    w("| %d | %d | %d | %d | %d | %d | %s |" % (len(d["produced"]), len(d["ref"]), len(groups["gleich"]),
                                             len(groups["leicht"]), len(groups["deutlich"]), len(d["only_new"]),
                                             "-" if d["partial"] else len(d["only_ref"])))
    w("")
    w("Hinweis: Die Modelle in assets/models verweisen per URI auf `assets/textures/shared` "
      "(tools/dedupe_glb_textures.js), frisch gebaute betten die Bilder ein. Die Bildbytes bleiben auch nach dem "
      "Dedupe im .glb, deshalb sind die Dateigroessen trotzdem vergleichbar. 'gleich' heisst: gleiche Zahlen "
      "(Knoten, Meshes, Vertices, Dreiecke, Materialien, Bilder, Knotennamen), gleicher Bildinhalt (SHA-1), "
      "BBox bis 1 mm, Groesse bis 5 %. "
      "'deutlich': Vertices/Dreiecke > 1 %, andere Knoten/Materialanzahl oder BBox > 1 cm.")
    w("")

    def table(rows):
        w("| Modell | Generator | KB alt -> neu | Vertices alt -> neu | Dreiecke alt -> neu | Masse neu (m) | Unterschiede |")
        w("|---|---|---|---|---|---|---|")
        for n, reasons in rows:
            o, s = d["ref"][n], d["produced"][n]
            w("| %s | %s | %s -> %s | %d -> %d | %d -> %d | %s | %s |" % (
                n, d["owner"].get(n, "?"), _fmt_kb(o["size"]), _fmt_kb(s["size"]), o["verts"], s["verts"],
                o["tris"], s["tris"], _bbox_txt(s["bbox"]), "; ".join(reasons).replace("|", "/")))
        w("")

    if groups["deutlich"]:
        w("### Deutlich abweichend (%d)" % len(groups["deutlich"]))
        w("")
        table(groups["deutlich"])
    if groups["leicht"]:
        w("### Leicht abweichend (%d)" % len(groups["leicht"]))
        w("")
        table(groups["leicht"])
    if d["only_new"]:
        w("### Nur erzeugt, nicht in assets/models (%d)" % len(d["only_new"]))
        w("")
        for n in d["only_new"]:
            w("- `%s` (%s, %s KB)" % (n, d["owner"].get(n, "?"), _fmt_kb(d["produced"][n]["size"])))
        w("")
    if d["only_ref"]:
        w("### Nur in assets/models, von keinem Generator erzeugt (%d)" % len(d["only_ref"]))
        w("")
        w(", ".join("`%s`" % n for n in d["only_ref"]))
        w("")
    if groups["gleich"]:
        w("### Gleich (%d)" % len(groups["gleich"]))
        w("")
        w(", ".join(n for n, _r in groups["gleich"]))
        w("")
    if d["stale"] and not d["default_mode"]:
        w("### Im Ausgabeordner, aber nicht in diesem Lauf geschrieben (%d)" % len(d["stale"]))
        w("")
        w(", ".join(d["stale"]))
        w("")

    if d["tex_cmp"] is not None:
        t = d["tex_cmp"]
        w("## Texturen der Generatoren (gegen assets/textures)")
        w("")
        w("- gleich: %d, anders: %d, neu: %d" % (len(t["gleich"]), len(t["anders"]), len(t["neu"])))
        for k in ("anders", "neu"):
            if t[k]:
                w("- %s: %s" % (k, ", ".join("`%s`" % x for x in t[k])))
        c = d["cache_cmp"]
        w("- PBR-Cache gegen tools/blender/_pbr_cache: %d gleich, %d anders, %d neu "
          "(ein Lauf direkt im Repo wuerde die anderen/neuen Dateien dort schreiben)" % (
              c["gleich"], len(c["anders"]), len(c["neu"])))
        for k in ("anders", "neu"):
            if c[k]:
                w("  - %s: %s" % (k, ", ".join("`%s`" % x for x in c[k][:40]) + (" ..." if len(c[k]) > 40 else "")))
        w("")

    w("## Vorschaubilder")
    w("")
    if d["no_previews"]:
        w("Abgeschaltet (--no-previews).")
    else:
        for p in d["sheets"] + d["pair_sheets"]:
            w("- `%s`" % rel(p, side))
        if d["default_mode"]:
            w("")
            w("Alt/neu-Vergleichsbilder gibt es nur mit --out ausserhalb von assets/models.")
        if d["preview_errors"]:
            w("")
            w("Fehler:")
            for k, v in sorted(d["preview_errors"].items()):
                w("- `%s`: %s" % (rel(k, side), v))
    w("")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf8", newline="\n") as f:
        f.write("\n".join(L))


if __name__ == "__main__":
    _argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    sys.exit(main(_argv))
