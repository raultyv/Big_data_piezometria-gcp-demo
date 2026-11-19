-- v_exclusiones: motivo de cada fila que no pasa a gold
-- Origen: informe de la entrega 2, anexo C.3.
-- Tokens __PROYECTO__ y __DATASET__: los reemplaza scripts/ejecutar_sql.sh.

CREATE OR REPLACE VIEW `__PROYECTO__.__DATASET__.v_exclusiones` AS
SELECT
  instrumento_cod, fecha, npa_msnm, fila_origen,
  IF(es_fecha_conflicto, 'Fecha en conflicto: mismo instrumento y fecha con NPA distinto', 'Duplicado exacto: segunda copia del mismo valor') AS motivo
FROM `__PROYECTO__.__DATASET__.s_lecturas`
WHERE es_duplicado_exacto OR es_fecha_conflicto
ORDER BY instrumento_cod, fecha, fila_origen;
