# Contrato HU-22 — Créditos de victoria y cofre de recompensa (v1)

- **Estado:** diseño de la Task [#427](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/427). Lo que dice «implementado» solo lo está cuando lo integran las Tasks [#428](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/428) (Wallet), [#429](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/429) (Combat), [#430](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/430) (Player-Inventory) y [#431](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/431) (Web); la validación integrada es la Task [#432](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/432). Hasta entonces todo lo de este documento es **diseño**.
- **Historia:** [HU-22 #69](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/69) · RF-22 · [EPIC-06 #6](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/6) · Team Alfa (Combat/Player-Inventory/Web) + Team Gama (Wallet, ADR-019) · `ACT-06 Combatir y progresar` → `Finalizar y recompensar`.
- **Bloqueada por:** HU-21 (#65), **cerrada**. Consume su notificación `BattleFinishedNotification` (contrato [hu-21-battle-finish-v1](hu-21-battle-finish-v1.md) §9) sin reabrirla.
- **Arquitectura aplicada, sin reabrirla:** [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md) (Wallet única fuente de verdad del saldo y del progreso; Combat único dueño de la aleatoriedad; reservas con caducidad, no transacción distribuida), [ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md) (`RandomSequencePort`, índice uniforme; **no** se reabre el generador ni la tabla de HU-25, se reutiliza el mismo puerto para un uso distinto).
- **Aclaraciones funcionales del PO:** registradas en [Management #69](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/69) (comentario "📌 Aclaraciones funcionales previas" + comentario de cierre de hard gates del 2026-09-22). Este documento las convierte en contrato; no redefine ninguna.
- **Diagramas:** [secuencia](../diagrams/hu-22-sequence-reward.puml), [actividad](../diagrams/hu-22-activity-reward.puml), [estados del workflow](../diagrams/hu-22-state-reward-workflow.puml).
- **Reward table versionada:** [hu-22-reward-table-v1.json](hu-22-reward-table-v1.json).

## 1. Qué exige la HU y qué no

**Requisito explícito (RF-22, Issue #69):**

- victoria 1 contra 1 → el ganador recibe **2 créditos totales**; victoria grupal → **4 créditos totales** para cada jugador del equipo ganador; el resto de participantes → **1 crédito por participar**.
- solo los créditos obtenidos por **victoria** alimentan el progreso hacia el cofre.
- al llegar a **20** créditos de progreso de victoria se entrega un cofre y el progreso **vuelve a 0**, sin conservar remanente.
- máximo **2 cofres por semana**; semana = lunes 00:00 → domingo 23:59:59, zona horaria `America/Bogota`.
- al llegar a 2/2 cofres en la semana, el progreso de victoria se **congela y queda en 0** hasta que la semana cambie (no genera un tercer cofre esa semana ni seguirá acumulando de fondo).
- el cofre es de **reveal inmediato**: Combat selecciona la recompensa con el motor centralizado de HU-24 y Player-Inventory la recibe directamente como producto; no existe un ítem "cofre" persistente en el inventario.
- Web debe mostrar, en la misma pantalla de resultado de HU-21: victoria/derrota, créditos obtenidos, saldo, progreso del cofre, límite semanal, cofre (si corresponde), recompensa real y confirmación de inventario; un refresh/reconnect debe reproducir exactamente el mismo resultado.

**Ya resuelto por HU-21 y reutilizado tal cual, sin reabrirlo:**

- `BattleFinishedNotification` (contrato HU-21 §9) ya trae, por participante, el campo `credits` — el **derecho** de 2/4/1 según `BattleCreditsPolicy` (Combat, `src/domain/policies/BattleCreditsPolicy.ts`, ya implementada e íntegra: `AI` → `null`, `WON` → 2 en duelo / 4 en grupo, cualquier otro resultado (`LOST` o `NO_WINNER`) → 1). **HU-22 no reimplementa esta política**: la consume.
- HU-21 aclara expresamente que ese `credits` es un derecho publicado, **no una acreditación**: Combat no tiene API de acreditación y Wallet no tiene todavía ninguna ruta de negocio. HU-22 es la primera historia que cierra ese circuito.

### Clasificación de lo decidido

| # | Tipo | Contenido |
| --- | --- | --- |
| 1 | Requisito explícito | Reglas de créditos (2/4/1), threshold 20, reset sin remanente, límite 2/semana, semana lunes–domingo. |
| 2 | Aclaración formal del PO ([Management #69](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/69), 2026-09-22) | Timezone `America/Bogota`; tabla de recompensas (§5, 40 productos reales del Catalog, pesos 60/30/10 por tier); regla post-2/2 = progreso se congela en 0 hasta la semana siguiente; cofre = reveal inmediato. |
| 3 | Decisión arquitectónica `Accepted`, reutilizada | ADR-019 (ownership, reservas con caducidad, HMAC interno), ADR-021 (`RandomSequencePort`, índice uniforme). |
| 4 | Contrato existente, reutilizado sin cambios de forma | `BattleFinishedNotification`/`creditEntitlements` (Combat, HU-21); `POST /api/internal/v1/inventory/grants` (Player-Inventory, HU-59/HU-69, `docs/purchase-grants.md`). |
| 5 | Decisión técnica interna (este documento) | Forma exacta de los DTO internos Combat↔Wallet, estados del workflow de recompensa, mapeo de `RandomIndex` a tier de la reward table. |
| 6 | Fuera de alcance | HU-23 (apuesta, `configuredReward`), HU-30 (caída de ítems), HU-10 (recompensa de misión), productos premium/épicos/héroes en el cofre, cualquier cambio a HU-21 o a HU-24/25/26. |

## 2. Ownership (recap de ADR-019, no se reabre)

| Contexto | Dueño de |
| --- | --- |
| **Wallet** | Saldo, ledger insert-only, progreso de créditos de victoria (`victoryProgress`), contador de cofres semanales. Calcula su propio estado; nunca recibe un balance/progress/weeklyCount ya calculado por Combat. |
| **Combat** | `BattleResult`, coordinación post-batalla, aleatoriedad (HU-24/25), selección de la recompensa del cofre, workflow de recompensa (orquestador), eventos realtime de batalla. |
| **Player-Inventory** | Qué productos posee el jugador, cantidades, entrega persistida e idempotente del reward. |
| **Web** | Solo presenta lo que los servicios devuelven; no calcula economía. |
| **Infrastructure** | Este contrato, los diagramas y la reward table versionada. |

Prohibido (ADR-019, reforzado aquí): Combat no lee PostgreSQL de Wallet ni Mongo de Player-Inventory; Wallet no escribe Mongo de Inventory; Player-Inventory no escribe Wallet; Web no toca ninguna base de datos.

## 3. Contrato Combat → Wallet (nuevo, interno)

```text
POST /api/internal/v1/wallet/credits/battle-reward
```

Sigue el esquema ya vigente de ADR-019: cabeceras `x-internal-service: combat`, `x-internal-timestamp`, `x-internal-signature` (HMAC-SHA256 sobre JSON canónico, ventana de 30 s), secreto `INTERNAL_SERVICE_AUTH_SECRET`, lista cerrada de servicios autorizados (`combat`), bloqueo en Caddy de `/api/internal*`.

**Cuerpo de la solicitud** (uno por participante `HUMAN`; Combat no llama por `AI`, que no tiene `credits`):

```jsonc
{
  "operationId": "battle:{roomId}:player:{playerId}:credit", // determinista, UUID v5 sobre esa cadena
  "playerId": "cognito-sub-del-jugador",
  "battleId": "roomId de Combat",
  "reason": "BATTLE_REWARD",
  "creditsAmount": 2, // el `credits` de BattleFinishedNotification para ese participante (2, 4 o 1)
  "victoryCreditsAmount": 2, // igual a creditsAmount si result === 'WON'; si no, 0 (participación no cuenta para el cofre)
  "occurredAt": "2026-09-22T10:06:00.000Z" // finishedAt de BattleResult
}
```

- `operationId` es **determinista** (no aleatorio): `battle:{battleId}:player:{playerId}:credit`, hasheado a UUID v5 con un namespace fijo del proyecto. Esto es lo que hace que un reintento de la misma notificación de HU-21 (semántica *al menos una vez*, §9 del contrato HU-21) nunca duplique saldo.
- `creditsAmount` es el total a acreditar (participación + victoria ya sumados, tal como lo define HU-21 — no son dos líneas separadas).
- `victoryCreditsAmount` es la porción que cuenta para `victoryProgress`. Es `0` para un perdedor o para un empate total (`NO_WINNER`, que ya reparte 1 de participación) y es igual a `creditsAmount` para un ganador.
- Wallet valida `creditsAmount` y `victoryCreditsAmount` contra el catálogo cerrado de valores válidos (`{1,2,4}` y `{0,2,4}` respectivamente) y rechaza cualquier otro con `422`: Wallet no confía en que Combat mande el monto correcto sin verificarlo, aunque Combat sea el único llamante autorizado.

### 3.1 Respuesta de Wallet

```jsonc
{
  "operationId": "…",
  "applied": true, // false si es un replay idempotente del mismo operationId+cuerpo
  "balance": 138,
  "victoryProgress": 0,
  "weeklyChestCount": 1,
  "weeklyChestLimit": 2,
  "weekIdentity": "2026-W39", // America/Bogota
  "chestEarned": true // evidencia estable: un retry del MISMO operationId devuelve el MISMO valor
}
```

- `chestEarned` se decide **una sola vez**, en la misma transacción que acredita y actualiza `victoryProgress`: se persiste junto con el movimiento del ledger, así que un retry del mismo `operationId` relee ese resultado y nunca lo recalcula. Un `chestEarned=true` no puede volverse `false` en un replay, ni al revés.
- Semántica de códigos (igual que HU-59/ADR-019): `200` con `applied` (`true` en la primera aplicación, `false` en un replay idempotente con el mismo cuerpo); `409` si el mismo `operationId` llega con un cuerpo distinto; `422` rechazo terminal (monto fuera del catálogo cerrado); `503` dependencia no disponible, reintentar con el mismo `operationId`.

## 4. Contrato Web → Wallet (nuevo, público)

```text
GET /api/v1/wallet/me
```

JWT de Cognito (token de acceso), `playerId` derivado del `sub`, nunca enviado por el cliente.

```jsonc
{
  "balance": 138,
  "victoryProgress": 0,
  "weeklyChestCount": 1,
  "weeklyChestLimit": 2,
  "threshold": 20
}
```

No expone el ledger completo (no lo pide HU-22). Este es el primer endpoint de negocio público de Wallet; hoy cualquier ruta bajo `/api/v1/wallet*` responde `404` (README de Wallet, auditado 2026-09-22).

## 5. Reward table (cofre)

Ver [hu-22-reward-table-v1.json](hu-22-reward-table-v1.json) — artefacto **versionado**, no hardcodeado en Combat. Auditoría del Catalog real en producción, 2026-09-22 (84 productos publicados, `GET /api/v1/catalog/products`, paginado completo).

| Tier | Tipo de producto | Productos elegibles | Peso combinado | Peso por producto |
| --- | --- | ---: | ---: | --- |
| `COMUN` | `ARMADURA` | 16 | 60 % | 60/16 = 3,75 % |
| `RARA` | `ARMA` | 16 | 30 % | 30/16 = 1,875 % |
| `ESPECIAL` | `ITEM` | 8 | 10 % | 10/8 = 1,25 % |

**Excluidos por regla del proyecto, no por elección arbitraria:** `HEROE` y `EPICA` (HU-22 §126–127: no se entregan desde el cofre salvo reward table explícita que los incluya, y esta no los incluye); productos `premium` (§126); productos con `printRunMode: LIMITED` (§125: no se consume stock finito automáticamente sin regla formal — no existe esa regla, así que no se arriesga inventario limitado como "Arco del Destino"); `HABILIDAD` (todas a 0 créditos en el Catalog real — no son loot con valor, quedan fuera del pool).

**Reglas del sorteo:**

- La recompensa **puede repetirse**, entre jugadores y para el mismo jugador (decisión del PO, Management #69).
- Dentro de un tier, cada producto pesa lo mismo (no hay dato de rareza individual en Catalog que justifique un peso distinto).
- El archivo JSON es la única fuente de los `productId` reales; Combat no vuelve a consultar Catalog en el momento del sorteo (evita una dependencia síncrona más en el camino crítico) pero si el contrato de Catalog cambia (producto archivado, etc.) esta tabla debe regenerarse — ver §9, `TERMINAL_FAILURE` si el `productId` seleccionado ya no es válido en el grant.
- **Versión:** `schemaVersion: "1"`. Cualquier cambio de pesos, tipos o exclusiones es una **nueva versión** de este archivo con su propia fecha de auditoría, nunca una edición silenciosa del array de productos.
- **Filas:** cada uno de los 40 productos tiene un tramo contiguo (`firstRow`–`lastRow`) dentro de **1–8000** — 300 filas por `ARMADURA` (16 × 300 = 4800 = 60 %), 150 por `ARMA` (16 × 150 = 2400 = 30 %), 100 por `ITEM` (8 × 100 = 800 = 10 %). Es el **mismo espacio de 8000 filas** que `EffectControlTable` (HU-25), no uno nuevo — ver §6.

## 6. RNG de la recompensa (reutiliza HU-24, no lo reabre — corregido 2026-09-22)

Combat ya posee `RandomSequencePort` (ADR-021): una secuencia con estado, `nextIndex()` devuelve un `RandomIndex`, **siempre en `1..8000` por construcción** (`RandomIndex.MIN`/`MAX`, HU-24). Ese rango **no es configurable por llamada** — no existe una forma de pedirle al puerto un índice uniforme en otro espacio (p. ej. `1..10000`). Una versión anterior de este contrato proponía un espacio de 10000 con dos sorteos (tier y luego producto); **se descarta**: no hay forma de obtener ese espacio del puerto real sin extenderlo, y extenderlo tocaría HU-24, que este contrato explícitamente no reabre.

**Diseño corregido: una única llamada, mismo espacio de 8000 que HU-25.**

```text
RandomSequencePort.nextIndex() ──► RandomIndex (1..8000) ──► RewardTable.resolve(index) ──► producto (uno de los 40 leaf de hu-22-reward-table-v1.json)
```

- `RewardTable` es una estructura de dominio nueva en Combat, **construida en memoria a partir del JSON versionado**, con el mismo patrón de "rangos contiguos" que `EffectControlTable` (HU-25): 40 tramos fijos y ordenados, sin huecos ni solapes, que cubren exactamente `1–8000`. `resolve(index)` es una función pura, sin RNG propio, igual que `EffectControlTable.resolve`.
- Una **única** llamada a `nextIndex()` por cofre resuelve directamente el producto — no hay un segundo sorteo "dentro del tier": los 40 tramos ya están al nivel de producto individual, con el peso por producto ya incorporado en su ancho de tramo (300/150/100 filas).
- Es una **secuencia propia del `RewardWorkflow`**, independiente de la que resolvió daño/crítico de esa misma batalla (no se reutiliza el cursor de la tabla de efectos de HU-25 ni se reinicia el generador): la fábrica de secuencias de Combat crea la que corresponde al workflow de recompensa, con su propia semilla derivada según la misma política que ya use Combat para crear secuencias de batalla (sin novedad de ADR-021, que deja la política de semilla por agregado como pendiente de implementación runtime, no como bloqueo de HU-22).
- **No** se usa `Math.random`, `node:crypto` como selector, ni una segunda instancia de MT19937/Box-Müller fuera de ese puerto. **No** se expone el índice ni la semilla a Web ni a Player-Inventory.

## 7. Contrato Combat → Player-Inventory (reutilizado, ampliado en el allow-list)

Se reutiliza **sin cambiar su forma** el contrato ya implementado de HU-59/HU-69 (`docs/purchase-grants.md`, Player-Inventory):

```text
POST /api/internal/v1/inventory/grants
```

```jsonc
{
  "operationId": "battle:{battleId}:player:{playerId}:chest:1:grant", // determinista, UUID v5
  "playerId": "cognito-sub-del-jugador",
  "items": [{ "productId": "<productId real del tier sorteado>", "quantity": 1 }]
}
```

**Corrección (2026-09-22, tras auditar el código y no solo la documentación):** el allow-list de `x-internal-service` en Player-Inventory **ya incluye `combat`** desde HU-15 (#31, héroe equipado) — `docs/purchase-grants.md` decía "solo `commerce`" pero ese texto estaba desactualizado. El `InternalServiceGuard` es **global** a toda ruta `@InternalOnly()` del servicio, no por ruta, así que `combat` ya podía llamar `POST /internal/v1/inventory/grants` sin ningún cambio de código. La Task #430 (PR [#40](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/40)) documenta esta capacidad ya existente y añade una prueba de regresión; **no se crea un segundo endpoint de grants ni se modifica el allow-list**.

`operationId` incluye una secuencia (`chest:1`, `chest:2`, …) porque un jugador puede ganar más de un cofre a lo largo de distintas batallas de la misma semana; dentro de una sola resolución de cofre el número de secuencia es siempre `1` salvo que HU-22 evolucione a entregar más de un ítem por cofre (no lo hace).

## 8. Workflow distribuido (orquestado por Combat)

```text
BattleResult terminal (HU-21)
        ↓
RewardWorkflow CREATED (persistido con la sala, antes de llamar a nadie)
        ↓
Wallet requested (POST §3)
        ↓
Wallet credited (CREDIT_CONFIRMED)
        ↓
chest?
   no → COMPLETED
   sí (CHEST_ELIGIBLE)
        ↓
reward selected (REWARD_SELECTED, persistido antes de llamar a Inventory)
        ↓
Inventory grant requested (POST §7)
        ↓
Inventory confirmed (COMPLETED)
        ↓
señal a Web (§10)
```

No es una transacción distribuida ACID: es un saga local con idempotencia en cada paso (mismo patrón de "reserva, confirmación o cancelación" de ADR-019, adaptado — aquí no hay reserva porque acreditar no es reversible por regla de negocio: una vez que Wallet confirma el crédito, Combat no lo revierte aunque el grant falle, ver §9).

### 8.1 Estados

| Estado | Significa | Se recupera tras reinicio |
| --- | --- | --- |
| `PENDING_CREDIT` | `RewardWorkflow` persistido, aún no se llamó a Wallet | Reintenta `POST §3` con el mismo `operationId` |
| `CREDIT_CONFIRMED` | Wallet respondió, `chestEarned=false` | Transiciona a `COMPLETED` |
| `CHEST_ELIGIBLE` | Wallet respondió `chestEarned=true`, aún no se sorteó | Sortea con el mismo workflow (no repite la llamada a Wallet) |
| `REWARD_SELECTED` | Producto elegido y persistido, aún no se llamó a Inventory | Reintenta `POST §7` con el mismo `operationId` y el **mismo** `productId` ya persistido (no vuelve a sortear) |
| `INVENTORY_PENDING` | Se llamó a Inventory, sin confirmación aún | Reintenta la misma llamada |
| `COMPLETED` | Terminal, con o sin cofre | No-op |
| `RETRYABLE_FAILURE` | `503`/timeout en el último paso | Reintenta el mismo paso con backoff acotado |
| `TERMINAL_FAILURE` | `422` u otro rechazo terminal (ej. `productId` ya no existe en Catalog) | No reintenta solo; requiere intervención (queda visible en observabilidad, Web muestra `rewardDelivery: PENDING` honestamente, nunca "entregado" en falso) |

Cada transición se persiste (misma base de Combat, MongoDB, junto a la sala o en una colección `reward_workflows` propia) **antes** de avanzar al siguiente paso, para que un reinicio de Combat recupere el workflow exactamente donde quedó (igual criterio que HU-21 §7 y ADR-019 "el estado vive en la base, no en el temporizador").

## 9. Matriz de fallos parciales

| Punto de falla | Estado persistido tras el fallo | Retry | Resultado visible en Web |
| --- | --- | --- | --- |
| Combat termina la batalla pero cae antes de llamar a Wallet | `PENDING_CREDIT` | Sí, mismo `operationId` | `rewardDelivery: PENDING` (créditos aún no confirmados) |
| Wallet acredita pero Combat cae antes de leer la respuesta | Wallet ya aplicó (idempotente); Combat reintenta y Wallet devuelve el mismo resultado (`applied:false`) | Sí | Ninguno perdido: el replay trae el mismo `chestEarned` |
| Wallet confirma cofre pero Combat cae antes de seleccionar | `CHEST_ELIGIBLE` | Sí, el mismo workflow reanuda el sorteo (no vuelve a llamar a Wallet) | `rewardDelivery: PENDING` |
| Combat selecciona pero cae antes de llamar a Inventory | `REWARD_SELECTED` (con `productId` ya persistido) | Sí, mismo `operationId`, mismo `productId` — **no** se vuelve a sortear | `rewardDelivery: PENDING`, cofre ya "ganado" pero sin confirmar entrega |
| Inventory entrega pero Combat cae antes de marcar `COMPLETED` | Inventory ya aplicó (idempotente); Combat reintenta y recibe el mismo resultado | Sí | Ninguno perdido |
| Combat completa pero el socket cae | `COMPLETED` en base | Web recupera por `snapshot`/consulta HTTP, no depende de haber recibido el evento realtime (§10) | Correcto tras reconectar |
| Wallet rechaza con `422` (monto fuera de catálogo cerrado) | `TERMINAL_FAILURE` | No (es un bug, no un fallo transitorio) | `rewardDelivery` nunca miente: no se muestra "entregado" |
| Inventory rechaza con `422` (`productId` ya no existe) | `TERMINAL_FAILURE` | No automático | Créditos **ya** confirmados y mostrados; reward pendiente, sin ítem falso |

Ningún fallo revierte automáticamente el saldo ya acreditado por Wallet (HU-22 §66: "NO revertir automáticamente saldo salvo que requisito lo ordene" — no lo ordena).

## 10. Cómo se entera Web

Aditivo sobre HU-21, sin tocar su semántica:

- **Realtime:** se reutiliza el socket de HU-17/18/21 (ADR-020). Tras `battleFinished` (HU-21, sin cambios), Combat publica una notificación adicional cuando el `RewardWorkflow` llega a un estado visible (`CREDIT_CONFIRMED`, `CHEST_ELIGIBLE`→`REWARD_SELECTED` mostrado junto, `COMPLETED`), como una extensión aditiva del snapshot de la sala — **no** un segundo socket ni un evento que reemplace `battleFinished`.
- **Recuperación:** si Web estuvo desconectada o hace un refresh, una consulta (`resume`/`snapshot` de Combat, igual patrón que HU-21 §6.3, o `GET wallet/me` + un endpoint de estado del `RewardWorkflow` de esa batalla) debe devolver el mismo resultado sin depender de haber recibido el evento en vivo.
- El campo visible mínimo: `creditsEarned`, `balance`, `victoryProgress`, `weeklyChestCount`, `chestEarned`, `rewardDelivery: 'NONE' | 'PENDING' | 'CONFIRMED'`, `reward: { productId, name, type, imageUrl } | null`.

## 11. Seguridad

- Interno (`Combat → Wallet`, `Combat → Inventory`): HMAC, allow-list, nunca JWT propagado servicio a servicio.
- Público (`Web → Wallet`): JWT de Cognito, `playerId` del `sub`, nunca del cuerpo/query.
- Web no puede: elegir el monto de crédito, inventar `chestEarned`, elegir la recompensa, ni llamar directamente a ninguna ruta `/api/internal*` (bloqueadas en Caddy).
- No se loguean secretos HMAC, JWT, ni el estado interno del RNG; sí se correlaciona `battleId`/`operationId`/estado del workflow.

## 12. Idempotencia (resumen)

| Operación | Clave | Reintento con mismo cuerpo | Reintento con cuerpo distinto |
| --- | --- | --- | --- |
| Combat → Wallet (crédito) | `operationId` determinista por `battleId`+`playerId` | Mismo resultado, `applied:false` | `409` |
| Combat → Inventory (grant) | `operationId` determinista por `battleId`+`playerId`+secuencia de cofre | Mismo resultado (contrato ya vigente de HU-59) | `409` |
| Web → Wallet (consulta) | No aplica (lectura) | — | — |

## 13. Fuera de alcance

HU-23 (apuesta, multiplicador, `configuredReward`), HU-30 (caída de ítems), HU-10 (recompensa de misión), productos premium/épicos/héroes en el cofre, feature flags (no se introduce ninguno), circuit breaker (timeouts + retry acotado bastan, §135 del prompt), cambios a HU-21/HU-24/HU-25/HU-26.

## 14. Compatibilidad y orden de despliegue

Aditivo: ningún mensaje de HU-13/17/18/19/21 cambia de forma. **Orden:** Infrastructure (este contrato) → Wallet (migraciones propias) → Player-Inventory (ampliar allow-list) → Combat (`npm run migrate` si aplica, y `npm run migrate` 007 pendiente de Combat #29 según auditoría previa de HU-18) → Web. Combat no debe llamar a un contrato que Wallet/Inventory todavía no exponen: desplegar Wallet e Inventory antes de activar la orquestación de Combat.
