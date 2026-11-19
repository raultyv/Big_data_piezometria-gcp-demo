#!/usr/bin/env bash
# Despliegue del demo end-to-end en Google Cloud (Cloud Shell o cualquier terminal con gcloud y bq).
#
#   ./deploy.sh lote     bucket + dataset + carga de bronze + silver + gold + modelo en estrella + verificaciones
#   ./deploy.sh flujo    Pub/Sub -> BigQuery + publicador simulado + silver/gold de eventos + vista híbrida + verificaciones
#   ./deploy.sh todo     lote y flujo
#
# Es idempotente en lo que se puede: repetirlo recrea tablas y vistas desde bronze. El flujo se publica UNA vez
# (la tabla cruda se conserva); para repetir, ejecute ./destroy.sh y vuelva a empezar.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/comun.sh"

verificar_entorno() {
  paso "Entorno"
  command -v gcloud >/dev/null || { echo "Falta gcloud"; exit 1; }
  command -v bq >/dev/null     || { echo "Falta bq"; exit 1; }
  command -v python3 >/dev/null || { echo "Falta python3"; exit 1; }
  gcloud config set project "$PROYECTO" >/dev/null 2>&1
  gcloud services enable bigquery.googleapis.com storage.googleapis.com pubsub.googleapis.com --project="$PROYECTO"
  ok "proyecto $PROYECTO · región $REGION · dataset $DATASET · bucket gs://$BUCKET"
}

