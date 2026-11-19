-- Verificación del esquema en estrella
-- Cada fila: comprobación, valor esperado, valor observado y resultado (OK o FALLA).
-- La columna 'modo' interna distingue igualdad ('eq') de "al menos uno" ('ge').
-- Tokens __PROYECTO__ y __DATASET__ (y los __…__ de eventos) los reemplaza scripts/ejecutar_sql.sh.

WITH c AS (
  SELECT 'filas de fact_lectura = gold' AS comprobacion, (SELECT valor FROM `__PROYECTO__.__DATASET__.b_manifiesto` WHERE clave = 'filas_gold_esperadas') AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.fact_lectura`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'dim_instrumento' AS comprobacion, (SELECT valor FROM `__PROYECTO__.__DATASET__.b_manifiesto` WHERE clave = 'instrumentos') AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.dim_instrumento`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'dim_umbral' AS comprobacion, (SELECT valor FROM `__PROYECTO__.__DATASET__.b_manifiesto` WHERE clave = 'tramos_de_niveles') AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.dim_umbral`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'dim_fecha = días de la ventana' AS comprobacion, CAST((SELECT DATE_DIFF(MAX(fecha), MIN(fecha), DAY) + 1 FROM `__PROYECTO__.__DATASET__.b_lecturas`) AS STRING) AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.dim_fecha`) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'hechos sin instrumento en la dimensión (huérfanos)' AS comprobacion, '0' AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.fact_lectura` f LEFT JOIN `__PROYECTO__.__DATASET__.dim_instrumento` d ON d.instrumento_key = f.instrumento_key WHERE d.instrumento_key IS NULL) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'hechos sin fecha en la dimensión (huérfanos)' AS comprobacion, '0' AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.fact_lectura` f LEFT JOIN `__PROYECTO__.__DATASET__.dim_fecha` d ON d.fecha_key = f.fecha_key WHERE d.fecha_key IS NULL) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'hechos sin los cuatro niveles vigentes' AS comprobacion, '0' AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.fact_lectura` WHERE umbral_npc_key IS NULL OR umbral_nac_key IS NULL OR umbral_nam_key IS NULL OR umbral_nca_key IS NULL) AS STRING) AS observado, 'eq' AS modo
  UNION ALL
  SELECT 'hechos repetidos por instrumento y fecha' AS comprobacion, '0' AS esperado, CAST((SELECT COUNT(*) - COUNT(DISTINCT CONCAT(CAST(instrumento_key AS STRING), '|', CAST(fecha_key AS STRING))) FROM `__PROYECTO__.__DATASET__.fact_lectura`) AS STRING) AS observado, 'eq' AS modo
)
SELECT comprobacion, esperado, observado,
       IF(IF(modo = 'ge', SAFE_CAST(observado AS INT64) >= 1, esperado = observado), 'OK', 'FALLA') AS resultado
FROM c;
