-- Los primeros 12 meses no tienen YoY y los 131 primeros no tienen ventana
-- de percentil completa (12 + 120 - 1): yoy_percentile y signal en NULL por
-- diseño. A partir del mes 132 ambos deben tener valor.
WITH numbered AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY event_time) AS rn
    FROM {{ ref('mart_china_m2') }}
)

SELECT *
FROM numbered
WHERE rn >= 132
  AND (yoy_percentile IS NULL OR signal IS NULL)
