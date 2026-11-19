#!/usr/bin/env python3
"""Generador de datos SINTÉTICOS de piezometría para el demo.

Produce los mismos archivos y columnas que el lote de la entrega 2, pero con
valores inventados por este script. No contiene ni deriva de datos de ninguna
operación: códigos INS-###, coordenadas y niveles son arbitrarios.

Qué reproduce (para ejercitar las reglas de calidad y el modelo):
  - 80 instrumentos, dique Principal/Lateral, tipo Tubo Abierto/Cuerda Vibrante.
  - Lecturas diarias del 2025-01-01 al 2026-06-01, con cadencias mixtas
    (instrumentos casi diarios y otros esporádicos) y un instrumento con la serie cortada.
  - Niveles NPC, NAC, NAM y NCA con vigencia (algunos instrumentos con varios tramos),
    todos marcados 'provisional'. Una parte de los instrumentos NO cumple NPC > NAC > NAM.
  - Duplicados exactos y fechas en conflicto, y tres instrumentos con lecturas en o sobre el NAM.
  - Un manifiesto con los conteos esperados, calculados aquí de forma independiente,
    que las verificaciones comparan contra BigQuery.

Solo usa la biblioteca estándar de Python.

Uso:
    python3 generar_datos.py --salida ../data --semilla 42
"""
import argparse
import csv
import datetime as dt
import hashlib
import json
import math
import os
import random

VENTANA_INI = dt.date(2025, 1, 1)
VENTANA_FIN = dt.date(2026, 6, 1)
N_INSTRUMENTOS = 80
N_PRINCIPAL = 37          # el resto son laterales
N_TUBO_ABIERTO = 45       # el resto son cuerda vibrante
N_ESPORADICOS = 15        # instrumentos con 21 a 34 % de los días
N_DUP_EXACTOS = 26
N_CONFLICTOS = 2          # pares con el mismo instrumento y fecha y NPA distinto
N_SOBRE_NAM = 3           # instrumentos con lecturas en o sobre el NAM
FRAC_ESCALERA_OK = 0.30   # fracción que cumple NPC > NAC > NAM
FRAC_MULTITRAMO = 0.26    # fracción con más de un tramo de niveles
CARGADO_UTC = "2026-01-01T00:00:00Z"   # fijo: la salida es determinista


def dias(ini, fin):
    d = ini
    while d <= fin:
        yield d
        d += dt.timedelta(days=1)


