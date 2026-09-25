"""Base class for source loaders.

Ported from the_trimarket_crew with three deliberate changes:

1. No rounding. Upstream applies round(value, 2) at extraction time, which turns
   funding_rate 0.00012 into 0.0 and leaves SOPR with no resolution below its own
   thresholds. Rounding is a transformation and has no place in the raw layer.

2. The source's original observation is carried through as `raw_observation`, so it
   can be stored in the `payload` column and reprocessed later without calling the
   API again.

3. datetime.now(timezone.utc) instead of datetime.utcnow(), which returns a naive
   datetime and is deprecated since Python 3.12.

Loaders never touch the database. They return payload dicts; landing them is the
job of transforms/ and data_access/.
"""

from abc import ABC, abstractmethod
from datetime import datetime

from services.utils import utc_now


class BaseDataLoader(ABC):
    """Minimal contract: fetch raw data, extract observations, return payloads."""

    def __init__(self, signal_name, start_date=None, end_date=None):
        self.signal_name = signal_name

        # Optional historical boundaries (ISO YYYY-MM-DD). When set, loaders that
        # support ranges fetch between these dates instead of only the latest point.
        self.start_date = start_date
        self.end_date = end_date

        # Common payload attributes. Subclasses override these in their own __init__
        # after calling super().__init__(). Declaring them here lets the shared
        # payload builder reference them unconditionally.
        self.data_type: str | None = None  # "asset" | "metric"
        self.market_type: str | None = None
        self.asset_code: str | None = None
        self.timeframe_name: str | None = None
        self.metric_code: str | None = None
        self.metric_family_code: str | None = None
        self.unit: str | None = None
        self.source_code: str | None = None
        self.source_name: str | None = None

    # -----------------------------
    # Hooks
    # -----------------------------

    @abstractmethod
    def fetch_raw_data(self):
        """Pull raw data from the upstream service (HTTP request, file read...)."""

    @abstractmethod
    def get_data(self, start_date=None, end_date=None):
        """Return a payload dict, or a list of them for a date range."""

    # -----------------------------
    # Helpers
    # -----------------------------

    def normalize_date(self, date_value):
        """Convert a source timestamp to YYYY-MM-DD."""
        token = date_value.split("T", 1)[0]
        try:
            return datetime.strptime(token, "%Y-%m-%d").date().isoformat()
        except ValueError:
            pass

        try:
            return (
                datetime.fromisoformat(date_value.replace("Z", "+00:00"))
                .date()
                .isoformat()
            )
        except ValueError:
            return token

    def build_metric_payload(self, obs_date, value, raw_observation=None):
        """Package one observation into the payload every metric loader returns.

        `number` keeps full precision on purpose -- see the module docstring.
        """
        return {
            "signal": self.signal_name,
            "type": "metric",
            "source_name": self.source_name,
            "source_code": self.source_code,
            "market_type": self.market_type,
            "asset_code": self.asset_code,
            "metric_code": self.metric_code,
            "metric_family_code": self.metric_family_code,
            "unit": self.unit,
            "timeframe_name": self.timeframe_name,
            "date": self.normalize_date(obs_date),
            "number": value,
            "raw_observation": raw_observation,
            "fetched_at": utc_now(),
        }
