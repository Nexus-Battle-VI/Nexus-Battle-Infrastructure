# ADR-015 — Atomicidad de Producto, auditoría y outbox en MongoDB

- **Estado:** **Proposed** — requiere aceptación del Tech Lead en Management #282
- **Fecha:** 2026-09-02
- **Decide:** Arquitectura
- **Relacionado:** [HU-33](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/41), [EN-027](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/280), [EN-027.2](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/282), [ADR-005](ADR-005-data-strategy.md), [ADR-006](ADR-006-messaging.md), [ADR-007](ADR-007-aws-cost-optimized-platform.md), [ADR-011](ADR-011-deployment-topology.md), [ADR-013](ADR-013-canonical-product-contract.md)

## Contexto

HU-33 exige que una creación exitosa deje tres resultados coherentes:

1. el producto canónico;
2. un registro de auditoría inmutable;
3. el evento pendiente `catalog.product.created`.

Si cualquiera falla, no debe quedar un producto parcial. Catalog utiliza MongoDB
8 con driver oficial y hoy inserta un único documento en `products`. El motor de
la demo corre como instancia standalone, con autenticación, límite de 384 MiB y
volumen persistente sobre el nodo `data` de la topología T2. En ese modo MongoDB
no admite transacciones multidocumento.

La colección desplegada no contiene productos que requieran backfill. Esta
decisión gobierna escrituras nuevas y no autoriza modificar infraestructura
productiva dentro de EN-027.2.

## Fuerzas de decisión

- atomicidad demostrable ante fallo entre Producto, auditoría y outbox;
- auditoría insert-only separada del estado mutable del agregado;
- entrega asíncrona al menos una vez, sin prometer exactly-once;
- reclamación concurrente e idempotente de eventos pendientes;
- límite de 16 MiB y crecimiento del historial;
- operación dentro del techo de USD 100 mensuales;
- compatibilidad con el MongoDB 8 y el driver oficial ya seleccionados;
- rollback sin pérdida deliberada de datos;
- no compartir la base privada de Catalog con otro servicio.

## Decisión propuesta

### 1. Replica set de un miembro para la demo

Convertir el MongoDB existente en un replica set de un solo miembro, con oplog
acotado explícitamente, y conservarlo en el mismo nodo `data`. No se añade otra
instancia EC2 ni un servicio administrado.

Un replica set de un miembro habilita transacciones y retryable writes, pero
**no proporciona alta disponibilidad**: una mayoría de un miembro sigue siendo
el mismo punto único de fallo de ADR-011. La arquitectura objetivo deberá usar
al menos tres miembros o un servicio administrado cuando exista presupuesto.

La implementación posterior deberá:

- fijar un nombre estable de replica set y un hostname resoluble;
- configurar autenticación interna mediante keyfile entregado como secreto;
- fijar el oplog de demo en 128 MiB y observar su ventana real;
- iniciar el replica set de forma idempotente y verificar que existe PRIMARY;
- añadir `replicaSet` a las URI de Catalog e Inventory;
- conservar el límite de memoria de 384 MiB solo si la prueba bajo carga no
  produce reinicios u OOM; de lo contrario, ajustar el reparto dentro del margen
  de 1 076 MiB del nodo `data` documentado en ADR-011.

### 2. Tres colecciones dentro de la base privada de Catalog

| Colección | Responsabilidad | Mutabilidad |
| --- | --- | --- |
| `products` | Estado canónico y versión de concurrencia | Mutable mediante reglas del agregado |
| `audit_log` | Actor, acción, fecha y snapshot/delta creado | Insert-only para la identidad runtime |
| `outbox` | Evento versionado pendiente de despacho | Mutable solo para claim, intento y resultado |

La identidad runtime de Catalog no recibirá `update` ni `remove` sobre
`audit_log`. Las migraciones usarán una identidad separada con permisos de
esquema. La cuenta raíz sigue siendo una capacidad operativa excepcional, no la
credencial de la aplicación.

### 3. Frontera transaccional

Crear o mutar un producto abre una sesión y una transacción MongoDB. Dentro de
ella se ejecutan, en este orden lógico:

1. insertar o actualizar `products` con filtro por `version` esperada;
2. insertar exactamente un registro en `audit_log`;
3. insertar exactamente un evento `PENDING` en `outbox`;
4. confirmar con `writeConcern: majority`.

