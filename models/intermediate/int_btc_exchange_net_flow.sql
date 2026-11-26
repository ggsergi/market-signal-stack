-- Flujo neto diario de BTC desde exchanges (Coin Metrics, en BTC):
-- net_flow_btc = outflow - inflow. Positivo = salen BTC de exchanges =
-- acumulación = BULLISH. Reglas en docs/indicator_rules/btc_exchange_net_flow.yaml.

-- streak_rule.days del YAML: N días naturales seguidos de retiros/entradas altos.
{%- set streak_days = 3 %}

WITH inflow AS (
    SELECT
        event_time,
        value AS inflow_btc
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'btc_exchange_inflow'
),

outflow AS (
    SELECT
        event_time,
        value AS outflow_btc
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'btc_exchange_outflow'
),

-- Inflow y outflow vienen en filas separadas (formato largo). Se parte de la
-- unión de fechas de ambas series para que un día con solo una de las dos
-- quede visible (con net_flow_btc NULL) en vez de desaparecer.
dates AS (
    SELECT event_time FROM inflow
    UNION DISTINCT
    SELECT event_time FROM outflow
),

joined AS (
    SELECT
        d.event_time,
        i.inflow_btc,
        o.outflow_btc
    FROM dates AS d
    LEFT JOIN inflow AS i USING (event_time)
    LEFT JOIN outflow AS o USING (event_time)
),

net AS (
    SELECT
        event_time,
        inflow_btc,
        outflow_btc,
        -- NULL, sin relleno, si falta una de las dos series, o si ambas son 0
        -- (13 días de 2011 sin cobertura de Coin Metrics, no un flujo nulo).
        CASE
            WHEN inflow_btc IS NULL OR outflow_btc IS NULL THEN NULL
            WHEN inflow_btc = 0 AND outflow_btc = 0 THEN NULL
            ELSE outflow_btc - inflow_btc
        END AS net_flow_btc
    FROM joined
),

with_streak AS (
    SELECT
        event_time,
        inflow_btc,
        outflow_btc,
        net_flow_btc,
        -- La racha exige N días naturales consecutivos con net_flow_btc: si
        -- falta un día en la serie o tiene NULL, la ventana no es completa.
        COUNT(net_flow_btc) OVER last_days AS days_with_value,
        DATE_DIFF(DATE(event_time), DATE(MIN(event_time) OVER last_days), DAY) AS window_span_days,
        MIN(net_flow_btc) OVER last_days AS min_in_window,
        MAX(net_flow_btc) OVER last_days AS max_in_window
    FROM net
    WINDOW last_days AS (
        ORDER BY event_time
        ROWS BETWEEN {{ streak_days - 1 }} PRECEDING AND CURRENT ROW
    )
),

classified AS (
    SELECT
        event_time,
        inflow_btc,
        outflow_btc,
        net_flow_btc,
        days_with_value = {{ streak_days }}
            AND window_span_days = {{ streak_days - 1 }} AS is_complete_window,
        min_in_window,
        max_in_window
    FROM with_streak
),

scored AS (
    SELECT
        event_time,
        inflow_btc,
        outflow_btc,
        net_flow_btc,
        -- Primer-match-gana con límite inferior inclusivo. SUPOSICIÓN (ver
        -- YAML): la racha refuerza el tramo +/-0.6 a +/-1.0 si los últimos N
        -- días están todos en ese lado (>= 2000 o < -2000).
        CASE
            WHEN net_flow_btc IS NULL THEN NULL
            WHEN net_flow_btc >= 5000 THEN 1.0
            WHEN net_flow_btc >= 2000 THEN
                IF(is_complete_window AND min_in_window >= 2000, 1.0, 0.6)
            WHEN net_flow_btc >= -2000 THEN 0.0
            WHEN net_flow_btc >= -5000 THEN
                IF(is_complete_window AND max_in_window < -2000, -1.0, -0.6)
            ELSE -1.0
        END AS normalized_value,
        -- TRUE si la racha ha reforzado la señal del día (0.6 -> 1.0 o
        -- -0.6 -> -1.0).
        CASE
            WHEN net_flow_btc >= 2000 AND net_flow_btc < 5000 THEN is_complete_window AND min_in_window >= 2000
            WHEN net_flow_btc >= -5000 AND net_flow_btc < -2000 THEN is_complete_window AND max_in_window < -2000
            WHEN net_flow_btc IS NULL THEN NULL
            ELSE FALSE
        END AS is_streak_signal
    FROM classified
)

SELECT
    event_time,
    inflow_btc,
    outflow_btc,
    net_flow_btc,
    is_streak_signal,
    normalized_value,
    CASE
        WHEN normalized_value IS NULL THEN NULL
        WHEN normalized_value > 0 THEN 'BULLISH'
        WHEN normalized_value < 0 THEN 'BEARISH'
        ELSE 'NEUTRAL'
    END AS signal,
    CASE
        WHEN normalized_value IS NULL THEN NULL
        WHEN normalized_value > 0 THEN 'positive'
        WHEN normalized_value < 0 THEN 'negative'
        ELSE 'neutral'
    END AS btc_bias,
    -- Mensaje del tramo resultante (un día reforzado toma el de +/-1.0).
    CASE
        WHEN normalized_value IS NULL THEN NULL
        WHEN normalized_value = 1.0 THEN 'Se observan retiros netos muy elevados de BTC desde exchanges, indicando acumulación fuerte y una clara reducción de presión vendedora.'
        WHEN normalized_value = 0.6 THEN 'Los flujos netos de BTC muestran retiros sostenidos desde exchanges, señalando acumulación y un entorno favorable para BTC.'
        WHEN normalized_value = 0.0 THEN 'Los flujos de BTC hacia y desde exchanges se mantienen equilibrados, sin señales claras de acumulación ni de distribución.'
        WHEN normalized_value = -0.6 THEN 'Se detectan entradas netas relevantes de BTC hacia exchanges, indicando aumento de presión vendedora y mayor riesgo a corto plazo.'
        ELSE 'Entradas netas muy elevadas de BTC a exchanges, señalando fuerte intención de venta, distribución y riesgo significativo de caídas.'
    END AS message
FROM scored
ORDER BY event_time
