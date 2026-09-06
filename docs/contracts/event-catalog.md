# Catálogo de eventos y mensajes

## Estado

**Ningún evento se publica todavía hacia un transporte real.** Los eventos existentes se emiten dentro de sus agregados y se registran en observabilidad. [ADR-017](../adr/ADR-017-catalog-events-sqs.md) está `Accepted` ([Management #284](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/284#issuecomment-5519755749), merge de [Infrastructure #65](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/65)) para SQS con `catalog.product.created`, y la cola y su DLQ ya están **Provisioned in IaC** (`infra/modules/catalog_events_queue`); ninguna de las dos cosas equivale a desplegado: no se ejecutó `terraform apply` y Catalog no tiene dispatcher que alimente la cola. Los eventos de ciclo de vida (`suspended`/`reactivated`/`inventory.adjusted`/`premium.configured`) siguen `BLOCKED BY ARCHITECTURE DECISION`: ADR-017 no los cubre y no existe una extensión ni un ADR nuevo que lo haga.

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
- **Productor auditado y confirmado ausente:** Catalog escribe los cinco
  eventos en su colección `outbox` de MongoDB, pero **no existe ningún
  proceso -dispatcher, worker, poller- que lea esa colección y publique hacia
  ningún transporte**. Se buscó explícitamente en el código de Catalog
  (`dispatcher`, `worker`, `poller`, `OutboxDispatcher`) y no aparece: solo
  existe el repositorio de persistencia del outbox (`claim`, `record`), no
  quien despacha. **Esto es una brecha real de Catalog, no de
  Infrastructure**, y requiere un PR separado en ese repositorio.
- **Transporte de `catalog.product.created`:** ADR-017 está `Accepted`
  (Management #284, merge de Infrastructure #65) y ahora **Provisioned in
  IaC**: `infra/modules/catalog_events_queue` ([Infrastructure #93](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/93)) declara la cola Standard y su DLQ con los
  parámetros exactos de ADR-017, y el rol del nodo `app` recibe
  `sqs:SendMessage` (Catalog) y `sqs:ReceiveMessage`/`DeleteMessage`/
  `ChangeMessageVisibility`/`GetQueueAttributes` (Notifications). **No
  Applied/deployed**: ningún `terraform apply` se ejecutó, así que la cola no
  existe todavía en AWS. Y aunque se aplicara, sigue faltando el dispatcher
  del lado de Catalog que la alimente -ver el punto anterior-, así que el
  evento no fluye.
- **Transporte de los eventos de ciclo de vida: BLOCKED BY ARCHITECTURE
  DECISION.** ADR-017 cubre explícitamente solo `catalog.product.created`; no
  existe una extensión de ADR-017 ni un ADR nuevo que decida una cola
  dedicada, una cola por evento, fan-out o DLQ para
  `suspended`/`reactivated`/`inventory.adjusted`/`premium.configured`. Este
  cambio audita esa ausencia y no la resuelve ni la provisiona -provisionar
  SQS sin una decisión arquitectónica sería inventar la decisión dentro de un
  PR de infraestructura, que no es su lugar-.
- **Consecuencia:** el consumidor de Notifications (`CatalogLifecycleEventsConsumer`,
  `CatalogProductEventsConsumer`) está listo y probado, pero en cualquier
  entorno real opera en memoria local: `CATALOG_QUEUE_URL` ya se configura
  con el output real del módulo de Terraform, pero **no basta por sí sola**
  para activar el consumo real, porque el adaptador SQS de Notifications se
  activa con `QUEUE_DRIVER=sqs`, un interruptor GLOBAL que a su vez exige
  `QUEUE_URL` -la cola general de ADR-006 para notificaciones
  transaccionales-, que sigue `Proposed` y sin provisionar. Activar `sqs` sin
  esa cola general rompería el arranque de todo el worker, no solo del
  consumidor de `catalog.product.created`; por eso `QUEUE_DRIVER` se deja en
  `memory` en compose. `CATALOG_LIFECYCLE_QUEUE_URL` sigue sin ningún valor,
  porque no hay cola real que apuntarle (punto anterior). La integración
  Notifications↔Player-Inventory (resolución de destinatarios) sí es real y
  fue verificada en un cambio anterior; lo que falta es exclusivamente el
  tramo Catalog→transporte→Notifications, ahora en dos partes distintas: la
  infraestructura (provisionada en código, no aplicada) y el dispatcher de
  Catalog (inexistente).

### Nombre de variable recomendado para el dispatcher de Catalog

Catalog no tiene hoy ninguna variable de entorno relacionada con SQS
(auditado: solo existe `AWS_REGION`, usada por el almacenamiento de assets de
ADR-016). Para el PR que implemente el dispatcher del outbox, se recomienda
`CATALOG_EVENTS_QUEUE_URL`: Notifications ya la acepta como alias equivalente
a `CATALOG_QUEUE_URL` en su `env.ts` (`env['CATALOG_QUEUE_URL'] ??
env['CATALOG_EVENTS_QUEUE_URL']`), así que ambos servicios pueden compartir el
mismo nombre de variable para el mismo valor -el output `queue_url` de
`infra/modules/catalog_events_queue`- sin que Infrastructure tenga que inventar
un nombre distinto del que el consumidor ya reconoce.

### DLQ de los eventos de ciclo de vida — decisión pendiente, no una brecha silenciada

Notifications#22 ya implementa reintento/DLQ del lado del consumidor
(`CatalogLifecycleEventsConsumer`: `Retry` reencola, `DeadLetter` va a la cola
de fallidos), pero su configuración (`deadLetterQueueUrl`) es **una única
variable general**, compartida hoy por el consumidor de notificaciones
transaccionales, el de `catalog.product.created` y el de ciclo de vida -no
existe una DLQ dedicada por consumidor en el código actual de Notifications-.

Cuando se decida el transporte de ciclo de vida (una extensión de ADR-017, ya
`Accepted` para `catalog.product.created`, u otro ADR) y se provisione la cola
real, habrá que decidir explícitamente:

- **Compartir** la DLQ general ya prevista para `catalog.product.created`, o
- **Dedicar** una DLQ propia para `catalog.product.suspended`/`reactivated`/
  `inventory.adjusted`/`premium.configured`.

Esta decisión **no se toma en este cambio** -no hay cola que provisionar
todavía-, pero queda documentada para no descubrirla al provisionar el
transporte de ciclo de vida. Si la arquitectura decide una DLQ dedicada, Notifications necesitará una variable de
configuración nueva (p. ej. `CATALOG_LIFECYCLE_DEAD_LETTER_QUEUE_URL`): **eso
es un PR separado en `Nexus-Battle-Notifications`**, no un cambio que
Infrastructure deba hacer por su cuenta en ese repositorio.

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
