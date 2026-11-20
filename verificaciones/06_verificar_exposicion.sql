-- Verificación de la capa de exposición (vistas api_*)
-- Cada fila: comprobación, valor esperado, valor observado y resultado (OK o FALLA).
-- Tokens __PROYECTO__ y __DATASET__ los reemplaza scripts/comun.sh.

WITH c AS (
  SELECT 'instrumentos en api_ultima_lectura = instrumentos de v_lectura_hibrida' AS comprobacion, CAST((SELECT COUNT(DISTINCT instrumento_cod) FROM `__PROYECTO__.__DATASET__.v_lectura_hibrida`) AS STRING) AS esperado, CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.api_ultima_lectura`) AS STRING) AS observado
  UNION ALL
  SELECT 'instrumentos repetidos en api_ultima_lectura', '0', CAST((SELECT COUNT(*) - COUNT(DISTINCT instrumento_cod) FROM `__PROYECTO__.__DATASET__.api_ultima_lectura`) AS STRING)
  UNION ALL
  SELECT 'suma de lecturas de api_resumen_dique = filas de v_lectura_hibrida', CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.v_lectura_hibrida`) AS STRING), CAST((SELECT SUM(lecturas) FROM `__PROYECTO__.__DATASET__.api_resumen_dique`) AS STRING)
  UNION ALL
  SELECT 'filas de api_serie_instrumento = filas de v_lectura_hibrida', CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.v_lectura_hibrida`) AS STRING), CAST((SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.api_serie_instrumento`) AS STRING)
  UNION ALL
  SELECT 'lecturas en o sobre NAM: resumen por dique = vista híbrida', CAST((SELECT COUNTIF(sobre_nam) FROM `__PROYECTO__.__DATASET__.v_lectura_hibrida`) AS STRING), CAST((SELECT SUM(lecturas_en_o_sobre_nam) FROM `__PROYECTO__.__DATASET__.api_resumen_dique`) AS STRING)
)
SELECT comprobacion, esperado, observado, IF(esperado = observado, 'OK', 'FALLA') AS resultado
FROM c;
