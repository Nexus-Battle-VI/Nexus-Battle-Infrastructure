# EN-037.4 (Management #573) — Medición de recursos

## Lectura obligatoria antes de usar este documento

El prompt maestro de #573 exige medir CUATRO escenarios (baseline,
entrenamiento, evaluación, carga simultánea) **en el nodo `app` real
(`t4g.medium`, AWS)**, con el mismo método SSM que usó ADR-022. **Ese acceso
no estuvo disponible en este entorno** (sin credenciales/MCP de AWS — el
servidor `aws-mcp` configurado para esta sesión no conectó). Por tanto:

> **La medición SSM en el nodo `app` real queda marcada `NO EJECUTADO` en
> este documento. No se inventa ni se extrapola una cifra de AWS a partir de
> la medición local.**

Lo que SÍ se hizo: mediciones LOCALES reales (Docker Desktop, host
`x86_64`), contra la imagen REAL del `trainer` (etapa `trainer` del
`Dockerfile` de Combat) y la imagen `runtime` real para el `evaluator`, cada
una conectada a un MongoDB real (replica set de un solo miembro, igual
topología lógica que `data.yml`). Estas cifras son una COTA DE REFERENCIA
útil para fijar `mem_limit` de forma no arbitraria, **nunca una confirmación
de que el nodo `app` de AWS tiene capacidad** — eso exige la medición SSM
pendiente.

## Matriz de escenarios (formato exigido por §18.1)

| Escenario | CPU pico | Memoria pico | Disco | OOM | Resultado |
| --- | --- | --- | --- | --- | --- |
| A — Baseline (servicios habituales, sin workers IA) en nodo `app` real | NO EJECUTADO | NO EJECUTADO | NO EJECUTADO | NO EJECUTADO | Sin acceso AWS/SSM en este entorno |
| B — Entrenamiento (trainer + resto) en nodo `app` real | NO EJECUTADO | NO EJECUTADO | NO EJECUTADO | NO EJECUTADO | Sin acceso AWS/SSM en este entorno |
| C — Evaluación (evaluator + resto) en nodo `app` real | NO EJECUTADO | NO EJECUTADO | NO EJECUTADO | NO EJECUTADO | Sin acceso AWS/SSM en este entorno |
| D — Carga simultánea en nodo `app` real | NO EJECUTADO | NO EJECUTADO | NO EJECUTADO | NO EJECUTADO | Sin acceso AWS/SSM en este entorno |

## Mediciones LOCALES reales (sustituto de referencia, NO de AWS)

Metodología: contenedor real (imagen `nexus-battle-combat-trainer:test-native`
/ `nexus-battle-combat:test-native`, construidas desde el `Dockerfile` real
de la rama de este PR), conectado a un MongoDB 8.0 real en modo replica set
de un miembro (mismo `rs0` que usa `data.yml`), con las 31 migraciones de
Combat aplicadas. `docker stats --no-stream` capturado mientras el proceso
corría de verdad (no justo tras arrancar).

### `combat-trainer` — worker Node en reposo, conectado a Mongo, sin candidatas pendientes

```
$ docker run -d --name en037-4-trainer --network en037-4-test \
    -e PERSISTENCE_DRIVER=mongo -e MONGODB_URI="mongodb://en037-4-mongo:27017/combat?replicaSet=rs0" \
    -e NODE_ENV=development -e OMP_NUM_THREADS=1 -e OPENBLAS_NUM_THREADS=1 -e MKL_NUM_THREADS=1 \
    nexus-battle-combat-trainer:test-native \
    node dist/infrastructure/training/continuous-training-worker.js --poll-interval-ms 5000 --source-commit en037-4-local-test
$ docker stats --no-stream en037-4-trainer
CONTAINER ID   NAME              CPU %     MEM USAGE / LIMIT     MEM %   PIDS
4978b97b6adb   en037-4-trainer   0.20%     45.65MiB / 7.358GiB   0.61%   11
```

**Node coordinador en reposo/sondeo: ~46 MiB RSS, 11 PIDs.**

### Subproceso Python/PyTorch — entrenamiento representativo (dentro de la MISMA imagen)

El MLP de ADR-023 (`Linear(72→64) → ReLU → Linear(64→32) → ReLU →
Linear(32→1)`) con `AdamW`, 50 pasos, `batch_size=256` (igual orden de
magnitud que el hiperparámetro real documentado en ADR-023):

```
$ docker run --rm -e OMP_NUM_THREADS=1 -e OPENBLAS_NUM_THREADS=1 \
    nexus-battle-combat-trainer:test-native sh -c "cd ai && uv run python -c '
import torch, resource
m = torch.nn.Sequential(torch.nn.Linear(72,64), torch.nn.ReLU(), torch.nn.Linear(64,32), torch.nn.ReLU(), torch.nn.Linear(32,1))
opt = torch.optim.AdamW(m.parameters(), lr=0.001)
for _ in range(50):
    x = torch.randn(256,72); y = m(x); loss = y.pow(2).mean()
    opt.zero_grad(); loss.backward(); opt.step()
print(\"peak_rss_mb\", resource.getrusage(resource.RUSAGE_SELF).ru_maxrss/1024)
'"
peak_rss_mb 333.38671875
```

