# HU-70 — Diseño de la matriculación en una misión

**Estado:** diseño. **No implementado.** En `develop`, `Nexus-Battle-Missions` solo tiene el andamiaje (health y version). Nada de este documento autoriza a marcar rutas como disponibles en [service-catalog.md](../contracts/service-catalog.md).

## Trazabilidad

| Elemento | Referencia |
| --- | --- |
| Historia | [HU-70 #55](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/55) — Matriculación en una misión (`RF-70`) |
| Épica | [EPIC-08 #8](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/8) — Misiones |
| Task de diseño | [HU-70.1 #365](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/365) |
| Tasks que usan este diseño | [HU-70.2 #366](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/366) implementación, [HU-70.3 #367](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/367) interfaz y [HU-70.4 #368](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/368) pruebas |
| Decisión de arquitectura | [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md): Missions es dueño de definiciones, tablón y matrículas; la disponibilidad del héroe vive en Player/Inventory |
| Contrato | [hu-70-mission-enrollment-v1.md](../contracts/hu-70-mission-enrollment-v1.md), [borrador OpenAPI](../contracts/hu-70-mission-enrollment-v1.openapi.yaml) y [fixtures](../contracts/hu-70-mission-enrollment-fixtures-v1.json) |
| Diagramas | [casos de uso](../diagrams/hu-70-use-case.puml), [actividad](../diagrams/hu-70-activity.puml), [secuencia](../diagrams/hu-70-sequence.puml), [dominio](../diagrams/hu-70-domain.puml) y [estados](../diagrams/hu-70-enrollment-states.puml) |
| Fuente funcional | Documento del curso, §7.8.3, §7.8.6, §7.8.7, §7.8.9, §7.8.10 y el ejemplo de §7.8.14 |
| HU relacionadas | HU-75 (#60) añade `difficulty` a esta matrícula ([Infrastructure#125](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/125)); HU-71 (#56) aporta las rotaciones; HU-72 (#57) ejecuta la matrícula en curso y la cierra |

## Vista rápida (para revisión)

| Pregunta | Respuesta del diseño |
| --- | --- |
| ¿Qué entrega HU-70? | El tablón, el detalle de una misión y el acto de matricular: la misión pasa a **En progreso**, el héroe queda comprometido y empieza a contar la duración. |
| ¿Quién guarda cada cosa? | Missions guarda definiciones, matrículas y el vencimiento. Player/Inventory guarda la disponibilidad del héroe (compromiso `MISSION`) y su equipamiento. Combat no participa en HU-70. |
| ¿Cómo se impide un héroe en dos misiones? | Con dos barreras: un índice único parcial en PostgreSQL sobre las matrículas activas y un compromiso exclusivo en Player/Inventory. |
| ¿Qué pasa si Player/Inventory no responde? | La matrícula queda `PENDING`, el jugador recibe `503` y un reconciliador reintenta con el mismo `operationId` hasta confirmar o liberar. |
| ¿Qué depende de otros equipos? | El compromiso `MISSION` (Player/Inventory), que Combat y Torneo pidan su propio compromiso (CA-03 y CA-05) y el contenido de las misiones. |

## Decisiones funcionales literales (HU publicada)

Tomadas de HU-70 sin reinterpretar:

1. La misión se elige del tablón y debe estar **Disponible**; una misión **Bloqueada** por misiones previas no se matricula (CA-07).
2. El héroe debe estar libre: ni en otra misión (CA-02) ni en un torneo activo (CA-03).
3. El héroe debe tener **mazo completo** equipado (CA-04).
4. Al confirmar, la misión pasa a **En progreso**, el héroe queda bloqueado para JcJ y torneos y arranca el temporizador con la duración de la misión (CA-01).
5. Mientras dure la misión no se puede modificar el equipamiento del héroe (CA-05).
6. Antes de confirmar, el jugador ve descripción y objetivos, duración, requisitos, galería de enemigos con el jefe final, probabilidad y tipos de Máster con sus épicas, y la tabla de recompensas (CA-06).

## Criterios técnicos propuestos (no aprobados por el PO)

| Id | Propuesta | Por qué |
| --- | --- | --- |
| P-M1 | Estados de la matrícula: `PENDING`, `IN_PROGRESS`, `COMPLETED`, `FAILED`, `ABANDONED`, `REJECTED` y `EXPIRED`. **Activos:** `PENDING` e `IN_PROGRESS`. | La guía del PO pide fijar qué cuenta como matrícula activa. `PENDING` cuenta porque el héroe ya está en proceso de reserva. |
| P-M2 | Como mucho una matrícula activa por jugador y misión. | CA-01 habla de «la misión» en progreso; dos héroes a la vez en la misma misión no aparecen en la HU ni en el curso. |
| P-M3 | El `POST` de matrícula exige la cabecera `Idempotency-Key`. | Un doble clic o un reintento después de un `503` no deben crear dos matrículas. |
| P-M4 | Precedencia de validación: primero lo de la misión (existe, requisitos, dificultad) y después lo del héroe. | Responde a la guía del PO: distinguir misión bloqueada de héroe ocupado de forma determinista. |
| P-M5 | Héroe ocupado → `409 HERO_BUSY`; misión bloqueada → `422 MISSION_LOCKED`. | `409` es un conflicto con el estado de otro recurso que se resuelve con el tiempo; `422` es una regla que el jugador todavía no cumple. |
| P-M6 | La disponibilidad del héroe se pide a Player/Inventory como compromiso `MISSION`; Missions no consulta a Combat ni a Torneo. | ADR-019: la disponibilidad única vive junto a lo que se bloquea. |
| P-M7 | «Mazo completo» = todas las ranuras al tope de su capacidad (2 armas, 6 armaduras y 2 ítems), evaluado por Player/Inventory. | La política de *readiness* de Player/Inventory considera listo a un héroe sin equipamiento, así que no demuestra CA-04. Missions no duplica las capacidades de `HeroLoadout`. |
| P-M8 | Una matrícula `PENDING` tiene 2 minutos para confirmarse; el compromiso caduca en `requestedAt + 2 min + duración + 30 min`. | ADR-019 exige que toda reserva nazca con caducidad. Los 30 minutos cubren la simulación y el cierre de HU-72. |
| P-M9 | El temporizador es un dato: `startedAt` y `endsAt` en la base, fijados por el servidor al confirmar. | Mismo patrón de vencimientos que ADR-019: un reinicio retrasa el vencimiento, no lo pierde. |
| P-M10 | Un requisito previo se cumple con al menos un *clear* de esa misión en cualquier dificultad (tabla de clears de HU-75). | Evita un segundo registro de «misión completada». |
| P-M11 | El nivel recomendado es informativo y no bloquea. | La HU solo bloquea por misiones previas (CA-07); el curso lo llama «sugerencia de poder del héroe». |

## Caso de uso textual

### CU-70.1 Consultar el tablón

- **Actor:** jugador autenticado (rol `PLAYER`).
- **Flujo:** Web pide `GET /api/v1/missions`; Missions devuelve las misiones activas con el estado **para ese jugador** (ver [Estado de la misión para el jugador](#estado-de-la-misión-para-el-jugador)).
- **Filtros:** categoría (`STORY`, `CHALLENGE`, `EXPLORATION`) y estado. El filtro por dificultad queda pendiente (decisión 10).

### CU-70.2 Ver el detalle de una misión (CA-06)

- **Flujo:** Web pide `GET /api/v1/missions/{missionId}`; Missions devuelve narrativa, objetivos, duración, requisitos, enemigos, jefe final, encuentro con Máster y tabla de recompensas.
- **Excepción:** misión inexistente o inactiva → `404 MISSION_NOT_FOUND`.

### CU-70.3 Matricular un héroe (CA-01 a CA-05 y CA-07)

- **Precondiciones:** jugador autenticado; misión activa; el jugador eligió héroe, dificultad (HU-75) y, si HU-71 lo exige, rotaciones.
- **Entradas:** `missionId` (ruta), `heroId`, `difficulty`, `strategyVersion` (HU-71; `null` sin estrategia) y la cabecera `Idempotency-Key`.
- **Flujo principal:**
  1. Missions valida el cuerpo y la cabecera.
  2. Comprueba que la misión existe y está activa.
  3. Si la `Idempotency-Key` ya se usó, devuelve el resultado guardado (ver [reintentos](../contracts/hu-70-mission-enrollment-v1.md#reintentos-con-la-misma-clave)).
  4. Comprueba requisitos previos (CA-07) y progresión de dificultad (HU-75).
  5. Comprueba que el jugador no tenga ya esta misión en curso (P-M2) y que el héroe no esté en otra misión (CA-02).
  6. Guarda la matrícula en `PENDING` con un `operationId` nuevo. Los índices únicos parciales resuelven dos confirmaciones simultáneas.
  7. Pide a Player/Inventory el compromiso `MISSION` del héroe con ese `operationId`. Player/Inventory comprueba propiedad, *readiness*, mazo completo y exclusividad (CA-03 y CA-04).
  8. Con el compromiso concedido, pasa la matrícula a `IN_PROGRESS`, fija `startedAt` y `endsAt` y registra el hecho `MissionEnrollmentStarted` para HU-72, todo en la misma transacción.
  9. Responde `201` con la matrícula.
- **Alternativas:**
  - A1. Player/Inventory rechaza (héroe ajeno, no listo, mazo incompleto u ocupado): la matrícula pasa a `REJECTED` y el jugador recibe el error correspondiente.
  - A2. Player/Inventory no responde o responde `409` o `503`: la matrícula sigue `PENDING`, el jugador recibe `503 DEPENDENCY_UNAVAILABLE` y el reconciliador termina el trabajo (ver [Secuencia](#secuencia-de-matrícula-e-integración-con-playerinventory)).
- **Excepciones:** `400`, `401`, `403`, `404`, `409`, `422` y `503`, según el [catálogo de errores](../contracts/hu-70-mission-enrollment-v1.md#errores).
- **Postcondiciones de éxito:** matrícula `IN_PROGRESS`; compromiso `MISSION` vigente en Player/Inventory; `endsAt` persistido; hecho interno listo para HU-72.
- **Postcondiciones de rechazo:** ninguna matrícula activa nueva; el estado de la misión para el jugador no cambia (CA-02).

## Fragmento de dominio

Diagrama: [hu-70-domain.puml](../diagrams/hu-70-domain.puml).

- **`MissionDefinition`** (catálogo de Missions): identidad, categoría, textos, objetivos, duración estimada, nivel recomendado, requisitos previos, enemigos, jefe final, encuentro con Máster y recompensas. Es contenido: HU-70 no lo crea ni lo edita.
- **`MissionEnrollment`** (agregado): jugador, misión, héroe, dificultad, estado, `operationId`, `Idempotency-Key`, compromiso, rotaciones, instantes y versión. Solo este agregado cambia de estado; la definición de la misión no.
- **`EnrollmentPolicy`** (dominio puro, sin E/S): decide si una matrícula procede a partir de la definición, los clears del jugador y sus matrículas activas.
- **Puertos:** `MissionCatalogRepository`, `EnrollmentRepository`, `DifficultyClearRepository` (el de HU-75), `HeroCommitmentPort` (Player/Inventory), `Clock` e `IdGenerator`.

## Estados de la matrícula

Diagrama: [hu-70-enrollment-states.puml](../diagrams/hu-70-enrollment-states.puml).

| Desde | Hacia | Disparador | HU dueña |
| --- | --- | --- | --- |
| — | `PENDING` | Confirmar la matrícula con las validaciones locales superadas | HU-70 |
| `PENDING` | `IN_PROGRESS` | Player/Inventory concede el compromiso `MISSION` | HU-70 |
| `PENDING` | `REJECTED` | Player/Inventory rechaza de forma terminal (`422`) | HU-70 |
| `PENDING` | `EXPIRED` | Pasan 2 minutos sin confirmar; se libera el compromiso con el mismo `operationId` | HU-70 |
| `IN_PROGRESS` | `COMPLETED` o `FAILED` | Resultado de la simulación | HU-72 |
| `IN_PROGRESS` | `ABANDONED` | Cancelación con penalización | Sin HU en Sprint 2 (decisión 11) |

`REJECTED` y `EXPIRED` no ocupan al héroe. Los estados finales no cambian.

## Estado de la misión para el jugador

La definición de la misión no tiene estado propio. El estado que ve cada jugador (§7.8.7) se **deriva** en este orden:

1. `IN_PROGRESS` si el jugador tiene una matrícula activa en esa misión.
2. `LOCKED` si falta algún requisito previo; `lockReason` nombra las misiones que faltan.
3. `COMPLETED`, `FAILED` o `ABANDONED`, según su última matrícula terminada.
4. `AVAILABLE` en cualquier otro caso.

`canEnroll` vale `true` en los casos 3 y 4: una misión completada se puede repetir (§7.8.9, «Repetir misión»). `FAILED` y `ABANDONED` los producen HU-72 o la cancelación; HU-70 solo los reserva en el vocabulario.

## Modelo conceptual de datos

| Dato | Propietario | Dónde vive | Cómo lo referencia Missions |
| --- | --- | --- | --- |
| Definiciones de misión | Missions | `mission_definitions` | Propio |
| Matrículas y vencimiento | Missions | `mission_enrollments` | Propio |
| Clears por dificultad (requisitos previos) | Missions (HU-75) | `mission_difficulty_clears` | Propio |
| Jugador | Account / Cognito | Fuera de Missions | `sub` del JWT, opaco |
| Héroe y equipamiento | Player/Inventory | Fuera de Missions | `heroId` (UUID del héroe del jugador), opaco |
| Compromiso del héroe | Player/Inventory | Fuera de Missions | `commitmentId` y `operationId`, opacos |
| Rotaciones | Missions (HU-71) | La fija HU-71 | Se guardan con la matrícula tal como las valide HU-71 |

Esquema conceptual en PostgreSQL. Los nombres definitivos los fija HU-70.2:

```sql
CREATE TABLE mission_enrollments (
  enrollment_id    text PRIMARY KEY,
  player_id        text NOT NULL,
  mission_id       text NOT NULL REFERENCES mission_definitions (mission_id),
  hero_id          uuid NOT NULL,
  difficulty       text NOT NULL CHECK (difficulty IN ('NORMAL', 'HEROIC', 'LEGENDARY', 'MYTHIC')),
  status           text NOT NULL CHECK (status IN ('PENDING', 'IN_PROGRESS', 'COMPLETED', 'FAILED',
                                                   'ABANDONED', 'REJECTED', 'EXPIRED')),
  operation_id     text NOT NULL UNIQUE,
  idempotency_key  text NOT NULL,
  request_hash     text NOT NULL,
  commitment_id    text,
  strategy_version integer,
  rotations        jsonb,
  rejection_code   text,
  requested_at     timestamptz NOT NULL,
  started_at       timestamptz,
  ends_at          timestamptz,
  finished_at      timestamptz,
  version          integer NOT NULL DEFAULT 0,
  UNIQUE (player_id, idempotency_key),
  CHECK (status <> 'IN_PROGRESS'
         OR (started_at IS NOT NULL AND ends_at > started_at AND commitment_id IS NOT NULL))
);

-- Invariante de ADR-019 y de CA-02: un héroe no está en dos misiones activas.
CREATE UNIQUE INDEX ux_enrollment_active_hero
  ON mission_enrollments (hero_id) WHERE status IN ('PENDING', 'IN_PROGRESS');

-- Propuesta P-M2: una matrícula activa por jugador y misión.
CREATE UNIQUE INDEX ux_enrollment_active_player_mission
  ON mission_enrollments (player_id, mission_id) WHERE status IN ('PENDING', 'IN_PROGRESS');

-- Para el reconciliador de PENDING (HU-70) y el vencimiento (HU-72).
CREATE INDEX ix_enrollment_pending ON mission_enrollments (requested_at) WHERE status = 'PENDING';
CREATE INDEX ix_enrollment_due ON mission_enrollments (ends_at) WHERE status = 'IN_PROGRESS';
```

`mission_definitions` guarda cada definición con su contenido (enemigos, jefe, Máster y recompensas) como columnas `jsonb` versionadas. Cómo se carga el contenido queda abierto (decisión 7).

## Secuencia de matrícula e integración con Player/Inventory

Diagrama: [hu-70-sequence.puml](../diagrams/hu-70-sequence.puml). Sigue el patrón de reservas de ADR-019:

1. **Persistir la intención.** Missions inserta la matrícula `PENDING` con un `operationId` nuevo antes de llamar a nadie.
2. **Reservar en el dueño.** Missions pide el compromiso `MISSION` a Player/Inventory con ese `operationId`.
3. **Confirmar o compensar**, según la respuesta:

| Respuesta de Player/Inventory | Qué hace Missions | Qué recibe el jugador |
| --- | --- | --- |
| `201` compromiso concedido | `PENDING → IN_PROGRESS`, fija `startedAt` y `endsAt` y registra el hecho para HU-72 | `201` |
| `422 HERO_NOT_OWNED` | `PENDING → REJECTED` | `422 HERO_NOT_OWNED` |
| `422 HERO_NOT_READY` | `PENDING → REJECTED` | `422 HERO_NOT_READY` con los `blockers` recibidos |
| `422 LOADOUT_INCOMPLETE` | `PENDING → REJECTED` | `422 LOADOUT_INCOMPLETE` con las ranuras que faltan |
| `422 HERO_COMMITTED` | `PENDING → REJECTED` | `409 HERO_BUSY` con `busyWith` |
| `409`, `503` o sin respuesta | La deja `PENDING`; el reconciliador reintenta con el **mismo** `operationId` | `503 DEPENDENCY_UNAVAILABLE` |

4. **Caducidad.** El reconciliador (intervalo en proceso con `FOR UPDATE SKIP LOCKED`, el patrón de ADR-019) toma las matrículas `PENDING` y reintenta. Si pasan 2 minutos sin confirmación, libera el compromiso con el mismo `operationId` (liberar es idempotente) y marca `EXPIRED`. Si Missions cae por completo, el compromiso caduca solo en Player/Inventory.
5. **Liberación normal.** Al terminar la misión (HU-72) o al cancelarla, Missions libera el compromiso con el mismo `operationId`.

Un fallo entre la concesión y el `UPDATE` deja la matrícula `PENDING` con el compromiso ya concedido. El reintento con el mismo `operationId` devuelve el mismo compromiso, así que la matrícula termina `IN_PROGRESS` sin reservar dos veces.

## Contrato conceptual

Detalle en [hu-70-mission-enrollment-v1.md](../contracts/hu-70-mission-enrollment-v1.md) y en el [borrador OpenAPI](../contracts/hu-70-mission-enrollment-v1.openapi.yaml).

| Método | Ruta | Uso |
| --- | --- | --- |
| `GET` | `/api/v1/missions` | Tablón con el estado para el jugador (CU-70.1) |
| `GET` | `/api/v1/missions/{missionId}` | Detalle antes de confirmar (CA-06) |
| `POST` | `/api/v1/missions/{missionId}/enrollments` | Matricular (CA-01 a CA-05 y CA-07) |
| `POST` | `/api/internal/v1/inventory/heroes/{heroId}/commitments` | **Propuesta para Player/Inventory:** crear el compromiso `MISSION` |
| `POST` | `/api/internal/v1/inventory/commitments/{operationId}/release` | **Propuesta para Player/Inventory:** liberarlo |

Las dos rutas internas son una **propuesta** para Team Alfa, dueño de Player/Inventory. Hoy no existen.

## Separación con Jugar Online, Torneo y Combat

- HU-70 **no** simula, no calcula daño y no genera números aleatorios: eso es HU-72 y Combat.
- HU-70 **no** consulta a Combat ni a Torneo para saber si el héroe está ocupado: pregunta a Player/Inventory (P-M6).
- **CA-03 (torneo)** solo se cumple de punta a punta cuando Torneo registre compromisos `TOURNAMENT` en Player/Inventory. EPIC-09 sigue en Backlog, así que hoy no hay contrato.
- **CA-05 (JcJ y equipamiento)** lo imponen otros servicios. Player/Inventory debe rechazar cambios de equipamiento de un héroe comprometido (lo que HU-29 construye para batalla, ampliado a `MISSION`), y Combat debe pedir su compromiso `BATTLE` antes de usar al héroe. Hoy Combat no pide compromisos.
- Missions solo **mantiene** el compromiso mientras dura la matrícula y lo libera al terminar.

## Matriz RF → CA → escenario → salida esperada

Los escenarios con datos de ejemplo están en los [fixtures](../contracts/hu-70-mission-enrollment-fixtures-v1.json).

| RF | CA | Escenario | Salida esperada | Elemento de diseño |
| --- | --- | --- | --- | --- |
| RF-70 | CA-01 | P-01: misión disponible y héroe libre con mazo completo | `201`; matrícula `IN_PROGRESS`; compromiso `MISSION`; `endsAt = startedAt + duración` | CU-70.3, pasos 6 a 9 |
| RF-70 | CA-02 | P-02: el héroe tiene otra matrícula activa | `409 HERO_BUSY` (`busyWith: MISSION`); ninguna fila nueva; la misión sigue `AVAILABLE` | Índice único parcial por héroe |
| RF-70 | CA-03 | P-03: héroe en un torneo activo | `409 HERO_BUSY` (`busyWith: TOURNAMENT`) | Compromiso exclusivo en Player/Inventory (depende de Torneo) |
| RF-70 | CA-04 | P-04: mazo incompleto | `422 LOADOUT_INCOMPLETE` con las ranuras que faltan | P-M7, evaluado por Player/Inventory |
| RF-70 | CA-05 | P-05: con la matrícula en curso, intentar JcJ, torneo o cambiar el equipo | Rechazo en Combat, Torneo o Player/Inventory | Compromiso vigente hasta `endsAt` (externo) |
| RF-70 | CA-06 | P-06: consultar el detalle | `200` con todos los bloques de CA-06 | `GET /api/v1/missions/{missionId}` |
| RF-70 | CA-07 | P-07: un requisito previo sin completar | `422 MISSION_LOCKED` con `missingPrerequisites` | P-M10 |
| — | — | T-01: reintento con la misma `Idempotency-Key` | La misma `201` con la misma matrícula | P-M3 |
| — | — | T-02: dos confirmaciones simultáneas con el mismo héroe | Una `201`; la otra `409 HERO_BUSY` | Índice único parcial |
| — | — | T-03: Player/Inventory no responde | `503`; matrícula `PENDING`; el reconciliador la confirma o la marca `EXPIRED` | P-M8 |
| — | — | T-04: misión bloqueada y héroe ocupado a la vez | `422 MISSION_LOCKED` (gana la misión) | P-M4 |

## Impacto arquitectónico

| Componente | Cambio | Responsable |
| --- | --- | --- |
| Missions | Tablas `mission_definitions` y `mission_enrollments` con sus índices; `EnrollmentPolicy`; casos de uso de tablón, detalle y matrícula; reconciliador de `PENDING` | Team Beta (HU-70.2) |
| Web | Tablón, detalle y confirmación en `src/features/missions/`, con una `Idempotency-Key` generada al pulsar «Iniciar misión» | Team Beta (HU-70.3) |
| Player/Inventory | Compromisos del héroe (crear, liberar y caducar), `MISSION` incluido, y rechazo de cambios de equipamiento con compromiso vigente | Team Alfa (ADR-019 y HU-29) |
| Combat y Torneo | Pedir su compromiso antes de usar al héroe | Team Alfa y el dueño de EPIC-09 |
| AWS e infraestructura | Ninguno: sin servicios ni colas nuevas | — |

## Decisiones pendientes (visibles, no resueltas)

1. **Qué es «mazo completo».** Propuesta P-M7 (2/6/2). Alternativas: al menos un arma, o solo *readiness*. Decide el PO.
2. **Qué nivel se exige.** No existe nivel de héroe en Player/Inventory y el nivel de jugador (HU-08 y HU-09) aún no está. Propuesta P-M11: informativo.
3. **¿Una matrícula activa por jugador y misión?** Propuesta P-M2.
4. **¿Las rotaciones son obligatorias para confirmar?** [HU-71](hu-71-rotaciones-habilidades.md) propone que no (P-R9): sin estrategia, la IA solo usa el ataque básico (§7.8.5).
5. **Cómo se libera una reserva fallida.** Propuesta P-M8: 2 minutos para `PENDING` y caducidad del compromiso con 30 minutos de margen.
6. **Qué respuesta distingue héroe ocupado de misión bloqueada.** Propuestas P-M4 y P-M5.
7. **Contenido de las misiones.** El curso (§7.8.4) pide dos misiones completas por equipo y no hay issue. Sin definiciones, el tablón sale vacío.
8. **Torneo.** CA-03 no se puede verificar de punta a punta hasta que Torneo registre compromisos.
9. **Combat.** CA-05 (JcJ) exige que Combat pida su compromiso antes de una batalla.
10. **Filtro por dificultad del tablón.** El curso usa Fácil, Normal, Difícil y Extremo en el filtro (§7.8.9) y Normal, Heroico, Legendario y Mítico en la progresión (§7.8.11). La misma pregunta está abierta en HU-75.
11. **Cancelar con penalización** (§7.8.7, «Abandonada»). Ninguna HU de Sprint 2 lo cubre.
12. **Probabilidad del Máster del ejemplo del curso.** El texto dice «0.15% (15% de probabilidad)». Los fixtures usan la fracción `0.15`, pendiente de confirmar.
