from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

router = APIRouter()


class ManufacturingSyncRequest(BaseModel):
    export_version: int = Field(default=1, ge=1)
    acknowledged_warning_codes: list[str] = Field(default_factory=list)


@router.post("/projects/{project_id}/manufacturing/sync")
def sync_manufacturing(project_id: str, payload: ManufacturingSyncRequest, request: Request):
    try:
        return request.app.state.manufacturing.sync(
            project_id,
            export_version=payload.export_version,
            acknowledged_warning_codes=payload.acknowledged_warning_codes,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail="project not found") from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@router.get("/projects/{project_id}/manufacturing/status")
def manufacturing_status(project_id: str, request: Request):
    try:
        return request.app.state.manufacturing.status(project_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail="project not found") from exc
