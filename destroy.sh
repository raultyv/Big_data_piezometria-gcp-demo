#!/usr/bin/env bash
# Elimina los recursos del demo para que no queden costos. Pide confirmación.
#   ./destroy.sh               borra suscripción, tema, dataset y bucket (con todas sus versiones)
#   ./destroy.sh --proyecto    además, borra el proyecto completo (irreversible tras 30 días)
#   ./destroy.sh --si          no pregunta
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/comun.sh"
BORRAR_PROYECTO=0; SI=0
for a in "$@"; do case "$a" in --proyecto) BORRAR_PROYECTO=1;; --si) SI=1;; esac; done

echo "Se eliminarán en el proyecto $PROYECTO: suscripción $SUSCRIPCION, tema $TEMA, dataset $DATASET y bucket gs://$BUCKET."
[[ $BORRAR_PROYECTO -eq 1 ]] && echo "ADEMÁS se eliminará el proyecto $PROYECTO."
if [[ $SI -ne 1 ]]; then read -r -p "Escriba el ID del proyecto para confirmar: " R; [[ "$R" == "$PROYECTO" ]] || { echo "Cancelado."; exit 1; }; fi

paso "Pub/Sub"
gcloud pubsub subscriptions delete "$SUSCRIPCION" --project="$PROYECTO" --quiet 2>/dev/null || echo "   (no existía la suscripción)"
gcloud pubsub topics delete "$TEMA" --project="$PROYECTO" --quiet 2>/dev/null || echo "   (no existía el tema)"
paso "BigQuery"
bq --project_id="$PROYECTO" rm -r -f -d "${PROYECTO}:${DATASET}" 2>/dev/null || echo "   (no existía el dataset)"
paso "Cloud Storage"
gcloud storage rm --recursive --all-versions "gs://$BUCKET" --project="$PROYECTO" 2>/dev/null || echo "   (no existía el bucket)"

if [[ $BORRAR_PROYECTO -eq 1 ]]; then
  paso "Proyecto"; gcloud projects delete "$PROYECTO" --quiet
fi

paso "Lo que queda en el proyecto (debe estar vacío)"
echo "-- datasets:";  bq --project_id="$PROYECTO" ls 2>&1 || true
echo "-- buckets:";   gcloud storage buckets list --project="$PROYECTO" --format='value(name)' 2>&1 || true
echo "-- temas:";     gcloud pubsub topics list --project="$PROYECTO" --format='value(name)' 2>&1 || true
