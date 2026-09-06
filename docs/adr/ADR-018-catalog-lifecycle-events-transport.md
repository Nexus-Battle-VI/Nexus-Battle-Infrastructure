# ADR-018 — Transporte de eventos de ciclo de vida de Producto

- **Estado:** **Accepted** — condición de aceptación registrada en [Management #314](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/314#issuecomment-5562149960)
- **Fecha:** 2026-09-06
- **Fecha de aceptación:** 2026-09-06
- **Decide:** Arquitectura, con validación de Catalog y Notifications
- **Relacionado:** [ADR-006](ADR-006-messaging.md), [ADR-007](ADR-007-aws-cost-optimized-platform.md), [ADR-013](ADR-013-canonical-product-contract.md), [ADR-015](ADR-015-catalog-atomicity-audit-outbox.md), [ADR-017](ADR-017-catalog-events-sqs.md), [HU-34 #44](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/44), [HU-35 #43](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/43), [HU-36 #45](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/45), [HU-38 #46](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/46)

## Contexto

[ADR-017](ADR-017-catalog-events-sqs.md) (Accepted, [Management #284](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/284#issuecomment-5519755749)) aprobó SQS Standard **únicamente** para `catalog.product.created`. Su propio texto lo declara explícito: la cola es punto a punto para ese evento, y "un futuro segundo consumidor requerirá su propia cola y fan-out aprobado". No aprobó, ni por extensión ni implícitamente, transporte para los cuatro eventos de ciclo de vida:

- `catalog.product.suspended` (HU-35)
- `catalog.product.reactivated` (HU-35)
- `catalog.product.inventory.adjusted` (HU-34)
- `catalog.product.premium.configured` (HU-36)

Auditado explícitamente tras el merge de Infrastructure#93: no existía ningún ADR posterior, extensión Accepted, ni issue de Management que decidiera su transporte. Infrastructure#93 y `docs/contracts/event-catalog.md` declararon esa ausencia como `BLOCKED BY ARCHITECTURE DECISION`, no como un olvido. Este documento fue esa decisión pendiente -Proposed al escribirse, registrada como Task de decisión en [Management #314](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/314), y `Accepted` desde que el Tech Lead comunicó su aprobación (ver Evidencia de aceptación, más abajo)-.

**Lo que ya existe y es un hecho verificable, no una suposición:**

- Catalog escribe los cuatro eventos en su outbox de MongoDB (`UpdateProductLifecycleStatus`, `AdjustProductInventory`, `ConfigureProductPremium`, ADR-015), auditado en código. No tiene dispatcher que los publique hacia ningún transporte (brecha separada, de Catalog, no de esta decisión).
- Notifications#20/#21/#22 ya implementan y prueban el consumo de los cuatro eventos con un **único parser y un único consumidor** (`CatalogLifecycleEventParser.ts`, `CatalogLifecycleEventsConsumer.ts`): los cuatro comparten el mismo envelope (`catalogProductLifecycleEnvelopeV1` en el AsyncAPI) y la misma forma de `data`; el consumidor distingue el tratamiento funcional por el campo `eventType` dentro del mensaje, no por la cola de origen.
- Notifications ya tiene una variable de configuración dedicada y ya reservada para este transporte: `CATALOG_LIFECYCLE_QUEUE_URL`, documentada en su `.env.example` y consumida en `catalog-notifications-application.ts`.
- Notifications ya implementa idempotencia por `eventId` (`catalog:lifecycle:${eventType}:${eventId}`), reintento y camino a DLQ para los cuatro eventos (`HandleCatalogLifecycleEvent.ts`), con la misma disciplina que `catalog.product.created`.

**Hallazgos originales, ya resueltos en [Notifications#24](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/24)** -detectados auditando `catalog-notifications-application.ts` en el momento de esta aceptación-:

1. La activación SQS de `lifecycleQueue` dependía de `config.queueDriver === QueueDriver.Sqs` -el interruptor de la cola **general**-, exactamente el mismo acoplamiento que [Notifications#23](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/23) había corregido para `catalogQueue`/`catalog.product.created` mediante `CATALOG_QUEUE_DRIVER`. **Corregido por Notifications#24** mediante `CATALOG_LIFECYCLE_QUEUE_DRIVER`, un driver propio e independiente.
2. `lifecycleQueue` se construía con `deadLetterQueueUrl: config.deadLetterQueueUrl` -la DLQ **general** de notificaciones transaccionales-, el mismo problema que #23 había corregido para `catalogQueue`. **Corregido por Notifications#24**: ya no se le pasa `deadLetterQueueUrl`, y confía en la redrive policy de su propia cola dedicada.

Con Notifications#24 mergeado, y con esta misma Task inyectando `CATALOG_LIFECYCLE_QUEUE_DRIVER=sqs` en `compose/nodes/app.yml`, el wiring de configuración queda completo. Sigue faltando, para un flujo E2E real: `terraform apply` de la cola (ver Estado de despliegue, más abajo) y el dispatcher de Catalog que la alimente.

## Fuerzas de decisión

Las mismas que ADR-017 aplicó a `created`, sin novedad:

- at-least-once y tolerancia a duplicados;
- idempotencia por `eventId` (ya implementada en Notifications, ver arriba);
- reintentos basados en atributos reales de SQS (`ApproximateReceiveCount`, no un contador de proceso);
- DLQ para mensajes irreprocesables;
- sin orden global garantizado, salvo que un requisito funcional real lo exija (hoy no existe tal requisito para estos cuatro eventos);
- coste dentro del techo de ADR-007;
- mínimo privilegio IAM, con la misma limitación aceptada de rol EC2 compartido de ADR-011/ADR-017.

## Opciones consideradas

### A. Una cola compartida para los cuatro eventos de ciclo de vida

Una única cola SQS Standard + una única DLQ, con los cuatro `eventType` como mensajes de la misma cola. Notifications ya está construido así: `CatalogLifecycleEventParser` y `CatalogLifecycleEventsConsumer` ya asumen un único flujo de entrada que distingue por `eventType` -es exactamente el consumidor de una cola compartida, no el de cuatro colas independientes-.

- **Complejidad:** mínima; una cola y una DLQ más, mismo patrón que ADR-017.
- **Aislamiento:** un mensaje malformado o un pico de un `eventType` puede retrasar a los otros tres dentro de la misma cola. Aceptable hoy: los cuatro comparten el mismo agregado (Producto), el mismo productor (Catalog) y el mismo consumidor: no hay dos equipos ni dos SLA distintos que aislar.
- **Coste:** el más bajo de las tres opciones (1 cola + 1 DLQ + 2 alarmas, igual que ADR-017 para `created`).
- **Routing:** ninguno nuevo que construir; el consumidor ya enruta internamente por `eventType`.
- **Consumidores:** uno solo (Notifications) hoy; no hay fan-out que resolver.
- **DLQ:** compartida entre los cuatro tipos. `event-catalog.md` ya señala esto como la pregunta pendiente ("Compartir la DLQ general... o Dedicar una DLQ propia"); esta opción responde: una DLQ propia de esta cola lifecycle, compartida entre los cuatro `eventType` pero **distinta** de la DLQ de `created` -no mezcla los dos dominios ya separados por Notifications#23-.
- **Observabilidad:** mismas dos alarmas mínimas de ADR-017 (edad del mensaje más viejo, DLQ con mensajes visibles), sin necesidad de multiplicarlas por evento.
- **Volumen esperado:** bajo -proyecto de demo académica-; los cuatro eventos juntos no se acercan a los límites de rendimiento de una cola Standard.
- **Evolución:** si el volumen o la necesidad de aislamiento crecen, migrar a una cola por evento es aditivo: se crean las colas nuevas, se redirige el productor y el consumidor sin romper el contrato de los mensajes ya definidos.

### B. Una cola por tipo de evento (cuatro colas + cuatro DLQ)

- **Complejidad:** cuadruplica los recursos Terraform, las políticas IAM y las alarmas de la Opción A.
- **Aislamiento:** el mejor de las tres opciones -un `eventType` con problemas no afecta a los otros-.
- **Coste:** cuatro colas + cuatro DLQ + hasta ocho alarmas; desproporcionado para el volumen esperado y para el techo de ADR-007, que ya se declaró ajustado en la estimación de ADR-017.
- **Routing:** exige que Catalog decida a qué cola despachar cada evento -trabajo adicional en el futuro dispatcher, que hoy ni siquiera existe-.
- **Consumidores:** exigiría que Notifications leyera de cuatro colas en vez de una, un cambio de código que hoy no está construido así (`CatalogLifecycleEventsConsumer` recibe una única `queue`).
- **Conclusión:** rechazada para el volumen y la topología actuales. Revisitable si en el futuro cada evento gana un consumidor propio con SLA distinto.

### C. Reutilizar la cola de `catalog.product.created`

Explícitamente descartada por instrucción directa de esta Task y por el propio ADR-017: esa cola fue aprobada para un `eventType` específico, y mezclar otros `eventType` cambiaría el contrato ya `Accepted` sin pasar por una nueva aprobación. Un defecto en el consumo de un evento de ciclo de vida podría además retrasar o poner en DLQ mensajes de `catalog.product.created` -el evento de mayor prioridad funcional, requerido por HU-33-, degradando una garantía ya aprobada por decisión ajena a esta.

## Decisión

**Opción A: una cola SQS Standard compartida para los cuatro eventos de ciclo de vida**, con los mismos parámetros que ADR-017 aprobó para `created`:

| Parámetro | Valor aceptado |
| --- | --- |
| Nombre de cola | `nexus-battle-<environment>-catalog-lifecycle-notifications` |
| Nombre de DLQ | `nexus-battle-<environment>-catalog-lifecycle-notifications-dlq` |
| Tipo | Standard; no FIFO |
| Long polling | 20 segundos |
| Visibility timeout | 60 segundos |
| Retención cola principal | 4 días |
| Retención DLQ | 14 días |
| `maxReceiveCount` | 5 |
| Cifrado | SSE-SQS, sin KMS de cliente |
| Transporte | HTTPS + Signature Version 4 |
| Ownership | Catalog: `sqs:SendMessage`. Notifications: `sqs:ReceiveMessage`/`DeleteMessage`/`ChangeMessageVisibility`/`GetQueueAttributes`. Infrastructure: cola, DLQ, IAM, alarmas |

Configuración en Notifications: `CATALOG_LIFECYCLE_QUEUE_URL` -variable que **ya existe**, sin necesidad de que Infrastructure invente un nombre nuevo ni de que Notifications agregue una variable-.

## Evidencia de aceptación

- aprobación del Tech Lead de la topología (Opción A) y sus parámetros: registrada en [Management #314](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/314#issuecomment-5562149960);
- aprobación de coste dentro del techo de ADR-007: estimación en [catalog-lifecycle-sqs-estimate.md](../costs/catalog-lifecycle-sqs-estimate.md) (hasta USD 0,2542/mes en el escenario de demo, insignificante frente al techo de USD 100);
- confirmación de que `CATALOG_LIFECYCLE_QUEUE_URL` apuntando a una cola con los cuatro `eventType` mezclados es el contrato que el consumidor de Notifications espera: verificado en código (`CatalogLifecycleEventParser`/`CatalogLifecycleEventsConsumer` ya tratan los cuatro como un único flujo) antes de esta aceptación.

**Condición de aceptación registrada en Management #314** (no una cita textual del Tech Lead, sino la condición tal como quedó documentada en esa Task): la implementación no debe romper, reutilizar, reemplazar ni mezclar la cola SQS de `catalog.product.created` ya aprobada por ADR-017, ni la cola general de notificaciones transaccionales de Notifications, ni sus DLQ; debe preservarse la semántica at-least-once, la idempotencia por `eventId`, los reintentos basados en `ApproximateReceiveCount` y una DLQ propia para esta cola lifecycle.

**Aceptar el ADR no equivale a desplegar.** Ningún `terraform apply` se ejecutó como parte de esta aceptación.

## Estado de despliegue

Mismos tres estados que ADR-017, y no deben confundirse entre sí:

| Estado | Significado | Vigente desde |
| --- | --- | --- |
| **Accepted** | El Tech Lead aprobó la decisión arquitectónica: cola compartida, parámetros, ownership, condición de no-regresión sobre ADR-017 y la cola general | [Management #314](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/314#issuecomment-5562149960) (2026-09-06) |
| **Provisioned in IaC** | La cola y la DLQ existen como código Terraform reproducible (`infra/modules/catalog_lifecycle_events_queue`, módulo separado del de ADR-017), con IAM de mínimo privilegio en una política propia sobre el rol compartido del nodo `app` | Infrastructure#95 |
| **Applied/deployed** | `terraform apply` se ejecutó de verdad contra la cuenta real; la cola existe en AWS | **Todavía no** — requiere autorización explícita fuera de esta Task |

**Wiring de configuración: completo.** [Notifications#24](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/24) agregó `CATALOG_LIFECYCLE_QUEUE_DRIVER` como driver independiente de `QUEUE_DRIVER`, y dejó de reenviar a la DLQ general (ver Contexto, arriba). Esta misma Task (rama `fix/hu-38-enable-lifecycle-sqs`) inyecta `CATALOG_LIFECYCLE_QUEUE_DRIVER=sqs` junto a `CATALOG_LIFECYCLE_QUEUE_URL` en `compose/nodes/app.yml`, con el mismo criterio fail-closed que `CATALOG_QUEUE_DRIVER`: si `terraform apply` no se ha ejecutado y la URL llega vacía, Notifications rechaza el arranque en vez de caer a memoria en silencio.

Falta una sola pieza para que el evento fluya de extremo a extremo:

- **dispatcher en Catalog** que lea el outbox y publique hacia esta cola (confirmado ausente en código, PR separado en `Nexus-Battle-Catalog`).

Mientras esa pieza -y `terraform apply`- no existan, los cuatro eventos de ciclo de vida permanecen sin transporte productivo real, aunque el contrato, la decisión arquitectónica, la infraestructura como código y el wiring de configuración ya estén en su lugar.

## Consecuencias

**Lo que se gana:**

- transporte real para los cuatro eventos de ciclo de vida de HU-38, cerrando la decisión que Infrastructure#93 dejó documentada como bloqueada;
- reutilización total del patrón, el código y la disciplina operativa ya aprobados y probados en ADR-017, sin arriesgar sus recursos existentes (módulo Terraform separado, política IAM separada);
- ninguna variable nueva que inventar en Notifications para la URL de la cola (`CATALOG_LIFECYCLE_QUEUE_URL` ya existía).

**Lo que cuesta:**

- una DLQ compartida entre cuatro `eventType` distintos, con la limitación de triage que eso implica frente a la Opción B.
