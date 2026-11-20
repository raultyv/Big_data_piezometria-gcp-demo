-- Capa de exposición: tres vistas de solo lectura que las aplicaciones consumidoras
-- (tableros, scripts, la API REST de BigQuery) pueden consultar sin conocer bronze, silver ni gold.
-- Todas leen v_lectura_hibrida (lote histórico + flujo posterior a la marca de agua).
-- Tokens __PROYECTO__ y __DATASET__: los reemplaza scripts/comun.sh.
-- Aviso: "en_o_sobre_nam" compara con niveles provisionales del generador sintético;
-- no es una evaluación de seguridad.

-- 1. Última lectura de cada instrumento
CREATE OR REPLACE VIEW `__PROYECTO__.__DATASET__.api_ultima_lectura` AS
SELECT instrumento_cod, dique, tipo, fecha AS ultima_fecha, origen,
       ROUND(npa_msnm, 3) AS npa_msnm, ROUND(nam_msnm, 3) AS nam_msnm,
       ROUND(margen_nam, 3) AS margen_nam_m, sobre_nam AS en_o_sobre_nam
FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY instrumento_cod ORDER BY fecha DESC) AS orden
  FROM `__PROYECTO__.__DATASET__.v_lectura_hibrida`
)
WHERE orden = 1;

-- 2. Resumen por dique
CREATE OR REPLACE VIEW `__PROYECTO__.__DATASET__.api_resumen_dique` AS
SELECT dique,
       COUNT(DISTINCT instrumento_cod) AS instrumentos,
       COUNT(*) AS lecturas,
       MAX(fecha) AS ultima_fecha,
       COUNTIF(sobre_nam) AS lecturas_en_o_sobre_nam
FROM `__PROYECTO__.__DATASET__.v_lectura_hibrida`
GROUP BY dique;

-- 3. Serie de un instrumento (la API la filtra con un parámetro: WHERE instrumento_cod = @instrumento)
CREATE OR REPLACE VIEW `__PROYECTO__.__DATASET__.api_serie_instrumento` AS
SELECT instrumento_cod, fecha, origen,
       ROUND(npa_msnm, 3) AS npa_msnm, ROUND(margen_nam, 3) AS margen_nam_m, sobre_nam AS en_o_sobre_nam
FROM `__PROYECTO__.__DATASET__.v_lectura_hibrida`;
