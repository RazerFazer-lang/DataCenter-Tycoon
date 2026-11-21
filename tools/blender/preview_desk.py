"""Rendert Vorschaubilder von assets/models/terminal_desk.glb (Workbench, ohne GPU-Anforderungen).

Aufruf:
    blender --background --factory-startup --python tools/blender/preview_desk.py

Ausgabe: tools/blender/preview_overview.png, preview_top.png, preview_tower.png, preview_mouse.png
"""
import math
import os

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
GLB = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models", "terminal_desk.glb"))

VIEWS = (
    ("preview_overview.png", (1.9, -2.6, 1.9), (0.0, 0.0, 0.65), 45.0),
    ("preview_top.png", (0.1, -1.25, 1.75), (0.05, 0.0, 0.85), 45.0),
    ("preview_tower.png", (1.35, -0.85, 1.25), (0.68, 0.10, 1.05), 40.0),
    ("preview_mouse.png", (0.32, -0.55, 1.02), (0.19, -0.16, 0.82), 50.0),
)


def look_at(cam, target):
    direction = Vector(target) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = "PNG"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"

    cam_data = bpy.data.cameras.new("PreviewCam")
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    for name, loc, target, lens in VIEWS:
        cam.location = Vector(loc)
        cam_data.lens = lens
        look_at(cam, target)
        scene.render.filepath = os.path.join(HERE, name)
        bpy.ops.render.render(write_still=True)
        print("PREVIEW " + scene.render.filepath)


if __name__ == "__main__":
    main()