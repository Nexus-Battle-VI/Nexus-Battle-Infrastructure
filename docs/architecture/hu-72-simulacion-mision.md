# HU-72 — Diseño de la ejecución de la simulación de misión

**Estado:** diseño. **No implementado.** Combat no expone `POST /api/internal/v1/combat/simulations` y Missions no tiene rutas de negocio en `develop`. Nada de este documento autoriza a marcar capacidades como disponibles en [service-catalog.md](../contracts/service-catalog.md).

## Trazabilidad

| Elemento | Referencia |
| --- | --- |
| Historia | [HU-72 #57](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/57) — Ejecución de la simulación de misión (`RF-72`) |
| Épica | [EPIC-08 #8](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/8) — Misiones |
| Task de diseño | [HU-72.1 #373](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/373) |
| Tasks que usan este diseño | [HU-72.2 #374](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/374) implementación y [HU-72.3 #375](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/375) pruebas |
| Decisiones de arquitectura | [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md): Missions pide la simulación a Combat de forma síncrona con `operationId` y no duplica reglas. [ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md): la aleatoriedad es solo de Combat |
| Contrato | [hu-72-mission-simulation-v1.md](../contracts/hu-72-mission-simulation-v1.md) y [fixtures](../contracts/hu-72-mission-simulation-fixtures-v1.json) |
| Diagramas | [casos de uso](../diagrams/hu-72-use-case.puml), [actividad](../diagrams/hu-72-activity.puml), [secuencia](../diagrams/hu-72-sequence.puml), [dominio](../diagrams/hu-72-domain.puml) y [estados](../diagrams/hu-72-execution-states.puml) |
| Fuente funcional | Documento del curso, §7.8.1, §7.8.5, §7.8.6, §7.8.8 y §7.8.12 |
| Diseños de los que parte | [HU-70](hu-70-matriculacion-mision.md): matrícula, compromiso del héroe y hecho `MissionEnrollmentStarted` |
| HU relacionadas | HU-71 (rotaciones), HU-73 (Máster), HU-74 (reporte), HU-75 (dificultad, [Infrastructure#125](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/125)), HU-76 (logros) y HU-10 (recompensas) |

## Vista rápida (para revisión)

| Pregunta | Respuesta del diseño |
| --- | --- |
| ¿Quién simula? | Combat, el único servicio con reglas de combate y aleatoriedad. Missions orquesta: pide la simulación, guarda el resultado y cierra la misión. |
| ¿Cuándo? | En cuanto la matrícula pasa a `IN_PROGRESS`. El resultado queda **sellado** hasta que vence la duración (`endsAt`). |
| ¿Qué pasa si Combat no responde? | Missions reintenta con el mismo `operationId` y la misión espera. ADR-019 lo acepta: una misión simulada con otras reglas sería peor que una misión que espera. |
| ¿Cuándo se libera al héroe? | Al cerrar la misión en `endsAt`, o al anularla, **una sola vez**, con el `operationId` del compromiso de HU-70. |
| ¿Qué falta de Team Alfa? | El endpoint de simulación, la IA que aplica las rotaciones, combatientes enemigos con perfil y el perfil de combate del héroe por `heroId`. |

## Decisiones funcionales literales (HU publicada)

1. La simulación es automática y asíncrona.
2. La IA controla al héroe según las rotaciones configuradas y a los enemigos (CA-02).
3. Se aplican las mismas mecánicas de combate y el mismo motor de aleatoriedad que en las batallas en línea (CA-03).
4. La simulación recorre los encuentros configurados contra los enemigos regulares y el jefe final.
5. Los enemigos aplican la dificultad escalada de la misión: su poder crece a medida que avanzan los encuentros.
6. Se registran todos los eventos para el reporte; como mínimo, encuentros completados, daño infligido y recibido, turnos, habilidades usadas y efectos críticos (CA-01).
7. El resultado final es éxito, fallo o abandono. Éxito: se cumplen los objetivos dentro de la duración (CA-06). Fallo: el héroe cae antes de cumplirlos (CA-04).
8. Al terminar, el héroe queda liberado (CA-05).

## Criterios técnicos propuestos (no aprobados por el PO)

| Id | Propuesta | Por qué |
| --- | --- | --- |
| P-S1 | Separar **simular** de **cerrar**: se simula al iniciar la misión y se cierra al llegar `endsAt`. | La duración es parte del juego (§7.8.6: al completarse el tiempo se genera el reporte y se libera al héroe). Simular pronto deja margen para reintentar si Combat falla. |
| P-S2 | Agregado `MissionExecution`, uno por matrícula, con su propio `operationId` hacia Combat. | Separa el ciclo técnico de la simulación del ciclo funcional de la matrícula de HU-70. |
| P-S3 | Llamada síncrona a Combat con reintentos del mismo `operationId`. Combat guarda la simulación y responde lo mismo ante ese `operationId`. | ADR-019 fija el modo síncrono y la idempotencia por `operationId`. |
| P-S4 | Missions envía **todo** lo que Combat necesita: perfil congelado del héroe, rotaciones, encuentros con perfiles base de enemigos, multiplicador de dificultad, configuración del Máster y presupuesto de tiempo. Combat no consulta a Missions. | Hoy los combatientes IA de Combat no tienen perfil (HU-18); sus estadísticas son contenido de Missions. |
| P-S5 | Missions evalúa los objetivos con los hechos del resumen que devuelve Combat; Combat no conoce los objetivos. | Los objetivos son contenido de la misión, no reglas de combate. |
| P-S6 | Objetivos evaluables en esta versión: `DEFEAT_BOSS`, `CLEAR_ENCOUNTERS`, `MIN_HEALTH_PERCENT` y `DEFEAT_MASTER`. | Cubren los objetivos del ejemplo del curso que se pueden decidir sin botín. Los de botín esperan a HU-10. |
| P-S7 | Resultado técnico `VOIDED` (misión anulada: sin penalización, sin *clear* y sin recompensas) cuando Combat rechaza la configuración o se agota el plazo de reintentos. El héroe se libera. | Un error técnico no es un fallo del jugador. Propone añadir `VOIDED` al vocabulario de estados de HU-70. |
| P-S8 | Plazo de reintentos: hasta `endsAt + 30 min`. Mientras tanto la matrícula sigue `IN_PROGRESS`. | Coincide con el margen del compromiso de HU-70 (P-M8). |
| P-S9 | La bitácora completa se guarda en Missions junto al resumen. El jugador no ve nada del resultado antes de `endsAt`. | HU-74 construye el reporte con ella. ADR-019: un resultado reproducible para auditoría, pero no predecible para el jugador. |
| P-S10 | La liberación del héroe se hace **después** de confirmar el cierre, con el `operationId` de HU-70, y se anota `heroReleasedAt`. | Liberar es idempotente en Player/Inventory, así que reintentar no libera dos veces (P-05). |

## Caso de uso textual

### CU-72.1 Ejecutar la simulación (actor: planificador de Missions)

- **Precondición:** matrícula `IN_PROGRESS` con su hecho `MissionEnrollmentStarted` (HU-70).
- **Flujo principal:**
  1. Al registrarse el hecho, Missions crea la `MissionExecution` en `QUEUED` con un `operationId` nuevo.
  2. El planificador (intervalo en proceso con `FOR UPDATE SKIP LOCKED`, patrón de ADR-019) la toma y arma la solicitud: perfil del héroe, rotaciones, encuentros, dificultad, Máster y presupuesto de tiempo.
  3. La pasa a `REQUESTED` y llama a Combat.
  4. Con la respuesta `200`, guarda resumen, bitácora y `seedRef` y la pasa a `SIMULATED`. El resultado queda sellado.
- **Alternativas:**
  - A1. Combat no responde, responde `503` o hay un error de red: se programa un reintento con el mismo `operationId` (ver [reintentos](#reintentos)).
  - A2. Combat responde `422` (configuración que no puede simular) o se agota el plazo: la ejecución pasa a `VOIDED` y se aplica CU-72.3.
- **Postcondición:** resultado guardado y oculto al jugador.

### CU-72.2 Cerrar la misión al vencer su duración

- **Precondición:** ejecución `SIMULATED` y `endsAt` alcanzado.
- **Flujo principal:**
  1. El planificador toma la ejecución y evalúa los objetivos con el resumen (P-S5 y P-S6).
  2. En una sola transacción: la matrícula pasa a `COMPLETED` (éxito, CA-06) o a `FAILED` (fallo, CA-04), la ejecución pasa a `SETTLED`, se inserta el *clear* de HU-75 si hubo éxito y se registra el hecho `MissionSettled` para HU-74, HU-76, HU-10 y Notifications.
  3. Después del `COMMIT`, libera al héroe en Player/Inventory con el `operationId` del compromiso y anota `heroReleasedAt` (CA-05).
- **Postcondiciones:** héroe disponible, resultado visible para el jugador y reporte listo para HU-74.

### CU-72.3 Anular por error técnico (propuesta P-S7)

La matrícula pasa a `VOIDED` y la ejecución también; se libera al héroe y se registra `MissionSettled` con `outcome: VOIDED`. No hay penalización, *clear* ni recompensas.

### CU-72.4 Abandonar (pendiente)

HU-72 reserva el resultado `ABANDONED`. No hay contrato aprobado de cancelación ni de penalización (decisión 3). Escenario P-06: pendiente.

## Estados de la ejecución

Diagrama: [hu-72-execution-states.puml](../diagrams/hu-72-execution-states.puml).

| Desde | Hacia | Disparador | Efecto en la matrícula (HU-70) |
| --- | --- | --- | --- |
| — | `QUEUED` | Hecho `MissionEnrollmentStarted` | Sigue `IN_PROGRESS` |
| `QUEUED` | `REQUESTED` | El planificador envía la solicitud | Sigue `IN_PROGRESS` |
| `REQUESTED` | `REQUESTED` | `503`, tiempo agotado o red: reintento programado | Sigue `IN_PROGRESS` |
| `REQUESTED` | `SIMULATED` | `200` de Combat: resultado guardado y sellado | Sigue `IN_PROGRESS` |
| `SIMULATED` | `SETTLED` | Llega `endsAt` | `COMPLETED` o `FAILED` |
| `QUEUED` o `REQUESTED` | `VOIDED` | `422`, `400` o `409` de Combat, o plazo agotado | `VOIDED` (propuesta) |

Tras `SETTLED` o `VOIDED`, la liberación del héroe se reintenta hasta confirmarse; no cambia más estados.

## Resultado y objetivos

Combat devuelve un `outcome` de combate y un resumen de hechos. Missions decide el resultado de la misión:

| `outcome` de Combat | Objetivos principales | Resultado de la misión |
| --- | --- | --- |
| `HERO_DEFEATED` | No importan | `FAILED` (CA-04) |
| `HERO_VICTORIOUS` | Cumplidos | `COMPLETED` (CA-06) |
| `HERO_VICTORIOUS` | Alguno sin cumplir | `FAILED` (decisión 2) |
| `TIME_BUDGET_EXHAUSTED` | Cumplidos antes de agotarse | `COMPLETED` |
| `TIME_BUDGET_EXHAUSTED` | Alguno sin cumplir | Propuesta: `FAILED` con motivo `TIME_LIMIT` (decisión 2) |

Los objetivos secundarios no cambian el resultado: alimentan bonificaciones (HU-10) y logros (HU-76).

## Modelo conceptual de datos

| Dato | Propietario | Dónde vive |
| --- | --- | --- |
| Ejecución, resumen y bitácora | Missions | `mission_executions` |
| Hechos para otras HU (`MissionEnrollmentStarted`, `MissionSettled`) | Missions | `mission_facts` |
| *Clear* por dificultad | Missions (HU-75) | `mission_difficulty_clears` |
| Simulación, semilla y estado del generador | Combat | Base `combat`; Missions solo guarda `simulationId` y `seedRef`, opacos |
| Compromiso del héroe | Player/Inventory | Fuera de Missions; se libera con el `operationId` de HU-70 |

```sql
CREATE TABLE mission_executions (
  enrollment_id     text PRIMARY KEY REFERENCES mission_enrollments (enrollment_id),
  operation_id      text NOT NULL UNIQUE,
  status            text NOT NULL CHECK (status IN ('QUEUED', 'REQUESTED', 'SIMULATED', 'SETTLED', 'VOIDED')),
  attempts          integer NOT NULL DEFAULT 0,
  next_attempt_at   timestamptz,
  last_error        text,
  simulation_id     text,
  seed_ref          text,
  combat_outcome    text CHECK (combat_outcome IN ('HERO_VICTORIOUS', 'HERO_DEFEATED', 'TIME_BUDGET_EXHAUSTED')),
  summary           jsonb,
  combat_log        jsonb,
  simulated_at      timestamptz,
  settled_at        timestamptz,
  hero_released_at  timestamptz,
  version           integer NOT NULL DEFAULT 0,
  CHECK (status NOT IN ('SIMULATED', 'SETTLED') OR (summary IS NOT NULL AND combat_log IS NOT NULL))
);

CREATE INDEX ix_execution_due ON mission_executions (next_attempt_at) WHERE status IN ('QUEUED', 'REQUESTED');
CREATE INDEX ix_execution_release ON mission_executions (settled_at)
  WHERE status IN ('SETTLED', 'VOIDED') AND hero_released_at IS NULL;

CREATE TABLE mission_facts (
  fact_id      text PRIMARY KEY,
  type         text NOT NULL,
  enrollment_id text NOT NULL REFERENCES mission_enrollments (enrollment_id),
  payload      jsonb NOT NULL,
  created_at   timestamptz NOT NULL,
  UNIQUE (type, enrollment_id)
);
```

`UNIQUE (type, enrollment_id)` hace que registrar dos veces el mismo hecho sea imposible, aunque el cierre se reintente.

## Reintentos

| Paso | Respuesta | Acción | Reintento |
| --- | --- | --- | --- |
| Pedir la simulación | `200` | Guardar el resultado y pasar a `SIMULATED` | — |
| Pedir la simulación | `503`, tiempo agotado o error de red | Mantener `REQUESTED` | Mismo `operationId` a los 5 s, 30 s, 2 min y 10 min, y luego cada 10 min hasta `endsAt + 30 min` |
| Pedir la simulación | `422` | `VOIDED` y registrar el motivo | No |
| Pedir la simulación | `400` o `409 OPERATION_ID_REUSED` | `VOIDED`, registrar y alertar: es un error de programación | No |
| Liberar al héroe | `204` | Anotar `heroReleasedAt` | — |
| Liberar al héroe | `503`, tiempo agotado o red | Mantener pendiente | Mismo `operationId`, con el mismo escalonado y sin límite (el compromiso caduca solo en el peor caso) |

Un fallo **después** de guardar el resultado y **antes** de cerrar no pierde nada: el cierre lee lo guardado y es idempotente (`UNIQUE` del hecho y transición condicionada por `version`).

## Separación con Jugar Online y Combat

| Missions (Team Beta) | Combat (Team Alfa) |
| --- | --- |
| Decide **cuándo** simular y cerrar | Ejecuta la simulación completa |
| Congela y envía perfiles, rotaciones, encuentros y dificultad | Aplica las mecánicas de HU-11, HU-18, HU-19 y HU-20 |
| Evalúa objetivos y decide el resultado de la misión | Decide quién gana cada encuentro y cuándo cae el héroe |
| Guarda resumen y bitácora | Genera toda la aleatoriedad (HU-24, HU-25) y guarda la semilla |
| Libera al héroe | Aplica la IA de rotaciones (CA-02) y la de los enemigos |

Missions **no** genera números aleatorios, **no** calcula daño y **no** decide acciones de la IA. Un doble en pruebas que devuelva resultados fijos sirve para HU-72.2, pero **no** acredita CA-02 ni CA-03: esos solo se aceptan con Combat real.

## Campos que necesitan las demás HU

La solicitud y la respuesta reservan estos campos para que HU-73, HU-74, HU-76 y HU-10 no tengan que cambiar el contrato:

| Campo del resultado | Lo produce | Lo usa |
| --- | --- | --- |
| `summary.encountersCompleted`, `totalTurns` y `damageDealt` / `damageTaken` | Combat | HU-74 (reporte) |
| `summary.skillsUsed` y `criticalEffects` | Combat | HU-74 |
| `summary.enemiesDefeated` y `bossDefeated` | Combat | HU-74 y objetivos `DEFEAT_BOSS` / `CLEAR_ENCOUNTERS` |
| `summary.minHealthPercent` | Combat | Objetivo `MIN_HEALTH_PERCENT` y HU-76 («sin recibir daño») |
| `summary.master` (`appeared`, `masterRef`, `defeated`) | Combat, con su generador | HU-73, HU-32, HU-74 y HU-76 |
| `summary.simulatedDuration` | Combat | HU-74 y HU-76 («tiempo récord») |
| Resultado de la misión y objetivos cumplidos | Missions | HU-74, HU-10 (recompensas) y HU-76 |
| `combatLog[]` | Combat | HU-74 (bitácora del reporte) |

## Matriz RF → CA → escenario → salida esperada

Los escenarios con datos de ejemplo están en los [fixtures](../contracts/hu-72-mission-simulation-fixtures-v1.json).

| RF | CA | Escenario | Salida esperada | Elemento de diseño |
| --- | --- | --- | --- | --- |
| RF-72 | CA-01 y CA-06 | P-01: configuración válida y objetivos cumplidos a tiempo | Ejecución `SETTLED`; matrícula `COMPLETED`; bitácora y resumen completos; *clear* insertado | CU-72.1 y CU-72.2 |
| RF-72 | CA-02 | P-02: rotaciones configuradas | Las acciones del héroe en la bitácora siguen la prioridad de las rotaciones | Combat (integración real) |
| RF-72 | CA-03 | P-03: se requiere un efecto aleatorio | El efecto sale del generador de Combat; Missions solo guarda `seedRef` | Combat (integración real) |
| RF-72 | CA-04 y CA-05 | P-04: el héroe cae antes de cumplir los objetivos | Matrícula `FAILED`; bitácora hasta la derrota; héroe liberado | Tabla de resultado |
| RF-72 | CA-05 | P-05: cualquier cierre válido | Una sola liberación confirmada (`heroReleasedAt`) | P-S10 |
| RF-72 | CA-01 | P-06: el jugador abandona | **Pendiente:** no hay contrato de cancelación | Decisión 3 |
| — | — | T-01: Combat no responde y luego sí | Reintentos con el mismo `operationId`; un solo resultado guardado | P-S3 |
| — | — | T-02: Combat responde dos veces al mismo `operationId` | Se guarda una vez; la segunda respuesta coincide y se descarta | P-S3 |
| — | — | T-03: caída después de guardar el resultado | El cierre se repite sin duplicar hechos ni liberaciones | `UNIQUE` y `version` |
| — | — | T-04: Combat rechaza la configuración (`422`) | Matrícula y ejecución `VOIDED`; héroe liberado; sin *clear* | P-S7 |
| — | — | T-05: el presupuesto de tiempo se agota | Propuesta: `FAILED` con motivo `TIME_LIMIT` | Decisión 2 |

## Impacto arquitectónico

| Componente | Cambio | Responsable |
| --- | --- | --- |
| Missions | `mission_executions` y `mission_facts`; planificadores de simulación, cierre y liberación; evaluación de objetivos | Team Beta (HU-72.2) |
| Combat | `POST /api/internal/v1/combat/simulations` con persistencia de la simulación y su semilla; IA de rotaciones y de enemigos; combatientes con perfil recibido en la solicitud | Team Alfa |
| Player/Inventory | Perfil de combate del héroe por `heroId` (o en la respuesta del compromiso de HU-70) y, si hace falta, renovar el compromiso | Team Alfa |
| Notifications | Plantilla de fin de misión por la ingesta HTTP (ADR-019) | Team Alfa |
| AWS e infraestructura | Ninguno: sin servicios ni colas nuevas | — |

## Decisiones pendientes (visibles, no resueltas)

1. **Qué significa «dentro de su duración».** La simulación es acelerada. Propuesta: Combat recibe un presupuesto de tiempo simulado igual a la duración y cuenta cada turno con una duración fija. Falta fijar esa duración.
2. **Resultado cuando se agota el tiempo sin cumplir los objetivos, o cuando el héroe gana los combates pero falta un objetivo principal.** Propuesta: `FAILED` con motivo `TIME_LIMIT`. La HU solo define fallo por derrota.
3. **Abandono y penalización.** La HU nombra el abandono pero no hay contrato de cancelación ni penalización definida (§7.8.7).
4. **Anulación técnica `VOIDED`** (P-S7): nombre, efectos y si se notifica al jugador.
5. **Vocabulario de objetivos** (P-S6). Los de botín, como «encontrar 3 fragmentos», dependen de HU-10.
6. **IA de los enemigos** («estrategias predefinidas», §7.8.6): la define Combat.
7. **Perfiles de enemigos y jefe.** Son contenido de las misiones del curso (§7.8.4) y no hay issue. Hoy los combatientes IA de Combat no tienen perfil.
8. **Escalado por encuentro.** La fórmula del incremento progresivo es contenido; cómo se combina con el multiplicador de HU-75 y cómo se redondea sigue abierto también en HU-75.
9. **Botín aleatorio** (HU-10): debe salir del generador de Combat (CA-03). ¿Se sortea dentro de la simulación?
10. **Perfil del héroe por `heroId`.** Opción A: la respuesta del compromiso de HU-70 trae el perfil congelado. Opción B: una ruta interna nueva. Lo decide Team Alfa.
11. **Renovar el compromiso** si Combat tarda más que el margen de 30 minutos.
12. **Tamaño y retención de la bitácora.**
13. **Nivel del héroe en el reporte** (§7.8.8): no existe nivel de héroe en Player/Inventory.
