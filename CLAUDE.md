# dbt-market-signal-stack

Proyecto dbt sobre BigQuery (`market-signal-stack`, region `EU`) que transforma
métricas de mercado crudas (`raw_market_signals.raw_market_metrics`) en modelos
de staging y marts en `market_signal_marts`.

## Documentación externa
- Las rutas locales a fuentes de convenciones y aprendizajes previos (Capstone
  de referencia, vault de notas) viven en `CLAUDE.local.md`, no versionado
  (específico de esta máquina). Consultar ese archivo antes de decisiones de
  estructura, naming, materialización o errores conocidos — no cargar todo el
  contenido de golpe, solo la nota relevante al problema concreto que tienes
  delante.

## Comandos y arquitectura
- Usar siempre `uv run dbt <comando>` — el venv no está activado por defecto.
- `raw_market_signals` es solo origen (no lo construye dbt); `market_signal_marts` es el schema destino por defecto.
- `profiles.yml` vive en `~/.dbt/`, no en el repo. Usa `method: oauth` vía Application Default Credentials (`gcloud auth application-default login`), distinto del login normal (`gcloud auth login`).

## Convenciones
- Este proyecto usa `staging/` + prefijo `stg_` (no `src/`/`src_` de Zoltan) — solo se adoptó su patrón CTE y la materialización ephemeral por carpeta.
- Tests `not_null` van en el source (`_sources.yml`); aún no hay `schema.yml` de modelo.
- `dbt_utils` está instalado (`dbt-labs/dbt_utils`, `>=1.0.0,<2.0.0`, vía `packages.yml`).
- Staging usa `SAFE_CAST` en vez de `CAST` a propósito, para no romper el pipeline ante valores no castables del JSON crudo.

## Gotchas
- La lista de métricas diarias en `freshness.filter` (`_sources.yml`) es manual — al añadir una métrica de cadencia diaria hay que sumarla ahí también.
- `google-genai` / `vertexai` en `uv.lock` son residuo de una exploración anterior sin usar — ignorar, no es integración activa.
