-- Las primeras 199 filas no tienen MA200 completa (distance_to_ma200 y signal
-- en NULL por diseño); a partir de la observación 200 ambos deben tener valor.
WITH numbered AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY event_time) AS rn
    FROM {{ ref('mart_nasdaq_tech_risk') }}
)

SELECT *
FROM numbered
WHERE rn >= 200
  AND (distance_to_ma200 IS NULL OR signal IS NULL)
