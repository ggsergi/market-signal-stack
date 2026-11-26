-- Bitcoin SOPR (Spent Output Profit Ratio), precomputed by BGeometrics
-- (free plan, ~7-day lag; variant to be confirmed with Sara).
-- Rules: docs/indicator_rules/sopr_spent_output_profit_ratio.yaml.
-- Spec: docs/specs/sopr_spent_output_profit_ratio.md.

WITH btc_sopr AS (
    SELECT
        event_time,
        -- Explicit NULL for a missing or non-positive value.
        IF(value > 0, value, NULL) AS sopr
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'btc_sopr'
)

SELECT
    event_time,
    sopr,
    -- Raw daily value (rolling_window: null). First match wins, lower bound
    -- inclusive ([min_inclusive, max_exclusive) in the rule).
    CASE
        WHEN sopr IS NULL THEN NULL
        WHEN sopr >= 1.05 THEN -0.6
        WHEN sopr >= 1.00 THEN -0.3
        WHEN sopr >= 0.98 THEN 0.0
        WHEN sopr >= 0.90 THEN 0.6
        ELSE 1.0
    END AS normalized_value,
    CASE
        WHEN sopr IS NULL THEN NULL
        WHEN sopr >= 1.00 THEN 'BEARISH'
        WHEN sopr >= 0.98 THEN 'NEUTRAL'
        ELSE 'BULLISH'
    END AS signal,
    CASE
        WHEN sopr IS NULL THEN NULL
        WHEN sopr >= 1.00 THEN 'negative'
        WHEN sopr >= 0.98 THEN 'neutral'
        ELSE 'positive'
    END AS btc_bias,
    CASE
        WHEN sopr IS NULL THEN NULL
        WHEN sopr >= 1.05 THEN 'El SOPR se sitúa claramente por encima de 1, indicando que el mercado está vendiendo BTC con beneficios, lo que históricamente suele preceder fases de distribución o correcciones.'
        WHEN sopr >= 1.00 THEN 'El SOPR se mantiene ligeramente por encima de 1, señalando realización de beneficios moderada y posible presión vendedora.'
        WHEN sopr >= 0.98 THEN 'El SOPR se mueve cerca de 1, reflejando equilibrio entre ventas con beneficio y con pérdidas, típico de zonas de decisión del mercado.'
        WHEN sopr >= 0.90 THEN 'El SOPR se sitúa por debajo de 1, indicando ventas con pérdidas y posibles fases de capitulación o acumulación.'
        ELSE 'El SOPR está muy por debajo de 1, señalando capitulación intensa y zonas históricamente asociadas a suelos de mercado.'
    END AS message
FROM btc_sopr
ORDER BY event_time
