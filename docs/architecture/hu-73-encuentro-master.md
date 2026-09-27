# HU-73 — Diseño del encuentro aleatorio con enemigo Máster

**Estado:** diseño. **No implementado.** Combat no evalúa apariciones de Máster y Player/Inventory no acredita épicas de Máster (HU-32 sigue en Backlog). Nada de este documento autoriza a marcar capacidades como disponibles en [service-catalog.md](../contracts/service-catalog.md).

## Trazabilidad

| Elemento | Referencia |
| --- | --- |
| Historia | [HU-73 #58](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/58) — Encuentro aleatorio con enemigo Máster (`RF-73`) |
| Épica | [EPIC-08 #8](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/8) — Misiones |
| Task de diseño | [HU-73.1 #376](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/376) |
| Tasks que usan este diseño | [HU-73.2 #377](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/377) implementación y [HU-73.3 #378](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/378) pruebas |
| HU de frontera | [HU-32 #79](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/79): acreditar la épica en el inventario |
| Decisiones de arquitectura | [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md) (entregas al inventario con el contrato idempotente de HU-59, abiertas a `missions`) y [ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md) (aleatoriedad solo en Combat) |
| Contrato | [hu-73-master-encounter-v1.md](../contracts/hu-73-master-encounter-v1.md) y [fixtures](../contracts/hu-73-master-encounter-fixtures-v1.json) |
| Diagramas | [casos de uso](../diagrams/hu-73-use-case.puml), [actividad](../diagrams/hu-73-activity.puml), [secuencia](../diagrams/hu-73-sequence.puml) y [dominio](../diagrams/hu-73-domain.puml) |
| Fuente funcional | Documento del curso: §6.1.2 (épicas y Tabla 20), §7.8.3, §7.8.4 y el ejemplo de §7.8.14 |
| Diseños de los que parte | [HU-72](hu-72-simulacion-mision.md): bloque `master` de la simulación, resumen y cierre |

## Vista rápida (para revisión)

| Pregunta | Respuesta del diseño |
| --- | --- |
| ¿Quién decide si aparece el Máster? | Combat, con su generador, en los puntos de evaluación que fija la misión. Missions no tira dados. |
| ¿Qué guarda Missions? | La configuración del Máster en la definición de la misión y, por cada matrícula, cada evaluación y cada encuentro como evidencia. |
| ¿Cuándo se entrega la épica? | Al cerrar la misión (HU-72), solo si Combat registró la derrota del Máster, una sola vez y por el contrato de entregas de Player/Inventory. |
| ¿Qué no se inventa? | La fórmula de «estadísticas superiores» ni el «nivel» del héroe: solo está aprobado el desfase de dos niveles. |

## Decisiones funcionales literales

De HU-73 y del curso, sin reinterpretar:

1. La aparición se evalúa con la probabilidad configurada para el tipo de héroe del jugador (CA-02).
2. La evaluación usa el motor centralizado de aleatoriedad.
3. El Máster aparece dos niveles por encima del héroe y con estadísticas superiores (CA-04).
4. En misiones largas pueden aparecer varios Máster.
5. Si el héroe derrota al Máster, el jugador recibe su habilidad épica única (CA-01). Si no aparece, o aparece y no lo derrota, no la recibe (CA-03).
6. La épica sigue el formato de la Tabla 20: un efecto para todos los héroes y un efecto potenciado solo para su tipo de héroe. No usa Poder y tiene dos turnos de recarga.
7. Las épicas de Máster solo se obtienen con este mecanismo del modo Misión (HU-32).
8. La aparición, la no aparición y el resultado del encuentro quedan registrados para el reporte (CA-02).

## Criterios técnicos propuestos (no aprobados por el PO)

| Id | Propuesta | Por qué |
| --- | --- | --- |
| P-X1 | `MasterEncounterConfig` en la definición de la misión: referencia y nombre del Máster, su subtipo, la épica, la probabilidad por tipo de héroe, el desfase de nivel, los puntos de evaluación y el tope de apariciones. | La guía del PO pide separar configuración, decisión aleatoria, combate y acreditación. |
| P-X2 | Missions resuelve la probabilidad para el subtipo del héroe matriculado y envía a Combat solo esa. Sin probabilidad para ese subtipo, no se evalúa y se registra `NOT_APPLICABLE`. | La HU liga la probabilidad al tipo de héroe del jugador. |
| P-X3 | Cada punto de evaluación es una oportunidad: Combat tira una vez por candidato, en orden, y aparece como mucho un Máster por punto. El tope `maxAppearances` limita el total (1 por defecto). | Varias oportunidades no implican varias apariciones: la regla queda explícita. |
| P-X4 | La aparición se evalúa **después** del encuentro indicado. El Máster es un encuentro adicional con las mismas reglas de combate: si cae el héroe, la misión falla (regla de HU-72); si cae el Máster, la épica se gana. | Reutiliza la simulación sin reglas nuevas. |
| P-X5 | Validaciones de la configuración: probabilidades en `[0, 1]`, referencias obligatorias, puntos dentro del número de encuentros y tope ≥ 1. | Que un error de contenido no llegue a Combat y anule la misión. |
| P-X6 | La épica se acredita **al cerrar** la misión, con `POST /api/internal/v1/inventory/grants` (contrato idempotente de HU-59) y un `operationId` determinista por matrícula, Máster y aparición. Nunca en una misión `VOIDED`. | La guía del PO pide que repetir un resultado no entregue dos veces la épica. |
| P-X7 | Missions guarda cada evaluación y cada encuentro en `mission_master_encounters`. | Evidencia verificable para HU-32 (acreditación) y HU-74 (reporte). |
| P-X8 | Missions envía `levelOffset: 2` y el perfil base del Máster; la conversión del desfase en estadísticas la decide el PO y la aplica Combat. | La guía del PO: no inventar multiplicadores. |

## Caso de uso textual

### CU-73.1 Configurar el Máster de una misión (contenido)

Quien carga el contenido define `masterEncounter` en la definición. Missions valida P-X5 al cargarla. El curso pide al menos un Máster por misión en las dos misiones de cada equipo (§7.8.4).

### CU-73.2 Evaluar la aparición y enfrentar al Máster (Combat, en la simulación)

1. Al terminar el encuentro de un punto de evaluación, Combat tira por cada candidato en orden (P-X3).
2. Sin aparición: registra la evaluación con `appeared: false` (CA-02).
3. Con aparición: crea el encuentro con el Máster con `levelOffset` y su perfil (CA-04) y lo resuelve con las reglas de combate.
4. Registra el resultado: Máster derrotado (CA-01), héroe derrotado (CA-03) o Máster en retirada si nadie cae dentro del límite (decisión 8).

### CU-73.3 Registrar y acreditar (Missions, al cerrar)

1. En la transacción del cierre de HU-72, Missions guarda las evaluaciones y los encuentros del resumen en `mission_master_encounters`.
2. Por cada encuentro con el Máster derrotado, y si la misión no quedó `VOIDED`, pide la entrega de la épica con su `operationId` determinista.
3. `200` marca `grantedAt`; `503` o red: reintento con el mismo `operationId`; `422`: se registra y queda para revisión (decisión 7).

## Tabla de decisión

| Caso | Probabilidad | Tirada en Combat | Combate | Registro | Épica |
| --- | --- | --- | --- | --- | --- |
| M-1 | `0` | No aparece nunca | — | `NOT_APPEARED` en cada punto | No |
| M-2 | `0.15` | No dispara | — | `NOT_APPEARED` (CA-02) | No |
| M-3 | `0.15` | Dispara | El héroe derrota al Máster | `APPEARED_DEFEATED` (CA-01) | Sí, una vez |
| M-4 | `0.15` | Dispara | El Máster derrota al héroe | `APPEARED_HERO_DEFEATED`; misión `FAILED` | No (CA-03) |
| M-5 | `1` y tope 1 | Dispara en el primer punto | El héroe gana | Primer punto `APPEARED_DEFEATED`; el segundo, `SKIPPED_MAX_REACHED` | Sí, una vez |
| M-6 | Sin valor para el subtipo | No se evalúa | — | `NOT_APPLICABLE` | No |
| M-7 | Cualquiera | — | — | El cierre se repite | Nunca dos veces (mismo `operationId`) |

Cómo convierte Combat su índice aleatorio en una tirada con probabilidad `p` lo decide Combat (ADR-021). Missions solo comprueba que el resultado venga registrado.

## Modelo conceptual de datos

| Dato | Propietario | Dónde vive |
| --- | --- | --- |
| Configuración del Máster | Missions (contenido) | `mission_definitions.master_encounter` (`jsonb`) |
| Evaluaciones y encuentros por matrícula | Missions | `mission_master_encounters` |
| Tirada, estadísticas y combate | Combat | Simulación de HU-72 |
| Épica en el inventario del jugador | Player/Inventory (HU-32) | Fuera de Missions |
| Definición de la épica como producto | Catalog | Fuera de Missions (decisión 7) |

```sql
CREATE TABLE mission_master_encounters (
  enrollment_id       text NOT NULL REFERENCES mission_enrollments (enrollment_id),
  sequence            integer NOT NULL CHECK (sequence >= 1),
  after_encounter     integer,
  master_ref          text,
  status              text NOT NULL CHECK (status IN ('NOT_APPLICABLE', 'NOT_APPEARED', 'APPEARED_DEFEATED',
                                                      'APPEARED_HERO_DEFEATED', 'APPEARED_ESCAPED',
                                                      'SKIPPED_MAX_REACHED')),
  epic_ref            text,
  grant_operation_id  uuid UNIQUE,
  granted_at          timestamptz,
  PRIMARY KEY (enrollment_id, sequence),
  CHECK (grant_operation_id IS NULL OR status = 'APPEARED_DEFEATED')
);
```

El `CHECK` impone en el motor que solo un Máster derrotado puede llevar una entrega de épica.

## Frontera con HU-32, Player/Inventory y Catalog

| Responsable | Qué hace |
| --- | --- |
| HU-73 (Missions) | Configura, envía la configuración, guarda la evidencia y **pide** la entrega |
| Combat | Tira, genera el encuentro, aplica el desfase de nivel y resuelve el combate |
| HU-32 / Player/Inventory | **Acredita** la épica en el inventario, de forma idempotente, y rechaza cualquier otra vía de obtención (CA-02 de HU-32) |
| Catalog | Define la épica como producto; hoy el contrato V1 no representa todas las filas de la Tabla 20 (brecha documentada en `Nexus-Battle-Player-Inventory/docs/hu-31-epic-effects.md`) |

## Matriz CA → escenario → salida esperada

Escenarios con datos en los [fixtures](../contracts/hu-73-master-encounter-fixtures-v1.json).

| RF | CA | Escenario | Salida esperada | Elemento de diseño |
| --- | --- | --- | --- | --- |
| RF-73 | CA-01 | M-3 | Encuentro registrado y épica entregada una vez | CU-73.2, CU-73.3 y P-X6 |
| RF-73 | CA-02 | M-1, M-2 y M-6 | Evaluación registrada como no aparición o no aplicable | P-X2 y P-X7 |
| RF-73 | CA-03 | M-4 | Sin épica; encuentro registrado; misión `FAILED` | P-X4 |
| RF-73 | CA-04 | Cualquier aparición | Máster con `levelOffset: 2` y estadísticas superiores según la regla que fije el PO | P-X8 (Combat) |
| — | — | M-5 | Tope respetado | P-X3 |
| — | — | M-7 | Una sola entrega aunque el cierre se repita | P-X6 |
| — | — | C-1 y C-2: probabilidad `1.5` o épica sin referencia | Configuración rechazada al cargarla | P-X5 |

## Impacto arquitectónico

| Componente | Cambio | Responsable |
| --- | --- | --- |
| Missions | Validación de `masterEncounter`, resolución de la probabilidad por subtipo, `mission_master_encounters` y entrega de la épica al cerrar | Team Beta (HU-73.2) |
| Combat | Tiradas por punto de evaluación, encuentro con el Máster y registro en el resumen y la bitácora | Team Alfa |
| Player/Inventory | Aceptar `missions` en `POST /api/internal/v1/inventory/grants` (ya decidido en ADR-019) y acreditar épicas (HU-32) | Team Alfa |
| Catalog | Representar las épicas de la Tabla 20 como productos | Dueño de Catalog |

## Decisiones pendientes (visibles, no resueltas)

1. **Qué probabilidad aplica.** La Tabla 20 da una por tipo de héroe (de 0,01 % a 0,1 %) y el ejemplo de misión da «0.15% (15% de probabilidad)». Hay que fijar la fuente y la unidad.
2. **Qué «nivel».** No existe nivel de héroe en Player/Inventory, y el nivel de jugador (HU-08 y HU-09) aún no está implementado.
3. **Qué son «estadísticas superiores».** La fórmula no está definida.
4. **Puntos de evaluación y tope** por tipo de misión (las de exploración tienen «mayor probabilidad» de Máster, §7.8.2).
5. **¿Se entrega la épica si la misión termina en fallo después de derrotar al Máster?** Propuesta: sí; la HU no la condiciona al éxito. En `VOIDED`, no.
6. **Qué pasa si el jugador ya tiene esa épica.**
7. **La épica como producto de Catalog.** Sin ese producto no hay `productId` para la entrega.
8. **Máster en retirada:** si ninguno cae dentro del límite de rondas del encuentro, propuesta `APPEARED_ESCAPED`, sin épica.
9. **Qué Máster puede aparecer:** el curso dice que cada tipo de héroe tiene Máster asociados, y el ejemplo fija uno por misión.
