-- Los primeros 12 meses no tienen YoY y los 191 primeros no tienen ventana
-- de percentil completa (12 + 180 - 1): yoy_percentile y signal en NULL por
-- diseño. A partir del mes 192 ambos deben tener valor.
WITH numbered AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY event_time) AS rn
    FROM {{ ref('mart_eurozone_m3') }}
)

SELECT *
FROM numbered
WHERE rn >= 192
  AND (yoy_percentile IS NULL OR signal IS NULL)
