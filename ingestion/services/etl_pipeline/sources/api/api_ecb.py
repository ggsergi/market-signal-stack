"""ECB Data Portal API loader.

- No date range: returns the latest observation as a single payload dict.
- With a date range: returns a list of payload dicts, one per observation.

Same shape as api_fred.py. The ECB API is public and needs no key. A series is
addressed by its dataflow (e.g. "BSI") plus its series key within that dataflow
(e.g. "M.U2.Y.V.M30.X.1.U2.2300.Z01.E" for euro area M3).

Monthly series are keyed by period ("2026-07"). They are anchored to the first day
of the month, the same convention FRED uses for M2SL, so monthly metrics from both
sources line up on the same event_time.
"""

import csv
import io
import logging
import time
from datetime import date

import requests

from services.etl_pipeline.sources.base_loader import BaseDataLoader

logger = logging.getLogger(__name__)

ECB_DATA_URL = "https://data-api.ecb.europa.eu/service/data/{flow}/{series_key}"

# Same retry policy as the FRED loader: transient 5xx and rate limits are retried,
# anything else fails straight away.
MAX_ATTEMPTS = 4
BACKOFF_SECONDS = 2
RETRYABLE_STATUS = {429, 500, 502, 503, 504}


class EcbSeriesLoader(BaseDataLoader):
    def __init__(
        self,
        signal_name,
        flow,
        series_key,
        data_type="metric",
        market_type="macro",
        metric_code=None,
        metric_family_code="macro",
        unit=None,
        timeframe_name="1mo",
        source_code="ecb",
        source_name="ECB",
        asset_code=None,
        start_date=None,
        end_date=None,
    ):
        super().__init__(signal_name, start_date=start_date, end_date=end_date)

        self.flow = flow
        self.series_key = series_key

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

    @staticmethod
    def _to_period(date_value):
        """YYYY-MM-DD -> YYYY-MM, the period format the API filters on.

        Truncating the start date to its month means the window always includes the
        month it starts in, so a monthly observation is never skipped just because
        the window began after the 1st.
        """
        if not date_value:
            return None
        return str(date_value)[:7]

    @staticmethod
    def _period_to_date(period):
        """'2026-07' -> '2026-07-01'. Daily periods pass through unchanged."""
        if len(period) == 7:
            return date.fromisoformat(f"{period}-01").isoformat()
        return period

    def _request_observations(self, **params):
        """Call the data endpoint and return the observations as CSV row dicts.

        An empty body with HTTP 200 is how the API says "no observations in that
        range" -- a normal outcome for a monthly series between publications.
        """
        url = ECB_DATA_URL.format(flow=self.flow, series_key=self.series_key)
        query = {"format": "csvdata", "detail": "dataonly", **params}

        last_error = None
        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                resp = requests.get(url, params=query, timeout=30)
            except (requests.ConnectionError, requests.Timeout) as exc:
                last_error = str(exc)
            else:
                if resp.status_code not in RETRYABLE_STATUS:
                    if not resp.ok:
                        raise ValueError(
                            f"ECB API error for {self.flow}.{self.series_key}: "
                            f"HTTP {resp.status_code} {resp.text[:200]}"
                        )
                    if not resp.text.strip():
                        return []
                    return list(csv.DictReader(io.StringIO(resp.text)))

                last_error = f"HTTP {resp.status_code}"

            if attempt < MAX_ATTEMPTS:
                delay = BACKOFF_SECONDS * (2 ** (attempt - 1))
                logger.warning(
                    "%s.%s: %s (attempt %d/%d), retrying in %ds",
                    self.flow,
                    self.series_key,
                    last_error,
                    attempt,
                    MAX_ATTEMPTS,
                    delay,
                )
                time.sleep(delay)

        raise ValueError(
            f"ECB API unreachable for {self.flow}.{self.series_key} after "
            f"{MAX_ATTEMPTS} attempts: {last_error}"
        )

    def _build_payload(self, obs):
        """Build the payload for one observation, keeping the original row.

        Returns None for a missing value: an empty OBS_VALUE is an absence, not a
        zero.
        """
        period = obs.get("TIME_PERIOD")
        value_str = obs.get("OBS_VALUE")
        if not period or value_str in (None, ""):
            return None
        try:
            value = float(value_str)
        except ValueError:
            return None

        raw_observation = {
            "flow": self.flow,
            "series_key": self.series_key,
            "TIME_PERIOD": period,
            "OBS_VALUE": value_str,
        }
        return self.build_metric_payload(
            self._period_to_date(period), value, raw_observation
        )

    # -----------------------------
    # BaseDataLoader hooks
    # -----------------------------

    def fetch_raw_data(self):
        """Fetch the newest observation."""
        return self._request_observations(lastNObservations=1)

    def get_data(self, start_date=None, end_date=None):
        """Latest observation, or every observation in the given range."""
        effective_start = start_date or self.start_date
        effective_end = end_date or self.end_date

        if not effective_start and not effective_end:
            for obs in self.fetch_raw_data():
                payload = self._build_payload(obs)
                if payload:
                    return payload
            raise ValueError(
                f"No valid latest observation for {self.flow}.{self.series_key}"
            )

        params = {}
        if effective_start:
            params["startPeriod"] = self._to_period(effective_start)
        if effective_end:
            params["endPeriod"] = self._to_period(effective_end)

        observations = self._request_observations(**params)
        payloads = [p for p in (self._build_payload(o) for o in observations) if p]

        if not payloads:
            logger.info(
                "%s.%s: no observations between %s and %s.",
                self.flow,
                self.series_key,
                effective_start,
                effective_end or "today",
            )

        return payloads
