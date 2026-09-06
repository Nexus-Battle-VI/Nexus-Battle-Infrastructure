# Catálogo de servicios

## Índice

| Servicio | Repositorio | Puerto | Team | OpenAPI | Base de datos objetivo |
| --- | --- | --- | --- | --- | --- |
| Web | [Nexus-Battle-Web](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web) | 8080 | Alfa + Beta + Gama | — | — |
| Account | [Nexus-Battle-Account](https://github.com/Nexus-Battle-VI/Nexus-Battle-Account) | 3000 | Alfa | `/api/docs` | PostgreSQL |
| Notifications | [Nexus-Battle-Notifications](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications) | 3001 | Alfa | — (AsyncAPI) | — |
| Player / Inventory | [Nexus-Battle-Player-Inventory](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory) | 3002 | Alfa | `/api/docs` | MongoDB |
| Catalog | [Nexus-Battle-Catalog](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog) | 3003 | Gama | `/api/docs` | MongoDB |
| Community | [Nexus-Battle-Community](https://github.com/Nexus-Battle-VI/Nexus-Battle-Community) | 3004 | Gama | `/api/docs` | PostgreSQL |
| Commerce | [Nexus-Battle-Commerce](https://github.com/Nexus-Battle-VI/Nexus-Battle-Commerce) | 3005 | Beta | `/api/docs` | PostgreSQL |

La especificación OpenAPI **se genera desde el código** con `@nestjs/swagger`, por lo que no puede quedar desincronizada de la implementación. Está deshabilitada en producción salvo decisión explícita.

## Sondas comunes

Los siete deployables exponen:

| Ruta | Semántica |
| --- | --- |
| `/health/live` | El proceso responde. No consulta dependencias |
| `/health/ready` | Evalúa dependencias reales. `503` si alguna falla |
| `/version` | Servicio, versión y entorno |

En los servicios NestJS, bajo el prefijo `/api`.

## Superficie por servicio

### Account — `/api/accounts`

| Método | Ruta | Códigos |
| --- | --- | --- |
| `POST` | `/api/accounts` | `201`, `400`, `409` |
| `GET` | `/api/accounts/search?email=...` | `200`, `400`, `401`, `403`, `404`, `503` |
| `POST` | `/api/accounts/:id/roles` | `200`, `400`, `401`, `403`, `404`, `409`, `503` |
| `DELETE` | `/api/accounts/:id/roles/:role` | `200`, `400`, `401`, `403`, `404`, `503` |
| `GET` | `/api/accounts/:id` | `200`, `404` |
| `POST` | `/api/accounts/:id/verification` | `200`, `400`, `404` |

### Player / Inventory — `/api/inventories`

| Método | Ruta | Códigos |
| --- | --- | --- |
| `GET` | `/api/inventories/:ownerId` | `200`, `404` |
| `POST` | `/api/inventories/:ownerId/items` | `200`, `400`, `404` |
| `POST` | `/api/inventories/:ownerId/items/removals` | `200`, `400`, `404` |
| `GET` | `/api/inventories/me/items` | `200`, `400`, `401`, `503` |
| `GET` | `/api/inventories/me/items/:itemReference` | `200`, `401`, `404`, `503` |

El alta crea el inventario si no existe: un jugador sin inventario y un inventario vacío son el mismo estado de negocio.

`GET /api/inventories/me/items` es la consulta self-service de HU-27: paginada de
16, identidad tomada del testimonio (nunca de la URL), con `?q=` (búsqueda por
nombre desde 4 caracteres) y `?type=` (tipo canónico). La búsqueda, el filtro y
la ficha de detalle enriquecen con la lectura canónica de Catalog
(`CATALOG_BASE_URL`); si Catalog no responde, esas operaciones devuelven `503` y
el listado sin búsqueda se degrada con `product: null`. Rating y comentarios
**no** forman parte de "Mi Inventario" (decisión funcional: pertenecen a
E-commerce/Subasta).

#### Contrato interno — `/api/internal/v1/inventory`

**Implementado e integrado en `develop`.** Servicio-a-servicio exclusivamente:
firmado con el mismo HMAC-SHA256 (`x-internal-service`/`x-internal-timestamp`/
`x-internal-signature`) que ya usa Commerce, `INTERNAL_SERVICE_AUTH_SECRET`
compartido. **NO se publica mediante Caddy** (`/api/internal*` responde `404`
en el proxy, ver más abajo).

| Método | Ruta | Códigos | Servicio permitido | HU |
| --- | --- | --- | --- | --- |
| `POST` | `/api/internal/v1/inventory/grants` | `200`, `400`, `409`, `422`, `503` | `commerce` | HU-59 |
| `GET` | `/api/internal/v1/inventory/products/:productId/owners` | `200`, `400`, `401` | `commerce`, `notifications` | HU-38 |

`.../products/:productId/owners` resuelve qué jugadores poseen actualmente un
producto (`{ productId, owners: [{ playerId }] }`, sin correo, nombre ni
inventario completo): lo consume Notifications para dirigir notificaciones de
suspensión/reactivación (HU-38) sin acceder directamente a esta base de datos.
Especificación: [Nexus-Battle-VI/Nexus-Battle-Management#175](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/175).
Implementación: [Nexus-Battle-VI/Nexus-Battle-Player-Inventory#23](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/23)
(mergeada a `develop`).

### Catalog — `/api/products`

**Estado implementado.** Esta sigue siendo la superficie desplegada y probada.

| Método | Ruta | Códigos |
| --- | --- | --- |
| `POST` | `/api/products` | `201`, `400`, `409` |
| `GET` | `/api/products` | `200`, `400` |
| `GET` | `/api/products/:sku` | `200`, `404` |
| `POST` | `/api/products/:sku/publication` | `200`, `400`, `404` |
| `POST` | `/api/products/:sku/archival` | `200`, `400`, `404` |
| `POST` | `/api/products/:sku/price` | `200`, `400`, `404` |

`GET /api/products/:sku` responde `404` para un producto en borrador o archivado. **No es un fallo: es la regla de visibilidad del dominio.**

#### Contrato objetivo HU-33 — `Accepted`

[ADR-013](../adr/ADR-013-canonical-product-contract.md) acepta la ruta
`POST /api/v1/catalog/products` con `productId` canónico y SKU como alias
temporal. Su especificación está en
[catalog-product-v1.openapi.yaml](catalog-product-v1.openapi.yaml).

| Método | Ruta | Códigos | Estado |
| --- | --- | --- | --- |
| `POST` | `/api/v1/catalog/products` | `201`, `400`, `401`, `403`, `409`, `422`, `503` | **Accepted; implementación trazada en Management #136** |
| `GET` | `/api/v1/catalog/products/:reference` | `200`, `404` | **Implementado (HU-27):** lectura pública por `productId` o alias `sku`; devuelve `lifecycleStatus` para ACTIVE y SUSPENDED |
| `POST` | `/api/v1/catalog/products/lookup` | `200`, `400` | **Implementado (HU-27):** resuelve hasta 500 referencias en una consulta (sin N+1), con filtro opcional por nombre normalizado y por tipo canónico. Es una lectura, no muta |

La ruta nueva no sustituye todavía `/api/products`. Durante la transición, la
superficie heredada se conserva como adaptador hacia los mismos casos de uso
canónicos. El retiro requiere telemetría, ausencia confirmada de consumidores
y aprobación del Product Owner.

Las dos rutas de LECTURA canónica se añadieron para HU-27 (consumidor:
Player/Inventory). Son `@Public()`, igual que `GET /api/products`: la información
de producto, una vez creado el producto canónico, es de lectura pública
(`SECURITY.md` de Catalog). **No habilitan enumeración del catálogo**: ambas
exigen que el consumidor aporte referencias exactas (`productId` o `sku`); no
hay endpoint de listado. Devuelven `lifecycleStatus` para ACTIVE y SUSPENDED
porque un jugador puede poseer un producto suspendido y RF-27 pide su
información vigente; en el modelo canónico no existe el estado `DRAFT`, que es el
único que Catalog oculta a las consultas públicas. No sustituyen a la superficie
heredada; son aditivas.

El contrato objetivo reserva `imageUrl`, pero el almacenamiento y ownership de
la imagen dependen de EN-027.3.
[`PO-ATTR-01`](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/286)
fue aprobada por el Product Owner el 30 de agosto de 2026: el OpenAPI define una
unión cerrada y versionada para los seis tipos, rechaza propiedades desconocidas
y exige que el discriminador de atributos coincida con `type`. ADR-013 está
aceptado; Catalog conserva la evidencia de implementación y despliegue en #136.

#### Administración del catálogo — `/api/v1/admin/products`

**Implementado e integrado en develop.** Requiere testimonio JWT, rol
ADMINISTRATOR (SUPER_ADMINISTRATOR lo satisface mediante la jerarquía RBAC) y,
salvo la lectura, evidencia TOTP vigente (`@RequiresMfaEvidence()`). El
Moderador no está autorizado en ninguna de estas rutas.

| Método | Ruta | Códigos | HU |
| --- | --- | --- | --- |
| `GET` | `/api/v1/admin/products/:id` | `200`, `401`, `403`, `404` | HU-34 |
| `PATCH` | `/api/v1/admin/products/:id/inventory` | `200`, `400`, `401`, `403`, `404`, `409`, `422`, `503` | HU-34 |
| `PATCH` | `/api/v1/admin/products/:id/premium` | `200`, `400`, `401`, `403`, `404`, `409`, `422`, `503` | HU-36 |
| `PATCH` | `/api/v1/admin/products/:id/status` | `200`, `400`, `401`, `403`, `404`, `503` | HU-35 |

`PATCH .../status` (HU-35, borrado lógico) suspende o reactiva un producto:
`status` admite únicamente `ACTIVE` o `SUSPENDED`, y `reason` es obligatorio
con un mínimo de 10 caracteres. Es idempotente: repetir el mismo estado
destino responde `200` sin generar una nueva entrada de auditoría ni un nuevo
evento de outbox. Su contrato HTTP completo está en
[catalog-product-v1.openapi.yaml](catalog-product-v1.openapi.yaml). Publicada
por [Caddy](../../compose/Caddyfile) mediante la regla ya existente
`handle /api/v1/admin*`, compartida con el resto de esta superficie
administrativa; no fue necesaria una regla nueva.

Especificación: [Nexus-Battle-VI/Nexus-Battle-Management#43](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/43).
Implementación de Catalog: [Nexus-Battle-VI/Nexus-Battle-Catalog#49](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/49)
(mergeada a `develop`). Interfaz de administración:
[Nexus-Battle-VI/Nexus-Battle-Web#83](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/83)
(mergeada a `develop`). Ninguna de las tres referencias afirma despliegue: no
hay evidencia de que este contrato corra en un entorno desplegado, solo de que
está implementado e integrado en `develop`.

### Community — `/api/threads`

| Método | Ruta | Códigos |
| --- | --- | --- |
| `POST` | `/api/threads` | `201`, `400` |
| `GET` | `/api/threads` | `200` |
| `GET` | `/api/threads/:threadId` | `200`, `404` |
| `POST` | `/api/threads/:threadId/posts` | `201`, `400`, `404` |
| `POST` | `/api/threads/:threadId/posts/:postId/hiding` | `200`, `400`, `404` |
| `POST` | `/api/threads/:threadId/closure` | `200`, `400`, `404` |

La lectura **omite los mensajes ocultos**. La persistencia los conserva.

### Commerce — `/api/orders`

| Método | Ruta | Códigos |
| --- | --- | --- |
| `POST` | `/api/orders` | `201`, `400` |
| `GET` | `/api/orders?customerId=` | `200`, `400` |
| `GET` | `/api/orders/:orderId` | `200`, `404` |
| `POST` | `/api/orders/:orderId/lines` | `200`, `400`, `404`, **`422`** |
| `DELETE` | `/api/orders/:orderId/lines/:sku` | `200`, `400`, `404` |
| `POST` | `/api/orders/:orderId/confirmation` | `200`, `400`, `404` |
| `POST` | `/api/orders/:orderId/cancellation` | `200`, `400`, `404` |

**El `422` es deliberado**: un producto que no está a la venta no es un `404`, porque el recurso de la petición —el pedido— sí existe. Lo que no se puede procesar es el contenido.

**El contrato de alta de línea no acepta el precio.** Lo determina el catálogo.

### Notifications

Su entrada principal sigue siendo la cola de mensajes; el contrato de eventos está en [event-catalog.md](event-catalog.md). Desde HU-38 (Management #46) tiene además superficie HTTP propia, **implementada e integrada en `develop`**, detrás de `CATALOG_NOTIFICATIONS_HTTP_ENABLED` (opcional, `false` por defecto en el propio servicio -ver [Nexus-Battle-VI/Nexus-Battle-Notifications#20](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/20)-; la composición de referencia de este repositorio la habilita, ver `compose/compose.example.yml` y `compose/nodes/app.yml`).

| Método | Ruta | Códigos | Quién |
| --- | --- | --- | --- |
| `GET` | `/api/v1/notifications/me/pending` | `200`, `401` | Jugador autenticado |
| `GET` | `/api/v1/notifications/me/history` | `200`, `401` | Jugador autenticado |
| `POST` | `/api/v1/notifications/me/read` | `200`, `400`, `401` | Jugador autenticado |
| `GET` | `/api/v1/banners` | `200` | Público, sin testimonio |
| `GET` | `/api/v1/admin/banners` | `200`, `401`, `403` | ADMINISTRATOR / SUPER_ADMINISTRATOR |
| `POST` | `/api/v1/admin/banners` | `201`, `400`, `401`, `403` | ADMINISTRATOR / SUPER_ADMINISTRATOR |

El `playerId` de `/me/*` se deriva siempre del testimonio JWT de Cognito (mismo mecanismo que el resto de servicios), nunca de la URL ni del cuerpo. MODERATOR no está autorizado sobre el banner: HU-38 solo nombra Admin y Super Admin.

**Publicada por Caddy** con reglas dedicadas: `handle /api/v1/admin/banners*` y `handle /api/v1/notifications*` y `handle /api/v1/banners*` en `compose/Caddyfile`, todas hacia `notifications:3004`. `handle /api/v1/admin/banners*` va **antes** que la regla general `handle /api/v1/admin*` (hacia Catalog): sin esa precedencia, `/api/v1/admin/banners` caería en el comodín de Catalog. Verificado con `caddy adapt` (el bloque de banners queda antes en la ruta compilada) y con peticiones reales contra un `caddy:2-alpine` en ejecución, no solo por inspección del fichero.

Depende internamente de Player-Inventory para resolver destinatarios de `catalog.product.suspended`/`reactivated` -ver `PATCH .../products/:id/owners` en la sección de Player/Inventory más abajo-; esa llamada es servicio-a-servicio, nunca alcanzable desde Web ni desde Internet.

Especificación: [Nexus-Battle-VI/Nexus-Battle-Management#46](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/46). Implementación: [Nexus-Battle-VI/Nexus-Battle-Notifications#20](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/20), [#21](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/21), [#22](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/22) (las tres mergeadas a `develop`). Ninguna afirma despliegue: solo que el contrato está implementado e integrado en `develop`, y que este repositorio ya lo enruta y configura en la composición de referencia.

**No implementa correo** (HU-38.6, ver Notifications#20): la notificación es exclusivamente in-app + banner.

**Readiness**: `GET /health/ready` añade la comprobación `catalog-notifications` únicamente cuando `CATALOG_NOTIFICATIONS_HTTP_ENABLED=true`, y esa comprobación solo verifica Mongo (`ping`). La ausencia de `PLAYER_INVENTORY_BASE_URL`/`INTERNAL_SERVICE_AUTH_SECRET` **no** hace fallar el readiness ni impide arrancar: es una degradación controlada y deliberada de Notifications#21 (cae en `UnavailableProductOwnersResolver`, y `suspended`/`reactivated` quedan como `Retry`/`DeadLetter` en vez de perderse), no una dependencia obligatoria inventada aquí. Este repositorio no modifica esa decisión.

## Convenciones comunes

| Aspecto | Convención |
| --- | --- |
| Prefijo | `/api` en los cinco servicios NestJS |
| Formato | JSON |
| **Importes** | **Entero en la unidad mínima de la moneda** |
| Fechas | ISO 8601 en UTC |
| Identificadores de catálogo | Implementado: SKU kebab-case. Objetivo ADR-013: `productId` UUID y SKU como alias temporal |
| Campos no declarados | **Rechazados con `400`** |
| Errores | `{ "statusCode", "message", "error" }` de NestJS |

El rechazo de campos no declarados no es un detalle de configuración: impide que un cliente fije el `status` de un producto, el `total` de un pedido o los `roles` de una cuenta. Hay pruebas de integración que lo verifican en los cinco servicios.

## Contrato de errores por capa

```text
DomainError                 -> 400 Bad Request
AccountAlreadyExists        -> 409 Conflict
ProductAlreadyExists        -> 409 Conflict
*NotFoundError              -> 404 Not Found
ProductNotPurchasable       -> 422 Unprocessable Entity
```

El dominio y la capa de aplicación **no conocen HTTP**. La correspondencia vive en el adaptador de entrada, en un único método `translate` por controlador.

## Estado

**Los servicios no se consumen entre sí todavía.** Estos contratos están implementados y probados, pero la integración real depende de [ADR-006](../adr/ADR-006-messaging.md).

La única excepción es `Nexus-Battle-Web`, que consume el contrato de Catalog en su pantalla implementada.
