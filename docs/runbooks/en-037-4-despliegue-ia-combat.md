# Desplegar los workers de IA de Combat (EN-037.4, Management #573)

Integra el worker de entrenamiento continuo (`combat-trainer`) y el worker de
evaluación/promoción automática (`combat-evaluator`) en el nodo `app` de la
topología T2. **Ninguno de los dos es un bounded context ni un
microservicio nuevo** (ADR-023): son procesos técnicos del mismo contexto
Combat, sin puerto publicado, sin ruta en Caddy.

Antes de seguir este runbook, leer **`docs/evidence/en-037-4-ai-deployment/`**
completo — en particular `deployment-preflight.md` (incluye un hallazgo de
drift en Terraform que bloquea cualquier `plan`/`apply` hasta corregirse) y
`resource-measurements.md` (la medición SSM real de los cuatro escenarios
sigue pendiente; **no desplegar en producción sin completarla primero**).

## 0. Arquitectura en una frase

```
Combat (runtime, HTTP)        <- NUNCA depende de los workers
combat-trainer  (Node + Python/uv/PyTorch CPU) -> model.onnx -> Model Registry (Mongo)
combat-evaluator (Node + ONNX Runtime Node, SIN Python)       -> ACTIVE/REJECTED (Mongo)
                           |
                      MongoDB de Combat (nodo `data`, igual que siempre)
```

`combat-evaluator` reutiliza la imagen `runtime` de Combat sin cambios (el
harness de evaluación corre en el mismo proceso Node, nunca un subproceso
Python). `combat-trainer` usa una imagen SEPARADA (`nexus-battle-combat-trainer`,
etapa `trainer` del `Dockerfile` de Combat) que añade Python 3.13 + `uv` +
PyTorch CPU sobre la misma base Node.

## 1. Condiciones previas

| Condición | Comprobación |
| --- | --- |
| PR #93 de Combat (EN-037.3) mergeado en `develop` | `git log --oneline -1 origin/develop` en Combat debe mostrar `(#93)` o un commit posterior |
| PR complementario de Combat (`feat/en-037-4-ai-worker-container`) revisado y en `main` | La imagen `nexus-battle-combat-trainer` solo se publica desde `main` |
| Drift de `terraform.tfvars` corregido | Ver `docs/evidence/en-037-4-ai-deployment/deployment-preflight.md` |
| Medición SSM de los 4 escenarios completada | Ver `docs/evidence/en-037-4-ai-deployment/resource-measurements.md` |
| Imágenes publicadas y con arquitectura `arm64` | Ver paso 2 |

## 2. Verificar que las imágenes existen con la arquitectura correcta

```bash
docker buildx imagetools inspect ghcr.io/nexus-battle-vi/nexus-battle-combat:sha-<corto>
docker buildx imagetools inspect ghcr.io/nexus-battle-vi/nexus-battle-combat-trainer:sha-<corto>
```

**Comprobación:** ambos manifests deben listar `linux/arm64` (y `linux/amd64`).
**Control:** un tag inexistente debe fallar con `unauthorized`/`not found`,
nunca devolver un manifest — si lo hiciera, el comando no estaría
comprobando nada.

## 3. Generar `COMBAT_SOURCE_COMMIT` y `COMBAT_IMAGE_TAG`

El `.env` que Terraform genera en el nodo `app` (ver comentario en
`compose/nodes/app.yml`) debe incluir AMBAS variables, describiendo el
MISMO commit/imagen (revisión de código, #573 — antes solo existía
`COMBAT_SOURCE_COMMIT` mientras las cuatro imágenes de Combat seguían en
`:latest`, permitiendo que una se actualizara sin la otra):

```
COMBAT_SOURCE_COMMIT=<el SHA completo correspondiente al tag sha-<corto> publicado>
COMBAT_IMAGE_TAG=sha-<los primeros 12 caracteres del mismo SHA>
```

**Nunca** `unknown`/`latest`/`development` para `COMBAT_SOURCE_COMMIT`: la
imagen de los workers no contiene `.git` (`.dockerignore`), así que sin
este valor explícito el proceso falla al arrancar con un error claro
(`required variable COMBAT_SOURCE_COMMIT is missing a value`) en vez de
registrar un `sourceCommit` falso.

**Nunca** `latest` para `COMBAT_IMAGE_TAG` en producción: las cuatro
imágenes de Combat (`combat`, `combat-migrate`, `combat-trainer`,
`combat-evaluator`) se fijan con esta MISMA variable — si difiere del
commit real, el `sourceCommit` que los workers registran podría no
corresponder al binario que realmente está corriendo.

## 4. Sustituir la composición en el nodo `app` (mismo patrón que Sprint 3)

**No se ejecuta `terraform apply`.** Mismo criterio que
`desplegar-contextos-sprint-3.md`: se sustituye `/opt/nexus/compose.yml`
en el nodo por el `compose/nodes/app.yml` de este repositorio, a un SHA
fijo y comprobado con SHA-256, y se levanta solo lo nuevo.

```bash
sha256sum compose/nodes/app.yml
# Comparar con el SHA-256 ya presente en el nodo antes de sustituir.

nuevo=$(base64 -w0 compose/nodes/app.yml)
aws ssm send-command --profile nexus-battles --instance-ids <id-del-nodo-app> \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"set -eu\", \"cp /opt/nexus/compose.yml /opt/nexus/compose.yml.bak-$(date +%s)\", \"echo $nuevo | base64 -d > /opt/nexus/compose.yml\", \"sha256sum /opt/nexus/compose.yml\"]"
```

**Comprobación:** el `sha256sum` devuelto coincide con el calculado
localmente. **Copia de seguridad:** el `.bak-<timestamp>` queda en el nodo
para el rollback del paso 9.

