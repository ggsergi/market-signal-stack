"""BGeometrics API loader (bitcoin-data.com, on-chain BTC metrics).

- No date range: returns the latest observation as a single payload dict.
- With a date range: returns a list of payload dicts, one per observation.

Same shape as api_coinmetrics.py. The free tier is public and needs no key, with
three limits that shape this loader:

* Requests are capped per IP (10 per hour, 15 per day), so each indicator costs
  exactly one request per run and a 429 is not retried: waiting a few seconds does
  not clear an hourly quota.
* History is a rolling window of about four years. Days that fall out of it can no
  longer be downloaded, only kept if they were ingested in time.
* Some metrics (SOPR) are served with a 7-day delay. A range that reaches into the
  delayed days simply returns fewer rows.

Each observation is a flat record such as {"d": "2026-11-19", "unixTs": ...,
"sopr": 0.9839}; `value_field` names the key that holds the metric.
"""

import logging
import time

import requests

from services.etl_pipeline.sources.base_loader import BaseDataLoader

logger = logging.getLogger(__name__)

BGEOMETRICS_URL = "https://bitcoin-data.com/v1"

# Same retry policy as the other API loaders, minus 429 (see the module docstring).
MAX_ATTEMPTS = 4
BACKOFF_SECONDS = 2
RETRYABLE_STATUS = {500, 502, 503, 504}

DATE_FIELD = "d"


class BGeometricsLoader(BaseDataLoader):
    def __init__(
        self,
        signal_name,
        endpoint,
        value_field,
        data_type="metric",
        market_type="crypto",
        metric_code=None,
        metric_family_code="on_chain",
        unit=None,
        timeframe_name="1d",
        source_code="bgeometrics",
        source_name="BGeometrics",
        asset_code=None,
        start_date=None,
        end_date=None,
    ):
        super().__init__(signal_name, start_date=start_date, end_date=end_date)

        # BGeometrics' own identifiers, e.g. endpoint="rhodl-ratio",
        # value_field="rhodlRatio".
        self.endpoint = endpoint
        self.value_field = value_field

        self.data_type = data_type
        self.market_type = market_type
        self.asset_code = asset_code
        self.metric_code = metric_code or signal_name
        self.metric_family_code = metric_family_code
        self.unit = unit
        self.timeframe_name = timeframe_name
        self.source_code = source_code
        self.source_name = source_name

    # -----------------------------
    # HTTP + parsing helpers
    # -----------------------------

    def _get(self, url, params=None):
        """GET with retries on transient errors; returns the decoded JSON body."""
        last_error = None
        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                resp = requests.get(url, params=params, timeout=30)
            except (requests.ConnectionError, requests.Timeout) as exc:
                last_error = str(exc)
            else:
                if resp.status_code == 429:
                    raise ValueError(
                        f"BGeometrics rate limit reached for {self.endpoint} "
                        f"(free tier: 10 requests/hour, 15/day per IP). "
                        f"Retry after the quota resets."
                    )
                if resp.status_code not in RETRYABLE_STATUS:
                    if not resp.ok:
                        raise ValueError(
                            f"BGeometrics API error for {self.endpoint}: "
                            f"HTTP {resp.status_code} {resp.text[:200]}"
                        )
                    return resp.json()

                last_error = f"HTTP {resp.status_code}"

            if attempt < MAX_ATTEMPTS:
                delay = BACKOFF_SECONDS * (2 ** (attempt - 1))
                logger.warning(
                    "%s: %s (attempt %d/%d), retrying in %ds",
                    self.endpoint,
                    last_error,
                    attempt,
                    MAX_ATTEMPTS,
                    delay,
                )
                time.sleep(delay)

        raise ValueError(
            f"BGeometrics API unreachable for {self.endpoint} after "
            f"{MAX_ATTEMPTS} attempts: {last_error}"
        )

    def _build_payload(self, obs):
        """Build the payload for one observation, keeping the original record.

        Returns None for a missing value: an absent metric on a day is not a zero.
        """
        obs_date = obs.get(DATE_FIELD)
        raw_value = obs.get(self.value_field)
        if not obs_date or raw_value in (None, ""):
            return None
        try:
            value = float(raw_value)
        except (TypeError, ValueError):
            return None

        # The whole record, so companion fields (e.g. rhodl1m) travel with the value.
        return self.build_metric_payload(obs_date, value, dict(obs))

    # -----------------------------
    # BaseDataLoader hooks
    # -----------------------------

    def fetch_raw_data(self):
        """Fetch the newest observation the free tier serves."""
        return self._get(f"{BGEOMETRICS_URL}/{self.endpoint}/last")

    def get_data(self, start_date=None, end_date=None):
        """Latest observation, or every observation in the given range."""
        effective_start = start_date or self.start_date
        effective_end = end_date or self.end_date

        if not effective_start and not effective_end:
            payload = self._build_payload(self.fetch_raw_data())
            if payload:
                return payload
            raise ValueError(f"No valid latest observation for {self.endpoint}")

        params = {}
        if effective_start:
            params["startday"] = str(effective_start)[:10]
        if effective_end:
            params["endday"] = str(effective_end)[:10]

        observations = self._get(f"{BGEOMETRICS_URL}/{self.endpoint}", params)
        if not isinstance(observations, list):
            raise ValueError(
                f"Unexpected BGeometrics response for {self.endpoint}: expected a "
                f"list of observations, got {type(observations).__name__}"
            )

        payloads = [p for p in (self._build_payload(o) for o in observations) if p]

        if not payloads:
            logger.info(
                "%s: no observations between %s and %s.",
                self.endpoint,
                effective_start,
                effective_end or "today",
            )

        return payloads