Un error aborta la transacción completa. El caso de uso no publica directamente
en SQS y una confirmación HTTP no espera a Notifications. El `eventId` se genera
antes de persistir y es único tanto en auditoría como en outbox.

El `version` del producto empieza en cero y aumenta en cada mutación. Una
escritura cuyo filtro `{ productId, version }` no encuentre documento se traduce
en conflicto de concurrencia; no se reintenta ocultando una decisión de dominio.

### 4. Outbox y entrega

Esta decisión define el almacenamiento, no adopta todavía SQS. EN-027.4 #284
definirá transporte, AsyncAPI, reintentos y DLQ.

El dispatcher reclamará eventos mediante una operación atómica con lease. La
entrega será at-least-once y los consumidores deberán ser idempotentes. Un fallo
después de enviar y antes de marcar `DISPATCHED` puede producir una repetición y
no se presentará como exactly-once.

Estados mínimos propuestos: `PENDING | IN_FLIGHT | DISPATCHED | DEAD`. Los
eventos `PENDING`, `IN_FLIGHT` vencidos y `DEAD` no tienen TTL. Los entregados
podrán purgarse después de 30 días mediante `purgeAt`, una vez que #284 apruebe
la ventana operativa. El evento funcional permanece trazable en `audit_log`.

### 5. Retención y límites

- `products` no incorpora arrays de auditoría ni outbox, por lo que su tamaño
  permanece acotado por el contrato canónico.
- `audit_log` no usa TTL hasta que la política de retención de ADR-014 defina un
  plazo aprobado. Durante el proyecto se conserva completo.
- `outbox` se monitoriza por antigüedad del evento pendiente, número de intentos
  y profundidad por estado.
- Cada payload de outbox tendrá un límite de 256 KiB para conservar
  compatibilidad con el candidato SQS; no transportará la imagen binaria.
- Se alertará antes de que el oplog deje de cubrir la ventana necesaria para
  recuperación y observación; el oplog no sustituye un backup.

## Alternativas consideradas

| Alternativa | Resultado | Motivo |
| --- | --- | --- |
| Documento único con producto, auditoría y outbox embebidos | Rechazada | Hace atómica la escritura, pero mezcla estado mutable con historial insert-only, enfrenta al dispatcher con el agregado, dificulta índices/leases y traslada retención al límite de 16 MiB |
| Replica set de un miembro y transacción entre colecciones | **Recomendada** | Cumple la frontera atómica y separa mutabilidad sin añadir coste de cómputo; conserva el punto único de fallo y añade operación explícita |
| Escrituras secuenciales con compensación | Rechazada | Un fallo del proceso puede ocurrir antes de compensar; no garantiza auditoría ni evento pendiente |
| Publicar primero y persistir después | Rechazada | Un consumidor puede observar un producto inexistente y la publicación no puede revertirse |
| Change Stream sin outbox | Rechazada para HU-33 | Requiere igualmente replica set y no materializa por sí solo la auditoría insert-only ni el estado de despacho exigido |
| PostgreSQL o base de otro servicio | Rechazada | Rompe ownership de datos de ADR-005 y crea una transacción distribuida |
| MongoDB administrado o tres nodos para la demo | Pospuesta | Mejora disponibilidad, pero amplía coste y operación fuera del alcance aprobado; corresponde a la arquitectura objetivo |

## Coste y capacidad

La recomendación no añade EC2, IP pública, volumen ni servicio AWS. Conserva la
topología T2 estimada en ADR-011: 35,03 USD/mes encendida 24/7 o 4,07 USD/mes en
régimen de demos. El oplog propuesto consume 128 MiB dentro del volumen gp3 ya
presupuestado, por lo que el coste marginal estimado es 0 USD mientras no obligue
a ampliar el volumen.

La PoC se ejecuta con el mismo límite de 384 MiB. Esa evidencia solo demuestra
viabilidad funcional y de arranque, no capacidad productiva. La implementación
deberá añadir una prueba de carga con Catalog e Inventory concurrentes y registrar
reinicios, OOM, latencia p95 y ventana de oplog antes del despliegue.

## Seguridad

