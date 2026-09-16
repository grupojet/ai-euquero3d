from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from engineering_service.app.api import exports, health, manufacturing, projects, revisions, validation
from engineering_service.app.blender.service import ManufacturingService
from engineering_service.app.projects.revisions import RevisionManager
from engineering_service.app.projects.store import ProjectStore
from engineering_service.app.settings import Settings


def create_app(project_root: Path | None = None) -> FastAPI:
    settings = Settings(project_root=project_root) if project_root is not None else Settings()
    app = FastAPI(title="JET 3D Engineer", version="0.1.0")
    store = ProjectStore(settings.project_root)
    manager = RevisionManager(store)
    manufacturing_service = ManufacturingService(
        store,
        blender_executable=settings.blender_executable,
        runner_script=settings.blender_runner_script,
        timeout_seconds=settings.blender_timeout_seconds,
    )
    app.state.settings = settings
    app.state.store = store
    app.state.revisions = manager
    app.state.manufacturing = manufacturing_service

    @app.middleware("http")
    async def require_api_token(request: Request, call_next):
        if settings.api_token and request.url.path.startswith("/v1"):
            expected = f"Bearer {settings.api_token}"
            if request.headers.get("Authorization") != expected:
                return JSONResponse(status_code=401, content={"detail": "Unauthorized"})
        return await call_next(request)
    app.include_router(health.router)
    app.include_router(projects.router, prefix="/v1")
    app.include_router(revisions.router, prefix="/v1")
    app.include_router(validation.router, prefix="/v1")
    app.include_router(exports.router, prefix="/v1")
    app.include_router(manufacturing.router, prefix="/v1")
    return app


app = create_app()
