"""Yahoo Finance loader.

Ported from the_trimarket_crew. Differences, all forced by the raw-layer contract:

1. No rounding. Upstream applies round(value, 2) when building the payload, which is a
   transformation and has no place in raw. See base_loader.py.

2. The original observation travels as `raw_observation` so it lands in the `payload`
   column and can be reprocessed without hitting Yahoo again.

3. market_type and unit are required. Upstream did not carry them; the raw contract and
   services/vocab.py both do.

4. Only data_type="metric". Upstream also emits OHLCV payloads for data_type="asset",
   which belong in raw_ohlcv -- a table this repo has not created yet. Adding assets
   means adding that table first, not widening this loader.

Yahoo has no API key and no documented contract: it is a scraped endpoint that yfinance
wraps. Treat any schema surprise here as expected maintenance, not as a bug in the
pipeline.
"""

import logging
from datetime import datetime, timedelta

import pandas as pd
import yfinance as yf

from services.etl_pipeline.sources.base_loader import BaseDataLoader

logger = logging.getLogger(__name__)


class YahooIndexLoader(BaseDataLoader):
    def __init__(
        self,
        signal_name,
        ticker,
        data_type="metric",
        market_type="index",
        metric_code=None,
        metric_family_code="macro",
        unit="index",
        timeframe_name="1d",
        interval="1d",
        price_field="Close",
        period="1y",
        source_code="yahoo",
        source_name="Yahoo Finance",
        asset_code=None,
        start_date=None,
        end_date=None,
    ):
        super().__init__(signal_name, start_date=start_date, end_date=end_date)

        if data_type != "metric":
            raise ValueError(
                f"{signal_name}: only data_type='metric' is supported. OHLCV rows "
                f"need raw_ohlcv, which does not exist yet."
            )

        self.ticker = ticker
        self.interval = interval
        self.price_field = price_field
        self.period = period

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
    # Fetching
    # -----------------------------

    def _download(self, **kwargs):
        """Call yfinance and hand back a frame with plain column names.

        auto_adjust is pinned explicitly: yfinance flipped its default, and letting it
        drift would silently change Close from raw to dividend-adjusted -- a different
        number in the same column, which is the kind of break nothing here would catch.

        Columns are flattened because yfinance returns a MultiIndex even for a single
        ticker, so row["Close"] would otherwise miss.
        """
        data = yf.download(
            self.ticker,
            interval=self.interval,
            progress=False,
            auto_adjust=False,
            **kwargs,
        )
        if data is None or data.empty:
            return None

        if isinstance(data.columns, pd.MultiIndex):
            data.columns = data.columns.get_level_values(0)
        return data

    def fetch_raw_data(self):
        return self._download(period=self.period)

    # -----------------------------
    # Parsing
    # -----------------------------

    @staticmethod
    def _to_date_str(index_value) -> str:
        if isinstance(index_value, datetime):
            return index_value.strftime("%Y-%m-%d")
        return str(index_value).split()[0]

    @staticmethod
    def _to_float(value):
        """Return a plain float, or None if the cell has no usable number.

        None and not 0.0: Yahoo leaves NaN on holidays, and a 0.0 close would be
        indistinguishable from a real crash once it reaches the table.
        """
        if value is None or pd.isna(value):
            return None
        try:
            return float(value.item() if hasattr(value, "item") else value)
        except (TypeError, ValueError):
            return None

    def _build_payload(self, index_value, row):
        value = self._to_float(row.get(self.price_field))
        if value is None:
            return None

        raw_observation = {"ticker": self.ticker, "date": self._to_date_str(index_value)}
        for column in ("Open", "High", "Low", "Close", "Adj Close", "Volume"):
            cell = self._to_float(row.get(column))
            if cell is not None:
                raw_observation[column] = cell

        return self.build_metric_payload(
            self._to_date_str(index_value), value, raw_observation
        )

    # -----------------------------
    # BaseDataLoader hooks
    # -----------------------------

    def get_data(self, start_date=None, end_date=None):
        """Latest observation, or every valid observation in the given range."""
        effective_start = start_date or self.start_date
        effective_end = end_date or self.end_date

        if not effective_start and not effective_end:
            data = self.fetch_raw_data()
            if data is None:
                raise ValueError(f"No data available for ticker {self.ticker}")
            index_value = data.index[-1]
            payload = self._build_payload(index_value, data.iloc[-1])
            if not payload:
                raise ValueError(f"No valid latest observation for {self.ticker}")
            return payload

        # Yahoo treats `end` as exclusive, so asking for a single day returns nothing.
        # Shifting it by one turns the range into the inclusive one the caller meant.
        end_exclusive = None
        if effective_end:
            end_exclusive = (
                datetime.fromisoformat(str(effective_end)).date() + timedelta(days=1)
            ).isoformat()

        data = self._download(start=effective_start, end=end_exclusive)
        if data is None:
            logger.warning(
                "%s: no observations between %s and %s.",
                self.ticker,
                effective_start,
                effective_end or "today",
            )
            return []

        payloads = []
        for index_value, row in data.iterrows():
            payload = self._build_payload(index_value, row)
            if payload:
                payloads.append(payload)

        skipped = len(data) - len(payloads)
        if skipped:
            logger.info("%s: skipped %d row(s) with no value.", self.ticker, skipped)
        return payloads
