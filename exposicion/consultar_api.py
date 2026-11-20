#!/usr/bin/env python3
"""Consulta la capa de exposición por la API REST de BigQuery y devuelve JSON.

Es un cliente mínimo (solo biblioteca estándar): hace POST a
  https://bigquery.googleapis.com/bigquery/v2/projects/<proyecto>/queries
con un token de la sesión de gcloud (no se imprime ni se guarda).

Uso (desde la raíz del repositorio, con config.env listo):
  ./consultar.sh ultima_lectura [--limite 5]
  ./consultar.sh resumen_dique
  ./consultar.sh serie --instrumento PZ-001 [--limite 5]
"""
import argparse
import json
import subprocess
import sys
import time
import urllib.request

VISTAS = {
    "ultima_lectura": ("api_ultima_lectura", "ORDER BY margen_nam_m"),
    "resumen_dique": ("api_resumen_dique", "ORDER BY dique"),
    "serie": ("api_serie_instrumento", "ORDER BY fecha DESC"),
}


def convertir(valor, tipo):
    if valor is None:
        return None
    if tipo in ("INTEGER", "INT64"):
        return int(valor)
    if tipo in ("FLOAT", "FLOAT64"):
        return float(valor)
    if tipo in ("BOOLEAN", "BOOL"):
        return valor in (True, "true", "True")
    return valor


def filas_desde_respuesta(resp):
    """Convierte la respuesta de BigQuery (campos f/v) en una lista de diccionarios."""
    campos = [(c["name"], c["type"]) for c in resp["schema"]["fields"]]
    return [{n: convertir(celda["v"], t) for (n, t), celda in zip(campos, fila["f"])}
            for fila in resp.get("rows", [])]


def token():
    return subprocess.check_output(["gcloud", "auth", "print-access-token"], text=True).strip()


def llamar(url, tk, cuerpo=None):
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    req = urllib.request.Request(url, data=datos, headers={
        "Authorization": f"Bearer {tk}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("recurso", choices=VISTAS)
    ap.add_argument("--proyecto", required=True)
    ap.add_argument("--dataset", required=True)
    ap.add_argument("--ubicacion", required=True)
    ap.add_argument("--instrumento", help="código de instrumento (solo para 'serie')")
    ap.add_argument("--limite", type=int, default=5)
    a = ap.parse_args()

    vista, orden = VISTAS[a.recurso]
    sql = f"SELECT * FROM `{a.proyecto}.{a.dataset}.{vista}`"
    cuerpo = {"useLegacySql": False, "location": a.ubicacion, "timeoutMs": 30000, "maxResults": 1000}
    if a.recurso == "serie":
        if not a.instrumento:
            sys.exit("Para 'serie' indique --instrumento")
        sql += " WHERE instrumento_cod = @instrumento"
        cuerpo["parameterMode"] = "NAMED"
        cuerpo["queryParameters"] = [{"name": "instrumento", "parameterType": {"type": "STRING"},
                                      "parameterValue": {"value": a.instrumento}}]
    cuerpo["query"] = f"{sql} {orden} LIMIT {int(a.limite)}"

    base = f"https://bigquery.googleapis.com/bigquery/v2/projects/{a.proyecto}"
    print(f"POST {base}/queries", file=sys.stderr)
    tk = token()
    t0 = time.time()
    resp = llamar(f"{base}/queries", tk, cuerpo)
    while not resp.get("jobComplete", True):
        ref = resp["jobReference"]
        resp = llamar(f"{base}/queries/{ref['jobId']}?location={ref.get('location', a.ubicacion)}", tk)
    ms = round((time.time() - t0) * 1000)
    filas = filas_desde_respuesta(resp)
    print(json.dumps({"recurso": a.recurso, "vista": vista, "tiempo_ms": ms,
                      "filas_devueltas": len(filas), "filas": filas}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
