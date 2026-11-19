-- v_lectura_hibrida: lote histórico + flujo posterior a la marca de agua
-- Origen: informe de la entrega 2, anexo C.10.
-- Tokens __PROYECTO__ y __DATASET__: los reemplaza scripts/ejecutar_sql.sh.

CREATE OR REPLACE VIEW `__PROYECTO__.__DATASET__.v_lectura_hibrida` AS
SELECT 'batch' AS origen, instrumento_cod, fecha, dique, tipo, npa_msnm,
       npc_msnm, nac_msnm, nam_msnm, nca_msnm, margen_npc, margen_nac, margen_nam, margen_nca,
       sobre_npc, sobre_nac, sobre_nam, fuera_escalera
FROM `__PROYECTO__.__DATASET__.g_lecturas`
UNION ALL
SELECT 'stream' AS origen, instrumento_cod, fecha, dique, tipo, npa_msnm,
       npc_msnm, nac_msnm, nam_msnm, nca_msnm, margen_npc, margen_nac, margen_nam, margen_nca,
       sobre_npc, sobre_nac, sobre_nam, fuera_escalera
FROM `__PROYECTO__.__DATASET__.g_eventos`
WHERE fecha > (SELECT MAX(fecha) FROM `__PROYECTO__.__DATASET__.g_lecturas`);
