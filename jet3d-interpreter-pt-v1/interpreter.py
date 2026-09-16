import re
import unicodedata


class InterpretationError(ValueError):
    pass


_DIMENSIONS = re.compile(
    r"(?P<w>\d+(?:\.\d+)?)\s*[x×]\s*(?P<d>\d+(?:\.\d+)?)\s*[x×]\s*(?P<h>\d+(?:\.\d+)?)\s*mm",
    re.I,
)
_CHANGE = re.compile(r"\b(width|depth|height)\s+(?:to\s+)?(\d+(?:\.\d+)?)\s*mm", re.I)
_GLAND = re.compile(r"(?:([0-9]+(?:\.[0-9]+)?)\s*mm\s+(?:cable[- ]gland|gland)|(?:cable[- ]gland|gland)(?:\s+opening)?(?:\s+of)?\s+([0-9]+(?:\.[0-9]+)?)\s*mm)", re.I)
_FASTENER = re.compile(r"(?:(\d+)\s+M(\d+)\s+fasteners?|(?:fasteners?|screws?)\s+(\d+)\s+M(\d+)|([0-9]+)\s+(?:fasteners?|screws?)\s+M(\d+))", re.I)
_GLAND_MOVE = re.compile(
    r"move\s+(?:the\s+)?gland\s+(\d+(?:\.\d+)?)\s*mm\s+(?:to\s+the\s+)?(right|left|up|down)",
    re.I,
)


def _ascii(text: str) -> str:
    return unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")


def _normalize_instruction(text: str) -> str:
    normalized = _ascii(" ".join(text.strip().split())).lower()

    phrase_replacements = (
        ("caixa de eletronica", "electronics enclosure"),
        ("caixa eletronica", "electronics enclosure"),
        ("gabinete de eletronica", "electronics enclosure"),
        ("gabinete eletronico", "electronics enclosure"),
        ("prensa-cabo", "gland"),
        ("prensa cabo", "gland"),
        ("para a direita", "right"),
        ("para direita", "right"),
        ("para a esquerda", "left"),
        ("para esquerda", "left"),
        ("para cima", "up"),
        ("para baixo", "down"),
        ("tampa removivel", "removable lid"),
        ("ventilacao lateral", "lateral ventilation"),
        ("baixo-relevo", "deboss"),
        ("baixo relevo", "deboss"),
        ("alto-relevo", "emboss"),
        ("alto relevo", "emboss"),
        ("abertura para gland de", "gland opening of"),
        ("abertura gland de", "gland opening of"),
    )
    for source, target in phrase_replacements:
        normalized = normalized.replace(source, target)

    word_replacements = {
        "largura": "width",
        "profundidade": "depth",
        "altura": "height",
        "mova": "move",
        "mover": "move",
        "altere": "change",
        "alterar": "change",
        "ventilacao": "ventilation",
        "parafusos": "fasteners",
        "parafuso": "fastener",
        "fixadores": "fasteners",
        "fixador": "fastener",
    }
    for source, target in word_replacements.items():
        normalized = re.sub(rf"\b{re.escape(source)}\b", target, normalized)

    normalized = re.sub(r"\bmove\s+o\s+gland\b", "move the gland", normalized)
    normalized = re.sub(r"\b(width|depth|height)\s+para\s+", r"\1 to ", normalized)
    return " ".join(normalized.split())


def _fastener_payload(match: re.Match | None) -> dict | None:
    if not match:
        return None
    groups = match.groups()
    pairs = ((groups[0], groups[1]), (groups[2], groups[3]), (groups[4], groups[5]))
    for count, metric in pairs:
        if count and metric:
            return {"count": int(count), "metric": f"M{metric}"}
    return None


def _gland_diameter(match: re.Match | None) -> float | None:
    if not match:
        return None
    return float(next(value for value in match.groups() if value is not None))


def interpret_instruction(instruction: str, state: dict) -> dict:
    del state  # Reserved for context-aware interpretation in later supported commands.
    text = _normalize_instruction(instruction)
    lowered = text.lower()

    changes = {f"{name.lower()}_mm": float(value) for name, value in _CHANGE.findall(text)}
    if changes:
        return {"kind": "dimension_revision", "changes": changes}

    if re.search(r"\bmove\b", lowered) and "gland" in lowered:
        match = _GLAND_MOVE.search(text)
        if not match:
            raise InterpretationError("gland move requires distance and direction")
        return {
            "kind": "feature_move",
            "feature": "gland",
            "distance_mm": float(match.group(1)),
            "direction": match.group(2).lower(),
        }

    dims = _DIMENSIONS.search(text)
    is_enclosure_request = "enclosure" in lowered or "electronics box" in lowered
    if is_enclosure_request:
        if not dims:
            raise InterpretationError("missing explicit dimensions for electronics enclosure")
        fastener = _FASTENER.search(text)
        gland = _GLAND.search(text)
        return {
            "kind": "electronics_enclosure",
            "dimensions_mm": {
                "width": float(dims.group("w")),
                "depth": float(dims.group("d")),
                "height": float(dims.group("h")),
            },
            "wall_mm": 2.4,
            "fastener": _fastener_payload(fastener),
            "lateral_ventilation": "ventilation" in lowered,
            "removable_lid": "removable lid" in lowered,
            "logo_mode": (
                "deboss" if "logo" in lowered and "deboss" in lowered
                else "emboss" if "logo" in lowered
                else None
            ),
            "gland_diameter_mm": _gland_diameter(gland),
        }

    raise InterpretationError("unsupported V1 instruction; use an explicit supported part or revision request")
