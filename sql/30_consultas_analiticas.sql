-- Consultas analíticas A y B sobre el modelo en estrella
-- Origen: informe de la entrega 2, anexos C.5 y C.6.
-- Tokens __PROYECTO__ y __DATASET__: los reemplaza scripts/ejecutar_sql.sh.

-- A. Lecturas en o sobre el NAM por dique, tipo y mes
SELECT i.dique, i.tipo, d.anio_mes,
       COUNT(*) AS lecturas,
       COUNTIF(f.sobre_nam) AS lecturas_en_o_sobre_nam,
       ROUND(MIN(f.margen_nam), 3) AS margen_nam_minimo_m
FROM `__PROYECTO__.__DATASET__.fact_lectura` AS f
JOIN `__PROYECTO__.__DATASET__.dim_instrumento` AS i USING (instrumento_key)
JOIN `__PROYECTO__.__DATASET__.dim_fecha` AS d USING (fecha_key)
GROUP BY i.dique, i.tipo, d.anio_mes
HAVING COUNTIF(f.sobre_nam) > 0
ORDER BY lecturas_en_o_sobre_nam DESC, d.anio_mes
LIMIT 10;

-- B. Última lectura de cada instrumento y su margen al NAM
SELECT instrumento_cod, dique, tipo, fecha AS ultima_lectura, ROUND(npa_msnm, 3) AS npa_msnm, ROUND(margen_nam, 3) AS margen_nam_m, sobre_nam
FROM (
  SELECT i.instrumento_cod, i.dique, i.tipo, f.fecha, f.npa_msnm, f.margen_nam, f.sobre_nam,
         ROW_NUMBER() OVER (PARTITION BY f.instrumento_key ORDER BY f.fecha DESC) AS orden
  FROM `__PROYECTO__.__DATASET__.fact_lectura` AS f
  JOIN `__PROYECTO__.__DATASET__.dim_instrumento` AS i USING (instrumento_key)
)
WHERE orden = 1
ORDER BY margen_nam_m
LIMIT 10;
