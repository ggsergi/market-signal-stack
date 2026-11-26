-- Bitcoin RHODL Ratio, precomputed by BGeometrics (free plan; payload field
-- rhodlRatio). Provisional bands calibrated on LookIntoBitcoin's chart zones
-- and applied to this series: valid at cycle scale only.
-- Rules: docs/indicator_rules/rhodl_ratio_btc.yaml.
-- Spec: docs/specs/rhodl_ratio_btc.md.

WITH btc_rhodl AS (
    SELECT
        event_time,
        -- Explicit NULL for a missing or non-positive value.
        IF(value > 0, value, NULL) AS rhodl
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'btc_rhodl_ratio'
)

SELECT
    event_time,
    rhodl,
    -- Raw daily value, no smoothing (decided). First match wins, lower bound
    -- inclusive ([min_inclusive, max_exclusive) in the rule). The outer bands
    -- come from LookIntoBitcoin's chart zones; the [5000, 22000),
    -- [1000, 5000) and [350, 1000) bands are ASSUMED.
    CASE
        WHEN rhodl IS NULL THEN NULL
        WHEN rhodl >= 22000 THEN -1.0
        WHEN rhodl >= 5000 THEN -0.6
        WHEN rhodl >= 1000 THEN 0.0
        WHEN rhodl >= 350 THEN 0.6
        ELSE 1.0
    END AS normalized_value,
    CASE
        WHEN rhodl IS NULL THEN NULL
        WHEN rhodl >= 5000 THEN 'BEARISH'
        WHEN rhodl >= 1000 THEN 'NEUTRAL'
        ELSE 'BULLISH'
    END AS signal,
    CASE
        WHEN rhodl IS NULL THEN NULL
        WHEN rhodl >= 5000 THEN 'negative'
        WHEN rhodl >= 1000 THEN 'neutral'
        ELSE 'positive'
    END AS btc_bias,
    CASE
        WHEN rhodl IS NULL THEN NULL
        WHEN rhodl >= 22000 THEN 'El RHODL Ratio se encuentra en niveles extremadamente altos, señalando euforia y un posible techo de ciclo en Bitcoin.'
        WHEN rhodl >= 5000 THEN 'El RHODL Ratio indica un mercado sobrecalentado, históricamente asociado a fases avanzadas del ciclo alcista.'
        WHEN rhodl >= 1000 THEN 'El RHODL Ratio se sitúa en una zona intermedia, sin señales claras de euforia ni de capitulación.'
        WHEN rhodl >= 350 THEN 'El RHODL Ratio muestra un mercado relativamente frío, típico de fases de acumulación o crecimiento saludable.'
        ELSE 'El RHODL Ratio se encuentra en niveles muy bajos, históricamente asociados a suelos de ciclo y oportunidades de acumulación.'
    END AS message
FROM btc_rhodl
ORDER BY event_time
