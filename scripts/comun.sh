#!/usr/bin/env bash
# Funciones comunes. Se carga con: source scripts/comun.sh
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$RAIZ/config.env" ]]; then
  # shellcheck disable=SC1091
  set -a; source "$RAIZ/config.env"; set +a
fi
: "${PROYECTO:?Falta PROYECTO. Copie config.env.example a config.env y complételo}"
DATASET="${DATASET:-piezometria_demo}"
REGION="${REGION:-southamerica-east1}"
BUCKET="${BUCKET:-${PROYECTO}-datos}"
TEMA="${TEMA:-lecturas-piezo}"
SUSCRIPCION="${SUSCRIPCION:-lecturas-piezo-bq}"
SEMILLA="${SEMILLA:-42}"
DATOS="$RAIZ/data"
SALIDAS="$RAIZ/salidas"

paso()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok()    { printf '   OK  %s\n' "$*"; }

# Ejecuta un archivo SQL reemplazando los tokens. Uso: ejecutar_sql archivo [TOKEN=valor ...]
ejecutar_sql() {
  local archivo="$1"; shift
  local expr=(-e "s/__PROYECTO__/${PROYECTO}/g" -e "s/__DATASET__/${DATASET}/g")
  local par
  for par in "$@"; do expr+=(-e "s/${par%%=*}/${par#*=}/g"); done
  sed "${expr[@]}" "$archivo" | bq query --use_legacy_sql=false --location="$REGION" \
      --project_id="$PROYECTO" --max_rows=200 --format=pretty
}

# Ejecuta una verificación y falla si alguna fila dice FALLA.
verificar_sql() {
  local salida
  salida="$(ejecutar_sql "$@")"
  printf '%s\n' "$salida"
  if grep -q 'FALLA' <<<"$salida"; then
    echo "   >>> HAY COMPROBACIONES CON FALLA en $1" >&2
    return 1
  fi
}

llamar() {  # llamar sp_actualizar
  bq query --use_legacy_sql=false --location="$REGION" --project_id="$PROYECTO" \
      "CALL \`${PROYECTO}.${DATASET}.$1\`()"
}
