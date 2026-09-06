# ADR-018 — Transporte de eventos de ciclo de vida de Producto

- **Estado:** **Proposed** — requiere aprobación del Tech Lead. NO Accepted: no se provisiona ningún recurso mientras este documento no cambie de estado.
- **Fecha:** 2026-09-06
- **Decide:** Arquitectura, con validación de Catalog y Notifications
- **Relacionado:** [ADR-006](ADR-006-messaging.md), [ADR-007](ADR-007-aws-cost-optimized-platform.md), [ADR-013](ADR-013-canonical-product-contract.md), [ADR-015](ADR-015-catalog-atomicity-audit-outbox.md), [ADR-017](ADR-017-catalog-events-sqs.md), [HU-34 #44](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/44), [HU-35 #43](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/43), [HU-36 #45](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/45), [HU-38 #46](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/46)

## Contexto

[ADR-017](ADR-017-catalog-events-sqs.md) (Accepted, [Management #284](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/284#issuecomment-5519755749)) aprobó SQS Standard **únicamente** para `catalog.product.created`. Su propio texto lo declara explícito: la cola es punto a punto para ese evento, y "un futuro segundo consumidor requerirá su propia cola y fan-out aprobado". No aprobó, ni por extensión ni implícitamente, transporte para los cuatro eventos de ciclo de vida:

- `catalog.product.suspended` (HU-35)
- `catalog.product.reactivated` (HU-35)
- `catalog.product.inventory.adjusted` (HU-34)
- `catalog.product.premium.configured` (HU-36)

Auditado explícitamente tras el merge de Infrastructure#93: no existe ningún ADR posterior, extensión Accepted, ni issue de Management que decida su transporte. Infrastructure#93 y `docs/contracts/event-catalog.md` ya declaran esta ausencia como `BLOCKED BY ARCHITECTURE DECISION`, no como un olvido. Este documento es esa decisión pendiente, propuesta y no aún aceptada.

**Lo que ya existe y es un hecho verificable, no una suposición:**

- Catalog escribe los cuatro eventos en su outbox de MongoDB (`UpdateProductLifecycleStatus`, `AdjustProductInventory`, `ConfigureProductPremium`, ADR-015), auditado en código. No tiene dispatcher que los publique hacia ningún transporte (brecha separada, de Catalog, no de esta decisión).
- Notifications#20/#21/#22 ya implementan y prueban el consumo de los cuatro eventos con un **único parser y un único consumidor** (`CatalogLifecycleEventParser.ts`, `CatalogLifecycleEventsConsumer.ts`): los cuatro comparten el mismo envelope (`catalogProductLifecycleEnvelopeV1` en el AsyncAPI) y la misma forma de `data`; el consumidor distingue el tratamiento funcional por el campo `eventType` dentro del mensaje, no por la cola de origen.
- Notifications ya tiene una variable de configuración dedicada y ya reservada para este transporte: `CATALOG_LIFECYCLE_QUEUE_URL`, documentada en su `.env.example` y consumida en `catalog-notifications-application.ts`.
- Notifications ya implementa idempotencia por `eventId` (`catalog:lifecycle:${eventType}:${eventId}`), reintento y camino a DLQ para los cuatro eventos (`HandleCatalogLifecycleEvent.ts`), con la misma disciplina que `catalog.product.created`.

**Hallazgos adicionales, reportados como bloqueo real y no resueltos aquí** -auditando `catalog-notifications-application.ts` de Notifications-:

1. La activación SQS de `lifecycleQueue` (línea 135) sigue condicionada a `config.queueDriver === QueueDriver.Sqs` -el interruptor de la cola **general**-, exactamente el mismo acoplamiento que [Notifications#23](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/23) ya corrigió para `catalogQueue`/`catalog.product.created` mediante `CATALOG_QUEUE_DRIVER`. Nadie corrigió el equivalente para `lifecycleQueue`.
2. `lifecycleQueue` (línea 139) sigue construyéndose con `deadLetterQueueUrl: config.deadLetterQueueUrl` -la DLQ **general** de notificaciones transaccionales-, exactamente el mismo problema que #23 corrigió para `catalogQueue` (que ya no reenvía a esa DLQ y confía en la redrive policy de su propia cola). Nadie corrigió el equivalente para `lifecycleQueue`.

Esto significa que, aunque este ADR se aceptara y se provisionara la cola descrita abajo, **Notifications no podría consumirla correctamente sin antes**: activar `QUEUE_DRIVER=sqs` general -que a su vez exige la cola general de ADR-006, todavía `Proposed`- **y** seguir mezclando su DLQ con la de notificaciones transaccionales, o sin un cambio de código en Notifications análogo a `#23` (p. ej. `CATALOG_LIFECYCLE_QUEUE_DRIVER`, y omitir `deadLetterQueueUrl` en `lifecycleQueue` para que su propia redrive policy sea quien mueva los mensajes a su DLQ dedicada). Esta Task no modifica Notifications; se documentan ambos bloqueos con precisión para que el PR de Notifications que implemente esto los resuelva junto con el consumo.

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

## Recomendación (Proposed, no Accepted)

**Opción A: una cola SQS Standard compartida para los cuatro eventos de ciclo de vida**, con los mismos parámetros que ADR-017 aprobó para `created`:

| Parámetro | Valor propuesto |
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

## Condiciones para pasar a Accepted

- aprobación del Tech Lead de la topología (Opción A) y sus parámetros;
- aprobación de coste dentro del techo de ADR-007 (estimación pendiente de elaborar, mismo formato que [catalog-events-sqs-estimate.md](../costs/catalog-events-sqs-estimate.md));
- confirmación de Notifications de que `CATALOG_LIFECYCLE_QUEUE_URL` apuntando a una cola con los cuatro `eventType` mezclados es el contrato que su consumidor espera -ya lo es, según el código auditado, pero corresponde confirmarlo en la revisión de este documento, no asumirlo unilateralmente-;
- **corrección previa o paralela en Notifications** del acoplamiento `lifecycleQueue`/`config.queueDriver` descrito en Contexto: sin ella, aceptar y provisionar esta cola no bastaría para activar el consumo real;
- ningún `terraform apply` dentro de esta decisión.

## Consecuencias

**Lo que se gana, si se acepta:**

- transporte real para los cuatro eventos de ciclo de vida de HU-38, cerrando la brecha que Infrastructure#93 dejó documentada como bloqueada;
- reutilización total del patrón, el código y la disciplina operativa ya aprobados y probados en ADR-017;
- ninguna variable nueva que inventar en Notifications.

**Lo que cuesta:**

- una DLQ compartida entre cuatro `eventType` distintos, con la limitación de triage que eso implica frente a la Opción B;
- persiste el hallazgo de acoplamiento en `catalog-notifications-application.ts` hasta que un PR de Notifications lo resuelva -no es una consecuencia de aceptar este ADR, sino una precondición para que aceptarlo tenga efecto real-.
