# Integración entre contextos

Ver [ADR-006](../adr/ADR-006-messaging.md).

## Criterio

Una integración es **síncrona** cuando quien llama no puede continuar sin la respuesta. Es **asíncrona** cuando puede.

| Integración | Modo | Estado |
| --- | --- | --- |
| Commerce → Catalog (precio) | Síncrono | Puerto definido, adaptador con catálogo local |
| Catalog → Account (evidencia MFA) | Síncrono interno | Account integrado; promoción de Catalog en PR #27 y cierre funcional en Management #136 |
| Catalog → Notifications (`catalog.product.created`) | Asíncrono | SQS Standard + outbox/inbox `Proposed` en ADR-017; no desplegado |
| Account → Notifications | Asíncrono | Puerto definido, adaptador de registro |
| Commerce → Notifications | Asíncrono | Pendiente |
| Commerce → Player/Inventory (reserva) | Asíncrono con saga | **No implementado** |

El razonamiento en cada caso:

- **Precio**: no se puede añadir una línea sin conocer el importe. Esperar es la única opción correcta.
- **Evidencia MFA**: una mutación administrativa no puede continuar si Account
  no confirma evidencia vigente para `subject + jti + method`. La ausencia o un
  método diferente responde `403`; la imposibilidad técnica de comprobarla
  responde `503`. En ambos casos se niega antes de escribir.
- **Notificación**: una cuenta creada es válida aunque el correo de bienvenida tarde. Bloquear el registro por un correo sería peor que retrasar el correo.
- **Reserva**: es un proceso de larga duración sin transacción común entre servicios.

### Flujo propuesto de creación de Producto

ADR-017 propone que Catalog persista `catalog.product.created` en el outbox de
la misma transacción de ADR-015 y lo despache después a una cola SQS Standard.
Notifications valida versión y deduplica por `eventId`. La cola es punto a
punto para ese consumidor; no se envía un mensaje por jugador y no se promete
orden ni exactly-once.

Contrato: [catalog-events-v1.asyncapi.yaml](../contracts/catalog-events-v1.asyncapi.yaml).

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
| `catalog.product.created` (externo V1 propuesto) | Catalog |
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
