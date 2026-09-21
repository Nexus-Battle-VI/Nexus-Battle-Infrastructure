# Contrato HU-13 — Chat del lobby y de las salas de batalla (v1)

- **Estado:** contrato del protocolo **implementado en Combat** por HU-13 ([Combat #27](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/27), abierto, sin integrar). Hasta que ese PR esté integrado en `develop` y desplegado, **lo descrito aquí es diseño, no capacidad desplegada**: `main` de Combat va por detrás de `develop` y el chat exige la migración `006` (`npm run migrate`; la `005` es la de HU-17). El trabajo se integró con HU-17 el 2026-09-21, y este contrato se alineó con lo que HU-17 implementó (ticket de un solo uso, latido, estado `IN_BATTLE`).
- **Historia:** [HU-13 #22](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/22) · **RF-13** · [EPIC-06 #6](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/6) · Team Alfa.
- **Arquitectura aplicada, sin reabrirla:** [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md) (Combat posee los mensajes de chat), [ADR-020](../adr/ADR-020-realtime-combat.md) (`Accepted`: WebSocket nativo, `commandId`, `seq`, mensajes entrantes de hasta 16 KiB, una sola réplica). **No hay ADR nuevo.** Detalle de implementación, trazabilidad a pruebas y evidencia: `docs/hu-13-chat.md` en Nexus-Battle-Combat.

## 1. Contextos

El documento oficial (§7.6) pide un chat «en las salas de batalla, así como en la vista general». Hay exactamente dos contextos, y cada mensaje pertenece a uno solo:

| Canal | `channel` | Quién lo lee y escribe |
| --- | --- | --- |
| **Lobby** (la vista general de Jugar Online) | `"lobby"` | Cualquier identidad verificada suscrita al lobby. Un único canal global. |
| **Sala** | `"room"` + `roomId` | Solo los participantes **humanos** de esa sala, y solo mientras su estado admita chat (`WAITING_FOR_PLAYERS`, `PREPARING`, `IN_BATTLE`). Una sala `CANCELLED` tiene el chat cerrado. |

Un mensaje **nunca** llega a un canal distinto del suyo. Quien deja de tener acceso (abandona la sala o se cancela) recibe `chat.unsubscribed` y no vuelve a recibir mensajes de ese canal.

**El chat de la sala sigue abierto durante la batalla (`IN_BATTLE`).** Es una decisión técnica derivada de «sala activa» (RF-13): ningún documento trata el chat de sala en batalla, y el documento oficial (§7.6) habla de «chatear en medio de uno» —de un juego—. **El PO debe confirmarla.** Cuando HU-21 añada el estado de batalla terminada decidirá si su chat se cierra: la tabla de estados de Combat es exhaustiva y no compila hasta que se decide.

## 2. Transporte y autenticación

`wss://nexus.simuladorupbbga.app/api/v1/combat/realtime` (ADR-020). Caddy ya enruta `/api/v1/combat*` a `combat:3006`: **no requiere cambios de infraestructura**.

La autenticación es la de HU-17 (ADR-020): el cliente pide un **ticket de un solo uso** por HTTP (`POST /api/v1/combat/realtime/tickets` con su JWT; responde `{ticket, expiresInSeconds: 30}`) y lo envía como **primer mensaje** del socket, `{"type":"auth","ticket":"…"}`; el servidor responde `{"type":"auth.ok"}`. El JWT no viaja por el socket ni por la URL, y el ticket no lleva credenciales. Sin ticket válido en 5 s, o con uno usado, caducado o desconocido, se cierra con `4401`. El chat solo usa el `sub` al que estaba ligado el ticket. **Ningún mensaje puede declarar otro jugador.**

Los comandos de chat de una conexión se atienden **de uno en uno y en el orden en que llegan**: un cliente puede enviar `chat.subscribe` y `chat.send` seguidos y el segundo verá la suscripción del primero (`chat.subscribe` es asíncrono: lee la sala y el historial). La cola es solo de chat; `auth`, `subscribe` y `resume` de HU-17 no pasan por ella. Un `chat.*` antes de autenticar cierra con `4401`.

## 3. Mensajes

### Cliente → servidor

| Mensaje | Efecto |
| --- | --- |
| `{"type":"chat.subscribe","channel":"lobby","lastSeq"?}` | Suscribe al lobby. |
| `{"type":"chat.subscribe","channel":"room","roomId","lastSeq"?}` | Suscribe a una sala (participante humano, sala activa). |
| `{"type":"chat.send","channel","roomId"?,"commandId","text"}` | Envía un mensaje **al canal al que la conexión está suscrita**. `commandId` es un UUID generado por el cliente. |
| `{"type":"chat.unsubscribe","channel","roomId"?}` | Deja de recibir ese canal. |

`lastSeq` es un entero ≥ 0; `roomId` un UUID v4. Un `roomId` con `channel:"lobby"` es un comando mal formado (`INVALID_COMMAND`), no se ignora.

### Servidor → cliente

| Mensaje | A quién |
| --- | --- |
| `chat.subscribed {channel, roomId?, upTo, truncated, messages[]}` | quien se suscribió |
| `chat.message {messageId, channel, roomId?, seq, commandId, sender:{displayName}, text, sentAt}` | **todos los suscritos al canal, remitente incluido** |
| `chat.accepted {commandId, seq, messageId, duplicate}` | solo el remitente |
| `chat.unsubscribed {channel, roomId?, reason}` | quien lo pidió (`REQUESTED`) o el expulsado (`NOT_A_PARTICIPANT`, `ROOM_NOT_ACTIVE`) |
| `command.rejected {command, commandId?, code, retryAfterMs?, maxLength?}` | solo quien envió el comando |

`sentAt` es la hora **del servidor** (ISO 8601). `chat.message` **no incluye el `sub` del remitente**: solo su nombre visible. Incluye `commandId` (un UUID que generó el propio cliente) para que el remitente reconcilie su mensaje optimista.

Ejemplo (lobby):

```jsonc
// C → S
{ "type": "chat.subscribe", "channel": "lobby" }
// S → C
{ "type": "chat.subscribed", "channel": "lobby", "upTo": 7, "truncated": false,
  "messages": [ { "messageId": "…", "channel": "lobby", "seq": 7, "commandId": "…",
                  "sender": { "displayName": "Ana" }, "text": "¿quién juega?", "sentAt": "2026-09-20T12:00:00.000Z" } ] }
// C → S
{ "type": "chat.send", "channel": "lobby", "commandId": "9c1b…", "text": "yo" }
// S → todos los suscritos
{ "type": "chat.message", "messageId": "…", "channel": "lobby", "seq": 8, "commandId": "9c1b…",
  "sender": { "displayName": "Beto" }, "text": "yo", "sentAt": "…" }
// S → solo el remitente
{ "type": "chat.accepted", "commandId": "9c1b…", "seq": 8, "messageId": "…", "duplicate": false }
```

### Códigos de rechazo (`code`)

`INVALID_COMMAND`, `EMPTY_MESSAGE`, `MESSAGE_TOO_LONG` (+`maxLength`), `INVALID_CHARACTERS`, `RATE_LIMITED` (+`retryAfterMs`), `NOT_SUBSCRIBED`, `ROOM_NOT_FOUND`, `ROOM_NOT_ACTIVE`, `NOT_A_PARTICIPANT`, `COMMAND_ID_REUSED`, `ACCOUNT_PROFILE_NOT_FOUND`, `CHAT_UNAVAILABLE`. El código es el contrato: el texto de los errores internos no viaja.

Cierres del socket: `4401` (no autenticado o ticket inválido), `4400` (mensaje mal formado o tipo desconocido) y `1009` si un mensaje entrante supera **16 KiB** (ADR-020) —los tres ya existían—; y los que añade el chat: `1008` si una conexión acumula más de **64 comandos de chat** esperando su turno, y `1013` si un destinatario es un consumidor lento (recupera lo perdido con `lastSeq`).

## 4. Garantías y semántica del cliente

- **Procesado una sola vez.** Combat deduplica por (`sub`, `commandId`). Repetir un comando devuelve `chat.accepted` con el **mismo** `seq` y `duplicate: true`, y **no se difunde otra vez**. Un cliente que no recibió el `chat.accepted` (p. ej. se cayó la conexión) puede reenviar el mismo `commandId` con seguridad. Reutilizar un `commandId` en otro canal es `COMMAND_ID_REUSED`.
- **Persistir antes de difundir.** `chat.message` sale solo cuando el mensaje está persistido; si la persistencia falla no se difunde nada y el remitente recibe `CHAT_UNAVAILABLE`.
- **Orden.** `seq` es un entero creciente **por canal**, independiente del `seq` de eventos de batalla de HU-17. La persistencia y la difusión de un canal son secuenciales: el orden de `seq` es el orden de entrega. Los mensajes de un canal llegan en orden de `seq`.
- **Cliente:** aplica solo `seq` mayor que el último aplicado; uno repetido o anterior se ignora. Un **salto** (`seq` mayor que el último + 1) puede ser un hueco inocuo o una pérdida: no se aplica ese mensaje y se vuelve a enviar `chat.subscribe` con el último `seq` aplicado; la respuesta trae lo que exista y `upTo` cierra la duda.
- **Recuperación.** Al reconectar, `chat.subscribe` con `lastSeq`. La respuesta trae los mensajes retenidos con `seq` mayor y `upTo`, el último `seq` asignado en el canal: **el cliente está al día hasta `upTo`**, y un `seq` ≤ `upTo` que no llegó **no existe** (expiró, o su escritura falló tras reservar el número: puede haber huecos). `truncated: true` declara que había más mensajes que los que caben en el historial.
- **Mensajes pendientes.** El cliente que reenvía tras reconectar sus comandos sin `chat.accepted` (mismo `commandId`) obtiene entrega sin duplicados.
- **Latido.** El servidor envía un `ping` cada 25 s y cierra la conexión que no responde con `pong` antes del siguiente (ADR-020).

## 5. Límites y decisiones de producto

ADR-020 delega en HU-13 la longitud y la frecuencia; la Historia no da cifras. **Decididas por el PO por chat** (transmitido por quien tiene la Historia asignada; **no consta por escrito en el issue**):

| Parámetro | Valor | Configuración en Combat |
| --- | --- | --- |
| Longitud máxima del texto | 500 puntos de código Unicode (un emoji cuenta uno) tras recortar espacios | `CHAT_MAX_MESSAGE_LENGTH` |
| Frecuencia | 5 mensajes cada 10 s **por remitente y canal** (ventana deslizante) | `CHAT_RATE_LIMIT_MESSAGES`, `CHAT_RATE_LIMIT_WINDOW_MS` |
| Lobby | Un único canal global | — |
| Moderación | Fuera de HU-13 (el documento §7.3.3 habla de comentarios, no del chat de juego) | — |

El texto es de una línea: los caracteres de control (incluido el salto de línea) y los sustitutos sueltos se rechazan; un mensaje sin ningún carácter visible está vacío. **Web debe pintar el texto como texto, nunca como HTML**: no se escapa en el servidor.

**Cifras y decisiones sin ninguna fuente, elegidas por quien implementó — el PO debe fijarlas o confirmarlas:** retención de **7 días** (`CHAT_RETENTION_HOURS=168`); historial de **50** mensajes al suscribirse (`CHAT_HISTORY_LIMIT`); chat de sala abierto también en `IN_BATTLE` (§1).

## 6. Persistencia y retención

Combat guarda los mensajes (colecciones `chat-messages` y `chat-channels`, migración aditiva `006`; `battle-rooms` no se toca). Cada mensaje caduca a los `CHAT_RETENTION_HOURS` (índice TTL). **Persistir mensajes asociados a un `sub` crea una categoría de dato que [EN-011](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/197) no clasificó**: su pendiente P2 pregunta si el chat entra en la exportación y en la eliminación de cuenta (HU-43). HU-13 **no lo resuelve**; decisión del PO pendiente.

## 7. Integración con HU-17 (Infrastructure #116, Combat #26)

HU-17 llegó a `develop` antes que el chat. Lo que este contrato declaraba como solape quedó así:

| Punto | Resolución |
| --- | --- |
| Autenticación | Es la de HU-17: ticket de un solo uso (§2). El chat solo usa el `sub` del ticket. |
| `seq` | Por canal, propio del chat; el de HU-17 es por sala y de eventos de batalla. |
| Suscripción | `chat.subscribe` / `chat.unsubscribe` frente a `subscribe` (`battle-room.updated`) y `resume` (batalla): **no se solapan**. |
| Latido | **El de HU-17** (por conexión). Se retiró el que había implementado HU-13: hay **una** implementación. |
| Gateway | El chat es un manejador dentro de `BattleRoomRealtimeGateway` (una ruta, un gateway); HU-18 y HU-19 añadirán sus comandos por la misma vía. |
| Estados de sala | HU-17 añadió `IN_BATTLE`; el chat de sala queda abierto en él (§1). |
| Migraciones | La de HU-17 es `005-battle-rooms-battle-state`; la del chat es `006-chat-messages`. |

## 8. Seguridad y minimización

Identidad = `sub` del ticket (emitido tras verificar el JWT); el cliente no elige remitente, sala ni nombre. El nombre visible sale del snapshot de la sala o de Account. El `sub` no viaja a otros clientes. El texto no se escribe en los logs.

## 9. Dos defectos de HU-15.2 hallados al empezar

Ambos dejaban sin funcionar todo lo que viaja por el WebSocket. Los destapó la primera prueba con un socket real. **No se probaron contra un Combat desplegado ni en navegador.**

1. El gateway se registraba con `useFactory` y `@nestjs/websockets` ignora los gateways de fábrica: `/api/v1/combat/realtime` respondía **404** al *upgrade*. HU-17 lo corrigió por su cuenta en Combat #26 (proveedor de clase con `@Inject`).
2. Con la autenticación por JWT, `auth` y `subscribe` enviados seguidos cerraban con `4401`: `subscribe` se comprobaba antes de que terminara la verificación asíncrona del token. Con el ticket, consumirlo es **síncrono** y el problema desaparece; el orden que sigue importando es el de los comandos de chat entre sí (§2).

## 10. Pendientes

Una sola réplica de Combat (suscripciones, cerrojo y limitador en memoria: ADR-020); moderación y reportes; retención y EN-011 P2; no está desplegado.
