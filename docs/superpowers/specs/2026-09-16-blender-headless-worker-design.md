# JET 3D Engineer — Blender Headless Manufacturing Worker Design

## Status
Approved architecture for implementation.

## Goal
After a revision is confirmed in the web UI, automatically materialize the committed `project.jet3d.json` operation graph into manufacturing geometry using Blender in background mode, validate the generated mesh, persist `project.blend`, produce versioned STL/3MF/report artifacts, and expose job/artifact status to the web UI without allowing arbitrary Python execution.

## Scope
This design covers the server-side manufacturing path only:

1. revision confirmed and committed;
2. deterministic Blender headless synchronization;
3. mesh validation and signatures;
4. `.blend` persistence;
5. STL + 3MF + engineering report generation;
6. artifact/status APIs for the web UI;
7. failure isolation, rollback, and idempotency.

It does not add a general-purpose CAD scripting language, user-supplied Python, a distributed worker cluster, GPU rendering, slicing/G-code generation, or printer control.

## Existing Contracts Reused

- `project.jet3d.json` remains the source of truth.
- `operation_graph` remains the only geometry instruction source.
- Blender geometry execution remains restricted to the existing allow-list: `create_box`, `create_cylinder`, `shell`, `add_boss`, `cut_hole`, `cut_slot`, `cut_slot_pattern`, `add_text`, `add_logo`, `edge_bevel`, and `transform_part`.
- `mesh_signature` remains the geometry integrity mechanism.
- validation severities remain `BLOCKER`, `WARNING`, and `INFO`.
- any `BLOCKER` prevents export.
- warnings require acknowledgement before final export.
- exports remain immutable and revision/version scoped.

## Architecture

### Components

### 1. API / Orchestrator
The FastAPI service owns manufacturing jobs. It never imports `bpy` in-process. It writes a versioned job JSON under the project directory and launches Blender as a subprocess.

Responsibilities:
- create job records;
- ensure only one active manufacturing job per project/revision;
- resolve project paths safely;
- launch Blender with a fixed trusted runner script;
- collect result JSON;
- update project metadata and manufacturing history;
- expose job/artifact endpoints.

### 2. Trusted Blender Runner
A fixed repository-owned Python script executes under:

`blender --background --factory-startup --python <trusted_runner.py> -- <job.json>`

The runner accepts only a path to a server-generated job document. It never evaluates user text or arbitrary Python.

Responsibilities:
- load job JSON;
- validate schema/version/revision;
- execute the allow-listed operation graph with existing `execute_operations()`;
- compute mesh signatures;
- run mesh checks and assembly overlap checks;
- compute world bounds;
- save `project.blend` atomically;
- export STL files into a temporary export directory;
- write a result JSON for the orchestrator.

### 3. Existing Service Export Layer
The API continues to own 3MF generation and engineering report generation. The Blender runner provides triangle meshes/signatures to the orchestrator; the service writes 3MF and finalizes the report using existing server-side functions.

This keeps the service as the source of truth for export history and avoids duplicating 3MF/report logic inside Blender.

### 4. Web UI
The web UI does not talk to Blender directly. After a revision commit it starts or observes a manufacturing job and polls its status.

States shown to the user:
- `queued`
- `running`
- `validating`
- `blocked`
- `ready`
- `failed`

When `ready`, the UI displays generated artifacts and preview metadata. When `blocked`, it displays validation issues. When `failed`, the committed revision remains intact and the prior `.blend` remains available.

## Project Filesystem Layout

For each project:

```text
<project>/
  project.jet3d.json
  project.blend
  assets/
  exports/
    r001/
    r001-v002/
  reports/
  snapshots/
  manufacturing/
    jobs/
      <job_id>.json
      <job_id>.result.json
      <job_id>.log
    staging/
      <job_id>/
        project.blend
        stl/
```

`manufacturing/staging/<job_id>` is temporary. Nothing is promoted to canonical paths until the Blender process exits successfully and the orchestrator validates the result.

## Manufacturing Job Contract

Server-generated job JSON:

```json
{
  "schema_version": 1,
  "job_id": "uuid",
  "project_id": "uuid",
  "revision": 1,
  "project_root": "/srv/jet3d/projects/<id>",
  "operation_graph": [],
  "printer_profile": "creality-k2-plus",
  "material_profile": "pla",
  "asset_registry": {},
  "export_version": 1,
  "acknowledged_warning_codes": []
}
```

The orchestrator generates every field from trusted server state. The browser cannot supply filesystem paths, runner paths, or operation types directly.

## Result Contract

The Blender runner writes:

