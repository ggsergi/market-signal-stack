# Plan de refactor: arquitectura por capas (Parte 1, capa macro)

Rama: `refactor/layer-architecture` (creada desde `origin/main` @ `4cdb21e`).
Estado: **Parte 1 ejecutada y comparación aprobada** (2026-10-28).
Decisiones: D1 sí (target `refactor`), D2 sí, D3 opción (b), D4 **no**
(`layer_signal` fuera de la Parte 1, se definirá aparte), D5 sí.
Resultado de la comparación sobre el mismo snapshot de raw: los 10 `int_*`
idénticos a sus `mart_*` (mismas filas, 0 diferencias en `EXCEPT DISTINCT`
en ambos sentidos) y `mart_macro_global` con 0 discrepancias de señal frente
a los marts antiguos en las fechas propias de cada indicador.
Pendiente: actualizar el README (punto 2, Documentación).

Objetivo de la Parte 1: reorganizar los 10 indicadores macro actuales sin
cambiar ninguna fórmula ni umbral, y añadir la unión por fecha
(`int_macro_signals`) y el mart de capa (`mart_macro_global`).

---

## 1. Decisiones que necesito antes de ejecutar

Están ordenadas por impacto. Para cada una indico mi recomendación.

### D1. Dónde construir la rama (bloqueante)

Solo hay un target (`dev`) y escribe en `market_signal_marts`, el mismo
dataset que lee el agente de Sara y que construye el CI diario desde `main`.
Construir la rama ahí crearía `int_*` y `mart_macro_global` en el dataset de
producción, con grant a la cuenta de Sara, antes de validarlos.

**Recomendación:** añadir un segundo output `refactor` en `~/.dbt/profiles.yml`
(fuera del repo) con dataset `market_signal_marts_refactor`, y construir la
rama siempre con `--target refactor`. Sin definir `SARA_MARTS_READER_PRINCIPAL`
en esas ejecuciones, para no dar acceso a Sara a tablas sin validar.
Necesito tu permiso para editar `~/.dbt/profiles.yml`.

### D2. Qué pasa con las tablas `mart_*` actuales

El agente de Sara lee hoy los 10 `mart_*`. Tras el refactor, dbt deja de
construirlos, pero **dbt no borra tablas**: seguirían existiendo en BigQuery,
congeladas en su último build y quedándose obsoletas sin aviso.

**Recomendación:** quitarlos de dbt en la rama (el objetivo es no tener un mart
por indicador) y, antes del merge, acordar con Sara la migración del agente a
`mart_macro_global`; borrar las tablas antiguas a mano solo después. La
alternativa (mantener vistas `mart_<indicador>` de transición) contradice el
objetivo y no la recomiendo salvo que Sara la necesite.

### D3. Grano y calendario de `mart_macro_global`

Mezcla cadencias: 6 diarios (días hábiles de EE. UU.; `yield_curve` ya
rellena huecos por su cuenta), 1 semanal (`fed_balance_sheet`, miércoles) y 3
mensuales (`eurozone_m3`, `usa_m2`, `china_m2`, fechados el día 1 del mes).

- **Calendario:** propongo días naturales (7/7), porque el activo final (BTC)
  cotiza todos los días y `mart_btc_cycle_signal` lo necesitará. Desde el
  primer día con alguna señal no nula hasta la última fecha con datos.
- **Días sin dato propio de un indicador** (fines de semana, y todos los días
  salvo uno para los mensuales). Dos opciones:
  - **(a) Estricto, sin relleno:** `signal_<indicador>` solo en las fechas con
    fila propia. Los mensuales tendrían señal 12 días al año; la columna sería
    casi siempre NULL. Fiel, pero poco útil a diario.
  - **(b) Arrastre con caducidad (as-of):** cada día toma la última señal
    disponible del indicador, solo si no es más antigua que su umbral de
    freshness (diario 3 d, semanal 14 d, mensual 60 d, los mismos de
    `_sources.yml`); si es más antigua, NULL. Añade una columna
    `<indicador>_as_of` con la fecha de la observación usada, para que el
    relleno sea siempre visible.
  - **Recomiendo (b).** Es un forward-fill, por eso lo pregunto.
