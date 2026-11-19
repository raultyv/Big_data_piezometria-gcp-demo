#!/usr/bin/env bash
# Ejecuta las verificaciones contra BigQuery sin volver a desplegar nada.
#   ./verificar.sh bronze silver_gold modelo     (cualquier combinación, en ese orden)
#   ./verificar.sh todo                          (las cinco; las de eventos requieren que ./deploy.sh flujo ya corrió)
# Nombres: bronze | silver_gold | modelo | eventos | hibrida
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/comun.sh"
[[ $# -ge 1 ]] || { echo "Uso: ./verificar.sh {bronze|silver_gold|modelo|eventos|hibrida|todo} ..."; exit 1; }
[[ "$1" == "todo" ]] && set -- bronze silver_gold modelo eventos hibrida

tokens_eventos() {
  local J="$SALIDAS/resumen_eventos.json"
  [[ -f "$J" ]] || { echo "Falta $J: ejecute primero ./deploy.sh flujo" >&2; exit 1; }
  local par
  for par in ENVIADOS:enviados DUP:duplicados_entrega SINCAT:instrumento_inexistente NULOS:npa_nulo \
             NONUM:npa_no_numerico GOLD_EV:gold_eventos_esperado; do
    printf '__%s__=%s\n' "${par%%:*}" "$(python3 -c "import json;print(json.load(open('$J'))['${par#*:}'])")"
  done
}

for nombre in "$@"; do
  archivo="$(ls "$RAIZ"/verificaciones/0*_verificar_"${nombre}".sql 2>/dev/null | head -1)"
  [[ -n "$archivo" ]] || { echo "No existe la verificación '$nombre'"; exit 1; }
  paso "Verificación: $nombre"
  if [[ "$nombre" == "eventos" ]]; then
    mapfile -t T < <(tokens_eventos)
    verificar_sql "$archivo" "${T[@]}"
  else
    verificar_sql "$archivo"
  fi
done
