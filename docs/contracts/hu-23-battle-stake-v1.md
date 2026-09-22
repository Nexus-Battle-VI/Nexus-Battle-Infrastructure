# Contrato HU-23 — Uso de créditos como apuesta en batalla (v1)

- **Estado:** diseño de la Task [#433](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/433). Lo que dice «implementado» solo lo está cuando lo integran las Tasks [#434](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/434) (Wallet), [#435](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/435) (Combat) y [#436](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/436) (Web); la validación integrada es la Task [#437](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/437). Hasta entonces todo lo de este documento es **diseño**.
- **Historia:** [HU-23 #70](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/70) · RF-23 · [EPIC-06 #6](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/6) · Team Alfa (Combat/Web) + Team Gama (Wallet).
- **Bloqueada por:** HU-14 (#23) y HU-21 (#65), ambas cerradas.
- **Arquitectura aplicada, sin reabrirla:** [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md) — Wallet única fuente de verdad del saldo; patrón **reserva, confirmación o cancelación** con `operationId` determinista e idempotente; **toda reserva nace con caducidad** (§«Temporizadores»); HMAC interno con lista cerrada de llamantes y bloqueo de `/api/internal*` en Caddy.
- **Contratos de los que parte:** [hu-14 (implícito en el código, sin doc propio)](#3-relación-con-roomrewardamount-hu-14-decisión-fundamentada), [hu-21-battle-finish-v1](hu-21-battle-finish-v1.md) (`BattleResult`, `BattleResultPublisherPort`), [hu-22-reward-contract-v1](hu-22-reward-contract-v1.md) (mismo punto de enganche `publish()`, mismo estilo de contrato interno Combat↔Wallet, mismo Wallet con `wallet_accounts`/`wallet_ledger`).
- **Decisiones funcionales tomadas por Dabji (2026-09-22), como PO, en esta conversación:** ver §2. Todas están marcadas **pendientes de ratificación por el PO real** salvo que el propio Dabji sea quien las cierre en el Issue.

## 1. Qué exige la HU y qué no

**Requisito explícito (RF-23, Issue #70):**

- apostar es **opcional** y solo con créditos **disponibles** del jugador;
- el jugador indica el monto al **crear o unirse** a una sala;
- los créditos apostados quedan **reservados** mientras la batalla está activa y no sirven para otra operación incompatible;
- al finalizar con un ganador válido, el monto se **transfiere al ganador**;
- si la sala se **cancela antes de iniciar**, los créditos se **liberan**;
- la operación **no duplica ni pierde** créditos en ningún paso.

**Lo que este documento decide y lo que dejó pendiente el Issue** — ver la tabla de §2.

## 2. Clasificación de lo decidido

| # | Tipo | Contenido |
| --- | --- | --- |
| D1 | Decisión del PO (Dabji, 2026-09-22, en esta conversación) | El monto es **individual**: cada jugador indica el suyo, al crear o al unirse, sin necesidad de igualar a nadie. El pozo de una batalla es la suma de lo que cada participante apostó (`0` para quien no apostó). |
| D2 | Decisión del PO | En equipo, con varios ganadores, el pozo se reparte en **partes iguales** entre los integrantes del equipo ganador, sin importar cuánto puso cada uno. |
| D3 | Decisión del PO | `NO_WINNER` (empate total, HU-21 §4.3): se **libera** a cada participante exactamente lo que apostó. Nadie gana ni pierde. |
| D4 | Decisión del PO | Las salas **PVE no admiten apuesta**: un participante `AI` no tiene cuenta en Wallet. La apuesta solo está disponible en salas JcJ (`mode: 'PVP'`). |
| D5 | Decisión del PO | Monto mínimo **1** crédito (`0` = no apostar); monto máximo = **saldo disponible** del jugador en el instante de la reserva. Sin techo adicional inventado. |
| D6 | Decisión del PO | Un `leave` de un participante en una sala de equipo **antes de iniciar** libera de inmediato SU apuesta reservada, aunque la sala siga existiendo con el resto — no hace falta que la sala completa se cancele. |
| D7 | Decisión del PO, **fundamentada con evidencia del código** (§3) | `room.reward.amount` (HU-14) y la apuesta de HU-23 son **conceptos distintos**. HU-23 añade un campo nuevo (`stake`); `reward.amount` sigue exactamente como está, sin tocarlo. |
| D8 | Decisión técnica del autor (a confirmar) | Momento de la reserva: **síncrono**, dentro del mismo comando `create`/`join` que declara el monto. Si Wallet rechaza (saldo insuficiente), el `create`/`join` completo falla — no se crea una sala ni una participación con una apuesta que no se pudo reservar. |
| D9 | Decisión técnica del autor (a confirmar) | Momento de la captura/liquidación: **después** de que HU-21 persiste `BattleResult` y difunde `battleFinished`, en el mismo punto de enganche que ya usa HU-22 (`BattleResultPublisherPort.publish()`, llamado por `BattleFinalizer.afterFinished`, después de publicar). No se toca la firma del puerto ni el orden persistir→difundir→finalizar de HU-21. |
| D10 | Decisión técnica del autor (a confirmar) | La liquidación es **una sola llamada por batalla** (`stakes/settle`, todos los participantes con apuesta en un solo cuerpo), no N llamadas independientes: así Wallet puede exigir que la suma capturada a los perdedores sea exactamente igual a la suma acreditada a los ganadores, en la MISMA transacción — el control más barato posible contra CA-07 («no duplicar ni perder créditos»). |
| D11 | Pendiente (Issue original, sin decidir aquí) | Expiración de una reserva huérfana (ADR-019: «toda reserva nace con caducidad»): propongo 24 h desde la reserva como red de seguridad — nunca debería dispararse en operación normal (una batalla dura como mucho unos minutos más el tiempo de lobby), es solo el respaldo si Combat muere sin liberar ni liquidar. **A confirmar por el PO**, aunque no cambia ningún comportamiento visible mientras no se dispare. |
| D12 | Decisión técnica del implementador (a confirmar), gap de este contrato detectado durante la implementación | **Pozo sin destinatario**: D2 reparte "entre los ganadores CON apuesta"; si NINGÚN integrante del equipo ganador apostó (pero el equipo perdedor sí), esa regla no tiene a quién aplicarse — capturar a los perdedores sin acreditar a nadie violaría la suma cero de Wallet (§8), y acreditar a un ganador que no apostó sería un premio no pactado (contradice D1). Se trata como si no hubiera resultado liquidable: se **libera** a cada quien lo suyo (mismo camino que D3/`NO_WINNER`), nadie gana ni pierde. Implementado en `stakeSettlementFor` (Combat): devuelve `null` cuando `winners.length === 0`, y el llamador libera en vez de liquidar. |

## 3. Relación con `room.reward.amount` (HU-14): decisión fundamentada

Antes de decidir D7 audité el código real, no solo el historial de comentarios:

- `RewardConfig` (Combat, `src/domain/value-objects/RewardConfig.ts`) ya advertía expresamente: *"RF-23 (apuesta de creditos, HU-23) es una historia separada y posterior que no se puede dar por identica a este campo sin confirmacion del Product Owner"*.
- El **Issue #23 (HU-14)** original dice: *"El creador debe configurar la recompensa asociada a la sala"* — una **sola** cifra, fijada **solo por el creador**, sin participación de quien se une.
- **Web ya tiene una pantalla en producción** (`CreateBattleRoomPanel.tsx`) que pide ese número al crear la sala, con la etiqueta **"Recompensa de la sala"** y el texto de ayuda **"Monto que se otorga al ganar la batalla."** — visible a los usuarios hoy mismo. No reserva nada de Wallet: es un número decorativo, sin acreditación real (HU-21 lo publica como `configuredReward` "sin semántica de entrega"; HU-22 lo dejó fuera de alcance a propósito).
- D1 (esta conversación) fija que la apuesta de HU-23 es **individual por jugador**, indicada tanto al crear como al **unirse** — una forma de dato completamente distinta (un valor por participante, no uno por sala) a la de `reward.amount` (un valor único, solo del creador).

**Conclusión:** reutilizar `reward.amount` exigiría cambiarle la forma (de "un número por sala" a "un número por participante") y la semántica (de "cosmético, sin reserva" a "reservado de verdad en Wallet"), rompiendo la etiqueta y el texto de ayuda que Web ya le muestra al usuario. Mantenerlos separados es lo único que no daña nada existente. `room.reward.amount` **no se toca** en esta HU: sigue disponible para lo que HU-14 lo definió, con su UI intacta.

## 4. Modelo de dominio

### 4.1 Wallet (dueño del dinero, ADR-019)

```ts
type StakeHoldStatus = 'ACTIVE' | 'CAPTURED' | 'RELEASED' | 'EXPIRED'

interface StakeHold {
  operationId: string      // = el `holdId`: mismo valor que identifica la reserva
  playerId: string
  battleId: string         // roomId de Combat
  amount: number           // entero positivo
  status: StakeHoldStatus
  createdAt: string
  expiresAt: string        // createdAt + 24 h (D11)
}
```

`wallet_accounts` gana una columna nueva, aditiva (migración propia de Wallet, fuera del alcance de este documento fijar el nombre exacto de columna, pero el significado es este):

- `balance`: **sin cambios de significado** — el total de créditos que el jugador posee.
- `reserved` (nueva): suma de sus `StakeHold` en `ACTIVE`. `reserved >= 0`, `reserved <= balance` (invariante, verificada en la misma transacción que cualquier cambio).
- `available` (derivado, no persistido): `balance - reserved`. Es lo único contra lo que se valida una reserva nueva.

Reservar **nunca** toca `balance` (el jugador sigue siendo dueño de sus créditos, solo deja de tenerlos disponibles). Solo **capturar** (perder la apuesta) o **acreditar** (ganarla) tocan `balance`.

### 4.2 Combat (dueño de la sala y la batalla)

Aditivo sobre `BattleRoom`/`Participant` (sin tocar la forma de HU-14/17/18/19/20/21/22):

```ts
type StakeStatus =
  | 'PENDING_RESERVE'   // Combat va a llamar a Wallet, aun no respondio
  | 'ACTIVE'            // Wallet confirmo la reserva
  | 'RESERVE_FAILED'    // Wallet rechazo (saldo insuficiente): el create/join completo fallo, no queda estado a medias
  | 'RELEASED'          // liberada (cancelacion, leave pre-inicio, o NO_WINNER)
  | 'CAPTURED'          // perdida (perdedor de una batalla con ganador)
  | 'SETTLED_WON'       // liquidada a favor (ganador de una batalla con ganador)

interface ParticipantStake {
  readonly amount: number            // > 0; ausente/0 = no aposto
  readonly holdOperationId: string   // = StakeHold.operationId en Wallet
  readonly status: StakeStatus
}
```

Cada `Participant` de `BattleRoom` (HU-14) gana un campo opcional `stake?: ParticipantStake`. Una sala **PVP con al menos un participante con `stake`** tiene una apuesta; el resto de salas no cambian de forma en absoluto (campo ausente, no `null` — mismo criterio que `BattleView.deadlines?` de HU-21).

## 5. Contrato Combat → Wallet (nuevo, interno)

Mismo esquema HMAC ya vigente (cabeceras `x-internal-service: combat`, `x-internal-timestamp`, `x-internal-signature`, secreto compartido, allow-list, bloqueo en Caddy de `/api/internal*` — igual que HU-22 §3). Reutiliza el mismo `InternalHttpClient` de Combat (`postInternalJson`) que ya firma peticiones a Wallet para HU-22.

### 5.1 Reservar

```text
POST /api/internal/v1/wallet/stakes/reserve
```

```jsonc
{
  "operationId": "battle:{battleId}:player:{playerId}:stake:reserve", // determinista, SIN hashear (mismo criterio que HU-22 §3)
  "playerId": "cognito-sub-del-jugador",
  "battleId": "roomId de Combat",
  "amount": 10,               // entero, 1..saldo disponible (D5)
  "occurredAt": "2026-09-22T10:00:00.000Z"
}
```

Respuesta `200`:

```jsonc
{
  "operationId": "…",
  "applied": true,       // false = replay idempotente del mismo operationId+cuerpo
  "holdId": "battle:{battleId}:player:{playerId}:stake:reserve", // = operationId, no hay un id separado
  "balance": 138,
  "reserved": 10,
  "available": 128
}
```

- `422` (rechazo terminal): saldo disponible `< amount`, o `amount <= 0`. El cuerpo trae `code: 'INSUFFICIENT_AVAILABLE_BALANCE'` o `'INVALID_AMOUNT'`.
- `409`: mismo `operationId` con un cuerpo distinto (otra reserva intentando reutilizar el id de una ya existente con otro monto — no debería ocurrir con el esquema determinista de un hold por jugador por batalla, pero Wallet lo rechaza igual que HU-22).
- `503`: dependencia no disponible, reintentar con el mismo `operationId`.

Un jugador solo puede tener **un** `StakeHold` `ACTIVE` por `battleId` (el propio `operationId` determinista lo garantiza: un segundo intento de reservar para la misma batalla y jugador es un replay del mismo id, nunca una reserva nueva).

### 5.2 Liberar

```text
POST /api/internal/v1/wallet/stakes/release
```

```jsonc
{
  "operationId": "battle:{battleId}:player:{playerId}:stake:release", // determinista, distinto del de reserva
  "holdId": "battle:{battleId}:player:{playerId}:stake:reserve",      // el operationId de la reserva a liberar
  "reason": "ROOM_CANCELLED" | "PARTICIPANT_LEFT" | "NO_WINNER"
}
```

Respuesta `200`: `{ operationId, applied, balance, reserved, available }`. Si el hold ya estaba `RELEASED`/`CAPTURED`/`EXPIRED`, Wallet responde el mismo resultado ya conocido (idempotente) — nunca falla por "ya liberado" ni intenta liberar dos veces.

- `422`: el `holdId` no existe. No debería ocurrir si Combat solo libera holds que él mismo reservó.

### 5.3 Liquidar (una sola llamada por batalla, D10)

```text
POST /api/internal/v1/wallet/stakes/settle
```

```jsonc
{
  "operationId": "battle:{battleId}:stakes:settle", // determinista, UNO por batalla (no por jugador)
  "battleId": "roomId de Combat",
  "settlements": [
    { "playerId": "a1", "holdId": "battle:{battleId}:player:a1:stake:reserve", "outcome": "CAPTURED", "amount": 10 },
    { "playerId": "b1", "holdId": "battle:{battleId}:player:b1:stake:reserve", "outcome": "CREDITED", "amount": 10 }
  ]
}
```

- `outcome: 'CAPTURED'`: el hold se cierra y **su monto se resta de `balance`** (el jugador pierde esos créditos de verdad). `amount` debe coincidir EXACTAMENTE con el monto original del hold — Wallet lo valida contra su propio registro, no confía en el número que Combat reenvía.
- `outcome: 'CREDITED'`: el hold del propio ganador se libera (recupera su disponibilidad, sin tocar `balance` por esa parte) **y además** se le acredita `amount` (su parte del pozo ajeno, calculada por `BattleStakePolicy` en Combat — D2). `amount` aquí es un número que Combat calcula, no necesariamente igual al monto original del hold.
- **Invariante de Wallet, verificada en la MISMA transacción:** `Σ amount de los CAPTURED == Σ amount de los CREDITED` del mismo `settlements[]`. Si no cuadra, `422` con `code: 'SETTLEMENT_NOT_ZERO_SUM'` y **nada** se aplica — es el control barato de CA-07.
- Un `outcome: 'CAPTURED'` para todos y ningún `CREDITED` no es válido (violaría la suma cero): para liberar sin ganador se usa §5.2 por cada hold, nunca `/settle` con capturas sin contrapartida.

Respuesta `200`: `{ operationId, applied, results: [{ playerId, holdId, balance, reserved, available }] }` (el estado final de cada cuenta tocada).

- `409`: mismo `operationId` con un `settlements[]` distinto.
- `422`: suma no cuadra, algún `holdId` no existe o no está `ACTIVE`, o algún `amount` de `CAPTURED` no coincide con el monto original del hold.

## 6. Contrato Web → Wallet (ampliación aditiva de HU-22 §4)

```text
GET /api/v1/wallet/me
```

Respuesta ampliada, aditiva (los campos de HU-22 no cambian):

```jsonc
{
  "balance": 138,
  "reserved": 10,        // NUEVO
  "available": 128,      // NUEVO, balance - reserved
  "victoryProgress": 0,
  "weeklyChestCount": 1,
  "weeklyChestLimit": 2,
  "threshold": 20
}
```

Web usa `available` para no dejar que la interfaz sugiera apostar más de lo que el jugador realmente puede reservar (D5) — sin reemplazar la validación autoritativa de Wallet, que es la que de verdad decide.

## 7. Integración con el ciclo de sala (Combat)

| Momento | Acción |
| --- | --- |
| `POST /rooms` (crear) con `stake.amount > 0` | Reserva síncrona (D8) antes de persistir la sala. Si Wallet rechaza, la creación completa falla con el mismo código (`422 INSUFFICIENT_AVAILABLE_BALANCE`), sin crear ninguna sala. |
| `POST /rooms/{id}/join` con `stake.amount > 0` | Igual: reserva síncrona antes de persistir la unión. Un `join` sin `stake` (o con `stake: 0`) no reserva nada — apostar es opcional por participante, no por sala (D1). |
| Sala **PVE** (`mode: 'PVE'`) con `stake` en la petición | Rechazada con `422` (`STAKE_NOT_ALLOWED_IN_PVE`, D4). No es un error de Wallet: Combat ni siquiera llama a Wallet. |
| `POST /rooms/{id}/cancel` (antes de iniciar) | Libera TODOS los holds `ACTIVE` de la sala (uno por participante con apuesta), vía §5.2, `reason: 'ROOM_CANCELLED'`. |
| `leave` de un participante en una sala de equipo, antes de iniciar | Libera SOLO el hold de ESE participante (D6), vía §5.2, `reason: 'PARTICIPANT_LEFT'`. El resto de la sala sigue como está. |
| `start` (batalla pasa a `IN_BATTLE`) | No hace nada nuevo: los holds ya están `ACTIVE` desde que se crearon/unieron. |
| `battleFinished` (HU-21, `outcome: 'WIN'`) con al menos un `stake` en la sala | Después de publicar (D9): calcula el reparto (D2, `BattleStakePolicy`, puro, análogo a `BattleCreditsPolicy`) y llama a §5.3 UNA vez con todos los participantes que apostaron. |
| `battleFinished` con `outcome: 'NO_WINNER'` | Después de publicar: libera TODOS los holds de la sala vía §5.2, `reason: 'NO_WINNER'` (D3) — no se llama a `/settle`. |
| `battleFinished` en una sala **sin ningún** `stake` | No se llama a Wallet en absoluto (ni reserva, ni liberación, ni liquidación existieron). |

**Reintento y recuperación:** igual criterio que `RewardWorkflow` (HU-22 §8): la intención (reservar/liberar/liquidar) se persiste en el propio `Participant.stake.status` ANTES de llamar a Wallet (`PENDING_RESERVE` antes del `POST reserve`, etc.), así que un reinicio de Combat retoma exactamente donde quedó sin perder ni repetir con otro `operationId`. El barrido existente (`IntervalRewardWorkflowScheduler` o uno análogo) reintenta cualquier `stake` que quedó en un estado no terminal.

## 8. Atomicidad, idempotencia y concurrencia

- Wallet sigue el patrón ya probado de HU-22: `pg_advisory_xact_lock(hashtext(operationId))` serializa reintentos de la MISMA operación; `pg_advisory_xact_lock(hashtext(playerId))` serializa operaciones CONCURRENTES sobre la MISMA cuenta (necesario porque dos batallas del mismo jugador podrían reservar o liquidar casi a la vez).
- `/settle` toca varias cuentas en una sola transacción: los `pg_advisory_xact_lock` de cada `playerId` se adquieren en **orden determinista** (ordenados por `playerId` como texto) para que dos liquidaciones que compartan un jugador (no debería pasar dentro de una sola batalla, pero sí entre batallas simultáneas del mismo jugador) nunca puedan producir un interbloqueo.
- Ningún fallo de Wallet revierte la batalla (igual regla que HU-21 §9 y HU-22 §9): el resultado de la batalla ya está persistido y difundido antes de tocar Wallet; un fallo se reintenta, nunca deshace `battleFinished`.
- **CA-07 (no duplicar ni perder créditos):** garantizado por (a) `operationId` determinista + idempotencia en cada uno de los tres endpoints, (b) la invariante de suma cero de `/settle` en una sola transacción, (c) que reservar nunca toca `balance` (solo `reserved`), así que un hold huérfano nunca puede perder ni crear crédito, solo quedar bloqueado hasta que se libere o expire.

## 9. Matriz de fallos parciales

| Punto de falla | Estado persistido en Combat | Retry | Visible en Web |
| --- | --- | --- | --- |
| Combat cae antes de llamar a `reserve` | `PENDING_RESERVE` | Sí, mismo `operationId`; si el `create`/`join` en sí no se completó, no queda sala a medias (D8: síncrono, todo o nada) | La petición de crear/unirse nunca respondió `200`; el cliente reintenta la acción completa |
| Wallet reserva pero Combat cae antes de leer la respuesta | Wallet ya aplicó (idempotente); Combat reintenta y recibe el mismo resultado | Sí | Ninguno perdido |
| Combat cae entre `battleFinished` y liberar/liquidar | El `Participant.stake.status` sigue en `ACTIVE` (nunca se marcó `PENDING_*`) | El barrido de recuperación al arrancar (mismo patrón que `ReconcileRewardWorkflows`, HU-22 §8.1) detecta salas `FINISHED` con `stake.status: ACTIVE` y dispara la liberación/liquidación pendiente | `stakeDelivery: PENDING` hasta que se resuelva |
| Wallet rechaza `/settle` con `422` (suma no cuadra) | Es un **bug** de `BattleStakePolicy`, no un fallo transitorio: se registra y NO se reintenta solo | Requiere intervención | `stakeDelivery: FAILED`, créditos de la batalla (HU-22) sin afectar — son sistemas independientes |
| Reserva huérfana (Combat muere y nunca libera ni liquida) | — | La expiración de 24 h (D11) la libera automáticamente por el barrido de Wallet | El jugador recupera su disponible sin intervención manual, con un retraso máximo de 24 h |

## 10. Seguridad

- Interno (`Combat → Wallet`): HMAC, allow-list, nunca JWT propagado — igual que HU-22 §11.
- Público (`Web → Wallet`): JWT de Cognito, `playerId` del `sub`, nunca del cuerpo — igual que HU-22 §11.
- Web **no puede**: elegir cuánto reservar sin que Wallet lo valide, ver el saldo de otro jugador, ni llamar directamente a `/api/internal*` (bloqueadas en Caddy).
- Combat expone a Web solo `stake.amount` y `stake.status` del PROPIO jugador (nunca de un rival, salvo el resumen agregado del pozo si el diseño de Web lo necesita — sin desglosar cuánto puso cada rival individualmente).
- No se loguean secretos HMAC ni JWT; sí se correlaciona `battleId`/`operationId`/`playerId` (sin nombre) en los registros, igual criterio que HU-21 §11 y HU-22 §11.

## 11. Errores

Códigos nuevos, todos `422` salvo que se indique otra cosa:

| Código | Cuándo |
| --- | --- |
| `INSUFFICIENT_AVAILABLE_BALANCE` | El monto pedido supera el disponible del jugador (Wallet, en `reserve`) |
| `INVALID_AMOUNT` | `amount <= 0` o no entero |
| `STAKE_NOT_ALLOWED_IN_PVE` | Se intentó apostar en una sala `PVE` (Combat, antes de llamar a Wallet) |
| `SETTLEMENT_NOT_ZERO_SUM` | La suma de `CAPTURED` no coincide con la de `CREDITED` en `/settle` (Wallet) |
| `HOLD_NOT_FOUND` | `holdId` inexistente en `/release` o `/settle` |
| `HOLD_AMOUNT_MISMATCH` | Un `CAPTURED` de `/settle` no coincide con el monto original del hold |

`409`/`503` siguen la semántica ya vigente de ADR-019/HU-22: `409` = mismo `operationId` con cuerpo distinto; `503` = reintentar con el mismo `operationId`, nunca asumir que no ocurrió.

## 12. Matriz de escenarios (base de las pruebas)

| # | Escenario | CA |
| --- | --- | --- |
| S-01 | Crear sala 1v1 con apuesta válida → reserva confirmada, `available` baja exactamente ese monto | CA-01, CA-02, CA-03 |
| S-02 | Unirse con apuesta válida a una sala ya creada (con o sin apuesta del creador) | CA-01, CA-02 |
| S-03 | Apostar más del disponible → `422 INSUFFICIENT_AVAILABLE_BALANCE`, sala/unión NO se crea, nada reservado | CA-01, CA-07 |
| S-04 | Crear/unirse sin apuesta (`amount` ausente o `0`) → ningún hold, comportamiento igual al de antes de HU-23 | CA-01 |
| S-05 | Cancelar sala antes de iniciar, con apuestas activas → todas se liberan, `reserved` vuelve a 0 | CA-06 |
| S-06 | `leave` de un participante en sala de equipo antes de iniciar → SOLO su hold se libera; el resto sigue reservado | CA-06 |
| S-07 | Batalla 1v1 con apuesta, termina con ganador → perdedor captured (`balance` baja), ganador credited (`balance` sube exactamente lo mismo) | CA-01, CA-05, CA-07 |
| S-08 | Batalla 2v2 con apuestas distintas por jugador, un equipo gana → pozo perdedor se reparte en partes IGUALES entre los ganadores (D2), sin importar cuánto puso cada uno | CA-05 |
| S-09 | Batalla termina en `NO_WINNER` → todos los holds se liberan, ningún `balance` cambia | CA-01, CA-06 |
| S-10 | Batalla termina por `DISCONNECTION` (HU-21) → se liquida igual que cualquier `outcome: WIN` (el desconectado pierde su apuesta, el rival la recibe) | CA-05 |
| S-11 | Sala sin ninguna apuesta finaliza → Wallet nunca recibe ninguna llamada de `/stakes/*` | CA-01 |
| S-12 | Reintentar `reserve`/`release`/`settle` con el mismo `operationId` y mismo cuerpo → mismo resultado, sin duplicar ni perder crédito (`applied:false`) | CA-07 |
| S-13 | Reintentar con el mismo `operationId` y OTRO cuerpo → `409`, nada se aplica | CA-07 |
| S-14 | Dos reservas concurrentes del mismo jugador en dos batallas que juntas superarían su disponible → una pasa, la otra `422` (nunca las dos) | CA-04, CA-07 |
| S-15 | `/settle` con una suma que no cuadra (bug simulado) → `422 SETTLEMENT_NOT_ZERO_SUM`, NADA se aplica (ni capturas ni créditos parciales) | CA-07 |
| S-16 | Sala PVE con `stake` en la petición → `422 STAKE_NOT_ALLOWED_IN_PVE`, Wallet nunca se llama | CA-01 |
| S-17 | Combat se reinicia con una sala `FINISHED` cuyo `stake.status` sigue `ACTIVE` (murió antes de liquidar) → la recuperación al arrancar completa la liquidación pendiente, sin duplicar | CA-07 |
| S-18 | Wallet expone `GET /wallet/me` con una reserva activa → `available` refleja el descuento; `balance` NO cambia solo por reservar | CA-03, CA-04 |

## 13. Fuera de alcance

- Implementación real en Wallet/Combat/Web (Tasks #434/#435/#436).
- Cambios a HU-21 o HU-22 (se reutilizan sus puntos de enganche, no se reabren).
- Un endpoint público para que el jugador vea el detalle de sus holds históricos (solo `balance`/`reserved`/`available` agregados, §6).
- Apuestas en modalidades que no sean 1v1/2v2/3v3 ya cubiertas por HU-14.
- Cualquier redistribución del pozo que no sea "partes iguales entre ganadores" (D2): si el PO pide una regla proporcional más adelante, es una revisión de este contrato, no una interpretación libre en el código.

## 14. Compatibilidad y orden de despliegue

Aditivo: ningún mensaje ni contrato de HU-13/14/17/18/19/20/21/22 cambia de forma. **Orden:** Infrastructure (este contrato) → **Wallet** (migración propia de holds, antes de que Combat pueda llamarla) → **Combat** (`npm run migrate` si aplica; no debe llamar a un contrato que Wallet no expone todavía) → **Web**. Una sala creada con apuesta antes de que Web tenga esta versión seguiría funcionando por API pero Web no mostraría el estado de la reserva hasta desplegarse.