- **Aviso de sesgo de anticipación (lookahead):** los mensuales están fechados
  en el mes al que se refieren, no en su publicación (el M3 de agosto se
  publica a finales de septiembre). Con (b), una fila del 15-ago usaría el M3
  de agosto, que ese día aún no se conocía. Para la lectura diaria del agente
  no importa; para un backtest de `mart_btc_cycle_signal` sí. No lo arreglo en
  este refactor (requiere fecha de publicación, que el raw no tiene para las
  filas de backfill); lo dejo documentado.

### D4. `layer_signal`: es lógica nueva, no reorganización

No existe ninguna regla de cómo combinar los 10 indicadores. Propuesta para que
la valides (iría versionada en `docs/layer_rules/macro_global.yaml`, mismo
formato `min_inclusive` / `max_exclusive`):

- `layer_score` = media de `normalized_value` de los indicadores disponibles
  ese día, ponderada por el `weight` de su regla (0.9 a 1.3 hoy).
- Cobertura mínima: si los indicadores con señal suman menos del 50 % del peso
  total, `layer_score` y `layer_signal` = NULL (no dar una señal de capa con
  2 de 10 indicadores).
- `layer_signal`: BULLISH si `layer_score` >= 0.3; NEUTRAL entre -0.3 y 0.3;
  BEARISH si < -0.3. **Los umbrales 0.3 / 50 % son un placeholder**: dime los
  tuyos.
- Si prefieres no decidir ahora, alternativa: dejar `layer_signal` fuera de la
  Parte 1 y añadirlo cuando tengas la regla.

### D5. Materialización de `models/intermediate/`

**Recomendación:** `view` (el defecto del proyecto). No ocupa almacenamiento,
se puede consultar para comparar con lo antiguo y admite tests. `ephemeral`
no se puede inspeccionar ni comparar; `table` duplica almacenamiento sin
necesidad. `mart_macro_global` sí como `table`, con contract.

Las vistas `int_*` viven en el mismo dataset, pero el agente no las ve: el
grant de Sara es por tabla, solo sobre los marts.

---

## 2. Archivos

### Se mueven (con `git mv`, para conservar historial) — sin tocar fórmulas ni umbrales

| Origen (`models/marts/`) | Destino (`models/intermediate/`) |
|---|---|
| `mart_yield_curve.sql/.yml` | `int_yield_curve.sql/.yml` |
| `mart_fed_balance_sheet.sql/.yml` | `int_fed_balance_sheet.sql/.yml` |
| `mart_dxy.sql/.yml` | `int_dxy.sql/.yml` |
| `mart_vix.sql/.yml` | `int_vix.sql/.yml` |
| `mart_spx.sql/.yml` | `int_spx.sql/.yml` |
| `mart_nasdaq_tech_risk.sql/.yml` | `int_nasdaq_tech_risk.sql/.yml` |
| `mart_move.sql/.yml` | `int_move.sql/.yml` |
| `mart_eurozone_m3.sql/.yml` | `int_eurozone_m3.sql/.yml` |
| `mart_usa_m2.sql/.yml` | `int_usa_m2.sql/.yml` |
| `mart_china_m2.sql/.yml` | `int_china_m2.sql/.yml` |

Cambios en cada uno, y solo estos:
- `.sql`: se quita `{{ config(materialized='table') }}` (hereda `view` de la
  carpeta, ver D5). Comentarios que citan otro `mart_*` pasan a `int_*`. El
  SQL de cálculo no cambia.
- `.yml`: nombre del modelo; se quitan `access: public`, `contract` y `grants`
  (pasan al mart de capa; un intermedio no es interfaz pública). Se mantienen
  `data_type`, descripciones, `meta` y **todos** los tests genéricos.

### Nuevos

- `models/intermediate/int_macro_signals.sql/.yml`: formato largo, una fila
  por (fecha, indicador) con `signal`, `normalized_value`, `weight`. Se
  construye con `UNION ALL` de los 10 `int_*`: **cero JOIN**.
