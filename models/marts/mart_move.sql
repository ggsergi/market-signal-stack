{{ config(materialized='table') }}

WITH move AS (
    -- value es un nivel de índice (^MOVE), no una cifra monetaria: sin
    -- conversión de unidades, a diferencia de mart_fed_balance_sheet.
    SELECT
        event_time,
        value
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'move'
),

with_ma30 AS (
    SELECT
        event_time,
        value,
        AVG(value) OVER (
            ORDER BY event_time
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ) AS ma30_raw,
        COUNT(value) OVER (
            ORDER BY event_time
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ) AS ma30_obs_count
    FROM move
),

ma30 AS (
    SELECT
        event_time,
        value,
        -- move_ma30 solo se calcula con la ventana de 30 días completa; con
        -- menos observaciones sería una media parcial, no una MA30 real.
        CASE
            WHEN ma30_obs_count >= 30 THEN ma30_raw
            ELSE NULL
        END AS move_ma30
    FROM with_ma30
),

with_zscore_window AS (
    SELECT
        event_time,
        value,
        move_ma30,
        AVG(move_ma30) OVER (
            ORDER BY event_time
            ROWS BETWEEN 999 PRECEDING AND CURRENT ROW
        ) AS avg_1000,
        STDDEV(move_ma30) OVER (
            ORDER BY event_time
            ROWS BETWEEN 999 PRECEDING AND CURRENT ROW
        ) AS stddev_1000,
        COUNT(move_ma30) OVER (
            ORDER BY event_time
            ROWS BETWEEN 999 PRECEDING AND CURRENT ROW
        ) AS zscore_obs_count
    FROM ma30
),

calculated AS (
    SELECT
        event_time,
        value,
        move_ma30,
        -- zscore solo se calcula con 1000 observaciones de move_ma30
        -- disponibles en la ventana (~4 años). Con el histórico actual esto
        -- da NULL en todas las filas -- esperado, no un error; ver la
        -- política de "indicadores en construcción" en el README.
        CASE
            WHEN zscore_obs_count >= 1000 THEN (move_ma30 - avg_1000) / stddev_1000
            ELSE NULL
        END AS zscore_raw
    FROM with_zscore_window
),

capped AS (
    SELECT
        event_time,
        value,
        move_ma30,
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
    move_ma30,
    zscore,
    -- Igual que en VIX: un zscore más bajo (MOVE bajo, poco estrés en bonos)
    -- es BULLISH y uno más alto (MOVE alto) es BEARISH, así que la cadena va
    -- en ascendente ("<"), con límite inferior inclusivo en cada tramo.
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
