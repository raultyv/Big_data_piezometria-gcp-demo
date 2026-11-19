-- sp_procesar_eventos(): silver y gold del flujo en tiempo real simulado
-- Origen: informe de la entrega 2, anexo C.9.
-- Tokens __PROYECTO__ y __DATASET__: los reemplaza scripts/ejecutar_sql.sh.

CREATE OR REPLACE PROCEDURE `__PROYECTO__.__DATASET__.sp_procesar_eventos`()
BEGIN
  DECLARE v_id STRING DEFAULT GENERATE_UUID();
  DECLARE v_ini TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  BEGIN
CREATE OR REPLACE TABLE `__PROYECTO__.__DATASET__.s_eventos` AS
WITH parsed AS (
  SELECT
    message_id, publish_time,
    JSON_VALUE(data, '$.evento_id') AS evento_id,
    JSON_VALUE(data, '$.run_id') AS run_id,
    JSON_VALUE(data, '$.instrumento_cod') AS instrumento_cod,
    SAFE_CAST(JSON_VALUE(data, '$.fecha') AS DATE) AS fecha,
    JSON_VALUE(data, '$.npa_msnm') AS npa_texto,
    SAFE_CAST(JSON_VALUE(data, '$.npa_msnm') AS FLOAT64) AS npa_msnm,
    SAFE_CAST(JSON_VALUE(data, '$.ts_generado') AS TIMESTAMP) AS ts_generado
  FROM `__PROYECTO__.__DATASET__.b_eventos_raw`
),
ordenado AS (
  SELECT p.*, ROW_NUMBER() OVER (PARTITION BY evento_id ORDER BY publish_time, message_id) AS orden_evento
  FROM parsed AS p
)
SELECT
  o.message_id, o.evento_id, o.run_id, o.instrumento_cod, o.fecha, o.npa_msnm, o.ts_generado, o.publish_time,
  TIMESTAMP_DIFF(o.publish_time, o.ts_generado, MILLISECOND) AS ms_hasta_publicar,
  (o.orden_evento > 1) AS es_duplicado_entrega,
  (i.instrumento_cod IS NULL) AS sin_catalogo,
  (o.npa_texto IS NULL) AS es_npa_nulo,
  (o.npa_texto IS NOT NULL AND o.npa_msnm IS NULL) AS es_npa_no_numerico,
  (o.fecha IS NULL) AS es_fecha_invalida
FROM ordenado AS o
LEFT JOIN `__PROYECTO__.__DATASET__.b_instrumentos` AS i ON i.instrumento_cod = o.instrumento_cod;

CREATE OR REPLACE TABLE `__PROYECTO__.__DATASET__.g_eventos` AS
WITH validos AS (
  SELECT s.*, ROW_NUMBER() OVER (PARTITION BY s.instrumento_cod, s.fecha ORDER BY s.publish_time DESC, s.message_id) AS orden_dia
  FROM `__PROYECTO__.__DATASET__.s_eventos` AS s
  WHERE NOT s.es_duplicado_entrega AND NOT s.sin_catalogo AND NOT s.es_npa_nulo AND NOT s.es_npa_no_numerico AND NOT s.es_fecha_invalida
),
unicos AS (SELECT * FROM validos WHERE orden_dia = 1),
tramos AS (
  SELECT u.evento_id, u.nivel, u.valor_msnm, u.estado
  FROM (
    SELECT e.evento_id, b.nivel, b.valor_msnm, b.estado,
           ROW_NUMBER() OVER (PARTITION BY e.evento_id, b.nivel ORDER BY b.vigente_desde DESC) AS rn
    FROM unicos AS e
    JOIN `__PROYECTO__.__DATASET__.b_umbrales` AS b ON b.instrumento_cod = e.instrumento_cod AND b.vigente_desde <= e.fecha
  ) AS u
  WHERE u.rn = 1
)
SELECT
  e.instrumento_cod, e.fecha, i.dique, i.tipo, e.npa_msnm,
  npc.valor_msnm AS npc_msnm, nac.valor_msnm AS nac_msnm, nam.valor_msnm AS nam_msnm, nca.valor_msnm AS nca_msnm,
  npc.valor_msnm - e.npa_msnm AS margen_npc,
  nac.valor_msnm - e.npa_msnm AS margen_nac,
  nam.valor_msnm - e.npa_msnm AS margen_nam,
  nca.valor_msnm - e.npa_msnm AS margen_nca,
  (e.npa_msnm >= npc.valor_msnm) AS sobre_npc,
  (e.npa_msnm >= nac.valor_msnm) AS sobre_nac,
  (e.npa_msnm >= nam.valor_msnm) AS sobre_nam,
  NOT (npc.valor_msnm > nac.valor_msnm AND nac.valor_msnm > nam.valor_msnm) AS fuera_escalera,
  npc.estado AS estado_niveles,
  e.evento_id, e.publish_time
FROM unicos AS e
JOIN `__PROYECTO__.__DATASET__.b_instrumentos` AS i ON i.instrumento_cod = e.instrumento_cod
JOIN tramos AS npc ON npc.evento_id = e.evento_id AND npc.nivel = 'NPC'
JOIN tramos AS nac ON nac.evento_id = e.evento_id AND nac.nivel = 'NAC'
JOIN tramos AS nam ON nam.evento_id = e.evento_id AND nam.nivel = 'NAM'
JOIN tramos AS nca ON nca.evento_id = e.evento_id AND nca.nivel = 'NCA';

    INSERT INTO `__PROYECTO__.__DATASET__.ejecuciones` (id_ejecucion, inicio, fin, filas_bronze, filas_silver, filas_gold, filas_excluidas, estado, detalle)
    SELECT v_id, v_ini, CURRENT_TIMESTAMP(),
      (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.b_eventos_raw`),
      (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.s_eventos`),
      (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.g_eventos`),
      (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.s_eventos`) - (SELECT COUNT(*) FROM `__PROYECTO__.__DATASET__.g_eventos`),
      'OK', 'eventos en tiempo real: filas_bronze = mensajes crudos de Pub/Sub';
  EXCEPTION WHEN ERROR THEN
    INSERT INTO `__PROYECTO__.__DATASET__.ejecuciones` (id_ejecucion, inicio, fin, filas_bronze, filas_silver, filas_gold, filas_excluidas, estado, detalle)
    SELECT v_id, v_ini, CURRENT_TIMESTAMP(), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), 'ERROR', @@error.message;
    RAISE USING MESSAGE = @@error.message;
  END;
END;
