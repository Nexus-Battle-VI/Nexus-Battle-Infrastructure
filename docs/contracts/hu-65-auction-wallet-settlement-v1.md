# Contrato HU-65 — Liquidación de subasta entre Auction y Wallet (v1)

- **Estado:** diseño de HU-65.2 / Task [#324](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/324). Las operaciones de `holds`, `captures` y `releases` descritas aquí **no están implementadas** al crear este contrato.
- **Historia:** [HU-65 #50](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/50) · Team Gama.
- **Base arquitectónica:** [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md), sin crear un ADR nuevo.
- **Orden obligatorio:** Infrastructure (este documento) → Wallet → Auction → pruebas integradas de #324. Wallet se despliega antes de habilitar las llamadas de Auction.

## 1. Alcance, realidad actual y propiedad

Este documento define el contrato interno para reservar créditos de una puja y, al cerrar una subasta, capturar la reserva ganadora a favor del vendedor y liberar las perdedoras. La captura económica no depende del reclamo posterior de HU-69.

Hoy Wallet solo implementa el crédito de recompensa de batalla (`POST /api/internal/v1/wallet/credits/battle-reward`); no tiene holds, saldo reservado, captura ni liberación. Auction ya persiste el identificador de reserva de las pujas y la oferta líder, pero aún no tiene un cliente HTTP de Wallet ni una intención durable de liquidación. Por tanto, todo endpoint de este documento es diseño hasta las Tasks posteriores.

| Wallet posee en exclusiva | Auction posee en exclusiva |
| --- | --- |
| saldo disponible y reservado; holds; captura; liberación; ledger insert-only; invariantes económicas | subasta; pujas; oferta líder; resultado de cierre; intención durable de liquidación; coordinación y reintentos |

Está prohibido que Auction lea PostgreSQL de Wallet, calcule saldos, mantenga claves foráneas cross-service o que Wallet decida el ganador. Wallet tampoco depende del reclamo del producto.

## 2. Seguridad común

Todas las rutas son internas bajo `/api/internal/v1/wallet/*` y requieren el mecanismo existente de ADR-019:

- `x-internal-service: auction` (Auction debe estar en la allow-list de Wallet);
- `x-internal-timestamp` dentro de la ventana vigente de 30 segundos;
- `x-internal-signature`, HMAC-SHA256 de método, ruta, timestamp y JSON canónico;
- secreto mediante variable de entorno, nunca registrado en logs.

Caddy bloquea `/api/internal*` desde fuera. No se propaga JWT de un jugador ni se introduce otro mecanismo de autenticación.

## 3. Modelo objetivo de Wallet

La migración futura de Wallet debe ampliar el saldo actual (`balance`) para soportar `available` y `reserved`, ambos no negativos, y tablas propias de holds y ledger. No existe todavía esa migración.

```text
available >= 0
reserved >= 0
available + reserved = créditos del jugador antes de créditos o capturas externas
```

Un hold tiene `id`, `playerId`, `amount`, referencia de Auction, `status`, `createdAt` y `expiresAt`. Sus únicos estados son `ACTIVE`, `CAPTURED`, `RELEASED` y `EXPIRED`; no existe reactivación.

| Transición | Efecto |
| --- | --- |
| `ACTIVE → CAPTURED` | reduce `reserved` del ganador y acredita el mismo importe al vendedor |
| `ACTIVE → RELEASED` | reduce `reserved` y devuelve el importe a `available` |
| `ACTIVE → EXPIRED` | mismo efecto económico que liberar, con auditoría de expiración |
| desde `CAPTURED`, `RELEASED` o `EXPIRED` | ninguna transición posterior |

Una captura de un hold `RELEASED`/`EXPIRED` o una liberación de uno `CAPTURED` es un rechazo terminal `422`. Repetir una operación ya resuelta con su mismo `operationId` es replay, no una nueva transición.

## 4. Idempotencia y operaciones

Cada mutación incluye un `operationId`. Wallet persiste la intención y el resultado completos.

- Mismo `operationId` y mismo cuerpo: `200`, `applied: false` y el resultado original.
- Mismo `operationId` y cuerpo distinto: `409 OPERATION_CONFLICT` sin efectos.
- `503` o timeout: el resultado es no concluyente; Auction reintenta exactamente el mismo `operationId`.

Auction conserva la convención de HU-63: el identificador raíz de la puja genera `:reserve`, `:release-new` y `:release-previous`. Para el cierre usa identificadores deterministas nuevos:

```text
auction:{auctionId}:settlement:capture
auction:{auctionId}:bid:{bidId}:release
```

### 4.1 Crear hold

```text
POST /api/internal/v1/wallet/holds
```

```json
{
  "operationId": "auction:auction-1:bid:bid-7:reserve",
  "playerId": "bidder-1",
  "amount": 35,
  "reason": "AUCTION_BID",
  "reference": {
    "auctionId": "auction-1",
    "bidId": "bid-7",
    "auctionClosesAt": "2026-09-23T12:00:00.000Z"
  }
}
```

`auctionClosesAt` es la hora que Auction ya fijó en servidor al publicar; nunca proviene del navegador. El request no acepta `expiresAt`: Wallet, con su propio reloj, valida que el cierre sea futuro y calcula `expiresAt = auctionClosesAt + AUCTION_HOLD_GRACE`. La gracia es configuración de Wallet y cubre el retraso del cierre/reintentos; si la fecha es inválida, vencida o fuera del máximo contractual configurado, responde `422`.

Respuesta `200`:

```json
{
  "operationId": "auction:auction-1:bid:bid-7:reserve",
  "holdId": "hold-1",
  "holdStatus": "ACTIVE",
  "applied": true
}
```

### 4.2 Capturar la reserva ganadora y acreditar al vendedor

```text
POST /api/internal/v1/wallet/holds/{holdId}/captures
```

```json
{
  "operationId": "auction:auction-1:settlement:capture",
  "beneficiaryPlayerId": "seller-1",
  "reason": "AUCTION_SETTLEMENT",
  "reference": {
    "auctionId": "auction-1",
    "winningBidId": "bid-7"
  }
}
```

No se envía importe ni saldo resultante: Wallet deriva el importe del hold almacenado y valida que su referencia coincida. En una única transacción local bloquea el hold `ACTIVE`, lo marca `CAPTURED`, reduce el `reserved` del ganador, acredita exactamente ese importe al vendedor, inserta las entradas de ledger de débito/crédito y guarda el resultado idempotente.

Invariante: **créditos capturados al ganador = créditos acreditados al vendedor**. La transacción completa confirma o revierte; no crea ni destruye créditos.

Respuesta `200`:

```json
{
  "operationId": "auction:auction-1:settlement:capture",
  "holdId": "hold-1",
  "holdStatus": "CAPTURED",
  "beneficiaryPlayerId": "seller-1",
  "applied": true
}
```

### 4.3 Liberar hold

```text
POST /api/internal/v1/wallet/holds/{holdId}/releases
```

```json
{
  "operationId": "auction:auction-1:bid:bid-6:release",
  "reason": "AUCTION_OUTBID"
}
```

Al cerrar una subasta puede usarse `reason: "AUCTION_SETTLEMENT_LOST"`. Wallet libera solo un hold `ACTIVE`, devuelve su importe a `available`, registra el ledger/auditoría y devuelve `200` con `{ operationId, holdId, holdStatus: "RELEASED", applied }`.

Un `holdId` inexistente devuelve `404 HOLD_NOT_FOUND` únicamente si no hay un resultado previo para ese `operationId`; Auction lo trata como inconsistencia terminal y no inventa una reserva. Una perdedora ya `RELEASED` responde como replay idempotente cuando el `operationId` coincide. Una compensación de HU-63 pendiente se reintenta con su identificador original; no se crea un hold alterno.

## 5. Códigos HTTP

| Código | Semántica de Auction |
| --- | --- |
| `200` | aplicación o replay idempotente; inspeccionar `applied` y estado retornado |
| `404` | solo hold inexistente sin operación previa; inconsistencia terminal, no reintento ciego |
| `409` | `operationId` reutilizado con cuerpo incompatible; conflicto terminal y sin efectos adicionales |
| `422` | request o invariante económica inválida, estado incompatible o vencimiento no admisible; terminal |
| `503` | fallo temporal/no concluyente; reintentar el mismo request e identificador |

## 6. Liberación de perdedoras y coordinación

HU-63 ya intenta liberar la reserva del líder anterior al ser superada. HU-65.2 debe, al cierre, consultar su intención durable e identificar cualquier reserva perdedora que siga `ACTIVE` o con compensación pendiente:

- `RELEASED`: registrar resultado local/replay sin liberar otra vez;
- `ACTIVE`: solicitar la liberación con el `operationId` determinista de esa puja;
- compensación pendiente: retomar el mismo `operationId` que HU-63 dejó persistido;
- inexistente: manejar el `404` contractual como inconsistencia, no como éxito.

La captura ganadora no espera una transacción distribuida con las liberaciones perdedoras. Auction persiste cada paso antes de llamar a Wallet, reintenta cada operación por separado y nunca repite una transferencia ya confirmada.

## 7. Matriz de fallos parciales

| Caso | Wallet/estado observable | Acción de Auction | Riesgo evitado |
| --- | --- | --- | --- |
| Wallet no disponible antes de captura | `503`, resultado desconocido | reintenta `auction:{auctionId}:settlement:capture` | perder la liquidación |
| timeout tras aplicar captura | el replay devuelve `CAPTURED`, `applied:false` | mismo request e id | doble transferencia |
| replay de captura | resultado original | marcar intención local confirmada | doble débito/abono |
| mismo id con cuerpo distinto | `409` | terminal, investigar intención | transferir a otro beneficiario |
| hold ya capturado | replay con el id original; otra captura incompatible es `422` | no liberar ni recapturar | transición inválida |
| hold ya liberado | replay de release; captura es `422` | no acreditar al vendedor | crédito sin reserva |
| release temporalmente fallida | `503`, hold puede seguir `ACTIVE` | reintento separado con mismo id | créditos bloqueados |
| Auction cae tras captura | Wallet conserva resultado idempotente | recupera intención durable y consulta por replay | transferencia duplicada u olvidada |
| liquidaciones concurrentes | Wallet serializa por hold/operación y devuelve una aplicación + replays | ambos usan el mismo id determinista | carrera y doble captura |

## 8. Responsabilidades de implementación

Wallet implementará migraciones para saldos `available`/`reserved`, holds, ledger de reserva/captura/liberación, endpoints, HMAC, locks e idempotencia. Auction implementará el cliente HTTP firmado, persistencia de la intención de liquidación, acceso a la reserva líder y reservas perdedoras, orquestación/reintentos y pruebas de integración. Ninguna implementación debe afirmar que este contrato ya estaba disponible antes de sus respectivos PRs.

## 9. Fuera de alcance

Wallet, inventario, scheduler, notificaciones, reclamo HU-69, endpoints públicos y la implementación de #324 están fuera de este PR documental.
