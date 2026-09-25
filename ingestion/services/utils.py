"""Small helpers shared across services."""

from datetime import datetime, timezone
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]


def load_yaml(path):
    """Read a YAML file, resolving relative paths against the repo root."""
    resolved = Path(path)
    if not resolved.is_absolute():
        resolved = REPO_ROOT / resolved

    if not resolved.is_file():
        raise FileNotFoundError(f"YAML file not found: {resolved}")

    with resolved.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def utc_now() -> datetime:
    """Timezone-aware UTC now.

    Not datetime.utcnow(): that returns a naive datetime and is deprecated since
    Python 3.12. Naive timestamps are the usual root cause of off-by-one-day bugs
    once the data reaches BigQuery.
    """
    return datetime.now(timezone.utc)
