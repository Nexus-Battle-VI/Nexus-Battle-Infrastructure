# ADR-024 — Tiempo real para Subasta

- **Estado:** **Accepted** el 2026-10-07 — aceptado por decisión de guishe2207 (responsable de las Tasks de EN-034), con revisión y fusión de [Infrastructure#208](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/208) por GabrielSastoque. No hay validación separada de Product Owners y Scrum Masters registrada (ver «Evidencia de aceptación»)
- **Fecha:** 2026-10-07
- **Decide:** Arquitectura, con validación de Auction y Web
- **Relacionado:** [ADR-004](ADR-004-identity-directory.md), [ADR-007](ADR-007-aws-cost-optimized-platform.md), [ADR-010](ADR-010-reverse-proxy.md), [ADR-011](ADR-011-deployment-topology.md), [ADR-019](ADR-019-sprint-2-bounded-contexts.md), [ADR-020](ADR-020-realtime-combat.md), [EN-034 #523](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/523), [TASK EN-034.1 #583](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/583), [EPIC-07 #7](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/7), contrato borrador en [Nexus-Battle-Auction#98](https://github.com/Nexus-Battle-VI/Nexus-Battle-Auction/pull/98)

## Contexto

El requisito 7.7.13 exige tiempo real para el módulo de Subasta. Hoy Auction solo expone HTTP (`/api/v1/auctions`) y el contador regresivo de la Web se actualiza localmente, de modo que dos jugadores pueden ver durante un rato información distinta de la misma subasta: una puja confirmada, un cierre, una compra inmediata o una cancelación hecha desde otra sesión.

ADR-020 decidió el tiempo real de Combat y dejó previsto este caso, en su sección «Alcance»: *«Si una Historia de Usuario exige empuje en tiempo real para pujas, se reutiliza este mismo esquema con un ADR que lo extienda»*. Este ADR es esa extensión.

Restricciones ya decididas que no se reabren aquí:

- Sin API Gateway WebSocket, Lambda, AppSync ni ALB ([ADR-007](ADR-007-aws-cost-optimized-platform.md)).
- Todo el tráfico entra por Caddy ([ADR-010](ADR-010-reverse-proxy.md)). El `Caddyfile` ya enruta `/api/v1/auctions*` hacia `auction:3008`.
- La identidad es un testimonio de Cognito verificado en el servicio ([ADR-004](ADR-004-identity-directory.md)).
- Auction es un único contenedor en el nodo `app` ([ADR-011](ADR-011-deployment-topology.md), topología T2).
- Pujar, comprar de inmediato, cancelar y liquidar siguen siendo operaciones transaccionales de Auction ([ADR-019](ADR-019-sprint-2-bounded-contexts.md)). Este ADR no las modifica.

## Decisión

### Naturaleza del canal: señales de invalidación, solo lectura

El canal **no transporta estado autoritativo** ni recibe comandos. Avisa de *qué subasta cambió y en qué revisión*; el cliente recupera el estado con las consultas HTTP existentes. Consecuencias directas:

- Un evento perdido, tardío o duplicado no puede dejar un valor imposible: la siguiente lectura HTTP prevalece.
- La reconexión es un refetch de lo observado. No hay `resume`, `lastSeq` ni bitácora de eventos, a diferencia de Combat, donde el estado de sala sí se reconstruye desde el flujo.
- El cliente no ejecuta por sí mismo una puja, compra ni liquidación a partir de una señal.

### Transporte: el mismo de ADR-020

- **WebSocket (RFC 6455)** en `wss://nexus.simuladorupbbga.app/api/v1/auctions/realtime`.
- En Auction, `@nestjs/websockets` con el adaptador `@nestjs/platform-ws`, en la misma versión menor de NestJS que el resto del servicio.
- Caddy no cambia: `handle /api/v1/auctions*` ya lo cubre y `reverse_proxy` atiende la actualización sin configuración adicional. **Coste AWS: cero.**
- El `Caddyfile` actual no define timeouts de lectura ni de transporte que corten conexiones largas. El latido de 25 s (igual que ADR-020) cubre cualquier intermediario.

Se descartan Socket.IO, API Gateway WebSocket y SSE por los motivos de ADR-020. En particular, mantener SSE para Subasta y WebSocket para Combat obligaría a la Web a sostener dos mecanismos de conexión y dos flujos de autenticación para un ahorro marginal.

### Autenticación: ticket de un solo uso, nunca el JWT en la URL

Mismo esquema que ADR-020:

1. `POST /api/v1/auctions/realtime/tickets` con `Authorization: Bearer <JWT>`, con los roles que ya exigen las lecturas HTTP (`Player`, `GameMaster`).
2. Auction verifica el testimonio y devuelve un **ticket opaco**, ligado al `sub`, de **un solo uso** y con caducidad de **30 segundos**. Solo se guarda su hash.
3. El cliente abre el WebSocket sin credenciales en la URL y envía `{"type":"auth","ticket":"..."}` como primer mensaje.
4. Sin ticket válido en 5 s, el servidor cierra con código `4401`. Un ticket usado o caducado cierra igual.

El `sub` del ticket es la única identidad de la conexión.

### Mensajes del cliente

Solo tres tipos, todos de gestión de la conexión: `auth`, `subscribe` y `unsubscribe`. Cualquier otro mensaje se rechaza; no existen comandos de negocio por este canal. Límites: 20 suscripciones por conexión y 3 conexiones simultáneas por usuario; tamaño máximo de mensaje entrante de 1 KiB.

### Canales

| Canal | Quién lo observa | Recibe |
|---|---|---|
| `auctions/{auctionId}` | Detalle de subasta, panel de puja | Señales de esa subasta |
| `auctions` | Marketplace | Señales de cualquier subasta, sin `summary` |

Suscribirse exige poder hacer el `GET` equivalente. Marketplace **invalida** sus listas y no intenta parchearlas, porque sus claves de caché incluyen filtros y paginación.

### Señal

`AuctionRealtimeSignalV1`: `signalVersion`, `signalId` (`auction:{auctionId}:r{revision}`), `auctionId`, `revision`, `reason` (`PUBLISHED`, `BID_ACCEPTED`, `BOUGHT_NOW`, `SETTLED`, `CANCELLED`), `occurredAt` y un `summary` opcional (`status`, `currentBidCredits`, `bidCount`) que solo es una pista para pintar antes del refetch. El detalle exacto está en el contrato publicado en `docs/contracts` (TASK EN-034.2).

- **Orden y deduplicación** por `(auctionId, revision)`: el cliente descarta cualquier señal con `revision` menor o igual a la última vista para esa subasta. `occurredAt` es informativo y nunca ordena.
- **Qué no viaja:** `bidderId`, `sellerId`, `winnerId`, `loserBidderIds` ni ningún dato personal. Los eventos `auction.*` v1 entre servicios sí los llevan, por eso **no se reutilizan tal cual** hacia el navegador.
- Tamaño máximo de una señal: 1 KiB.

### Autoridad: persistir y luego difundir

- Auction añade a cada subasta una columna **`revision bigint`**, incrementada **dentro de la misma transacción** que cualquier cambio observable (puja confirmada, compra inmediata, cierre, cancelación, publicación).
- La señal se difunde **solo después del commit**. Nunca se difunde un estado que luego no existe.
- Se crea el evento de dominio de compra inmediata (`BOUGHT_NOW`), que hoy no existe.

### Reconexión

- Al caer la conexión el cliente reconecta con backoff exponencial y jitter (tope sugerido 30 s), pide un ticket nuevo y, al reabrir, **invalida las consultas de subasta que estaba observando**.
- Latido del servidor cada 25 s; una conexión sin respuesta se cierra.
- Mientras está desconectado, la interfaz no presenta el valor como «en vivo».
- **Un reinicio de Caddy o de Auction cierra todas las conexiones.** Es esperado: el estado sobrevive porque vive en PostgreSQL, no en la memoria del proceso.

### Reversión

El interruptor `AUCTION_REALTIME_ENABLED` desactiva el endpoint de suscripción y el de tickets. El cliente, ante un fallo permanente, cae a sondeo HTTP con intervalo largo. Ninguno de los dos caminos toca reglas de puja, créditos ni estados persistidos. La columna `revision` es aditiva y no necesita revertirse.

### Alcance

- **Dentro:** actualización de oferta vigente y `bidCount`, compra inmediata, cierre, cancelación y publicación; sincronización entre sesiones; reconexión; invalidación de Marketplace y Detalle.
- **Fuera:** métricas de negocio (HU-91); notificaciones persistentes (pertenecen a Notifications); el panel personal de HU-89, que se evalúa en TASK EN-034.4.

## Consecuencias

**Lo que se gana**

- Una sola autoridad del estado: el canal no puede divergir del backend porque no lo reemplaza.
- Un único mecanismo realtime, un único flujo de autenticación y una sola implementación de cliente reutilizable para la Web.
- Sin recurso AWS nuevo ni cambio de Caddy: coste cero.
- Reversión sin efecto sobre datos.

**Lo que cuesta**

- **Auction queda en una sola réplica para esta función.** Las suscripciones viven en la memoria del proceso: con dos réplicas, un cambio confirmado en una no llegaría a los clientes conectados a la otra. Escalar exigiría un bus de difusión (por ejemplo `LISTEN/NOTIFY` de PostgreSQL) y un ADR nuevo. Mientras tanto el estado nunca queda incorrecto, solo tarda hasta el siguiente refetch.
- **Memoria:** el contenedor tiene `mem_limit: 160m`. Con la carga de demostración (≤ 30 usuarios concurrentes, `docs/costs/assumptions.md`) las conexiones caben, pero los límites de suscripciones y conexiones son obligatorios y TASK EN-034.2 debe medir el consumo.
- **Cada despliegue de Auction desconecta a todos los observadores.**
- Una migración (`revision`) y un evento de dominio nuevos en Auction.
- La Web debe implementar reconexión, descarte por `revision` e invalidación por clave; su módulo de Subasta (HU-87 y HU-88) aún no existe.

## Alternativas consideradas

| Alternativa | Por qué se descartó |
| --- | --- |
| SSE (`text/event-stream`) | Válido para difundir, pero `EventSource` no envía `Authorization` y obligaría a resolver aparte la autenticación; ADR-020 ya eligió WebSocket y descartó SSE, y mantener dos mecanismos cuesta más de lo que ahorra |
| Transportar el estado completo por el canal | Convierte al canal en fuente de verdad y exige replay, orden y bitácora; las señales de invalidación con refetch lo evitan |
| Reutilizar los eventos `auction.*` v1 hacia el navegador | Contienen identificadores de postores, vendedor y ganador |
| Derivar `revision` de `bidCount` | No cubre cancelación, compra inmediata ni publicación |
| Difusión por un bus compartido desde el inicio | Coste y complejidad sin necesidad con una sola réplica (ADR-011); queda como camino de escalado |
| Sondeo HTTP periódico como mecanismo principal | Latencia visible en las pujas y carga constante sin actividad; se conserva solo como recuperación |
| API Gateway WebSocket | Prohibido por ADR-007 |

## Evidencia de aceptación

- **Aceptado el 2026-10-07** por decisión de guishe2207, responsable de las Tasks de EN-034. El PR [Infrastructure#208](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/208) fue aprobado y fusionado por GabrielSastoque. **No se ha registrado una validación separada de Product Owners y Scrum Masters**, que ADR-020 sí tuvo; si la gobernanza de [ADR-001](ADR-001-repository-strategy.md) la exige para este ADR, debe añadirse aquí como evidencia.
- **Contrato publicado:** [auction-realtime-v1.md](../contracts/auction-realtime-v1.md).
- **Aceptar no es implementar:** Auction todavía no tiene WebSocket. Se añade con TASK EN-034.2 (#584).
- **Implementado** en Nexus-Battle-Auction#99 (TASK EN-034.2, Management #584): migracion 021 con `revision` y triggers `pg_notify`, oyente `LISTEN`, hub de suscripciones, tickets y gateway, todo tras `AUCTION_REALTIME_ENABLED` (apagado por defecto). La emision se resolvio en PostgreSQL y no en el codigo del repositorio: asi cubre todos los caminos de escritura y respeta «persistir y luego difundir» por construccion.
- **Correccion sobre ADR-020:** la nota de ADR-020 que describe el esquema con ticket como no integrado esta desactualizada; `develop` de Nexus-Battle-Combat ya registra `RealtimeTicketController` con ticket de un solo uso. Auction replico ese mismo patron (puertos, almacen en memoria y codec propios). Si ambos servicios evolucionan, conviene extraer la emision y verificacion de tickets a un componente compartido.
- La verificación de una conexión de más de 60 s a través de Caddy queda como prueba en TASK EN-034.5 (#587).
