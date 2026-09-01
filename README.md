# Market Signal Stack

[![dbt](https://img.shields.io/badge/dbt-1.12.0-FF694B?logo=dbt&logoColor=white)](https://www.getdbt.com/)
[![Warehouse](https://img.shields.io/badge/warehouse-BigQuery-4285F4?logo=googlebigquery&logoColor=white)](https://cloud.google.com/bigquery)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE)

Pipeline de indicadores macro, cripto y on-chain construido en dbt sobre BigQuery. Transforma datos crudos de mercado en señales normalizadas que alimentan un agente de IA para evaluar el ciclo de mercado de Bitcoin.

## Contenidos
- [Arquitectura](#arquitectura)
- [Estado actual](#estado-actual)
- [Roadmap](#roadmap)
- [Cómo correrlo](#cómo-correrlo)
- [Tests y garantías de calidad](#tests-y-garantías-de-calidad)

## Arquitectura

```mermaid
flowchart LR
    subgraph source["source"]
        raw_market_metrics["raw_market_metrics"]
    end
    subgraph staging["staging"]
        stg_market_metrics["stg_market_metrics"]
    end
    subgraph marts["marts"]
        mart_fed_balance_sheet["mart_fed_balance_sheet"]
        mart_yield_curve["mart_yield_curve"]
    end
    raw_market_metrics --> stg_market_metrics
    stg_market_metrics --> mart_fed_balance_sheet
    stg_market_metrics --> mart_yield_curve
    marts --> market_signal_marts[("market_signal_marts<br/>(BigQuery)")]
    market_signal_marts --> agent["Agente de IA<br/>(Sara)"]
```

- **`raw_market_signals`**: dataset de BigQuery donde se carga los datos crudos. dbt no lo construye, solo lo lee como `source`.
- **`models/staging/`**: limpieza mínima (cast de tipos, columnas seleccionadas) sobre el dato crudo. Sin lógica de negocio. Materializado como `ephemeral` — no deja tabla propia, se inyecta en los modelos que lo usan.
- **`models/marts/`**: aquí vive el cálculo de cada indicador — la lógica de negocio real. Se materializa como tabla en `market_signal_marts`, el dataset que se consume desde el agente con una cuenta de servicio de solo lectura.

## Estado actual

Dos indicadores construidos, ambos en la capa Macro Global:

- **Yield Curve (10Y-2Y)** (`mart_yield_curve`): spread entre los tipos del Tesoro de EE. UU. a 10 y 2 años, señal de riesgo de recesión y de apetito por activos de riesgo como BTC. Calcula el spread diario, una señal categórica (`BULLISH` / `NEUTRAL` / `BEARISH`) con valor normalizado, y aplica forward-fill cuando falta el dato de una de las dos series — cada fila indica explícitamente si su valor es real o arrastrado (`is_dgs2_imputed`, `is_dgs10_imputed`).
- **FED Balance Sheet (QE/QT)** (`mart_fed_balance_sheet`): variación semanal del balance de la Reserva Federal (WALCL), señal de expansión o contracción de liquidez. Calcula el delta semana a semana y la misma señal categórica normalizada.

Ambos siguen el mismo patrón: staging genérico, mart con la lógica de negocio, reglas documentadas en `docs/indicator_rules/`, tests y contrato de datos.

## Roadmap

Yield Curve y FED Balance Sheet son los dos primeros indicadores de una capa más amplia de **Macro Global** — señales macroeconómicas pensadas para alimentar la evaluación del ciclo de mercado de BTC. La idea es seguir ampliando esta capa con más indicadores macro reutilizando el mismo patrón (staging, mart, reglas versionadas, tests, contrato de datos), y usarla como base para otras capas de señal más adelante.

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
