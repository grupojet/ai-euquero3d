from pathlib import Path

import bpy


def export_stl(objects: list, path: Path) -> Path:
    if not objects:
        raise ValueError("STL export requires at least one object")
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.wm.stl_export(
        filepath=str(path),
        export_selected_objects=True,
        global_scale=1000.0,
    )
    return path
