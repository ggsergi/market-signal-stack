"""Farside Investors ETF flow loader (HTML scraping).

Ported from the_trimarket_crew's farside_etf_flow.py. Reads the "all data" page,
which holds every trading day since the US spot ETFs launched (2024-01-11), one row
per day: a date, one column per ETF and a Total, in US$ millions, with negatives in
parentheses ("(95.1)") and "-" for no figure.

Differences from upstream:

1. Plain requests instead of Playwright: the page is served without a browser
   challenge, so a headless Chromium in GitHub Actions is not needed.
2. The page's markup leaves rows unclosed, so parsing by <tr> merges them. Cells
   are read in document order and regrouped by the header's column count instead.
3. Every dated row is stored as published, including US market holidays, where
   Farside shows "-" for every ETF and 0.0 as Total. Telling a holiday from a flat
   day is left to the marts; the per-ETF nulls in the payload make it possible.
4. The per-ETF breakdown is kept in the payload, so it can be modeled later without
   re-scraping; only the Total is the row's value.

Scraping, not an API: if Farside changes the table, the loader raises instead of
landing nothing in silence.
"""

import logging
from datetime import datetime

import requests
from bs4 import BeautifulSoup

from services.etl_pipeline.sources.base_loader import BaseDataLoader

logger = logging.getLogger(__name__)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}

TOTAL_COLUMN = "Total"


class FarsideEtfFlowLoader(BaseDataLoader):
    def __init__(
        self,
        signal_name,
        url,
        data_type="metric",
        market_type="crypto",
        metric_code=None,
        metric_family_code="flows",
        unit=None,
        timeframe_name="1d",
        source_code="farside",
        source_name="Farside Investors",
        asset_code=None,
        start_date=None,
        end_date=None,
    ):
        super().__init__(signal_name, start_date=start_date, end_date=end_date)

        self.url = url

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
        resp = requests.get(self.url, headers=HEADERS, timeout=60)
        if not resp.ok:
            raise ValueError(f"Farside returned HTTP {resp.status_code} for {self.url}")
        return resp.text

    @staticmethod
    def _parse_date(token):
        try:
            return datetime.strptime(token, "%d %b %Y").date()
        except ValueError:
            return None

    @staticmethod
    def _parse_number(token):
        """'1,234.5' -> 1234.5, '(19.3)' -> -19.3, '-' or '' -> None."""
        cleaned = token.replace(",", "").strip()
        if cleaned in ("", "-"):
            return None
        negative = cleaned.startswith("(") and cleaned.endswith(")")
        value = float(cleaned.strip("()"))
        return -value if negative else value

    def _parse(self, html):
        """[(date, total, {etf: value}), ...] for every trading day on the page."""
        table = BeautifulSoup(html, "html.parser").select_one("table.etf")
        if table is None:
            raise ValueError(f"{self.signal_name}: ETF table not found on {self.url}")

        header = [th.get_text(" ", strip=True) for th in table.select("thead th")]
        if len(header) < 3 or header[0] != "Date" or header[-1] != TOTAL_COLUMN:
            raise ValueError(
                f"{self.signal_name}: unexpected table header {header} on {self.url}"
            )
        etfs = header[1:-1]
        width = len(header)

        cells = [td.get_text(" ", strip=True) for td in table.select("tbody td")]
        rows = []
        index = 0
        while index < len(cells):
            day = self._parse_date(cells[index])
            if day is None:
                # Summary rows (Total, Average, Maximum, Minimum) close the table.
                break
            chunk = cells[index : index + width]
            if len(chunk) < width:
                raise ValueError(f"{self.signal_name}: truncated row for {day} on {self.url}")

            per_etf = {etf: self._parse_number(v) for etf, v in zip(etfs, chunk[1:-1])}
            total = self._parse_number(chunk[-1])
            # A row without a Total has no value to store (raw rows require one).
            if total is not None:
                rows.append((day, total, per_etf))
            index += width

        if not rows:
            raise ValueError(f"{self.signal_name}: no flow rows parsed on {self.url}")
        return rows

    def _build_payload(self, day, total, per_etf):
        raw_observation = {"url": self.url, "total": total, "etfs": per_etf}
        return self.build_metric_payload(day.isoformat(), total, raw_observation)

    # -----------------------------
    # BaseDataLoader hooks
    # -----------------------------

    def get_data(self, start_date=None, end_date=None):
        """Latest trading day, or every trading day in the given range."""
        rows = self._parse(self.fetch_raw_data())

        effective_start = start_date or self.start_date
        effective_end = end_date or self.end_date

        if not effective_start and not effective_end:
            return self._build_payload(*max(rows, key=lambda r: r[0]))

        first = str(effective_start)[:10] if effective_start else None
        last = str(effective_end)[:10] if effective_end else None
        return [
            self._build_payload(day, total, per_etf)
            for day, total, per_etf in rows
            if (not first or day.isoformat() >= first) and (not last or day.isoformat() <= last)
        ]
