# HU-09 — Evidencia de diseño: experiencia por derrota de un rival (JvE)

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#18](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/18)
- **Tasks:** [#439](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/439) (diseño · `open`), [#440](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/440) (Combat · `open`), [#441](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/441) (Player-Inventory · `open`), [#442](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/442) (Missions · `open`), [#443](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/443) (Web · `open`), [#444](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/444) (E2E · `open`)
- **Fecha:** 2026-09-23
- **Requisito trazado:** `RF-09`
- **Bounded context:** Missions (coordinación) + Combat (tirada) + Player/Inventory (estado del héroe)
- **Contrato entregado:** [hu-09-experience-reward-v1](../contracts/hu-09-experience-reward-v1.md)
- **Estado:** **solo diseño de la Task #439.** No hay código de HU-09 en `develop` en ningún repositorio, ninguna Task de implementación ha empezado y **la HU no está aceptada**.

## Estado de la verificación: qué se comprobó y qué NO

Este documento **no declara la HU aceptada** ni afirma que exista implementación. Declarar aquí una aceptación sería el mismo error que el Project ya cometió con HU-29 y HU-31.

| Nivel | Estado |
| --- | --- |
| Contrato de la recompensa (reparto, fórmulas, `operationId`, errores) | **Diseñado** en `docs/contracts/hu-09-experience-reward-v1.md` |
| Diseño de dominio y fronteras | **Diseñado** en `docs/architecture/hu-09-experiencia-mision.md` |
| Cuatro diagramas (caso de uso, actividad, secuencia, dominio) | **Entregados** en `docs/diagrams/hu-09-*.puml` |
| SAD §4 y §14 | **Actualizadas** con la subsección y las limitaciones de HU-09 |
| Superficie documentada (`service-catalog.md`) | **Actualizada** con las dos operaciones internas |
| Tirada `1d8` en Combat (`#440`) | **NO implementada** |
| Acreditación idempotente en Player/Inventory (`#441`) | **NO implementada** |
| Coordinación y fórmula en Missions (`#442`) | **NO implementada** |
| Visualización en Web (`#443`) | **NO implementada** |
| Pruebas de cualquier tipo | **NO existen** |
| Revisión por pares | **PENDIENTE** |
| Aceptación del PO | **PENDIENTE**, y condicionada por las decisiones abiertas |

## Qué se decidió, y con qué autoridad

| # | Origen | Contenido |
| --- | --- | --- |
| 1 | Requisito explícito del Issue #18 | Fórmula `10 × 1,2^(1d8)`; `1d8` entero `1..8` del motor centralizado; la XP se acumula; se verifica el umbral tras acreditar; sin victoria válida no hay recompensa |
| 2 | Aclaración funcional del PO (posterior al enunciado) | La fórmula es de **JvE** (muerte de NPC en misión); **PvP no la otorga**; Missions coordina y calcula; Combat tira; Player/Inventory acredita |
| 3 | Decisión arquitectónica vigente | `ADR-019` (ownership y HMAC interno) y `ADR-021` (Combat, única autoridad de aleatoriedad) |
| 4 | Contrato reutilizado como plantilla | `POST /api/internal/v1/inventory/grants` (Player-Inventory, HU-59/HU-69): forma del endpoint interno y del ledger idempotente |
| 5 | Decisión técnica de esta Task | Las dos operaciones internas, los `operationId` deterministas, los estados de la recompensa, la matriz de fallos y la elección de operación propia para la tirada |
| 6 | Fuera de alcance | HU-10, HU-30, HU-32/HU-73, PvP y `CA-06` de HU-08 |

## Contrato entregado

| Operación | Frontera | Idempotencia |
| --- | --- | --- |
| `POST /api/internal/v1/combat/experience-rolls` | Missions → Combat | `mission:{enrollmentId}:rival:{rivalRef}:xp-roll` |
| `POST /api/internal/v1/players/{playerId}/heroes/{heroId}/experience` | Missions → Player/Inventory | `mission:{enrollmentId}:rival:{rivalRef}:hero:{heroId}:xp` |

- **Ninguna superficie pública nueva.** Web consume el reporte de misión (HU-74).
- **Ninguna ruta existente se modifica** y ningún mensaje de HU-21 cambia de forma.
- **`missions` no entra en el allow-list global** de Player/Inventory: la ruta se acota con `@InternalCallers('missions')`.

## Decisiones abiertas del PO

| # | Decisión | Valor provisional del contrato | Efecto |
| --- | --- | --- | --- |
| `P-1` | Una tirada **por rival derrotado** o **una por victoria** | Una por **victoria sobre un rival** | Solo cambia cuántas veces se invoca la operación de tirada |
| `P-2` | Redondeo **al más próximo** o **truncamiento** | **Al más próximo**: `12, 14, 17, 21, 25, 30, 36, 43` | Con truncamiento: `12, 14, 17, 20, 24, 29, 35, 42` |
| `P-3` | Corrección del enunciado de #18 (restringir a JvE y añadir la cadena de Misiones como dependencia) | Pendiente | No afecta al diseño; afecta a la trazabilidad |

**Ninguna de las tres se ha resuelto en silencio.** Están escritas en el contrato, en el diseño y en el comentario de trazabilidad de #18.

## Bloqueos, medidos

| Bloqueo | Estado | Efecto real |
| --- | --- | --- |
| **HU-08** (#17) | `open`; entregada en los PRs [#42](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/42), [#43](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/43) y [#44](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/44), con CI en verde | **#441 no puede compilar**: `HeroProgression` y `ExperiencePolicy` no están en `develop` |
| **HU-24** (#71) | `closed` | El motor existe: `BoundedRandom.nextInt(8) + 1` |
| **Cadena de Misiones** | `HU-70`, `HU-71`, `HU-72`, `HU-73`, `HU-74`, `HU-75` y `HU-76` `open`, con sus Tasks (#365–#390) `open` y **solo diseñadas** | **Missions no tiene ninguna ruta de negocio ni ninguna tabla**: `#442` no puede existir antes que `HU-72.2` (#374) y `HU-74.2` (#380) |

**Consecuencia dicha sin adornos:** con el alcance acordado (JvE), HU-09 **no puede cerrarse en el Sprint 2** mientras la cadena de Misiones siga sin implementar. Lo que puede avanzar ya es este diseño, y `#441` en cuanto HU-08 se mergee.

## Criterios de aceptación y su cobertura

| CA | Task que lo cubre | Prueba prevista |
| --- | --- | --- |
| CA-01 flujo principal | #440 + #441 + #442 | E2E de #444 |
| CA-02 se aplica al héroe ganador | #441 + #442 | unitaria por `heroId` |
| CA-03 fórmula `10 × 1,2^(1d8)` | #442 | unitaria de la política, ocho valores |
| CA-04 `1d8` entero `1..8` del motor centralizado | #440 | unitaria de la política de tirada |
| CA-05 sin fuente de aleatoriedad distinta | #440 | guarda estática |
| CA-06 se acumula en el perfil | #441 | unitaria + DB del ledger |
| CA-07 verifica el umbral tras acreditar | #441 | unitaria de subida de nivel, incluido el salto múltiple |
| CA-08 sin victoria válida no se otorga | #440 + #442 | unitaria del guard + E2E negativo |
| CA-09 condición de aceptación | — | **No es un escenario**: es la condición de aceptación de la HU |

## Peligros registrados para quien implemente

1. **No crear un generador.** `ADR-021` da la exclusiva a Combat y las guardas estáticas del repositorio ya vigilan `Math.random`/`crypto`.
2. **No duplicar la fórmula.** Vive solo en Missions; Combat devuelve la tirada y Player/Inventory recibe un importe entero.
3. **No volver a tirar en un reintento.** La tirada se persiste en Combat antes de responder, con `operationId` determinista.
4. **No acreditar dos veces.** El ledger de Player/Inventory tiene `_id = operationId` y la progresión se actualiza en la misma transacción.
5. **No mostrar como concedida una recompensa pendiente.** El reporte de misión ya separa la foto del estado de cada línea.

## Qué falta para cerrar HU-09

1. **Corrección de `P-3`** por el PO (enunciado y dependencias de #18).
2. **Respuesta a `P-1` y `P-2`**; si no llega, el contrato mantiene los valores provisionales.
3. **Merge de HU-08** (PRs #42/#43/#44) para desbloquear `#441`.
4. **Flujo de misión** (`HU-72.2`, `HU-74.2`) para desbloquear `#442`.
5. Implementación de `#440`, `#441`, `#442` y, si el PO la pide, `#443`.
6. Verificación E2E (`#444`) y **entonces** revisión por pares y aceptación del PO.

## Archivos de este entregable

- `docs/contracts/hu-09-experience-reward-v1.md`
- `docs/architecture/hu-09-experiencia-mision.md`
- `docs/diagrams/hu-09-use-case.puml`, `hu-09-activity.puml`, `hu-09-sequence.puml`, `hu-09-domain.puml`
- `docs/architecture/SAD.md` (§4 y §14)
- `docs/contracts/service-catalog.md`
- `README.md`
- este documento
