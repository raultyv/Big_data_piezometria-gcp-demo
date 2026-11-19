-- Latencia hasta publicar, sobre los eventos únicos
-- Origen: informe de la entrega 2, anexo C.11.
-- Tokens __PROYECTO__ y __DATASET__: los reemplaza scripts/ejecutar_sql.sh.

SELECT COUNT(*) AS mensajes_unicos,
       ROUND(APPROX_QUANTILES(ms_hasta_publicar, 100)[OFFSET(50)]) AS mediana_ms,
       ROUND(APPROX_QUANTILES(ms_hasta_publicar, 100)[OFFSET(95)]) AS p95_ms,
       MIN(ms_hasta_publicar) AS minimo_ms,
       MAX(ms_hasta_publicar) AS maximo_ms,
       TIMESTAMP_DIFF(MAX(publish_time), MIN(publish_time), MILLISECOND) AS ventana_publicacion_ms
FROM `__PROYECTO__.__DATASET__.s_eventos`
WHERE NOT es_duplicado_entrega;
