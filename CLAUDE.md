# dbt-market-signal-stack

Proyecto dbt sobre BigQuery (region `EU`; el project ID real de GCP no se
versiona, ver `CLAUDE.local.md`) que transforma
métricas de mercado crudas (`raw_market_signals.raw_market_metrics`) en modelos
de staging, intermediate y marts en `market_signal_marts`.

## Documentación externa
- Las rutas locales a fuentes de convenciones y aprendizajes previos (Capstone
  de referencia, vault de notas) viven en `CLAUDE.local.md`, no versionado
  (específico de esta máquina). Consultar ese archivo antes de decisiones de
  estructura, naming, materialización o errores conocidos — no cargar todo el
  contenido de golpe, solo la nota relevante al problema concreto que tienes
  delante.
- Las reglas de negocio de cada indicador (fórmula, thresholds, señales) viven
  versionadas en `docs/indicator_rules/` (un archivo por indicador) — fuente
  de verdad para implementaciones nuevas o revisiones de las existentes.

## Comandos y arquitectura
- Usar siempre `uv run dbt <comando>` — el venv no está activado por defecto.
- `raw_market_signals` es solo origen (no lo construye dbt); `market_signal_marts` es el schema destino por defecto.
- Capas: `staging/` (ephemeral, sin lógica) → `intermediate/` (vistas: un `int_<indicador>` con fórmula y señal, y un `int_<capa>_signals` por capa) → `marts/` (tablas: un mart por capa, p. ej. `mart_macro_global`, con contract y grants). No se crean marts por indicador.
- Para probar cambios sin tocar el dataset que lee el agente: `--target refactor` (output en `~/.dbt/profiles.yml`, dataset `market_signal_marts_refactor`).
- `profiles.yml` vive en `~/.dbt/`, no en el repo. Usa `method: oauth` vía Application Default Credentials (`gcloud auth application-default login`), distinto del login normal (`gcloud auth login`).

## Convenciones
- Este proyecto usa `staging/` + prefijo `stg_` (no `src/`/`src_` de Zoltan) — solo se adoptó su patrón CTE y la materialización ephemeral por carpeta.
- Tests `not_null` van en el source (`_sources.yml`); aún no hay `schema.yml` de modelo.
- `dbt_utils` está instalado (`dbt-labs/dbt_utils`, `>=1.0.0,<2.0.0`, vía `packages.yml`).
- Staging usa `SAFE_CAST` en vez de `CAST` a propósito, para no romper el pipeline ante valores no castables del JSON crudo.

## Gotchas
- La lista de métricas diarias en `freshness.filter` (`_sources.yml`) es manual — al añadir una métrica de cadencia diaria hay que sumarla ahí también.
- `google-genai` / `vertexai` en `uv.lock` son residuo de una exploración anterior sin usar — ignorar, no es integración activa.
- El `grants` de los marts (hoy `mart_macro_global.yml`) usa `env_var('SARA_MARTS_READER_PRINCIPAL', ...)` con un placeholder por defecto — el valor real (no versionado, repo es público) vive en `CLAUDE.local.md`. Sin esa variable definida, el grant al placeholder **falla** ("Service account … does not exist"): BigQuery crea la tabla (dbt aplica el grant después) pero el modelo queda en ERROR y `dbt build` salta sus tests. En `--target refactor` se acepta ese error a propósito (no se da acceso a Sara a tablas sin validar) y los tests se corren aparte con `dbt test --target refactor`.
