import bpy

MM = 0.001


def ensure_scene_units():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.length_unit = "MILLIMETERS"
    scene.unit_settings.scale_length = 1.0


def _position_tuple(position_mm: dict) -> tuple[float, float, float]:
    return tuple(float(position_mm.get(axis, 0.0)) * MM for axis in ("x", "y", "z"))


def create_box(part: str, op_id: str, p: dict):
    ensure_scene_units()
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    obj = bpy.context.object
    obj.name = f"JET3D__{part}"
    obj.dimensions = (
        float(p["width_mm"]) * MM,
        float(p["depth_mm"]) * MM,
        float(p["height_mm"]) * MM,
    )
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    pos = p.get(
        "position_mm",
        {"x": 0.0, "y": 0.0, "z": float(p["height_mm"]) / 2},
    )
    obj.location = (
        float(pos.get("x", 0.0)) * MM,
        float(pos.get("y", 0.0)) * MM,
        float(pos.get("z", float(p["height_mm"]) / 2)) * MM,
    )
    obj["jet3d_part"] = part
    obj["jet3d_operation_id"] = op_id
    return obj


def create_cylinder(
    name: str,
    diameter_mm: float,
    height_mm: float,
    position_mm: dict,
    vertices: int = 64,
):
    ensure_scene_units()
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=float(diameter_mm) * MM / 2,
        depth=float(height_mm) * MM,
    )
    obj = bpy.context.object
    obj.name = name
    obj.location = _position_tuple(position_mm)
    return obj


def create_cylinder_part(part: str, op_id: str, p: dict):
    height_mm = float(p["height_mm"])
    position = p.get(
        "position_mm",
        {"x": 0.0, "y": 0.0, "z": height_mm / 2},
    )
    obj = create_cylinder(
        f"JET3D__{part}",
        float(p["diameter_mm"]),
        height_mm,
        position,
        int(p.get("vertices", 64)),
    )
    obj["jet3d_part"] = part
    obj["jet3d_operation_id"] = op_id
    return obj
