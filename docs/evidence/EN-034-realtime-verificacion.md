# EN-034 — Evidencia de verificación del realtime de Subasta (servidor)

- **Enabler:** [Nexus-Battle-VI/Nexus-Battle-Management#523](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/523)
- **Task:** [EN-034.5 #587](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/587)
- **Fecha de la verificación:** 2026-10-07
- **Entorno:** Docker Desktop en Windows (máquina de desarrollo), **no** el despliegue de AWS. Imagen construida desde `Nexus-Battle-Auction` en el commit `0a954f1` (PR #99), PostgreSQL 17, Caddy 2 con el `compose/Caddyfile` real de este repositorio.
- **Método:** ejecutado contra contenedores reales con el límite de memoria de producción (`mem_limit: 160m`, `compose/nodes/app.yml`). Los scripts están en `scripts/realtime/` de `Nexus-Battle-Auction` (PR #101) y se reproducen con su `README.md`.
- **Alcance:** esta evidencia cubre **solo el lado del servidor**. El cliente de la Web (TASK EN-034.4, #586) no existe todavía porque el módulo de Subasta de la Web (HU-87, HU-88) no está implementado, así que los criterios que dependen de él **no están verificados**.

## Criterios de aceptación de EN-034

| Criterio | Servidor | Web | Cómo se comprobó |
| --- | --- | --- | --- |
| CA-01 — Actualización de puja | **Cubierto** | Pendiente (#586) | Prueba de extremo a extremo de Auction#99: dos sesiones observan la misma subasta y reciben la puja con `currentBidCredits` y `bidCount`, sin acción manual |
| CA-02 — Aislamiento por subasta | **Cubierto** | Pendiente (#586) | Eventos simultáneos de dos subastas solo llegan a quien observa cada una (Auction#99); 12 pujas y dos subastas entrelazadas conservan su propia secuencia (Auction#100) |
| CA-03 — Reconexión | **Cubierto en servidor** | Pendiente (#586) | La caída de la conexión de escucha con PostgreSQL emite `resync` y las señales se reanudan (Auction#99); cada conexión nueva exige ticket nuevo. El refetch al reconectar es del cliente |
| CA-04 — Cambio de estado | **Cubierto en servidor** | Pendiente (#586) | `BOUGHT_NOW`, `SETTLED` y `CANCELLED` por los caminos reales del repositorio, con la revisión siguiente; una puja posterior a la cancelación nunca se acepta (Auction#100). Que la vista deje de ofrecer acciones es del cliente |
| CA-05 — Caché consistente | No aplica | **Pendiente (#586)** | Depende por completo de las claves de React Query de Marketplace y Detalle, que aún no existen |
| CA-06 — Autoridad del backend | **Cubierto en servidor** | Pendiente (#586) | La señal solo invalida: no lleva datos personales ni estado autoritativo; `revision` estrictamente creciente sin huecos bajo concurrencia (Auction#100). Descartar una señal tardía o duplicada por `revision` es del cliente |

## Medición 1 — Conexión larga a través de Caddy

Pendiente declarada en [auction-realtime-v1.md](../contracts/auction-realtime-v1.md) §12: comprobar que una conexión de más de 60 s sobrevive a Caddy.

Tres conexiones autenticadas por ticket, cada una suscrita a `auctions/{id}` y `auctions`, mantenidas **75 s sin tráfico de aplicación** a través de Caddy (`:8080`, sitio interno).

| Comprobación | Resultado |
| --- | --- |
| Conexiones abiertas a los 15, 30, 45, 60 y 75 s | 3/3 en todos los puntos |
| Latidos del servidor recibidos por conexión | 3 (cada 25 s) |
| Señal tras los 75 s de espera (inserción de una puja) | Llegó a las 3 conexiones en **150 ms**, `BID_ACCEPTED`, revisión 1 |
| Ráfaga de 300 pujas | Las 301 señales llegaron a la sesión observada, sin pérdidas |

**Conclusión:** `reverse_proxy` de Caddy mantiene la conexión con el latido de 25 s y no corta conexiones inactivas dentro de este margen, tal como se asumió en ADR-024 (D-4).

## Medición 2 — Memoria bajo el límite de 160 MiB

### Auction completo (imagen real, `AUTH_MODE=disabled`)

| Momento | Memoria (`docker stats`) |
| --- | --- |
| En reposo | 49,8 MiB |
| 3 conexiones, 2 suscripciones cada una | 50,5 MiB |
| Tras una ráfaga de 300 señales | 53,0 MiB |

Con `AUTH_MODE=disabled` todas las conexiones comparten el mismo usuario y el límite de 3 por usuario impide abrir más, por eso hay una segunda medición.

### Carga de la demostración: 30 usuarios × 3 conexiones × 20 suscripciones

El gateway, el hub y los tickets **reales** de la imagen sobre un servidor propio (`load-server.cjs`), con 30 usuarios distintos, en un contenedor de 160 MiB.

| Momento | RSS del proceso | Heap usado |
| --- | --- | --- |
| Antes de conectar | 78,9 MiB | 11,4 MiB |
| 90 conexiones, 20 suscripciones cada una (1800 suscripciones) | 81,4 MiB | 11,0 MiB |
| Tras difundir 1000 señales (**180 000 mensajes** entregados) | 82,5 MiB | 11,5 MiB |
| Tras cerrar todas las conexiones | 82,8 MiB | 11,8 MiB |

- Conexiones caídas durante la prueba: **0**.
- `OOMKilled`: **false**.

**Conclusión:** el costo de las conexiones es de unos **3,6 MiB** para el caso de demostración (90 conexiones, 1800 suscripciones, 180 000 mensajes). Sumado a los ~50 MiB del servicio completo en reposo, queda en torno a **54 MiB de los 160 MiB**, con holgura amplia. Los límites de 20 suscripciones y 3 conexiones por usuario acotan el peor caso por usuario.

## Limitaciones de esta verificación

- **No es el despliegue de AWS.** Docker Desktop sobre Windows mide con el mismo límite de cgroup, pero la EC2 y su red son distintas.
- **Caddy sin TLS.** Se probó el sitio interno `:8080`. El sitio público (`tls internal` o Let's Encrypt, mismo bloque `rutas`) no se ejercitó: WebSocket sobre TLS atraviesa el mismo `reverse_proxy`, pero no está medido.
- **Dos mediciones de memoria distintas.** `docker stats` (cgroup, Auction completo) y RSS del proceso (servidor de carga). El RSS es la cifra más conservadora de las dos; no se sumaron en una sola corrida, por eso la conclusión de ~54 MiB es una estimación.
- **Memoria en reposo del servicio completo** se midió con 3 conexiones; el incremento por conexión se midió aparte, con 90.
- **Un solo nodo.** Las limitaciones de réplicas de [ADR-024](../adr/ADR-024-realtime-auction.md) y [auction-realtime-v1.md](../contracts/auction-realtime-v1.md) §12 (tickets en memoria) siguen vigentes.

## Pendiente para cerrar EN-034

1. **Web (TASK EN-034.4, #586):** cliente, reconexión, descarte por `revision` e invalidación de caché. Desbloquea CA-05 y la parte de cliente de CA-01 a CA-06. Depende de HU-87 y HU-88.
2. **Prueba con dos sesiones reales en la Web** y evidencia de caché con filtros y detalle.
3. **Verificación en el despliegue** (AWS), con el sitio público con TLS, cuando se active `AUCTION_REALTIME_ENABLED`.
