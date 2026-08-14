# Market Signal Stack

Pipeline de indicadores macro, cripto y on-chain construido en dbt sobre BigQuery. Transforma datos crudos de mercado en señales normalizadas que alimentan un agente de IA (desarrollado por Sara) para evaluar el ciclo de mercado de Bitcoin.

Es un proyecto de portfolio y, a la vez, una colaboración real entre dos personas: yo construyo y mantengo el pipeline de datos, Sara construye el agente que lo consume. Está en fase inicial — el primer indicador ya funciona de punta a punta, y sirve de plantilla para los siguientes.

## Arquitectura

```
Sara carga datos crudos          yo transformo en dbt              Sara consume
   ↓                                    ↓                               ↓
raw_market_signals    →    models/staging/  →  models/marts/   →   market_signal_marts
(BigQuery, fuera de dbt)      (staging, ephemeral)   (tablas)         (BigQuery, vía su agente)
```

- **`raw_market_signals`**: dataset de BigQuery donde Sara carga los datos crudos. dbt no lo construye, solo lo lee como `source`.
- **`models/staging/`**: limpieza mínima (cast de tipos, columnas seleccionadas) sobre el dato crudo. Sin lógica de negocio. Materializado como `ephemeral` — no deja tabla propia, se inyecta en los modelos que lo usan.
- **`models/marts/`**: aquí vive el cálculo de cada indicador — la lógica de negocio real. Se materializa como tabla en `market_signal_marts`, el dataset que Sara consume desde su agente con una cuenta de servicio de solo lectura.

## Estado actual

Primer indicador construido: **Yield Curve (10Y-2Y)**, el spread entre los tipos del Tesoro de EE. UU. a 10 y 2 años, usado como señal de riesgo de recesión y de apetito por activos de riesgo como BTC.

El mart `mart_yield_curve` calcula:
- El spread (`dgs10 - dgs2`) para cada día disponible.
- Una señal categórica (`BULLISH` / `NEUTRAL` / `BEARISH`) y un valor normalizado, según rangos de spread predefinidos.
- Forward-fill: si un día falta el dato de una de las dos series, se arrastra el último valor disponible en vez de dejar un hueco — y cada fila indica explícitamente si su valor es real o arrastrado (`is_dgs2_imputed`, `is_dgs10_imputed`), para que el agente de Sara sepa cuándo confiar menos en un dato.

Este es el primero de varios indicadores planeados — el resto del pipeline (staging genérico, tests, contrato de datos, permisos) está pensado para reutilizarse con cada uno nuevo.

## Cómo correrlo

Requiere Python 3.11+, [uv](https://docs.astral.sh/uv/) y acceso al proyecto de GCP `market-signal-stack`.

```bash
uv sync                # instala dependencias
uv run dbt deps        # instala paquetes dbt (dbt_utils)
uv run dbt debug        # verifica la conexión a BigQuery
uv run dbt run          # construye los modelos
uv run dbt test         # corre los tests
```

`profiles.yml` no está en este repo — vive en `~/.dbt/profiles.yml` de cada máquina, con las credenciales de BigQuery. Hay que crearlo aparte antes de correr nada; `dbt debug` confirma si está bien configurado.

## Tests y garantías de calidad

El pipeline no es un script suelto: cada capa tiene sus propias comprobaciones automáticas.

- **Freshness del source**: alerta si los datos crudos llevan más de 1 día sin actualizarse, y falla si llevan más de 3 (solo para las métricas de cadencia diaria).
- **Integridad de datos**: columnas clave nunca nulas, y combinación única de métrica + fecha (sin duplicados).
- **Guardrail de forward-fill**: un test dedicado falla si un indicador lleva más de 5 días seguidos arrastrando el mismo valor — señal de que el pipeline de origen dejó de traer datos y nadie se ha dado cuenta.

Para el detalle técnico más fino — convenciones de código, comandos exactos, gotchas conocidos — consulta [CLAUDE.md](CLAUDE.md).