```json
{
  "schema_version": 1,
  "job_id": "uuid",
  "project_id": "uuid",
  "revision": 1,
  "status": "success",
  "object_signatures": {},
  "bounds_mm": {"x": 0, "y": 0, "z": 0},
  "issues": [],
  "mesh_parts": [],
  "stl_files": [],
  "blend_file": "manufacturing/staging/<job_id>/project.blend"
}
```

The API rejects a result if `job_id`, `project_id`, or `revision` differs from the submitted job.

## Revision and Synchronization Semantics

A revision commit remains a metadata transaction. Geometry synchronization is a second, explicit manufacturing transaction.

After commit:
1. the revision is durable in `project.jet3d.json`;
2. a manufacturing job is created for that exact revision;
3. Blender rebuilds from the full committed `operation_graph`, never incrementally from the previous mesh;
4. successful geometry replaces canonical `project.blend` atomically;
5. failed geometry does not roll back the metadata revision, but marks that revision as unsynchronized/failed.

The project state gains:

```json
{
  "manufacturing": {
    "revision": 1,
    "status": "ready",
    "job_id": "uuid",
    "updated_at": "ISO-8601",
    "object_signatures": {},
    "artifacts": []
  },
  "manufacturing_history": []
}
```

The web UI must never describe a revision as fabrication-ready unless `manufacturing.revision == revision` and `manufacturing.status == "ready"`.

## Validation Flow

The Blender runner performs geometry-dependent validation:
- non-manifold/boundary edges;
- degenerate faces;
- loose geometry;
- duplicate vertices;
- inverted normals;
- thin-feature heuristic;
- assembly overlap;
- world-space build volume.

The service adds declaration/profile validation already implemented by the backend.

The combined issue set is persisted as the validation record for the exact revision and exact object signatures.

If any issue is `BLOCKER`:
- `.blend` may still be promoted for inspection;
- no final STL/3MF/report export is promoted;
- manufacturing status becomes `blocked`.

If there are only `WARNING`/`INFO` issues:
- geometry synchronization completes;
- manufacturing status becomes `blocked` until required warnings are acknowledged for export, or `ready` when the current export request satisfies the warning gate.

For V1 web automation, synchronization and export are separate actions: first produce validated geometry; then the user acknowledges warnings and requests export. This prevents silent acknowledgement.

## Export Flow

### Synchronize Geometry
Produces:
- canonical `project.blend`;
- persisted validation record;
- object signatures;
- preview/artifact metadata.

### Export Manufacturing Package
Requires:
- manufacturing revision equals current project revision;
- validation signatures equal current manufacturing signatures;
- no `BLOCKER`;
- all `WARNING` codes acknowledged;
- requested export revision/version does not already exist.

Then:
1. create an export staging directory;
2. copy runner-generated STL files for the validated signatures;
3. generate 3MF server-side from the runner mesh payload;
4. finalize engineering report server-side;
5. atomically rename staging to the immutable final export directory;
6. append export history.

Partial failures delete only the staging directory.

## API Additions

### `POST /v1/projects/{project_id}/manufacturing/sync`
Starts synchronization for the current committed revision.

Response `202`:

```json
{
  "job_id": "uuid",
  "project_id": "uuid",
  "revision": 1,
  "status": "queued"
}
```

Rules:
- returns `409` if project has an active job for the same revision;
- returns `409` if the requested/current revision changed during launch;
- repeated request after a `ready` result may return the existing job unless `force=true` is introduced in a later version. V1 does not add `force`.

### `GET /v1/projects/{project_id}/manufacturing/jobs/{job_id}`
Returns job state, timestamps, validation summary, and safe relative artifact paths.

### `GET /v1/projects/{project_id}/manufacturing`
Returns the latest manufacturing state for the current project revision.

### `POST /v1/projects/{project_id}/manufacturing/export`
Body:

```json
{
  "export_version": 1,
  "acknowledged_warning_codes": []
}
```

Creates STL/3MF/report only from the latest validated manufacturing result.

### Artifact download
A dedicated endpoint serves only allow-listed project-relative files recorded in manufacturing/export history. It does not accept arbitrary filesystem paths.

## Process Control

- Blender executable defaults to `/usr/bin/blender` and is configurable only by server environment.
- subprocess uses an argument list, never `shell=True`.
- timeout is configurable, default 300 seconds.
- stdout/stderr are captured to `manufacturing/jobs/<job_id>.log`.
- worker exit code non-zero marks the job `failed`.
- runner result missing or invalid also marks `failed`.
- service restart can recover jobs left in `running` by marking them `failed` with reason `service_restart` in V1. Automatic job resumption is out of scope.

## Concurrency and Idempotency

