{{ config(materialized='table') }}

WITH fed_liquidity AS (
    -- El source reporta `value` en usd_millions (ver columna `unit` en
    -- raw_market_metrics para este metric). Se convierte a USD completos aquí
    -- para que value y delta queden en la misma unidad que los thresholds de
    -- docs/indicator_rules/fed_balance_sheet_qe_qt.yaml (normalization.unit: USD).
    SELECT
        event_time,
        value * 1000000 AS value
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'fed_liquidity'
),

with_lag AS (
    SELECT
        event_time,
        value,
        LAG(value) OVER (ORDER BY event_time) AS previous_value
    FROM fed_liquidity
),

calculated AS (
    SELECT
        event_time,
        value,
        value - previous_value AS delta
    FROM with_lag
)

SELECT
    event_time,
    value,
    delta,
    CASE
        WHEN delta IS NULL THEN NULL
        WHEN delta >= 20000000000 THEN 1.0
        WHEN delta >= 5000000000 THEN 0.6
        WHEN delta >= -5000000000 THEN 0.0
        WHEN delta >= -20000000000 THEN -0.6
        ELSE -1.0
    END AS normalized_value,
    CASE
        WHEN delta IS NULL THEN NULL
        WHEN delta >= 20000000000 THEN 'BULLISH'
        WHEN delta >= 5000000000 THEN 'BULLISH'
        WHEN delta >= -5000000000 THEN 'NEUTRAL'
        WHEN delta >= -20000000000 THEN 'BEARISH'
        ELSE 'BEARISH'
    END AS signal
FROM calculated
ORDER BY event_time
