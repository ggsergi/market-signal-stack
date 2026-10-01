-- Los primeros 12 meses no tienen YoY y los 251 primeros no tienen ventana
-- de percentil completa (12 + 240 - 1): yoy_percentile y signal en NULL por
-- diseño. A partir del mes 252 ambos deben tener valor.
WITH numbered AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY event_time) AS rn
    FROM {{ ref('mart_usa_m2') }}
)

SELECT *
FROM numbered
WHERE rn >= 252
  AND (yoy_percentile IS NULL OR signal IS NULL)