lote() {
  paso "Datos sintéticos (semilla $SEMILLA)"
  python3 "$RAIZ/synthetic/generar_datos.py" --salida "$DATOS" --semilla "$SEMILLA"

  paso "Bucket privado con versionado (data lake)"
  if ! gcloud storage buckets describe "gs://$BUCKET" --project="$PROYECTO" >/dev/null 2>&1; then
    gcloud storage buckets create "gs://$BUCKET" --project="$PROYECTO" --location="$REGION" \
        --uniform-bucket-level-access --public-access-prevention
  fi
  gcloud storage buckets update "gs://$BUCKET" --versioning >/dev/null
  gcloud storage cp "$DATOS"/*.csv "$DATOS"/manifiesto_control.json "gs://$BUCKET/entrada/lote_001/"
  ok "lote cargado en gs://$BUCKET/entrada/lote_001/"

  paso "Dataset en BigQuery"
  if ! bq --project_id="$PROYECTO" show --dataset "${PROYECTO}:${DATASET}" >/dev/null 2>&1; then
    bq --project_id="$PROYECTO" --location="$REGION" mk --dataset "${PROYECTO}:${DATASET}"
  fi

  paso "Bronze: carga con tipos explícitos"
  local U="gs://$BUCKET/entrada/lote_001"
  bq --location="$REGION" load --replace --source_format=CSV --skip_leading_rows=1 "${PROYECTO}:${DATASET}.b_lecturas" \
     "$U/bronze_piezometria_sintetico.csv" \
     instrumento_cod:STRING,fecha:DATE,npa_msnm:FLOAT,npc_msnm:FLOAT,nac_msnm:FLOAT,nam_msnm:FLOAT,nca_msnm:FLOAT,fila_origen:INTEGER,archivo_sha256:STRING,cargado_utc:TIMESTAMP
  bq --location="$REGION" load --replace --source_format=CSV --skip_leading_rows=1 "${PROYECTO}:${DATASET}.b_instrumentos" \
     "$U/instrumentos_sintetico.csv" instrumento_cod:STRING,dique:STRING,tipo:STRING,este_seudo:FLOAT,norte_seudo:FLOAT
  bq --location="$REGION" load --replace --source_format=CSV --skip_leading_rows=1 "${PROYECTO}:${DATASET}.b_umbrales" \
     "$U/umbrales_sintetico.csv" instrumento_cod:STRING,nivel:STRING,valor_msnm:FLOAT,vigente_desde:DATE,vigente_hasta:DATE,estado:STRING,fuente:STRING
  bq --location="$REGION" load --replace --source_format=CSV --skip_leading_rows=1 "${PROYECTO}:${DATASET}.b_manifiesto" \
     "$U/manifiesto_resumen.csv" clave:STRING,valor:STRING
  verificar_sql "$RAIZ/verificaciones/01_verificar_bronze.sql"

  paso "Silver y gold (procedimiento sp_actualizar)"
  ddl "$RAIZ/sql/00_tabla_ejecuciones.sql"
  ddl "$RAIZ/sql/10_sp_actualizar.sql"
  llamar sp_actualizar
  ddl "$RAIZ/sql/11_vista_exclusiones.sql"     # la vista lee s_lecturas: va DESPUÉS de sp_actualizar
  verificar_sql "$RAIZ/verificaciones/02_verificar_silver_gold.sql"

  paso "Modelo en estrella (procedimiento sp_modelar)"
  ddl "$RAIZ/sql/20_sp_modelar.sql"
  llamar sp_modelar
  verificar_sql "$RAIZ/verificaciones/03_verificar_modelo.sql"

  paso "Consultas analíticas A y B"
  ejecutar_sql "$RAIZ/sql/30_consultas_analiticas.sql"
}

flujo() {
  paso "Pub/Sub hacia BigQuery"
  gcloud services enable pubsub.googleapis.com --project="$PROYECTO"
  gcloud beta services identity create --service=pubsub.googleapis.com --project="$PROYECTO" >/dev/null 2>&1 || true
  local NUM SA
  NUM="$(gcloud projects describe "$PROYECTO" --format='value(projectNumber)')"
  SA="serviceAccount:service-${NUM}@gcp-sa-pubsub.iam.gserviceaccount.com"
  if ! bq --project_id="$PROYECTO" show "${PROYECTO}:${DATASET}.b_eventos_raw" >/dev/null 2>&1; then
    bq --location="$REGION" mk --table "${PROYECTO}:${DATASET}.b_eventos_raw" \
       subscription_name:STRING,message_id:STRING,publish_time:TIMESTAMP,data:STRING,attributes:STRING
  fi
  gcloud pubsub topics describe "$TEMA" --project="$PROYECTO" >/dev/null 2>&1 || \
    gcloud pubsub topics create "$TEMA" --project="$PROYECTO" --message-storage-policy-allowed-regions="$REGION"
  # Roles a nivel de proyecto: aceptable en un proyecto de pruebas; en producción, limitarlos al dataset.
  gcloud projects add-iam-policy-binding "$PROYECTO" --member="$SA" --role=roles/bigquery.dataEditor --condition=None >/dev/null
  gcloud projects add-iam-policy-binding "$PROYECTO" --member="$SA" --role=roles/bigquery.metadataViewer --condition=None >/dev/null
  if ! gcloud pubsub subscriptions describe "$SUSCRIPCION" --project="$PROYECTO" >/dev/null 2>&1; then
    # Los permisos recién asignados pueden tardar en propagarse: se reintenta hasta 4 veces.
    local intento
    for intento in 1 2 3 4; do
      gcloud pubsub subscriptions create "$SUSCRIPCION" --topic="$TEMA" \
          --bigquery-table="${PROYECTO}:${DATASET}.b_eventos_raw" --write-metadata --project="$PROYECTO" && break
      [[ $intento -eq 4 ]] && { echo "No se pudo crear la suscripción"; exit 1; }
      echo "   reintentando en 20 s (propagación de permisos)…"; sleep 20
    done
  fi
  ok "tema $TEMA y suscripción $SUSCRIPCION creados"

  paso "Publicador de eventos (simulación declarada)"
  if [[ ! -d "$RAIZ/.venv" ]]; then python3 -m venv "$RAIZ/.venv"; fi
  # shellcheck disable=SC1091
  source "$RAIZ/.venv/bin/activate"
  pip install -q google-cloud-pubsub google-cloud-bigquery
  mkdir -p "$SALIDAS"
  python3 "$RAIZ/publicador/publicar_eventos.py" --proyecto "$PROYECTO" --dataset "$DATASET" \
      --ubicacion "$REGION" --tema "$TEMA" --salida "$SALIDAS/resumen_eventos.json"
  deactivate

  paso "Silver y gold de eventos (procedimiento sp_procesar_eventos) y vista híbrida"
  ddl "$RAIZ/sql/50_sp_procesar_eventos.sql"
  llamar sp_procesar_eventos
  ddl "$RAIZ/sql/60_vista_hibrida.sql"

  local J="$SALIDAS/resumen_eventos.json" t=()
  for par in ENVIADOS:enviados DUP:duplicados_entrega SINCAT:instrumento_inexistente NULOS:npa_nulo \
             NONUM:npa_no_numerico GOLD_EV:gold_eventos_esperado; do
    t+=("__${par%%:*}__=$(python3 -c "import json,sys;print(json.load(open('$J'))['${par#*:}'])")")
  done
  verificar_sql "$RAIZ/verificaciones/04_verificar_eventos.sql" "${t[@]}"
  verificar_sql "$RAIZ/verificaciones/05_verificar_hibrida.sql"

  paso "Latencia medida (informativa)"
  ejecutar_sql "$RAIZ/sql/70_consulta_latencia.sql"
}

case "${1:-}" in
  lote)  verificar_entorno; lote ;;
  flujo) verificar_entorno; flujo ;;
  todo)  verificar_entorno; lote; flujo ;;
  *) echo "Uso: ./deploy.sh {lote|flujo|todo}"; exit 1 ;;
esac
paso "Terminado. Para eliminar todo: ./destroy.sh"
