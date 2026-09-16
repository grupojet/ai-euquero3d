import os
from pathlib import Path

from pydantic import BaseModel, Field


class Settings(BaseModel):
    host: str = Field(default_factory=lambda: os.environ.get("JET3D_HOST", "127.0.0.1"))
    port: int = Field(default_factory=lambda: int(os.environ.get("JET3D_PORT", "8765")))
    api_token: str = Field(default_factory=lambda: os.environ.get("JET3D_API_TOKEN", ""))
    project_root: Path = Field(
        default_factory=lambda: Path(
            os.environ.get("JET3D_PROJECT_ROOT", str(Path.home() / "JET3DProjects"))
        )
    )
    blender_executable: str = Field(default_factory=lambda: os.environ.get("JET3D_BLENDER", "blender"))
    blender_timeout_seconds: int = Field(default_factory=lambda: int(os.environ.get("JET3D_BLENDER_TIMEOUT", "180")))
    blender_runner_script: Path = Field(
        default_factory=lambda: Path(
            os.environ.get(
                "JET3D_BLENDER_RUNNER",
                str(Path(__file__).resolve().parents[2] / "scripts" / "blender_headless_worker.py"),
            )
        )
    )
