import math

from .cuts import add_boss, cut_hole, cut_slot, cut_slot_pattern, shell_box
from .finishing import edge_bevel
from .markings import add_logo, add_text
from .primitives import MM, create_box, create_cylinder_part

ALLOWED = {
    "create_box",
    "create_cylinder",
    "shell",
    "add_boss",
    "cut_hole",
    "cut_slot",
    "cut_slot_pattern",
    "add_text",
    "add_logo",
    "edge_bevel",
    "transform_part",
}

REQUIRED_PARAMETERS = {
    "create_box": {"width_mm", "depth_mm", "height_mm"},
    "create_cylinder": {"diameter_mm", "height_mm"},
    "shell": {"wall_mm", "open_face"},
    "add_boss": {"outer_diameter_mm", "height_mm", "hole_diameter_mm", "position_mm"},
    "cut_hole": {"diameter_mm", "axis", "position_mm"},
    "cut_slot": {"slot_width_mm", "slot_length_mm", "slot_depth_mm", "axis", "position_mm"},
    "cut_slot_pattern": {"count", "pitch_mm", "slot_depth_mm", "slot_length_mm", "slot_width_mm", "origin_mm", "axis"},
    "add_text": {"text", "depth_mm", "position_mm", "mode"},
    "add_logo": {"asset_key", "depth_mm", "position_mm", "mode"},
    "edge_bevel": {"width_mm", "segments"},
    "transform_part": {"translation_mm", "rotation_deg"},
}


def _validate_operation(op: dict) -> None:
    op_type = op.get("type")
    if op_type not in ALLOWED:
        raise ValueError(f"operation type not allow-listed: {op_type}")
    if not op.get("id") or not op.get("part") or not isinstance(op.get("parameters"), dict):
        raise ValueError("operation requires id, part, and parameters")
    missing = REQUIRED_PARAMETERS[op_type] - set(op["parameters"])
    if missing:
        raise ValueError(f"operation {op['id']} missing parameters: {', '.join(sorted(missing))}")


def _transform_part(target, params: dict) -> None:
    translation = params.get("translation_mm", {})
    rotation = params.get("rotation_deg", {})
    target.location = tuple(float(translation.get(axis, 0.0)) * MM for axis in ("x", "y", "z"))
    target.rotation_euler = tuple(math.radians(float(rotation.get(axis, 0.0))) for axis in ("x", "y", "z"))


def execute_operations(operations: list[dict], asset_registry: dict[str, str] | None = None) -> dict:
    parts = {}
    asset_registry = asset_registry or {}
    for op in operations:
        _validate_operation(op)
        op_type = op["type"]
        part = op["part"]
        params = op["parameters"]
        if op_type == "create_box":
            parts[part] = create_box(part, op["id"], params)
        elif op_type == "create_cylinder":
            parts[part] = create_cylinder_part(part, op["id"], params)
        else:
            if part not in parts:
                raise ValueError(f"operation {op['id']} references missing part {part}")
            target = parts[part]
            if op_type == "shell":
                shell_box(target, params["wall_mm"], params["open_face"])
            elif op_type == "add_boss":
                add_boss(target, params)
            elif op_type == "cut_hole":
                cut_hole(target, params)
            elif op_type == "cut_slot":
                cut_slot(target, params)
            elif op_type == "cut_slot_pattern":
                cut_slot_pattern(target, params)
            elif op_type == "add_text":
                add_text(target, params)
            elif op_type == "add_logo":
                add_logo(target, params, asset_registry)
            elif op_type == "edge_bevel":
                edge_bevel(target, params["width_mm"], params["segments"])
            elif op_type == "transform_part":
                _transform_part(target, params)
        parts[part]["jet3d_last_operation_id"] = op["id"]
    return parts
