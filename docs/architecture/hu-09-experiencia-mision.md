# HU-09 — Diseño: experiencia por derrota de un rival en misión (JvE)

- **Historia:** [HU-09 #18](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/18) · `RF-09` · [EPIC-01 #1](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/1).
- **Task de este documento:** [#439](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/439) (HU-09.1).
- **Contrato que desarrolla:** [hu-09-experience-reward-v1](../contracts/hu-09-experience-reward-v1.md).
- **Estado:** **diseño.** No hay código de HU-09 en `develop` en ningún repositorio.
- **Equipos:** Team Beta (Missions, dueño funcional de la misión), Team Alfa (Combat y Player/Inventory).

## 1. Qué problema resuelve

El jugador progresa al ganar, pero hoy **nada conecta una victoria con su progreso**: HU-08 sabe cuánto cuesta subir de nivel y cómo acumular experiencia, y HU-24 sabe producir un número aleatorio uniforme, pero no existe la pieza que, ante una derrota de un rival, obtenga la tirada, calcule la recompensa y la acredite.

HU-09 es esa pieza, y su dificultad no está en la fórmula —que es trivial— sino en **respetar tres fronteras a la vez**: la aleatoriedad es de Combat, el cálculo es de Missions y el estado del héroe es de Player/Inventory.

## 2. Alcance

**Entra:** la recompensa de experiencia `10 × 1,2^(1d8)` por derrota de un rival en una misión JvE, su tirada autoritativa, su cálculo, su acreditación idempotente y la representación de su estado.

**No entra:** PvP («Jugar Online»), la recompensa por misión completada (HU-10), la caída de objetos (HU-30), la épica por derrota de Máster (HU-32/HU-73), el multiplicador de estadísticas por nivel (`CA-06` de HU-08) y el flujo de misión completo (HU-70, HU-71, HU-72, HU-74).

## 3. Caso de uso

- **Identificador:** `UC-HU09-01` — Otorgar experiencia por derrota de un rival.
- **Actor:** el **sistema**, no el jugador. Lo dispara el cierre de un enfrentamiento JvE ganado; el jugador es el beneficiario, no el que invoca.
- **Objetivo:** que el héroe que ganó reciba la experiencia que le corresponde y, si con ella alcanza el umbral, suba de nivel.
- **Precondiciones:**
  - existe un enfrentamiento JvE con resultado de victoria sobre un rival;
  - el héroe beneficiario está identificado (`heroId`) y pertenece a un jugador (`playerId`);
  - el motor de aleatoriedad de Combat está disponible.
- **Entrada:** el hecho de la derrota del rival (misión, simulación, héroe, rival y momento).
- **Flujo principal (victoria válida):**
  1. Missions determina que hubo **victoria válida** sobre un rival y crea la recompensa en estado `PENDING`.
  2. Missions pide la tirada a Combat con un `operationId` determinista.
  3. Combat obtiene el `1d8` del motor centralizado, **lo persiste** y lo devuelve.
  4. Missions calcula `10 × 1,2^(1d8)`, lo redondea a entero y persiste el importe (`ROLLED`).
  5. Missions acredita el importe en Player/Inventory con el `operationId` determinista.
  6. Player/Inventory acumula la experiencia, recalcula el nivel con la tabla de HU-08 y confirma.
  7. Missions marca la recompensa como `CREDITED` y la refleja en el reporte.
- **Flujos alternativos:**
  - **A1 — Sin victoria válida (`CA-08`):** no se crea recompensa, no se pide tirada y no se acredita nada.
  - **A2 — Beneficiario inexistente (`heroId` nulo o participante `AI`):** no hay recompensa.
  - **A3 — Reintento:** cada paso se repite con el **mismo** `operationId`; se obtiene el mismo resultado y no se consume azar de nuevo.
  - **A4 — Rechazo terminal (`422`):** la recompensa queda `FAILED`; la misión **no** se revierte.
  - **A5 — Dependencia no disponible (`503`):** la recompensa se queda en su estado de origen y el barrido reintenta.
- **Postcondiciones:** el acumulado del héroe creció exactamente una vez por victoria; el nivel es el que corresponde a ese acumulado según la tabla de HU-08; el estado de la recompensa es terminal o está pendiente de reintento, nunca indefinido.
- **Reglas:** `RF-09` y `CA-01` a `CA-08`. `CA-09` es la condición de aceptación de la HU y no se convierte en escenario.

## 4. Modelo de dominio

```text
Missions
  ExperienceReward                 (agregado propio, por recompensa)
    enrollmentId, simulationId, heroId, playerId
    rivalRef, roll?, amount?, state, attempts, failureReason?

  ExperienceRewardPolicy           (política pura, dueño único de la fórmula)
    rewardFor(roll: 1..8) -> entero

Combat
  ExperienceRollPolicy             (política pura; consume el motor, no la fórmula)
    rollFor(sequence) -> 1..8

Player/Inventory
  ExperienceGrant                  (ledger insert-only, _id = operationId)
  HeroProgression                  (HU-08: acumulado + nivel, ya implementado)
```

Decisiones de modelado:

- **La recompensa es un agregado de Missions**, no un campo del reporte ni del héroe. Tiene ciclo de vida propio (pendiente mientras se reintenta) y estado que sobrevive al reinicio, exactamente como el `RewardWorkflow` de HU-22 en Combat.
- **La tirada no se guarda en Missions como fuente de verdad**: se guarda el importe calculado. La tirada vive en Combat, que es quien la produjo y quien debe poder repetirla sin volver a consumir el cursor.
- **El importe se persiste antes de acreditar.** Si Missions cae entre el cálculo y la acreditación, el reintento usa el importe guardado y **no** vuelve a tirar ni a calcular distinto.
- **Missions no guarda el nivel ni el acumulado del héroe.** Es estado de otro contexto; lo devuelve Player/Inventory y se representa, no se copia.

## 5. Fronteras

| Frontera | Regla | Por qué |
| --- | --- | --- |
| **HU-08 ↔ HU-09** | HU-09 no calcula umbrales ni niveles: usa `HeroProgression.awardExperience`, que ya acumula, recalcula con la tabla y no descarta experiencia en el nivel 8 | Duplicar la tabla rompería el «único punto conceptual» que HU-08 sostiene |
| **HU-24 ↔ HU-09** | El `1d8` se obtiene **solo** del motor de Combat; Missions no tiene generador | `ADR-021` da la exclusiva de la aleatoriedad a Combat |
| **HU-09 ↔ HU-10** | HU-09 es la XP **por derrota**; HU-10 la recompensa de **misión completada**, incluida su línea `EXPERIENCE` en el reporte | Son dos hechos distintos con la misma moneda |
| **HU-09 ↔ HU-72** | HU-09 **no** modifica el contrato de simulación: pide la tirada en una operación propia | El contrato de HU-72 sigue siendo una propuesta abierta (PR #132) |
| **HU-09 ↔ HU-74** | HU-09 escribe el estado de su línea de recompensa; no genera la foto del reporte | El reporte es inmutable y las recompensas tienen estado aparte (`P-T2` de HU-74) |
| **HU-09 ↔ Web** | Web no calcula nada: representa el estado de la recompensa y el nivel que le llegan | Es la regla de continuidad del proyecto |

## 6. Decisiones y su justificación

| # | Decisión | Motivo | Alternativa descartada |
| --- | --- | --- | --- |
| D-1 | La tirada se produce en una operación propia de Combat, no dentro de la simulación de HU-72 | Desacopla HU-09 de un contrato sin mergear y evita tirar cuando no hay derecho a recompensa | Extender la respuesta de simulación: la habría acoplado al PR #132 |
| D-2 | Missions calcula la fórmula | Es la aclaración del PO y deja la aritmética donde vive el hecho | Que la calculara Combat: habría metido la progresión del héroe en el dominio de combate |
| D-3 | Player/Inventory recibe un importe **entero** y rechaza lo que no lo sea | El redondeo es parte de la fórmula, no de la frontera | Redondear en Player/Inventory: repartiría la regla en dos servicios |
| D-4 | El endpoint interno se acota con `@InternalCallers('missions')` en lugar de ampliar el allow-list global | Permiso mínimo suficiente sobre una ruta concreta | Añadir `missions` a la lista global: daría acceso a todas las rutas internas |
| D-5 | La recompensa se persiste antes de cada efecto remoto | Sin eso, un reinicio dejaría una tirada sin recompensa o una recompensa sin traza | Reintentar recalculando: volvería a consumir el cursor de azar |
| D-6 | El `operationId` es determinista y se reutiliza en cada reintento | Es lo que hace que un reintento no duplique experiencia | Un identificador por intento: duplicaría la recompensa |

## 7. Riesgos

| # | Riesgo | Impacto | Mitigación |
| --- | --- | --- | --- |
| R-1 | Implementar un generador propio para el `1d8` | **Crítico**: viola `ADR-021` y las guardas estáticas del proyecto | Guarda de azar en Combat + revisión |
| R-2 | Duplicar la fórmula en dos servicios | Alto: dos verdades que se desincronizan | Un único dueño y prueba de no-duplicación |
| R-3 | Volver a tirar en un reintento | Alto: recompensa distinta por el mismo hecho | Tirada persistida antes de responder, con `operationId` |
| R-4 | Acreditar dos veces | Alto: progresión inflada | Ledger con `_id = operationId` y transacción |
| R-5 | Dar la recompensa por concedida antes de estarlo | Medio: el jugador ve algo que no ocurrió | Estado explícito (`PENDING`/`CREDITED`/`FAILED`) en el reporte |
| R-6 | Implementar antes de que exista el flujo de misión | Alto: trabajo que no se puede integrar | HU-09.4 bloqueada por `HU-72.2` y `HU-74.2` |
| R-7 | Asumir que una victoria sube de nivel | Medio: `1d8 = 8` da `43` y el primer umbral es `200` | Documentado en el contrato; la prueba lo fija |

## 8. Lo que este diseño NO afirma

- **No** afirma que HU-09 esté implementada: no hay código en `develop` en ningún repositorio.
- **No** declara la HU aceptada: eso exige revisión por pares y del PO.
- **No** da por aprobado el contrato de simulación de HU-72 ni el reporte de HU-74: ambos son propuestas abiertas y aquí solo se referencian.
- **No** cierra `P-1`, `P-2` ni `P-3`: quedan registradas como decisiones abiertas del PO.
- **No** promete que HU-09 pueda cerrarse en el Sprint 2 con el alcance acordado, porque la cadena de Misiones de la que depende no está implementada.
