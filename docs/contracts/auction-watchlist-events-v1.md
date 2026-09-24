# Contrato de eventos de seguimiento de subastas v1 — HU-68 / TASK 68.3

Estado: implementado por Auction y Notifications.

## Transporte y autenticación

Auction envía `POST /api/internal/v1/notifications/auction/watchlist-events` a Notifications. La petición usa `x-internal-service: auction`, sello Unix en milisegundos y firma HMAC SHA-256 sobre servicio, método, ruta, sello y resumen canónico del cuerpo. Notifications admite una deriva máxima de 30 segundos.

El productor exige una respuesta `200` cuyo `eventId` coincida. Notifications tolera reintentos: la clave persistente se deriva de `eventId + playerId`.

## Eventos

Campos comunes: `eventId`, `auctionId`, `recipientPlayerIds` no vacío y sin significado posicional, y `occurredAt` ISO-8601.

### Cambio de puja líder

```json
{
  "eventId": "bid-operation-1:watchlist-change",
  "eventType": "auction.watchlist.changed.v1",
  "auctionId": "auction-1",
  "recipientPlayerIds": ["player-1"],
  "changeType": "LEADING_BID_CHANGED",
  "occurredAt": "2026-09-21T12:00:00.000Z"
}
```

### Cierre próximo

```json
{
  "eventId": "auction-1:closing:2026-09-21T13:00:00.000Z",
  "eventType": "auction.closing-soon.v1",
  "auctionId": "auction-1",
  "recipientPlayerIds": ["player-1", "bidder-1"],
  "closesAt": "2026-09-21T13:00:00.000Z",
  "occurredAt": "2026-09-21T12:00:00.000Z"
}
```

Los destinatarios del recordatorio son la unión sin duplicados de seguidores y participantes. El identificador estable evita repetir la notificación cuando el planificador vuelve a evaluar la misma ventana.

## Respuestas

| HTTP | Significado |
| --- | --- |
| `200` | Evento creado o replay idempotente; devuelve `eventId`, `status`, `created` y `duplicated`. |
| `400` | Cuerpo o versión de evento inválidos. |
| `401` | Servicio, sello o firma inválidos; también cuando falta el secreto interno. |
| `413` | Cuerpo mayor a 16 KiB. |
| `500` | Fallo interno de persistencia. |

## Changelog / Registro de Cambios

- Definidos los dos eventos versionados de TASK 68.3 y sus destinatarios.
- Documentada la autenticación HMAC, la confirmación y la idempotencia de TASK 68.4.
- Commit propuesto: `docs(infrastructure): define HU-68 auction event contract`.
