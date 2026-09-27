# Contrato HTTP de seguimiento de subastas v1 — HU-68 / TASK 68.2

Estado: contrato propuesto para implementación y revisión en TASK 68.2; no declara despliegue ni aceptación de la HU.

Refs Nexus-Battle-VI/Nexus-Battle-Management#53.

## Identidad y ownership

Auction mantiene la watchlist. Todas las operaciones requieren un access token Bearer válido y rol `PLAYER`. `playerId` se toma exclusivamente del `subject` verificado por `JwtAuthGuard`; nunca se admite como selector en cuerpo, query o ruta. Las rutas rechazan acceso incluso con `AUTH_MODE=disabled`, para no compartir seguimientos bajo una identidad anónima.

## Operaciones

| Método y ruta | Entrada | Salida |
| --- | --- | --- |
| `POST /api/v1/auctions/watchlist` | JSON `{ "auctionId": "auction-1" }` | `201`, `{ "auctionId": "auction-1", "followedAt": "2026-09-21T12:00:00.000Z" }` |
| `GET /api/v1/auctions/watchlist` | Sin parámetros | `200`, `{ "items": [...] }`; lista vacía `{ "items": [] }` |
| `DELETE /api/v1/auctions/watchlist/{auctionId}` | Sin cuerpo ni query | `204` sin cuerpo; también cuando la pareja propia no existe |

El identificador admite entre 1 y 128 caracteres: extremos alfanuméricos ASCII; interior alfanumérico o `.`, `_`, `:`, `-`. La API exige la forma canónica sin espacios. POST rechaza campos adicionales; ninguna operación admite parámetros de query. DELETE rechaza cuerpos no vacíos.

Cada elemento de la lista contiene `auctionId`, `followedAt` ISO-8601 UTC y `auction`, con el snapshot público de Auction: `id`, `sellerId`, `productId`, `durationHours`, `publicationFeeCredits`, `minimumBidCredits`, `buyNowCredits` (nullable), `status`, `publishedAt`, `closesAt`. No se exponen tokens, identificadores de cobros ni compromisos de inventario. El snapshot se obtiene al listar, no se conserva como copia obsoleta en la watchlist.

La lista ordena por `followedAt` descendente y `auctionId` ascendente para empates, según TASK 68.1. Conserva seguimientos de subastas vencidas: el vencimiento impide nuevas altas, no consultar o retirar seguimientos. No se introduce borrado automático ni paginación en esta tarea. Un fallo al leer datos no se disfraza de lista vacía.

## Reglas y respuestas de error

| HTTP | Código estable / condición |
| --- | --- |
| `400` | `INVALID_REQUEST`: cuerpo, identificador, query o campos no permitidos. |
| `401` | Credencial ausente/inválida o autenticación deshabilitada; formato existente del guard NestJS. |
| `403` | Identidad sin rol PLAYER; formato existente del guard. |
| `404` | `AUCTION_NOT_FOUND`: la subasta solicitada en POST no existe. |
| `409` | `WATCHLIST_ALREADY_EXISTS`: pareja ya registrada, también ante concurrencia. |
| `422` | `AUCTION_NOT_FOLLOWABLE`: estado distinto de ACTIVE o `now >= closesAt`. |
| `503` | `WATCHLIST_UNAVAILABLE`: persistencia/lectura indisponible o inconsistente; sin detalles internos. |

Errores de aplicación: `{ "statusCode": 409, "code": "WATCHLIST_ALREADY_EXISTS", "message": "..." }`. El cliente decide por status/code, no por el texto del mensaje. Errores de DTO pueden incluir el arreglo `errors` del ValidationPipe existente. Errores de verificación inesperados del proveedor de identidad conservan el comportamiento del guard existente (`500`); no se presentan como credenciales inválidas.

POST consulta existencia y estado, usa `ClockPort` y delega unicidad al repositorio. Un duplicado no actualiza `followedAt`. Si una subasta ya venció, la validación de elegibilidad ocurre antes del intento de inserción y devuelve `422`, aunque hubiese un seguimiento previo. No se añade una prohibición de seguir subastas propias que HU-68 no especifica. La comprobación de elegibilidad corresponde al instante de validación, sin garantía de serialización con un futuro proceso de cierre.

DELETE actúa únicamente sobre `(subject, auctionId)`, sin revelar la existencia de seguimientos de terceros ni exigir que la subasta siga activa. Repetirlo es inocuo. La eliminación física concurrente de una subasta está protegida por la FK local de TASK 68.1.

## OpenAPI y enrutamiento

El servicio publicará el esquema runtime mediante los decoradores `@nestjs/swagger`, con el esquema de seguridad `bearer`, DTOs de solicitud/respuesta y respuestas HTTP documentadas. Las pruebas verifican las tres operaciones y sus contratos. Caddy ya enruta `/api/v1/auctions*` a `auction:3008`; no se requiere una ruta nueva en el proxy.

## Changelog / Registro de cambios

- Añadido `docs/contracts/auction-watchlist-v1.md` antes de implementar los casos de uso y controladores.
- Decididos paths, propiedad de identidad, estado elegible, límite temporal, orden y errores.
- Sin cambios en mensajería, recordatorios, Notifications ni Web; corresponden a TASKs 68.3–68.5.
- Commit preparado: `docs(infrastructure): [HU-68.2] definir contrato HTTP de seguimiento`.
