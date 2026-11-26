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
- Tests `not_null` del raw van en el source (`_sources.yml`); cada modelo tiene su `<modelo>.yml` con tests (y unit tests en los `int_` de capa on-chain y en `mart_macro_global`).
- `dbt_utils` está instalado (`dbt-labs/dbt_utils`, `>=1.0.0,<2.0.0`, vía `packages.yml`).
- Staging usa `SAFE_CAST` en vez de `CAST` a propósito, para no romper el pipeline ante valores no castables del JSON crudo.

## Gotchas
- La lista de métricas diarias en `freshness.filter` (`_sources.yml`) es manual — al añadir una métrica de cadencia diaria hay que sumarla ahí también. Las series de BGeometrics tienen además su propio bloque (`raw_market_metrics_bgeometrics`, error a 10 días: el plan gratuito publica SOPR con ~7 días de retraso).
- La caducidad de cada indicador en un mart de capa (`max_age_days`) es el `error_after` del bloque de freshness que se le asigna en `int_<capa>_signals`; no se copia en ningún otro sitio.
- `google-genai` / `vertexai` en `uv.lock` son residuo de una exploración anterior sin usar — ignorar, no es integración activa.
- El `grants` de los marts de capa (`mart_macro_global`, `mart_crypto_liquidity`, `mart_onchain_btc`) va en el `config()` del `.sql` (los macros del proyecto no se pueden llamar en los `.yml` de propiedades) y usa `sara_marts_reader()` (`macros/sara_marts_reader.sql`): lee `SARA_MARTS_READER_PRINCIPAL` (valor real no versionado, repo público; vive en `CLAUDE.local.md`) con un placeholder por defecto. **En el dataset `market_signal_marts_refactor` devuelve siempre el placeholder**, aunque la variable esté definida, para no dar nunca acceso a Sara a tablas sin validar. El grant al placeholder **falla** ("Service account … does not exist"): BigQuery crea la tabla (dbt aplica el grant después) pero el modelo queda en ERROR y `dbt build` salta sus tests; en `--target refactor` es lo esperado y los tests se corren aparte con `dbt test --target refactor`. En `dev`, sin la variable definida pasa lo mismo.
- Si una query o modelo parsea `payload` (JSON), usar `PARSE_JSON(x, wide_number_mode => 'round')`: en modo exacto (por defecto) `SAFE.PARSE_JSON` devuelve NULL en silencio con números que no caben exactos en FLOAT64 (2.114 payloads del raw). Ver `docs/qa/onchain_layer_qa.md`.
