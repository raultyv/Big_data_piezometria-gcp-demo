# Monitoreo piezométrico de un depósito de relaves en Google Cloud: demo end-to-end

Demo reproducible de un pipeline de datos para lecturas piezométricas: ingesta por lotes y en tiempo real (simulado), capas bronze/silver/gold, esquema en estrella, vista híbrida, capa de exposición (vistas y consulta por la API REST de BigQuery) y verificaciones automáticas. Proyecto final del curso de Big Data (Maestría en Ciencia de Datos e IA, UTEC), entregas 1 a 3.

> **Datos sintéticos.** Este repositorio no contiene datos de ninguna operación. El script `synthetic/generar_datos.py` inventa instrumentos, coordenadas, niveles y lecturas con la misma estructura que el lote usado en el informe. Las cifras del informe de la entrega 2 (35,632 lecturas, 80 instrumentos, 353 tramos) se midieron con un lote **seudonimizado** de otra procedencia; este demo produce cifras distintas con las mismas reglas.
>
> **Alcance.** Es un ejercicio de ingeniería de datos. No evalúa la estabilidad ni la seguridad de ninguna presa y no sustituye el sistema de monitoreo de seguridad, el criterio del ingeniero de registro ni la revisión independiente. Los niveles (NPC, NAC, NAM, NCA) del generador son arbitrarios y están marcados como `provisional`.

> **Declaración de uso de IA generativa.** Este repositorio se desarrolló con apoyo de IA generativa para escribir el código, los scripts y la documentación. El autor definió el alcance, ejecutó el demo en Google Cloud, revisó los resultados y validó las verificaciones.

## Contenido

