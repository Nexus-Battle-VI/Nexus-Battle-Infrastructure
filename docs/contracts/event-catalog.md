# Catálogo de eventos y mensajes

## Estado

**Ningún evento cruza todavía un transporte real entre procesos distintos.** Los eventos existentes se emiten dentro de sus agregados y se registran en observabilidad. [ADR-017](../adr/ADR-017-catalog-events-sqs.md) está `Accepted` ([Management #284](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/284#issuecomment-5519755749), merge de [Infrastructure #65](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/65)) para SQS con `catalog.product.created`, su cola y DLQ ya están **Provisioned in IaC** (`infra/modules/catalog_events_queue`, Infrastructure#93), y Notifications ya sabe activarla de forma independiente de su cola general (`CATALOG_QUEUE_DRIVER`, [Notifications#23](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/23)) -este mismo cambio ya inyecta `CATALOG_QUEUE_DRIVER=sqs` en `compose/nodes/app.yml`-. Nada de esto equivale a desplegado: no se ejecutó `terraform apply` y Catalog no tiene dispatcher que alimente la cola.

Los eventos de ciclo de vida (`suspended`/`reactivated`/`inventory.adjusted`/`premium.configured`) ya tienen decisión de transporte: [ADR-018](../adr/ADR-018-catalog-lifecycle-events-transport.md) está `Accepted` ([Management #314](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/314#issuecomment-5562149960)) para una cola SQS compartida entre los cuatro, con su propia DLQ, **distinta** de la de `catalog.product.created` y de la cola general de Notifications. Su cola y DLQ ya están **Provisioned in IaC** (`infra/modules/catalog_lifecycle_events_queue`, módulo Terraform separado del de ADR-017 para no arriesgar esos recursos). Architecture Accepted; runtime pendiente de Notifications wiring y deployment: no se ejecutó `terraform apply`, Catalog no tiene dispatcher, y Notifications todavía activa su consumidor de ciclo de vida (`catalog-notifications-application.ts`) con el interruptor de la cola GENERAL (`QUEUE_DRIVER`) y reenvía a la DLQ general -el mismo acoplamiento que Notifications#23 ya corrigió para `catalog.product.created`, sin equivalente todavía para el ciclo de vida-: hace falta un PR de Notifications que lo resuelva antes de que esta cola, ya aceptada y provisionada en código, sirva de algo en tiempo de ejecución.

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
- **Transporte de los eventos de ciclo de vida: Architecture Accepted,
  Provisioned in IaC, runtime configurado, deployment pendiente.**
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
  ya aplicó a `catalog.product.created`-. Esta Task inyecta
  `CATALOG_LIFECYCLE_QUEUE_DRIVER=sqs` en `compose/nodes/app.yml`, cerrando el
  wiring de configuración correspondiente.
- **Consecuencia, resumen del estado real:** `catalog.product.created` tiene
  ADR `Accepted`, cola `Provisioned in IaC` (Infrastructure#93) y wiring de
  Notifications completo (`CATALOG_QUEUE_DRIVER=sqs` en
  `compose/nodes/app.yml`); le falta únicamente `terraform apply` y el
  dispatcher de Catalog. Los cuatro eventos de ciclo de vida tienen ADR
  `Accepted` (ADR-018), cola `Provisioned in IaC`
  (`infra/modules/catalog_lifecycle_events_queue`) y wiring de Notifications
  ahora también completo (`CATALOG_LIFECYCLE_QUEUE_DRIVER=sqs` en
  `compose/nodes/app.yml`); les falta igualmente `terraform apply` y el
  dispatcher de Catalog. La configuración de runtime está lista para
  consumir la cola lifecycle en cuanto la infraestructura se aplique y
  Catalog publique hacia ella -no antes-. La integración
  Notifications↔Player-Inventory (resolución de destinatarios) sigue siendo
  real e independiente de todo esto.

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
