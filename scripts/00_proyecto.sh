#!/usr/bin/env bash
# OPCIONAL. Crea un proyecto nuevo, lo vincula a la facturación, habilita las APIs y crea un presupuesto.
# Es repetible: si el proyecto, el vínculo o el presupuesto ya existen, no los vuelve a crear.
# Uso: scripts/00_proyecto.sh <ID_PROYECTO> <ID_CUENTA_FACTURACION> [PRESUPUESTO_MENSUAL, p. ej. 50PEN]
# La moneda del presupuesto debe coincidir con la de la cuenta de facturación.
# Un presupuesto AVISA, no corta el gasto.
# Si el vínculo falla con "Cloud billing quota exceeded", la cuenta alcanzó su tope de proyectos con
# facturación: desvincule uno que no use (gcloud billing projects unlink <ID>) y repita este script.
set -euo pipefail
P="${1:?ID del proyecto}"; CUENTA="${2:?ID de la cuenta de facturación (formato XXXXXX-XXXXXX-XXXXXX)}"; PRES="${3:-50PEN}"
NOMBRE_PRES="Demo piezometria ($P)"

if gcloud projects describe "$P" >/dev/null 2>&1; then
  echo "El proyecto $P ya existe; se continúa."
else
  gcloud projects create "$P" --name="Piezometria Demo"
fi
gcloud billing projects link "$P" --billing-account="$CUENTA"
gcloud config set project "$P"
gcloud services enable bigquery.googleapis.com storage.googleapis.com pubsub.googleapis.com \
    billingbudgets.googleapis.com --project="$P"
if gcloud billing budgets list --billing-account="$CUENTA" --format='value(displayName)' | grep -qxF "$NOMBRE_PRES"; then
  echo "El presupuesto '$NOMBRE_PRES' ya existe."
else
  gcloud billing budgets create --billing-account="$CUENTA" --display-name="$NOMBRE_PRES" \
      --budget-amount="$PRES" --filter-projects="projects/$P" \
      --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0
fi
echo "Proyecto $P listo. Copie config.env.example a config.env y ponga PROYECTO=$P"
