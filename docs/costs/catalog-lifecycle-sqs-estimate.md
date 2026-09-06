# Estimación de coste — Eventos de ciclo de vida de Producto en SQS

> Estimación para [ADR-018](../adr/ADR-018-catalog-lifecycle-events-transport.md) / [Management #314](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/314). No autoriza provisionar recursos: la estimación acompaña la aprobación de la decisión, no un `terraform apply`.

Misma metodología que
[catalog-events-sqs-estimate.md](catalog-events-sqs-estimate.md) (ADR-017);
**no se copian sus cifras de resultado** porque el volumen esperado de esta
cola es distinto -los cuatro eventos de ciclo de vida son acciones
administrativas (suspender, reactivar, ajustar tiraje, configurar Premium),
no un evento por cada registro de usuario como `catalog.product.created`-.

- Región: `us-east-1`.
- Cola: SQS Standard + una DLQ Standard, **distintas** de las de
  `catalog.product.created` (ADR-017) y de la cola general de Notifications:
  ninguna comparte recursos con esta estimación.
- Mensaje contractual: máximo 64 KiB; cada acción cuenta como una request.
- Long polling: 20 segundos.
- Cifrado: SSE-SQS, sin clave KMS de cliente.
- Precios consultados el 2026-09-02 (misma fecha y misma fuente que
  ADR-017; no se revalidaron precios nuevos porque AWS no cambió su tabla de
  SQS/CloudWatch entre una estimación y otra).

Fuentes oficiales (idénticas a la estimación de ADR-017, misma fuente
aprobada del proyecto, no se inventan precios nuevos):

- [Amazon SQS Pricing](https://aws.amazon.com/sqs/pricing/);
- [cuotas de mensajes SQS](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/quotas-messages.html);
- [dead-letter queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html);
- [SSE-SQS](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-configure-sqs-sse-queue.html);
- [CloudWatch Pricing](https://aws.amazon.com/cloudwatch/pricing/).

## Precios y medición

Mismos precios que ADR-017, referenciados y no reinventados:

| Concepto | Precio usado |
| --- | ---: |
| Primer millón de requests SQS al mes | USD 0,00, agregado por cuenta/regiones aplicables |
| SQS Standard después de la franquicia | USD 0,40 por millón |
| SSE-SQS | sin tarifa adicional |
| Transferencia entre servicios en la misma región | USD 0 |
| Alarma CloudWatch estándar | sensibilidad de USD 0,10 por métrica/mes |

**La franquicia del primer millón de requests es POR CUENTA, no por cola.**
Esta cola comparte esa franquicia con la de `catalog.product.created`
(ADR-017) y con cualquier otra cola SQS de la cuenta: la columna "con
franquicia" de ambas estimaciones no debe sumarse como si cada una tuviera su
propio millón gratuito. La columna "sin franquicia" sí es aditiva y es la
comparación conservadora correcta.

## Supuestos explícitos de volumen

A diferencia de `catalog.product.created` -un evento por cada alta de
Producto-, los cuatro eventos de ciclo de vida son acciones administrativas
deliberadas (HU-34, HU-35, HU-36): suspender/reactivar un Producto, ajustar su
tiraje o configurar su condición Premium. No hay en este repositorio un dato
de uso real que fije su frecuencia -es una demo académica, no un catálogo en
producción-, así que el supuesto siguiente es una elección explícita y
conservadora hacia el lado alto, no una medición:

| Supuesto mensual | Cantidad | Justificación |
| --- | ---: | --- |
| Eventos de ciclo de vida combinados (los 4 `eventType`) | 2 000 | Orden de magnitud de operaciones administrativas manuales sobre un catálogo de demo; muy por debajo de los 10 000 `catalog.product.created` de ADR-017, que es un supuesto ya aprobado para un evento de mayor frecuencia |

## Escenario de demo

| Supuesto mensual | Cantidad |
| --- | ---: |
| Eventos de ciclo de vida | 2 000 |
| SendMessage | 2 000 |
| ReceiveMessage exitosos | 2 000 |
| DeleteMessage | 2 000 |
| Polls máximos de un worker 24/7 a 20 s | 129 600 |
| Reintentos/DLQ | 0 en el cálculo base |
| Mensaje | menor o igual a 64 KiB |

El cálculo de polls es el mismo de ADR-017: un worker con long polling
continuo de 20 s genera como máximo 129 600 polls/mes
(30 días × 86 400 s ÷ 20 s), independientemente del volumen de eventos.

| Partida | Fórmula | Requests | USD con franquicia\* | USD sin franquicia |
| --- | --- | ---: | ---: | ---: |
| Envío | 2 000 | 2 000 | 0,000 | 0,0008 |
| Recepción/poll | 2 000 + 129 600 | 131 600 | 0,000 | 0,0526 |
| Borrado | 2 000 | 2 000 | 0,000 | 0,0008 |
| **SQS total** | | **135 600** | **0,000\*** | **0,0542** |

\*Columna "con franquicia" asumiendo que el millón de requests gratuito
todavía no lo consumió la cola de `catalog.product.created` ni otra cola de
la cuenta. La columna "sin franquicia" es la que debe usarse para sumar
contra el techo de ADR-007 junto con el resto de la plataforma.

Dos alarmas estándar -edad de la cola y mensajes visibles en su DLQ propia-
pueden sumar hasta USD 0,20/mes fuera de la franquicia aplicable de
CloudWatch.

**Total conservador de demo:** entre USD 0,00 y **USD 0,2542/mes** antes de
impuestos, según franquicias compartidas.

## Escenario de sensibilidad

Mismo supuesto de sensibilidad que ADR-017 (1 000 000 de eventos/mes), para
comparar en el mismo orden de magnitud aunque sea muy improbable para eventos
administrativos:

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

Idéntico resultado numérico al escenario de sensibilidad de ADR-017 porque el
cálculo depende solo del número de requests, no del `eventType`; se mantiene
aquí por completitud comparativa, no porque se espere ese volumen para
eventos administrativos.

## Comparación contra el techo de ADR-007

El escenario de demo de esta cola (hasta USD 0,2542/mes) sumado al de
`catalog.product.created` (hasta USD 0,264/mes, ADR-017) es
**USD 0,5182/mes en el peor caso sin franquicia compartida** — una fracción
insignificante del techo mensual de USD 100 (ADR-007) y del objetivo
operativo de USD 25. Incluso el escenario de sensibilidad combinado de ambas
colas (hasta USD 2,904/mes) permanece muy por debajo del techo.

## Controles de coste

Mismos controles que ADR-017, aplicados también a esta cola:

- mensaje menor o igual a 64 KiB y sin binarios;
- long polling de 20 segundos y lotes de hasta diez;
- una cola por consumidor, creada únicamente cuando exista el consumidor;
- métricas nativas; no publicar métricas personalizadas duplicadas;
- alarma de edad y alarma de DLQ, propias de esta cola;
- etiqueta de proyecto, entorno, owner y centro de costo;
- revisar costo real mensual contra esta estimación una vez desplegada;
- nueva aprobación antes de SNS, EventBridge, KMS de cliente u otra región.

**Esto es una estimación, no una factura real.** El coste real depende del
volumen efectivo de operaciones administrativas de Catalog una vez el
dispatcher exista y la cola esté aplicada (`terraform apply`), ninguno de los
cuales ocurre en este cambio.
