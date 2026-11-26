-- Bitcoin MVRV Z-Score, derived from Coin Metrics' market cap and MVRV.
-- Rules: docs/indicator_rules/btc_mvrv_zscore.yaml.
-- Spec: docs/specs/btc_mvrv_zscore.md.

-- The expanding standard deviation of market cap starts at the FIRST
-- available data point (Coin Metrics, 2010-07-18), as in the standard
-- definition (Glassnode, Coinglass, Look Into Bitcoin). Decided 2026-11-26:
-- it matches Look Into Bitcoin's cycle maxima and minima; a 2012 window start
-- understated the tops (2013: 7.85 vs ~10.5).
-- Output start date (same as NUPL: before 2012 realized cap is not a market
-- reading): Z is NULL before it, but those days still enter the window.
{%- set start_date = '2012-01-01' %}
-- Minimum observations in the window before Z has a value (kept as a guard).
-- With the window from the first data point it no longer binds on real data
-- (n_obs is 533 on 2012-01-01). A var only so the unit test can lower it;
-- not meant to be overridden in normal runs.
{%- set min_obs = var('btc_mvrv_z_min_obs', 365) %}

WITH market_cap AS (
    SELECT
        event_time,
        value AS market_cap
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'btc_market_cap'
),

-- Not named "mvrv": BigQuery would read "mvrv" in a later CTE as the whole
-- row of the table, not the column.
btc_mvrv AS (
    SELECT
        event_time,
        value AS mvrv
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'btc_mvrv'
),

joined AS (
    SELECT
        event_time,
        m.market_cap,
        v.mvrv
    FROM market_cap AS m
    FULL OUTER JOIN btc_mvrv AS v USING (event_time)
),

windowed AS (
    SELECT
        event_time,
        market_cap,
        mvrv,
        -- MVRV = market cap / realized cap.
        IF(mvrv > 0, market_cap / mvrv, NULL) AS realized_cap,
        -- Expanding window from the first available data point up to and
        -- including the day: no look-ahead.
        STDDEV_SAMP(market_cap) OVER (
            ORDER BY event_time
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS market_cap_std,
        COUNT(market_cap) OVER (
            ORDER BY event_time
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS n_obs
    FROM joined
),

calculated AS (
    SELECT
        *,
        -- Explicit NULL before the start date, with too few observations, or
        -- with a missing / non-positive input.
        CASE
            WHEN event_time < TIMESTAMP '{{ start_date }}' THEN NULL
            WHEN n_obs < {{ min_obs }} THEN NULL
            WHEN market_cap IS NULL OR mvrv IS NULL OR mvrv <= 0 THEN NULL
            WHEN market_cap_std IS NULL OR market_cap_std <= 0 THEN NULL
            ELSE (market_cap - realized_cap) / market_cap_std
        END AS mvrv_z
    FROM windowed
)

SELECT
    event_time,
    market_cap,
    mvrv,
    realized_cap,
    market_cap_std,
    n_obs,
    mvrv_z,
    -- First match wins, lower bound inclusive ([min_inclusive,
    -- max_exclusive) in the rule). The [4.0, 7.0) band is ASSUMED (spec Q3).
    CASE
        WHEN mvrv_z IS NULL THEN NULL
        WHEN mvrv_z >= 7.0 THEN -1.0
        WHEN mvrv_z >= 4.0 THEN -0.6
        WHEN mvrv_z >= 2.0 THEN 0.0
        WHEN mvrv_z >= 0.0 THEN 0.6
        ELSE 1.0
    END AS normalized_value,
    CASE
        WHEN mvrv_z IS NULL THEN NULL
        WHEN mvrv_z >= 4.0 THEN 'BEARISH'
        WHEN mvrv_z >= 2.0 THEN 'NEUTRAL'
        ELSE 'BULLISH'
    END AS signal,
    CASE
        WHEN mvrv_z IS NULL THEN NULL
        WHEN mvrv_z >= 4.0 THEN 'negative'
        WHEN mvrv_z >= 2.0 THEN 'neutral'
        ELSE 'positive'
    END AS btc_bias,
    CASE
        WHEN mvrv_z IS NULL THEN NULL
        WHEN mvrv_z >= 7.0 THEN 'El MVRV Z-Score se encuentra en zona de burbuja, históricamente asociada a techos de ciclo (2013, 2017, 2021) y alto riesgo de corrección en BTC.'
        WHEN mvrv_z >= 4.0 THEN 'El MVRV Z-Score indica un mercado sobrecalentado, con el precio claramente por encima del valor realizado y riesgo creciente para BTC.'
        WHEN mvrv_z >= 2.0 THEN 'El MVRV Z-Score se sitúa en una fase alcista saludable, sin señales de exceso ni de infravaloración.'
        WHEN mvrv_z >= 0.0 THEN 'El MVRV Z-Score se mueve cerca del valor justo, típico de fases de acumulación con riesgo moderado para BTC.'
        ELSE 'El MVRV Z-Score está por debajo de 0, señalando infravaloración severa y capitulación, históricamente asociadas a suelos de ciclo (2015, 2018, 2020).'
    END AS message
FROM calculated
ORDER BY event_time
