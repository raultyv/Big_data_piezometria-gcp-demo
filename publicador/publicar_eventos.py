#!/usr/bin/env python3
"""Publica en Pub/Sub las lecturas de los últimos 7 días del lote (fechas +7 días), mide la latencia
y espera a que todo sea consultable en BigQuery. Es el equivalente en terminal del notebook B4.

Requiere: pip install google-cloud-pubsub google-cloud-bigquery  y credenciales (en Cloud Shell ya están).
Se detiene si la tabla cruda ya tiene mensajes, salvo --permitir-repetir.
"""
import argparse
import datetime
import json
import os
import statistics
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eventos import construir_eventos  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--proyecto", required=True)
    ap.add_argument("--dataset", default="piezometria_demo")
    ap.add_argument("--ubicacion", default="southamerica-east1")
    ap.add_argument("--tema", default="lecturas-piezo")
    ap.add_argument("--salida", default="salidas/resumen_eventos.json")
    ap.add_argument("--permitir-repetir", action="store_true")
    a = ap.parse_args()

    from google.cloud import bigquery, pubsub_v1
    os.environ.setdefault("GOOGLE_CLOUD_QUOTA_PROJECT", a.proyecto)
    bq = bigquery.Client(project=a.proyecto, location=a.ubicacion)
    ds = f"{a.proyecto}.{a.dataset}"
    raw = f"`{ds}.b_eventos_raw`"

    previos = list(bq.query(f"SELECT COUNT(*) AS n FROM {raw}").result())[0].n
    if previos > 0 and not a.permitir_repetir:
        sys.exit(f"La tabla cruda ya tiene {previos} mensajes. No se publica de nuevo (use --permitir-repetir).")

    # Lecturas base: los últimos 7 días de gold (la ventana se calcula, no se fija).
    filas = bq.query(f"""
        SELECT instrumento_cod, fecha, npa_msnm
        FROM `{ds}.g_lecturas`
        WHERE fecha >= DATE_SUB((SELECT MAX(fecha) FROM `{ds}.g_lecturas`), INTERVAL 6 DAY)
        ORDER BY fecha, instrumento_cod
    """).result()
    base = [(f.instrumento_cod, f.fecha, f.npa_msnm) for f in filas]
    mensajes, resumen = construir_eventos(base)
    print("Lecturas base leídas de gold:", len(base))
    for k, v in resumen.items():
        print(f"  {k}: {v}")

    run_id = "corrida-" + time.strftime("%Y%m%d-%H%M%S", time.gmtime())
    pub = pubsub_v1.PublisherClient()
    ruta = pub.topic_path(a.proyecto, a.tema)
    total = len(mensajes)
    acks_ms, futuros = [], []

    def marcar(inicio):
        def cb(_):
            acks_ms.append((time.perf_counter() - inicio) * 1000)
        return cb

    print(f"RUN_ID {run_id} · publicando {total} mensajes en {ruta}")
    t0 = time.perf_counter()
    for i, m in enumerate(mensajes, 1):
        carga = dict(m, run_id=run_id,
                     ts_generado=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds"))
        fut = pub.publish(ruta, json.dumps(carga).encode("utf-8"), run_id=run_id)
        fut.add_done_callback(marcar(time.perf_counter()))
        futuros.append(fut)
        if i % 100 == 0 or i == total:
            print(f"  enviados {i}/{total}")
    for f in futuros:
        f.result(timeout=120)
    t_pub = time.perf_counter() - t0
    print(f"Todos los mensajes confirmados por Pub/Sub en {t_pub:.2f} s")

    consulta = f"SELECT COUNT(*) AS n FROM {raw} WHERE JSON_VALUE(data, '$.run_id') = '{run_id}'"
    cfg = bigquery.QueryJobConfig(use_query_cache=False)
    recibidos, t_visible = 0, None
    while time.perf_counter() - t0 < 300:
        recibidos = list(bq.query(consulta, job_config=cfg).result())[0].n
        print(f"  en BigQuery: {recibidos}/{total}  (t = {time.perf_counter() - t0:.1f} s)")
        if recibidos >= total:
            t_visible = time.perf_counter() - t0
            break
        time.sleep(2)

    q = statistics.quantiles(acks_ms, n=20) if len(acks_ms) >= 2 else [0] * 19
    out = {
        "run_id": run_id, "enviados": total, "recibidos": recibidos, "diferencia": total - recibidos,
        "base": resumen["base"], "duplicados_entrega": resumen["duplicados_entrega"],
        "instrumento_inexistente": resumen["instrumento_inexistente"],
        "npa_nulo": resumen["npa_nulo"], "npa_no_numerico": resumen["npa_no_numerico"],
        "gold_eventos_esperado": resumen["base"],
        "ack_mediana_ms": round(statistics.median(acks_ms)) if acks_ms else None,
        "ack_p95_ms": round(q[18]), "ack_max_ms": round(max(acks_ms)) if acks_ms else None,
        "segundos_hasta_publicar": round(t_pub, 2),
        "segundos_hasta_consultable": round(t_visible, 1) if t_visible else None,
    }
    os.makedirs(os.path.dirname(a.salida) or ".", exist_ok=True)
    with open(a.salida, "w") as f:
        json.dump(out, f, indent=2)
    print("\nRESUMEN DE LA CORRIDA")
    for k, v in out.items():
        print(f"  {k}: {v}")
    if recibidos < total:
        sys.exit("No llegaron todos los mensajes en 300 s.")


if __name__ == "__main__":
    main()
