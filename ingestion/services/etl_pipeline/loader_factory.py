"""Build loaders from config/sources.yaml.

Ported from the_trimarket_crew. Adding a provider means adding a branch here and a
module under sources/; it never means touching data_access/ or creating a new raw
table.
"""

import os
from pathlib import Path

from services.etl_pipeline.sources.api.api_ecb import EcbSeriesLoader
from services.etl_pipeline.sources.api.api_fred import FredSeriesLoader
from services.etl_pipeline.sources.api.api_yahoo import YahooIndexLoader
from services.utils import REPO_ROOT, load_yaml

SOURCES_PATH = "config/sources.yaml"

FREQ_TO_TIMEFRAME = {
    "daily": "1d",
    "weekly": "1wk",
    "monthly": "1mo",
}


def freq_to_timeframe(freq):
    """Map a frequency string to a timeframe name."""
    if not freq:
        return None
    return FREQ_TO_TIMEFRAME.get(freq.strip().lower())


FRED_KEY_FILE = "config/fred_api_key.txt"
FRED_KEY_PLACEHOLDER = "PASTE_YOUR_FRED_API_KEY_HERE"


def fred_api_key() -> str:
    """Resolve the FRED API key: env var first, then config/fred_api_key.txt.

    The file may carry comments, so the key is the first line that is neither blank
    nor a comment. The placeholder is rejected explicitly: otherwise it would travel
    to FRED and come back as an opaque 400, which reads like a broken loader rather
    than an unconfigured one.
    """
    env_key = os.environ.get("FRED_API_KEY")
    if env_key and env_key.strip():
        return env_key.strip()

    key_file = Path(REPO_ROOT) / FRED_KEY_FILE
    if key_file.is_file():
        for line in key_file.read_text(encoding="utf-8").splitlines():
            candidate = line.strip()
            if not candidate or candidate.startswith("#"):
                continue
            if candidate == FRED_KEY_PLACEHOLDER:
                raise ValueError(
                    f"{FRED_KEY_FILE} still contains the placeholder. "
                    f"Replace it with your key -- get one free at "
                    f"https://fredaccount.stlouisfed.org/apikeys"
                )
            return candidate

    raise ValueError(
        f"FRED API key not found. Set the FRED_API_KEY environment variable or put "
        f"the key in {FRED_KEY_FILE} (get one free at "
        f"https://fredaccount.stlouisfed.org/apikeys)."
    )


def build_loaders_from_sources_yaml(
    path=SOURCES_PATH, only_indicators=None, backfill=False
):
    """Build loaders from the YAML configuration.

    :param only_indicators: iterable of indicator names to build; all if omitted.
    :param backfill: use backfill_start_date instead of start_date, to download the
                     full historical series.
    """
    cfg = load_yaml(path)
    providers = cfg.get("providers", {})
    indicators = cfg.get("indicators", {})
    loaders = []

    selected = set(only_indicators) if only_indicators else None
    if selected:
        unknown = selected - set(indicators)
        if unknown:
            raise ValueError(
                f"Unknown indicator(s): {sorted(unknown)}. "
                f"Available: {sorted(indicators)}"
            )

    for signal_name, signal_cfg in indicators.items():
        if selected and signal_name not in selected:
            continue

        provider = signal_cfg.get("provider")
        if not provider:
            raise ValueError(f"Signal '{signal_name}' is missing 'provider'")

        defaults = providers.get(provider, {}).get("defaults", {})
        config = {**defaults, **signal_cfg}

        timeframe = freq_to_timeframe(config.get("frequency")) or config.get(
            "timeframe_name"
        )
        start_date = (
            config.get("backfill_start_date") or config.get("start_date")
            if backfill
            else config.get("start_date")
        )

        if provider == "fred":
            if not config.get("series_id"):
                raise ValueError(
                    f"Signal '{signal_name}' is missing 'series_id' for provider fred"
                )

            loaders.append(
                FredSeriesLoader(
                    signal_name=signal_name,
                    series_id=config["series_id"],
                    api_key=fred_api_key(),
                    data_type=config.get("data_type", "metric"),
                    market_type=config.get("market_type", "macro"),
                    metric_code=config.get("metric_code"),
                    metric_family_code=config.get("metric_family_code"),
                    unit=config.get("unit"),
                    timeframe_name=timeframe,
                    source_code=config.get("source_code", "fred"),
                    source_name=config.get("source_name", "FRED"),
                    asset_code=config.get("asset_code"),
                    start_date=start_date,
                    end_date=config.get("end_date"),
                )
            )
        elif provider == "yahoo":
            if not config.get("ticker"):
                raise ValueError(
                    f"Signal '{signal_name}' is missing 'ticker' for provider yahoo"
                )

            loaders.append(
                YahooIndexLoader(
                    signal_name=signal_name,
                    ticker=config["ticker"],
                    data_type=config.get("data_type", "metric"),
                    market_type=config.get("market_type", "index"),
                    metric_code=config.get("metric_code"),
                    metric_family_code=config.get("metric_family_code"),
                    unit=config.get("unit"),
                    timeframe_name=timeframe,
                    interval=config.get("interval", "1d"),
                    price_field=config.get("price_field", "Close"),
                    period=config.get("period", "1y"),
                    source_code=config.get("source_code", "yahoo"),
                    source_name=config.get("source_name", "Yahoo Finance"),
                    asset_code=config.get("asset_code"),
                    start_date=start_date,
                    end_date=config.get("end_date"),
                )
            )

        elif provider == "ecb":
            if not config.get("flow") or not config.get("series_key"):
                raise ValueError(
                    f"Signal '{signal_name}' needs 'flow' and 'series_key' for "
                    f"provider ecb"
                )

            loaders.append(
                EcbSeriesLoader(
                    signal_name=signal_name,
                    flow=config["flow"],
                    series_key=config["series_key"],
                    data_type=config.get("data_type", "metric"),
                    market_type=config.get("market_type", "macro"),
                    metric_code=config.get("metric_code"),
                    metric_family_code=config.get("metric_family_code"),
                    unit=config.get("unit"),
                    timeframe_name=timeframe,
                    source_code=config.get("source_code", "ecb"),
                    source_name=config.get("source_name", "ECB"),
                    asset_code=config.get("asset_code"),
                    start_date=start_date,
                    end_date=config.get("end_date"),
                )
            )

        else:
            raise ValueError(
                f"Unsupported provider '{provider}' for signal '{signal_name}'. "
                f"Supported: 'fred', 'yahoo', 'ecb'."
            )

    return loaders
