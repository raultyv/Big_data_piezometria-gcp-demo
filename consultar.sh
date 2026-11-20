#!/usr/bin/env bash
# Consulta la capa de exposición por la API REST de BigQuery (devuelve JSON).
#   ./consultar.sh ultima_lectura [--limite 5]
#   ./consultar.sh resumen_dique
#   ./consultar.sh serie --instrumento <codigo> [--limite 5]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/comun.sh"
[[ $# -ge 1 ]] || { echo "Uso: ./consultar.sh {ultima_lectura|resumen_dique|serie} [opciones]"; exit 1; }
python3 "$RAIZ/exposicion/consultar_api.py" "$1" --proyecto "$PROYECTO" --dataset "$DATASET" \
    --ubicacion "$REGION" "${@:2}"
