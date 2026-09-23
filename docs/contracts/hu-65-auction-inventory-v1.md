# Contrato HU-65 — Auction ↔ Player-Inventory para productos comprometidos (v1)

- **Estado:** contrato canónico para HU-65.4 / Task [#326](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/326). No implementa servicios.
- **Historia:** [HU-65 #50](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/50) · Team Gama.
- **Referencias:** [Auction–Wallet](hu-65-auction-wallet-settlement-v1.md), ADR-005 y ADR-019.

## Alcance y ownership

Este contrato bloquea el producto publicado, lo devuelve al vendedor con
`WITHOUT_BIDS` y lo retiene para el ganador con `WITH_WINNER`. No entrega el
producto al inventario usable del ganador: eso es claim futuro de HU-69.

| Player-Inventory posee | Auction posee |
| --- | --- |
| inventario usable, commitments, ciclo de vida del producto bloqueado, persistencia e idempotencia Inventory | `auctionId`, vendedor, producto, `closesAt`, ganador, resultado, `inventoryCommitmentId`, pending claim y coordinación/reintentos |

Auction no lee MongoDB de Inventory, no crea FK cross-service ni concede
directamente el producto al ganador. Player-Inventory no decide ganador ni
resultado de la subasta. `inventory/grants` queda excluido: añade unidades y
no libera, transfiere ni retiene commitments.

## Commitment y expiración

| Estado | Significado | Transición HU-65.4 |
| --- | --- | --- |
| `ACTIVE` | producto bloqueado al vendedor durante la subasta | `PENDING_CLAIM` o `RELEASED` |
| `PENDING_CLAIM` | derecho durable del ganador sin inventario usable | futura: `CLAIMED` por HU-69 |
| `RELEASED` | producto original nuevamente usable por vendedor | terminal |

`CLAIMED` se reserva para HU-69; HU-65.4 no expone claim ni lo marca en
Auction. `expiresAt` es metadata/deadline operativa: **no libera
automáticamente** un commitment `ACTIVE` o `PENDING_CLAIM`. Por tanto,
`expiresAt = closesAt` nunca devuelve el producto tras `WITH_WINNER`; sólo
transiciones explícitas, autorizadas e idempotentes cambian el estado.

## Seguridad e identificadores

Todas las rutas `/api/internal/v1/inventory/auction-commitments*` usan el HMAC
existente de Player-Inventory:

- `x-internal-service: auction` (incorporarlo a la allow-list es trabajo de PI);
- `x-internal-timestamp` Unix ms, ventana de 30 s;
- `x-internal-signature` HMAC-SHA256; secreto `INTERNAL_SERVICE_AUTH_SECRET`;
- sin JWT y bloqueadas por el proxy público.

Cadena canónica:

```text
auction
METHOD
PATH
TIMESTAMP
SHA256(JSON_CANONICO)
```

El JSON canónico ordena claves recursivamente, conserva arrays y no añade
espacios. En retry se renuevan sello/firma, pero no el ID ni el cuerpo.

`operationId` es string determinista UTF-8 de máximo 200 caracteres, no UUID:

```text
auction:{auctionId}:inventory:commit
auction:{auctionId}:inventory:release
auction:{auctionId}:inventory:pending-claim
```

`commitmentId` es opaco y generado por Player-Inventory (puede ser UUID).
Player-Inventory persiste intención y resultado:

- mismo `operationId` + intent normalizado idéntico: `200`, resultado original,
  `applied:false`;
- mismo ID + intent distinto: `409 OPERATION_CONFLICT`, sin efectos;
- timeout/`503`: Auction reintenta exactamente el mismo ID y cuerpo.

Release y pending-claim validan el commitment durable (`auctionId`, producto,
vendedor/owner y estado), no sólo el body. `release` sobre `PENDING_CLAIM` y
`pending-claim` sobre `RELEASED` son `422` terminales.

## Crear commitment en publicación

```text
POST /api/internal/v1/inventory/auction-commitments
```

```json
{
  "operationId": "auction:auction-1:inventory:commit",
  "auctionId": "auction-1",
  "ownerId": "seller-1",
  "productId": "11111111-1111-4111-8111-111111111111",
  "expiresAt": "2026-09-23T12:00:00.000Z"
}
```

```json
{
  "operationId": "auction:auction-1:inventory:commit",
  "commitmentId": "a9b234d1-58b8-4c17-8a41-57f88f45de41",
  "status": "ACTIVE",
  "applied": true
}
```

Inventory valida ownership y ausencia de bloqueo incompatible, bloquea el
producto del inventario usable y persiste el commitment. Replay entrega el
mismo resultado con `applied:false`.

Secuencia: (1) `inspect` opcional para UX; no reserva. (2) `commit`
autoritativo. (3) Auction persiste Auction e `inventoryCommitmentId`. (4) si
falla esa persistencia, solicita release compensatorio con ID durable; nunca
crea o concede una copia alternativa.

## Liberar en `WITHOUT_BIDS`

```text
POST /api/internal/v1/inventory/auction-commitments/{commitmentId}/release
```

```json
{
  "operationId": "auction:auction-1:inventory:release",
  "auctionId": "auction-1",
  "ownerId": "seller-1",
  "productId": "11111111-1111-4111-8111-111111111111",
  "reason": "AUCTION_WITHOUT_BIDS"
}
```

Respuesta `200`: `{ operationId, commitmentId, status: "RELEASED", applied }`.
Hace usable al vendedor el producto original: no crea una copia ni usa grants.

Secuencia: resultado durable `WITHOUT_BIDS` → no hay captura Wallet ganadora
→ release Inventory → sólo tras éxito/replay `completeSettlement` → audit/outbox
local de Auction.

## Retener en `WITH_WINNER`

```text
POST /api/internal/v1/inventory/auction-commitments/{commitmentId}/pending-claim
```

```json
{
  "operationId": "auction:auction-1:inventory:pending-claim",
  "auctionId": "auction-1",
  "sellerId": "seller-1",
  "winnerId": "winner-1",
  "productId": "11111111-1111-4111-8111-111111111111"
}
```

```json
{
  "operationId": "auction:auction-1:inventory:pending-claim",
  "commitmentId": "a9b234d1-58b8-4c17-8a41-57f88f45de41",
  "status": "PENDING_CLAIM",
  "winnerId": "winner-1",
  "applied": true
}
```

La transición excluye el producto del flujo usable del vendedor y lo conserva
para el ganador; no inserta una ranura del ganador ni usa grants.

Secuencia: cierre durable → captura Wallet ganadora → releases Wallet
perdedoras → `ACTIVE → PENDING_CLAIM` Inventory → sólo tras éxito/replay
`completeSettlement` → `auction_pending_claim`, audit/outbox en una transacción
local. HU-69 podrá materializar después `PENDING_CLAIM → CLAIMED` y entregar
el producto; su endpoint y su claim quedan fuera de HU-65.4.

## HTTP y recuperación

| Código | Significado | Acción Auction |
| --- | --- | --- |
| `200` | aplicado o replay | verificar estado y continuar |
| `400` | body inválido | terminal, corregir contrato |
| `401` | HMAC/caller/timestamp inválido | terminal, corregir auth |
| `404` | commitment/product inexistente | inconsistencia terminal; no inventar producto |
| `409` | ID con intent incompatible/conflicto durable | terminal, investigar intención |
| `422` | estado/regla de dominio incompatible | terminal |
| `503` | temporal/no concluyente | retry mismo ID y body |

| Caso | Regla |
| --- | --- |
| crash antes de enviar | recuperar intención y enviar el mismo comando |
| timeout tras aplicar | replay: Inventory devuelve el resultado durable |
| `503` | mantener settlement pendiente; no completar ni compensar a ciegas |
| dos settlements concurrentes | IDs deterministas: una aplicación y replays |

Ningún retry puede duplicar producto ni cambiar vendedor, producto o ganador.

## Compatibilidad con Auction actual

| Puerto `ProductInventoryPort` | Contrato v1 |
| --- | --- |
| `inspect(ownerId, productId)` | precheck opcional, no autoritativo |
| `commit({ operationId, ownerId, productId, expiresAt })` | endpoint commit; añadir `auctionId` |
| `release(operationId, commitmentId)` | endpoint release; transportar/validar intent completo |

Auction requiere una ampliación mínima, por ejemplo
`markPendingClaim({ operationId, commitmentId, auctionId, sellerId, winnerId,
productId })`, además de adaptador HTTP firmado e intención Inventory durable
para recuperar timeout/restart antes de `completeSettlement`.

No hay transacciones distribuidas, DB compartida ni FK cross-service. Cada
servicio confirma su transacción local; Auction coordina con intenciones
durables e idempotentes.

## Fuera de alcance

Esta versión no implementa servicios, migraciones, workers de expiración,
endpoint público de claim, entrega al ganador, cambios Wallet ni HU-69.
