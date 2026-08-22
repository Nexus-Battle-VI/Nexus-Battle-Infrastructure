# ADR-006 — Mensajería e integración entre contextos

- **Estado:** Proposed
- **Fecha:** 2026-08-21
- **Decide:** Arquitectura
- **Relacionado:** [ADR-001](ADR-001-repository-strategy.md), [ADR-007](ADR-007-aws-cost-optimized-platform.md)

## Contexto

Los seis contextos necesitan comunicarse. El plan fija *event-driven selectivo*: no todo evento merece un bus, y no toda llamada merece ser asíncrona.

Hay tres integraciones reales en el alcance:

| Origen | Destino | Naturaleza |
| --- | --- | --- |
| Account, Commerce | Notifications | Solicitud de notificación |
| Commerce | Catalog | Consulta de precio |
| Commerce | Player / Inventory | Reserva de inventario tras confirmar |

## Decisión

### Criterio: síncrono o asíncrono

Una integración es **síncrona** cuando quien llama **no puede continuar** sin la respuesta. Es **asíncrona** cuando puede.

| Integración | Modo | Por qué |
| --- | --- | --- |
| Commerce → Catalog (precio) | **Síncrono** | No se puede añadir una línea sin conocer el importe. Esperar es la única opción correcta |
| Account/Commerce → Notifications | **Asíncrono** | Una cuenta creada es válida aunque el correo de bienvenida tarde. Bloquear el registro por un correo sería peor que retrasar el correo |
| Commerce → Player/Inventory (reserva) | **Asíncrono, con saga** | Es un proceso de larga duración sin transacción común |

### Transporte: SQS es el candidato, y no está adoptado

**SQS** es el candidato para la mensajería asíncrona:

- Es *usage-based*: sin tráfico, no hay coste. Encaja en el techo de USD 100.
- Ofrece entrega «al menos una vez», visibilidad diferida y cola de mensajes fallidos, que es exactamente el conjunto que el worker de Notifications necesita.

**EventBridge no es obligatorio en Sprint 1.** Aporta enrutado y filtrado que hoy no hacen falta: hay un solo consumidor. Notifications puede consumir SQS directamente.

**Este ADR no adopta SQS todavía**, porque adoptarlo implica provisionar infraestructura AWS y eso requiere aprobación de costes ([ADR-007](ADR-007-aws-cost-optimized-platform.md)).

### Qué existe hoy

| Puerto | Implementación actual | Qué es |
| --- | --- | --- |
| `MessageQueuePort` (Notifications) | `InMemoryMessageQueue` | Cola real con visibilidad diferida, reentrega y DLQ |
| `NotificationRequestPort` (Account) | `LoggingNotificationRequester` | Registra la solicitud con la forma exacta del mensaje |
| `ProductPricingPort` (Commerce) | `LocalCatalogPricing` | Catálogo local de precios |

Los tres son **implementaciones completas de su puerto**, no simulaciones de un servicio remoto. Permiten ejecutar y verificar el sistema de extremo a extremo sin acoplarse a una decisión de transporte que aún no se ha tomado.

`resolveSqsSettings` valida y deriva los parámetros de una cola SQS **sin instanciar ningún cliente de AWS**: existe para que adoptar SQS no obligue a rehacer la configuración ni el arranque del worker.

### Patrones obligatorios en el consumo asíncrono

Ya implementados en Notifications:

| Patrón | Dónde | Por qué |
| --- | --- | --- |
| **Idempotent Consumer** | `IdempotencyStorePort` | Entrega «al menos una vez» significa que el mensaje llegará repetido. El correo no debe enviarse dos veces |
| **Retry con retroceso exponencial** | `RetryPolicy` | Un proveedor caído no debe recibir reintentos inmediatos en bucle |
| **Dead Letter Queue** | `MessageQueuePort.deadLetter` | Un mensaje que nunca podrá procesarse debe salir del flujo en lugar de bloquearlo |

**Hallazgo de la implementación:** el número de intento debe provenir del **contador de entregas de la cola** (`ApproximateReceiveCount` en SQS), no del estado en memoria del proceso. Al construirlo, una prueba de integración reveló que el agregado se reconstruía desde cero en cada entrega y la política de reintentos nunca se agotaba. Es exactamente el fallo que un modelo ingenuo produce, y quedó corregido y cubierto por prueba.

### La saga de checkout no está implementada

Confirmar un pedido debería reservar inventario y notificar. Es un proceso de larga duración sin transacción común, y por tanto candidato a **saga con compensaciones**.

`commerce.order.confirmed` existe y transporta lo necesario para iniciarla. El orquestador, las compensaciones y el transporte **dependen de esta decisión**. Implementar una saga contra un transporte no elegido produciría código que habría que rehacer.

Sí existe ya una **compensación explícita** dentro de un único caso de uso: `RegisterAccount` retira el sujeto de identidad si falla la persistencia, para no dejar identidades huérfanas. Es el mismo principio a menor escala, y demuestra que el patrón no se pospone por desconocimiento sino por dependencia de transporte.

### Los eventos no transportan contenido sensible

`community.post.published` lleva la **longitud** del mensaje, no el texto. Un evento que cruza el límite del servicio no debe llevar contenido escrito por personas usuarias fuera del contexto que lo custodia. Hay una prueba que verifica que el texto no aparece en el evento serializado.

## Consecuencias

**Lo que se gana**

- El sistema funciona hoy, verificable de extremo a extremo, sin AWS.
- Los patrones difíciles del consumo asíncrono ya están implementados y probados: adoptar SQS será sustituir un adaptador, no diseñar de nuevo.
- No se paga por infraestructura que aún no se usa.

**Lo que cuesta**

- Los servicios **no se comunican realmente entre sí** en el alcance actual. Es la limitación funcional más visible del Sprint 1.
- La saga de checkout queda pendiente y con ella la reserva de inventario.

## Alternativas consideradas

| Alternativa | Por qué se descartó |
| --- | --- |
| Adoptar SQS ya | Requiere provisionar AWS, que depende de aprobación de costes |
| EventBridge desde el inicio | Aporta enrutado que hoy no hace falta: hay un consumidor único |
| Kafka o RabbitMQ autoalojado | Coste fijo de cómputo y operación desproporcionado para el volumen del Sprint |
| Todo síncrono por HTTP | Acoplaría la disponibilidad de Account a la de Notifications: un fallo del correo impediría registrarse |

## Evidencia

- `InMemoryMessageQueue` implementa visibilidad diferida, reentrega con contador y DLQ, con 133 pruebas verdes en Notifications.
- La corrección del contador de entregas está cubierta por la prueba `agota los reintentos y termina en la cola de mensajes fallidos`.
- Ningún `package.json` del producto declara dependencia de `@aws-sdk/client-sqs`.
