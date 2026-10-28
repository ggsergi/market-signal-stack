-- Capa macro global: una fila por día natural, una columna signal_<indicador>
-- por indicador macro. Cada día toma la última observación disponible de cada
-- indicador (arrastre as-of) siempre que no tenga más de max_age_days días;
-- si es más antigua, signal_<indicador> y <indicador>_as_of quedan en NULL.
-- <indicador>_as_of es la fecha de la observación usada, para que el arrastre
-- sea siempre visible.
--
-- Aviso (lookahead): los indicadores mensuales están fechados en el mes al
-- que se refieren, no en su publicación. Con el arrastre, una fila puede usar
-- un dato que ese día aún no se había publicado. No afecta a la lectura diaria
-- actual; sí a un backtest. Ver docs/refactor_plan.md (D3).
--
-- layer_score / layer_coverage / layer_signal: reglas de
-- docs/layer_rules/macro_global.yaml, las mismas en todas las capas.
--
-- El cuerpo es común a todos los marts de capa: macros/layer_mart.sql.

{%- set indicators = ['yield_curve', 'fed_balance_sheet', 'dxy', 'vix', 'spx',
                      'nasdaq_tech_risk', 'move', 'eurozone_m3', 'usa_m2', 'china_m2'] %}

{{ layer_mart('int_macro_signals', indicators) }}
