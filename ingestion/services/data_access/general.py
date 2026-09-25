"""Semantic operations on the raw layer.

Mirrors general.py in the_trimarket_crew, with two deliberate differences:

1. No ID resolution. get_asset() / get_metric() / get_source() / get_timeframe()
   exist upstream only to translate text into star-schema foreign keys. Our raw layer
   stores text on purpose -- that translation belongs to whoever builds the marts.

2. Batch, not row by row. Upstream persists one payload per statement, which is fine
   in Postgres and unusable in BigQuery: a yield backfill would be ~4,000 DML
   statements. Here a whole batch becomes one load job plus one MERGE.
"""

import logging
from datetime import datetime

from .bigquery_manager import BigQueryManager
from .queries_str import QueryStrs

logger = logging.getLogger(__name__)

RAW_MARKET_METRICS = "raw_market_metrics"

# Scratch space for the MERGE, not a layer: created by the load job and dropped in the
# same call.
STG_MARKET_METRICS = "stg_market_metrics"


def _as_datetime(value) -> datetime:
    """Coerce an event_time to a datetime.

    Rows carry ISO strings because that is what a JSON load job expects, while the
    MERGE parameter needs a real TIMESTAMP.
    """
    if isinstance(value, datetime):
        return value
    return datetime.fromisoformat(value)


def _metric_key(row: dict) -> tuple:
    """Natural key of a raw_market_metrics row."""
    return (
        row["source"],
        row["metric"],
        row.get("asset") or "",
        row.get("timeframe") or "",
        row["event_time"],
    )


class GeneralQueries:
    """Read/write operations shared across jobs."""

    def __init__(self, manager: BigQueryManager | None = None):
        self.manager = manager or BigQueryManager()

    # ---- market metrics: write ----

    def upsert_market_metrics(self, rows: list[dict]) -> int:
        """Upsert metric rows into raw_market_metrics. Returns rows staged.

        Load job into a scratch table, then one MERGE on the natural key: new keys are
        inserted, keys whose value changed (a source revision) are updated in place,
        and everything else is left alone. Re-running any window is harmless.
        """
        if not rows:
            logger.info("No rows to upsert.")
            return 0

        target = self.manager.raw(RAW_MARKET_METRICS)
        staging = self.manager.raw(STG_MARKET_METRICS)
        deduped = self._dedupe(rows)

        # The table's DDL is the single source of truth for the schema: reading it
        # back means the staging table can never drift from it.
        schema = self.manager.get_table(target).schema

        staged = self.manager.load_rows(
            deduped, staging, schema=schema, write_disposition="WRITE_TRUNCATE"
        )

        min_event_time = min(_as_datetime(row["event_time"]) for row in deduped)
        job = self.manager.execute(
            QueryStrs.MERGE_MARKET_METRICS.format(target=target, staging=staging),
            params={"min_event_time": min_event_time},
        )

        # Only after a successful MERGE. On failure the scratch table stays, as the
        # evidence of what was about to be written; the next run truncates it anyway.
        self.manager.drop_table(staging)

        logger.info(
            "Staged %d row(s); MERGE touched %s row(s) in %s.",
            staged,
            job.num_dml_affected_rows,
            RAW_MARKET_METRICS,
        )
        return staged

    @staticmethod
    def _dedupe(rows: list[dict]) -> list[dict]:
        """Collapse rows sharing a natural key, keeping the last occurrence.

        Required, not cosmetic: if staging holds two rows with the same key, BigQuery
        aborts the MERGE with "UPDATE/MERGE must match at most one source row for
        each target row".
        """
        unique: dict[tuple, dict] = {}
        for row in rows:
            unique[_metric_key(row)] = row

        dropped = len(rows) - len(unique)
        if dropped:
            logger.info("Dropped %d duplicate row(s) before staging.", dropped)
        return list(unique.values())
