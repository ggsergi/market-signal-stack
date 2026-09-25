"""Entry point for the ETL jobs.

Usage:
    # dry run, nothing written
    python scripts/run_jobs.py --indicator yield_2y --indicator yield_10y

    # full history
    python scripts/run_jobs.py --indicator yield_2y --indicator yield_10y --backfill --persist

    # daily incremental (rolling 30-day window)
    python scripts/run_jobs.py --persist
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.etl_pipeline.jobs.market_data_refresh import main  # noqa: E402

if __name__ == "__main__":
    main()