## 5. Aplicar migraciones (si no corrieron ya desde el merge de PR #91/#92/#93)

```bash
aws ssm send-command --profile nexus-battles --instance-ids <id-del-nodo-app> \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["cd /opt/nexus","docker compose run --rm combat-migrate"]'
```

**Comprobación:** la salida termina en `migrations_up_to_date` con
`applied` ≥ 31 (27-31 son las migraciones de IA; ver
`docs/en-037-model-registry.md`/`docs/en-037-continuous-training-worker.md`/
`docs/en-037-automatic-model-promotion.md` de Combat para el detalle de
cada una).

## 6. Arrancar `combat-trainer` SOLO (nunca junto con `combat-evaluator` la primera vez)

```bash
aws ssm send-command --profile nexus-battles --instance-ids <id-del-nodo-app> \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["cd /opt/nexus","docker compose up -d combat-trainer"]'
```

**Comprobación:**

```bash
docker logs --tail 50 $(docker ps -qf name=combat-trainer)
# Esperar "continuous_training_worker_started"
```

**Medir (Escenario B de `resource-measurements.md`):**

```bash
free -m; docker stats --no-stream; docker ps
```

Repetir cada pocos minutos durante al menos una iteración completa de
entrenamiento real (o forzar una con `docker compose exec combat-trainer
node dist/infrastructure/training/continuous-training-worker.js --once`).
**Si aparece `OOMKilled` en `docker ps -a` o Combat deja de responder
`/api/health/ready`, detener `combat-trainer` de inmediato (paso 8) y
documentar el bloqueo — no continuar al paso 7.**

## 7. Arrancar `combat-evaluator` SOLO (con `combat-trainer` ya detenido o ya medido)

```bash
aws ssm send-command --profile nexus-battles --instance-ids <id-del-nodo-app> \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["cd /opt/nexus","docker compose up -d combat-evaluator"]'
```

Mismo patrón de comprobación y medición que el paso 6 (Escenario C). Forzar
una evaluación real exige una `CANDIDATE` real en el Model Registry — si no
existe ninguna todavía, este paso solo mide el reposo/sondeo (ver
`resource-measurements.md` para la cifra de referencia local).

## 8. Carga simultánea (solo si 6 y 7 fueron limpios) — Escenario D

```bash
docker compose up -d combat-trainer combat-evaluator
```

Mismo patrón de medición. Si el nodo muestra señales de insuficiencia
(swap sostenido, Combat degradado, OOM), **detener ambos** y documentar
la limitación concreta — el prompt maestro de #573 permite declarar
capacidad insuficiente con evidencia; no permite forzarlo.

## 9. Parada / rollback

```bash
# Detener solo los workers de IA, Combat sigue disponible:
docker compose stop combat-trainer combat-evaluator

# Revertir la composición completa a la version anterior (NUNCA -v):
cp /opt/nexus/compose.yml.bak-<timestamp> /opt/nexus/compose.yml
docker compose up -d
```

**Nunca** `docker compose down -v`: destruiría los volúmenes de datos.
El trabajo pendiente del trainer/evaluator (leases, cursores,
`CANDIDATE`/`EVALUATING` en Mongo) sobrevive la parada — al reiniciar el
worker, la recuperación es automática (EN-037.2/EN-037.3, ya probada a
nivel de código). Nunca borrar manualmente documentos de
`ai-training-coordinator`/`ai-model-evaluations` "para reiniciar desde
cero".

## 10. Observabilidad

Los workers no exponen HTTP ni health endpoint propio — no crear uno.
Verificar salud por:

- Eventos estructurados en `docker logs`: `continuous_training_worker_started`,
  `continuous_training_candidate_registered`, `automatic_evaluation_worker_started`,
  `ai_promotion_policy_evaluated`, `ai_model_promoted`, `ai_candidate_rejected`,
  `ai_active_model_loaded`, `ai_active_model_unavailable`, `ai_neural_fallback_used`
  (nombres reales del código de Combat, confirmados en
  `src/infrastructure/training/`, `src/infrastructure/evaluation/`,
  `src/infrastructure/ai/ActiveModelProvider.ts`).
- Estado en MongoDB: colecciones `ai-training-coordinator`,
  `ai-model-evaluations`, `ai-model-versions` (consultar vía `mongosh`,
  nunca inventar un dashboard nuevo para esta Task).
- `docker ps`/`docker stats` para CPU/memoria/PIDs/restarts.

Un worker sin trabajo pendiente (`IDLE`) NO es un servicio caído. Un
rechazo de candidata por gates (`ai_candidate_rejected`) NO es un fallo de
infraestructura.

## 11. Seguridad

- Ambos workers corren como usuario `node` (no root) — confirmado en
  `docs/evidence/en-037-4-ai-deployment/container-build-results.md`.
- Mismas credenciales Mongo que `combat`/`combat-migrate` (usuario `combat`,
  sin acceso a otras bases) — nunca el usuario root de Mongo.
- Sin puertos publicados, sin IAM nuevo, sin credenciales AWS en los
  contenedores.

## 12. Limitaciones conocidas / dependencias para EN-037.5 #574

- La medición SSM real de los 4 escenarios queda pendiente en este PR (sin
  acceso AWS desde el entorno que lo preparó) — es una condición de
  finalización explícita de #573, no delegable a #574.
- La verificación en hardware Graviton real (frente a QEMU) no se hizo —
  recomendado como parte del primer despliegue controlado de este runbook.
- El ciclo E2E completo (batalla real → dataset → entrenamiento →
  candidata → evaluación → promoción/rechazo → `ActiveModelProvider`
  recarga el modelo en Combat sin reiniciar) es el alcance exacto de
  **EN-037.5 #574** — este runbook deja los workers operables, no repite
  esa validación.
