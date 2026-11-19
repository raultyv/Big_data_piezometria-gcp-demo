-- Verificación de silver y gold contra el manifiesto
-- Cada fila: comprobación, valor esperado, valor observado y resultado (OK o FALLA).
-- La columna 'modo' interna distingue igualdad ('eq') de "al menos uno" ('ge').
-- Tokens __PROYECTO__ y __DATASET__ (y los __…__ de eventos) los reemplaza scripts/ejecutar_sql.sh.

WITH c AS (
  SELECT 'filas de s_lecturas (silver) = bronze' AS comprobacion, (SELECT valor FROM `__PROYECTO__.__DATASET__.b_manifiesto` WHERE clave = 'filas_bronze') AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.s_lecturas`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'duplicados exactos marcados' AS comprobacion, (SELECT valor FROM `__PROYECTO__.__DATASET__.b_manifiesto` WHERE clave = 'duplicados_exactos') AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.s_lecturas` WHERE es_duplicado_exacto) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'filas en conflicto marcadas' AS comprobacion, (SELECT valor FROM `__PROYECTO__.__DATASET__.b_manifiesto` WHERE clave = 'filas_en_conflicto') AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.s_lecturas` WHERE es_fecha_conflicto) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'filas de g_lecturas (gold)' AS comprobacion, (SELECT valor FROM `__PROYECTO__.__DATASET__.b_manifiesto` WHERE clave = 'filas_gold_esperadas') AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.g_lecturas`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'gold sin repetidos por instrumento y fecha' AS comprobacion, '0' AS esperado, CAST((SELECT COUNT(*) - COUNT(DISTINCT CONCAT(instrumento_cod, '|', CAST(fecha AS STRING))) FROM `__PROYECTO__.__DATASET__.g_lecturas`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'filas de v_exclusiones = duplicados + conflictos' AS comprobacion, CAST(CAST((SELECT valor FROM `__PROYECTO__.__DATASET__.b_manifiesto` WHERE clave = 'duplicados_exactos') AS INT64) + CAST((SELECT valor FROM `__PROYECTO__.__DATASET__.b_manifiesto` WHERE clave = 'filas_en_conflicto') AS INT64) AS STRING) AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.v_exclusiones`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'silver = gold + exclusiones (nada se pierde en silencio)' AS comprobacion, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.s_lecturas`) AS STRING) AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.g_lecturas`) + (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.v_exclusiones`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'ejecuciones registradas con estado OK (al menos 1)' AS comprobacion, '>= 1' AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.ejecuciones` WHERE estado = 'OK') AS STRING) AS observado, 'ge' AS modo
)
SELECT comprobacion, esperado, observado,
       IF(IF(modo = 'ge', SAFE_CAST(observado AS INT64) >= 1, esperado = observado), 'OK', 'FALLA') AS resultado
FROM c;
