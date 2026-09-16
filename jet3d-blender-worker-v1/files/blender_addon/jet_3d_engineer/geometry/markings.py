from pathlib import Path

import bpy

from .cuts import apply_boolean
from .primitives import MM


def _position_mm(obj, p: dict) -> None:
    pos = p["position_mm"]
    obj.location = tuple(float(pos.get(axis, 0.0)) * MM for axis in ("x", "y", "z"))


def add_text(target, p: dict):
    if p["mode"] not in {"emboss", "deboss"}:
        raise ValueError("text mode must be emboss or deboss")
    bpy.ops.object.text_add()
    text = bpy.context.object
    text.data.body = p["text"]
    text.data.extrude = abs(float(p["depth_mm"])) * MM
    _position_mm(text, p)
    bpy.context.view_layer.objects.active = text
    bpy.ops.object.convert(target="MESH")
    apply_boolean(target, bpy.context.object, operation="UNION" if p["mode"] == "emboss" else "DIFFERENCE")


def add_logo(target, p: dict, asset_registry: dict[str, str]):
    if p["mode"] not in {"emboss", "deboss"}:
        raise ValueError("logo mode must be emboss or deboss")
    if p["asset_key"] not in asset_registry:
        raise ValueError(f"unregistered asset key: {p['asset_key']}")
    asset_path = Path(asset_registry[p["asset_key"]])
    if not asset_path.exists() or asset_path.suffix.lower() != ".svg":
        raise ValueError(f"registered SVG asset unavailable: {p['asset_key']}")
    before = {obj.name for obj in bpy.data.objects}
    bpy.ops.import_curve.svg(filepath=str(asset_path))
    imported = [obj for obj in bpy.data.objects if obj.name not in before]
    if not imported:
        raise ValueError("SVG import produced no geometry")
    for obj in imported:
        if hasattr(obj.data, "extrude"):
            obj.data.extrude = abs(float(p["depth_mm"])) * MM
        _position_mm(obj, p)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target="MESH")
        apply_boolean(target, bpy.context.object, operation="UNION" if p["mode"] == "emboss" else "DIFFERENCE")
