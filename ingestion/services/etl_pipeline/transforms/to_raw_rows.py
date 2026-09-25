"""Map loader payloads to raw table rows.

This is the seam between "whatever shape a provider hands us" and "the contract of
the raw layer". It has no network and no BigQuery, so it is the one piece that can be
tested against a saved API response.
"""

import json
from datetime import datetime, timezone

from services import vocab


def _to_event_time(date_value) -> str:
    """Anchor a source date to an instant in UTC.

    FRED delivers dates, Binance delivers instants, and both land in the same
    TIMESTAMP column. The rule is: if the source gives only a date, it means
    00:00:00Z on that date.
    """
    if isinstance(date_value, datetime):
        parsed = date_value
    else:
        parsed = datetime.fromisoformat(str(date_value).split("T", 1)[0])

    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat()


def _to_ingested_at(value) -> str:
    if isinstance(value, datetime):
        stamped = value
    else:
        stamped = datetime.fromisoformat(str(value))

    if stamped.tzinfo is None:
        stamped = stamped.replace(tzinfo=timezone.utc)
    return stamped.astimezone(timezone.utc).isoformat()


def metric_payload_to_raw_row(payload: dict) -> dict:
    """Convert one metric payload into a raw_market_metrics row.

    Timestamps come out as ISO strings because that is what a JSON load job expects.
    """
    raw_observation = payload.get("raw_observation")

    row = {
        "source": payload.get("source_name"),
        "market_type": payload.get("market_type"),
        # Empty string would mean 'an asset with no name'; global metrics have no
        # asset at all.
        "asset": payload.get("asset_code") or None,
        "metric": payload.get("metric_code"),
        "metric_family": payload.get("metric_family_code"),
        "value": float(payload["number"]),
        "unit": payload.get("unit"),
        "timeframe": payload.get("timeframe_name") or None,
        "event_time": _to_event_time(payload["date"]),
        "ingested_at": _to_ingested_at(payload["fetched_at"]),
        "payload": (
            json.dumps(raw_observation, separators=(",", ":"), sort_keys=True)
            if raw_observation
            else None
        ),
    }

    vocab.validate_metric_row(row)
    return row


def to_raw_rows(payloads: list[dict]) -> list[dict]:
    """Convert a batch of metric payloads, failing fast on the first bad row."""
    rows = []
    for index, payload in enumerate(payloads):
        try:
            rows.append(metric_payload_to_raw_row(payload))
        except Exception as exc:
            raise ValueError(
                f"Payload {index} ({payload.get('signal')}) could not be mapped: {exc}"
            ) from exc
    return rows
