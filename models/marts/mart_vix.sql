{{ config(materialized='table') }}

WITH vix AS (
    SELECT
        event_time,
        value
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'vix'
),

with_ma20 AS (
    SELECT
        event_time,
        value,
        AVG(value) OVER (
            ORDER BY event_time
            ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
        ) AS ma20_raw,
        COUNT(value) OVER (
            ORDER BY event_time
            ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
        ) AS ma20_obs_count
    FROM vix
),

ma20 AS (
    SELECT
        event_time,
        value,
        -- vix_ma20 solo se calcula con la ventana de 20 días completa; con
        -- menos observaciones sería una media parcial, no una MA20 real.
        CASE
            WHEN ma20_obs_count >= 20 THEN ma20_raw
            ELSE NULL
        END AS vix_ma20
    FROM with_ma20
),

with_zscore_window AS (
    SELECT
        event_time,
        value,
        vix_ma20,
        AVG(vix_ma20) OVER (
            ORDER BY event_time
            ROWS BETWEEN 749 PRECEDING AND CURRENT ROW
        ) AS avg_750,
        STDDEV(vix_ma20) OVER (
            ORDER BY event_time
            ROWS BETWEEN 749 PRECEDING AND CURRENT ROW
        ) AS stddev_750,
        COUNT(vix_ma20) OVER (
            ORDER BY event_time
            ROWS BETWEEN 749 PRECEDING AND CURRENT ROW
        ) AS zscore_obs_count
    FROM ma20
),

calculated AS (
    SELECT
        event_time,
        value,
        vix_ma20,
        -- zscore solo se calcula con 750 observaciones de vix_ma20
        -- disponibles en la ventana (normalization.rolling_window: 750 en
        -- docs/indicator_rules/vix_volatility_index.yaml). Con el histórico
        -- actual esto da NULL en todas las filas -- esperado, no un error;
        -- ver la política de "indicadores en construcción" en el README.
        CASE
            WHEN zscore_obs_count >= 750 THEN (vix_ma20 - avg_750) / stddev_750
            ELSE NULL
        END AS zscore_raw
    FROM with_zscore_window
),

capped AS (
    SELECT
        event_time,
        value,
        vix_ma20,
        -- cap a [-3, 3], aplicado antes de comparar contra los thresholds
        CASE
            WHEN zscore_raw IS NULL THEN NULL
            WHEN zscore_raw > 3 THEN 3
            WHEN zscore_raw < -3 THEN -3
            ELSE zscore_raw
        END AS zscore
    FROM calculated
)

SELECT
    event_time,
    value,
    vix_ma20,
    zscore,
    -- Igual que en DXY: un zscore más bajo (VIX bajo) es BULLISH y uno más
    -- alto (VIX alto) es BEARISH, así que la cadena va en ascendente ("<").
    CASE
        WHEN zscore IS NULL THEN NULL
        WHEN zscore < -1.0 THEN 1.0
        WHEN zscore < -0.5 THEN 0.6
        WHEN zscore < 0.5 THEN 0.0
        WHEN zscore < 1.0 THEN -0.6
        ELSE -1.0
    END AS normalized_value,
    CASE
        WHEN zscore IS NULL THEN NULL
        WHEN zscore < -1.0 THEN 'BULLISH'
        WHEN zscore < -0.5 THEN 'BULLISH'
        WHEN zscore < 0.5 THEN 'NEUTRAL'
        WHEN zscore < 1.0 THEN 'BEARISH'
        ELSE 'BEARISH'
    END AS signal
FROM capped
ORDER BY event_time
