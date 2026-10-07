# Contrato de señales realtime de Subasta v1 — EN-034 / TASK EN-034.1

Estado: **contrato publicado; sin implementar**. Auction todavía no expone el WebSocket (TASK EN-034.2, Management #584) y la Web no lo consume (TASK EN-034.4, #586).

Decisión de arquitectura: [ADR-024](../adr/ADR-024-realtime-auction.md), que extiende [ADR-020](../adr/ADR-020-realtime-combat.md). Diseño detallado y diagrama de secuencia: `docs/tasks/TASK-34.1-contrato-realtime.md` en `Nexus-Battle-Auction`. Enabler: [EN-034 #523](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/523).

## 1. Principio

El backend es la fuente de verdad. El canal transporta **señales de invalidación**: dice qué subasta cambió y en qué revisión, y el cliente recupera el estado con las consultas HTTP existentes (`GET /api/v1/auctions` y `GET /api/v1/auctions/{auctionId}`). El canal es de solo lectura: no existen comandos de negocio por él. Pujar, comprar de inmediato y cancelar siguen siendo HTTP transaccional.

## 2. Superficie

| Elemento | Valor |
| --- | --- |
| WebSocket | `wss://nexus.simuladorupbbga.app/api/v1/auctions/realtime` |
| Emisión de ticket | `POST /api/v1/auctions/realtime/tickets` |
| Enrutado | Caddy `handle /api/v1/auctions*` → `auction:3008`; sin cambios |
| Interruptor | `AUCTION_REALTIME_ENABLED`; apagado desactiva ambos puntos |
| Roles | `Player`, `GameMaster` (los mismos que las lecturas HTTP) |

## 3. Autenticación: ticket de un solo uso

1. El cliente llama `POST /api/v1/auctions/realtime/tickets` con `Authorization: Bearer <JWT>`.
2. Auction verifica el testimonio como en cualquier ruta y responde:

```json
{
  "ticket": "opaque-random-string",
  "expiresAt": "2026-10-07T12:00:30.000Z"
}
```

3. El ticket es opaco, está ligado al `sub`, es de **un solo uso** y caduca a los **30 segundos**. Solo se guarda su hash.
4. El cliente abre el WebSocket **sin credenciales en la URL** y envía como primer mensaje `{"type":"auth","ticket":"..."}`.
5. Sin ticket válido en **5 segundos**, o con un ticket usado o caducado, el servidor cierra con código `4401`.

El `sub` del ticket es la única identidad de la conexión. El JWT nunca viaja en la URL.

## 4. Mensajes del cliente

Solo tres tipos. Cualquier otro se rechaza y cierra con `4400`.

```json
{ "type": "auth", "ticket": "opaque-random-string" }
{ "type": "subscribe", "channel": "auctions/auction-1" }
{ "type": "unsubscribe", "channel": "auctions/auction-1" }
```

| Canal | Quién lo observa | Recibe |
| --- | --- | --- |
| `auctions/{auctionId}` | Detalle de subasta, panel de puja | Señales de esa subasta, con `summary` |
| `auctions` | Marketplace | Señales de cualquier subasta, **sin** `summary` |

Suscribirse exige poder hacer el `GET` equivalente. Una subasta inexistente o no visible responde igual que ese `GET`.

## 5. Mensajes del servidor

### Confirmaciones

```json
{ "type": "subscribed", "channel": "auctions/auction-1" }
{ "type": "unsubscribed", "channel": "auctions/auction-1" }
{ "type": "error", "code": "SUBSCRIPTION_LIMIT", "message": "..." }
```

### Señal `AuctionRealtimeSignalV1`

```json
{
  "type": "signal",
  "channel": "auctions/auction-1",
  "signal": {
    "signalVersion": 1,
    "signalId": "auction:auction-1:r42",
    "auctionId": "auction-1",
    "revision": 42,
    "reason": "BID_ACCEPTED",
    "occurredAt": "2026-10-07T12:00:00.000Z",
    "summary": {
      "status": "ACTIVE",
      "currentBidCredits": 1500,
      "bidCount": 7
    }
  }
}
```

| Campo | Tipo | Notas |
| --- | --- | --- |
| `signalVersion` | `1` | Versión del contrato |
| `signalId` | string | `auction:{auctionId}:r{revision}`; idempotente |
| `auctionId` | string | Única clave de ruteo |
| `revision` | entero | Creciente por subasta; ver §6 |
| `reason` | enum | `PUBLISHED`, `BID_ACCEPTED`, `BOUGHT_NOW`, `SETTLED`, `CANCELLED` |
| `occurredAt` | ISO-8601 | Informativo; **nunca** se usa para ordenar |
| `summary` | objeto, opcional | Pista para pintar antes del refetch |
| `summary.status` | enum | `ACTIVE`, `FINISHED`, `SOLD`, `CANCELLED` |
| `summary.currentBidCredits` | entero o `null` | `null` si nadie ha pujado |
| `summary.bidCount` | entero | |

`BOUGHT_NOW`, `SETTLED` y `CANCELLED` son terminales. Tamaño máximo de una señal: 1 KiB.

### Qué no viaja

Ni `bidderId`, ni `sellerId`, ni `winnerId`, ni `loserBidderIds`, ni ningún dato personal. Los eventos `auction.*` v1 entre servicios sí los llevan, por eso **no se reutilizan tal cual** hacia el navegador.

## 6. Revisión, orden y deduplicación

- Cada subasta tiene una columna `revision bigint` (migración 021) que se incrementa **dentro de la misma transacción** que cualquier cambio observable: puja confirmada, compra inmediata, cierre, cancelación y publicación.
- La señal se emite **después del commit**, nunca antes.
- El cliente guarda la última `revision` vista por `auctionId` y **descarta** toda señal con `revision` menor o igual.
- `summary` es solo una pista: aunque exista, el cliente siempre dispara el refetch y prevalece su resultado.

## 7. Reconexión

1. El cliente detecta el cierre del socket o la falta de latido.
2. Reconecta con backoff exponencial con jitter (tope sugerido 30 s) y repite el flujo de ticket: cada conexión necesita uno nuevo.
3. Tras autenticar, vuelve a suscribirse a lo observado e **invalida las consultas de subasta que observaba**.
4. Mientras está desconectado, la interfaz no presenta el valor como «en vivo».

No hay `resume`, `lastSeq` ni bitácora: el refetch cumple esa función. Un reinicio de Caddy o de Auction cierra todas las conexiones, y es esperado.

## 8. Latido y límites

| Parámetro | Valor |
| --- | --- |
| Latido del servidor | cada 25 s; una conexión sin respuesta se cierra |
| Suscripciones por conexión | 20 |
| Conexiones simultáneas por usuario | 3 |
| Tamaño máximo de mensaje entrante | 1 KiB |
| Tiempo para autenticar | 5 s |
| Caducidad del ticket | 30 s |

## 9. Códigos de cierre

| Código | Significado |
| --- | --- |
| `4400` | Mensaje inválido o de tipo no permitido |
| `4401` | Ticket ausente, usado, caducado o sin autenticar a tiempo |
| `4403` | Rol sin permiso |
| `4429` | Límite de conexiones por usuario excedido |

## 10. Reversión

Con `AUCTION_REALTIME_ENABLED` apagado, el endpoint de tickets y el WebSocket dejan de aceptar peticiones. El cliente, ante un fallo permanente, cae a sondeo HTTP con intervalo largo. Ninguna de las dos rutas toca reglas de puja, créditos ni estados persistidos; la columna `revision` es aditiva.

## 11. Criterios de aceptación de EN-034 y dónde se cubren

| CA | Cobertura |
| --- | --- |
| CA-01 actualización de puja entre sesiones | §5 `BID_ACCEPTED`, §4 canal por subasta |
| CA-02 aislamiento por subasta | §4, §6 y §5 (`auctionId` como única clave de ruteo) |
| CA-03 reconexión | §7 |
| CA-04 cambio de estado | §5 razones terminales |
| CA-05 caché consistente | §4 (Marketplace invalida, no parchea) |
| CA-06 autoridad del backend | §1 y §6 |

## 12. Limitaciones conocidas

- **Una sola réplica de Auction.** La difusión es en memoria del proceso (ADR-011, ADR-024). Con más de una réplica, un cambio confirmado en una no llegaría a los clientes conectados a otra; el estado no queda incorrecto, solo tarda hasta el siguiente refetch. Escalar exige un bus de difusión y un ADR nuevo.
- **Memoria.** El contenedor de Auction tiene `mem_limit: 160m`; los límites de §8 son obligatorios y TASK EN-034.2 debe medir el consumo.
- **Verificación pendiente.** Mantener una conexión de más de 60 s a través de Caddy se prueba en TASK EN-034.5 (#587).
- **Web.** El módulo de Subasta de la Web (HU-87, HU-88) aún no existe.
