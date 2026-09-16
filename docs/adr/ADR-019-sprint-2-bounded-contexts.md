# ADR-019 — Contextos acotados de Sprint 2: Combat, Missions, Auction y Wallet

- **Estado:** Proposed
- **Fecha:** 2026-09-16
- **Decide:** Arquitectura, con validación obligatoria de Product Owners y Scrum Masters (nombre, alcance y Team de cada repositorio, conforme a [ADR-001](ADR-001-repository-strategy.md))
- **Relacionado:** [ADR-001](ADR-001-repository-strategy.md), [ADR-002](ADR-002-backend-stack.md), [ADR-005](ADR-005-data-strategy.md), [ADR-006](ADR-006-messaging.md), [ADR-007](ADR-007-aws-cost-optimized-platform.md), [ADR-011](ADR-011-deployment-topology.md), [ADR-020](ADR-020-realtime-combat.md), [EPIC-06 #6](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/6), [EPIC-07 #7](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/7), [EPIC-08 #8](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/8), [EN-012 #198](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/198)

## Contexto

Sprint 2 abre tres épicas que ningún servicio existente cubre: **Jugar Online**
(EPIC-06), **Subasta** (EPIC-07) y **Misiones** (EPIC-08). Antes de crear
repositorios hay que aplicar la cadena de [ADR-001](ADR-001-repository-strategy.md)
—requisito, dominio, contexto, **propiedad de datos**, dependencias, contrato,
deployable, Team— y no la intuición de «una épica, un repositorio».

Cinco hechos verificados condicionan la decisión:

1. **Ningún servicio custodia el saldo de créditos.** Catalog guarda
   `creditsPrice` como atributo del Producto, pero no existe saldo, reserva ni
   movimiento en ningún repositorio. Aun así, lo consumen HU-62 (comisión),
   HU-63 (reserva de puja), HU-65 (liquidación), HU-23 (apuesta), HU-22 (cofre)
   y HU-10 (recompensas). La Task HU-63.2 (Management #316) pide «revisar el
   contrato actual del servicio de créditos»: ese contrato no existe.
2. **Jugar Online y Misiones deben aplicar las mismas reglas de combate y el
   mismo generador de aleatoriedad** (HU-72: «mismas mecánicas», «mismo motor
   centralizado»; HU-24: «un único generador centralizado»). ADR-001 prohíbe
   compartir entidades de dominio mediante un paquete común, así que el motor
   solo puede vivir en **un** deployable.
3. **El héroe, su equipamiento y sus estadísticas efectivas ya pertenecen a
   Player/Inventory** (`HeroLoadout`, `effective-stats`, `HeroReadinessPolicy`).
   Falta la **disponibilidad única** del héroe y del ítem: la épica de Misiones
   declara como riesgo usar el mismo héroe en misión, batalla y torneo a la vez,
   y HU-29 (bloqueo de equipamiento en combate) sigue abierta.
4. **Las Tasks de HU-65 (Management #323 a #328) nombran `Nexus-Battle-Commerce`**
   como repositorio de la subasta. Este ADR propone otra ubicación; la Task
   debe realinearse en Management, que este repositorio no modifica.
5. **Capacidad medida el 2026-09-16 por SSM**, no estimada:

   | Nodo | Memoria total | En uso | Disponible | Observación |
   | --- | ---: | ---: | ---: | --- |
   | `app` | 1 841 MiB | 893 MiB | 766 MiB | Cada servicio NestJS usa 50–72 MiB en reposo; suma de `mem_limit` en marcha: 1 104 MiB |
   | `data` | 1 841 MiB | 493 MiB | 1 153 MiB | MongoDB 202/384 MiB, PostgreSQL 47/288 MiB; disco 18 % |

## Decisión

### Cuatro contextos nuevos

| Contexto | Repositorio | Datos que posee en exclusiva | Motor | Puerto | Team |
| --- | --- | --- | --- | ---: | --- |
| Combat | `Nexus-Battle-Combat` | Salas y lobby, batallas (participantes, orden de turnos, vida, Poder, efectos, bitácora), semillas y simulaciones, mensajes de chat | MongoDB | 3006 | Por asignar |
| Missions | `Nexus-Battle-Missions` | Definiciones y tablón de misiones, matrículas, rotaciones, progreso de dificultad, reportes, logros | PostgreSQL | 3007 | Por asignar |
| Auction | `Nexus-Battle-Auction` | Subastas, pujas, pujas automáticas, seguimiento, liquidaciones, productos pendientes de reclamo | PostgreSQL | 3008 | Por asignar |
| Wallet | `Nexus-Battle-Wallet` | Saldos de créditos, reservas, libro de movimientos insert-only | PostgreSQL | 3009 | Por asignar |

Los cuatro heredan íntegro el arquetipo de [ADR-002](ADR-002-backend-stack.md):
NestJS 11.2.1, TypeScript 5.9.3, Clean + Hexagonal con `no-restricted-imports`,
casos de uso sin decoradores, verificación JWT de Cognito obligatoria en
producción, HMAC para rutas internas, sondas `/api/health/*` y `/api/version`,
cobertura ≥ 80 %, pruebas contra motor real con Testcontainers, `main` y
`develop` protegidas y publicación multi-arquitectura en GHCR solo desde `main`.

### Por qué cada uno es un contexto y no un módulo de otro

**Combat reúne salas, motor y aleatoriedad.** La batalla es un único agregado:
el orden de turnos, la vida, el Poder y la bitácora cambian juntos y sus
invariantes —no actuar fuera de turno, no dañar aliados sin autorización, no
consumir Poder que no hay— abarcan la batalla completa. Separar «salas» de
«motor» partiría ese agregado en dos almacenes. Se elige **MongoDB** por el
mismo criterio que Player/Inventory: el agregado se lee y escribe entero, con
bloqueo optimista por versión.

**El motor no es un servicio aparte.** Un «Engine» sin estado no posee datos, y
según ADR-001 sin propiedad exclusiva de datos no hay deployable. Además la
semilla y la simulación sí son datos, y pertenecen a quien ejecuta el combate.

**Missions es otro contexto, aunque reutiliza el motor.** Posee datos que
Combat no conoce —tablón, matrícula, progreso de dificultad, logros— y tiene
otro ciclo de vida: asíncrono, sin jugador conectado. **No duplica reglas**:
pide la simulación a Combat por contrato interno y guarda el resultado. Se
elige **PostgreSQL** porque sus invariantes son relacionales y el motor puede
imponerlas: «un héroe no está en dos misiones activas» es un índice único
parcial, y «no se accede a Heroico sin completar Normal» es una consulta sobre
historial, no un documento.

**Auction no es un módulo de Commerce.** Commerce posee pedidos de compra con
precio congelado del catálogo; la subasta posee un precio que **descubren los
postores**, con temporizador, pujas concurrentes y reclamo diferido. Son
agregados distintos con ciclos de vida distintos. Meterla en Commerce ahorraría
un contenedor a cambio de convertir a Commerce en el centro de toda la economía.
Se elige **PostgreSQL** por el control de concurrencia de pujas
(`SELECT ... FOR UPDATE` sobre la subasta) y por `CHECK` sobre importes.

**Wallet es un contexto propio porque tiene cuatro consumidores.** Auction,
Combat, Missions y, más adelante, Commerce mueven créditos. Si el saldo viviera
dentro de uno de ellos, los otros tres dependerían de un servicio cuyo propósito
es otro, y la invariante económica central —**ningún crédito se crea, duplica o
pierde fuera de una operación válida**— quedaría repartida. Se elige
**PostgreSQL** para imponerla en el motor: `CHECK (available >= 0)`,
`CHECK (reserved >= 0)`, `operation_id` único, importes `bigint` y movimientos
insert-only.

### Cambios en contextos existentes

| Contexto | Cambio | Por qué ahí |
| --- | --- | --- |
| Player/Inventory | **Compromisos** del héroe y del ítem (`BATTLE`, `MISSION`, `AUCTION`, `TOURNAMENT`) y **perfil de combate** del héroe | Ya es la fuente de verdad del héroe y del equipamiento; la disponibilidad única debe vivir junto a lo que se bloquea. Absorbe HU-29 |
| Player/Inventory | Ampliar los servicios autorizados de `POST /api/internal/v1/inventory/grants` a `auction` y `missions` | El reclamo de HU-69 y las recompensas de HU-10 son entregas al inventario con el mismo contrato idempotente de HU-59 |
| Notifications | Plantillas nuevas (puja superada, liquidación, fin de misión, logro) recibidas por la ingesta HTTP que ya usa Account | Evita colas nuevas en Sprint 2 |
| Commerce | **Ninguno en Sprint 2** | Cuando compre con créditos, consumirá Wallet por el mismo contrato |

### Integraciones

Criterio de [ADR-006](ADR-006-messaging.md): síncrono cuando quien llama no
puede continuar sin la respuesta.

| Origen | Destino | Operación | Modo | Idempotencia |
| --- | --- | --- | --- | --- |
| Auction | Wallet | Reservar comisión y pujas; capturar al liquidar; liberar al ser superada | Síncrono | `operationId` |
| Auction | Player/Inventory | Comprometer el producto al publicar; consumir al liquidar; liberar sin pujas | Síncrono | `operationId` |
| Auction | Player/Inventory | Entregar el producto reclamado (HU-69) | Síncrono | `operationId` |
| Combat | Player/Inventory | Perfil de combate y compromiso del héroe al iniciar; liberar al terminar | Síncrono | `operationId` |
| Combat | Wallet | Reservar apuesta; transferir al ganador; liberar si se cancela | Síncrono | `operationId` |
| Missions | Player/Inventory | Perfil de combate, compromiso `MISSION`, recompensas | Síncrono | `operationId` |
| Missions | Combat | Ejecutar simulación de misión | Síncrono | `operationId` |
| Missions | Wallet | Acreditar recompensas en créditos | Síncrono | `operationId` |
| Auction, Missions, Combat | Notifications | Solicitud de notificación | Asíncrono por ingesta HTTP | Identificador del mensaje |

Todas las rutas internas usan el esquema ya vigente: prefijo
`/api/internal/v1/<contexto>`, cabeceras `x-internal-service`,
`x-internal-timestamp` y `x-internal-signature` (HMAC-SHA256 sobre JSON
canónico, ventana de 30 s), lista cerrada de servicios autorizados por ruta, y
**bloqueo en Caddy** (`/api/internal*` responde `404` desde fuera).

### Consistencia: reservas con caducidad, no transacciones distribuidas

No hay transacción común entre almacenes y no se va a simular una. Cada
operación que toca créditos o productos de otro contexto sigue el patrón de
**reserva, confirmación o cancelación**:

1. El coordinador (Auction, Combat o Missions) persiste su intención con un
   `operationId` antes de llamar.
2. Wallet o Player/Inventory **reservan** con ese `operationId`. Reintentar con
   el mismo identificador devuelve el mismo resultado; reutilizarlo con otro
   cuerpo responde `409`.
3. El coordinador **captura** o **libera** según el resultado de su propio
   agregado.
4. **Toda reserva nace con caducidad.** Si el coordinador muere entre el paso 2
   y el 3, el dueño de la reserva la libera al vencer. Una reserva huérfana no
   puede retener créditos ni productos para siempre.

La semántica de códigos es la de HU-59: `422` es un rechazo terminal
(saldo insuficiente, producto no disponible), `409` y `503` **no** autorizan a
suponer que la operación no ocurrió; se reintenta con el mismo `operationId`.

### Aleatoriedad, solo en Combat

El generador (Mersenne Twister con transformación Box-Muller, HU-24), la tabla
de efectos (HU-25) y la validación de semilla (HU-26) viven exclusivamente en
Combat. Ningún cliente recibe la semilla ni el estado del generador mientras la
batalla o la simulación siguen abiertas. Missions no genera números: recibe
resultados. Cada batalla y simulación guarda su semilla, lo que hace el
resultado **reproducible** para auditoría sin hacerlo **predecible** para el
jugador.

### Temporizadores

El vencimiento de subastas (HU-65), de reservas (Wallet), de misiones (HU-70)
y de turnos usa el patrón ya existente en Account
(`AccountDeletionProcessingScheduler`): intervalo dentro del proceso, apagado
por defecto, con **reclamación durable** en el almacén (`FOR UPDATE SKIP LOCKED`
en PostgreSQL, arrendamiento por `findOneAndUpdate` en MongoDB, como el outbox
de Catalog). El estado vive en la base, no en el temporizador: un reinicio
retrasa el vencimiento, no lo pierde. La hora la fija siempre el servidor;
ningún contrato acepta una fecha de vencimiento calculada por el cliente.

**Limitación declarada:** una sola réplica por servicio. Escalar horizontalmente
no rompería la reclamación durable, pero sí el tiempo real de [ADR-020](ADR-020-realtime-combat.md).

### Topología y coste

La topología T2 de [ADR-011](ADR-011-deployment-topology.md) **no cambia**.
Cambia el tamaño del nodo `app`:

| Escenario | Suma de `mem_limit` en marcha | Memoria del nodo |
| --- | ---: | ---: |
| Hoy | 1 104 MiB | 1 841 MiB (`t4g.small`) |
| Con cuatro servicios de 160 MiB | 1 744 MiB | 1 841 MiB — sin margen para el sistema ni para los contenedores de migración |
| **Decisión:** `app` pasa a `t4g.medium` | 1 744 MiB | 4 GiB |

Precio consultado a la Price List API el 2026-09-16 (Linux, `us-east-1`, bajo
demanda): `t4g.small` 0,0168 USD/h y `t4g.medium` 0,0336 USD/h. Encendido 24/7
son **+12,27 USD/mes** (de 12,26 a 24,53) sobre el techo de 100 de
[ADR-007](ADR-007-aws-cost-optimized-platform.md). El nodo `data` mantiene
`t4g.small`: tiene 1 153 MiB disponibles y los contextos nuevos solo añaden bases
lógicas a motores que ya corren.

**Este ADR no introduce ningún servicio de AWS nuevo.** Ninguno de los prohibidos
por ADR-007 (Lambda, DynamoDB, ECS, ALB, ElastiCache…) es necesario: WebSocket
pasa por Caddy, los temporizadores corren en proceso y las notificaciones usan
la ingesta HTTP existente.

## Consecuencias

**Lo que se gana**

- Cada contexto posee sus datos en exclusiva y puede desplegarse y fallar por separado.
- Una sola implementación del motor de combate y de la aleatoriedad para dos épicas.
- Una sola fuente de verdad del saldo y una sola de la disponibilidad del héroe,
  con las invariantes impuestas por el motor de base de datos.
- Ningún servicio de AWS nuevo y ninguna cola nueva en Sprint 2.

**Lo que cuesta**

- **Once deployables** en el producto (Web y diez servicios). Se acepta por el mismo motivo académico
  que ADR-001 declara, y porque el andamiaje se replica.
- Las operaciones económicas atraviesan la red: cada puja son dos llamadas
  internas. Se paga con idempotencia, caducidad de reservas y pruebas de fallo
  parcial, que la épica de Subasta ya exige (HU-63.7, HU-65.7).
- Missions no puede simular si Combat no responde. Es correcto: una misión
  simulada con reglas distintas sería peor que una misión que espera.
- Reemplazar el nodo `app` al cambiar su tipo y su composición. `mergear` no
  aplica nada: el `plan` por nodo se revisa antes del `apply`.
- Las Tasks HU-65.x deben realinearse en Management de Commerce a Auction.

## Alternativas consideradas

| Alternativa | Por qué se descartó |
| --- | --- |
| Subasta como módulo de Commerce | Local, la puja y la reserva serían una transacción; pero Commerce pasaría a custodiar dos agregados con ciclos de vida distintos y la economía entera. Se prefiere pagar la coordinación con reservas idempotentes |
| Saldo dentro de Commerce o de Player/Inventory | Cuatro consumidores dependerían de un servicio cuyo propósito es otro. En Player/Inventory, además, las reservas no compartirían transacción con nada que lo justifique |
| Un único servicio «Game» con Jugar Online y Misiones | Mezcla dos contextos con datos y ciclos de vida distintos en un almacén |
| Motor de combate en un servicio sin estado aparte | No posee datos; incumple el criterio de ADR-001 y añade un salto de red a cada acción de turno |
| Paquete npm común con las reglas de combate | Prohibido por ADR-001: acopla despliegues y convierte cada cambio de regla en un despliegue coordinado |
| Colas SQS para toda integración nueva | Cada cola exige ADR, Terraform y aprobación de coste; ninguna integración de Sprint 2 lo necesita |

## Lo que este ADR no hace

- No crea repositorios: ADR-001 exige que nombre, alcance y Team estén
  aprobados antes.
- No aplica Terraform ni cambia la composición desplegada.
- No define los contratos detallados: se publicarán como OpenAPI en
  `docs/contracts/` antes de implementar.
- No decide la retención ni la moderación del chat: es decisión de producto
  de HU-13 ([ADR-020](ADR-020-realtime-combat.md)).
- No decide cómo recibe un jugador sus primeros créditos: no hay Historia de
  Usuario que lo defina.

## Pendiente de aprobación

Permanece en `Proposed` hasta que Product Owners y Scrum Masters aprueben los
cuatro nombres, su alcance y su Team propietario.
