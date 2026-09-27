# Integración entre contextos

Ver [ADR-006](../adr/ADR-006-messaging.md).

## Criterio

Una integración es **síncrona** cuando quien llama no puede continuar sin la respuesta. Es **asíncrona** cuando puede.

| Integración | Modo | Estado |
| --- | --- | --- |
| Commerce → Catalog (precio) | Síncrono | Puerto definido, adaptador con catálogo local |
| Catalog → Account (evidencia MFA) | Síncrono interno | Account integrado; promoción de Catalog en PR #27 y cierre funcional en Management #136 |
| Catalog → Notifications (`catalog.product.created`) | Asíncrono | SQS Standard + outbox/inbox: ADR-017 `Accepted` ([Management #284](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/284#issuecomment-5519755749), merge de [Infrastructure #65](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/65)), **Provisioned in IaC** (`infra/modules/catalog_events_queue`, [Infrastructure #93](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/93)). Notifications activa su consumo independiente de la cola general (`CATALOG_QUEUE_DRIVER=sqs`, [Notifications #23](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/23)) y Catalog implementa el dispatcher que publica hacia ella ([Catalog#51](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/51)); esta Task activa ese productor en el nodo real (`CATALOG_EVENT_DISPATCH_ENABLED=true` + `CATALOG_EVENTS_QUEUE_URL` en `compose/nodes/app.yml`, mismo output que `CATALOG_QUEUE_URL`). **No Applied/deployed** -ningún `terraform apply` se ejecutó-. No desplegado |
| Catalog → Notifications (`suspended`/`reactivated`/`inventory.adjusted`/`premium.configured`, HU-38) | Asíncrono | Consumidor implementado en Notifications (#20/#21/#22); Catalog implementa el dispatcher que publica los 4 eventos desde su outbox ([Catalog#51](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/51)). [ADR-018](../adr/ADR-018-catalog-lifecycle-events-transport.md) `Accepted` ([Management #314](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/314#issuecomment-5562149960)) para una cola SQS compartida entre los 4, con DLQ propia distinta de la de `created` y de la general; **Provisioned in IaC** (`infra/modules/catalog_lifecycle_events_queue`, módulo Terraform separado del de ADR-017). Wiring de Notifications completo ([Notifications#24](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/24): `CATALOG_LIFECYCLE_QUEUE_DRIVER` propio, sin DLQ general); esta Task activa el productor de Catalog en el nodo real (`CATALOG_EVENT_DISPATCH_ENABLED=true` + `CATALOG_LIFECYCLE_QUEUE_URL` en `compose/nodes/app.yml`). **No Applied/deployed** -ningún `terraform apply` se ejecutó-. No desplegado -brecha de aplicación de Terraform, no de wiring- |
| Notifications → Player/Inventory (resolución de propietarios, HU-38) | Síncrono interno | **Implementado** (Notifications#21, Player-Inventory#23): HMAC servicio-a-servicio, mismo mecanismo que Catalog→Account. Un fallo transitorio reintenta (Notifications#22); indisponible o sin configurar sigue la misma ruta de reintento/DLQ, nunca cae a un destinatario inventado |
| Account → Notifications | Asíncrono | Puerto definido, adaptador de registro |
| Commerce → Notifications | Asíncrono | Pendiente |
| Commerce → Player/Inventory (reserva) | Asíncrono con saga | **No implementado** |
| Combat → Player/Inventory (héroe equipado: `subtype`, estadísticas efectivas y `activeEffects`) | Síncrono interno | **Implementado** (Player-Inventory [#35](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/35), Combat [#22](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/22)): `GET /api/internal/v1/players/:playerId/equipped-hero`, HMAC |
| Combat → Account (perfil de batalla) | Síncrono interno | **Implementado**: cliente en Combat, ruta interna `GET /api/internal/accounts/:subject/battle-profile` en Account, HMAC |
| Missions → Combat (simulación autoritativa) | Síncrono interno | **Implementado** en `develop` (Combat [#44](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/44) y [#50](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/50)): `POST /api/internal/v1/combat/simulations`, HMAC, [contrato HU-72](../contracts/hu-72-mission-simulation-v1.md) |
| Missions → Combat (probabilidad de éxito, P-J7) | Síncrono interno | **En la rama `feat/misiones-jugabilidad`**: `POST /api/internal/v1/combat/simulations/estimates`, HMAC; la misma simulación varias veces, sin guardar nada ([diseño](misiones-jugabilidad.md)) |
| Missions → Player/Inventory (épica del Máster y botín del jefe) | Síncrono interno, con reintento | `POST /api/internal/v1/inventory/grants`, HMAC e idempotente por `operationId` (Player-Inventory #49). La épica (HU-73) está en `develop`; el botín (P-J1) está en la rama `feat/misiones-jugabilidad` |

El razonamiento en cada caso:

- **Precio**: no se puede añadir una línea sin conocer el importe. Esperar es la única opción correcta.
- **Evidencia MFA**: una mutación administrativa no puede continuar si Account
  no confirma evidencia vigente para `subject + jti + method`. La ausencia o un
  método diferente responde `403`; la imposibilidad técnica de comprobarla
  responde `503`. En ambos casos se niega antes de escribir.
- **Notificación**: una cuenta creada es válida aunque el correo de bienvenida tarde. Bloquear el registro por un correo sería peor que retrasar el correo.
- **Reserva**: es un proceso de larga duración sin transacción común entre servicios.
- **Héroe equipado (Combat)**: Combat no puede construir la tabla de efectos sin el `subtype` y los `activeEffects` del héroe, y no debe duplicar reglas de equipamiento: los pide a Player/Inventory, su dueño.
- **Simulación de Missions**: Missions no puede continuar sin el resultado y no implementa aleatoriedad ni reglas de combate; la simulación autoritativa es de Combat ([ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md), [ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md)).
- **Resolución de propietarios (HU-38)**: sin saber qué jugadores poseen el producto suspendido/reactivado no hay a quién notificar; Notifications no puede continuar el procesamiento del evento sin esa respuesta. Ver [docs/contracts/product-owners.md](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/blob/develop/docs/product-owners.md) de Player-Inventory para el contrato completo.

### Flujo aprobado de creación de Producto

ADR-017 (`Accepted`) decide que Catalog persista `catalog.product.created` en
el outbox de la misma transacción de ADR-015 y lo despache después a una cola
SQS Standard, todavía no provisionada.
Notifications valida versión y deduplica por `eventId`. La cola es punto a
punto para ese consumidor; no se envía un mensaje por jugador y no se promete
orden ni exactly-once.

Contrato: [catalog-events-v1.asyncapi.yaml](../contracts/catalog-events-v1.asyncapi.yaml).

### Combat: héroe equipado y aleatoriedad

```text
Player/Inventory --(subtype + activeEffects, HMAC)--> Combat: BuildHeroEffectTable -> tabla vigente
Combat: sequence.nextIndex() (HU-24) + tabla vigente -> ResolveRandomEffect -> efecto y magnitud (HU-25)
Missions --(HMAC)--> Combat: simulación y estimación de la misión con el mismo motor
```

Player/Inventory es dueño del héroe, del equipamiento y de los `activeEffects`; Combat, de la tabla probabilística, su aplicación y la aleatoriedad. Ningún cliente aporta semilla, índice ni `activeEffects`. Detalle y decisión en [ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md) y [combat-randomness.puml](../diagrams/combat-randomness.puml).

### Combat: inicio de batalla y orden de turnos (HU-17, diseño)

```text
Web A/B --POST /rooms/{id}/start--> Combat: revalida HU-16 (Player/Inventory) -> orden con HU-24 -> persiste -> battleStarted (WebSocket, seq)
Web A/B <--WebSocket ticket + resume/seq-- Combat: misma cola y mismo turno para ambos
```

Combat es la única autoridad de la cola y del turno; Web solo lo representa. Contrato, mensajes y decisiones pendientes en el [contrato HU-17](../contracts/hu-17-battle-turn-order-v1.md) y sus diagramas de [secuencia](../diagrams/hu-17-sequence-battle-start.puml), [actividades](../diagrams/hu-17-activity-turn-order.puml) y [estados](../diagrams/hu-17-state-battle-room.puml). El transporte es el WebSocket ya aceptado en [ADR-020](../adr/ADR-020-realtime-combat.md); no hay ADR nuevo.

### Combat: ataque básico (HU-18, diseño)

```text
Web A --WebSocket {"type":"attack","commandId","roomId","target":{teamLabel,seat}}--> Combat
Combat: valida turno/objetivo (0 sorteos) -> HU-20 (Ataque vs Defensa) -> HU-25 (efecto) -> daño (floor) -> Vida
        -> UNA escritura (Vida + evento + commandId + turno avanzado) -> basicAttackResolved (seq)
Web A/B <-- basicAttackResolved / snapshot / resume -- Combat: misma Vida y mismo turno para ambos
```

El cliente solo envía la **intención** (el objetivo); Combat deriva al atacante del `sub` autenticado y es la única fuente de la Vida, que congela como *snapshot de combate* al iniciar la batalla (sin llamadas a Player/Inventory por golpe). No hay endpoint REST de ataque. Contrato y decisiones en el [contrato HU-18](../contracts/hu-18-basic-attack-v1.md) y sus diagramas de [secuencia](../diagrams/hu-18-sequence-basic-attack.puml), [actividades](../diagrams/hu-18-activity-basic-attack.puml) y [estados](../diagrams/hu-18-state-battle-health.puml).

## Contrato del mensaje de notificación

```json
{
  "notificationId": "n-8f3c",
  "recipient": "jugador@nexus.test",
  "templateId": "account-verification-code",
  "variables": { "displayName": "Ana", "code": "123456", "expiresInMinutes": 10 },
  "idempotencyKey": "opcional"
}
```

Los identificadores de plantilla forman parte del contrato: añadir o retirar uno es un cambio de contrato. Catálogo completo en [event-catalog.md](../contracts/event-catalog.md).

`idempotencyKey` es opcional; si se omite se usa `notificationId`. El número de intento **no viaja en el mensaje**: proviene del contador de entregas de la cola.

## Eventos de dominio

| Evento | Emisor |
| --- | --- |
| `account.registered` | Account |
| `account.verified` | Account |
| `account.email-changed` | Account |
| `inventory.item.added` | Player / Inventory |
| `inventory.item.removed` | Player / Inventory |
| `catalog.product.created` (externo V1, ADR-017 `Accepted`) | Catalog |
| `catalog.product.published` (interno heredado) | Catalog |
| `catalog.product.price-changed` | Catalog |
| `catalog.product.archived` | Catalog |
| `community.post.published` | Community |
| `community.post.hidden` | Community |
| `community.thread.closed` | Community |
| `commerce.order.confirmed` | Commerce |
| `commerce.order.cancelled` | Commerce |

**Los eventos no transportan contenido escrito por personas usuarias.** `community.post.published` lleva la **longitud** del mensaje, no el texto: un evento que cruza el límite del servicio no debe llevar contenido fuera del contexto que lo custodia. Hay una prueba que verifica que el texto no aparece en el evento serializado.

`catalog.product.price-changed` incluye el importe anterior de forma deliberada, para que un consumidor detecte la dirección del cambio sin consultar el servicio.

## Estado real

**Los servicios no se comunican entre sí todavía.** Los puertos existen con implementaciones locales completas; el transporte depende de [ADR-006](../adr/ADR-006-messaging.md).

> Esta descripción es del cierre de Sprint 1. Las integraciones síncronas internas con HMAC que ya existen (p. ej. Notifications → Player/Inventory, Combat → Player/Inventory y Combat → Account) figuran en la tabla del principio.

Es la limitación funcional más visible del Sprint 1, y está declarada como tal en el README de cada servicio afectado.

Lo que sí existe y funciona:

| Puerto | Implementación | Qué hace de verdad |
| --- | --- | --- |
| `MessageQueuePort` | `InMemoryMessageQueue` | Visibilidad diferida, reentrega con contador y DLQ |
| `NotificationRequestPort` | `LoggingNotificationRequester` | Registra la solicitud con la forma exacta del mensaje |
| `ProductPricingPort` | `LocalCatalogPricing` | Resuelve precios de un catálogo local |

Son implementaciones completas del puerto, no simulaciones de un servicio remoto.

## Patrones del consumo asíncrono

Ya implementados y probados en Notifications:

| Patrón | Por qué es obligatorio |
| --- | --- |
| **Idempotent Consumer** | Entrega «al menos una vez» significa que el mensaje llegará repetido. El correo no debe enviarse dos veces |
| **Retry con retroceso exponencial** | Un proveedor caído no debe recibir reintentos inmediatos en bucle |
| **Dead Letter Queue** | Un mensaje irreprocesable debe salir del flujo en lugar de bloquearlo |

**Hallazgo de la implementación:** el número de intento debe provenir del contador de entregas de la cola (`ApproximateReceiveCount` en SQS), no del estado en memoria del proceso.

Una prueba de integración reveló que el agregado se reconstruía desde cero en cada entrega, por lo que el contador volvía a 1 y **la política de reintentos nunca se agotaba**. Es exactamente el fallo que produce un modelo ingenuo. Quedó corregido propagando `receivedCount` hasta el agregado, y cubierto por prueba.

## La saga de checkout

```text
Commerce: confirmar pedido
    |
    +--> Player/Inventory: reservar unidades
    |         compensacion: liberar la reserva
    |
    +--> Notifications: confirmar por correo
              sin compensacion: el pedido ya es valido
```

`commerce.order.confirmed` transporta lo necesario para iniciarla. El orquestador, las compensaciones y el transporte **dependen de ADR-006**. Implementar una saga contra un transporte no elegido produciría código que habría que rehacer.

Sí existe ya una **compensación explícita** a menor escala: `RegisterAccount` retira el sujeto de identidad si falla la persistencia, para no dejar identidades huérfanas. La solicitud de notificación queda deliberadamente fuera de esa compensación, porque la cuenta ya es válida y deshacer un registro por no haber podido enviar un correo sería peor que reintentar el correo.