- el keyfile nunca se versiona ni se pasa como argumento visible;
- las URI y credenciales se inyectan mediante el mecanismo de secretos vigente;
- Catalog e Inventory conservan usuarios y bases lógicas independientes;
- solo la identidad de migración administra esquemas;
- la identidad runtime de Catalog puede insertar auditoría, pero no modificarla
  ni eliminarla;
- ningún consumidor de eventos accede a MongoDB.

## Observabilidad y recuperación

Métricas mínimas: estado del miembro, reinicios, memoria, ventana de oplog,
transacciones abortadas, conflictos de versión, edad del outbox más antiguo,
claims vencidos, intentos y eventos `DEAD`.

El backup incluye `products`, `audit_log`, `outbox` y la configuración del replica
set. Restaurar solo una colección rompería la evidencia de atomicidad.

## Despliegue y rollback

EN-027.2 no ejecuta estos pasos; los deja como condición de una Task posterior:

1. detener escrituras de Catalog y deshabilitar el dispatcher;
2. verificar backup restaurable del volumen y las colecciones;
3. entregar keyfile y configuración sin exponer secretos;
4. reiniciar MongoDB con replica set y oplog acotado;
5. iniciar/verificar PRIMARY de forma idempotente;
6. actualizar URI y desplegar migraciones/identidades;
7. desplegar Catalog con la escritura transaccional;
8. ejecutar prueba de fallo antes de habilitar tráfico y despacho.

Para revertir: detener escrituras, deshabilitar despacho, restaurar las versiones
compatibles de Catalog y URI y, si es imprescindible, arrancar el mismo volumen
sin `--replSet`. No se eliminan `audit_log`, `outbox` ni el oplog durante el
rollback. Cualquier reversión exige backup previo y prueba de lectura.

## Evidencia reproducible

[`scripts/verificar-atomicidad-mongo.py`](../../scripts/verificar-atomicidad-mongo.py)
levanta contenedores temporales sin volúmenes ni puertos públicos y comprueba:

1. un standalone rechaza la transacción multidocumento;
2. el replica set de un miembro confirma producto, auditoría y outbox juntos;
3. un duplicado forzado aborta los tres cambios;
4. un escritor con versión obsoleta no modifica el producto;
5. el miembro continúa vivo bajo el límite de 384 MiB;
6. la salida de `replSetGetStatus` se reduce a estado, miembros y PRIMARY.

La PoC no valida autenticación/keyfile ni sustituye la prueba de carga. Esos dos
puntos quedan explícitamente como gates de implementación.

Ejecución local del 2026-09-02 con Docker Engine 29.4.0 y `mongo:8.0`:

- transacción standalone rechazada;
- commit válido: `3_OF_3` documentos;
- fallo forzado: `0_OF_2_PARTIAL_WRITES` persistidas;
- escritor obsoleto rechazado por versión;
- replica set: un miembro y un PRIMARY;
- memoria observada al finalizar: aproximadamente 146 MiB de 384 MiB (variación
  observada de 145,1 a 146,8 MiB entre ejecuciones).

La cifra de memoria es una observación puntual de la PoC sin carga y no se usa
como estimación de producción.

El flujo propuesto y el estado actual están separados visualmente en
[`catalog-atomicity-audit-outbox.puml`](../diagrams/catalog-atomicity-audit-outbox.puml).

## Condiciones para pasar a Accepted

- aprobación registrada del Tech Lead en Management #282;
- PoC reproducida en CI y en el motor local;
- aceptación explícita de la limitación de un solo miembro;
- confirmación del límite de oplog y la estrategia de keyfile;
- aceptación de la retención propuesta o sustitución por plazos aprobados;
- creación de Tasks separadas para configuración del replica set, escritura
  transaccional, auditoría y outbox;
- ningún `terraform apply` ni cambio productivo como parte de este ADR.

## Consecuencias

**Lo que se gana**

- una frontera atómica verificable para HU-33;
- auditoría y outbox con ciclos de vida e índices independientes;
- concurrencia optimista explícita;
- camino directo hacia SQS sin acoplar la transacción al transporte.

**Lo que cuesta**

- operación de replica set, keyfile, inicialización y monitorización;
- transacciones más costosas que un único insert;
- la demo conserva un punto único de fallo;
- se requieren nuevas migraciones y separación de credenciales;
- la entrega sigue siendo at-least-once y exige idempotencia.
