import math

import bpy

from .primitives import MM, create_cylinder


def apply_boolean(target, cutter, operation="DIFFERENCE"):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = target
    target.select_set(True)
    modifier = target.modifiers.new(name=f"JET3D_BOOL_{cutter.name}", type="BOOLEAN")
    modifier.operation = operation
    modifier.solver = "EXACT"
    modifier.object = cutter
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def shell_box(target, wall_mm: float, open_face: str):
    if open_face != "top":
        raise ValueError("V1 shell supports open_face='top' only")
    outer = target.dimensions.copy()
    wall_m = float(wall_mm) * MM
    inner_w = outer.x - 2 * wall_m
    inner_d = outer.y - 2 * wall_m
    inner_h = outer.z - wall_m
    if min(inner_w, inner_d, inner_h) <= 0:
        raise ValueError("wall thickness leaves no internal volume")
    bpy.ops.mesh.primitive_cube_add(
        size=1.0,
        location=(
            target.location.x,
            target.location.y,
            target.location.z + wall_m / 2,
        ),
    )
    cutter = bpy.context.object
    cutter.dimensions = (inner_w, inner_d, inner_h)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    apply_boolean(target, cutter)


def cut_hole(target, p: dict):
    diameter = float(p["diameter_mm"])
    span_mm = max(target.dimensions) / MM + 10.0
    cutter = create_cylinder("JET3D_CUTTER", diameter, span_mm, p["position_mm"])
    axis = p["axis"]
    if axis == "x":
        cutter.rotation_euler[1] = math.pi / 2
    elif axis == "y":
        cutter.rotation_euler[0] = math.pi / 2
    elif axis != "z":
        raise ValueError(f"unsupported hole axis: {axis}")
    bpy.context.view_layer.objects.active = cutter
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    apply_boolean(target, cutter)


def add_boss(target, p: dict):
    position = dict(p["position_mm"])
    position["z"] = float(position.get("z", 0.0)) + float(p["height_mm"]) / 2
    boss = create_cylinder(
        "JET3D_BOSS",
        p["outer_diameter_mm"],
        p["height_mm"],
        position,
    )
    apply_boolean(target, boss, operation="UNION")
    hole = dict(p)
    hole["diameter_mm"] = p["hole_diameter_mm"]
    hole["axis"] = "z"
    hole["position_mm"] = position
    cut_hole(target, hole)


def cut_slot_pattern(target, p: dict):
    if p.get("axis") != "x":
        raise ValueError("V1 slot pattern supports axis='x' only")
    count = int(p["count"])
    for index in range(count):
        origin = dict(p["origin_mm"])
        origin["z"] = float(origin.get("z", 0.0)) + (
            index - (count - 1) / 2
        ) * float(p["pitch_mm"])
        bpy.ops.mesh.primitive_cube_add(size=1.0)
        cutter = bpy.context.object
        cutter.dimensions = (
            float(p["slot_depth_mm"]) * MM,
            float(p["slot_length_mm"]) * MM,
            float(p["slot_width_mm"]) * MM,
        )
        cutter.location = (
            float(origin.get("x", 0.0)) * MM,
            float(origin.get("y", 0.0)) * MM,
            float(origin.get("z", 0.0)) * MM,
        )
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        apply_boolean(target, cutter)


def cut_slot(target, p: dict):
    """Cut one deterministic rectangular slot along the requested penetration axis."""
    axis = p.get("axis", "z")
    length = float(p["slot_length_mm"]) * MM
    width = float(p["slot_width_mm"]) * MM
    depth = float(p.get("slot_depth_mm", max(target.dimensions) / MM + 10.0)) * MM
    if min(length, width, depth) <= 0:
        raise ValueError("slot dimensions must be positive")
    if axis == "x":
        dimensions = (depth, length, width)
    elif axis == "y":
        dimensions = (length, depth, width)
    elif axis == "z":
        dimensions = (length, width, depth)
    else:
        raise ValueError(f"unsupported slot axis: {axis}")
    position = p.get("position_mm", p.get("origin_mm", {}))
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    cutter = bpy.context.object
    cutter.name = "JET3D_SLOT_CUTTER"
    cutter.dimensions = dimensions
    cutter.location = tuple(float(position.get(a, 0.0)) * MM for a in ("x", "y", "z"))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    apply_boolean(target, cutter)
