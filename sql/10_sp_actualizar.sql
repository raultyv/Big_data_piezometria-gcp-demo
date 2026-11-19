-- sp_actualizar(): silver (marcas de calidad, sin corregir) y gold (lecturas válidas cruzadas con niveles vigentes)
-- Origen: informe de la entrega 2, anexo C.2.
-- Tokens __PROYECTO__ y __DATASET__: los reemplaza scripts/ejecutar_sql.sh.

CREATE OR REPLACE PROCEDURE `__PROYECTO__.__DATASET__.sp_actualizar`()
BEGIN
  DECLARE v_id STRING DEFAULT GENERATE_UUID();
  DECLARE v_ini TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  BEGIN
CREATE OR REPLACE TABLE `__PROYECTO__.__DATASET__.s_lecturas` AS
WITH base AS (
  SELECT
    l.*,
    COUNT(*) OVER (PARTITION BY instrumento_cod, fecha) AS n_misma_fecha,
    MIN(npa_msnm) OVER (PARTITION BY instrumento_cod, fecha) AS npa_min_fecha,
    MAX(npa_msnm) OVER (PARTITION BY instrumento_cod, fecha) AS npa_max_fecha,
    ROW_NUMBER() OVER (PARTITION BY instrumento_cod, fecha ORDER BY fila_origen) AS orden_en_fecha
  FROM `__PROYECTO__.__DATASET__.b_lecturas` AS l
),
cobertura AS (
  SELECT DISTINCT l.instrumento_cod, l.fecha
  FROM `__PROYECTO__.__DATASET__.b_lecturas` AS l
  JOIN `__PROYECTO__.__DATASET__.b_umbrales` AS u
    ON u.instrumento_cod = l.instrumento_cod AND u.nivel = 'NPC' AND l.fecha BETWEEN u.vigente_desde AND u.vigente_hasta
)
SELECT
  b.instrumento_cod, b.fecha, b.npa_msnm, b.npc_msnm, b.nac_msnm, b.nam_msnm, b.nca_msnm,
  b.fila_origen, b.archivo_sha256, b.cargado_utc,
  (b.n_misma_fecha > 1 AND b.npa_min_fecha = b.npa_max_fecha AND b.orden_en_fecha > 1) AS es_duplicado_exacto,
  (b.n_misma_fecha > 1 AND b.npa_min_fecha <> b.npa_max_fecha) AS es_fecha_conflicto,
  (b.npa_msnm IS NULL) AS es_npa_nulo,
  NOT (b.npc_msnm > b.nac_msnm AND b.nac_msnm > b.nam_msnm) AS fuera_escalera,
  (i.instrumento_cod IS NULL) AS sin_catalogo,
  (c.instrumento_cod IS NULL) AS sin_nivel_vigente
FROM base AS b
LEFT JOIN `__PROYECTO__.__DATASET__.b_instrumentos` AS i ON i.instrumento_cod = b.instrumento_cod
LEFT JOIN cobertura AS c ON c.instrumento_cod = b.instrumento_cod AND c.fecha = b.fecha;

CREATE OR REPLACE TABLE `__PROYECTO__.__DATASET__.g_lecturas` AS
SELECT
  s.instrumento_cod, s.fecha, i.dique, i.tipo, s.npa_msnm,
  npc.valor_msnm AS npc_msnm, nac.valor_msnm AS nac_msnm, nam.valor_msnm AS nam_msnm, nca.valor_msnm AS nca_msnm,
  npc.valor_msnm - s.npa_msnm AS margen_npc,
  nac.valor_msnm - s.npa_msnm AS margen_nac,
  nam.valor_msnm - s.npa_msnm AS margen_nam,
  nca.valor_msnm - s.npa_msnm AS margen_nca,
  (s.npa_msnm >= npc.valor_msnm) AS sobre_npc,
  (s.npa_msnm >= nac.valor_msnm) AS sobre_nac,
  (s.npa_msnm >= nam.valor_msnm) AS sobre_nam,
  s.fuera_escalera,
  npc.estado AS estado_niveles,
  (ABS(s.npc_msnm - npc.valor_msnm) < 0.000001 AND ABS(s.nac_msnm - nac.valor_msnm) < 0.000001
   AND ABS(s.nam_msnm - nam.valor_msnm) < 0.000001 AND ABS(s.nca_msnm - nca.valor_msnm) < 0.000001) AS niveles_coinciden_con_fila,
  s.fila_origen, s.archivo_sha256
FROM `__PROYECTO__.__DATASET__.s_lecturas` AS s
JOIN `__PROYECTO__.__DATASET__.b_instrumentos` AS i ON i.instrumento_cod = s.instrumento_cod
JOIN `__PROYECTO__.__DATASET__.b_umbrales` AS npc ON npc.instrumento_cod = s.instrumento_cod AND npc.nivel = 'NPC' AND s.fecha BETWEEN npc.vigente_desde AND npc.vigente_hasta
JOIN `__PROYECTO__.__DATASET__.b_umbrales` AS nac ON nac.instrumento_cod = s.instrumento_cod AND nac.nivel = 'NAC' AND s.fecha BETWEEN nac.vigente_desde AND nac.vigente_hasta
JOIN `__PROYECTO__.__DATASET__.b_umbrales` AS nam ON nam.instrumento_cod = s.instrumento_cod AND nam.nivel = 'NAM' AND s.fecha BETWEEN nam.vigente_desde AND nam.vigente_hasta
JOIN `__PROYECTO__.__DATASET__.b_umbrales` AS nca ON nca.instrumento_cod = s.instrumento_cod AND nca.nivel = 'NCA' AND s.fecha BETWEEN nca.vigente_desde AND nca.vigente_hasta
WHERE NOT s.es_duplicado_exacto AND NOT s.es_fecha_conflicto AND NOT s.es_npa_nulo;

    INSERT INTO `__PROYECTO__.__DATASET__.ejecuciones` (id_ejecucion, inicio, fin, filas_bronze, filas_silver, filas_gold, filas_excluidas, estado, detalle)
    SELECT v_id, v_ini, CURRENT_TIMESTAMP(),
      (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.b_lecturas`),
      (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.s_lecturas`),
      (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.g_lecturas`),
      (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.s_lecturas` WHERE es_duplicado_exacto OR es_fecha_conflicto),
      'OK', CAST(NULL AS STRING);
  EXCEPTION WHEN ERROR THEN
    INSERT INTO `__PROYECTO__.__DATASET__.ejecuciones` (id_ejecucion, inicio, fin, filas_bronze, filas_silver, filas_gold, filas_excluidas, estado, detalle)
    SELECT v_id, v_ini, CURRENT_TIMESTAMP(), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), 'ERROR', @@error.message;
    RAISE USING MESSAGE = @@error.message;
  END;
END;
