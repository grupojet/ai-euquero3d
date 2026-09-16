import json
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from engineering_service.app.api.exports import _export_dir, _export_stem
from engineering_service.app.blender.jobs import build_job, run_blender_job
from engineering_service.app.exporters.three_mf import write_3mf
from engineering_service.app.profiles.loader import load_material_profile, load_printer_profile
from engineering_service.app.reports.html import render_report
from engineering_service.app.validation.core import export_gate, validate_declared_features, validate_declared_fits


class ManufacturingService:
    def __init__(
        self,
        store,
        *,
        blender_executable: str,
        runner_script: Path,
        timeout_seconds: int = 180,
        runner=run_blender_job,
    ):
        self.store = store
        self.blender_executable = str(blender_executable)
        self.runner_script = Path(runner_script)
        self.timeout_seconds = int(timeout_seconds)
        self.runner = runner

    def _set_status(self, project_id: str, status: str, **extra) -> dict:
        state = self.store.load(project_id)
        state["manufacturing"] = {
            "status": status,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            **extra,
        }
        self.store.save(project_id, state)
        return state

    def status(self, project_id: str) -> dict:
        state = self.store.load(project_id)
        return state.get("manufacturing", {"status": "not_started"})

    def sync(
        self,
        project_id: str,
        export_version: int = 1,
        acknowledged_warning_codes: list[str] | None = None,
    ) -> dict:
        acknowledged = sorted(set(acknowledged_warning_codes or []))
        state = self.store.load(project_id)
        revision = int(state["revision"])
        if revision < 1 or not state.get("operation_graph"):
            raise ValueError("project has no committed manufacturing revision")
        project_root = self.store.resolve_project_path(project_id)
        export_dir = _export_dir(project_root, revision, int(export_version))
        if export_dir.exists() and any(export_dir.iterdir()):
            raise ValueError("export directory already contains files")

        self._set_status(project_id, "running", revision=revision, export_version=int(export_version))
        jobs_dir = project_root / ".jobs"
        jobs_dir.mkdir(parents=True, exist_ok=True)
        job = build_job(state, project_root, int(export_version))
        job_fd, job_name = tempfile.mkstemp(prefix="job-", suffix=".json", dir=jobs_dir)
        result_fd, result_name = tempfile.mkstemp(prefix="result-", suffix=".json", dir=jobs_dir)
        Path(job_name).write_text(json.dumps(job, ensure_ascii=False, indent=2), encoding="utf-8")
        Path(result_name).unlink(missing_ok=True)
        try:
            try:
                result = self.runner(
                    self.blender_executable,
                    self.runner_script,
                    Path(job_name),
                    Path(result_name),
                    self.timeout_seconds,
                )
            except Exception as exc:
                if export_dir.exists():
                    shutil.rmtree(export_dir, ignore_errors=True)
                self._set_status(project_id, "error", revision=revision, error=str(exc))
                raise

            current = self.store.load(project_id)
            if int(current["revision"]) != revision or int(result.get("revision", -1)) != revision:
                if export_dir.exists():
                    shutil.rmtree(export_dir, ignore_errors=True)
                self._set_status(project_id, "error", revision=revision, error="stale Blender worker result")
                raise RuntimeError("stale Blender worker result")

            issues = list(result.get("issues", []))
            printer = load_printer_profile(current["printer_profile"])
            material = load_material_profile(current["material_profile"])
            issues.extend(validate_declared_fits(current.get("fits", [])))
            issues.extend(validate_declared_features(current.get("operation_graph", []), printer, material))
            validation = {
                "revision": revision,
                "issues": issues,
                "object_signatures": dict(result.get("object_signatures", {})),
            }
            current["validation_history"].append(validation)
            current["object_signatures"] = dict(result.get("object_signatures", {}))
            self.store.save(project_id, current)

            if any(issue.get("severity") == "BLOCKER" for issue in issues):
                self._set_status(project_id, "blocked", revision=revision, issues=issues)
                raise ValueError("manufacturing validation contains BLOCKER issues")
            if not export_gate(issues, acknowledged):
                self._set_status(project_id, "awaiting_warning_ack", revision=revision, issues=issues)
                raise ValueError("manufacturing validation warnings require acknowledgement")

            export_dir.mkdir(parents=True, exist_ok=True)
            stem = _export_stem(current, revision, int(export_version))
            three_mf_path = export_dir / f"{stem}.3mf"
            if three_mf_path.exists():
                raise ValueError("3MF export already exists for this revision/version")
            write_3mf(three_mf_path, list(result.get("mesh_parts", [])))

            files = sorted(path.name for path in export_dir.iterdir() if path.is_file())
            if not any(name.endswith(".stl") for name in files):
                raise RuntimeError("Blender worker produced no STL files")
            record = {
                "revision": revision,
                "export_version": int(export_version),
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "validation": issues,
                "acknowledged_warning_codes": acknowledged,
                "files": files,
            }
            report_name = (
                f"r{revision:03d}-engineering-report.html"
                if int(export_version) == 1
                else f"r{revision:03d}-v{int(export_version):03d}-engineering-report.html"
            )
            report_path = project_root / "reports" / report_name
            if report_path.exists():
                raise ValueError("engineering report already exists")
            report_path.write_text(render_report(current, record), encoding="utf-8")
            current["export_history"].append(record)
            current["manufacturing"] = {
                "status": "ready",
                "updated_at": datetime.now(timezone.utc).isoformat(),
                "revision": revision,
                "export_version": int(export_version),
                "blend_path": result.get("blend_path", "project.blend"),
                "files": [f"{export_dir.relative_to(project_root).as_posix()}/{name}" for name in files],
                "report_path": report_path.relative_to(project_root).as_posix(),
                "issues": issues,
            }
            self.store.save(project_id, current)
            return dict(current["manufacturing"])
        finally:
            try:
                import os
                os.close(job_fd)
                os.close(result_fd)
            except OSError:
                pass
            Path(job_name).unlink(missing_ok=True)
            Path(result_name).unlink(missing_ok=True)
