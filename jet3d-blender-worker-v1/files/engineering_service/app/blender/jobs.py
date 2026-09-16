import json
import subprocess
from pathlib import Path


def _ensure_within(path: Path, root: Path) -> Path:
    resolved_root = Path(root).resolve()
    resolved = Path(path).resolve()
    if resolved != resolved_root and resolved_root not in resolved.parents:
        raise ValueError("path outside project root")
    return resolved


def build_job(state: dict, project_root: Path, export_version: int) -> dict:
    if state.get("project_id") in {"", ".", ".."} or "/" in str(state.get("project_id", "")) or "\\" in str(state.get("project_id", "")):
        raise ValueError("invalid project id")
    project_root = Path(project_root).resolve()
    revision = int(state["revision"])
    export_version = int(export_version)
    if revision < 0 or export_version < 1:
        raise ValueError("invalid revision/export version")
    suffix = f"r{revision:03d}" if export_version == 1 else f"r{revision:03d}-v{export_version:03d}"
    export_dir = _ensure_within(project_root / "exports" / suffix, project_root)
    blend_path = _ensure_within(project_root / "project.blend", project_root)
    return {
        "schema_version": 1,
        "project_id": state["project_id"],
        "revision": revision,
        "export_version": export_version,
        "project_root": str(project_root),
        "blend_path": str(blend_path),
        "export_dir": str(export_dir),
        "operation_graph": list(state.get("operation_graph", [])),
        "printer_profile": state.get("printer_profile"),
        "material_profile": state.get("material_profile"),
        "asset_registry": {},
    }


def run_blender_job(
    blender_executable: str,
    runner_script: Path,
    job_path: Path,
    result_path: Path,
    timeout_seconds: int,
) -> dict:
    argv = [
        str(blender_executable),
        "--background",
        "--factory-startup",
        "--python",
        str(runner_script),
        "--",
        str(job_path),
        str(result_path),
    ]
    proc = subprocess.run(
        argv,
        check=False,
        capture_output=True,
        text=True,
        timeout=int(timeout_seconds),
    )
    if proc.returncode != 0:
        stderr = (proc.stderr or "").strip()
        stdout = (proc.stdout or "").strip()
        detail = stderr or stdout or f"exit status {proc.returncode}"
        raise RuntimeError(f"Blender worker failed: {detail}")
    if not Path(result_path).is_file():
        raise RuntimeError("Blender worker did not produce a result file")
    result = json.loads(Path(result_path).read_text(encoding="utf-8"))
    if result.get("status") != "ok":
        raise RuntimeError(f"Blender worker returned failure: {result.get('error', 'unknown error')}")
    return result
