"""Schneidet die Oeffnung der Hintertuer (Westwand, z 3.65) aus own_hall_interior.glb und own_hall_exterior.glb.
Nur Flaechen im Tuerbereich werden geteilt und entfernt, alles andere bleibt, wie es ist. Mehrfach ausfuehrbar."""
import os
import sys
import bpy
import bmesh
from mathutils import Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "assets", "models")
# Spielkoordinaten
X0, X1, Y1, Z0, Z1 = -6.05, -5.30, 2.10, 3.17, 4.13
# Blender: x = x, y = -z, z = y
LO, HI = V((X0, -Z1, -0.02)), V((X1, -Z0, Y1))


def run(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    path = os.path.join(OUT, name + ".glb")
    before = os.path.getsize(path)
    bpy.ops.import_scene.gltf(filepath=path)
    cutn = 0
    for ob in list(bpy.data.objects):
        if ob.type != "MESH":
            continue
        mw = ob.matrix_world
        inv = mw.inverted()
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        hit = []
        for f in bm.faces:
            ps = [mw @ v.co for v in f.verts]
            lo = V((min(p.x for p in ps), min(p.y for p in ps), min(p.z for p in ps)))
            hi = V((max(p.x for p in ps), max(p.y for p in ps), max(p.z for p in ps)))
            if all(lo[i] < HI[i] - 1e-4 and hi[i] > LO[i] + 1e-4 for i in range(3)):
                hit.append(f)
        # Tretmuelleimer, der im Durchgang stand
        bin_f = [f for f in bm.faces if all(-5.30 < p.x < -4.60 and -3.70 < p.y < -3.05 and 0.004 < p.z < 0.80 for p in (mw @ v.co for v in f.verts))] if name == "own_hall_interior" else []
        if bin_f:
            print("EIMER", ob.name, len(bin_f))
            hit = [f for f in hit if f not in set(bin_f)]
            bmesh.ops.delete(bm, geom=bin_f, context="FACES")
            hit = [f for f in hit if f.is_valid]
            if not hit:
                bm.to_mesh(ob.data)
        if not hit:
            bm.free()
            continue
        # Boden und Schwelle bleiben
        geom = set(hit)
        for ax, val in ((1, LO.y), (1, HI.y), (2, HI.z), (2, 0.015)):
            no = V((0, 0, 0)); no[ax] = 1
            co = V((0, 0, 0)); co[ax] = val
            g = [f for f in geom if f.is_valid]
            es = {e for f in g for e in f.edges}
            vs = {v for f in g for v in f.verts}
            r = bmesh.ops.bisect_plane(bm, geom=g + list(es) + list(vs), dist=1e-5, plane_co=inv @ co, plane_no=(inv.to_3x3() @ no).normalized())
            geom = {x for x in r["geom"] if isinstance(x, bmesh.types.BMFace)} | {x for x in geom if x.is_valid}
        dele = []
        for f in geom:
            if not f.is_valid:
                continue
            c = mw @ f.calc_center_median()
            if LO.y < c.y < HI.y and 0.015 < c.z < HI.z and X0 < c.x < X1:
                dele.append(f)
        cutn += len(dele)
        bmesh.ops.delete(bm, geom=dele, context="FACES")
        bm.to_mesh(ob.data)
        bm.free()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=False, export_normals=True, export_tangents=False, export_animations=False, export_image_format="AUTO", export_image_quality=90)
    print("TUER %s: %d Flaechen entfernt, %.1f -> %.1f MB" % (name, cutn, before / 1048576.0, os.path.getsize(path) / 1048576.0))


for n in sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["own_hall_interior", "own_hall_exterior"]:
    run(n)
