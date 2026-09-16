import bmesh


def _duplicate_vertex_count(bm, tolerance_mm: float) -> int:
    tolerance_m = float(tolerance_mm) / 1000.0
    if tolerance_m <= 0:
        return 0
    seen = set()
    duplicates = 0
    for vert in bm.verts:
        key = tuple(round(float(coord) / tolerance_m) for coord in vert.co)
        if key in seen:
            duplicates += 1
        else:
            seen.add(key)
    return duplicates


def validate_mesh_object(
    obj,
    minimum_wall_mm: float,
    duplicate_tolerance_mm: float = 0.001,
) -> list[dict]:
    bm = bmesh.new()
    try:
        bm.from_mesh(obj.data)
        issues = []
        part = obj.get("jet3d_part", obj.name)
        boundary_or_nonmanifold = [edge for edge in bm.edges if not edge.is_manifold]
        if boundary_or_nonmanifold:
            issues.append(
                {
                    "code": "NON_MANIFOLD",
                    "severity": "BLOCKER",
                    "part": part,
                    "message": f"{len(boundary_or_nonmanifold)} non-manifold/boundary edges detected.",
                    "details": {"edge_count": len(boundary_or_nonmanifold)},
                }
            )
        degenerate = [face for face in bm.faces if face.calc_area() < 1e-12]
        if degenerate:
            issues.append(
                {
                    "code": "DEGENERATE_FACE",
                    "severity": "BLOCKER",
                    "part": part,
                    "message": f"{len(degenerate)} degenerate faces detected.",
                    "details": {"face_count": len(degenerate)},
                }
            )
        loose = [vert for vert in bm.verts if not vert.link_edges]
        if loose:
            issues.append(
                {
                    "code": "LOOSE_GEOMETRY",
                    "severity": "BLOCKER",
                    "part": part,
                    "message": f"{len(loose)} loose vertices detected.",
                    "details": {"vertex_count": len(loose)},
                }
            )
        duplicates = _duplicate_vertex_count(bm, duplicate_tolerance_mm)
        if duplicates:
            issues.append(
                {
                    "code": "DUPLICATE_VERTICES",
                    "severity": "WARNING",
                    "part": part,
                    "message": f"{duplicates} vertices overlap within the configured tolerance.",
                    "details": {
                        "vertex_count": duplicates,
                        "tolerance_mm": float(duplicate_tolerance_mm),
                    },
                }
            )
        if not boundary_or_nonmanifold and bm.faces:
            try:
                signed_volume = float(bm.calc_volume(signed=True))
            except ValueError:
                signed_volume = 0.0
            if signed_volume < -1e-15:
                issues.append(
                    {
                        "code": "INVERTED_NORMALS",
                        "severity": "BLOCKER",
                        "part": part,
                        "message": "Closed mesh has inward-facing orientation.",
                        "details": {"signed_volume_m3": signed_volume},
                    }
                )
        if min(obj.dimensions) * 1000 < float(minimum_wall_mm):
            issues.append(
                {
                    "code": "THIN_FEATURE_HEURISTIC",
                    "severity": "WARNING",
                    "part": part,
                    "message": "Object bounding thickness is below configured minimum wall heuristic.",
                    "details": {"minimum_wall_mm": float(minimum_wall_mm)},
                }
            )
        return issues
    finally:
        bm.free()
