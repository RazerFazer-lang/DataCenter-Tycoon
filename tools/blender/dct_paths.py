"""Ausgabeordner der Blender-Generatoren an einer Stelle.

Ohne Umgebungsvariablen gilt alles wie bisher. build_all.py setzt sie, damit ein Lauf mit --out
ausserhalb des Projekts nichts im Repo schreibt:

    DCT_MODELS_OUT    .glb-Dateien                      (sonst assets/models)
    DCT_TEXTURES_OUT  Spieltexturen, z. B. nature/      (sonst assets/textures)
    DCT_PBR_CACHE     Zwischenspeicher der PBR-Texturen (sonst tools/blender/_pbr_cache)
    DCT_WORK_OUT      Nebenprodukte: .blend, Vorschaubilder der Generatoren (sonst tools/blender)
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))


def _env(name, default):
    value = os.environ.get(name, "").strip()
    return os.path.abspath(value) if value else default


MODELS_DIR = _env("DCT_MODELS_OUT", os.path.join(ROOT, "assets", "models"))
TEXTURES_DIR = _env("DCT_TEXTURES_OUT", os.path.join(ROOT, "assets", "textures"))
PBR_CACHE = _env("DCT_PBR_CACHE", os.path.join(HERE, "_pbr_cache"))
WORK_DIR = _env("DCT_WORK_OUT", HERE)
