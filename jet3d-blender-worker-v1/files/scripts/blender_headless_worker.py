"""Fixed Blender entrypoint for JET 3D Engineer manufacturing jobs.

Invoked only as:
  blender --background --factory-startup --python scripts/blender_headless_worker.py -- JOB RESULT
"""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "blender_addon"))

os.environ["JET3D_HEADLESS_WORKER"] = "1"

import bpy

from engineering_service.app.profiles.loader import load_material_profile
from jet_3d_engineer.export.stl import export_stl
from jet_3d_engineer.geometry.executor import execute_operations
from jet_3d_engineer.geometry.signature import mesh_signature
from jet_3d_engineer.validation.mesh_checks import validate_mesh_object


def _safe_path(value: str, project_root: Path) -> Path:
    root = project_root.resolve()
    path = Path(value).resolve()
    if path != root and root not in path.parents:
        raise ValueError("job path outside project root")
    return path


def _asset_registry(project_root: Path) -> dict[str, str]:
    registry = {}
    logo = project_root / "assets" / "grupo_jet_logo.svg"
    if logo.is_file():
        registry["grupo_jet_logo"] = str(logo)
    return registry


def _mesh_part(obj) -> dict:
    vertices = [
        (float(v.co.x) * 1000.0, float(v.co.y) * 1000.0, float(v.co.z) * 1000.0)
        for v in obj.data.vertices
    ]
    triangles = []
    for polygon in obj.data.polygons:
        indices = [int(i) for i in polygon.vertices]
        for offset in range(1, len(indices) - 1):
            triangles.append((indices[0], indices[offset], indices[offset + 1]))
    return {"name": obj.get("jet3d_part", obj.name), "vertices_mm": vertices, "triangles": triangles}


def run(job: dict) -> dict:
    project_root = Path(job["project_root"]).resolve()
    blend_path = _safe_path(job["blend_path"], project_root)
    export_dir = _safe_path(job["export_dir"], project_root)
    export_dir.mkdir(parents=True, exist_ok=True)
    material = load_material_profile(job["material_profile"])
    minimum_wall_mm = float(material["minimum_wall_mm"])

    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = execute_operations(job["operation_graph"], _asset_registry(project_root))

    issues = []
    signatures = {}
    mesh_parts = []
    stl_parts = []
    for part_name, obj in sorted(parts.items()):
        issues.extend(validate_mesh_object(obj, minimum_wall_mm=minimum_wall_mm))
        signatures[part_name] = mesh_signature(obj)
        mesh_parts.append(_mesh_part(obj))
        stl_path = export_dir / f"{part_name.replace('_', '-')}.stl"
        export_stl([obj], stl_path)
        stl_parts.append(str(stl_path.relative_to(project_root)))

    blend_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    return {
        "status": "ok",
        "project_id": job["project_id"],
        "revision": int(job["revision"]),
        "export_version": int(job["export_version"]),
        "blend_path": str(blend_path.relative_to(project_root)),
        "stl_parts": stl_parts,
        "mesh_parts": mesh_parts,
        "object_signatures": signatures,
        "issues": issues,
    }


def main() -> int:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 2:
        raise SystemExit("expected JOB_JSON RESULT_JSON")
    job_path, result_path = args
    result_file = Path(result_path)
    try:
        job = json.loads(Path(job_path).read_text(encoding="utf-8"))
        result = run(job)
    except Exception as exc:
        result = {"status": "error", "error": f"{type(exc).__name__}: {exc}"}
        result_file.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        raise
    result_file.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
