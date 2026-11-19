-- Verificación del flujo en tiempo real (simulado)
-- Cada fila: comprobación, valor esperado, valor observado y resultado (OK o FALLA).
-- La columna 'modo' interna distingue igualdad ('eq') de "al menos uno" ('ge').
-- Tokens __PROYECTO__ y __DATASET__ (y los __…__ de eventos) los reemplaza scripts/ejecutar_sql.sh.

WITH c AS (
  SELECT 'mensajes crudos en b_eventos_raw = enviados' AS comprobacion, '__ENVIADOS__' AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.b_eventos_raw`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'filas de s_eventos (silver) = enviados' AS comprobacion, '__ENVIADOS__' AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.s_eventos`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'entregas duplicadas marcadas' AS comprobacion, '__DUP__' AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.s_eventos` WHERE es_duplicado_entrega) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'instrumento inexistente marcado' AS comprobacion, '__SINCAT__' AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.s_eventos` WHERE sin_catalogo) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'NPA nulo marcado' AS comprobacion, '__NULOS__' AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.s_eventos` WHERE es_npa_nulo) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'NPA no numérico marcado' AS comprobacion, '__NONUM__' AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.s_eventos` WHERE es_npa_no_numerico) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'filas de g_eventos (gold del flujo)' AS comprobacion, '__GOLD_EV__' AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.g_eventos`) AS STRING) AS observado, 'eq' AS modo
)
SELECT comprobacion, esperado, observado,
       IF(IF(modo = 'ge', SAFE_CAST(observado AS INT64) >= 1, esperado = observado), 'OK', 'FALLA') AS resultado
FROM c;
