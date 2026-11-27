"""
Vexom Studio — Blender 5.2 High-Poly 2K-ORM-PBR Generator
Builds two freely placeable distribution strips for DataCenter Tycoon Co-op:
  1. assets/models/power_strip.glb  — 6-fach Industrie-Stromleiste (Alu-Profil, Schuko-Buchsen, beleuchteter Schalter)
  2. assets/models/lan_strip.glb    — 8-Port Industrie-LAN-Verteilerleiste (Stahlblech, RJ45-Ports, Link-LEDs)

Socket coordinates (Godot Y-up, meters) match DecorProp.POWER_STRIP_SOCKETS / LAN_STRIP_SOCKETS exactly:
  power_strip: 6 sockets at x = -0.20 + i * 0.08 (i=0..5), y = 0.056, z = 0.0
  lan_strip:   8 ports   at x = -0.21 + i * 0.06 (i=0..7), y = 0.053, z = 0.0
"""
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import bpy
from mathutils import Vector

from build_delivery_van import PartBuilder, make_solid_mat
from hall_pbr_kit import (
    OUT_MODELS_DIR,
    ensure_hall_pbr_library,
    export_glb,
    make_emissive_mat,
    make_orm_mat,
    reset_scene,
)


def _build_power_strip(lib: dict) -> None:
    reset_scene()
    root = bpy.data.objects.new("PowerStripRoot", None)
    bpy.context.scene.collection.objects.link(root)

    m_alu = make_orm_mat("Strip_AluBody", lib["galv"], normal_strength=0.65)
    m_dark = make_orm_mat("Strip_DarkHousing", lib["steel_anthracite"], normal_strength=0.55)
    m_yellow = make_solid_mat("Strip_SafetyYellow", (0.92, 0.70, 0.08), rough=0.38, metal=0.06)
    m_brass = make_solid_mat("Strip_BrassClip", (0.88, 0.72, 0.28), rough=0.22, metal=0.95)
    m_rubber = make_orm_mat("Strip_Rubber", lib["rubber_black"], normal_strength=0.60)
    m_sw_red = make_emissive_mat("Strip_SwitchRed", (0.95, 0.14, 0.10), strength=2.6)
    m_led_ok = make_emissive_mat("Strip_LedGreen", (0.14, 0.92, 0.34), strength=2.2)

    B = PartBuilder("PowerStrip_Mesh", origin_g=Vector((0, 0, 0)))

    # Extruded aluminum main rail + rubber feet + dark endcaps + mounting ears
    B.box((0.0, 0.025, 0.0), (0.60, 0.050, 0.110), m_alu, bevel=0.006)
    B.box((0.0, 0.004, 0.0), (0.62, 0.008, 0.118), m_rubber, bevel=0.002)
    for sx in (-0.315, 0.315):
        B.box((sx, 0.026, 0.0), (0.042, 0.052, 0.114), m_dark, bevel=0.005)
        fx = sx + (0.026 if sx > 0 else -0.026)
        B.box((fx, 0.008, 0.0), (0.022, 0.010, 0.092), m_alu, bevel=0.002)
        for sz in (-0.030, 0.030):
            B.cyl((fx, 0.014, sz), 0.0055, 0.0055, 0.006, m_dark, axis_g="y", seg=12)

    # Top recessed dark socket bed + safety yellow stripes
    B.box((0.0, 0.051, 0.0), (0.54, 0.006, 0.082), m_dark, bevel=0.002)
    B.box((0.0, 0.0515, 0.047), (0.56, 0.004, 0.009), m_yellow, bevel=0.001)
    B.box((0.0, 0.0515, -0.047), (0.56, 0.004, 0.009), m_yellow, bevel=0.001)

    # Illuminated power rocker switch + status LED on left end (-X)
    B.box((-0.268, 0.053, 0.0), (0.034, 0.010, 0.042), m_dark, bevel=0.002)
    B.box((-0.268, 0.058, 0.0), (0.024, 0.010, 0.030), m_sw_red, rot_g_deg=(0.0, 0.0, 8.0), bevel=0.002)
    B.cyl((-0.268, 0.055, -0.030), 0.0045, 0.0045, 0.004, m_led_ok, axis_g="y", seg=12)

    # Strain-relief cable gland on right end (+X)
    B.cyl((0.348, 0.026, 0.0), 0.014, 0.014, 0.036, m_rubber, axis_g="x", seg=16)
    B.cyl((0.374, 0.026, 0.0), 0.010, 0.008, 0.028, m_rubber, axis_g="x", seg=14)

    # 6 angled Schuko power sockets at x = -0.20 + i * 0.08 (i = 0..5)
    for i in range(6):
        sx = -0.20 + float(i) * 0.08
        B.cyl((sx, 0.053, 0.0), 0.028, 0.028, 0.010, m_dark, axis_g="y", seg=24)
        B.cyl((sx, 0.056, 0.0), 0.023, 0.023, 0.004, m_rubber, axis_g="y", seg=20)
        for sign in (-1.0, 1.0):
            B.cyl((sx + sign * 0.008, 0.058, sign * 0.008), 0.0034, 0.0034, 0.003, m_dark, axis_g="y", seg=10)
            B.box((sx - sign * 0.014, 0.057, sign * 0.014), (0.005, 0.007, 0.005), m_brass, rot_g_deg=(0.0, 45.0, 0.0), bevel=0.001)
        B.box((sx, 0.054, -0.034), (0.014, 0.003, 0.005), m_yellow, bevel=0.001)

    B.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "power_strip.glb"))


