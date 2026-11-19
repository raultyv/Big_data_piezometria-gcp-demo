-- Verificación de la vista híbrida
-- Cada fila: comprobación, valor esperado, valor observado y resultado (OK o FALLA).
-- La columna 'modo' interna distingue igualdad ('eq') de "al menos uno" ('ge').
-- Tokens __PROYECTO__ y __DATASET__ (y los __…__ de eventos) los reemplaza scripts/ejecutar_sql.sh.

WITH c AS (
  SELECT 'filas de v_lectura_hibrida = gold del lote + gold del flujo' AS comprobacion, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.g_lecturas`) + (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.g_eventos`) AS STRING) AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.v_lectura_hibrida`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'orígenes en la vista (batch y stream)' AS comprobacion, '2' AS esperado, CAST((SELECT COUNT(DISTINCT origen) FROM `__PROYECTO__.__DATASET__.v_lectura_hibrida`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'repetidos por instrumento y fecha en la vista' AS comprobacion, '0' AS esperado, CAST((SELECT COUNT(*) - COUNT(DISTINCT CONCAT(instrumento_cod, '|', CAST(fecha AS STRING))) FROM `__PROYECTO__.__DATASET__.v_lectura_hibrida`) AS STRING) AS observado, 'eq' AS modo
)
SELECT comprobacion, esperado, observado,
       IF(IF(modo = 'ge', SAFE_CAST(observado AS INT64) >= 1, esperado = observado), 'OK', 'FALLA') AS resultado
FROM c;
