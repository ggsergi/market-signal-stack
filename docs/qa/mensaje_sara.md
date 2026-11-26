Hola Sara,

Dos cosas sobre la capa on-chain:

1. **NUPL sale de Coin Metrics, no de Glassnode.** La serie de Glassnode no
   está en el raw, así que la calculo a partir de `btc_mvrv` (Coin Metrics):
   NUPL = 1 − 1/MVRV. Es una identidad exacta, pero es el NUPL con el realized
   cap de Coin Metrics, así que los valores no tienen por qué coincidir al
   decimal con los gráficos de Glassnode. Antes de 2012 queda en NULL a
   propósito.

2. **Freshness (pregunta abierta):** `btc_mvrv` no está en el filtro diario de
   `_sources.yml`, así que hoy nada avisa si deja de cargar. ¿Lo añadimos?
   Y si más adelante usamos `btc_market_cap` y `btc_supply`, ¿también?

Gracias.
