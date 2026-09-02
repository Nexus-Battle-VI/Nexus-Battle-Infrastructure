# ADR-017 — Entrega de eventos de Producto mediante SQS

- **Estado:** **Proposed** — requiere aprobación del Tech Lead y del coste en [EN-027.4 #284](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/284)
- **Fecha:** 2026-09-02
- **Decide:** Arquitectura, con validación de Catalog, Notifications y Tech Lead
- **Relacionado:** [ADR-006](ADR-006-messaging.md), [ADR-007](ADR-007-aws-cost-optimized-platform.md), [ADR-013](ADR-013-canonical-product-contract.md), [ADR-015](ADR-015-catalog-atomicity-audit-outbox.md), [HU-33 #41](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/41), [HU-38 #46](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/46)

## Contexto

HU-33 exige publicar `catalog.product.created` después de crear un Producto de
forma auditable. HU-38 consumirá cambios de catálogo para construir
notificaciones y banners, pero no debe convertir la transacción de creación en
una llamada síncrona a Notifications.

ADR-006 propuso SQS como candidato, sin adoptarlo. Notifications ya tiene puertos
y pruebas para visibilidad, reentrega, idempotencia y DLQ, pero no existe un
adaptador AWS ni una cola provisionada. El catálogo de eventos todavía usa
`catalog.product.published`, mientras el contrato funcional vigente exige
`catalog.product.created`.

ADR-015 decidió que Producto, auditoría y outbox se escriban en la misma
transacción MongoDB. El envío a SQS ocurre después del commit y puede repetirse
si el proceso cae entre `SendMessage` y marcar el outbox como entregado. Por
tanto, el transporte debe aceptar duplicados y no puede prometer exactly-once.

## Fuerzas de decisión

- desacoplar la disponibilidad de Catalog y Notifications;
- conservar atomicidad interna sin transacción distribuida MongoDB/SQS;
- costo bajo y variable dentro del techo de USD 100;
- contrato versionado antes de implementar productor y consumidor;
- reintentos basados en atributos reales de SQS;
- idempotencia estable ante reenvíos y redrive;
- ausencia de orden global garantizado;
- mínimo privilegio y cifrado sin introducir KMS de pago;
- ejecución local y CI sin credenciales AWS;
- posibilidad de añadir consumidores sin que compitan por el mismo mensaje.

## Decisión propuesta

### 1. Alcance y ownership

| Responsabilidad | Owner |
| --- | --- |
| Crear el hecho de dominio y persistirlo en outbox con Producto/auditoría | **Catalog** |
| Despachar el mismo `eventId` a SQS y registrar el resultado | **Catalog** |
| Cola, DLQ, IAM, cifrado, alarmas y etiquetas | **Infrastructure** |
| Recibir, validar versión y deduplicar por `eventId` | **Notifications** |
| Materializar notificaciones por jugador, consolidar y presentar | **HU-38 / Notifications y Web**, fuera de EN-027.4 |
| Definir semántica funcional del aviso al jugador | **Product Owner de HU-38** |

Catalog publica un evento del sistema, no un mensaje por jugador. Notifications
lo consume una vez y decide posteriormente cómo materializar destinatarios.

### 2. Topología SQS

Se adopta, únicamente para este flujo, una cola **SQS Standard** punto a punto:

```text
nexus-battle-<environment>-catalog-product-created-notifications
nexus-battle-<environment>-catalog-product-created-notifications-dlq
```

Configuración inicial:

| Parámetro | Valor |
| --- | --- |
| Tipo | Standard; entrega at-least-once y orden best-effort |
| Long polling | 20 segundos |
| Visibility timeout | 60 segundos; el handler debe terminar antes o extenderlo explícitamente |
| Retención de cola principal | 4 días |
| Retención de DLQ | 14 días |
| `maxReceiveCount` | 5 |
| Recepción | lotes de hasta 10 |
| Tamaño contractual | máximo 64 KiB, aunque SQS admita más |
| Cifrado | SSE-SQS con clave administrada por SQS, sin KMS de cliente |
| Transporte | HTTPS + Signature Version 4 |

Una cola SQS distribuye mensajes entre consumidores; no hace broadcast. Si en
el futuro otro bounded context necesita este evento, recibe su propia cola
mediante un fan-out aprobado. No se conectan varios contextos a esta cola.

### 3. Contrato versionado

La fuente formal es
[catalog-events-v1.asyncapi.yaml](../contracts/catalog-events-v1.asyncapi.yaml).
El envelope V1 contiene:

- `eventId`: UUID estable generado al insertar el outbox;
- `eventType`: valor fijo `catalog.product.created`;
- `eventVersion`: entero fijo `1`;
- `aggregateId`: igual al `productId` canónico;
- `occurredAt`: instante UTC del hecho, no del envío;
- `producer`: valor fijo `catalog`;
- `correlationId`: trazabilidad de la solicitud original;
- `data`: `productId`, `name`, `type`, `lifecycleStatus` e `imageUrl` canónica.

No incluye actor administrativo, access token, TOTP, atributos completos, precio
real, correo, contenido binario ni URL S3 firmada. La auditoría conserva actor y
valores creados dentro de Catalog; no se replica información innecesaria.

El evento se denomina `created`, no `published`: la creación vigente nace
`ACTIVE` y el hecho requerido por HU-33 es la creación. El evento heredado
`catalog.product.published` puede seguir existiendo internamente durante la
migración, pero no se publican ambos por el mismo hecho.

### 4. Entrega e idempotencia

1. Catalog abre la transacción de ADR-015.
2. Inserta Producto, auditoría y outbox con un `eventId` único.
3. Después del commit, un dispatcher reclama el outbox mediante lease.
4. Envía el envelope sin modificar `eventId` ni `occurredAt`.
5. Solo después de `SendMessage` exitoso marca el outbox entregado.
6. Notifications valida envelope y versión.
7. Notifications registra `eventId` en su inbox/almacén idempotente con índice único.
8. Ejecuta el efecto una vez y elimina el mensaje de SQS.

Una caída después del envío y antes de marcar el outbox causa un duplicado. Una
caída después del efecto y antes de `DeleteMessage` también. Ambas rutas se
resuelven con el mismo `eventId`; no se usa el SQS MessageId como identidad de
negocio.

### 5. Reintentos, mensajes inválidos y DLQ

- `ApproximateReceiveCount` es la única fuente del número de intento.
- Error transitorio: no borrar; dejar vencer o extender visibility timeout.
- Envelope inválido o versión no soportada: registrar sin payload sensible,
  enviar a DLQ de forma controlada y borrar el original.
- Al quinto receive fallido, la redrive policy mueve el mensaje a DLQ.
- La DLQ solo permite redrive desde la cola fuente definida.
- El redrive es una operación administrativa auditada, con causa corregida y
  consumidor idempotente comprobado.
- Consultar mensajes desde la consola también incrementa receives; no se usa
  como mecanismo habitual de inspección.

El orden no está garantizado. Todo consumidor compara `occurredAt`, versión del
agregado o estado vigente cuando el orden sea relevante. HU-33 solo incorpora
`created`; futuros eventos de actualización deben definir su regla de obsolescencia.

### 6. Evolución compatible

| Cambio | Regla |
| --- | --- |
| Añadir campo opcional dentro de `data` | Compatible dentro de V1 |
| Añadir nuevo `eventType` | Compatible con consumidor que rechaza/desvía desconocidos de forma controlada |
| Retirar o volver obligatorio un campo opcional | Incompatible; nueva versión |
| Renombrar campo/evento o cambiar tipo/semántica | Incompatible; nueva versión |
| Publicar V2 | Convivencia V1/V2 hasta demostrar cero consumidores V1 |

El consumidor valida `eventType + eventVersion`. No infiere versión a partir del
nombre de cola ni acepta silenciosamente payloads desconocidos.

### 7. Seguridad y limitación de la demo

- política de cola sin principal público;
- Catalog: `sqs:SendMessage` únicamente sobre la cola principal;
- Notifications: `ReceiveMessage`, `DeleteMessage`, `ChangeMessageVisibility` y
  `GetQueueAttributes` sobre la cola principal;
- redrive administrativo separado para DLQ;
- SSE-SQS y HTTPS/SigV4 obligatorios;
- logs sin body completo, credenciales, JWT ni datos personales;
- payload mínimo y menor de 64 KiB;
- sin credenciales AWS estáticas en contenedores o repositorios.

Los contenedores de la demo comparten el rol IAM del nodo EC2. Como en ADR-016,
los permisos se pueden acotar a colas y acciones, pero no aislar realmente por
contenedor. Se acepta como limitación de demo; la arquitectura objetivo asigna
identidad de workload por servicio.

### 8. Observabilidad

Métricas y alarmas mínimas:

- `ApproximateNumberOfMessagesVisible` y `ApproximateAgeOfOldestMessage`;
- `ApproximateNumberOfMessagesNotVisible`;
- `ApproximateNumberOfMessagesVisible` de la DLQ mayor que cero;
- envíos, duplicados descartados, versiones rechazadas y fallos del handler;
- edad del outbox pendiente y leases vencidos;
- diferencia entre eventos confirmados en outbox y envíos exitosos.

Cada log usa `eventId`, `aggregateId`, `correlationId`, `eventType` y versión.
No registra el envelope completo por defecto.

### 9. Coste

La estimación reproducible está en
[catalog-events-sqs-estimate.md](../costs/catalog-events-sqs-estimate.md).

Para 10 000 eventos/mes y un worker con long polling continuo se estiman
159 600 solicitudes: aproximadamente USD 0 bajo la franquicia mensual de un
millón de requests, o USD 0,064 sin asumirla. Dos alarmas estándar agregan hasta
USD 0,20/mes fuera de su franquicia.

En la sensibilidad de un millón de eventos se estiman 3,13 millones de requests:
USD 0,85 después de la franquicia, más hasta USD 0,20 de alarmas. No existe
tarifa mínima de SQS y no se adopta KMS de cliente.

### 10. Despliegue y rollback

EN-027.4 no provisiona recursos ni instala SDK. Después de aceptar:

1. crear Task de IaC para cola, DLQ, políticas y alarmas;
2. desplegar adaptadores con `CATALOG_EVENT_DISPATCH_ENABLED=false`;
3. comprobar contrato e idempotencia con SQS emulado/local y ambiente de prueba;
4. habilitar primero productor, verificar backlog y luego consumidor;
5. ejecutar duplicado, reintento, poison message, DLQ y redrive;
6. observar edad, DLQ y coste antes de considerar completada HU-33.

Rollback:

- deshabilitar despacho sin borrar outbox pendiente;
- detener consumidor sin eliminar cola;
- revertir adaptadores conservando datos de inbox/outbox;
- no purgar ni destruir colas hasta inventariar mensajes;
- reprocesar solo después de restaurar compatibilidad e idempotencia.

## Alternativas consideradas

| Alternativa | Resultado | Motivo |
| --- | --- | --- |
| SQS Standard + outbox/inbox | **Recomendada** | Bajo costo, at-least-once explícito y patrones ya probados |
| SQS FIFO | Rechazada | Orden y deduplicación del broker no eliminan la idempotencia extremo a extremo; mayor coste sin necesidad para `created` |
| SNS + una SQS | Pospuesta | Añade un servicio sin fan-out actual; se evalúa cuando exista un segundo consumidor |
| EventBridge | Rechazada para este alcance | Enrutado innecesario con un consumidor |
| HTTP síncrono Catalog → Notifications | Rechazada | Acopla creación a disponibilidad del consumidor |
| Publicar directamente sin outbox | Rechazada | Puede perder el evento entre commit Mongo y envío |
| Kafka/RabbitMQ autoalojado | Rechazada | Operación y memoria desproporcionadas para la demo |

## Condiciones para pasar a Accepted

- aprobación del Tech Lead de Standard, parámetros, envelope y semántica;
- validación de Catalog como productor y Notifications como consumidor;
- aprobación de coste dentro del techo;
- AsyncAPI válido y diagrama renderizable;
- aceptación explícita de at-least-once, duplicados y falta de orden;
- aceptación de la limitación IAM del rol EC2 compartido;
- Tasks separadas de IaC, productor/outbox, consumidor/inbox y pruebas;
- ningún `terraform apply` ni cambio runtime dentro de esta decisión.

## Consecuencias

**Lo que se gana**

- creación de Producto desacoplada de Notifications;
- evento recuperable mediante outbox y cola durable;
- contrato versionado e idempotencia verificable;
- costo marginal bajo y observable;
- base concreta para el consumo posterior de HU-38.

**Lo que cuesta**

- entrega duplicada y orden no garantizado;
- operación de DLQ y redrive;
- adaptadores AWS en Catalog y Notifications;
- datos adicionales de inbox/outbox;
- permisos IAM compartidos a nivel del nodo durante la demo.