def generar(semilla):
    rnd = random.Random(semilla)
    todos_los_dias = list(dias(VENTANA_INI, VENTANA_FIN))

    # ---------------- catálogo ----------------
    codigos = [f"INS-{i:03d}" for i in range(1, N_INSTRUMENTOS + 1)]
    diques = ["Principal"] * N_PRINCIPAL + ["Lateral"] * (N_INSTRUMENTOS - N_PRINCIPAL)
    tipos = (["Piezometro Tubo Abierto"] * N_TUBO_ABIERTO
             + ["Piezometro Cuerda Vibrante"] * (N_INSTRUMENTOS - N_TUBO_ABIERTO))
    rnd.shuffle(diques)
    rnd.shuffle(tipos)
    instrumentos = []
    for cod, dq, tp in zip(codigos, diques, tipos):
        # Coordenadas arbitrarias: no corresponden a ningún sitio real.
        instrumentos.append({
            "instrumento_cod": cod, "dique": dq, "tipo": tp,
            "este_seudo": round(rnd.uniform(500000, 505000), 3),
            "norte_seudo": round(rnd.uniform(7000000, 7003000), 3),
        })

    # ---------------- niveles con vigencia ----------------
    ok = set(rnd.sample(codigos, round(FRAC_ESCALERA_OK * N_INSTRUMENTOS)))
    multi = set(rnd.sample(codigos, round(FRAC_MULTITRAMO * N_INSTRUMENTOS)))
    umbrales = []          # filas del CSV
    niveles_por_ins = {}   # cod -> lista de (desde, hasta, {nivel: valor})
    for cod in codigos:
        npc = round(rnd.uniform(2400, 2500), 3)
        if cod in ok:
            nac = round(npc - rnd.uniform(0.8, 2.0), 3)
            nam = round(nac - rnd.uniform(0.8, 2.0), 3)
        elif rnd.random() < 0.5:
            nac = round(npc + rnd.uniform(0.3, 1.5), 3)       # NAC por encima de NPC
            nam = round(nac - rnd.uniform(0.8, 2.0), 3)
        else:
            nac = round(npc - rnd.uniform(0.8, 2.0), 3)
            nam = round(nac + rnd.uniform(0.3, 1.5), 3)       # NAM por encima de NAC
        nca = round(npc + rnd.uniform(30, 60), 3)
        base = {"NPC": npc, "NAC": nac, "NAM": nam, "NCA": nca}

        if cod in multi:
            k = rnd.choice([2, 2, 3, 4])
            cortes = sorted(rnd.sample(todos_los_dias[30:-30], k - 1))
        else:
            cortes = []
        limites, ini = [], VENTANA_INI
        for c in cortes:
            limites.append((ini, c - dt.timedelta(days=1)))
            ini = c
        limites.append((ini, VENTANA_FIN))
        tramos = []
        for n_tramo, (d, h) in enumerate(limites):
            if n_tramo == 0:
                vals = dict(base)
            else:
                vals = dict(tramos[-1][2])
                vals["NPC"] = round(vals["NPC"] + rnd.uniform(-0.6, 0.6), 3)
                if rnd.random() < 0.5:
                    vals["NAC"] = round(vals["NAC"] + rnd.uniform(-0.6, 0.6), 3)
                if rnd.random() < 0.5:
                    vals["NAM"] = round(vals["NAM"] + rnd.uniform(-0.6, 0.6), 3)
            tramos.append((d, h, vals))
        niveles_por_ins[cod] = tramos
        for d, h, vals in tramos:
            for nivel in ("NPC", "NAC", "NAM", "NCA"):
                umbrales.append({
                    "instrumento_cod": cod, "nivel": nivel, "valor_msnm": vals[nivel],
                    "vigente_desde": d.isoformat(), "vigente_hasta": h.isoformat(),
                    "estado": "provisional", "fuente": "SINTETICO (definido por el generador)",
                })

    def niveles_en(cod, fecha):
        for d, h, vals in niveles_por_ins[cod]:
            if d <= fecha <= h:
                return vals
        raise ValueError("sin cobertura")  # no debe ocurrir

    # ---------------- lecturas ----------------
    esporadicos = set(rnd.sample(codigos, N_ESPORADICOS))
    cortado = rnd.choice(sorted(esporadicos))              # serie cortada a mitad de la ventana
    sobre_nam = set(rnd.sample(sorted(set(codigos) - esporadicos), N_SOBRE_NAM))
    lecturas = []   # dicts con instrumento_cod, fecha, npa, fila_origen (sin huella ni carga)
    por_ins = {}
    for cod in codigos:
        v0 = niveles_en(cod, VENTANA_INI)
        # nivel medio respecto del NAM del primer tramo (valor sintético)
        media = v0["NAM"] + 0.25 if cod in sobre_nam else v0["NAM"] - rnd.uniform(1.0, 6.0)
        amp = rnd.uniform(0.1, 0.4)
        fase = rnd.uniform(0, 2 * math.pi)
        sigma = rnd.uniform(0.02, 0.08)
        deriva = rnd.uniform(-0.0004, 0.0004)
        if cod in esporadicos:
            p = rnd.uniform(0.21, 0.34)
            fechas = [d for d in todos_los_dias if rnd.random() < p]
            if cod == cortado:
                fechas = [d for d in fechas if d <= dt.date(2025, 4, 30)]
        else:
            fechas = [d for d in todos_los_dias if rnd.random() > 0.004]
            for d in (VENTANA_FIN, VENTANA_FIN - dt.timedelta(days=1)):
                if d not in fechas:
                    fechas.append(d)          # garantiza lecturas al final de la ventana
            fechas.sort()
        filas = []
        for n, d in enumerate(fechas):
            t = (d - VENTANA_INI).days
            npa = media + amp * math.sin(2 * math.pi * t / 365.0 + fase) + deriva * t + rnd.gauss(0, sigma)
            filas.append({"instrumento_cod": cod, "fecha": d, "npa": round(npa, 6), "fila_origen": n + 2})
        por_ins[cod] = filas

    # ---------------- fallas de calidad inyectadas ----------------
    candidatos = [(c, i) for c in codigos for i in range(len(por_ins[c])) if len(por_ins[c]) > 150]
    rnd.shuffle(candidatos)
    elegidos = candidatos[:N_DUP_EXACTOS + N_CONFLICTOS]
    for k, (cod, i) in enumerate(elegidos):
        orig = por_ins[cod][i]
        nueva_npa = orig["npa"] if k < N_DUP_EXACTOS else round(orig["npa"] + rnd.choice([-1, 1]) * rnd.uniform(0.3, 1.0), 6)
        siguiente = max(f["fila_origen"] for f in por_ins[cod]) + 1
        por_ins[cod].append({"instrumento_cod": cod, "fecha": orig["fecha"], "npa": nueva_npa, "fila_origen": siguiente})

    for cod in codigos:
        lecturas.extend(por_ins[cod])

    # ---------------- huella del lote y conteos esperados (independientes de BigQuery) ----------------
    canon = "\n".join(f"{l['instrumento_cod']},{l['fecha'].isoformat()},{l['npa']},{l['fila_origen']}" for l in lecturas)
    huella = hashlib.sha256(canon.encode("utf-8")).hexdigest()

    grupos = {}
    for l in lecturas:
        grupos.setdefault((l["instrumento_cod"], l["fecha"]), []).append(l["npa"])
    dup_exactos = sum(len(v) - 1 for v in grupos.values() if len(v) > 1 and len(set(v)) == 1)
    filas_conflicto = sum(len(v) for v in grupos.values() if len(v) > 1 and len(set(v)) > 1)
    manifiesto = {
        "archivo_origen": f"SINTETICO (semilla {semilla})",
        "archivo_origen_sha256": huella,
        "huella_de": "lecturas sintéticas canónicas: instrumento, fecha, npa, fila_origen",
        "cargado_utc": CARGADO_UTC,
        "ventana": [VENTANA_INI.isoformat(), VENTANA_FIN.isoformat()],
        "instrumentos": N_INSTRUMENTOS,
        "tramos_de_niveles": len(umbrales),
        "filas_bronze": len(lecturas),
        "duplicados_exactos": dup_exactos,
        "filas_en_conflicto": filas_conflicto,
        "filas_gold_esperadas": len(lecturas) - dup_exactos - filas_conflicto,
        "filas_por_instrumento": {c: len(por_ins[c]) for c in codigos},
        "nota": ("Datos sintéticos generados por synthetic/generar_datos.py. No provienen ni derivan de datos "
                 "de ninguna operación; códigos, coordenadas y niveles son arbitrarios."),
    }
    return instrumentos, umbrales, lecturas, niveles_en, huella, manifiesto