V1 permits one active Blender job per project. Different projects may execute concurrently up to a configurable global semaphore, default `1` on the current 4 vCPU / 8 GB runtime VM.

A job is uniquely bound to `(project_id, revision, operation_graph_hash)`.

If the operation graph hash and revision already have a completed synchronization, the API returns that existing completed job instead of rebuilding.

## Security

- browser never sends Python;
- browser never sends executable paths;
- browser never sends filesystem paths;
- runner is a fixed file deployed with the application;
- operation graph is revalidated against the allow-list before Blender launch and again inside Blender;
- project path is resolved through `ProjectStore.resolve_project_path()`;
- asset keys resolve only through a server-owned asset registry;
- subprocess uses no shell;
- output promotion accepts only paths under the job staging directory;
- Nginx continues to inject the backend bearer token server-side; token is not exposed to browser JavaScript.

## Failure and Rollback

Before synchronization, the service preserves:
- current `project.blend` as a revision-linked snapshot when present;
- current metadata state already protected by the existing revision snapshot mechanism.

On worker failure:
- canonical `project.blend` is untouched;
- staging is retained only long enough to collect diagnostics, then removed;
- job log/result remain for troubleshooting;
- manufacturing state becomes `failed`.

On successful synchronization:
- staged `.blend` replaces canonical `project.blend` atomically;
- signatures and validation are persisted together with manufacturing state.

## Web UI Changes

After revision confirmation:
- show `Sincronizar geometria` automatically as the next primary action;
- start sync after explicit user action in V1;
- display live job status by polling every 2 seconds while active;
- show blocker/warning/info counts;
- show `Exportar STL + 3MF` only when geometry is synchronized and no blocker exists;
- show download links only for recorded artifacts;
- display the last successful manufacturing revision prominently.

Automatic sync immediately after commit can be enabled in a later revision once the manual flow is accepted in production.

## Preview

V1 keeps the existing browser schematic preview during editing. After successful synchronization, the backend exposes a lightweight preview mesh endpoint sourced from the validated runner mesh result. The browser may render that mesh with Three.js.

The preview is informational only. STL/3MF generation uses the validated Blender geometry, not the browser mesh.

## Testing Strategy

### Pure Python tests
- job schema and hash stability;
- safe path validation;
- job lifecycle transitions;
- idempotent completed-job reuse;
- conflict on active job;
- result identity/revision verification;
- export gate behavior;
- artifact allow-list enforcement;
- failure leaves canonical `.blend` untouched.

### Blender background tests
Run with installed Blender:
- trusted runner loads job and executes allow-listed operations;
- expected enclosure golden model is generated;
- signatures are stable across deterministic rebuilds;
- `.blend` is saved;
- STL files are generated;
- mesh validation detects a known blocker;
- runner rejects an unknown operation type;
- runner rejects project/job identity mismatch.

### API integration tests
- commit revision → sync → poll → ready;
- commit revision → sync → blocked;
- worker failure → failed state and preserved previous blend;
- new revision makes previous manufacturing state stale;
- export denied before sync;
- export denied on stale signatures;
- export denied with blocker;
- export denied until warnings are acknowledged;
- successful export records STL, 3MF, and report.

### Production acceptance on `euquero3d-runtime`
- confirm Blender version;
- run one real project from current web UI;
- confirm generated `project.blend` opens headlessly;
- confirm validation history is recorded;
- confirm STL/3MF/report artifacts exist and are downloadable;
- confirm API remains healthy after Blender worker completion/failure;
- confirm no bearer token appears in browser source/network payloads.

## Deployment

The deployment adds the trusted runner and worker/orchestrator modules to `/opt/jet3d/app`, restarts only `jet3d-api.service`, and does not reinstall Blender or replace the web UI wholesale.

Deployment verification must include:

```bash
blender --version | head -n 1
curl -fsS http://127.0.0.1:8765/health
systemctl is-active jet3d-api.service
```

Then an authenticated production smoke test creates a manufacturing sync job and verifies its terminal status.

## Acceptance Criteria

The feature is accepted when all of the following are true:

1. a committed revision can be synchronized without opening Blender interactively;
2. Blender receives only server-generated allow-listed operations;
3. a successful sync produces canonical `project.blend` and stable object signatures;
4. validation is persisted for the exact revision/signatures;
5. blockers prevent manufacturing export;
6. warnings require explicit acknowledgement;
7. export produces immutable STL, 3MF, and report artifacts;
8. failed jobs do not corrupt the committed project or previous canonical blend;
9. the web UI reports queued/running/blocked/ready/failed state and exposes only recorded artifacts;
10. the existing `/health` endpoint remains healthy before and after worker jobs.
