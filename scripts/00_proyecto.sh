#!/usr/bin/env bash
# OPCIONAL. Crea un proyecto nuevo, lo vincula a la facturación, habilita las APIs y crea un presupuesto.
# Uso: scripts/00_proyecto.sh <ID_PROYECTO> <ID_CUENTA_FACTURACION> [PRESUPUESTO_MENSUAL, p. ej. 50PEN]
# La moneda del presupuesto debe coincidir con la de la cuenta de facturación.
# Un presupuesto AVISA, no corta el gasto.
set -euo pipefail
P="${1:?ID del proyecto}"; CUENTA="${2:?ID de la cuenta de facturación (formato XXXXXX-XXXXXX-XXXXXX)}"; PRES="${3:-50PEN}"

gcloud projects create "$P" --name="Piezometria Demo"
gcloud billing projects link "$P" --billing-account="$CUENTA"
gcloud config set project "$P"
gcloud services enable bigquery.googleapis.com storage.googleapis.com pubsub.googleapis.com \
    billingbudgets.googleapis.com --project="$P"
gcloud billing budgets create --billing-account="$CUENTA" --display-name="Demo piezometria ($P)" \
    --budget-amount="$PRES" --filter-projects="projects/$P" \
    --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0
echo "Proyecto $P listo. Copie config.env.example a config.env y ponga PROYECTO=$P"
