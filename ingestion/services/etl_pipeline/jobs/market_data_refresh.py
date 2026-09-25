"""Run the market-data loaders and land their output in the raw layer.

Flow:
  1) Build loaders from config/sources.yaml
  2) Run each loader (always in range mode -- see below)
  3) Map payloads to raw rows
  4) One batched upsert into raw_market_metrics

Two design notes:

* Always range mode. Upstream has a "latest only" path that fetches the newest
  observation; here every run asks for a window, so backfill and incremental share a
  single code path. Fewer branches, and the result is idempotent either way.

* Persistence is batched. Upstream issues one statement per payload, which is fine in
  Postgres and unusable in BigQuery -- a yield backfill would be ~4,000 DML
  statements. All rows from all loaders go in one batch.
"""

import argparse
import logging
from datetime import timedelta

from services.data_access import GeneralQueries
from services.etl_pipeline.loader_factory import SOURCES_PATH, build_loaders_from_sources_yaml
from services.etl_pipeline.transforms.to_raw_rows import to_raw_rows
from services.utils import load_yaml, utc_now

logger = logging.getLogger(__name__)

# Only a floor for a sources.yaml with no settings block. The real default lives in
# the YAML, because how far back a run reaches is configuration, not code.
FALLBACK_WINDOW_DAYS = 30


def ensure_list(value):
    return value if isinstance(value, list) else [value]


def configured_window_days() -> int:
    settings = load_yaml(SOURCES_PATH).get("settings") or {}
    return int(settings.get("incremental_window_days") or FALLBACK_WINDOW_DAYS)


def window_start_date(days: int) -> str:
    """First day of a rolling window of `days` days ending today.

    Inclusive of today, hence days - 1: --days 1 must mean "today only", which is the
    reading anyone typing it expects.
    """
    if days < 1:
        raise ValueError(f"The window must be at least 1 day, got {days}.")
    return (utc_now() - timedelta(days=days - 1)).date().isoformat()


def run_job(
    persist=False,
    selected_indicators=None,
    backfill=False,
    days=None,
    start_date=None,
    end_date=None,
):
    """Execute the loaders and optionally persist.

    Returns (rows, failed): the raw rows produced and the names of the loaders that
    raised.

    Window precedence, widest override first:
      --backfill  -> backfill_start_date from the YAML, the full history
      start_date  -> explicit date, overrides everything below
      days        -> rolling window of N days ending today
      the YAML    -> per-indicator start_date, else settings.incremental_window_days
    """
    loaders = build_loaders_from_sources_yaml(
        only_indicators=selected_indicators, backfill=backfill
    )
    if not loaders:
        logger.warning("No loaders matched the selection.")
        return [], []

    fallback_start = None if backfill else window_start_date(
        days or configured_window_days()
    )
    all_rows = []
    failed = []

    for loader in loaders:
        try:
            # An explicit --start-date is an instruction for this run and outranks the
            # per-indicator start_date in the YAML. Without it the indicator wins, and
            # the rolling window is only the fallback.
            start = start_date or loader.start_date or fallback_start
            payloads = ensure_list(
                loader.get_data(start_date=start, end_date=end_date or loader.end_date)
            )
            rows = to_raw_rows(payloads)

            logger.info(
                "%s: %d row(s) from %s onwards",
                loader.signal_name,
                len(rows),
                start or "the beginning of the series",
            )
            all_rows.extend(rows)

        except Exception:
            # One failing source must not abort the others: a partial run is more
            # useful than no run, and the MERGE makes a later retry harmless.
            logger.exception("Loader %s failed. Continuing...", loader.signal_name)
            failed.append(loader.signal_name)
            continue

    if not persist:
        return all_rows, failed

    if not all_rows:
        logger.warning("Nothing to persist.")
        return all_rows, failed

    queries = GeneralQueries()
    queries.upsert_market_metrics(all_rows)
    return all_rows, failed


# -----------------------------
# CLI
# -----------------------------


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run market-data loaders and land them in the raw layer."
    )
    parser.add_argument(
        "--persist",
        action="store_true",
        help="Write to BigQuery. Without it, the run is a dry preview.",
    )
    parser.add_argument(
        "--indicator",
        action="append",
        dest="indicators",
        help="Run only the given indicator(s). Repeatable.",
    )
    parser.add_argument(
        "--days",
        type=int,
        metavar="N",
        help=(
            "Download the last N days, ending today (1 = today only). Overrides "
            "settings.incremental_window_days in sources.yaml for this run."
        ),
    )
    parser.add_argument(
        "--start-date",
        metavar="YYYY-MM-DD",
        help="Explicit start date. Overrides --days and any start_date in the YAML.",
    )
    parser.add_argument(
        "--end-date",
        metavar="YYYY-MM-DD",
        help="Explicit end date. Defaults to today.",
    )
    parser.add_argument(
        "--backfill",
        action="store_true",
        help=(
            "Use backfill_start_date from sources.yaml instead of the rolling "
            "window, downloading the full history."
        ),
    )

    args = parser.parse_args()

    # Caught here rather than silently resolved: --backfill with --days is not a
    # preference to rank, it is two contradictory instructions in one command.
    if args.backfill and (args.days or args.start_date):
        parser.error("--backfill cannot be combined with --days or --start-date.")
    if args.days is not None and args.days < 1:
        parser.error("--days must be at least 1.")

    return args


def main():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = parse_args()

    rows, failed = run_job(
        persist=args.persist,
        selected_indicators=args.indicators,
        backfill=args.backfill,
        days=args.days,
        start_date=args.start_date,
        end_date=args.end_date,
    )

    if not args.persist:
        print(f"\nPreview mode: {len(rows)} row(s), nothing written.\n")
        for row in rows[:5]:
            print(row)
        if len(rows) > 5:
            print(f"... and {len(rows) - 5} more")

    # Checked last, after the working sources have been persisted: a partial run is
    # still worth landing, but a scheduler must see it as a failure.
    if failed:
        logger.error("%d loader(s) failed: %s", len(failed), ", ".join(failed))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
