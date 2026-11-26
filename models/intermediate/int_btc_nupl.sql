-- Bitcoin NUPL (Net Unrealized Profit/Loss), derived from Coin Metrics' MVRV.
-- Rules: docs/indicator_rules/btc_nupl_cycle_regime.yaml.
-- Spec: docs/specs/btc_nupl_cycle_regime.md.

-- missing_data.start_date in the rule: before it, the derived NUPL is not a
-- market reading (coins mined at ~0 cost before there was a market).
{%- set start_date = '2012-01-01' %}

-- The CTE is not named "mvrv": BigQuery would read "mvrv" in the next CTE as
-- the whole row of the table, not the column.
WITH btc_mvrv AS (
    SELECT
        event_time,
        value AS mvrv
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'btc_mvrv'
),

calculated AS (
    SELECT
        event_time,
        mvrv,
        -- MVRV = market cap / realized cap, so
        -- NUPL = (market cap - realized cap) / market cap = 1 - 1 / MVRV.
        -- Explicit NULL before the start date, and if MVRV is missing or not
        -- positive (guard against the division).
        CASE
            WHEN event_time < TIMESTAMP '{{ start_date }}' THEN NULL
            WHEN mvrv IS NULL OR mvrv <= 0 THEN NULL
            ELSE 1 - 1 / mvrv
        END AS nupl
    FROM btc_mvrv
)

SELECT
    event_time,
    mvrv,
    nupl,
    -- First match wins, lower bound inclusive ([min_inclusive,
    -- max_exclusive) in the rule). High NUPL (euphoria) is BEARISH, so the
    -- chain goes from the top band down.
    CASE
        WHEN nupl IS NULL THEN NULL
        WHEN nupl >= 0.70 THEN -1.0
        WHEN nupl >= 0.60 THEN -0.6
        WHEN nupl >= 0.30 THEN 0.0
        WHEN nupl >= 0.00 THEN 0.6
        ELSE 1.0
    END AS normalized_value,
    CASE
        WHEN nupl IS NULL THEN NULL
        WHEN nupl >= 0.70 THEN 'BEARISH'
        WHEN nupl >= 0.60 THEN 'BEARISH'
        WHEN nupl >= 0.30 THEN 'NEUTRAL'
        WHEN nupl >= 0.00 THEN 'BULLISH'
        ELSE 'BULLISH'
    END AS signal,
    CASE
        WHEN nupl IS NULL THEN NULL
        WHEN nupl >= 0.60 THEN 'negative'
        WHEN nupl >= 0.30 THEN 'neutral'
        ELSE 'positive'
    END AS btc_bias,
    CASE
        WHEN nupl IS NULL THEN NULL
        WHEN nupl >= 0.70 THEN 'El NUPL se encuentra en zona de euforia extrema, históricamente asociada a techos de ciclo y mayor riesgo de corrección en BTC.'
        WHEN nupl >= 0.60 THEN 'El NUPL se sitúa en niveles elevados de euforia, indicando exceso de beneficios no realizados y riesgo creciente para BTC.'
        WHEN nupl >= 0.30 THEN 'El NUPL se encuentra en una fase de optimismo saludable, típica de tendencias alcistas sostenibles sin excesos.'
        WHEN nupl >= 0.00 THEN 'El NUPL se sitúa en niveles bajos de beneficio no realizado, una zona entre el miedo y el optimismo típica de fases de acumulación.'
        ELSE 'El NUPL se encuentra en zona de pérdidas no realizadas, históricamente asociada a capitulación y suelos de ciclo en BTC.'
    END AS message
FROM calculated
ORDER BY event_time
