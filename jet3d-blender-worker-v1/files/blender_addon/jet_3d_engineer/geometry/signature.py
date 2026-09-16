import hashlib
import struct


def mesh_signature(obj) -> str:
    digest = hashlib.sha256()
    digest.update(obj.name.encode("utf-8"))
    for vertex in obj.data.vertices:
        digest.update(
            struct.pack(
                "!iii",
                round(vertex.co.x * 1_000_000),
                round(vertex.co.y * 1_000_000),
                round(vertex.co.z * 1_000_000),
            )
        )
    for polygon in obj.data.polygons:
        digest.update(struct.pack("!I", len(polygon.vertices)))
        for index in polygon.vertices:
            digest.update(struct.pack("!I", int(index)))
    return digest.hexdigest()


def manual_override_status(
    stored_signatures: dict[str, str],
    current_signatures: dict[str, str],
    confirmed: bool,
) -> dict[str, bool]:
    if not stored_signatures:
        return {"detected": False, "allowed": True}
    detected = any(
        current_signatures.get(part) != signature
        for part, signature in stored_signatures.items()
    )
    return {"detected": detected, "allowed": (not detected) or bool(confirmed)}


def validation_matches_signatures(
    validation_record: dict, current_signatures: dict[str, str]
) -> bool:
    validated = validation_record.get("object_signatures", {})
    return bool(validated) and validated == current_signatures
