"""Generación de eventos del tiempo real SIMULADO (sin dependencias de la nube).

Toma lecturas base y arma mensajes con las fechas corridas +7 días, como si fueran lecturas nuevas,
e inyecta fallas sintéticas: entregas duplicadas, instrumento inexistente, NPA nulo y NPA no numérico.
Es una simulación declarada: no hay sensores conectados.
"""
import json, random, uuid, datetime as dt

def construir_eventos(base, desplazamiento_dias=7, semilla=42, n_dup=10, n_sin_cat=5, n_nulo=5, n_no_num=5):
    """base: lista de (instrumento_cod, fecha:date, npa_msnm). Devuelve (mensajes, resumen).
    Cada mensaje es un dict sin ts_generado (se estampa al publicar)."""
    random.seed(semilla)
    ev = []
    for ins, f, npa in base:
        ev.append({"evento_id": str(uuid.uuid4()), "instrumento_cod": ins,
                   "fecha": (f + dt.timedelta(days=desplazamiento_dias)).isoformat(), "npa_msnm": float(npa)})
    idx = random.sample(range(len(ev)), n_dup)
    dups = [dict(ev[i]) for i in idx]
    sin_cat = [dict(ev[i], evento_id=str(uuid.uuid4()), instrumento_cod="INS-999") for i in random.sample(range(len(ev)), n_sin_cat)]
    nulos = [dict(ev[i], evento_id=str(uuid.uuid4()), npa_msnm=None) for i in random.sample(range(len(ev)), n_nulo)]
    no_num = [dict(ev[i], evento_id=str(uuid.uuid4()), npa_msnm="N/D") for i in random.sample(range(len(ev)), n_no_num)]
    todo = ev + dups + sin_cat + nulos + no_num
    random.shuffle(todo)
    resumen = {"base": len(ev), "duplicados_entrega": n_dup, "instrumento_inexistente": n_sin_cat,
               "npa_nulo": n_nulo, "npa_no_numerico": n_no_num, "total_mensajes": len(todo)}
    return todo, resumen
