# HU-74 — Diseño del reporte y el historial de misiones

**Estado:** diseño. **No implementado.** Missions no tiene rutas de negocio en `develop`. Nada de este documento autoriza a marcar rutas como disponibles en [service-catalog.md](../contracts/service-catalog.md).

## Trazabilidad

| Elemento | Referencia |
| --- | --- |
| Historia | [HU-74 #59](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/59) — Generación de reporte de misión (`RF-74`) |
| Épica | [EPIC-08 #8](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/8) — Misiones |
| Task de diseño | [HU-74.1 #379](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/379) |
| Tasks que usan este diseño | [HU-74.2 #380](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/380) implementación, [HU-74.3 #381](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/381) consulta en Web y [HU-74.4 #382](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/382) pruebas |
| Contrato | [hu-74-mission-report-v1.md](../contracts/hu-74-mission-report-v1.md) y [fixtures](../contracts/hu-74-mission-report-fixtures-v1.json) |
| Diagramas | [casos de uso](../diagrams/hu-74-use-case.puml), [actividad](../diagrams/hu-74-activity.puml), [secuencia](../diagrams/hu-74-sequence.puml) y [dominio](../diagrams/hu-74-domain.puml) |
| Fuente funcional | Documento del curso, §7.8.8 (reporte e historial) |
| Diseños de los que parte | [HU-72](hu-72-simulacion-mision.md) (resumen, bitácora y `MissionSettled`) y [HU-73](hu-73-encuentro-master.md) (evidencia del Máster) |
| HU relacionadas | HU-10 (recompensas, en Backlog), HU-32 (épicas) y HU-76 (logros) |

## Vista rápida (para revisión)

| Pregunta | Respuesta del diseño |
| --- | --- |
| ¿Qué es un reporte? | Una **foto inmutable** de una misión terminada, creada en la misma transacción que la cierra. No recalcula daño ni vuelve a entregar recompensas. |
| ¿Qué es el historial? | **Proyecciones** calculadas a partir de los reportes: misiones terminadas, estadísticas por tipo, mejores tiempos, colección de épicas y progreso narrativo. |
| ¿Y las recompensas que aún no se acreditaron? | Cada línea de recompensa tiene su propio estado (`PENDING`, `CREDITED` o `FAILED`), guardado aparte de la foto. HU-74 no espera a HU-10. |
| ¿Una misión en curso tiene reporte? | No (CA-04). La consulta responde `404 REPORT_NOT_AVAILABLE`. |

## Decisiones funcionales literales (HU publicada)

1. El reporte se genera al terminar la misión; una misión en curso no tiene reporte (CA-04).
2. Resumen general: resultado, héroe utilizado y duración.
3. Estadísticas de combate: daño infligido y recibido, turnos, habilidades usadas, encuentros completados y efectos críticos.
4. Enemigos derrotados, con el estado del jefe final y del Máster si aplica (CA-03).
5. Recompensas: créditos, productos con su rareza, épicas y experiencia.
6. Objetivos con su estado y las bonificaciones por objetivos cumplidos.
7. Queda persistido y disponible en el historial (CA-01).
8. El historial muestra misiones completadas con fecha, estadísticas acumuladas por tipo, mejores tiempos, colección de épicas de Máster y progreso en cadenas narrativas (CA-05).

## Criterios técnicos propuestos (no aprobados por el PO)

| Id | Propuesta | Por qué |
| --- | --- | --- |
| P-T1 | El reporte se crea en la **misma transacción** que el cierre de HU-72. | Así es imposible una misión terminada sin reporte o un reporte de una misión en curso (CA-04). |
| P-T2 | `MissionReport` es inmutable: no se actualiza después de crearse. Las recompensas viven en `mission_report_rewards`, con su estado propio. | Cumple la foto inmutable que pide el PO y evita el ciclo HU-10 ↔ HU-74. |
| P-T3 | Reporte para `COMPLETED`, `FAILED` y `ABANDONED`. Una misión `VOIDED` aparece en el historial sin estadísticas ni reporte de combate. | Una anulación técnica no tiene simulación válida que mostrar (HU-72, P-S7). |
| P-T4 | Cada campo indica quién lo produce: Combat (resumen), Missions (resultado y objetivos), HU-73 (Máster) o HU-10 (recompensas). Los que dependen de propuestas aún no aceptadas se marcan provisionales en el contrato. | La guía del PO pide no asumir como definitivos los campos de HU-72 y HU-73. |
| P-T5 | «Mejor tiempo» usa la duración **simulada** (`simulatedDuration`) de las misiones completadas. | La duración real es fija por misión y no distingue un tiempo de otro. |
| P-T6 | Una «cadena narrativa» es el conjunto de misiones `STORY` unidas por requisitos previos. El progreso es `completadas / total` de la cadena. | La HU la nombra sin definirla (decisión 3). |
| P-T7 | El historial se calcula al leer, sobre índices por jugador, fecha, misión y dificultad. Sin tablas de agregados. | El volumen por jugador es pequeño; menos estado que mantener coherente. |
| P-T8 | Solo el dueño lee sus reportes. Un reporte de otro jugador responde `404`, igual que uno inexistente. | No revelar qué matrículas existen. |

## Caso de uso textual

### CU-74.1 Generar el reporte (sistema, dentro del cierre de HU-72)

1. El cierre de HU-72 decide el resultado y registra `MissionSettled`.
2. En la misma transacción, Missions arma la foto con el resumen y la bitácora guardados, la evidencia del Máster (HU-73) y los objetivos evaluados.
3. Crea las líneas de recompensa en `PENDING` con lo que se conozca (HU-10 las calcula; hasta entonces puede no haber líneas).
4. Guarda la foto con `schemaVersion: 1`.

### CU-74.2 Consultar un reporte (jugador)

- `GET /api/v1/missions/me/reports/{enrollmentId}` devuelve la foto y las recompensas con su estado actual.
- Misión en curso: `404 REPORT_NOT_AVAILABLE` (CA-04). Inexistente o de otro jugador: `404 REPORT_NOT_FOUND`.

### CU-74.3 Consultar el historial (jugador, CA-05)

- `GET /api/v1/missions/me/history`: misiones terminadas, de la más reciente a la más antigua, paginadas por cursor.
- `GET /api/v1/missions/me/history/summary`: estadísticas por tipo, mejores tiempos, colección de épicas y progreso narrativo.

### CU-74.4 Actualizar el estado de una recompensa (HU-10 y HU-73)

Cuando una entrega se confirma (`200`) o falla de forma terminal (`422`), la línea pasa a `CREDITED` o `FAILED`. La foto no cambia.

## Fragmento de dominio

Diagrama: [hu-74-domain.puml](../diagrams/hu-74-domain.puml).

- **`MissionReport`** (inmutable): resumen, héroe, duración, estadísticas, enemigos, Máster, objetivos y versión del esquema.
- **`ReportRewardLine`**: tipo (`CREDITS`, `PRODUCT`, `EPIC` o `EXPERIENCE`), referencia, rareza, cantidad y estado.
- **`ReportBuilder`** (aplicación): arma la foto a partir de lo guardado por HU-72 y HU-73; no llama a Combat.
- **Proyecciones de historial** (lectura): `HistoryEntry`, `CategoryStats`, `BestTime`, `EpicCollectionEntry` y `NarrativeProgress`.

## Modelo conceptual de datos

| Dato | Propietario | Dónde vive |
| --- | --- | --- |
| Foto del reporte | Missions | `mission_reports` |
| Líneas de recompensa y su estado | Missions (el cálculo es de HU-10) | `mission_report_rewards` |
| Resumen y bitácora de origen | Missions (HU-72) | `mission_executions` |
| Evidencia del Máster | Missions (HU-73) | `mission_master_encounters` |
| Créditos, productos y épicas entregados | Wallet y Player/Inventory | Fuera de Missions |

```sql
CREATE TABLE mission_reports (
  enrollment_id   text PRIMARY KEY REFERENCES mission_enrollments (enrollment_id),
  player_id       text NOT NULL,
  mission_id      text NOT NULL,
  category        text NOT NULL,
  difficulty      text NOT NULL,
  outcome         text NOT NULL CHECK (outcome IN ('COMPLETED', 'FAILED', 'ABANDONED')),
  outcome_reason  text,
  hero            jsonb NOT NULL,
  started_at      timestamptz NOT NULL,
  finished_at     timestamptz NOT NULL,
  simulated_duration interval,
  combat_stats    jsonb NOT NULL,
  enemies         jsonb NOT NULL,
  master          jsonb NOT NULL,
  objectives      jsonb NOT NULL,
  schema_version  integer NOT NULL DEFAULT 1,
  generated_at    timestamptz NOT NULL
);

CREATE INDEX ix_report_player_date ON mission_reports (player_id, finished_at DESC);
CREATE INDEX ix_report_player_mission ON mission_reports (player_id, mission_id);
CREATE INDEX ix_report_player_difficulty ON mission_reports (player_id, difficulty);

CREATE TABLE mission_report_rewards (
  enrollment_id  text NOT NULL REFERENCES mission_reports (enrollment_id),
  line_no        integer NOT NULL,
  kind           text NOT NULL CHECK (kind IN ('CREDITS', 'PRODUCT', 'EPIC', 'EXPERIENCE')),
  reference      text,
  name           text NOT NULL,
  rarity         text,
  quantity       integer NOT NULL CHECK (quantity >= 1),
  status         text NOT NULL CHECK (status IN ('PENDING', 'CREDITED', 'FAILED')),
  source         text NOT NULL CHECK (source IN ('HU-10', 'HU-73')),
  updated_at     timestamptz NOT NULL,
  PRIMARY KEY (enrollment_id, line_no)
);
```

La inmutabilidad de `mission_reports` se impone en la aplicación (sin rutas de actualización) y, si el equipo lo decide, con un `REVOKE UPDATE` al usuario de la aplicación.

## Campos y quién los produce

| Bloque del reporte | Productor | Provisional hasta |
| --- | --- | --- |
| `outcome`, `outcomeReason`, `objectives` | Missions (HU-72) | Que se acepten las decisiones 1 y 2 de HU-72 |
| `hero` (`heroId`, nombre, subtipo) | Perfil congelado de Player/Inventory | La decisión 10 de HU-72 |
| `combatStats` | Resumen de Combat | Que Combat acepte la propuesta de HU-72 |
| `enemies`, `bossDefeated` | Resumen de Combat | Ídem |
| `master` | Evidencia de HU-73 | Que Combat acepte el fragmento de HU-73 |
| Recompensas `CREDITS`, `PRODUCT` y `EXPERIENCE` | HU-10 | Que HU-10 salga del Backlog |
| Recompensa `EPIC` | HU-73 con Player/Inventory | Que Catalog tenga la épica como producto |

## Matriz CA → escenario → salida esperada

Escenarios con datos en los [fixtures](../contracts/hu-74-mission-report-fixtures-v1.json).

| RF | CA | Escenario | Salida esperada | Elemento de diseño |
| --- | --- | --- | --- | --- |
| RF-74 | CA-01 | R-1: misión completada | Reporte creado en el cierre y visible en el historial | P-T1 |
| RF-74 | CA-02 | R-1 | Los cinco bloques del reporte presentes | Contrato |
| RF-74 | CA-03 | R-3: Máster derrotado | El Máster figura en `enemies` y la épica en las recompensas | P-T4 |
| RF-74 | CA-04 | R-5: misión en curso | `404 REPORT_NOT_AVAILABLE` | P-T1 |
| RF-74 | CA-05 | H-1: historial con varias misiones | Lista con fechas y resumen con estadísticas, mejores tiempos, épicas y progreso | P-T5, P-T6 y P-T7 |
| — | — | R-2: misión fallida | Reporte con `outcome: FAILED` y la bitácora hasta la derrota | P-T3 |
| — | — | R-4: recompensa pendiente | Línea en `PENDING`; luego `CREDITED` sin cambiar la foto | P-T2 |
| — | — | R-6: pedir el reporte de otro jugador | `404 REPORT_NOT_FOUND` | P-T8 |

## Impacto arquitectónico

| Componente | Cambio | Responsable |
| --- | --- | --- |
| Missions | `mission_reports`, `mission_report_rewards`, `ReportBuilder` dentro del cierre y rutas de reporte e historial | Team Beta (HU-74.2) |
| Web | Reporte e historial en `src/features/missions/` | Team Beta (HU-74.3) |
| HU-10 | Calcular y acreditar recompensas y actualizar el estado de sus líneas | Sin asignar (Backlog) |

## Decisiones pendientes (visibles, no resueltas)

1. **¿Qué muestra el historial de una misión `VOIDED`?** Propuesta P-T3: aparece sin reporte de combate.
2. **Abandono:** el reporte de una misión `ABANDONED` depende de que exista la cancelación (HU-72, decisión 3).
3. **Qué es una «cadena narrativa».** Propuesta P-T6.
4. **«Mejor tiempo»** con la duración simulada (P-T5).
5. **Nivel del héroe** en el resumen (§7.8.8): no existe nivel de héroe.
6. **Retención** de reportes y bitácoras.
7. **Bitácora completa en el reporte:** propuesta de no incluirla en la respuesta del reporte; se expone aparte si HU-74.3 la necesita.
