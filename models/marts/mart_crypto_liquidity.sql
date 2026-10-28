-- Capa de liquidez cripto: una fila por día natural, una columna signal_<indicador>
-- por indicador de la capa. Cada día toma la última observación disponible de cada
-- indicador (arrastre as-of) siempre que no tenga más de max_age_days días;
-- si es más antigua, signal_<indicador> y <indicador>_as_of quedan en NULL.
-- <indicador>_as_of es la fecha de la observación usada, para que el arrastre
-- sea siempre visible.
--
-- Los dos indicadores son diarios. El ETF solo tiene sesiones de días hábiles
-- de EE. UU.: fines de semana y festivos arrastran la última sesión (hasta 3
-- días). Los flujos de exchanges se revisan durante ~30 días (ver
-- docs/indicator_rules/btc_exchange_net_flow.yaml).
--
-- layer_score / layer_coverage / layer_signal: reglas de
-- docs/layer_rules/crypto_liquidity.yaml, las mismas en todas las capas.
--
-- El cuerpo es común a todos los marts de capa: macros/layer_mart.sql.

{%- set indicators = ['btc_etf_net_flow', 'btc_exchange_net_flow'] %}

{{ layer_mart('int_crypto_liquidity_signals', indicators) }}