def escribir(salida, semilla):
    os.makedirs(salida, exist_ok=True)
    instrumentos, umbrales, lecturas, niveles_en, huella, manifiesto = generar(semilla)

    with open(os.path.join(salida, "instrumentos_sintetico.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["instrumento_cod", "dique", "tipo", "este_seudo", "norte_seudo"])
        w.writeheader(); w.writerows(instrumentos)

    with open(os.path.join(salida, "umbrales_sintetico.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["instrumento_cod", "nivel", "valor_msnm", "vigente_desde",
                                          "vigente_hasta", "estado", "fuente"])
        w.writeheader(); w.writerows(umbrales)

    with open(os.path.join(salida, "bronze_piezometria_sintetico.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["instrumento_cod", "fecha", "npa_msnm", "npc_msnm", "nac_msnm", "nam_msnm", "nca_msnm",
                    "fila_origen", "archivo_sha256", "cargado_utc"])
        for l in lecturas:
            v = niveles_en(l["instrumento_cod"], l["fecha"])
            w.writerow([l["instrumento_cod"], l["fecha"].isoformat(), l["npa"], v["NPC"], v["NAC"], v["NAM"], v["NCA"],
                        l["fila_origen"], huella, CARGADO_UTC])

    with open(os.path.join(salida, "manifiesto_control.json"), "w") as f:
        json.dump(manifiesto, f, indent=2, ensure_ascii=False)

    # Resumen clave,valor que deploy.sh carga a BigQuery (tabla b_manifiesto) para las verificaciones.
    with open(os.path.join(salida, "manifiesto_resumen.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["clave", "valor"])
        for k in ("instrumentos", "tramos_de_niveles", "filas_bronze", "duplicados_exactos",
                  "filas_en_conflicto", "filas_gold_esperadas"):
            w.writerow([k, manifiesto[k]])
        w.writerow(["huella", manifiesto["archivo_origen_sha256"]])
    return manifiesto


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--salida", default="data", help="carpeta de salida (por defecto: data)")
    ap.add_argument("--semilla", type=int, default=42, help="semilla aleatoria (por defecto: 42)")
    a = ap.parse_args()
    m = escribir(a.salida, a.semilla)
    print(f"Datos sintéticos escritos en {a.salida}/")
    for k in ("instrumentos", "tramos_de_niveles", "filas_bronze", "duplicados_exactos",
              "filas_en_conflicto", "filas_gold_esperadas"):
        print(f"  {k}: {m[k]}")
    print(f"  huella: {m['archivo_origen_sha256']}")