1. [Arquitectura](#arquitectura)
2. [Estructura del repositorio](#estructura-del-repositorio)
3. [Requisitos](#requisitos)
4. [Inicio rápido](#inicio-rápido)
5. [Qué hace cada etapa](#qué-hace-cada-etapa)
6. [Reglas de calidad](#reglas-de-calidad)
7. [Modelo en estrella](#modelo-en-estrella)
8. [Verificaciones y pruebas](#verificaciones-y-pruebas)
9. [Costos y limpieza](#costos-y-limpieza)
10. [Limitaciones](#limitaciones)
11. [Estado de validación](#estado-de-validación)

## Arquitectura

```mermaid
flowchart LR
  subgraph L["Camino por lotes"]
    A[CSV sintéticos<br/>+ manifiesto] --> B[(Cloud Storage<br/>privado, versionado)]
    B --> C[Bronze<br/>b_lecturas, b_instrumentos,<br/>b_umbrales, b_manifiesto]
    C --> D[Silver s_lecturas<br/>marcas, sin corregir]
    D --> E[Gold g_lecturas]
    E --> F[Estrella<br/>fact_lectura + 3 dim.]
  end
  subgraph S["Camino en tiempo real (simulado)"]
    P[Publicador<br/>Colab o terminal] --> T[Pub/Sub<br/>lecturas-piezo]
    T --> R[Bronze b_eventos_raw<br/>suscripción a BigQuery]
    R --> SE[Silver s_eventos]
    SE --> GE[Gold g_eventos]
  end
  E --> H{{Vista v_lectura_hibrida}}
  GE --> H
  H --> X[Capa de exposición<br/>vistas api_*]
  X --> API[API REST de BigQuery<br/>./consultar.sh]
  X -.-> TAB[Tableros u otros consumidores<br/>no probado]
```

Decisiones principales: SQL en BigQuery como motor (el volumen no justifica Spark ni Flink); marcar sin corregir, para que cada depuración sea auditable; suscripción de Pub/Sub directa a BigQuery, sin suscriptor propio; vista híbrida con marca de agua para no contar dos veces una misma fecha; capa de exposición con vistas de solo lectura (`api_*`) como punto único de consumo; procedimientos que registran cada ejecución en la tabla `ejecuciones`.

## Estructura del repositorio

```
.
├── deploy.sh                 # lote | flujo | todo
├── destroy.sh                # elimina todo y lista lo que queda
├── verificar.sh              # repite las verificaciones sin volver a desplegar
├── consultar.sh              # consulta la capa de exposición por la API REST (JSON)
├── config.env.example        # copiar a config.env y poner PROYECTO
├── scripts/
│   ├── comun.sh              # funciones compartidas (tokens, verificaciones)
│   └── 00_proyecto.sh        # opcional: proyecto, facturación, APIs y presupuesto
├── synthetic/generar_datos.py   # datos sintéticos + manifiesto con conteos esperados
├── sql/                      # 00 auditoría · 10 silver/gold · 11 exclusiones · 20 estrella
│                             # 30 consultas · 50 eventos · 60 vista híbrida · 70 latencia · 80 exposición
├── exposicion/consultar_api.py  # cliente mínimo de la API REST de BigQuery (solo biblioteca estándar)
├── publicador/               # eventos.py (generación) · publicar_eventos.py (terminal)
├── notebooks/B4_publicador_eventos.ipynb   # el mismo publicador para Colab
├── verificaciones/           # 6 archivos SQL: cada fila dice OK o FALLA
└── tests/test_local_duckdb.py   # prueba local de la lógica SQL, sin nube
```

Los archivos SQL usan los tokens `__PROYECTO__` y `__DATASET__`; `deploy.sh` los reemplaza al ejecutar.

## Requisitos

- Un proyecto de Google Cloud con facturación activa (puede crearse con `scripts/00_proyecto.sh`).
- Google Cloud Shell (trae `gcloud`, `bq`, `git` y `python3`) o cualquier terminal con esas herramientas y sesión iniciada.
- Permisos de propietario o equivalente sobre el proyecto (crea bucket, dataset, tema, suscripción y asigna roles).

## Inicio rápido

En Cloud Shell, un comando a la vez:

```bash
git clone https://github.com/raultyv/Big_data_piezometria-gcp-demo && cd Big_data_piezometria-gcp-demo
cp config.env.example config.env && nano config.env     # poner PROYECTO=<su-proyecto>
./deploy.sh lote      # bucket, dataset, bronze, silver, gold, estrella y verificaciones
./deploy.sh flujo     # Pub/Sub, publicador simulado, eventos, vista híbrida, capa de exposición y verificaciones
./consultar.sh resumen_dique   # consulta de los datos procesados por la API REST (JSON)
./destroy.sh          # al terminar: borra los recursos y muestra lo que queda
```

`./deploy.sh todo` ejecuta lote y flujo seguidos. Cada etapa termina con tablas de comprobaciones (`OK` o `FALLA`); si alguna falla, el script se detiene con error.

Para crear también el proyecto y un presupuesto con alertas (opcional):

```bash
scripts/00_proyecto.sh <ID_PROYECTO> <ID_CUENTA_FACTURACION> 50PEN
```

## Qué hace cada etapa

| Etapa | Qué crea | Qué comprueba |
|---|---|---|
| Datos sintéticos | 3 CSV, manifiesto y resumen con conteos esperados (calculados aparte del SQL) | Salida determinista con la misma semilla |
| Bronze | Bucket privado y versionado; `b_lecturas`, `b_instrumentos`, `b_umbrales`, `b_manifiesto` con tipos explícitos | Filas, instrumentos, tramos y huella frente al manifiesto; sin fechas futuras |
| Silver y gold | `sp_actualizar()` → `s_lecturas`, `g_lecturas`; vista `v_exclusiones`; registro en `ejecuciones` | Duplicados y conflictos marcados; silver = gold + exclusiones; sin repetidos en gold |
| Estrella | `sp_modelar()` → `dim_instrumento`, `dim_fecha`, `dim_umbral`, `fact_lectura` (particionada por mes, agrupada por instrumento) | Conteos, sin huérfanos, cuatro niveles vigentes en cada hecho |
| Pub/Sub | Tema, tabla `b_eventos_raw`, suscripción a BigQuery con metadatos y roles para la identidad de Pub/Sub | Enviados = recibidos |
| Eventos | `sp_procesar_eventos()` → `s_eventos`, `g_eventos`; `v_lectura_hibrida` | Cada falla inyectada marcada; vista = gold del lote + gold del flujo |
| Exposición | Vistas `api_ultima_lectura`, `api_resumen_dique` y `api_serie_instrumento`, que leen `v_lectura_hibrida` | Mismos instrumentos y totales que la vista híbrida; sin instrumentos repetidos en la última lectura |
| Latencia | Consulta informativa sobre los eventos únicos | Mediana, p95 y máximo hasta publicar |

## Capa de exposición

Los consumidores no leen bronze, silver ni gold: leen tres vistas de solo lectura sobre `v_lectura_hibrida`.

| Recurso (`./consultar.sh …`) | Vista | Devuelve |
|---|---|---|
| `ultima_lectura [--limite N]` | `api_ultima_lectura` | Última lectura de cada instrumento, con su margen al NAM (ordenada por margen) |
| `resumen_dique` | `api_resumen_dique` | Instrumentos, lecturas, última fecha y lecturas en o sobre el NAM por dique |
| `serie --instrumento COD [--limite N]` | `api_serie_instrumento` | Lecturas recientes de un instrumento (el código viaja como parámetro de la consulta) |

`consultar.sh` llama a la API REST de BigQuery (`POST https://bigquery.googleapis.com/bigquery/v2/projects/<proyecto>/queries`) con el token de la sesión de `gcloud` y devuelve JSON. No es un servicio propio: es la API de BigQuery con un cliente mínimo. Un tablero (por ejemplo Looker Studio) podría conectarse a las mismas vistas; **no se probó**. Las columnas `en_o_sobre_nam` comparan con niveles provisionales del generador y no evalúan la seguridad de ninguna presa.

## Reglas de calidad

Silver agrega una marca por regla y **no modifica el dato**. Solo gold excluye.

| Marca | Regla | ¿Sale de gold? |
|---|---|---|
| `es_duplicado_exacto` | Mismo instrumento y fecha, mismo NPA, segunda copia o posterior | Sí |
| `es_fecha_conflicto` | Mismo instrumento y fecha con NPA distinto (se marcan ambas filas) | Sí |
| `es_npa_nulo` | NPA vacío | Sí |
| `fuera_escalera` | No se cumple NPC > NAC > NAM en la fila | No: se conserva y se informa |
| `sin_catalogo` | Instrumento ausente del catálogo | Informativa |
| `sin_nivel_vigente` | Sin tramo de NPC vigente en la fecha | Informativa (el cruce de gold exige los cuatro niveles) |

Los niveles se guardan con vigencia y estado en `b_umbrales`; cambiar un criterio no exige tocar el código. Este demo solo **compara** la lectura con los niveles y calcula márgenes: no los define ni interpreta su significado para la seguridad.

Para el flujo: entregas duplicadas (mismo `evento_id`), instrumento inexistente, NPA nulo y NPA no numérico se marcan en `s_eventos`; `g_eventos` conserva un evento válido por instrumento y fecha.

## Modelo en estrella

`fact_lectura` (una fila por lectura válida, con márgenes a cada nivel, indicadores `sobre_*` y claves a las dimensiones) · `dim_instrumento` · `dim_fecha` · `dim_umbral` (tramos con vigencia, estado y fuente). Cada hecho conserva `fila_origen` y `archivo_sha256`, de modo que se puede rastrear hasta el archivo del lote.

## Verificaciones y pruebas

- **En la nube:** los 6 archivos de `verificaciones/` se ejecutan dentro de `deploy.sh`. Comparan BigQuery con el manifiesto que generó el script de datos. Para repetirlas sin volver a desplegar: `./verificar.sh todo` (o `./verificar.sh bronze silver_gold modelo`).
- **Local, sin nube:** `python3 tests/test_local_duckdb.py` traduce el SQL de BigQuery a DuckDB (con `sqlglot`) y ejecuta toda la lógica, incluido el flujo simulado. Requiere `pip install duckdb sqlglot`. No prueba particionado, clustering, procedimientos, Pub/Sub ni IAM.

## Costos y limpieza

- La estimación de costos de la arquitectura propuesta está en el documento de la entrega 3 (Calculadora de precios de Google Cloud, con fecha y supuestos). 
- Un presupuesto de Google Cloud **avisa, no corta el gasto**. Revise el reporte de facturación después de cada etapa.
- `./destroy.sh` elimina suscripción, tema, dataset y bucket (con todas sus versiones) y lista lo que queda. Con `--proyecto` borra además el proyecto.

## Limitaciones

- El tiempo real es una **simulación declarada**: no hay sensores; las lecturas base se reenvían con fechas +7 días y se inyectan fallas sintéticas.
- La latencia se mide en una sola corrida y con pocos mensajes; mezcla agrupamiento del cliente, red y posible desfase de reloj. No es una prueba de carga.
- Los roles de la suscripción de Pub/Sub se asignan a nivel de proyecto (aceptable en un proyecto de pruebas; en producción se limitarían al dataset).
- Sin orquestación ni alertas: los procedimientos se ejecutan desde el script. Trabajo futuro: consultas programadas, cola de mensajes fallidos y fuentes adicionales (caudales, topografía, informes PDF).
- Una sola fuente de lotes; no se probaron Spark ni Flink.

## Estado de validación

| Qué | Estado |
|---|---|
| Lógica SQL sobre datos sintéticos (DuckDB, 42 comprobaciones, incluida la capa de exposición) | Probada localmente |
| Capa de exposición y `consultar.sh` en Google Cloud (20-nov-2026) | **Validados**: las 5 comprobaciones de `verificaciones/06` en OK y las tres consultas (`resumen_dique`, `ultima_lectura`, `serie`) devolvieron JSON en 1.0 a 1.2 s (una sola medición cada una) |
| `deploy.sh lote` y `deploy.sh flujo` en Google Cloud (proyecto nuevo, 19-nov-2026) | **Validados**: todas las verificaciones en OK |
| `destroy.sh` (19-nov-2026) | **Validado**: suscripción, tema, dataset y bucket eliminados; las listas finales quedaron vacías |
| `scripts/00_proyecto.sh` (proyecto, facturación, presupuesto) | **Validado** tras una corrección (ver abajo) |

### Registro de la capa de exposición (20-nov-2026)

Segunda corrida real, en el mismo proyecto de pruebas, con `time ./deploy.sh todo`: terminó en 3 min 7 s sin ninguna comprobación en FALLA (el script se detiene si alguna falla). Las comprobaciones de flujo, vista híbrida y exposición salieron en OK, con los mismos conteos que el 19-nov (508 enviados y 508 recibidos, 483 en gold del flujo, vista de 36,070 filas, 80 instrumentos en `api_ultima_lectura`). La latencia hasta publicar fue distinta: mediana de 538 ms y p95 de 661 ms (498 mensajes únicos), contra 175 y 219 ms del 19-nov. Es la variación que se espera de una medición única desde Cloud Shell, y confirma que esas cifras son una referencia, no una garantía.

### Registro de la validación (19-nov-2026)

Una corrida real, con datos sintéticos (semilla 42), en un proyecto nuevo de Google Cloud en `southamerica-east1`:

- Lote: 35,617 lecturas de bronze; 26 duplicados exactos y 4 filas en conflicto marcados; 35,587 en gold; modelo en estrella con 35,587 hechos, 80 instrumentos, 484 tramos y 517 días.
- Flujo (simulado): 508 mensajes enviados y 508 recibidos; las 25 fallas inyectadas quedaron marcadas; 483 en gold del flujo; vista híbrida de 36,070 filas.
- Latencia medida, una sola corrida desde Cloud Shell: mediana de 175 ms y p95 de 219 ms hasta publicar; todo consultable a los 4.8 s del primer envío. Es una referencia, no una prueba de carga.

Problemas que aparecieron en la primera corrida real y que se corrigieron:

1. `scripts/00_proyecto.sh` falló al vincular la facturación porque la cuenta alcanzó su cuota de proyectos con facturación, y no se podía repetir porque el proyecto ya existía. Ahora es repetible y avisa de la cuota.
2. `deploy.sh lote` creaba la vista `v_exclusiones` antes de `sp_actualizar()`, y la vista lee `s_lecturas`, que aún no existía. Además el error quedaba oculto. Se corrigió el orden y se agregó `ddl()`, que muestra el error completo.

La prueba local no detectó el segundo problema porque ejecutaba los pasos en el orden correcto: la prueba local y la corrida real se complementan.
