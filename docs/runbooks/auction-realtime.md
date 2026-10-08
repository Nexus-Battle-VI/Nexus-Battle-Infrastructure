# Activar y revertir el realtime de Subasta (EN-034, ADR-024)

Señales de invalidación por WebSocket para Marketplace y Detalle de Subasta. **Está apagado por
defecto** y se enciende con una variable de entorno de Auction. Este runbook cubre cómo
encenderlo, comprobarlo, apagarlo y qué esperar si se escala.

- Decisión: [ADR-024](../adr/ADR-024-realtime-auction.md). Contrato: [auction-realtime-v1.md](../contracts/auction-realtime-v1.md).
- Evidencia de la verificación: [EN-034-realtime-verificacion.md](../evidence/EN-034-realtime-verificacion.md).

> **Estado de este procedimiento — qué se probó y qué no.**
>
> - **Probado:** el efecto del interruptor. Pruebas automáticas contra PostgreSQL real arrancan la aplicación apagada, encendida y apagada sobre la misma base: apagado no hay tickets ni WebSocket y las consultas HTTP responden; encender y apagar **no cambia ningún dato persistido**; y al volver a encender las señales retoman con la `revision` correcta (Nexus-Battle-Auction, `test/db/auction-realtime-switch-postgres.spec.ts`). Además, la composición real (Caddy + Auction + PostgreSQL) se levantó en Docker local con el interruptor encendido ([evidencia](../evidence/EN-034-realtime-verificacion.md)).
> - **No probado:** los comandos de este runbook tal como están escritos (`sed` sobre `.env`, `docker compose up -d auction`, los controles con `curl`) **no se ejecutaron**, ni en Docker local ni en el nodo de AWS. Siguen el patrón de [desplegar-contextos-sprint-3.md](desplegar-contextos-sprint-3.md). Quien los ejecute por primera vez debe tratarlos como no verificados.
> - **Por razonamiento, no por prueba:** que una imagen anterior de Auction funcione con la migración 021 aplicada. Se apoya en que `revision` tiene `default 0` y en que el código actual tampoco escribe esa columna al insertar.

## Qué cambia al encenderlo

| Con `AUCTION_REALTIME_ENABLED=false` (por defecto) | Con `true` |
| --- | --- |
| `POST /api/v1/auctions/realtime/tickets` responde `404` | Responde `201` con un ticket de 30 s (`401` sin JWT, `403` sin rol) |
| `wss://…/api/v1/auctions/realtime` se rechaza | Acepta conexiones con ticket |
| No hay conexión de escucha con PostgreSQL | Auction mantiene **1 conexión extra** a PostgreSQL (`LISTEN`) |
| Las consultas HTTP funcionan igual | Igual: **siguen siendo la fuente de verdad** |

**Nada de la lógica de negocio cambia con el interruptor:** pujar, comprar, cancelar y liquidar
son HTTP transaccional en los dos casos. Caddy **no requiere cambios**: `handle /api/v1/auctions*`
ya enruta el WebSocket.

### Lo que el interruptor NO apaga

La migración 021 (columna `auctions.revision` y los triggers que avisan con `pg_notify`) **queda
instalada y activa aunque el interruptor esté apagado.** Es deliberado y es inofensivo:

- `revision` sigue avanzando con cada puja y cambio de estado. Sin oyente, `pg_notify` no tiene a
  quién entregar y su costo es despreciable.
- Por eso, al volver a encender, las señales retoman con la `revision` correcta, sin hueco.
- Una versión anterior de Auction (sin realtime) **sigue funcionando** con la migración aplicada:
  `revision` tiene `default 0` y el código viejo no la escribe.

## 0. Condiciones previas

