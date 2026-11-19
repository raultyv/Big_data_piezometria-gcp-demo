#!/usr/bin/env python3
"""Prueba local (sin la nube) de la lógica SQL del demo, con DuckDB y sqlglot.

Qué hace: genera los datos sintéticos, los carga en DuckDB, traduce el SQL de BigQuery
a DuckDB con sqlglot y ejecuta silver, gold, el modelo en estrella, el flujo de eventos
(simulado con las mismas fallas inyectadas), la vista híbrida y todas las verificaciones.

Qué NO prueba: BigQuery real (particionado, clustering, procedimientos, Pub/Sub, IAM).
Es una red de seguridad contra errores de lógica y de sintaxis comunes, no un reemplazo de
la corrida en Google Cloud.

Requiere: pip install duckdb sqlglot
Uso:      python3 tests/test_local_duckdb.py
"""
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
import uuid

import duckdb
import sqlglot

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "publicador"))
from eventos import construir_eventos  # noqa: E402


def leer(ruta):
    return open(os.path.join(RAIZ, ruta), encoding="utf-8").read()


def quitar_tokens(sql):
    return sql.replace("`__PROYECTO__.__DATASET__.", "`").replace("`__PROYECTO__.__DATASET__", "`")


def sentencias_de_procedimiento(sql):
    """Devuelve las sentencias DDL (CREATE OR REPLACE TABLE) del cuerpo de un procedimiento,
    sin el envoltorio BEGIN/EXCEPTION ni los INSERT de auditoría."""
    cuerpo = sql[sql.index("CREATE OR REPLACE TABLE"):]
    cuerpo = cuerpo[:cuerpo.index("INSERT INTO")]
    cuerpo = re.sub(r"\bPARTITION BY [^\n]+\nCLUSTER BY [^\n]+ AS", "AS", cuerpo)
    return cuerpo


def ejecutar(con, sql_bq):
    for st in sqlglot.parse(quitar_tokens(sql_bq), read="bigquery"):
        if st is None:
            continue
        con.execute(st.sql(dialect="duckdb"))


def consultar(con, sql_bq):
    st = [s for s in sqlglot.parse(quitar_tokens(sql_bq), read="bigquery") if s is not None][-1]
    return con.execute(st.sql(dialect="duckdb")).fetchall()


