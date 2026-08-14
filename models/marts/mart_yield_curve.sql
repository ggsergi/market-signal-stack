{{ config(materialized='table') }}

WITH dgs10 AS (
    SELECT
        event_time,
        value AS dgs10
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'yield_10y'
),

dgs2 AS (
    SELECT
        event_time,
        value AS dgs2
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'yield_2y'
),

joined AS (
    SELECT
        COALESCE(dgs10.event_time, dgs2.event_time) AS event_time,
        dgs2.dgs2,
        dgs10.dgs10
    FROM dgs10
    FULL OUTER JOIN dgs2
        ON dgs10.event_time = dgs2.event_time
),

filled AS (
    SELECT
        event_time,
        dgs2 IS NULL AS is_dgs2_imputed,
        dgs10 IS NULL AS is_dgs10_imputed,
        LAST_VALUE(dgs2 IGNORE NULLS) OVER (
            ORDER BY event_time
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS dgs2,
        LAST_VALUE(dgs10 IGNORE NULLS) OVER (
            ORDER BY event_time
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS dgs10
    FROM joined
),

calculated AS (
    SELECT
        event_time,
        dgs2,
        dgs10,
        is_dgs2_imputed,
        is_dgs10_imputed,
        dgs10 - dgs2 AS raw_diff
    FROM filled
)

SELECT
    event_time,
    dgs2,
    dgs10,
    is_dgs2_imputed,
    is_dgs10_imputed,
    raw_diff,
    CASE
        WHEN raw_diff IS NULL THEN NULL
        WHEN raw_diff >= 1.0 THEN 1.0
        WHEN raw_diff >= 0.25 THEN 0.6
        WHEN raw_diff >= -0.25 THEN 0.0
        WHEN raw_diff >= -1.0 THEN -0.6
        ELSE -1.0
    END AS normalized_value,
    CASE
        WHEN raw_diff IS NULL THEN NULL
        WHEN raw_diff >= 1.0 THEN 'BULLISH'
        WHEN raw_diff >= 0.25 THEN 'BULLISH'
        WHEN raw_diff >= -0.25 THEN 'NEUTRAL'
        WHEN raw_diff >= -1.0 THEN 'BEARISH'
        ELSE 'BEARISH'
    END AS signal
FROM calculated
ORDER BY event_time
