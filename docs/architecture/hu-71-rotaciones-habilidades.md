# HU-71 — Diseño de la configuración de rotaciones de habilidades

**Estado:** diseño. **No implementado.** Missions no tiene rutas de negocio en `develop` y Combat no aplica rotaciones. Nada de este documento autoriza a marcar rutas como disponibles en [service-catalog.md](../contracts/service-catalog.md).

## Trazabilidad

| Elemento | Referencia |
| --- | --- |
| Historia | [HU-71 #56](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/56) — Configuración de rotaciones de habilidades (`RF-71`) |
| Épica | [EPIC-08 #8](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/8) — Misiones |
| Task de diseño | [HU-71.1 #369](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/369) |
| Tasks que usan este diseño | [HU-71.2 #370](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/370) implementación, [HU-71.3 #371](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/371) editor y [HU-71.4 #372](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/372) pruebas |
| Decisión de arquitectura | [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md): Missions posee las rotaciones; Combat ejecuta las reglas |
| Contrato | [hu-71-mission-strategy-v1.md](../contracts/hu-71-mission-strategy-v1.md) y [fixtures](../contracts/hu-71-mission-strategy-fixtures-v1.json) |
| Diagramas | [casos de uso](../diagrams/hu-71-use-case.puml), [decisión por turno](../diagrams/hu-71-turn-decision.puml), [secuencia](../diagrams/hu-71-sequence.puml) y [dominio](../diagrams/hu-71-domain.puml) |
| Fuente funcional | Documento del curso, §7.8.5 (rotaciones y lógica de decisión) y §7.8.12 (configuraciones guardadas) |
| Diseños de los que parte | [HU-70](hu-70-matriculacion-mision.md) (la matrícula congela la estrategia) y [HU-72](hu-72-simulacion-mision.md) (bloque `strategy` de la simulación) |
| Reglas de Combat que se reutilizan | Poder (HU-11), habilidades y recarga (HU-19) y ataque básico (HU-18), tal como las publica Combat |

## Vista rápida (para revisión)

| Pregunta | Respuesta del diseño |
| --- | --- |
| ¿Qué guarda Missions? | Hasta tres rotaciones por jugador, héroe y misión, cada una con su prioridad (`HIGH`, `MEDIUM` o `LOW`) y una secuencia de acciones. |
| ¿Quién decide si una rotación es viable? | Combat, en cada turno de la simulación: Poder suficiente, recarga cumplida y estado de salud del héroe. |
| ¿Qué pasa si ninguna es viable? | La IA ejecuta el ataque básico sin consumir Poder (CA-03). Es un resultado del contrato, no un error. |
| ¿Cómo se evita que dos ediciones se pisen? | Versión optimista: cada guardado indica la versión que leyó (`expectedVersion`). |
| ¿Qué usa la simulación? | Una **copia congelada** que la matrícula toma al confirmar. Editar después no cambia una misión en curso. |

## Decisiones funcionales literales (HU publicada)

1. Hasta tres rotaciones; no se puede configurar una cuarta (CA-04).
2. Cada rotación es una secuencia ordenada de habilidades y/o ataque básico. El ejemplo del producto usa tres acciones por rotación.
3. Rotación 1 = prioridad alta; Rotación 2 = media; Rotación 3 = baja.
4. En cada turno se evalúa primero la de mayor prioridad y, si no es viable, la siguiente (CA-02).
5. La viabilidad considera Poder suficiente, recarga cumplida y estado de salud del héroe.
6. Si ninguna es viable, ataque básico sin consumir Poder (CA-03).
7. La configuración queda guardada y se aplica en la simulación (CA-01).

## Criterios técnicos propuestos (no aprobados por el PO)

| Id | Propuesta | Por qué |
| --- | --- | --- |
| P-R1 | La estrategia se guarda por **jugador, héroe y misión** y la matrícula la **congela** al confirmar. | La guía del PO la asocia a jugador, héroe, misión y matrícula. Congelarla hace que la simulación de HU-72 use exactamente lo que el jugador vio. |
| P-R2 | Las prioridades van sin huecos: con una rotación, `HIGH`; con dos, `HIGH` y `MEDIUM`; con tres, las tres. | «Rotación 1, 2 y 3» son posiciones, no etiquetas libres. |
| P-R3 | Cada rotación tiene entre 1 y 3 acciones. | Coincide con el ejemplo de referencia; más acciones las decide el PO (decisión 2). |
| P-R4 | Cada acción es `ABILITY` con un `abilityId` que el héroe tenga, o `BASIC_ATTACK`. Missions valida las referencias al guardar, contra las habilidades que publica Player/Inventory. | Evita que la simulación falle con `422` por una referencia inválida, lo que la anularía (HU-72). |
| P-R5 | Una acción `BASIC_ATTACK` siempre es viable. | Cuesta 0 Poder y no tiene recarga (HU-18 y HU-11). |
| P-R6 | Cada rotación tiene su propio cursor: avanza cuando se ejecuta uno de sus pasos y vuelve al inicio tras el último. Una rotación no viable no avanza. | La HU habla de «secuencias» y no define qué pasa entre turnos (decisión 3). |
| P-R7 | La bitácora de la simulación anota en cada acción del héroe qué rotación y qué paso se usaron, y por qué se saltaron las de mayor prioridad. | Permite comprobar CA-02 y CA-03 con la bitácora, sin acceder a Combat. |
| P-R8 | La matrícula de HU-70 recibe `strategyVersion` en lugar de `rotations`. Si no coincide con la versión guardada: `409 STRATEGY_VERSION_MISMATCH`. | El jugador confirma con la estrategia que tiene delante; si otra pestaña la cambió, se entera. |
| P-R9 | Sin estrategia guardada, la matrícula sigue adelante con estrategia vacía: la IA solo usará el ataque básico. Web avisa antes de confirmar. | Evita bloquear la misión; la HU no la declara obligatoria (decisión 4). |

## Caso de uso textual

### CU-71.1 Guardar la estrategia (CA-01, CA-04)

- **Actor:** jugador autenticado (rol `PLAYER`).
- **Precondiciones:** la misión existe; el héroe es del jugador.
- **Entradas:** `missionId`, `heroId`, `expectedVersion` (`null` si es la primera vez) y las rotaciones.
- **Flujo principal:**
  1. Missions valida la forma: entre 1 y 3 rotaciones, prioridades sin huecos ni repetidas y entre 1 y 3 acciones por rotación.
  2. Pide a Player/Inventory las habilidades del héroe y comprueba cada `abilityId`.
  3. Guarda la estrategia con la versión siguiente, solo si la versión actual coincide con `expectedVersion`.
  4. Responde con la estrategia y su versión nueva.
- **Excepciones:** cuarta rotación → `422 TOO_MANY_ROTATIONS` (CA-04); forma no válida → `422 INVALID_ROTATION`; habilidad que el héroe no tiene → `422 UNKNOWN_ABILITY`; héroe ajeno → `422 HERO_NOT_OWNED`; versión distinta → `409 VERSION_CONFLICT`; Player/Inventory no responde → `503`.

### CU-71.2 Consultar la estrategia

Devuelve la estrategia guardada con su versión, o `404 STRATEGY_NOT_FOUND`.

### CU-71.3 Congelar la estrategia al matricular

En el paso de validación de HU-70, Missions compara `strategyVersion` con la versión guardada y copia las rotaciones en la matrícula. La simulación (HU-72) usa esa copia.

### CU-71.4 Aplicar la estrategia en cada turno (lo ejecuta Combat)

Ver [decisión por turno](#decisión-por-turno). Missions no participa: solo envió la estrategia congelada en el bloque `strategy` de la solicitud de simulación.

## Decisión por turno

Diagrama: [hu-71-turn-decision.puml](../diagrams/hu-71-turn-decision.puml). La ejecuta Combat en la simulación:

1. Para cada rotación en orden de prioridad, tomar la acción que marca su cursor.
2. La rotación es viable si esa acción es `BASIC_ATTACK`, o si es `ABILITY` y el héroe tiene Poder para su costo, la recarga está en 0 y cumple la condición de salud (decisión 5). Se comprueba en ese orden de causa: recarga (`ON_COOLDOWN`), Poder (`NOT_ENOUGH_POWER`) y salud (`HEALTH_CONDITION`); la bitácora anota la primera que falla.
3. Ejecutar la acción de la primera rotación viable y avanzar **solo** su cursor.
4. Si ninguna es viable, ejecutar el ataque básico sin consumir Poder (CA-03).

| Caso | Rotación 1 | Rotación 2 | Rotación 3 | Acción | Poder consumido |
| --- | --- | --- | --- | --- | --- |
| D-1: alta viable | Viable | — | — | Acción actual de la 1 | Costo de la acción |
| D-2: alta no viable, media viable | Sin Poder | Viable | — | Acción actual de la 2 | Costo de la acción |
| D-3: solo baja viable | En recarga | Sin Poder | Viable | Acción actual de la 3 | Costo de la acción |
| D-4: ninguna viable (CA-03) | Sin Poder | Sin Poder | En recarga | Ataque básico de respaldo | 0 |
| D-5: la acción actual de la 1 es `BASIC_ATTACK` | Viable | — | — | Ataque básico de la rotación 1 | 0 |
| D-6: solo hay una rotación y no es viable | Sin Poder | No existe | No existe | Ataque básico de respaldo | 0 |
| D-7: cuarta rotación al guardar (CA-04) | — | — | — | `422 TOO_MANY_ROTATIONS` | — |

Cuando una habilidad se ejecuta con Poder insuficiente en una batalla, Combat la **degrada** a ataque básico (HU-19). En la simulación no hace falta: la regla de viabilidad salta antes a la siguiente rotación.

## Fragmento de dominio

Diagrama: [hu-71-domain.puml](../diagrams/hu-71-domain.puml).

- **`RotationStrategy`** (agregado de Missions): jugador, héroe, misión, versión y hasta tres `Rotation`.
- **`Rotation`**: prioridad (`HIGH`, `MEDIUM` o `LOW`) y entre 1 y 3 `RotationStep`.
- **`RotationStep`**: `ABILITY` con `abilityId`, o `BASIC_ATTACK`.
- **`StrategyPolicy`** (dominio puro): valida límites, prioridades y referencias contra las habilidades del héroe.
- **Puertos:** `StrategyRepository` y `HeroAbilitiesPort` (Player/Inventory). La ejecución vive detrás del `CombatSimulationPort` de HU-72.

Missions **no** copia clases ni DTO de Combat: el límite es el bloque `strategy` del contrato de simulación.

## Modelo conceptual de datos

| Dato | Propietario | Dónde vive |
| --- | --- | --- |
| Estrategia guardada | Missions | `mission_strategies` |
| Copia congelada en la matrícula | Missions | `mission_enrollments.rotations` y `strategy_version` (HU-70) |
| Habilidades del héroe | Player/Inventory | Fuera de Missions; se consultan al guardar |
| Poder, recarga y salud en cada turno | Combat | Estado de la simulación |

```sql
CREATE TABLE mission_strategies (
  player_id   text NOT NULL,
  hero_id     uuid NOT NULL,
  mission_id  text NOT NULL REFERENCES mission_definitions (mission_id),
  rotations   jsonb NOT NULL,
  version     integer NOT NULL CHECK (version >= 1),
  updated_at  timestamptz NOT NULL,
  PRIMARY KEY (player_id, hero_id, mission_id),
  CHECK (jsonb_typeof(rotations) = 'array' AND jsonb_array_length(rotations) BETWEEN 1 AND 3)
);

-- HU-70 añade a mission_enrollments:
--   strategy_version integer  (NULL si se matriculó sin estrategia; P-R9)
```

El guardado usa `UPDATE ... WHERE version = :expectedVersion` (o `INSERT` si `expectedVersion` es `null`). Cero filas afectadas significa `409 VERSION_CONFLICT`.

## Secuencia

Diagrama: [hu-71-sequence.puml](../diagrams/hu-71-sequence.puml): Web guarda la estrategia, Missions valida contra Player/Inventory, la matrícula de HU-70 la congela y la simulación de HU-72 la envía a Combat.

## Cambios en los contratos de HU-70 y HU-72

| Contrato | Cambio |
| --- | --- |
| [HU-70](../contracts/hu-70-mission-enrollment-v1.md) | El cuerpo de la matrícula lleva `strategyVersion` en lugar de `rotations`, con el error `409 STRATEGY_VERSION_MISMATCH` (P-R8) |
| [HU-72](../contracts/hu-72-mission-simulation-v1.md) | El bloque `strategy` usa la forma de este diseño: prioridades `HIGH`, `MEDIUM` y `LOW` y acciones con `kind` |

## Matriz RF → CA → escenario → salida esperada

Escenarios con datos de ejemplo en los [fixtures](../contracts/hu-71-mission-strategy-fixtures-v1.json).

| RF | CA | Escenario | Salida esperada | Elemento de diseño |
| --- | --- | --- | --- | --- |
| RF-71 | CA-01 | P-01: guardar las tres rotaciones del ejemplo del curso | `201` con versión 1; la matrícula la congela; la simulación la recibe | CU-71.1, CU-71.3 |
| RF-71 | CA-02 | P-02: la rotación 1 no es viable en un turno | La bitácora muestra una acción de la rotación 2, o de la 3 si la 2 tampoco es viable | D-2, D-3 (Combat) |
| RF-71 | CA-03 | P-03: ninguna rotación es viable | Ataque básico de respaldo, sin consumir Poder | D-4 (Combat) |
| RF-71 | CA-04 | P-04: guardar cuatro rotaciones | `422 TOO_MANY_ROTATIONS`; no cambia nada | CU-71.1 |
| — | — | T-01: dos ediciones con la misma versión leída | Una `200`; la otra `409 VERSION_CONFLICT` | Versión optimista |
| — | — | T-02: una acción con una habilidad que el héroe no tiene | `422 UNKNOWN_ABILITY` con la referencia | P-R4 |
| — | — | T-03: prioridades con hueco (`HIGH` y `LOW`) | `422 INVALID_ROTATION` | P-R2 |
| — | — | T-04: matricular con una versión vieja | `409 STRATEGY_VERSION_MISMATCH` | P-R8 |

## Impacto arquitectónico

| Componente | Cambio | Responsable |
| --- | --- | --- |
| Missions | `mission_strategies`, `StrategyPolicy`, rutas para consultar y guardar la estrategia; congelado en la matrícula | Team Beta (HU-71.2) |
| Web | Editor de rotaciones en el detalle de la misión, con las habilidades reales del héroe | Team Beta (HU-71.3) |
| Player/Inventory | Habilidades del héroe por `heroId` para validar al guardar (la misma necesidad que la decisión 10 de HU-72) | Team Alfa |
| Combat | Decisión por turno con cursores por rotación y anotación en la bitácora | Team Alfa |

La ruta prevista en `Nexus-Battle-Missions/docs/architecture.md` (`PUT /api/v1/missions/enrollments/{enrollmentId}/rotations`) se sustituye por la estrategia guardada por misión y héroe: con la simulación al inicio de la misión (HU-72), editar rotaciones de una matrícula en curso ya no tendría efecto.

## Decisiones pendientes (visibles, no resueltas)

1. **Alcance de la estrategia guardada:** por jugador, héroe y misión (P-R1) o reutilizable entre misiones del mismo héroe (el curso habla de «configuraciones guardadas»).
2. **Cuántas acciones admite una rotación.** Propuesta P-R3: entre 1 y 3.
3. **Qué pasa con el cursor entre turnos.** Propuesta P-R6: cada rotación avanza el suyo y vuelve al inicio.
4. **¿Es obligatoria la estrategia para matricular?** Propuesta P-R9: no.
5. **Qué es el «estado de salud del héroe»** en la viabilidad. La HU lo nombra sin regla. Lo tiene que fijar el PO y aplicarlo Combat.
6. **¿Se admite la habilidad épica en una rotación?** La épica aún no está implementada en Combat (HU-31) y su recarga es de 2 turnos.
7. **Habilidades por `heroId`.** Hoy Player/Inventory solo publica las habilidades del héroe **seleccionado** (`equipped-hero`); Missions necesita las de un héroe concreto.