def main():
    tmp = tempfile.mkdtemp()
    subprocess.run([sys.executable, os.path.join(RAIZ, "synthetic", "generar_datos.py"), "--salida", tmp],
                   check=True, stdout=subprocess.DEVNULL)
    man = json.load(open(os.path.join(tmp, "manifiesto_control.json")))
    con = duckdb.connect()

    # --- bronce (mismos tipos que la carga con bq load) ---
    con.execute(f"""CREATE TABLE b_lecturas AS SELECT instrumento_cod, CAST(fecha AS DATE) AS fecha,
        npa_msnm, npc_msnm, nac_msnm, nam_msnm, nca_msnm, CAST(fila_origen AS BIGINT) AS fila_origen,
        archivo_sha256, CAST(cargado_utc AS TIMESTAMP) AS cargado_utc
        FROM read_csv_auto('{tmp}/bronze_piezometria_sintetico.csv')""")
    con.execute(f"CREATE TABLE b_instrumentos AS SELECT * FROM read_csv_auto('{tmp}/instrumentos_sintetico.csv')")
    con.execute(f"""CREATE TABLE b_umbrales AS SELECT instrumento_cod, nivel, valor_msnm,
        CAST(vigente_desde AS DATE) AS vigente_desde, CAST(vigente_hasta AS DATE) AS vigente_hasta, estado, fuente
        FROM read_csv_auto('{tmp}/umbrales_sintetico.csv')""")
    con.execute(f"CREATE TABLE b_manifiesto AS SELECT clave, CAST(valor AS VARCHAR) AS valor "
                f"FROM read_csv_auto('{tmp}/manifiesto_resumen.csv', types={{'valor': 'VARCHAR'}})")
    con.execute("""CREATE TABLE ejecuciones (id_ejecucion VARCHAR, inicio TIMESTAMP, fin TIMESTAMP,
        filas_bronze BIGINT, filas_silver BIGINT, filas_gold BIGINT, filas_excluidas BIGINT, estado VARCHAR, detalle VARCHAR)""")

    resultados = []

    def verificar(archivo, reemplazos=None):
        sql = leer(archivo)
        for k, v in (reemplazos or {}).items():
            sql = sql.replace(k, str(v))
        filas = consultar(con, sql)
        for c, e, o, r in filas:
            resultados.append((archivo.split("/")[-1], c, e, o, r))

    verificar("verificaciones/01_verificar_bronze.sql")

    # --- silver y gold ---
    ejecutar(con, sentencias_de_procedimiento(leer("sql/10_sp_actualizar.sql")))
    ejecutar(con, leer("sql/11_vista_exclusiones.sql"))
    con.execute("INSERT INTO ejecuciones VALUES ('t', now(), now(), 1, 1, 1, 0, 'OK', NULL)")
    verificar("verificaciones/02_verificar_silver_gold.sql")

    # --- modelo en estrella ---
    ejecutar(con, sentencias_de_procedimiento(leer("sql/20_sp_modelar.sql")))
    verificar("verificaciones/03_verificar_modelo.sql")
    # consultas analíticas A y B deben ejecutarse sin error y devolver filas
    partes = leer("sql/30_consultas_analiticas.sql").split("-- B.")
    n_a = len(consultar(con, partes[0].split("-- A.")[1].split("\n", 1)[1]))
    n_b = len(consultar(con, partes[1].split("\n", 1)[1]))
    resultados.append(("30_consultas_analiticas.sql", "consulta A devuelve filas", ">0", str(n_a), "OK" if n_a > 0 else "FALLA"))
    resultados.append(("30_consultas_analiticas.sql", "consulta B devuelve filas", ">0", str(n_b), "OK" if n_b > 0 else "FALLA"))

    # --- flujo de eventos simulado: mismas fallas inyectadas; los duplicados llegan con otro message_id ---
    base = [tuple(r) for r in con.execute(
        "SELECT instrumento_cod, fecha, npa_msnm FROM g_lecturas "
        "WHERE fecha >= (SELECT MAX(fecha) FROM g_lecturas) - INTERVAL 6 DAY ORDER BY fecha, instrumento_cod").fetchall()]
    base = [(i, f if isinstance(f, dt.date) else f.date(), n) for i, f, n in base]
    mensajes, resumen = construir_eventos(base)
    con.execute("CREATE TABLE b_eventos_raw (subscription_name VARCHAR, message_id VARCHAR, publish_time TIMESTAMP, data VARCHAR, attributes VARCHAR)")
    t0 = dt.datetime(2026, 11, 20, 12, 0, 0)
    run_id = "corrida-prueba"
    filas = []
    for k, m in enumerate(mensajes):
        gen = t0 + dt.timedelta(milliseconds=5 * k)
        carga = dict(m, run_id=run_id, ts_generado=gen.strftime("%Y-%m-%dT%H:%M:%S.") + f"{gen.microsecond // 1000:03d}+00:00")
        filas.append(("proyectos/p/suscripciones/s", str(uuid.uuid4()), gen + dt.timedelta(milliseconds=600),
                      json.dumps(carga), json.dumps({"run_id": run_id})))
    con.executemany("INSERT INTO b_eventos_raw VALUES (?, ?, ?, ?, ?)", filas)

    sql_ev = leer("sql/50_sp_procesar_eventos.sql")
    ejecutar(con, sentencias_de_procedimiento(sql_ev))
    ejecutar(con, leer("sql/60_vista_hibrida.sql"))
    verificar("verificaciones/04_verificar_eventos.sql", {
        "__ENVIADOS__": resumen["total_mensajes"], "__DUP__": resumen["duplicados_entrega"],
        "__SINCAT__": resumen["instrumento_inexistente"], "__NULOS__": resumen["npa_nulo"],
        "__NONUM__": resumen["npa_no_numerico"], "__GOLD_EV__": resumen["base"]})
    verificar("verificaciones/05_verificar_hibrida.sql")

    # --- informe ---
    ancho = max(len(r[1]) for r in resultados)
    fallas = 0
    for archivo, c, e, o, r in resultados:
        print(f"[{r:5}] {c:<{ancho}}  esperado={e}  observado={o}")
        fallas += r != "OK"
    print(f"\n{len(resultados)} comprobaciones, {fallas} con FALLA")
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
