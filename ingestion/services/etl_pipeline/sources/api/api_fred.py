"""FRED (Federal Reserve Economic Data) API loader.

- No date range: returns the latest valid observation as a single payload dict.
- With a date range: returns a list of payload dicts, one per valid observation.

Ported from the_trimarket_crew. Changes are documented in base_loader.py, plus one
here: an empty range no longer raises. A daily incremental run over a weekend or a
holiday legitimately returns nothing, and turning that into an exception would make
the cron log errors on every non-business day.
"""

import logging
import time

import requests

from services.etl_pipeline.sources.base_loader import BaseDataLoader

logger = logging.getLogger(__name__)

FRED_OBSERVATIONS_URL = "https://api.stlouisfed.org/fred/series/observations"

# FRED returns transient 502/503 under load. Without retries a single blip aborts a
# whole backfill, and a nightly cron logs a failure for a problem that fixes itself.
MAX_ATTEMPTS = 4
BACKOFF_SECONDS = 2
RETRYABLE_STATUS = {429, 500, 502, 503, 504}


class FredSeriesLoader(BaseDataLoader):
    def __init__(
        self,
        signal_name,
        series_id,
        api_key,
        data_type="metric",
        market_type="macro",
        metric_code=None,
        metric_family_code="macro",
        unit="percent",
        timeframe_name="1d",
        source_code="fred",
        source_name="FRED",
        asset_code=None,
        start_date=None,
        end_date=None,
    ):
        super().__init__(signal_name, start_date=start_date, end_date=end_date)

        self.series_id = series_id
        self.api_key = api_key

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

    def _redact(self, text) -> str:
        """Strip the API key from anything user-visible.

        FRED takes the key as a query parameter, so it appears verbatim in every URL
        and therefore in every traceback and log line. Redacting here keeps it out of
        anything that might get pasted into a ticket or a chat.
        """
        return str(text).replace(self.api_key, "***")

    def _request_observations(
        self, sort_order, limit=None, observation_start=None, observation_end=None
    ):
        """Call the FRED observations endpoint and return the observations list.

        Retries transient failures with exponential backoff. A 400 is not retried:
        it means a bad series id or bad parameters, and repeating it only wastes time.
        """
        params = {
            "series_id": self.series_id,
            "api_key": self.api_key,
            "file_type": "json",
            "sort_order": sort_order,
        }
        if limit is not None:
            params["limit"] = limit
        if observation_start:
            params["observation_start"] = observation_start
        if observation_end:
            params["observation_end"] = observation_end

        last_error = None

        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                resp = requests.get(FRED_OBSERVATIONS_URL, params=params, timeout=30)
            except (requests.ConnectionError, requests.Timeout) as exc:
                last_error = self._redact(exc)
            else:
                if resp.status_code == 400:
                    # FRED returns useful error JSON for bad ids or parameters.
                    try:
                        err = resp.json()
                        msg = (
                            err.get("error_message")
                            or err.get("message")
                            or "Bad Request"
                        )
                    except Exception:
                        msg = resp.text or "Bad Request"
                    raise ValueError(
                        f"FRED API error for series '{self.series_id}': {msg}. "
                        f"Verify the series id exists and the parameters are valid."
                    )

                if resp.status_code not in RETRYABLE_STATUS:
                    if not resp.ok:
                        raise ValueError(
                            f"FRED API error for series '{self.series_id}': "
                            f"HTTP {resp.status_code}"
                        )
                    return resp.json().get("observations") or []

                last_error = f"HTTP {resp.status_code}"

            if attempt < MAX_ATTEMPTS:
                delay = BACKOFF_SECONDS * (2 ** (attempt - 1))
                logger.warning(
                    "%s: %s (attempt %d/%d), retrying in %ds",
                    self.series_id,
                    last_error,
                    attempt,
                    MAX_ATTEMPTS,
                    delay,
                )
                time.sleep(delay)

        raise ValueError(
            f"FRED API unreachable for series '{self.series_id}' after "
            f"{MAX_ATTEMPTS} attempts: {last_error}"
        )

    def _parse_observation(self, obs):
        """Convert one FRED observation into (date_str, value_float).

        Returns None when the observation is missing. FRED emits "." for days with
        no reading (weekends, holidays): those are absences, not zeros, and coercing
        them to 0 would corrupt the series in a way that is hard to spot later.
        """
        date_str = obs.get("date")
        value_str = obs.get("value")

        if not date_str or value_str in (None, ".", ""):
            return None

        try:
            return date_str, float(value_str)
        except (ValueError, TypeError):
            return None

    def _build_payload(self, obs):
        """Build the payload for one observation, keeping the original object.

        The stored observation is enriched with series_id so the row stays
        self-explanatory, and it is only this observation -- never the whole API
        response, which for a full backfill would repeat the same ~1 MB blob across
        thousands of rows.
        """
        parsed = self._parse_observation(obs)
        if not parsed:
            return None

        obs_date, value = parsed
        raw_observation = {"series_id": self.series_id, **obs}
        return self.build_metric_payload(obs_date, value, raw_observation)

    # -----------------------------
    # BaseDataLoader hooks
    # -----------------------------

    def fetch_raw_data(self):
        """Fetch the newest observations. A few, in case the latest ones are '.'."""
        return {"observations": self._request_observations(sort_order="desc", limit=5)}

    def extract_latest(self, data):
        """Pick the latest valid observation from raw data."""
        for obs in data.get("observations") or []:
            payload = self._build_payload(obs)
            if payload:
                return payload
        raise ValueError(
            f"No valid latest observation found for series {self.series_id}"
        )

    def get_data(self, start_date=None, end_date=None):
        """Latest observation, or every valid observation in the given range."""
        effective_start = start_date or self.start_date
        effective_end = end_date or self.end_date

        if not effective_start and not effective_end:
            return self.extract_latest(self.fetch_raw_data())

        observations = self._request_observations(
            sort_order="asc",
            observation_start=effective_start,
            observation_end=effective_end,
        )

        payloads = [p for p in (self._build_payload(o) for o in observations) if p]
        skipped = len(observations) - len(payloads)
        if skipped:
            logger.info(
                "%s: skipped %d observation(s) with no value.", self.series_id, skipped
            )

        if not payloads:
            logger.warning(
                "%s: no valid observations between %s and %s.",
                self.series_id,
                effective_start,
                effective_end,
            )

        return payloads
