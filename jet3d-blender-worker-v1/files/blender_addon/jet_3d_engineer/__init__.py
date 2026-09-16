bl_info = {
    "name": "JET 3D Engineer",
    "author": "Grupo Jet",
    "version": (0, 1, 0),
    "blender": (4, 2, 0),
    "location": "View3D > Sidebar > JET 3D",
    "category": "3D View",
}

import os

try:
    import bpy
except ModuleNotFoundError:  # Allows transport/domain imports in normal Python tests.
    bpy = None

_HEADLESS = os.getenv("JET3D_HEADLESS_WORKER") == "1"

if bpy is not None and not _HEADLESS:
    from .operators.export import JET3D_OT_export
    from .operators.project import JET3D_OT_create_project, JET3D_OT_open_project, JET3D_OT_reconnect
    from .operators.revision import JET3D_OT_apply_revision, JET3D_OT_interpret, JET3D_OT_rebuild_current
    from .operators.validate import JET3D_OT_validate
    from .properties import JET3DProperties, JET3DWarningAck
    from .ui.panel import JET3D_PT_main

    CLASSES = (
        JET3DWarningAck,
        JET3DProperties,
        JET3D_OT_reconnect,
        JET3D_OT_create_project,
        JET3D_OT_open_project,
        JET3D_OT_interpret,
        JET3D_OT_apply_revision,
        JET3D_OT_rebuild_current,
        JET3D_OT_validate,
        JET3D_OT_export,
        JET3D_PT_main,
    )
else:
    CLASSES = ()


def register():
    if bpy is None:
        raise RuntimeError("JET 3D Engineer registration requires Blender")
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Scene.jet3d = bpy.props.PointerProperty(type=JET3DProperties)


def unregister():
    if bpy is None:
        return
    if hasattr(bpy.types.Scene, "jet3d"):
        del bpy.types.Scene.jet3d
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)
