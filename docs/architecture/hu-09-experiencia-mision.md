# HU-09 — Diseño: experiencia por derrota de un rival en misión (JvE)

- **Historia:** [HU-09 #18](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/18) · `RF-09` · [EPIC-01 #1](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/1).
- **Task de este documento:** [#439](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/439) (HU-09.1).
- **Contrato que desarrolla:** [hu-09-experience-reward-v1](../contracts/hu-09-experience-reward-v1.md).
- **Estado:** **implementado en `develop` y verificado de extremo a extremo; la HU no está aceptada.** Combat (#440), Player-Inventory (#441) y Missions (#442) están entregados; la cadena con las tres piezas reales está en la [evidencia](../evidence/HU-09-experiencia-por-derrota-de-un-rival.md). `P-2` está **cerrada** (redondeo al entero más próximo) y `CA-08` se fijó por **derrota válida de NPC** (§3, contrato §14.1). Este documento nació como diseño previo a la implementación; donde antes decía «no implementado» ahora describe lo entregado.
- **Equipos:** Team Beta (Missions, dueño funcional de la misión), Team Alfa (Combat y Player/Inventory).

## 1. Qué problema resuelve

Antes de HU-09, el jugador progresaba al derrotar rivales pero **nada conectaba una derrota con su progreso**: HU-08 sabe cuánto cuesta subir de nivel y cómo acumular experiencia, y HU-24 sabe producir un número aleatorio uniforme, pero no existe la pieza que, ante una derrota de un rival, obtenga la tirada, calcule la recompensa y la acredite.

HU-09 es esa pieza, y su dificultad no está en la fórmula —que es trivial— sino en **respetar tres fronteras a la vez**: la aleatoriedad es de Combat, el cálculo es de Missions y el estado del héroe es de Player/Inventory.

## 2. Alcance

**Entra:** la recompensa de experiencia `10 × 1,2^(1d8)` por derrota de un rival en una misión JvE, su tirada autoritativa, su cálculo, su acreditación idempotente y la representación de su estado.

**No entra:** PvP («Jugar Online»), la recompensa por misión completada (HU-10), la caída de objetos (HU-30), la épica por derrota de Máster (HU-32/HU-73), el multiplicador de estadísticas por nivel (`CA-06`, que es de HU-08 y no interviene en la fórmula ni en el importe) y el flujo de misión completo (HU-70, HU-71, HU-72, HU-74).

## 3. Caso de uso

- **Identificador:** `UC-HU09-01` — Otorgar experiencia por derrota de un rival.
- **Actor:** el **sistema**, no el jugador. Lo dispara el cierre de una misión JvE en la que el héroe derrotó a al menos un NPC; el jugador es el beneficiario, no el que invoca.
- **Objetivo:** que el héroe que derrotó a un NPC reciba la experiencia que le corresponde y, si con ella alcanza el umbral, suba de nivel.
- **Precondiciones:**
  - existe una misión JvE cerrada cuya simulación registra al menos una **derrota válida de un NPC** (la misión puede haber terminado `COMPLETED` o `FAILED`);
  - el héroe beneficiario está identificado (`heroId`) y pertenece a un jugador (`playerId`);
  - el motor de aleatoriedad de Combat está disponible.
- **Entrada:** el hecho de la derrota del rival (misión, simulación, héroe, rival y momento).
- **Flujo principal (derrota de un rival):**
  1. Missions cierra el enfrentamiento JvE y **enumera cada enemigo derrotado** a partir de la simulación (encuentro + instancia).
  2. Por **cada derrota**, Missions persiste una recompensa en estado `PENDING`. **Se persiste antes de pedir nada**: es lo que impide que exista una tirada sin dueño.
  3. Missions pide a Combat el **lote de tiradas** de esa misión, con un `operationId` determinista.
  4. Combat consume un `1d8` del motor centralizado **por derrota** y devuelve el lote en el mismo orden, **persistido antes de responder** en un único documento por misión, con la clave de cada derrota dentro.
  5. Por cada derrota, Missions calcula `10 × 1,2^(1d8)`, lo redondea a entero y persiste el importe (`ROLLED`).
  6. Por cada derrota, Missions acredita el importe en Player/Inventory con el `operationId` determinista de esa instancia.
  7. Player/Inventory acumula la experiencia, recalcula el nivel con la tabla de HU-08 y confirma.
  8. Missions marca cada recompensa como `CREDITED` y las refleja en el reporte.
- **Flujos alternativos:**
  - **A1 — Sin derrota válida de NPC (`CA-08`):** no se crea recompensa, no se pide tirada y no se acredita nada, aunque la misión termine `FAILED`.
  - **A1b — Misión `FAILED` con NPC ya derrotados (`CA-08`):** cada derrota devenga y **conserva** su XP; el fracaso posterior no la revierte.
  - **A1c — Misión `VOIDED`:** anulada, resultado inválido o simulación rechazada: no se crea ninguna recompensa.
  - **A2 — Beneficiario inexistente (`heroId` nulo o participante `AI`):** no hay recompensa.
  - **A3 — Reintento:** cada paso se repite con el **mismo** `operationId`; se obtiene el mismo resultado y no se consume azar de nuevo.
  - **A4 — Rechazo terminal (`422`):** la recompensa queda `FAILED`; la misión **no** se revierte.
  - **A5 — Dependencia no disponible (`503`):** la recompensa se queda en su estado de origen y el barrido reintenta.
- **Postcondiciones:** el acumulado del héroe creció exactamente una vez por derrota válida; el nivel es el que corresponde a ese acumulado según la tabla de HU-08; el estado de la recompensa es terminal o está pendiente de reintento, nunca indefinido.
- **Reglas:** `RF-09` y `CA-01` a `CA-08`. `CA-09` es la condición de aceptación de la HU y no se convierte en escenario.

## 4. Modelo de dominio

```text
Missions
  ExperienceReward                 (agregado propio, UNA POR NPC DERROTADO)
    enrollmentId, simulationId, heroId, playerId
    encounterId, enemyInstanceId    <- la instancia real; NO el arquetipo
    rivalRef, roll?, amount?, state, attempts, failureReason?

  ExperienceRewardPolicy           (política pura, dueño único de la fórmula)
    rewardFor(roll: 1..8) -> entero

Combat
  ExperienceRollBatch              (persistido, UNO POR MISIÓN)
    operationId                    <- clave del lote: mission:{enrollmentId}:xp-rolls
    enrollmentId, simulationId, heroId, createdAt
    rolls[]                        <- una por derrota, con su clave de instancia
      encounterId, enemyInstanceId, rivalRef, roll: 1..8, persistedAt

  ExperienceRollPolicy             (política pura; consume el motor, no la fórmula)
    rollFor(sequence) -> 1..8

Player/Inventory
  ExperienceGrant                  (ledger insert-only, _id = operationId)
  HeroProgression                  (HU-08: acumulado + nivel, ya implementado)
```

Decisiones de modelado:

- **La recompensa es un agregado de Missions**, no un campo del reporte ni del héroe, y hay **una por NPC derrotado**. Tiene ciclo de vida propio (pendiente mientras se reintenta) y estado que sobrevive al reinicio, exactamente como el `RewardWorkflow` de HU-22 en Combat.
- **La clave de una recompensa es la instancia de la derrota** (`encounterId` + `enemyInstanceId`), nunca el arquetipo del enemigo: una misión puede enfrentar dos veces al mismo tipo y el arquetipo colisionaría. La misma clave identifica cada tirada dentro del lote de Combat.
- **El lote de tiradas se persiste en un único documento por misión**, no en uno por tirada. Dos motivos: una sola escritura impide conjuntos de tiradas a medias, y el documento es lo que permite comparar el contenido cuando llega el mismo `operationId` con otra lista —sin él, el `409` que promete el contrato sería inimplementable.
- **La tirada no se guarda en Missions como fuente de verdad**: se guarda el importe calculado. La tirada vive en Combat, que es quien la produjo y quien debe poder repetirla sin volver a consumir el cursor.
- **El importe se persiste antes de acreditar.** Si Missions cae entre el cálculo y la acreditación, el reintento usa el importe guardado y **no** vuelve a tirar ni a calcular distinto.
- **Missions no guarda el nivel ni el acumulado del héroe.** Es estado de otro contexto; lo devuelve Player/Inventory y se representa, no se copia.

## 5. Fronteras

| Frontera | Regla | Por qué |
| --- | --- | --- |
| **HU-08 ↔ HU-09** | HU-09 no calcula umbrales ni niveles: usa `HeroProgression.awardExperience`, que ya acumula, recalcula con la tabla y no descarta experiencia en el nivel 8 | Duplicar la tabla rompería el «único punto conceptual» que HU-08 sostiene |
| **HU-24 ↔ HU-09** | El `1d8` se obtiene **solo** del motor de Combat; Missions no tiene generador | `ADR-021` da la exclusiva de la aleatoriedad a Combat |
| **HU-09 ↔ HU-10** | HU-09 es la XP **por derrota**; HU-10 la recompensa de **misión completada**, incluida su línea `EXPERIENCE` en el reporte | Son dos hechos distintos con la misma moneda |
| **HU-09 ↔ HU-72** | HU-09 **no** modifica el contrato de simulación: pide la tirada en una operación propia | El contrato de HU-72 (PR #132, ya mergeado) no se reabre |
| **HU-09 ↔ HU-74** | HU-09 escribe el estado de su línea de recompensa; no genera la foto del reporte | El reporte es inmutable y las recompensas tienen estado aparte (`P-T2` de HU-74) |
| **HU-09 ↔ Web** | Web no calcula nada: representa el estado de la recompensa y el nivel que le llegan | Es la regla de continuidad del proyecto |

## 6. Decisiones y su justificación

| # | Decisión | Motivo | Alternativa descartada |
| --- | --- | --- | --- |
| D-1 | La tirada se produce en una operación propia de Combat, no dentro de la simulación de HU-72 | Desacopla HU-09 de un contrato sin mergear y evita tirar cuando no hay derecho a recompensa | Extender la respuesta de simulación: habría acoplado HU-09 al contrato de HU-72 (PR #132, entonces sin mergear) |
| D-2 | Missions calcula la fórmula | Es la aclaración del PO y deja la aritmética donde vive el hecho | Que la calculara Combat: habría metido la progresión del héroe en el dominio de combate |
| D-3 | Player/Inventory recibe un importe **entero** y rechaza lo que no lo sea | El redondeo es parte de la fórmula, no de la frontera | Redondear en Player/Inventory: repartiría la regla en dos servicios |
| D-4 | El endpoint interno se acota con `@InternalCallers('missions')` en lugar de ampliar el allow-list global | Permiso mínimo suficiente sobre una ruta concreta | Añadir `missions` a la lista global: daría acceso a todas las rutas internas |
| D-5 | La recompensa se persiste antes de cada efecto remoto | Sin eso, un reinicio dejaría una tirada sin recompensa o una recompensa sin traza | Reintentar recalculando: volvería a consumir el cursor de azar |
| D-6 | El `operationId` es determinista y se reutiliza en cada reintento | Es lo que hace que un reintento no duplique experiencia | Un identificador por intento: duplicaría la recompensa |
| D-7 | La clave de una recompensa es `encounterId` + `enemyInstanceId`, no `rivalRef` | Una misión puede enfrentar dos veces al mismo arquetipo; identificarlo por arquetipo colisionaría y perdería o duplicaría recompensas | Identificar por `rivalRef`: colisiona con `sombra-corrompida` en los encuentros 1 y 2 del ejemplo de HU-72 |
| D-8 | Las tiradas de una misión se piden **en un lote**, las acreditaciones **una por derrota** | Un lote resuelve el consumo del cursor de azar de una vez y evita conjuntos de tiradas a medias; una acreditación por derrota conserva traza e idempotencia | Una llamada de tirada por derrota: 19 viajes y riesgo de lote parcial; una acreditación agregada: pierde la clave por derrota |
| D-9 | La recompensa se persiste **antes** de pedir la tirada | Es lo que hace imposible la tirada huérfana: toda tirada guardada tiene una recompensa que la reclama | Pedir primero la tirada: una caída dejaría tiradas sin dueño |
| D-10 | El lote de tiradas se persiste en **un único documento** por misión, con la clave de cada derrota dentro | Una escritura atómica —sin conjuntos a medias— y un contenido comparable, que es lo que hace implementable el `409` del contrato | Un documento por tirada: no habría dónde detectar que el mismo `operationId` llegó con otra lista |

## 7. Riesgos

| # | Riesgo | Impacto | Mitigación |
| --- | --- | --- | --- |
| R-1 | Implementar un generador propio para el `1d8` | **Crítico**: viola `ADR-021` y las guardas estáticas del proyecto | Guarda de azar en Combat + revisión |
| R-2 | Duplicar la fórmula en dos servicios | Alto: dos verdades que se desincronizan | Un único dueño y prueba de no-duplicación |
| R-3 | Volver a tirar en un reintento | Alto: recompensa distinta por el mismo hecho | Tirada persistida antes de responder, con `operationId` |
| R-4 | Acreditar dos veces | Alto: progresión inflada | Ledger con `_id = operationId` y transacción |
| R-5 | Dar la recompensa por concedida antes de estarlo | Medio: el jugador ve algo que no ocurrió | Estado explícito (`PENDING`/`CREDITED`/`FAILED`) en el reporte |
| R-6 | Implementar antes de que exista el flujo de misión | Alto: trabajo que no se puede integrar | HU-09.4 bloqueada por `HU-72.2` y `HU-74.2` |
| R-7 | Asumir que una derrota sube de nivel | Medio: `1d8 = 8` da `43` y el primer umbral (HU-08 vigente) es `100` acumulados | Documentado en el contrato; la cadena E2E fija las fronteras (`99 + 12 = 111`) |
| R-8 | Identificar la recompensa por el arquetipo del enemigo | **Alto**: dos enemigos del mismo tipo colisionarían y se perdería o duplicaría experiencia | La clave es `encounterId` + `enemyInstanceId`, tomados del `combatLog` de HU-72 |
| R-9 | Dejar una tirada sin recompensa que la reclame | **Alto**: azar consumido sin efecto recuperable | La recompensa se persiste **antes** de pedir la tirada; el barrido termina lo pendiente |

## 8. Lo que este documento NO afirma

- **No** declara la HU aceptada: eso exige revisión por pares y la aprobación del PO. La verificación de extremo a extremo es **técnica**.
- **No** afirma que la cadena sea «totalmente real» en todos los escenarios: la simulación de misión de Combat todavía no produce la bitácora de bajas, así que la cadena usa un doble de desarrollo para ese resultado (y, en `S-12`, un doble que recorta la bitácora para reproducir un `FAILED` con bajas). Las tiradas de Combat y la acreditación de Player-Inventory sí son reales. Lo sustituido está en la tabla de límites del reporte de ejecución.
- **No** reabre el contrato de simulación de HU-72 ni el reporte de HU-74 (ambos mergeados): aquí solo se referencian.
- **`P-2` está cerrada** (redondeo al entero más próximo, decisión del PO en Management #18) y `P-3` (corrección del enunciado del Issue) está ejecutada.
- **No** reabre la tabla de umbrales de HU-08 (`100 / 300 / 500 / 700 / 900 / 1.100 / 1.300`, nivel 8 máximo): HU-09 la consume.
