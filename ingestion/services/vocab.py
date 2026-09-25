"""Controlled vocabulary for the raw layer.

Every ingestion module imports from here. Nobody hand-writes these literals: it is
the only way to stop 'on-chain', 'on_chain' and 'onchain' from coexisting in the same
column while no WHERE clause catches them all -- a divergence that already exists
between the README and the_trimarket_crew config.

Extending a list is cheap. What is expensive is discovering three months later that
half the rows use a different variant.
"""

# --- source -------------------------------------------------------------
# Provider proper name, keeping its own capitalization.
FRED = "FRED"
ECB = "ECB"
YAHOO_FINANCE = "Yahoo Finance"
BINANCE = "Binance"
GLASSNODE = "Glassnode"
ALTERNATIVE_ME = "Alternative.me"
FARSIDE = "Farside Investors"
BTC_MAGAZINE_PRO = "Bitcoin Magazine Pro"
TRADING_ECONOMICS = "TradingEconomics"

SOURCES = frozenset(
    {
        FRED,
        ECB,
        YAHOO_FINANCE,
        BINANCE,
        GLASSNODE,
        ALTERNATIVE_ME,
        FARSIDE,
        BTC_MAGAZINE_PRO,
        TRADING_ECONOMICS,
    }
)

# --- market_type --------------------------------------------------------
MACRO = "macro"
CRYPTO = "crypto"
INDEX = "index"
FOREX = "forex"
COMMODITY = "commodity"

MARKET_TYPES = frozenset({MACRO, CRYPTO, INDEX, FOREX, COMMODITY})

# --- metric_family ------------------------------------------------------
RATES = "rates"
INFLATION = "inflation"
LIQUIDITY = "liquidity"
# Level of a quoted instrument: index closes (SPX, NDX, DXY) and spot prices. Kept
# apart from 'macro' because these are market observations, not published statistics,
# and the marts will want to treat them differently.
PRICE = "price"
FLOWS = "flows"
ON_CHAIN = "on_chain"
SENTIMENT = "sentiment"
DERIVATIVES = "derivatives"
VOLATILITY = "volatility"
MACRO_FAMILY = "macro"

METRIC_FAMILIES = frozenset(
    {
        RATES,
        INFLATION,
        LIQUIDITY,
        PRICE,
        FLOWS,
        ON_CHAIN,
        SENTIMENT,
        DERIVATIVES,
        VOLATILITY,
        MACRO_FAMILY,
    }
)

# --- unit ---------------------------------------------------------------
PERCENT = "percent"
PERCENTAGE_POINTS = "percentage_points"
RATIO = "ratio"
USD = "usd"
USD_MILLIONS = "usd_millions"
# FRED publishes WALCL in millions and M2SL in billions. Storing both under one unit
# would need a conversion, and converting is a transformation the raw layer must not
# do -- the number has to stay exactly as the source delivered it.
USD_BILLIONS = "usd_billions"
# Euro area aggregates from the ECB come in millions of euros. Kept in euros, not
# converted to USD: converting is a transformation, and the raw layer does not do it.
EUR_MILLIONS = "eur_millions"
# China's M2 as TradingEconomics states it (PBoC figures), unconverted.
CNY_BILLIONS = "cny_billions"
INDEX_UNIT = "index"

UNITS = frozenset(
    {
        PERCENT,
        PERCENTAGE_POINTS,
        RATIO,
        USD,
        USD_MILLIONS,
        USD_BILLIONS,
        EUR_MILLIONS,
        CNY_BILLIONS,
        INDEX_UNIT,
    }
)

# --- timeframe ----------------------------------------------------------
# Same names as the_trimarket_crew, so dim_timeframe needs no translation.
TF_1M = "1m"
TF_1H = "1h"
TF_4H = "4h"
TF_1D = "1d"
TF_1WK = "1wk"
TF_1MO = "1mo"

TIMEFRAMES = frozenset({TF_1M, TF_1H, TF_4H, TF_1D, TF_1WK, TF_1MO})


def validate_metric_row(row: dict) -> None:
    """Fail during ingestion, not in the table.

    An out-of-vocabulary value that reaches BigQuery can no longer be told apart
    from a legitimate one without auditing the history by hand.
    """
    checks = (
        ("source", row.get("source"), SOURCES),
        ("market_type", row.get("market_type"), MARKET_TYPES),
        ("metric_family", row.get("metric_family"), METRIC_FAMILIES),
        ("unit", row.get("unit"), UNITS),
    )
    for field, value, allowed in checks:
        if value not in allowed:
            raise ValueError(
                f"{field}={value!r} is out of vocabulary. "
                f"Allowed: {sorted(allowed)}. "
                f"If it is legitimate, add it to services/vocab.py first."
            )

    timeframe = row.get("timeframe")
    if timeframe is not None and timeframe not in TIMEFRAMES:
        raise ValueError(
            f"timeframe={timeframe!r} is out of vocabulary. "
            f"Allowed: {sorted(TIMEFRAMES)} or None."
        )

    metric = row.get("metric")
    if not metric or metric != metric.lower():
        raise ValueError(f"metric={metric!r} must be lowercase snake_case.")

    # An empty asset is the classic mistake: it means 'an asset with no name', not
    # 'no asset'. And it silently breaks the MERGE, because '' matches nothing the
    # way NULL does not either.
    if row.get("asset") == "":
        raise ValueError("asset='' is invalid. Use None for global metrics.")

    if row.get("value") is None:
        raise ValueError("value is required. Drop the observation instead.")
