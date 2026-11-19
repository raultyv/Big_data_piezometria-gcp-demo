-- Tabla de auditoría de ejecuciones
-- Cada procedimiento deja una fila (OK o ERROR). Origen: informe de la entrega 2, anexo C.2.
-- Tokens __PROYECTO__ y __DATASET__: los reemplaza scripts/ejecutar_sql.sh.

CREATE TABLE IF NOT EXISTS `__PROYECTO__.__DATASET__.ejecuciones` (
  id_ejecucion STRING, inicio TIMESTAMP, fin TIMESTAMP,
  filas_bronze INT64, filas_silver INT64, filas_gold INT64, filas_excluidas INT64,
  estado STRING, detalle STRING
);
