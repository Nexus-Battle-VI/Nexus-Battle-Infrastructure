# HU-76 — Diseño del sistema de logros y reconocimientos de misiones

**Estado:** diseño. **No implementado.** Missions no tiene rutas de negocio en `develop`. Ningún logro de este documento está otorgado en producción: el catálogo y los datos son de ejemplo.

## Trazabilidad

| Elemento | Referencia |
| --- | --- |
| Historia | [HU-76 #61](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/61) — Sistema de logros y reconocimientos (`RF-76`) |
| Épica | [EPIC-08 #8](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/8) — Misiones |
| Task de diseño | [HU-76.1 #387](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/387) |
| Tasks que usan este diseño | [HU-76.2 #388](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/388) implementación, [HU-76.3 #389](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/389) perfil en Web y [HU-76.4 #390](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/390) pruebas |
| Contrato | [hu-76-mission-achievements-v1.md](../contracts/hu-76-mission-achievements-v1.md) y [fixtures](../contracts/hu-76-mission-achievements-fixtures-v1.json) |
| Diagramas | [casos de uso](../diagrams/hu-76-use-case.puml), [actividad](../diagrams/hu-76-activity.puml), [secuencia](../diagrams/hu-76-sequence.puml) y [dominio](../diagrams/hu-76-domain.puml) |
| Fuente funcional | Documento del curso, §7.8.11 (logros y reconocimientos) |
| Diseños de los que parte | [HU-72](hu-72-simulacion-mision.md) (`MissionSettled`), [HU-73](hu-73-encuentro-master.md) (Máster y épicas) y [HU-74](hu-74-reporte-mision.md) (reporte) |

## Vista rápida (para revisión)

| Pregunta | Respuesta del diseño |
| --- | --- |
| ¿De dónde salen los datos? | De un hecho normalizado `MissionFinishedForAchievements`, armado al cerrar cada misión con lo que ya guardaron HU-72, HU-73 y HU-74. |
| ¿Quién decide si se cumple un logro? | Missions, en un evaluador aparte del cierre. Web solo consulta. |
| ¿Cómo se evita otorgar dos veces? | `UNIQUE (playerId, achievementId)` y un registro de hechos ya procesados por jugador y matrícula. |
| ¿Qué se entrega? | Un título o una insignia que Missions registra y el perfil muestra; los cosméticos que sean productos van por el contrato de entregas de Player/Inventory. |

## Decisiones funcionales literales (HU publicada)

1. Se rastrean logros de misiones.
2. Criterios previstos: completar todas las misiones de una categoría (Historia, Desafío o Exploración), derrotar a todos los Máster disponibles, completar una misión sin recibir daño, lograr tiempos récord y coleccionar todas las épicas de Máster.
3. Al cumplirse un logro se entrega su título, insignia o recompensa cosmética (CA-01, CA-02).
4. Un logro solo se otorga cuando su criterio está cumplido y es verificable (CA-03).
5. Los criterios se evalúan con los eventos de progreso; al terminar cada misión se actualiza el progreso.

## Criterios técnicos propuestos (no aprobados por el PO)

| Id | Propuesta | Por qué |
| --- | --- | --- |
| P-L1 | Catálogo versionado de logros: `achievementId` estable, categoría, tipo de criterio, parámetros, umbral y reconocimiento. | Lo pide la guía del PO. Permite añadir logros sin tocar el evaluador. |
| P-L2 | Hecho normalizado por misión terminada con lo mínimo de cada criterio: resultado, categoría, dificultad, daño recibido, duración simulada, Máster derrotados y épicas obtenidas. | Separa los logros de la forma interna del reporte. |
| P-L3 | El progreso de los criterios de «todas» se guarda como **conjuntos** (misiones completadas, Máster derrotados, épicas obtenidas). | Añadir un elemento que ya está no cambia nada: la idempotencia sale gratis. |
| P-L4 | El evaluador corre **después** del cierre, leyendo los hechos `MissionSettled` pendientes con `FOR UPDATE SKIP LOCKED`, y marca cada hecho procesado. | Un fallo en los logros no puede bloquear el cierre de una misión. |
| P-L5 | Un logro desbloqueado no se revoca, aunque luego se añadan misiones o Máster al catálogo. | Evita quitar reconocimientos ya mostrados. |
| P-L6 | «Disponibles» = Máster de las definiciones de misión **activas** en el momento de evaluar. | La HU no lo define (decisión 2). |
| P-L7 | «Tiempo récord» = completar una misión con duración simulada igual o menor que el umbral del logro, fijado por misión en el catálogo. | Un récord contra otros jugadores sería inestable y exigiría datos de todos (decisión 3). |
| P-L8 | «Sin recibir daño» = misión `COMPLETED` con `damageTaken = 0`. | Literal del curso; una misión fallida no cuenta. |
| P-L9 | Títulos e insignias se registran en Missions y el perfil los muestra por su API. Un cosmético que sea producto se entrega por `POST /api/internal/v1/inventory/grants` con `operationId` determinista por jugador y logro. | No hay contrato de perfil para reconocimientos (decisión 4). |

## Caso de uso textual

### CU-76.1 Evaluar logros al terminar una misión (sistema)

1. El evaluador toma un hecho `MissionSettled` no procesado.
2. Si el par (jugador, matrícula) ya fue procesado, lo marca y termina: idempotencia.
3. Arma el hecho normalizado (P-L2) y actualiza el progreso de cada logro del catálogo.
4. Evalúa los criterios. Para cada logro cumplido, inserta el desbloqueo (`UNIQUE` por jugador y logro) y registra el reconocimiento.
5. Si el reconocimiento es un producto, pide la entrega a Player/Inventory.
6. Marca el hecho como procesado, en la misma transacción que el progreso y los desbloqueos.

### CU-76.2 Consultar logros (jugador, CA-01)

`GET /api/v1/missions/me/achievements` devuelve cada logro del catálogo con su estado: `LOCKED`, `IN_PROGRESS` (con `current` y `target`) o `UNLOCKED` (con fecha y reconocimiento).

## Tabla de decisión por criterio

| Id | Criterio | Datos | ¿Se otorga? |
| --- | --- | --- | --- |
| L-1 | Sin recibir daño | Misión `COMPLETED` con `damageTaken = 0` | Sí (CA-02) |
| L-2 | Sin recibir daño | Misión `COMPLETED` con `damageTaken = 1` | No |
| L-3 | Sin recibir daño | Misión `FAILED` con `damageTaken = 0` | No |
| L-4 | Tiempo récord | Duración simulada ≤ umbral | Sí |
| L-5 | Todos los Máster | Derrotados 1 de 2 disponibles | No; progreso 1/2 (CA-03) |
| L-6 | Todos los Máster | Derrotados 2 de 2 | Sí |
| L-7 | Colección de épicas | Épicas acreditadas 2 de 2 | Sí |
| L-8 | Todas las misiones de Historia | 2 de 3 completadas | No; progreso 2/3 (CA-03) |
| L-9 | Cualquiera | El mismo hecho reprocesado | Sin cambios: ni progreso extra ni segunda entrega |

## Fragmento de dominio

Diagrama: [hu-76-domain.puml](../diagrams/hu-76-domain.puml).

- **`AchievementDefinition`** (catálogo): `achievementId`, versión, categoría, `criterion`, parámetros, umbral y reconocimiento.
- **`AchievementProgress`** (agregado por jugador y logro): conjunto de elementos o contador, estado, `unlockedAt` y versión.
- **`AchievementEvaluator`** (dominio puro): aplica un hecho normalizado al progreso y dice qué logros se cumplen.
- **`Recognition`**: `TITLE`, `BADGE` o `COSMETIC_PRODUCT`.
- **Puertos:** `AchievementCatalog`, `ProgressRepository`, `ProcessedFactsRepository` y `RecognitionGrantPort` (Player/Inventory).

## Modelo conceptual de datos

```sql
CREATE TABLE achievement_definitions (
  achievement_id  text NOT NULL,
  version         integer NOT NULL,
  criterion       text NOT NULL CHECK (criterion IN ('ALL_CATEGORY_MISSIONS', 'ALL_MASTERS_DEFEATED', 'FLAWLESS_MISSION',
                                                     'RECORD_TIME', 'ALL_MASTER_EPICS')),
  params          jsonb NOT NULL,
  recognition     jsonb NOT NULL,
  active          boolean NOT NULL,
  PRIMARY KEY (achievement_id, version)
);

CREATE TABLE achievement_progress (
  player_id       text NOT NULL,
  achievement_id  text NOT NULL,
  progress        jsonb NOT NULL,
  status          text NOT NULL CHECK (status IN ('LOCKED', 'IN_PROGRESS', 'UNLOCKED')),
  unlocked_at     timestamptz,
  version         integer NOT NULL DEFAULT 0,
  PRIMARY KEY (player_id, achievement_id),
  CHECK ((status = 'UNLOCKED') = (unlocked_at IS NOT NULL))
);

CREATE TABLE achievement_processed_facts (
  player_id      text NOT NULL,
  enrollment_id  text NOT NULL,
  processed_at   timestamptz NOT NULL,
  PRIMARY KEY (player_id, enrollment_id)
);

CREATE TABLE achievement_recognition_grants (
  player_id        text NOT NULL,
  achievement_id   text NOT NULL,
  kind             text NOT NULL CHECK (kind IN ('TITLE', 'BADGE', 'COSMETIC_PRODUCT')),
  operation_id     uuid UNIQUE,
  status           text NOT NULL CHECK (status IN ('RECORDED', 'PENDING', 'CREDITED', 'FAILED')),
  PRIMARY KEY (player_id, achievement_id)
);
```

- `PRIMARY KEY (player_id, achievement_id)` en progreso y reconocimientos: un logro se otorga como mucho una vez (CA-02 sin duplicados).
- `achievement_processed_facts`: el mismo hecho no suma dos veces (L-9).
- Títulos e insignias quedan `RECORDED` en Missions; los cosméticos que son productos pasan por `PENDING` y `CREDITED`.

## Matriz CA → escenario → salida esperada

Escenarios con datos en los [fixtures](../contracts/hu-76-mission-achievements-fixtures-v1.json).

| RF | CA | Escenario | Salida esperada | Elemento de diseño |
| --- | --- | --- | --- | --- |
| RF-76 | CA-01 | L-1: misión sin daño | Logro `UNLOCKED` visible en `GET /me/achievements` con su título | CU-76.1 y CU-76.2 |
| RF-76 | CA-02 | L-4, L-6 y L-7 | Logro registrado y reconocimiento entregado | Tabla de decisión |
| RF-76 | CA-03 | L-2, L-3, L-5 y L-8 | Sin logro; progreso parcial visible | Tabla de decisión |
| — | — | L-9 | Sin cambios al reprocesar | P-L3 y P-L4 |

## Impacto arquitectónico

| Componente | Cambio | Responsable |
| --- | --- | --- |
| Missions | Catálogo, progreso, evaluador después del cierre y `GET /api/v1/missions/me/achievements` | Team Beta (HU-76.2) |
| Web | Sección de logros de Misiones en el perfil, solo lectura | Team Beta (HU-76.3) |
| Player/Inventory | Entregar cosméticos que sean productos (contrato de HU-59, abierto a `missions` por ADR-019) | Team Alfa |
| Account (perfil) | Mostrar títulos e insignias si el perfil vive allí | A coordinar (decisión 4) |

## Decisiones pendientes (visibles, no resueltas)

1. **Catálogo definitivo** de logros, sus nombres y sus reconocimientos. El del contrato es de ejemplo.
2. **Qué son los Máster «disponibles».** Propuesta P-L6.
3. **Qué es un «tiempo récord».** Propuesta P-L7, con un umbral por misión que fija el PO.
4. **Dónde viven títulos e insignias**: en Missions (propuesta P-L9) o en el perfil de Account.
5. **¿Una misión `ABANDONED` o `VOIDED` cuenta para algo?** Propuesta: no cuenta para ningún criterio.
6. **Colección de épicas:** ¿cuenta la épica ganada o solo la ya acreditada? Propuesta: solo la acreditada (`CREDITED`), porque es la que el jugador tiene.