**Subproceso Python/PyTorch, pico de RSS propio: ~333 MB.**

Nota: esta corrida incluyó la resolución/instalación de `uv sync` en tiempo
de ejecución (contenedor efímero, sin `.venv` cacheada entre corridas de esta
prueba puntual) — en un despliegue real, `uv sync` ya corrió en tiempo de
`build` de la imagen (ver `Dockerfile`), así que el RSS en producción debería
ser igual o levemente MENOR que esta cifra (nunca mayor por esta causa).

**Estimación compuesta (suma simple, NUNCA una medición conjunta real):**
Node (~46 MiB) + subproceso Python en su pico (~333 MB) ≈ **~380-400 MB**
durante una iteración de entrenamiento real. El límite elegido en
`compose/nodes/app.yml` (`combat-trainer: mem_limit: 512m`) deja un margen
de ~110-130 MB sobre esta estimación — una cota de seguridad, no una
confirmación de que 512m es definitivamente suficiente en el nodo real
(que tiene otros 13 contenedores compitiendo por la misma RAM física).

### `combat-evaluator` — worker Node en reposo, conectado a Mongo, sin candidatas pendientes

```
$ docker run -d --name en037-4-evaluator --network en037-4-eval-test \
    -e PERSISTENCE_DRIVER=mongo -e MONGODB_URI="mongodb://en037-4-eval-mongo:27017/combat?replicaSet=rs0" \
    -e NODE_ENV=development \
    nexus-battle-combat:test-native \
    node dist/infrastructure/evaluation/automatic-evaluation-worker.js --poll-interval-ms 5000 --source-commit en037-4-local-test
$ docker stats --no-stream en037-4-evaluator
CONTAINER ID   NAME                CPU %     MEM USAGE / LIMIT     MEM %   PIDS
615db32ce3c7   en037-4-evaluator   11.96%    36.53MiB / 7.358GiB   0.48%   11
```

**Node evaluador en reposo/sondeo: ~37 MiB RSS, 11 PIDs.**

**NO medido localmente:** el consumo durante una `FULL_EVALUATION` real
(cientos de combates simulados, incluido MCTS como teacher/comparador, más
una sesión ONNX Runtime Node cargada) — requiere una candidata real
registrada en el Model Registry y un conjunto de escenarios/semillas
completo, que no se montó en esta auditoría por el costo de tiempo. El
`mem_limit: 384m` elegido es, por tanto, una cota de seguridad MÁS
conservadora todavía (sin medición directa bajo carga real), y debe
verificarse con una `FULL_EVALUATION` real antes de confiar en ella en
producción.

## Lo que ADR-022/ADR-019 ya establecieron (contexto, no una medición nueva)

- ADR-019 (2026-09-16, pre-resize): nodo `app` en `t4g.small`, 1841 MiB
  totales, 893 MiB en uso, 766 MiB libres.
- ADR-022 (2026-09-30/10-01, post-resize): nodo `app` en `t4g.medium`, 3830
  MiB totales, 1574 MiB en uso, 2066 MiB libres, 13 contenedores.

**Ninguna medición posterior al incidente OOM de Combat del 2026-10-07
(elevación a `mem_limit: 256m`) ni a la incorporación final de
Tournament/Chatbot existe en el repositorio.** La suma actual de
`mem_limit` en `compose/nodes/app.yml` (sin los workers de IA) es **2320
MiB** — ya por encima de los 2066 MiB "libres" que midió ADR-022 antes de
esos dos cambios. Esto es una señal de que el presupuesto de memoria del
nodo `app` necesita una medición SSM fresca con urgencia, **independientemente**
de si se despliegan o no los workers de IA — se documenta aquí porque esta
auditoría lo encontró, no porque sea causado por EN-037.4.

## Procedimiento para completar la medición SSM real (pendiente, requiere acceso AWS)

1. `aws ssm start-session --target <instance-id-app>` (mismo runbook que usó ADR-022).
2. `free -m`, `df -h`, `docker stats --no-stream`, `docker ps` — Escenario A, ANTES de tocar nada.
3. Desplegar `combat-trainer` solo (sin `combat-evaluator`), forzar una iteración real (`docker exec ... node dist/infrastructure/training/continuous-training-worker.js --once`), repetir las mismas capturas durante la ejecución — Escenario B.
4. Detener `combat-trainer`, desplegar `combat-evaluator` solo, forzar una `FULL_EVALUATION` real, repetir capturas — Escenario C.
5. Si B y C no mostraron señales de insuficiencia (sin OOM, sin swap sostenido, Combat sigue `ready`), desplegar ambos simultáneamente y repetir — Escenario D.
6. Completar la tabla de arriba con los números reales, nunca con los de este documento (que son locales, no de AWS).
7. Si cualquier escenario muestra OOM o degradación de Combat, DETENER el despliegue de ese worker y documentar el bloqueo concreto (qué contenedor, qué cifra, qué mitigación se evaluó) en vez de forzarlo.
