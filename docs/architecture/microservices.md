# Microservicios

Diagrama en [microservices-component.puml](../diagrams/microservices-component.puml).

## Inventario de deployables

| Deployable | Puerto | Tipo | Team | Imagen base |
| --- | --- | --- | --- | --- |
| `Nexus-Battle-Web` | 8080 | Estáticos sobre Caddy | Alfa + Beta + Gama | `caddy:2-alpine` |
| `Nexus-Battle-Account` | 3000 | API NestJS | Alfa | `node:24-alpine` |
| `Nexus-Battle-Notifications` | 3001 (solo salud) | Worker Node | Alfa | `node:24-alpine` |
| `Nexus-Battle-Player-Inventory` | 3002 | API NestJS | Alfa | `node:24-alpine` |
| `Nexus-Battle-Catalog` | 3003 | API NestJS | Gama | `node:24-alpine` |
| `Nexus-Battle-Community` | 3004 | API NestJS | Gama | `node:24-alpine` |
| `Nexus-Battle-Commerce` | 3005 | API NestJS | Beta | `node:24-alpine` |

El puerto 3001 de Notifications expone **únicamente** las sondas de salud: el worker no tiene API de negocio, su entrada es la cola de mensajes.

`Nexus-Battle-Web` no incluye runtime de Node en su imagen final: es Caddy sirviendo ficheros estáticos, lo que reduce su superficie de ataque.

## Superficie de cada servicio

### Account — bounded context Account / Identity

| Método | Ruta |
| --- | --- |
| `POST` | `/api/accounts` |
| `GET` | `/api/accounts/:id` |
| `POST` | `/api/accounts/:id/verification` |

Agregado `Account`. Estados `PENDING_VERIFICATION` → `ACTIVE` → `SUSPENDED`. Roles acumulativos sobre `PLAYER`, que no puede retirarse.

**No almacena contraseñas, hashes, sales ni tokens de sesión.**

### Player / Inventory

| Método | Ruta |
| --- | --- |
| `GET` | `/api/inventories/:ownerId` |
| `POST` | `/api/inventories/:ownerId/items` |
| `POST` | `/api/inventories/:ownerId/items/removals` |

Agregado `Inventory`. La capacidad limita **ranuras distintas**, no unidades totales: apilar más unidades de un objeto ya poseído no consume ranura, ni siquiera con el inventario lleno.

### Catalog

| Método | Ruta |
| --- | --- |
| `POST` | `/api/products` |
| `GET` | `/api/products` (admite `?category=`) |
| `GET` | `/api/products/:sku` |
| `POST` | `/api/products/:sku/publication` |
| `POST` | `/api/products/:sku/archival` |
| `POST` | `/api/products/:sku/price` |

Agregado `Product`. Estados `DRAFT` → `PUBLISHED` → `ARCHIVED`. Solo lo publicado es visible en las consultas públicas; un borrador responde `404` por regla de dominio, no por fallo.

### Community

| Método | Ruta |
| --- | --- |
| `POST` | `/api/threads` |
| `GET` | `/api/threads` |
| `GET` | `/api/threads/:threadId` |
| `POST` | `/api/threads/:threadId/posts` |
| `POST` | `/api/threads/:threadId/posts/:postId/hiding` |
| `POST` | `/api/threads/:threadId/closure` |

Agregado `Thread` con sus mensajes dentro. Los mensajes no son agregado propio porque las invariantes —no publicar en hilo cerrado, límite de 500 mensajes, identificador único— abarcan el hilo completo y no pueden verificarse mirando un mensaje aislado.

### Commerce

| Método | Ruta |
| --- | --- |
| `POST` | `/api/orders` |
| `GET` | `/api/orders?customerId=` |
| `GET` | `/api/orders/:orderId` |
| `POST` | `/api/orders/:orderId/lines` |
| `DELETE` | `/api/orders/:orderId/lines/:sku` |
| `POST` | `/api/orders/:orderId/confirmation` |
| `POST` | `/api/orders/:orderId/cancellation` |

Agregado `Order`. El total se calcula, no se almacena. El precio se congela al añadir la línea. Un pedido confirmado es inmutable.

**El contrato de alta de línea no acepta el precio**: lo determina el catálogo, no quien compra.

### Notifications

Sin API de negocio. Consume mensajes de la cola, resuelve la plantilla y entrega el correo, aplicando idempotencia y política de reintentos.

## Sondas comunes

Los siete deployables exponen:

| Ruta | Semántica |
| --- | --- |
| `/health/live` | El proceso responde. **No consulta dependencias** |
| `/health/ready` | Evalúa dependencias reales. `503` si alguna falla |
| `/version` | Servicio, versión y entorno |

En los servicios NestJS van bajo el prefijo `/api`. En Notifications, en la raíz del puerto 3001. En Web, el `Caddyfile` expone `/health`.

Una comprobación que lanza una excepción **cuenta como fallo, nunca como éxito**. Verificado por prueba en los seis servicios.

## Estructura interna, idéntica en los seis

```text
src/
  domain/            Entidades, objetos de valor, politicas y eventos
  application/       Casos de uso, puertos, DTO y errores
  adapters/
    inbound/http/    Controladores y contratos HTTP
    outbound/        Persistencia, mensajeria y utilidades
  infrastructure/    config, observability, health, bootstrap
```

Dos restricciones verificadas por CI mediante `no-restricted-imports` de ESLint:

- El dominio no importa NestJS, SDK de AWS, ORM, HTTP ni drivers de base de datos.
- La capa de aplicación depende de sus puertos, nunca de adaptadores concretos.

Los casos de uso son clases planas sin decoradores, registradas con fábricas explícitas en `infrastructure/bootstrap`. La capa de aplicación podría ejecutarse fuera de NestJS sin cambios.
