"""TradingEconomics page loader (HTML scraping).

Ported from the_trimarket_crew's pbc_m2_loader.py, for series that have no live
official API we can use. It reads the summary sentence TradingEconomics puts on every
indicator page, e.g.:

    "Money Supply M2 in China increased to 356808.36 CNY Billion in August from
     355507.72 CNY Billion in July of 2026."

and the headline sentence that carries the year of the latest month:

    "... rose 7.5% year-on-year to CNY 356.808 trillion in August 2026 ..."

Three deliberate differences from upstream, all forced by the raw-layer contract:

1. No unit conversion. Upstream turned billions into trillions; the value is stored
   exactly as the sentence gives it, in the unit configured for the indicator.
2. No month shift. Upstream stored August's value as September. Here a monthly value
   is anchored to the first day of the month it refers to, like FRED's M2SL and the
   ECB's M3, so all monthly money supply series line up.
3. Both months in the sentence are returned, not only the latest, so a missed run
   does not lose a month.

There is no history: the page only exposes the last two months. The series builds
up from the first run onwards.

Scraping, not an API: if TradingEconomics rewrites that sentence, the regex stops
matching and the loader raises -- by design, so the daily job fails loudly instead of
landing nothing in silence.
"""

import calendar
import logging
import re
from datetime import date

import requests
from bs4 import BeautifulSoup

from services.etl_pipeline.sources.base_loader import BaseDataLoader

logger = logging.getLogger(__name__)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}

MONTHS = {name.lower(): number for number, name in enumerate(calendar.month_name) if name}

NUMBER = r"([\d,]+(?:\.\d+)?)"


class TradingEconomicsLoader(BaseDataLoader):
    def __init__(
        self,
        signal_name,
        url,
        value_label,
        data_type="metric",
        market_type="macro",
        metric_code=None,
        metric_family_code="macro",
        unit=None,
        timeframe_name="1mo",
        source_code="tradingeconomics",
        source_name="TradingEconomics",
        asset_code=None,
        start_date=None,
        end_date=None,
    ):
        super().__init__(signal_name, start_date=start_date, end_date=end_date)

        self.url = url
        # The unit text as it appears in the sentence, e.g. "CNY Billion".
        self.value_label = value_label

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
    # Fetching + parsing
    # -----------------------------

    def fetch_raw_data(self):
        """Return the page as plain text with whitespace collapsed."""
        resp = requests.get(self.url, headers=HEADERS, timeout=30)
        if not resp.ok:
            raise ValueError(
                f"TradingEconomics returned HTTP {resp.status_code} for {self.url}"
            )
        text = BeautifulSoup(resp.text, "html.parser").get_text(" ")
        return " ".join(text.split())

    def _parse(self, text):
        """Extract [(YYYY-MM-01, value, sentence), ...] for the last two months."""
        label = re.escape(self.value_label)
        summary = re.search(
            rf"(?:increased|decreased|rose|fell|remained unchanged)\s+(?:to|at)\s+"
            rf"{NUMBER}\s+{label}\s+in\s+(\w+)\s+from\s+{NUMBER}\s+{label}\s+in\s+(\w+)",
            text,
            re.IGNORECASE,
        )
        if not summary:
            raise ValueError(
                f"{self.signal_name}: summary sentence not found on {self.url}. "
                f"TradingEconomics may have changed the page."
            )

        latest_value, latest_month, previous_value, previous_month = summary.groups()
        latest_num = MONTHS.get(latest_month.lower())
        previous_num = MONTHS.get(previous_month.lower())
        if not latest_num or not previous_num:
            raise ValueError(
                f"{self.signal_name}: unexpected month names "
                f"{latest_month!r}/{previous_month!r} on {self.url}"
            )

        # The summary sentence's trailing "of YYYY" is ambiguous across a year
        # boundary, so the year comes from the headline, which states it next to the
        # latest month ("... in August 2026").
        headline = re.search(rf"\bin\s+{latest_month}\s+(\d{{4}})\b", text)
        if not headline:
            raise ValueError(
                f"{self.signal_name}: could not find the year of {latest_month} "
                f"on {self.url}"
            )
        latest_year = int(headline.group(1))
        previous_year = latest_year - 1 if previous_num > latest_num else latest_year

        sentence = summary.group(0)
        return [
            (date(previous_year, previous_num, 1).isoformat(), previous_value, sentence),
            (date(latest_year, latest_num, 1).isoformat(), latest_value, sentence),
        ]

    def _build_payload(self, obs_date, value_str, sentence):
        raw_observation = {"url": self.url, "sentence": sentence}
        return self.build_metric_payload(
            obs_date, float(value_str.replace(",", "")), raw_observation
        )

    # -----------------------------
    # BaseDataLoader hooks
    # -----------------------------

    def get_data(self, start_date=None, end_date=None):
        """The last two months on the page, kept only if they fall in the range.

        The range is compared by month, so a window that starts mid-month still
        includes that month's observation (same rule as the ECB loader).
        """
        observations = self._parse(self.fetch_raw_data())

        effective_start = start_date or self.start_date
        effective_end = end_date or self.end_date
        first = str(effective_start)[:7] if effective_start else None
        last = str(effective_end)[:7] if effective_end else None

        payloads = [
            self._build_payload(obs_date, value, sentence)
            for obs_date, value, sentence in observations
            if (not first or obs_date[:7] >= first) and (not last or obs_date[:7] <= last)
        ]

        # No range (--backfill, since there is no backfill_start_date) means both
        # months: they are all the history the page has.
        return payloads
