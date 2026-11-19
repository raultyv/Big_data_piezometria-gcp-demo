-- sp_modelar(): esquema en estrella (dim_instrumento, dim_fecha, dim_umbral, fact_lectura)
-- Origen: informe de la entrega 2, anexo C.4.
-- Tokens __PROYECTO__ y __DATASET__: los reemplaza scripts/ejecutar_sql.sh.

CREATE OR REPLACE PROCEDURE `__PROYECTO__.__DATASET__.sp_modelar`()
BEGIN
  DECLARE v_id STRING DEFAULT GENERATE_UUID();
  DECLARE v_ini TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  BEGIN
CREATE OR REPLACE TABLE `__PROYECTO__.__DATASET__.dim_instrumento` AS
SELECT
  ROW_NUMBER() OVER (ORDER BY instrumento_cod) AS instrumento_key,
  instrumento_cod, dique, tipo, este_seudo, norte_seudo
FROM `__PROYECTO__.__DATASET__.b_instrumentos`;

CREATE OR REPLACE TABLE `__PROYECTO__.__DATASET__.dim_fecha` AS
SELECT
  CAST(FORMAT_DATE('%Y%m%d', d) AS INT64) AS fecha_key,
  d AS fecha,
  EXTRACT(YEAR FROM d) AS anio,
  EXTRACT(QUARTER FROM d) AS trimestre,
  EXTRACT(MONTH FROM d) AS mes,
  FORMAT_DATE('%Y-%m', d) AS anio_mes,
  EXTRACT(DAYOFWEEK FROM d) AS dia_semana,
  EXTRACT(DAYOFWEEK FROM d) IN (1, 7) AS es_fin_de_semana
FROM UNNEST(GENERATE_DATE_ARRAY(
  (SELECT MIN(fecha) FROM `__PROYECTO__.__DATASET__.b_lecturas`),
  (SELECT MAX(fecha) FROM `__PROYECTO__.__DATASET__.b_lecturas`)
)) AS d;

CREATE OR REPLACE TABLE `__PROYECTO__.__DATASET__.dim_umbral` AS
SELECT
  ROW_NUMBER() OVER (ORDER BY u.instrumento_cod, u.nivel, u.vigente_desde) AS umbral_key,
  di.instrumento_key, u.nivel, u.valor_msnm, u.vigente_desde, u.vigente_hasta, u.estado, u.fuente
FROM `__PROYECTO__.__DATASET__.b_umbrales` AS u
JOIN `__PROYECTO__.__DATASET__.dim_instrumento` AS di ON di.instrumento_cod = u.instrumento_cod;

CREATE OR REPLACE TABLE `__PROYECTO__.__DATASET__.fact_lectura`
PARTITION BY DATE_TRUNC(fecha, MONTH)
CLUSTER BY instrumento_key AS
SELECT
  di.instrumento_key,
  CAST(FORMAT_DATE('%Y%m%d', g.fecha) AS INT64) AS fecha_key,
  g.fecha,
  g.npa_msnm,
  g.margen_npc, g.margen_nac, g.margen_nam, g.margen_nca,
  g.sobre_npc, g.sobre_nac, g.sobre_nam,
  g.fuera_escalera,
  npc.umbral_key AS umbral_npc_key, nac.umbral_key AS umbral_nac_key,
  nam.umbral_key AS umbral_nam_key, nca.umbral_key AS umbral_nca_key,
  g.fila_origen, g.archivo_sha256
FROM `__PROYECTO__.__DATASET__.g_lecturas` AS g
JOIN `__PROYECTO__.__DATASET__.dim_instrumento` AS di ON di.instrumento_cod = g.instrumento_cod
JOIN `__PROYECTO__.__DATASET__.dim_umbral` AS npc ON npc.instrumento_key = di.instrumento_key AND npc.nivel = 'NPC' AND g.fecha BETWEEN npc.vigente_desde AND npc.vigente_hasta
JOIN `__PROYECTO__.__DATASET__.dim_umbral` AS nac ON nac.instrumento_key = di.instrumento_key AND nac.nivel = 'NAC' AND g.fecha BETWEEN nac.vigente_desde AND nac.vigente_hasta
JOIN `__PROYECTO__.__DATASET__.dim_umbral` AS nam ON nam.instrumento_key = di.instrumento_key AND nam.nivel = 'NAM' AND g.fecha BETWEEN nam.vigente_desde AND nam.vigente_hasta
JOIN `__PROYECTO__.__DATASET__.dim_umbral` AS nca ON nca.instrumento_key = di.instrumento_key AND nca.nivel = 'NCA' AND g.fecha BETWEEN nca.vigente_desde AND nca.vigente_hasta;

    INSERT INTO `__PROYECTO__.__DATASET__.ejecuciones` (id_ejecucion, inicio, fin, filas_bronze, filas_silver, filas_gold, filas_excluidas, estado, detalle)
    SELECT v_id, v_ini, CURRENT_TIMESTAMP(), CAST(NULL AS INT64), CAST(NULL AS INT64),
      (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.fact_lectura`), CAST(NULL AS INT64), 'OK',
      FORMAT('modelo estrella: fact_lectura=%d, dim_instrumento=%d, dim_fecha=%d, dim_umbral=%d',
        (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.fact_lectura`), (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.dim_instrumento`),
        (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.dim_fecha`), (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.dim_umbral`));
  EXCEPTION WHEN ERROR THEN
    INSERT INTO `__PROYECTO__.__DATASET__.ejecuciones` (id_ejecucion, inicio, fin, filas_bronze, filas_silver, filas_gold, filas_excluidas, estado, detalle)
    SELECT v_id, v_ini, CURRENT_TIMESTAMP(), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), 'ERROR', @@error.message;
    RAISE USING MESSAGE = @@error.message;
  END;
END;
