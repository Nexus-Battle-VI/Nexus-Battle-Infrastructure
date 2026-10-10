# EN-037.4 (Management #573) — Arranque, parada y recuperación

Todas las pruebas de este documento corrieron LOCALMENTE (Docker Desktop,
contenedores reales, MongoDB real en modo replica set) contra las imágenes
construidas en `container-build-results.md`. Ninguna corrió en AWS — ver
`deployment-result.md`.

## 1. Migraciones antes del arranque de los workers

```
$ docker run --rm --network en037-4-test -e PERSISTENCE_DRIVER=mongo \
    -e MONGODB_URI="mongodb://en037-4-mongo:27017/combat?replicaSet=rs0" -e NODE_ENV=development \
    nexus-battle-combat-trainer:test-native node dist/infrastructure/persistence/migrate.js
...
{"message":"migration_applied","migration":"031-ai-atomic-active-and-evaluation-evidence"}
{"message":"migrations_up_to_date","applied":31}
```

Las 31 migraciones de Combat (incluidas las 5 de IA: `027`-`031`) se aplican
limpiamente usando la MISMA imagen que el worker (`nexus-battle-combat-trainer`
también contiene `dist/infrastructure/persistence/migrate.js`, igual
binario que usa `combat-migrate` en producción). Confirma que
`combat-trainer`/`combat-evaluator` pueden depender de `combat-migrate`
exactamente como se diseñó en `compose/nodes/app.yml` (`condition:
service_completed_successfully`), sin necesitar un proceso de migración
separado.

## 2. Arranque — `combat-trainer`

```
$ docker run -d --name en037-4-trainer ... nexus-battle-combat-trainer:test-native \
    node dist/infrastructure/training/continuous-training-worker.js --once --source-commit en037-4-local-test
$ docker logs en037-4-trainer
{"message":"continuous_training_worker_started","ownerId":"117ffb7f2789:1:d1066b8fc28d","aiDir":"/app/ai","once":true}
{"message":"continuous_training_worker_stopped","iterations":1}
```

Arranque limpio, evento estructurado real (`continuous_training_worker_started`,
el mismo nombre de evento que ya emite el código — no inventado para esta
prueba), `aiDir` resuelto correctamente por default (`/app/ai`, sin
necesidad de pasar `--ai-dir`). Con `--once` y sin ninguna `BattleRoom`
`FINISHED` pendiente en el Mongo de prueba, el worker detecta
correctamente que no hay trabajo (`IDLE`) y termina limpio
(`continuous_training_worker_stopped`, `iterations: 1`, código de salida 0).

## 3. Arranque — `combat-evaluator`

```
$ docker run -d --name en037-4-evaluator ... nexus-battle-combat:test-native \
    node dist/infrastructure/evaluation/automatic-evaluation-worker.js --poll-interval-ms 5000 --source-commit en037-4-local-test
$ docker logs en037-4-evaluator
{"message":"automatic_evaluation_worker_started","ownerId":"615db32ce3c7:1:b94494ec-37e9-4e54-a3dd-f2d28537d77f","once":false}
```

Arranque limpio sobre la imagen `runtime` (confirmando que el evaluador NO
necesita la imagen `trainer`/Python), evento estructurado real
(`automatic_evaluation_worker_started`), modo continuo (`--poll-interval-ms
5000`, sin `--once`) corriendo de forma estable durante la ventana de
medición (ver `resource-measurements.md`).

## 4. Independencia de `combat` (API) frente a los workers — §9.5 del prompt maestro

Verificado por diseño en `compose/nodes/app.yml` (no por prueba de
integración completa de los 14 servicios, que excede el alcance de esta
auditoría local):

- `combat` (API) `depends_on: combat-migrate` ÚNICAMENTE — nunca
  `combat-trainer` ni `combat-evaluator`.
- `combat-trainer`/`combat-evaluator` `depends_on: combat-migrate`
  ÚNICAMENTE — nunca `combat` (API).
- Ningún servicio del fichero tiene `combat-trainer`/`combat-evaluator`
  como dependencia.

Esto garantiza, estructuralmente (no solo por intención en un comentario),
que un fallo o parada de cualquiera de los dos workers nunca impide que
`combat-migrate` complete, ni que `combat` arranque — son tres ramas
independientes que solo comparten el prerequisito común `combat-migrate`.

## 5. Parada controlada

```
$ docker rm -f en037-4-trainer en037-4-evaluator en037-4-mongo en037-4-eval-mongo
```

`docker rm -f` envía `SIGTERM` y, tras el periodo de gracia, `SIGKILL` si no
terminó — el mismo comportamiento que `docker compose stop`/`down` (sin
`-v`) produciría en producción. Ambos workers terminaron sin dejar procesos
huérfanos (`docker ps -a` tras la prueba no mostró contenedores
`Exited` con código distinto de 0 o 137/143 esperados por la señal).

## 6. Recuperación tras reinicio — qué SÍ se verificó y qué NO

**Verificado (por diseño de código, EN-037.2/EN-037.3, no repetido aquí
como prueba nueva):** el lease/fencing distribuido de
`ContinuousTrainingCoordinatorPort`/`AiEvaluationCoordinatorPort` ya tiene
suite de pruebas reales contra MongoDB (`test/db/mongo-continuous-training-coordinator.spec.ts`,
`test/db/mongo-ai-evaluation-coordinator.spec.ts` en el repositorio de
Combat) que demuestran recuperación segura tras pérdida de lease, sin
duplicar trabajo ni corromper estado. Esta Issue (#573) es de
INFRAESTRUCTURA/despliegue, no repite esa prueba de lógica — la referencia
aquí es para no reimplementarla ni reafirmarla sin evidencia.

**NO verificado en esta auditoría (requiere una iteración de entrenamiento
real en curso, con datos, interrumpida a mitad de camino):** un reinicio
real de Docker/contenedor DURANTE un entrenamiento/evaluación en curso,
observando la recuperación de principio a fin contra el nodo real. Esto es
exactamente el alcance de **EN-037.5 #574** ("validar E2E del ciclo
continuo y recuperación ante fallos"), declarado explícitamente fuera del
alcance de #573 por el propio Management.

## 7. Señales/timeouts

No se envió `SIGTERM` manualmente durante una ejecución activa de
`uv run nexus-combat-train` en esta auditoría (requeriría datos reales en
curso, mismo límite que el punto 6). El manejo de `SIGTERM`/`SIGINT` con
escalamiento a `SIGKILL` tras gracia ya está implementado y probado a nivel
de código en `ChildProcessRunner.ts`/`continuous-training-worker.ts`
(EN-037.2) — no se repite esa prueba aquí.