- `models/marts/mart_macro_global.sql/.yml`: una fila por día. Pivota
  `int_macro_signals` con agregación condicional (`MAX(IF(...))`) sobre un
  calendario (`dbt_utils.date_spine`): **un solo JOIN**. Columnas:
  `signal_date` (DATE), `signal_<indicador>` × 10, `<indicador>_as_of` × 10
  (si D3 = b), `layer_score`, `layer_signal`. Contract enforced, `access:
  public`, grants con el mismo `env_var`. Tests: `unique` + `not_null` en
  `signal_date`, `accepted_values` en cada `signal_*` y en `layer_signal`.
- `docs/layer_rules/macro_global.yaml`: regla de `layer_signal` (si D4 se
  confirma).
- `dbt_project.yml`: entrada `intermediate: +materialized: view` explícita.

### Tests singulares (solo cambia el `ref`)

`assert_yield_curve_no_prolonged_imputation`,
`assert_fed_balance_sheet_delta_not_null_after_first_week`,
`assert_nasdaq_tech_risk_not_null_after_ma200`,
`assert_eurozone_m3_not_null_after_window`,
`assert_usa_m2_not_null_after_window`,
`assert_china_m2_not_null_after_window`: `ref('mart_x')` → `ref('int_x')`.
`assert_per_metric_freshness` no cambia.

### Documentación

- `README.md`: Architecture (diagrama regenerado con
  `scripts/generate_lineage_diagram.py`, no a mano), Current status (los 10
  indicadores pasan a describirse como intermedios de la capa macro; el mart
  público es `mart_macro_global`), Indicators in progress, Roadmap (capas).
- `scripts/generate_lineage_diagram.py`: añadir `intermediate` a
  `LAYER_ORDER`. Además, hoy pintaría `raw_market_metrics_weekly` y
  `_monthly` (solo de freshness) como nodos huérfanos: propongo omitir
  sources sin modelos que dependan de ellos.
- `CLAUDE.md` (gotcha del grant de `mart_yield_curve.yml`) y el comentario en
  `.github/workflows/dbt_build.yml:71`: pasan a referirse a
  `mart_macro_global`.
- `docs/indicator_rules/`: sin cambios.

---

## 3. Verificación (tras tu confirmación)

1. Construir la versión antigua y la nueva **sobre el mismo snapshot de raw**,
   ambas en `market_signal_marts_refactor`: primero `main` (en un `git
   worktree` aparte, para no tocar la rama ni `main`), luego la rama.
2. `dbt build --target refactor` de la rama con todos los tests en verde.
3. Comparación por indicador, `mart_x` antiguo frente a `int_x` nuevo:
   número de filas, y `EXCEPT DISTINCT` en ambos sentidos sobre todas las
   columnas. Se espera 0 diferencias (misma lógica).
4. Comparación de `mart_macro_global` frente a los marts antiguos: en cada
   fecha en que un indicador tiene fila propia, `signal_<indicador>` debe
   coincidir con el `signal` del mart antiguo. Recuento de señales por fecha.
5. Te enseño las diferencias y paro.

---

## 4. Fuera de alcance (lo anoto, no lo toco)

- **Las notas del README sobre historial están desfasadas:** los backfills ya
  se han cargado (`m2_usa` desde 1959, `m2_china` desde 2008 con 225 filas,
  `vix` desde 2010, `move` desde 2020). La frase de "China M2 sin backfill,
  señal hacia 2037" ya no es cierta. Se corrige en la actualización de README
  del punto 2.
- **Métricas diarias nuevas sin freshness por bloque:** `btc_etf_net_flow`,
  `btc_exchange_inflow/outflow`, `btc_market_cap`, `btc_mvrv`, `btc_supply` y
  `mags` no están en la lista manual del filtro diario de `_sources.yml`, así
  que ni el bloque diario ni `assert_per_metric_freshness` las vigilan.
- Parte 2 (ETF flows) no se empieza hasta que confirmes la Parte 1.
