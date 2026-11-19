-- Verificación de la carga de bronze contra el manifiesto
-- Cada fila: comprobación, valor esperado, valor observado y resultado (OK o FALLA).
-- La columna 'modo' interna distingue igualdad ('eq') de "al menos uno" ('ge').
-- Tokens __PROYECTO__ y __DATASET__ (y los __…__ de eventos) los reemplaza scripts/ejecutar_sql.sh.

WITH c AS (
  SELECT 'filas de b_lecturas' AS comprobacion, (SELECT valor FROM `__PROYECTO__.__DATASET__.b_manifiesto` WHERE clave = 'filas_bronze') AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.b_lecturas`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'instrumentos en b_instrumentos' AS comprobacion, (SELECT valor FROM `__PROYECTO__.__DATASET__.b_manifiesto` WHERE clave = 'instrumentos') AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.b_instrumentos`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'instrumentos distintos en b_lecturas' AS comprobacion, (SELECT valor FROM `__PROYECTO__.__DATASET__.b_manifiesto` WHERE clave = 'instrumentos') AS esperado, CAST((SELECT COUNT(DISTINCT instrumento_cod) FROM `__PROYECTO__.__DATASET__.b_lecturas`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'tramos de niveles en b_umbrales' AS comprobacion, (SELECT valor FROM `__PROYECTO__.__DATASET__.b_manifiesto` WHERE clave = 'tramos_de_niveles') AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.b_umbrales`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'una sola huella de archivo en b_lecturas' AS comprobacion, '1' AS esperado, CAST((SELECT COUNT(DISTINCT archivo_sha256) FROM `__PROYECTO__.__DATASET__.b_lecturas`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'la huella coincide con el manifiesto' AS comprobacion, (SELECT valor FROM `__PROYECTO__.__DATASET__.b_manifiesto` WHERE clave = 'huella') AS esperado, (SELECT MIN(archivo_sha256) FROM `__PROYECTO__.__DATASET__.b_lecturas`) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'filas con fecha futura' AS comprobacion, '0' AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.b_lecturas` WHERE fecha > CURRENT_DATE()) AS STRING) AS observado, 'eq' AS modo
)
SELECT comprobacion, esperado, observado,
       IF(IF(modo = 'ge', SAFE_CAST(observado AS INT64) >= 1, esperado = observado), 'OK', 'FALLA') AS resultado
FROM c;