def _build_lan_strip(lib: dict) -> None:
    reset_scene()
    root = bpy.data.objects.new("LanStripRoot", None)
    bpy.context.scene.collection.objects.link(root)

    m_steel = make_orm_mat("Lan_SteelBody", lib["steel_anthracite"], normal_strength=0.65)
    m_blue = make_orm_mat("Lan_AccentBlue", lib["euro_blue"], normal_strength=0.45)
    m_shield = make_orm_mat("Lan_Rj45Shield", lib["galv"], normal_strength=0.55)
    m_hole = make_solid_mat("Lan_PortHole", (0.04, 0.045, 0.055), rough=0.88, metal=0.1)
    m_rubber = make_orm_mat("Lan_Feet", lib["rubber_black"], normal_strength=0.60)
    m_led_g = make_emissive_mat("Lan_LedGreen", (0.12, 0.94, 0.36), strength=2.6)
    m_led_a = make_emissive_mat("Lan_LedAmber", (0.98, 0.68, 0.10), strength=2.4)
    m_led_b = make_emissive_mat("Lan_LedBlue", (0.18, 0.62, 1.0), strength=2.6)

    B = PartBuilder("LanStrip_Mesh", origin_g=Vector((0, 0, 0)))

    # Managed 8-port industrial switch/patch strip chassis
    B.box((0.0, 0.025, 0.0), (0.56, 0.048, 0.125), m_steel, bevel=0.005)
    B.box((0.0, 0.003, 0.0), (0.54, 0.006, 0.110), m_rubber, bevel=0.002)
    B.box((0.0, 0.049, 0.054), (0.54, 0.005, 0.010), m_blue, bevel=0.001)
    B.box((0.0, 0.049, -0.054), (0.54, 0.005, 0.010), m_blue, bevel=0.001)
    for sx in (-0.295, 0.295):
        B.box((sx, 0.009, 0.0), (0.032, 0.012, 0.098), m_shield, bevel=0.002)
        for sz in (-0.032, 0.032):
            B.cyl((sx, 0.016, sz), 0.005, 0.005, 0.005, m_hole, axis_g="y", seg=12)
    for k in range(5):
        vx = -0.18 + float(k) * 0.09
        B.box((vx, 0.025, 0.063), (0.052, 0.016, 0.003), m_hole, bevel=0.0005)
        B.box((vx, 0.025, -0.063), (0.052, 0.016, 0.003), m_hole, bevel=0.0005)

    # System status LEDs
    B.box((-0.258, 0.050, 0.028), (0.010, 0.004, 0.006), m_led_b, bevel=0.001)
    B.box((-0.258, 0.050, 0.014), (0.010, 0.004, 0.006), m_led_g, bevel=0.001)

    # 8 shielded RJ45 ports at x = -0.21 + i * 0.06 (i = 0..7)
    for i in range(8):
        px = -0.21 + float(i) * 0.06
        B.box((px, 0.051, 0.0), (0.034, 0.012, 0.036), m_shield, bevel=0.002)
        B.box((px, 0.0565, 0.001), (0.024, 0.004, 0.024), m_hole, bevel=0.001)
        B.box((px, 0.0565, -0.013), (0.010, 0.004, 0.007), m_hole, bevel=0.0005)
        B.box((px - 0.010, 0.051, -0.026), (0.007, 0.004, 0.006), m_led_g, bevel=0.001)
        B.box((px + 0.010, 0.051, -0.026), (0.007, 0.004, 0.006), m_led_a, bevel=0.001)

    B.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "lan_strip.glb"))


def main() -> None:
    lib = ensure_hall_pbr_library()
    _build_power_strip(lib)
    _build_lan_strip(lib)
    print("OK: Exported power_strip.glb & lan_strip.glb")


if __name__ == "__main__":
    main()
