# ADR-020 — Tiempo real para Jugar Online

- **Estado:** **Accepted** el 2026-09-16 — validado por Product Owners y Scrum Masters junto con ADR-019
- **Fecha:** 2026-09-16
- **Decide:** Arquitectura, con validación de Combat y Web
- **Relacionado:** [ADR-004](ADR-004-identity-directory.md), [ADR-006](ADR-006-messaging.md), [ADR-007](ADR-007-aws-cost-optimized-platform.md), [ADR-010](ADR-010-reverse-proxy.md), [ADR-019](ADR-019-sprint-2-bounded-contexts.md), [EPIC-06 #6](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/6), [HU-13 #22](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/22), [HU-15 #24](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/24), [HU-17 #26](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/26)

## Contexto

Jugar Online exige que varios jugadores vean el mismo estado de batalla y el
mismo chat sin recargar (EPIC-06: «el estado de batalla debe mantenerse
consistente entre los participantes»; HU-13: «distribución de mensajes en tiempo
real»). La épica nombra dos riesgos que este ADR debe atender por diseño y no
por disciplina: **divergencia del estado entre clientes** y **pérdida de
mensajes o latencia**.

Restricciones que ya están decididas y no se reabren aquí:

- Sin API Gateway WebSocket ni Lambda, AppSync o ALB ([ADR-007](ADR-007-aws-cost-optimized-platform.md)).
- Todo el tráfico entra por Caddy ([ADR-010](ADR-010-reverse-proxy.md)), que ya
  termina TLS para `nexus.simuladorupbbga.app`.
- La identidad es un testimonio de Cognito verificado en el servicio ([ADR-004](ADR-004-identity-directory.md)).
- Un solo contexto ejecuta el combate: Combat ([ADR-019](ADR-019-sprint-2-bounded-contexts.md)).

## Decisión

### Transporte: WebSocket servido por Combat, a través de Caddy

- **WebSocket (RFC 6455)** en `wss://nexus.simuladorupbbga.app/api/v1/combat/realtime`.
- En Combat, `@nestjs/websockets` con el adaptador `@nestjs/platform-ws` (librería
  `ws`), en la misma versión menor de NestJS que el resto del servicio.
- Caddy lo enruta con un `handle /api/v1/combat*` hacia `combat:3006`.
  `reverse_proxy` de Caddy v2 atiende la actualización a WebSocket sin
  configuración adicional.
- **Coste AWS: cero.** No hay recurso nuevo; el puerto 443 ya está abierto.

Se descarta Socket.IO: añade un protocolo propio y un modo de sondeo largo que
aquí no hace falta, y obliga al cliente a usar su librería. Un WebSocket estándar
lo consume el navegador sin dependencias.

### Autenticación: ticket de un solo uso, nunca el JWT en la URL

Un navegador no puede fijar la cabecera `Authorization` al abrir un WebSocket, y
poner el testimonio en la consulta lo dejaría en los registros del proxy y del
servicio.

1. El cliente pide `POST /api/v1/combat/realtime/tickets` con `Authorization: Bearer <JWT>`.
2. Combat verifica el testimonio como en cualquier ruta y devuelve un **ticket
   opaco** aleatorio, ligado al `sub`, de **un solo uso** y con caducidad de
   **30 segundos**. Solo se guarda su hash.
3. El cliente abre el WebSocket **sin credenciales en la URL** y envía como
   primer mensaje `{"type":"auth","ticket":"..."}`.
4. Sin ticket válido en 5 segundos, el servidor cierra con código `4401`. Un
   ticket ya usado o caducado cierra igual.

El `sub` del ticket es la única identidad de la conexión. Ningún mensaje
posterior puede declarar otro jugador.

### Autoridad: el servidor decide, el cliente solicita

- El cliente **no envía estado**, envía **comandos** (`join`, `ready`,
  `attack`, `useSkill`, `chat`), cada uno con un `commandId` generado en el
  cliente. Repetir un `commandId` devuelve el resultado ya calculado.
- Combat valida el comando contra el agregado —turno vigente, participante,
  Poder, objetivo aliado—, ejecuta el motor, **persiste la nueva versión de la
  batalla** con bloqueo optimista y **solo después** difunde el evento.
- Cada evento de una sala lleva un número de secuencia `seq` creciente.
- Un comando rechazado responde solo a quien lo envió, con un código estable, y
  no modifica nada. Ninguna regla de combate se evalúa en el cliente.

### Reconexión y pérdida de mensajes

- Al autenticarse de nuevo, el cliente envía `{"type":"resume","roomId","lastSeq"}`.
- Si los eventos posteriores siguen en la bitácora persistida, se reenvían en
  orden; si no, se envía una **instantánea** completa del estado visible.
- Latido del servidor cada 25 segundos; una conexión sin respuesta se cierra
  y su participante queda como desconectado, no como abandonado. Cuándo una
  desconexión se convierte en abandono es una regla de producto (HU-21), no de
  transporte.
- **Un reinicio de Caddy o de Combat cierra todas las conexiones.** No se oculta:
  la reconexión es obligatoria en el cliente, y el estado sobrevive porque vive
  en MongoDB, no en la memoria del proceso.

### Qué viaja y qué no

- Nunca viajan la semilla, el estado del generador ni resultados aleatorios
  futuros ([ADR-019](ADR-019-sprint-2-bounded-contexts.md)).
- Cada cliente recibe solo el estado visible para su participante.
- Tamaño máximo de mensaje entrante: 16 KiB; límite de comandos por conexión
  configurable. El límite de longitud y frecuencia del **chat** lo fija HU-13.

### Alcance

- **Sprint 2:** salas, lobby, turnos y chat de Jugar Online.
- **Fuera:** Auction y Missions consultan por HTTP. Si una Historia de Usuario
  exige empuje en tiempo real para pujas, se reutiliza este mismo esquema con
  un ADR que lo extienda.

## Consecuencias

**Lo que se gana**

- Una sola autoridad del estado: dos clientes no pueden divergir porque ninguno
  calcula el resultado.
- Reconexión sin pérdida de eventos gracias a `seq` y a la bitácora persistida.
- Ningún testimonio en URL ni en registros.
- Coste AWS nulo.

**Lo que cuesta**

- **Combat queda en una sola réplica.** Las suscripciones viven en memoria del
  proceso; con dos réplicas un evento no llegaría a quien esté conectado a la
  otra. Escalar exigiría un bus de difusión y un ADR nuevo.
- Persistir antes de difundir añade la latencia de una escritura por acción de
  turno. Es aceptable en un juego por turnos y es lo que evita difundir un
  estado que luego no existe.
- El cliente de Web debe implementar reconexión, reenvío por `seq` y
  deduplicación por `commandId`.

## Alternativas consideradas

| Alternativa | Por qué se descartó |
| --- | --- |
| API Gateway WebSocket | Exige Lambda o integración HTTP con estado de conexión externo; Lambda está prohibido por ADR-007 |
| Socket.IO | Protocolo y librería propios en ambos extremos sin necesidad real |
| Server-Sent Events + HTTP | Válido para difundir, pero los comandos irían por otra conexión y el orden entre ambos canales dejaría de estar garantizado |
| Sondeo periódico | Latencia visible en turnos y chat, y carga constante sin actividad |
| JWT en la cadena de consulta | Queda en registros de Caddy y del servicio |

## Evidencia de aceptación

- Validado por Product Owners y Scrum Masters el 2026-09-16 e integrado en
  [Infrastructure#101](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/101).
- **Aceptar no es implementar:** Combat todavía no tiene WebSocket. Se añade con
  la primera Historia de Usuario que lo necesite (HU-13, HU-15 o HU-17).
- HU-13 debe fijar retención y moderación del chat antes de persistirlo más allá
  de la sala.
