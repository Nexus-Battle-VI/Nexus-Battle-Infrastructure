# Estimación de coste — Eventos de Producto en SQS

> Estimación para EN-027.4 #284. No autoriza provisionar recursos.

- Región: `us-east-1`.
- Cola: SQS Standard + una DLQ Standard.
- Mensaje contractual: máximo 64 KiB; cada acción cuenta como una request.
- Long polling: 20 segundos.
- Cifrado: SSE-SQS, sin clave KMS de cliente.
- Precios consultados el 2026-09-02.

Fuentes oficiales:

- [Amazon SQS Pricing](https://aws.amazon.com/sqs/pricing/);
- [cuotas de mensajes SQS](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/quotas-messages.html);
- [dead-letter queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html);
- [SSE-SQS](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-configure-sqs-sse-queue.html);
- [CloudWatch Pricing](https://aws.amazon.com/cloudwatch/pricing/).

## Precios y medición

| Concepto | Precio usado |
| --- | ---: |
| Primer millón de requests SQS al mes | USD 0,00, agregado por cuenta/regiones aplicables |
| SQS Standard después de la franquicia | USD 0,40 por millón |
| SSE-SQS | sin tarifa adicional |
| Transferencia entre servicios en la misma región | USD 0 |
| Alarma CloudWatch estándar | sensibilidad de USD 0,10 por métrica/mes |

Cada acción `SendMessage`, `ReceiveMessage`, `DeleteMessage` y
`ChangeMessageVisibility` cuenta como request. Cada bloque de 64 KiB se factura
como una request. No se afirma que la franquicia esté siempre disponible: puede
ser consumida por otras colas de la misma cuenta.

## Escenario de demo

| Supuesto mensual | Cantidad |
| --- | ---: |
| Eventos creados | 10 000 |
| SendMessage | 10 000 |
| ReceiveMessage exitosos | 10 000 |
| DeleteMessage | 10 000 |
| Polls máximos de un worker 24/7 a 20 s | 129 600 |
| Reintentos/DLQ | 0 en el cálculo base |
| Mensaje | menor o igual a 64 KiB |

El cálculo es conservador porque una recepción puede devolver hasta diez
mensajes y los polls con tráfico sustituyen parte de los polls vacíos.

| Partida | Fórmula | Requests | USD con franquicia | USD sin franquicia |
| --- | --- | ---: | ---: | ---: |
| Envío | 10 000 | 10 000 | 0,000 | 0,004 |
| Recepción/poll | 10 000 + 129 600 | 139 600 | 0,000 | 0,056 |
| Borrado | 10 000 | 10 000 | 0,000 | 0,004 |
| **SQS total** | | **159 600** | **0,000** | **0,064** |

Dos alarmas estándar —edad de la cola y mensajes visibles en DLQ— pueden sumar
hasta USD 0,20/mes fuera de la franquicia aplicable de CloudWatch.

**Total conservador de demo:** entre USD 0,00 y **USD 0,264/mes** antes de
impuestos, según franquicias compartidas.

## Escenario de sensibilidad

| Supuesto mensual | Cantidad |
| --- | ---: |
| Eventos | 1 000 000 |
| Send + Receive + Delete | 3 000 000 requests |
| Polls continuos adicionales | 129 600 requests |
| Total | 3 129 600 requests |

| Condición | SQS USD/mes | Alarmas | Total |
| --- | ---: | ---: | ---: |
| Con primer millón sin cargo | 0,852 | 0,20 | **1,052** |
| Sin asumir franquicia | 1,252 | 0,20 | **1,452** |

El cálculo no incluye reintentos masivos. Una tasa de fallo sostenida debe
considerarse incidente: multiplica receives y puede llenar la DLQ, pero no
justifica dimensionar el caso base como operación normal.

## Controles de coste

- mensaje menor o igual a 64 KiB y sin binarios;
- long polling de 20 segundos y lotes de hasta diez;
- una cola por consumidor, creada únicamente cuando exista el consumidor;
- métricas nativas; no publicar métricas personalizadas duplicadas;
- alarma de edad y alarma de DLQ;
- etiqueta de proyecto, entorno, owner y centro de costo;
- revisar costo real mensual contra esta estimación;
- nueva aprobación antes de SNS, EventBridge, KMS de cliente o otra región.

Sumado al escenario de sensibilidad documentado para la plataforma y assets,
el costo de SQS no compromete el techo de USD 100. La principal protección
económica sigue siendo no crear consumidores o colas sin una capacidad activa.