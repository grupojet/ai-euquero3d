import bpy

from .primitives import MM


def edge_bevel(target, width_mm: float, segments: int):
    bpy.context.view_layer.objects.active = target
    modifier = target.modifiers.new(name="JET3D_BEVEL", type="BEVEL")
    modifier.width = float(width_mm) * MM
    modifier.segments = int(segments)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
