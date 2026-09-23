# Catálogo de eventos y mensajes

## Estado

**Ningún evento cruza todavía un transporte real entre procesos distintos -falta `terraform apply`-, pero el wiring de configuración de los dos extremos ya está completo.** Los eventos existentes se emiten dentro de sus agregados y se registran en observabilidad. [ADR-017](../adr/ADR-017-catalog-events-sqs.md) está `Accepted` ([Management #284](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/284#issuecomment-5519755749), merge de [Infrastructure #65](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/65)) para SQS con `catalog.product.created`, su cola y DLQ ya están **Provisioned in IaC** (`infra/modules/catalog_events_queue`, Infrastructure#93). Notifications activa su consumo de forma independiente de su cola general (`CATALOG_QUEUE_DRIVER`, [Notifications#23](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/23)) y Catalog implementa el dispatcher del outbox que publica hacia la cola ([Catalog#51](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/51)); esta Task activa ese productor en el nodo real (`CATALOG_EVENT_DISPATCH_ENABLED=true` en `compose/nodes/app.yml`). Nada de esto equivale a desplegado: no se ejecutó `terraform apply`, así que la cola no existe todavía en AWS.

Los eventos de ciclo de vida (`suspended`/`reactivated`/`inventory.adjusted`/`premium.configured`) ya tienen decisión de transporte: [ADR-018](../adr/ADR-018-catalog-lifecycle-events-transport.md) está `Accepted` ([Management #314](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/314#issuecomment-5562149960)) para una cola SQS compartida entre los cuatro, con su propia DLQ, **distinta** de la de `catalog.product.created` y de la cola general de Notifications. Su cola y DLQ ya están **Provisioned in IaC** (`infra/modules/catalog_lifecycle_events_queue`, módulo Terraform separado del de ADR-017 para no arriesgar esos recursos). Architecture Accepted, wiring de configuración completo en ambos extremos (Notifications#24 desacopló su consumo de la cola general; Catalog#51 implementó el dispatcher; esta Task activa el productor en el nodo real); deployment pendiente: no se ejecutó `terraform apply`.

El catálogo mezcla contratos internos ya implementados con un contrato externo ya aceptado pero sin transporte desplegado. Cada tabla indica la diferencia; no se presenta el AsyncAPI nuevo como runtime existente.

## Convención de nombres

```text
<contexto>.<agregado>.<hecho-en-pasado>
```

El hecho va en pasado porque un evento describe algo que **ya ocurrió**. Un nombre en imperativo describiría un comando, que es otra cosa: un comando puede rechazarse, un evento no.

## Campos comunes

Todo evento incluye:

| Campo | Tipo | Significado |
| --- | --- | --- |
| `name` | `string` | Identificador del evento |
| `aggregateId` | `string` | Identidad del agregado que lo emitió |
| `occurredAt` | `Date` | Cuándo ocurrió el hecho |

`occurredAt` **se recibe desde fuera del dominio**, mediante `ClockPort`. Ninguna entidad lee el reloj del sistema, lo que hace los agregados deterministas y verificables sin falsear temporizadores globales.

### Envelope externo versionado

Los eventos que crucen un transporte usan un envelope adicional con `eventId`,
`eventType`, `eventVersion`, `aggregateId`, `occurredAt`, `producer`,
`correlationId` y `data`. `eventId` permanece estable en outbox, reintentos, SQS
e inbox y es la clave de idempotencia. El contrato formal inicial está en
[catalog-events-v1.asyncapi.yaml](catalog-events-v1.asyncapi.yaml).

## Account

| Evento | Cuándo | Campos propios |
| --- | --- | --- |
| `account.registered` | Se registra una cuenta | `email`, `displayName` |
| `account.verified` | La cuenta demuestra control del correo | `email` |
| `account.email-changed` | Cambia la dirección | `previousEmail`, `newEmail` |

## Player / Inventory

| Evento | Cuándo | Campos propios |
| --- | --- | --- |
| `inventory.item.added` | Se añaden unidades | `itemId`, `quantity`, `resultingQuantity` |
| `inventory.item.removed` | Se retiran unidades | `itemId`, `quantity`, `resultingQuantity` |

Ambos incluyen la cantidad de la operación **y la resultante**, de modo que un consumidor puede reconstruir el saldo sin consultar el servicio.

## Auction

| Evento | Cuándo | Campos propios |
| --- | --- | --- |
| `auction.settled.v1` | Una subasta queda liquidada durablemente, después de Wallet e Inventory | envelope V1 + `auctionId`, `productId`, `sellerId`, `resultType`, `settledAt`; con ganador añade `winnerId`, `winningBidId`, `finalAmountCredits` y `loserBidderIds` |

**HU-65.6 / Management #328.** El contrato formal es
[auction-settlement-events-v1.asyncapi.yaml](auction-settlement-events-v1.asyncapi.yaml).
Auction es productor y Notifications es el único consumidor competitivo de su
cola SQS Standard dedicada. Es un hecho de integración, no un comando por
destinatario: Notifications decide las representaciones in-app para vendedor,
ganador y perdedores.

`eventId` es obligatoriamente `auction:{auctionId}:settled` y `correlationId`
es `auction:{auctionId}:settlement`; ambos permanecen estables en outbox,
reintentos, SQS y redrive. `aggregateId` y `data.auctionId` son el mismo ID.

- `WITH_WINNER` exige ganador, puja ganadora, importe final y
  `loserBidderIds`; estos son IDs de usuario únicos calculados como
  `distinct(all bidderIds) - winnerId`, sin historial de pujas y sin incluir
  al ganador.
- `WITHOUT_BIDS` omite todos los campos de ganador y `loserBidderIds`; no usa
  `null`. Solo genera una notificación dirigida al vendedor.
- `productName` no forma parte de V1: `productId` es la referencia funcional
  mínima. Puede añadirse opcionalmente en una evolución compatible si una UX
  posterior lo necesita.
- La comisión no reembolsada es una regla de negocio de Auction/Wallet; no se
  transporta `feeCredits`. Notifications puede expresar la regla sin conocer
  el monto.

El productor debe comprobar que el JSON serializado cabe en el máximo
contractual de **64 KiB**. SQS Standard admite hasta 256 KiB: 64 KiB es un
guardrail del proyecto, no una restricción nativa de AWS. La
lista compacta de IDs únicos es el único conjunto variable permitido; no se
introduce segmentación en V1 porque el dominio actual no demuestra que pueda
exceder el límite. Si ocurriera, requerirá un contrato versionado/evolución,
no truncar destinatarios silenciosamente.

La entrega es at-least-once y no hay orden global. Auction marca
`published_at` solamente tras `SendMessage` exitoso. Si este falla, queda
`null` y el dispatcher reintenta. Si el proceso cae entre enviar y marcar,
puede publicar un duplicado: Notifications debe absorberlo con persistencia
durable y unicidad real de los IDs por destinatario:

```text
auction:{auctionId}:settled:seller:{sellerId}
auction:{auctionId}:settled:winner:{winnerId}
auction:{auctionId}:settled:loser:{userId}
```

Para `WITH_WINNER`, Notifications genera como máximo un aviso por rol y no
genera el de perdedor para el ganador. Si un ID coincide de forma anómala entre
seller, winner y perdedor, debe deduplicar por destinatario con precedencia
`winner > seller > loser`; no se emiten dos mensajes de resultado para la
misma persona. Para `WITHOUT_BIDS`, solo se genera el de vendedor.

La secuencia no acopla settlement a Notifications:

```text
Auction DB transaction -> settlement COMPLETED + outbox durable -> dispatcher
-> SQS -> Notifications -> Mongo notification
```

Una caída de Notifications no revierte Wallet ni Inventory: el mensaje queda
reintentable en outbox/SQS. Un error transitorio conserva el mensaje hasta que
venza/extienda su visibilidad; a los cinco receives se mueve a DLQ. El redrive
manual es administrativo y seguro solo porque el consumidor es idempotente.
Payload inválido o versión no soportada va a DLQ de forma controlada.

Los fixtures contractuales obligatorios están como ejemplos AsyncAPI: un
`WITH_WINNER` con seller, winner y dos perdedores distintos, y un
`WITHOUT_BIDS`. Las implementaciones deben además rechazar: ganador incluido
en `loserBidderIds`, `WITH_WINNER` sin `winnerId`, y `WITHOUT_BIDS` con un
campo de ganador.

### Topología, configuración y seguridad futuras

La topología definida para una futura tarea de IaC es deliberadamente separada
de Catalog:

```text
nexus-battle-{environment}-auction-settlement-notifications
nexus-battle-{environment}-auction-settlement-notifications-dlq
```

Debe reproducir el patrón SQS existente: Standard, long polling de 20 s,
visibility timeout de 60 s, retención principal de 4 días, DLQ de 14 días,
SSE-SQS, máximo contractual de 64 KiB y `maxReceiveCount: 5`. La política de
redrive de la DLQ solo acepta la cola principal como fuente. No hay orden
global ni deduplicación del broker; la garantía es at-least-once.

El futuro módulo Terraform debe conceder únicamente sobre el ARN de la cola
principal: Auction `sqs:SendMessage`; Notifications `sqs:ReceiveMessage`,
`sqs:DeleteMessage`, `sqs:ChangeMessageVisibility` y
`sqs:GetQueueAttributes`. No concede `sqs:*`, gestión de la DLQ ni redrive al
rol de ejecución. La demo actual comparte un rol de nodo, por lo que esos
permisos se declaran separados por owner y recurso aunque aún no se puedan
aislar por contenedor.

Las variables de runtime propuestas, siguiendo los nombres de Catalog, son:

| Servicio | Variable | Uso futuro |
| --- | --- | --- |
| Auction | `AUCTION_SETTLEMENT_QUEUE_URL` | URL de la cola para el dispatcher |
| Auction | `AUCTION_SETTLEMENT_EVENT_DISPATCH_ENABLED` | Opt-in seguro del dispatcher, análogo a `CATALOG_EVENT_DISPATCH_ENABLED` |
| Notifications | `AUCTION_SETTLEMENT_QUEUE_URL` | Misma URL de consumo |
| Notifications | `AUCTION_SETTLEMENT_QUEUE_DRIVER` | Driver dedicado (`sqs`/`memory`), sin acoplarse a la cola general |

Estas son especificaciones para el wiring posterior de Terraform/Compose y
los dos servicios; esta documentación no crea recursos, no modifica Compose y
no habilita ningún producer o consumer.

## Catalog

| Evento | Cuándo | Campos propios |
| --- | --- | --- |
| `catalog.product.created` | **Aceptado externo V1 (ADR-017 `Accepted`):** se confirma un Producto canónico | envelope V1 + `productId`, `name`, `type`, `lifecycleStatus`, `imageUrl` |
| `catalog.product.suspended` | **En outbox (HU-35, Catalog #49):** se suspende (borrado lógico) un Producto | envelope V1 + snapshot completo del producto (`catalogProductLifecycleDataV1`) |
| `catalog.product.reactivated` | **En outbox (HU-35, Catalog #49):** se reactiva un Producto suspendido | envelope V1 + snapshot completo del producto (`catalogProductLifecycleDataV1`) |
| `catalog.product.inventory.adjusted` | **En outbox (HU-34, `AdjustProductInventory`):** cambia el tiraje de un Producto | envelope V1 + snapshot completo del producto (`catalogProductLifecycleDataV1`) |
| `catalog.product.premium.configured` | **En outbox (HU-36, `ConfigureProductPremium`):** cambia la condición Premium de un Producto | envelope V1 + snapshot completo del producto (`catalogProductLifecycleDataV1`) |
| `catalog.product.published` | **Interno heredado:** un producto pasa a estar disponible | `productName`, `category`, `priceAmount`, `priceCurrency` |
| `catalog.product.price-changed` | Cambia el precio | `previousAmount`, `newAmount`, `currency` |
| `catalog.product.archived` | Deja de estar disponible | — |

`price-changed` incluye el importe anterior de forma deliberada: permite detectar la dirección del cambio sin consultar el servicio.

Los cuatro eventos de ciclo de vida (`suspended`, `reactivated`,
`inventory.adjusted`, `premium.configured`) **ya se escriben en el outbox de
MongoDB de Catalog** (verificado en código: `UpdateProductLifecycleStatus`,
`AdjustProductInventory`, `ConfigureProductPremium`, ADR-015), igual que
`catalog.product.created`, pero a diferencia de este **no tienen canal ni
operación en el AsyncAPI**: ADR-017 -`Accepted`- cubre únicamente la cola de
`catalog.product.created`; el transporte de estos cuatro eventos de ciclo de
vida todavía no tiene una decisión/extensión arquitectónica propia, y este
mismo documento ya establece que no deben enviarse por esa cola. Se documentan como componentes
reutilizables en
[catalog-events-v1.asyncapi.yaml](catalog-events-v1.asyncapi.yaml) para fijar
el contrato exacto que Catalog produce.

**Estado real de HU-38 (Management #46), auditado al integrar Infrastructure
con Notifications:**

- **Consumidor implementado:** `Nexus-Battle-VI/Nexus-Battle-Notifications#20`/`#21`/`#22`
  (mergeadas a `develop`) consumen los cinco eventos anteriores -incluido
  `catalog.product.created`- y generan `CatalogNotification`. `#21` añade la
  resolución real de propietarios contra Player-Inventory para
  `suspended`/`reactivated`; `#22` corrige el tratamiento de sus fallos
  transitorios (reintento/DLQ en vez de pérdida silenciosa).
- **Productor implementado:** [Catalog#51](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/51)
  añade `DispatchProductOutbox`, el proceso que reclama los cinco eventos
  aprobados de la colección `outbox` de MongoDB (allowlist exacta de
  `eventType`; otros eventos, como `catalog.product.stock.depleted`,
  permanecen intactos) y los publica hacia la cola correspondiente vía
  `@aws-sdk/client-sqs`, sin credenciales estáticas. Por defecto
  (`CATALOG_EVENT_DISPATCH_ENABLED=false`) no publica nada -despliegue
  seguro-; esta Task lo activa explícitamente en el nodo real.
- **Transporte de `catalog.product.created`:** ADR-017 está `Accepted`
  (Management #284, merge de Infrastructure #65) y **Provisioned in
  IaC**: `infra/modules/catalog_events_queue` ([Infrastructure #93](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/93)) declara la cola Standard y su DLQ con los
  parámetros exactos de ADR-017, y el rol del nodo `app` recibe
  `sqs:SendMessage` (Catalog) y `sqs:ReceiveMessage`/`DeleteMessage`/
  `ChangeMessageVisibility`/`GetQueueAttributes` (Notifications). Wiring de
  runtime completo en ambos extremos: Notifications consume con
  `CATALOG_QUEUE_DRIVER=sqs` (Notifications#23); Catalog publica con
  `CATALOG_EVENT_DISPATCH_ENABLED=true` + `CATALOG_EVENTS_QUEUE_URL`, el
  MISMO output que `CATALOG_QUEUE_URL` (esta Task, `compose/nodes/app.yml`).
  **No Applied/deployed**: ningún `terraform apply` se ejecutó, así que la
  cola no existe todavía en AWS y el evento no fluye.
- **Transporte de los eventos de ciclo de vida: Architecture Accepted,
  Provisioned in IaC, wiring de runtime completo, deployment pendiente.**
  [ADR-018](../adr/ADR-018-catalog-lifecycle-events-transport.md) está
  `Accepted` ([Management #314](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/314#issuecomment-5562149960))
  para una cola SQS compartida entre los cuatro eventos, con los mismos
  parámetros que ADR-017 y una DLQ propia, **distinta** de la de
  `catalog.product.created` y de la cola general de Notifications. Su cola y
  DLQ ya están **Provisioned in IaC**:
  `infra/modules/catalog_lifecycle_events_queue`, un módulo Terraform
  **separado** del de ADR-017 -condición explícita de aprobación en
  Management#314: no modificar ni arriesgar la cola de `created` ya
  existente-. **No Applied/deployed**: ningún `terraform apply` se ejecutó.
- **Acoplamiento de Notifications, ya corregido:**
  [Notifications#24](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/24)
  desacopló `lifecycleQueue` de `QUEUE_DRIVER` (interruptor de la cola
  GENERAL) mediante `CATALOG_LIFECYCLE_QUEUE_DRIVER` propio, y dejó de
  reenviar a `deadLetterQueueUrl` (DLQ GENERAL) -mismo patrón que
  [Notifications#23](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/23)
  ya aplicó a `catalog.product.created`-.
- **Consecuencia, resumen del estado real:** `catalog.product.created` tiene
  ADR `Accepted`, cola `Provisioned in IaC` (Infrastructure#93), dispatcher
  implementado (Catalog#51) y wiring de runtime completo en Notifications
  (`CATALOG_QUEUE_DRIVER=sqs`) y en Catalog (`CATALOG_EVENT_DISPATCH_ENABLED=true`
  + `CATALOG_EVENTS_QUEUE_URL`, esta Task); le falta únicamente
  `terraform apply`. Los cuatro eventos de ciclo de vida tienen ADR
  `Accepted` (ADR-018), cola `Provisioned in IaC`
  (`infra/modules/catalog_lifecycle_events_queue`) y el mismo wiring de
  runtime completo de ambos lados (`CATALOG_LIFECYCLE_QUEUE_DRIVER=sqs` en
  Notifications, `CATALOG_EVENT_DISPATCH_ENABLED=true` +
  `CATALOG_LIFECYCLE_QUEUE_URL` en Catalog); les falta igualmente
  `terraform apply`. La configuración de runtime está lista para que el
  evento fluya en cuanto la infraestructura se aplique -no antes-. La
  integración Notifications↔Player-Inventory (resolución de destinatarios)
  sigue siendo real e independiente de todo esto.

### Variable del productor de Catalog

`CATALOG_EVENTS_QUEUE_URL` es la variable que Catalog#51 usa para publicar
hacia la cola de ADR-017 -Notifications ya la acepta como alias equivalente
a `CATALOG_QUEUE_URL` en su `env.ts` (`env['CATALOG_QUEUE_URL'] ??
env['CATALOG_EVENTS_QUEUE_URL']`)-, así que ambos servicios comparten el
mismo output (`infra/modules/catalog_events_queue.queue_url`) bajo dos
nombres de variable distintos: uno por cada servicio que ya lo fijó antes de
que esta Task los conectara. Para la cola de ciclo de vida no hace falta
alias: Catalog y Notifications ya usan el mismo nombre,
`CATALOG_LIFECYCLE_QUEUE_URL`.

### DLQ de los eventos de ciclo de vida — ADR-018 Accepted, wiring completo, aplicación pendiente

Notifications#22 ya implementaba reintento/DLQ del lado del consumidor
(`CatalogLifecycleEventsConsumer`: `Retry` reencola, `DeadLetter` va a la cola
de fallidos), pero hasta [Notifications#24](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/24)
su configuración (`deadLetterQueueUrl` en `catalog-notifications-application.ts`)
seguía siendo la **DLQ general** de notificaciones transaccionales.
Notifications#23 ya había corregido esto para
`catalogQueue`/`catalog.product.created`; Notifications#24 aplicó el mismo
patrón a `lifecycleQueue`: ya no reenvía a la DLQ general.

[ADR-018](../adr/ADR-018-catalog-lifecycle-events-transport.md) está
`Accepted` ([Management #314](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/314#issuecomment-5562149960))
con exactamente esta topología: una DLQ propia de la cola lifecycle,
compartida entre los cuatro `eventType` de ciclo de vida pero **distinta** de
la DLQ de `created` y de la general. Esa DLQ ya está **Provisioned in IaC**
(`infra/modules/catalog_lifecycle_events_queue`) y el wiring de configuración
(`CATALOG_LIFECYCLE_QUEUE_DRIVER=sqs` en `compose/nodes/app.yml`, esta Task)
ya está completo. **No se ejecutó `terraform apply`**: la cola no existe
todavía en AWS, así que un mensaje irreprocesable no tiene, hoy, ninguna DLQ
real a la que llegar -el mecanismo está listo, no desplegado-.

## Community

| Evento | Cuándo | Campos propios |
| --- | --- | --- |
| `community.post.published` | Se publica un mensaje | `postId`, `authorId`, **`contentLength`** |
| `community.post.hidden` | Se oculta por moderación | `postId`, `moderatorId` |
| `community.thread.closed` | Se cierra un hilo | `moderatorId` |

**`community.post.published` transporta la longitud del contenido, no el contenido.**

Un evento que cruza el límite del servicio no debe llevar texto escrito por personas usuarias fuera del contexto que lo custodia. Hay una prueba que verifica que el texto no aparece en el evento serializado.

## Commerce

| Evento | Cuándo | Campos propios |
| --- | --- | --- |
| `commerce.order.confirmed` | Se confirma un pedido | `customerId`, `totalAmount`, `currency`, `lineCount` |
| `commerce.order.cancelled` | Se cancela un pedido | `customerId`, `reason` |

`order.confirmed` es el evento que iniciaría la **saga de checkout**: transporta lo necesario para reservar inventario y notificar. La saga no está implementada.

## Mensaje de entrada de Notifications

Es el único contrato **de entrada** asíncrono del sistema.

```json
{
  "notificationId": "n-8f3c",
  "recipient": "jugador@nexus.test",
  "templateId": "account-verification-code",
  "variables": { "displayName": "Ana", "code": "123456", "expiresInMinutes": 10 },
  "idempotencyKey": "opcional"
}
```

| Campo | Obligatorio | Regla |
| --- | --- | --- |
| `notificationId` | Sí | Texto no vacío |
| `recipient` | Sí | Correo válido; se valida en el dominio |
| `templateId` | Sí | Debe existir en el catálogo de plantillas |
| `variables` | No | Objeto plano; **no se admiten objetos anidados** |
| `idempotencyKey` | No | Si se omite se usa `notificationId` |

**El número de intento no viaja en el mensaje.** Proviene del contador de entregas de la cola (`ApproximateReceiveCount` en SQS). Esa decisión corrigió un defecto real: sin ella, el agregado se reconstruía desde cero en cada entrega y la política de reintentos nunca se agotaba.

Un mensaje malformado va **directo a la cola de mensajes fallidos**, sin reintento: reintentarlo produciría el mismo error y bloquearía el consumo.

## Catálogo de plantillas

Los identificadores forman parte del contrato. Añadir o retirar uno **es un cambio de contrato**.

| Plantilla | Variables | Emisor previsto |
| --- | --- | --- |
| `account-verification-code` | `displayName`, `code`, `expiresInMinutes` | Account |
| `account-welcome` | `displayName` | Account |
| `account-deletion-closed` | Ninguna | Account (HU-43.4, Management #306) |
| `commerce-order-confirmed` | `displayName`, `orderId`, `total` | Commerce |

Los marcadores sin valor se sustituyen por cadena vacía, **nunca por `undefined`**: un correo con la palabra «undefined» en el cuerpo es un fallo visible para quien lo recibe.

## Reglas de evolución

| Cambio | ¿Compatible? |
| --- | --- |
| Añadir un campo opcional | Sí |
| Añadir un evento nuevo | Sí |
| **Retirar un campo** | No |
| **Renombrar un campo o un evento** | No |
| **Cambiar el tipo de un campo** | No |
| **Retirar una plantilla** | No |

Un cambio incompatible exige versionar el evento y mantener ambas versiones hasta que no queden consumidores de la anterior.

## AsyncAPI

[catalog-events-v1.asyncapi.yaml](catalog-events-v1.asyncapi.yaml) formaliza la decisión aceptada de EN-027.4 (ADR-017) para `catalog.product.created`. Usa AsyncAPI 3.0.0 y declara una cola SQS Standard, envelope V1, productor Catalog y consumidor Notifications.

El contrato está aceptado y versionado, y la cola que declara ya está provisionada como código Terraform (`infra/modules/catalog_events_queue`); todavía no se aplicó contra la cuenta real. Los demás eventos de este catálogo no quedan adoptados por esa decisión y no deben enviarse por la cola de Producto.

[auction-settlement-events-v1.asyncapi.yaml](auction-settlement-events-v1.asyncapi.yaml)
formaliza HU-65.6 (Management #328) para `auction.settled.v1`. Declara una cola
SQS Standard y DLQ propias, pero **no** provisiona recursos ni afirma que
Auction o Notifications ya tengan dispatcher/consumer: esos cambios pertenecen
a sus respectivos repositorios.
