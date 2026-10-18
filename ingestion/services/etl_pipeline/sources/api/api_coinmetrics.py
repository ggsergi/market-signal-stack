"""Coin Metrics community API loader (on-chain asset metrics).

- No date range: returns the latest observation as a single payload dict.
- With a date range: returns a list of payload dicts, one per observation.

Same shape as api_ecb.py. The community API is public and needs no key; it serves a
subset of Coin Metrics' catalog (e.g. CapMVRVCur, CapMrktCurUSD, SplyCur,
FlowInExNtv, FlowOutExNtv for BTC) and answers 403 for metrics outside it.

Daily values are timestamped at 00:00 UTC of the day they cover. Some metrics
(exchange flows) are first published as 'flash' and revised later; the rolling
ingestion window re-reads them and the MERGE picks up the revision.
"""

import logging
import time

import requests

from services.etl_pipeline.sources.base_loader import BaseDataLoader

logger = logging.getLogger(__name__)

COINMETRICS_URL = "https://community-api.coinmetrics.io/v4/timeseries/asset-metrics"

# The API's maximum page size; full BTC history (~6k days) fits in one page, and
# next_page_url is followed anyway in case it does not.
PAGE_SIZE = 10000

# Same retry policy as the FRED and ECB loaders. The community API rate-limits
# per IP, so 429 is the likely transient error.
MAX_ATTEMPTS = 4
BACKOFF_SECONDS = 2
RETRYABLE_STATUS = {429, 500, 502, 503, 504}


class CoinMetricsLoader(BaseDataLoader):
    def __init__(
        self,
        signal_name,
        metric_id,
        cm_asset="btc",
        data_type="metric",
        market_type="crypto",
        metric_code=None,
        metric_family_code="on_chain",
        unit=None,
        timeframe_name="1d",
        source_code="coinmetrics",
        source_name="Coin Metrics",
        asset_code=None,
        start_date=None,
        end_date=None,
    ):
        super().__init__(signal_name, start_date=start_date, end_date=end_date)

        # Coin Metrics' own identifiers, e.g. metric_id="CapMVRVCur", cm_asset="btc".
        self.metric_id = metric_id
        self.cm_asset = cm_asset

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

    def _get(self, url, params):
        """GET one page with retries; returns the decoded JSON body."""
        last_error = None
        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                resp = requests.get(url, params=params, timeout=30)
            except (requests.ConnectionError, requests.Timeout) as exc:
                last_error = str(exc)
            else:
                if resp.status_code not in RETRYABLE_STATUS:
                    if not resp.ok:
                        raise ValueError(
                            f"Coin Metrics API error for {self.cm_asset}/{self.metric_id}: "
                            f"HTTP {resp.status_code} {resp.text[:200]}"
                        )
                    return resp.json()

                last_error = f"HTTP {resp.status_code}"

            if attempt < MAX_ATTEMPTS:
                delay = BACKOFF_SECONDS * (2 ** (attempt - 1))
                logger.warning(
                    "%s/%s: %s (attempt %d/%d), retrying in %ds",
                    self.cm_asset,
                    self.metric_id,
                    last_error,
                    attempt,
                    MAX_ATTEMPTS,
                    delay,
                )
                time.sleep(delay)

        raise ValueError(
            f"Coin Metrics API unreachable for {self.cm_asset}/{self.metric_id} after "
            f"{MAX_ATTEMPTS} attempts: {last_error}"
        )

    def _request_observations(self, **params):
        """Return every observation for the query, following pagination."""
        query = {
            "assets": self.cm_asset,
            "metrics": self.metric_id,
            "frequency": "1d",
            **params,
        }
        body = self._get(COINMETRICS_URL, query)
        observations = list(body.get("data", []))

        # next_page_url already carries every query parameter.
        while body.get("next_page_url"):
            body = self._get(body["next_page_url"], None)
            observations.extend(body.get("data", []))

        return observations

    def _build_payload(self, obs):
        """Build the payload for one observation, keeping the original record.

        Returns None for a missing value: an absent metric on a day is not a zero.
        """
        timestamp = obs.get("time")
        value_str = obs.get(self.metric_id)
        if not timestamp or value_str in (None, ""):
            return None
        try:
            value = float(value_str)
        except ValueError:
            return None

        # The whole record, so the 'flash'/'reviewed' status travels with the value.
        return self.build_metric_payload(timestamp[:10], value, dict(obs))

    # -----------------------------
    # BaseDataLoader hooks
    # -----------------------------

    def fetch_raw_data(self):
        """Fetch the newest observation (the API pages from the end by default)."""
        return self._get(
            COINMETRICS_URL,
            {
                "assets": self.cm_asset,
                "metrics": self.metric_id,
                "frequency": "1d",
                "page_size": 1,
            },
        ).get("data", [])

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
                f"No valid latest observation for {self.cm_asset}/{self.metric_id}"
            )

        params = {"page_size": PAGE_SIZE, "paging_from": "start"}
        if effective_start:
            params["start_time"] = str(effective_start)[:10]
        if effective_end:
            params["end_time"] = str(effective_end)[:10]

        observations = self._request_observations(**params)
        payloads = [p for p in (self._build_payload(o) for o in observations) if p]

        if not payloads:
            logger.info(
                "%s/%s: no observations between %s and %s.",
                self.cm_asset,
                self.metric_id,
                effective_start,
                effective_end or "today",
            )

        return payloads