| Condición | Comprobación |
| --- | --- |
| Auction desplegado con una imagen que incluye EN-034.2 (Nexus-Battle-Auction#99) | `docker compose images auction` y revisar el SHA contra `develop` |
| Migración 021 aplicada | `docker compose logs auction-migrate \| grep 021` debe mostrar `migration_applied` o `migrations_up_to_date` |
| **Una sola réplica de Auction** | `docker compose ps auction` debe listar un contenedor (ver «Escalar») |
| Memoria disponible en Auction | `mem_limit: 160m` es suficiente: ver la evidencia (~54 MiB con la carga de la demostración) |
| La composición expone la variable | `grep AUCTION_REALTIME_ENABLED /opt/nexus/compose.yml` (la trae Infrastructure#210) |

## 1. Encender

En el nodo `app`, por SSM:

```bash
cd /opt/nexus

# 1. Fijar la variable. La composición lee ${AUCTION_REALTIME_ENABLED:-false} de .env.
grep -q '^AUCTION_REALTIME_ENABLED=' .env \
  && sed -i 's/^AUCTION_REALTIME_ENABLED=.*/AUCTION_REALTIME_ENABLED=true/' .env \
  || echo 'AUCTION_REALTIME_ENABLED=true' >> .env

# 2. Recrear SOLO Auction (las migraciones ya corren antes por depends_on).
docker compose up -d auction
```

**Recrear Auction cierra las conexiones WebSocket abiertas y reinicia los tickets en memoria.**
Es esperado: los clientes reconectan y piden otro ticket.

## 2. Comprobar

```bash
cd /opt/nexus
docker compose ps auction                      # estado healthy
docker compose logs --since 2m auction | grep -E "auction_realtime_listener_ready|service_started"
```

Debe aparecer `auction_realtime_listener_ready` y `"realtime":true` en `service_started`. **Si
aparece `auction_realtime_listener_unavailable`, la conexión de escucha no se estableció**: ver
«Diagnóstico».

Control desde fuera, sin credenciales:

```bash
curl -s -o /dev/null -w "tickets %{http_code}\n" -X POST \
  https://nexus.simuladorupbbga.app/api/v1/auctions/realtime/tickets
curl -s -o /dev/null -w "control %{http_code}\n" https://nexus.simuladorupbbga.app/api/v1/auctions
```

| Respuesta de `tickets` | Significa |
| --- | --- |
| `401` | **Encendido**: la ruta existe y exige JWT |
| `404` | **Apagado** (o la imagen no trae EN-034.2) |
| `200` con `text/html` | La ruta cayó en Web: Caddy no está enrutando `/api/v1/auctions*` |

El control `auctions` debe seguir dando `401` o `404` con `application/json`, como en cualquier
despliegue.

## 3. Apagar (reversión)

```bash
cd /opt/nexus
sed -i 's/^AUCTION_REALTIME_ENABLED=.*/AUCTION_REALTIME_ENABLED=false/' .env
docker compose up -d auction
docker compose exec auction wget -qO- http://127.0.0.1:3008/api/health/ready
```

Después, el `curl` de «Comprobar» debe devolver `404` en `tickets`.

**Qué ve el usuario:** las conexiones se cierran y el cliente de la Web, ante un fallo permanente,
cae a sondeo HTTP con intervalo largo (comportamiento a implementar en TASK EN-034.4, #586). Las
pujas, compras y cancelaciones no se interrumpen.

**Qué NO hace falta revertir:** la migración 021, los triggers ni la columna `revision`. No hay
estado persistido que corregir.

### Si hay que volver a una imagen anterior de Auction

Fijar el tag anterior y `docker compose up -d auction`. La imagen vieja **funciona** con la
migración 021 aplicada (ver «Lo que el interruptor NO apaga»). No hace falta deshacer nada en la
base.

### Quitar la migración 021 (solo si es imprescindible)

El runner de migraciones solo avanza (`npm run migrate`). La 021 define `down`, pero no se invoca
desde el despliegue; hacerlo es una operación manual y destructiva para la `revision`:

```sql
-- Solo con Auction apagado o sin tráfico de pujas. Pierde el contador de revision.
DROP TRIGGER IF EXISTS auctions_published_realtime ON auctions;
DROP TRIGGER IF EXISTS auctions_status_realtime_notify ON auctions;
DROP TRIGGER IF EXISTS auctions_status_revision ON auctions;
DROP TRIGGER IF EXISTS auction_bids_realtime ON auction_bids;
DROP FUNCTION IF EXISTS auction_published_realtime();
DROP FUNCTION IF EXISTS auction_status_realtime_notify();
DROP FUNCTION IF EXISTS auction_status_realtime();
DROP FUNCTION IF EXISTS auction_bid_realtime();
DROP FUNCTION IF EXISTS auction_realtime_notify(text, bigint, text);
ALTER TABLE auctions DROP COLUMN revision;
DELETE FROM kysely_migration WHERE name = '021-add-auction-realtime-revision';
```

No es necesario para apagar el realtime. Existe solo por si la migración misma causara un problema.

## Diagnóstico

| Síntoma | Causa probable | Qué hacer |
| --- | --- | --- |
| `auction_realtime_listener_unavailable` en el arranque | PostgreSQL no alcanzable desde Auction, o credenciales | Auction reintenta con backoff hasta 30 s; revisar `DATABASE_URL` y la red al nodo `data` |
| `auction_realtime_listener_error` / `…_ready` repetidos | La conexión de escucha se cae (reinicio de PostgreSQL, red) | Los clientes reciben `resync` al recuperarse y releen por HTTP. Si es frecuente, revisar `max_connections` del nodo `data` |
| `auction_realtime_notice_discarded` | Una carga de `pg_notify` mal formada | Descartada sin afectar al resto. Si persiste, comparar la migración 021 aplicada con la del repositorio |
| Los clientes se conectan pero no reciben señales | El oyente no está activo, o la migración 021 no está aplicada | Comprobar `auction_realtime_listener_ready` y que `revision` existe: `\d auctions` |
| `4401` en todos los clientes | Tickets caducados (30 s) o Auction recreado entre emitir y usar | Esperado tras recrear Auction: el cliente pide otro |
| `4429` | Más de 3 conexiones simultáneas del mismo usuario | Límite del contrato; el cliente debe reutilizar su conexión |
| El contenedor se reinicia por memoria | Posible fuga o carga mayor a la medida | Revisar `docker stats`; **apagar el interruptor** mientras se investiga |

## Escalar a más de una réplica

**No se ha probado ni está soportado hoy.** Qué pasa, de menor a mayor gravedad:

1. **Las señales sí llegarían a todas las réplicas.** Cada una abre su propia conexión `LISTEN`
   y PostgreSQL entrega cada aviso a todas. La difusión no se pierde.
2. **Los tickets NO se comparten.** Viven en la memoria del proceso: un ticket emitido por una
   réplica lo rechaza otra con `4401`. Con un balanceador sin afinidad, una parte de las
   conexiones fallaría de forma intermitente.
3. **Cada réplica añade una conexión de escucha** al `max_connections` del nodo `data`, que ya
   comparten todos los servicios (ADR-011).
4. **Los límites de 3 conexiones por usuario se cuentan por réplica**, no en total.

Antes de escalar hace falta un ADR que mueva el almacén de tickets a un lugar compartido (o
fije la afinidad de la conexión a la réplica que emitió el ticket), y volver a medir la memoria
y las conexiones.

## Lo que este runbook no cubre

- El **cliente de la Web** (TASK EN-034.4, #586): hasta que exista, encender el interruptor no
  tiene efecto visible para el jugador. Conviene encenderlo cuando la Web pueda consumirlo.
- Una **prueba de carga en AWS** ni el sitio público con TLS (ver la evidencia).
