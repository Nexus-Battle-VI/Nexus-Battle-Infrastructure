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

Sin API de negocio. Su entrada es la cola de mensajes; el contrato está en [event-catalog.md](event-catalog.md).

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
