-- Flujo neto diario de los ETF spot de BTC de EE. UU. (Farside, total de todos
-- los ETF, millones de USD). Reglas en docs/indicator_rules/btc_etf_net_flow.yaml.

-- streak_rule.sessions del YAML: N sesiones seguidas de entradas/salidas.
{%- set streak_sessions = 5 %}

WITH etf AS (
    -- 100 % BTC aunque asset sea NULL: no se filtra por asset.
    SELECT
        event_time,
        value AS net_flow_musd
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'btc_etf_net_flow'
),

sessions AS (
    -- Antes de 2025-07 Farside publica los festivos de EE. UU. con 0 en todas
    -- las columnas: es "mercado cerrado", no "flujo plano". Se excluyen, igual
    -- que los festivos posteriores, que ya no tienen fila (missing_data en el
    -- YAML). Así tampoco cuentan para la racha.
    SELECT
        event_time,
        net_flow_musd
    FROM etf
    WHERE net_flow_musd != 0
),

with_streak AS (
    SELECT
        event_time,
        net_flow_musd,
        COUNT(net_flow_musd) OVER last_sessions AS sessions_in_window,
        MIN(net_flow_musd) OVER last_sessions AS min_in_window,
        MAX(net_flow_musd) OVER last_sessions AS max_in_window
    FROM sessions
    WINDOW last_sessions AS (
        ORDER BY event_time
        ROWS BETWEEN {{ streak_sessions - 1 }} PRECEDING AND CURRENT ROW
    )
),

classified AS (
    SELECT
        event_time,
        net_flow_musd,
        -- Racha: las últimas N sesiones (incluida la actual) todas con entradas
        -- (> 0) o todas con salidas (< 0). Solo cuenta con N sesiones completas.
        sessions_in_window = {{ streak_sessions }} AND min_in_window > 0 AS is_inflow_streak,
        sessions_in_window = {{ streak_sessions }} AND max_in_window < 0 AS is_outflow_streak,
        -- Primer-match-gana con límite inferior inclusivo: primero los umbrales
        -- diarios (>= 200, < -100); la racha solo actúa sobre días que por
        -- umbral serían NEUTRAL.
        CASE
            WHEN net_flow_musd >= 200 THEN 1.0
            WHEN net_flow_musd < -100 THEN -1.0
            WHEN sessions_in_window = {{ streak_sessions }} AND min_in_window > 0 THEN 0.6
            WHEN sessions_in_window = {{ streak_sessions }} AND max_in_window < 0 THEN -0.6
            ELSE 0.0
        END AS normalized_value
    FROM with_streak
)

SELECT
    event_time,
    net_flow_musd,
    -- TRUE si la señal del día sale de la racha y no del umbral diario.
    normalized_value IN (0.6, -0.6) AS is_streak_signal,
    normalized_value,
    CASE
        WHEN normalized_value > 0 THEN 'BULLISH'
        WHEN normalized_value < 0 THEN 'BEARISH'
        ELSE 'NEUTRAL'
    END AS signal,
    CASE
        WHEN normalized_value > 0 THEN 'positive'
        WHEN normalized_value < 0 THEN 'negative'
        ELSE 'neutral'
    END AS btc_bias,
    CASE
        WHEN normalized_value > 0 THEN 'El flujo diario de ETFs muestra una señal positiva. Los ETFs son hoy el motor principal del precio del BTC.'
        WHEN normalized_value < 0 THEN 'El flujo diario de ETFs muestra una señal negativa. Los ETFs son hoy el motor principal del precio del BTC.'
        ELSE 'El flujo diario de ETFs muestra una señal neutra. Los ETFs son hoy el motor principal del precio del BTC.'
    END AS message
FROM classified
ORDER BY event_time
