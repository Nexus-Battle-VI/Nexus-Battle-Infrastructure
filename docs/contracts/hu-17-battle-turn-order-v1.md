# Contrato HU-17 — Inicio de batalla y orden de turnos (v1)

- **Estado:** contrato de diseño de la Task [HU-17.1 #405](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/405), previo a la implementación de [#406](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/406) (Combat) y [#407](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/407) (Web). Hasta que esos PR se integren en `develop`, **lo descrito aquí es diseño, no capacidad desplegada**.
- **Historia:** [HU-17 #26](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/26) · **RF-17** · [EPIC-06 #6](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/6) · Team Alfa.
- **Arquitectura aplicada, sin reabrirla:** [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md) (Combat única autoridad), [ADR-020](../adr/ADR-020-realtime-combat.md) (`Accepted`: WebSocket nativo, ticket de un solo uso, `seq`, `commandId`, `resume`) y [ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md) (aleatoriedad HU-24). **No hay ADR nuevo:** ninguna decisión arquitectónica nueva; lo que sigue son decisiones técnicas de aplicación de esos ADR.
- **Diagramas:** [secuencia](../diagrams/hu-17-sequence-battle-start.puml), [actividades](../diagrams/hu-17-activity-turn-order.puml) y [estados](../diagrams/hu-17-state-battle-room.puml).

## 1. Qué exige HU-17 (RF-17) y qué no

Requisitos explícitos de la Issue: la cola solo se genera con los participantes confirmados y con las validaciones previas superadas; la lista de héroes y equipos es definitiva; el equipo inicial se decide **aleatoriamente con el motor de HU-24**; los participantes se organizan en una **Queue** alternando equipos; en 1 contra 1 la cola tiene exactamente dos participantes y el seleccionado va primero; las estadísticas no influyen; el orden es **invariable** durante toda la batalla (sin nuevo sorteo por ronda); todos los clientes reciben la misma cola **antes de la primera acción**; se emite `battleStarted`; solo el participante en la posición activa puede actuar; al terminar bien su turno se avanza al siguiente.

**Fuera de alcance de HU-17** (no se implementa ni se anticipa): ataque y daño (HU-18), habilidades y épica (HU-19), resultado y fin de batalla (HU-21), chat (HU-13).

## 2. Transición sala → batalla

Auditado el dominio actual de Combat (`develop`): existe el agregado `BattleRoom` (estados `WAITING_FOR_PLAYERS`, `PREPARING`, `CANCELLED`); **no existe un agregado `Battle` aparte** y el comentario de `BattleRoomStatus` reserva `startBattle()` para HU-17. Por [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md) («la batalla es un único agregado … separar salas de motor partiría ese agregado en dos almacenes») **se extiende `BattleRoom`**, sin crear otra entidad ni otra colección.

| Estado de la sala | Evento | Estado resultante | Condición |
| --- | --- | --- | --- |
| `WAITING_FOR_PLAYERS` | último cupo ocupado (`join`) | `PREPARING` | ya existe (HU-15) |
| `PREPARING` | `start` (participante) | **`IN_BATTLE`** | roster completo; cada participante `HUMAN` supera de nuevo la elegibilidad precombate (HU-16); orden generado y persistido |
| `PREPARING` | `leave` | `WAITING_FOR_PLAYERS` | ya existe |
| `IN_BATTLE` | `start` repetido | `IN_BATTLE` | **idempotente**: devuelve el estado vigente, no genera otra cola ni otro `battleStarted` |
| `IN_BATTLE` | fin de turno válido (server-side) | `IN_BATTLE` | avanza la posición activa y emite `turnAdvanced` |
| `WAITING_FOR_PLAYERS` / `CANCELLED` | `start` | — | rechazado: `409` |
| `IN_BATTLE` | `cancel` / `join` / `leave` | — | rechazado: la sala ya no es cancelable ni admite ingreso (los errores de dominio existentes ya lo cubren por estado). El abandono en batalla es regla de HU-21 y no se define aquí |

`battleId` **es** el `roomId` (una sala produce como máximo una batalla): no se introduce un segundo identificador.

### Decisión técnica necesaria: quién y cómo dispara el inicio

La Issue no define el disparador. Se elige un comando HTTP explícito, **`POST /api/v1/combat/rooms/:roomId/start`**, que puede invocar **cualquier participante `HUMAN` de la sala** y que no admite cuerpo (ningún cliente elige quién inicia ni quién participa). Motivos y alternativas descartadas:

- **Iniciar automáticamente dentro de `join`** se descarta: acopla la transacción del ingreso con la revalidación de otros jugadores contra Player-Inventory (hasta seis llamadas internas) y deja una sala `PREPARING` sin camino de reintento si esa validación falla por un motivo transitorio.
- **Comando WebSocket `start`**: ADR-020 reserva el canal de tiempo real para comandos de juego (`attack`, `useSkill`, …); el ciclo de vida de la sala (crear, unirse, abandonar, cancelar) ya es HTTP y el inicio es de esa misma familia.
- El comando es **idempotente**, así que ambos clientes pueden invocarlo al ver `PREPARING` sin carrera ni doble batalla.

> Esta elección está **pendiente de ratificación del Product Owner**; no contradice ninguna regla de RF-17.

## 3. Superficie HTTP

Todas las rutas son autenticadas (JWT de Cognito) y **derivan la identidad del `sub` verificado**; ninguna acepta `playerId`, equipo inicial ni participantes en el cuerpo.

| Método | Ruta | Éxito | Errores |
| --- | --- | --- | --- |
| `POST` | `/api/v1/combat/realtime/tickets` (ADR-020) | `201` `{ "ticket": "<opaco>", "expiresInSeconds": 30 }` | `401` |
| `POST` | `/api/v1/combat/rooms/:roomId/start` | `200` sala (ver §4) | `400` (`roomId` no UUID v4), `401`, `403` (no es participante), `404`, `409` (sala no `PREPARING`/`IN_BATTLE` o conflicto de versión), `422` (`blockers[]` de elegibilidad, o sin héroe equipado), `503` (Player-Inventory o Account no respondieron) |
| `GET` | `/api/v1/combat/rooms/:roomId` | `200` sala (ver §4) | `400`, `401`, `403` (no es participante), `404` |

`GET /api/v1/combat/rooms/:roomId` existe porque `GET /rooms` solo lista salas `WAITING_FOR_PLAYERS` con cupo: en cuanto una sala pasa a `PREPARING` o `IN_BATTLE` el cliente perdía toda forma HTTP de leerla (limitación ya declarada por Web en HU-15.3).

### Validación precombate en el inicio

HU-16 valida al **unirse** y captura `heroLoadoutVersion`. El inicio **repite** la validación de cada participante `HUMAN` con los mismos puertos y la misma política (`assessPrecombatEligibility`), sin reimplementar equipamiento: se vuelve a leer el héroe equipado; debe existir (`PlayerWithoutEquippedHeroError`), ser el mismo `heroId`, cumplir la elegibilidad de la sala y conservar la `heroLoadoutVersion` capturada (si cambió, `HERO_LOADOUT_CHANGED`). Si **cualquiera** falla: no se crea cola, no se emite `battleStarted`, la sala sigue `PREPARING` y no se permite ninguna acción. Los participantes `AI` no tienen héroe equipado que validar.

## 4. Forma de la sala y de la batalla

`BattleRoomDto` (HU-14) **se amplía de forma aditiva** con `battle` y `lastSeq`; los clientes de HU-14/15 los ignoran.

```jsonc
{
  "id": "…", "mode": "PVP", "status": "IN_BATTLE",
  "teams": [ /* igual que HU-14/15 */ ],
  "reward": { "amount": 100 }, "createdBy": "…", "createdAt": "…", "version": 7,
  "lastSeq": 1,
  "battle": {
    "battleId": "<= roomId>",
    "startedAt": "2026-09-21T10:00:00.000Z",
    "turnOrder": [
      { "position": 0, "teamLabel": "B", "seat": 0, "kind": "HUMAN",
        "playerId": "…", "displayName": "…", "heroId": "…", "heroSubtype": "GUERRERO_ARMAS" },
      { "position": 1, "teamLabel": "A", "seat": 0, "kind": "HUMAN", "…": "…" }
    ],
    "turnsCompleted": 0,
    "round": 1,
    "currentTurn": { "position": 0, "teamLabel": "B", "seat": 0, "…": "…" }
  }
}
```

- `battle` es `null` mientras la sala no esté `IN_BATTLE`.
- `turnOrder` es la **cola inmutable**: una vez creada no cambia de contenido ni de orden. `position` es el índice 0-based.
- `seat` es el índice 0-based del participante dentro de su equipo en la sala (los participantes `AI` no tienen `playerId`; `seat` los distingue).
- `turnsCompleted` es el **único** contador de progreso; `round = floor(turnsCompleted / turnOrder.length) + 1` y `currentTurn.position = turnsCompleted mod turnOrder.length` **se derivan**, no se guardan por separado (una sola fuente de verdad).
- `heroSubtype` es una copia de **presentación** del subtipo canónico que publica Player-Inventory al iniciar, para que Web elija el modelo visual; no se copia inventario ni estadísticas. `null` para `AI`.
- `playerId` ya viaja hoy en `BattleRoomDto` (HU-15) y Web ya lo compara con su `sub`; no es un dato nuevo expuesto.
- **Nunca** viajan: semilla, estado de MT19937, valores aleatorios futuros, número de sorteos, inventario, JWT, tickets ni sus hashes.

## 5. Protocolo de tiempo real (aplicación de ADR-020)

Ruta: `wss://nexus.simuladorupbbga.app/api/v1/combat/realtime`. Caddy ya enruta `/api/v1/combat*` a `combat:3006` (comprobado en `compose/Caddyfile`); **no requiere cambios de infraestructura**.

**Autenticación.** El cliente obtiene un ticket por HTTP (§3), abre el socket **sin credenciales en la URL** y envía como primer mensaje `{"type":"auth","ticket":"…"}`. El ticket es opaco, de un solo uso, ligado al `sub` y caduca a los **30 s**; solo se retiene su hash. Sin ticket válido en **5 s**, o con un ticket usado, caducado o inexistente: cierre `4401`. El `sub` del ticket es la única identidad de la conexión. El antiguo mensaje `{"type":"auth","token":"<JWT>"}` de HU-15.2 **deja de aceptarse**: era la simplificación documentada que ADR-020 no aprobó.

**Mensajes del cliente** (máximo 16 KiB):

| Mensaje | Efecto |
| --- | --- |
| `{"type":"auth","ticket"}` | autentica; responde `{"type":"auth.ok"}` |
| `{"type":"subscribe","roomId"}` | lobby: recibe `battle-room.updated` de esa sala (comportamiento de HU-15.2, sin cambios) |
| `{"type":"resume","roomId","lastSeq"?}` | **solo participantes**: se suscribe a los eventos de batalla y recupera el estado |

Cualquier comando futuro llevará `commandId` (ADR-020). Combat **deduplica por `commandId`**: repetirlo devuelve el resultado ya calculado y no ejecuta dos veces. HU-17 no expone ningún comando de juego por WebSocket; el avance de turno lo invoca **el servidor** al terminar una acción válida (HU-18/19) y ya está protegido por `commandId` en el dominio.

**Mensajes del servidor:**

| Mensaje | Cuándo | A quién |
| --- | --- | --- |
| `auth.ok` | ticket válido | la conexión |
| `subscribe.ok` | suscripción de lobby aceptada | la conexión |
| `battle-room.updated` `{roomId,status,version}` | cambio de estado de la sala (HU-15.2) | suscritos a la sala |
| `snapshot` `{roomId,seq,status,battle}` | `resume` sin `lastSeq` válido | quien lo pidió |
| `battleStarted` `{seq,roomId,occurredAt,battle}` | tras **persistir** la batalla | participantes de la sala |
| `turnAdvanced` `{seq,roomId,occurredAt,completedPosition,battle}` | tras **persistir** el avance | participantes de la sala |
| `resume.ok` `{roomId,seq}` | fin de la recuperación | quien lo pidió |
| `command.rejected` `{commandId?,code}` | comando rechazado | **solo** a quien lo envió |

- **`seq`**: entero creciente **por sala**, comienza en 1 (`battleStarted` = 1). Cada evento de batalla lleva el suyo; el orden entre eventos es total.
- **`resume`**: si `lastSeq` está entre 1 y el último `seq`, se **reenvían en orden** los eventos posteriores de la bitácora persistida; si falta o es inválido, se envía un `snapshot` del estado visible completo. Termina con `resume.ok`. Un no participante recibe `command.rejected` con `NOT_A_PARTICIPANT` y **no** se suscribe.
- **Cliente:** aplica solo `seq` mayor que el último aplicado; un `seq` repetido o anterior se ignora; un salto (`seq` > último + 1) obliga a pedir `resume`. No reconstruye estado con mensajes inventados.
- **Latido:** el servidor envía un *ping* cada 25 s; una conexión sin *pong* se cierra (queda desconectada, no abandonada; el abandono es de HU-21).
- **Persistir antes de difundir:** validar → generar/actualizar → **persistir con bloqueo optimista** → difundir. Si la persistencia falla, no se difunde nada.
- **Códigos de cierre:** `4401` autenticación/ticket, `4400` mensaje mal formado.

## 6. Orden de turnos (Queue)

**Entrada:** los equipos `A` y `B` de la sala con su lista definitiva de participantes (`PREPARING` implica cupo completo). **No** se usan estadísticas, nivel, Poder, tipo de héroe ni equipamiento para ordenar.

**Algoritmo (dominio puro, aleatoriedad inyectada):**

1. Elegir el equipo que inicia con un entero uniforme en `{0,1}`.
2. Barajar cada equipo con Fisher-Yates usando enteros uniformes acotados (los «participantes» de un equipo son intercambiables; RF-17 exige que las decisiones aleatorias necesarias para construir la secuencia salgan de HU-24).
3. Intercalar: equipo inicial, otro equipo, equipo inicial… mientras queden participantes en ambos.
4. Si un equipo se agota antes (composiciones desiguales, p. ej. 1 humano contra 3 IA en `PVE`), los que restan del otro equipo **se añaden a continuación en su orden barajado**. *Decisión técnica pendiente de ratificación del PO*: RF-17 define la alternancia solo para equipos equilibrados.
5. Persistir la cola resultante. **No se vuelve a sortear jamás.**

**1 contra 1:** la cola tiene exactamente dos entradas; inicia quien resulte del sorteo del paso 1 y el rival va segundo.

**Invariantes** (verificadas por pruebas de dominio): lista no vacía; solo participantes de la sala confirmados; sin duplicados; tamaño = roster definitivo; alternancia entre equipos mientras ambos tengan integrantes; una única posición activa; el contenido de `turnOrder` no cambia; tras el último participante se vuelve al primero (`turnsCompleted mod n`); las rondas siguientes reutilizan exactamente la misma cola.

**Fin de turno.** `completeTurn(actor, commandId)` (dominio/aplicación, **no** expuesto como ruta pública): exige batalla `IN_BATTLE` y que `actor` sea el participante de la posición activa (o el servidor para un turno de `AI`); avanza `turnsCompleted` y registra `turnAdvanced`. Un `commandId` ya procesado devuelve el resultado anterior sin avanzar de nuevo. Web **nunca** decide `turno + 1`: solo pinta el `currentTurn` que recibe.

## 7. Uso de HU-24 sin sesgo y sin exponer nada

Ninguna decisión usa `Math.random`, `crypto`, `Date.now` ni otro generador: solo `RandomSequencePort.nextIndex()` (`1..8000`, uniforme por ADR-021). Para elegir uniformemente entre `n` opciones **no se usa el módulo ingenuo** (`8000` no es múltiplo de 3, 5 ni 6, lo que sesgaría): se aplica **muestreo por rechazo**: con `v = índice − 1`, se acepta si `v < 8000 − (8000 mod n)` y el resultado es `v mod n`; en otro caso se descarta y se toma otro índice (con tope de intentos). Con `n = 2` nunca se rechaza. Se documentan los sorteos: 1 para el equipo inicial y, por equipo de `k` integrantes, `k − 1` más los rechazos.

> **Política de semilla (pendiente de decisión, heredada de ADR-021):** el código de Combat no tenía política de semilla por batalla. HU-17 es el primer consumidor real y necesita una secuencia. Se decide **la mínima compatible con HU-26**: una secuencia con estado **de proceso**, creada al arrancar con la semilla validada (por defecto `3.000.000`, configurable con `COMBAT_RANDOM_SEED`, entero sin signo de 32 bits) y consumida por todas las batallas, de modo que cada sorteo **avanza** el estado. No se usa una semilla constante por batalla (produciría siempre el mismo equipo inicial). **Limitación declarada:** tras reiniciar Combat la secuencia vuelve a empezar; persistir la posición del cursor, o una semilla por batalla, requiere decisión del PO y es la política runtime que ADR-021 ya marcaba como pendiente.

## 8. Persistencia

`BattleRoom` se amplía en el mismo documento de `battle-rooms` (una sola escritura atómica con bloqueo optimista por `version`): `status` admite `IN_BATTLE`; `battle` (orden, `startedAt`, `turnsCompleted`); `events` (bitácora de eventos de batalla con su `seq`); `handledCommands` (`commandId` → `seq`, para deduplicar). Se añade una migración **aditiva** del validador `$jsonSchema`. Guardar la bitácora **en el propio documento** hace que «persistir la batalla» y «persistir el evento» sean la misma operación atómica: ningún cliente puede ver un evento cuyo estado no exista.

## 9. Seguridad y minimización

- El cliente no elige inicio, participantes, equipo inicial ni turno; todo lo decide Combat.
- `JWT` solo en HTTP; nunca en la URL del socket. Tickets de un solo uso, 30 s, solo hash retenido.
- Un no participante no recibe `battleStarted` ni `turnAdvanced` y no puede hacer `resume`.
- No se registra JWT, ticket, semilla ni carga completa de mensajes; sí `roomId`, tipo de evento, `seq`, `commandId` y resultado.
- Combat sigue en **una sola réplica** (ADR-020): las suscripciones viven en memoria del proceso.

## 10. Preguntas y pendientes

| Punto | Estado |
| --- | --- |
| Disparador del inicio (`POST …/start` por cualquier participante) | decisión técnica **pendiente de ratificar** por el PO |
| Alternancia con equipos desiguales | decisión técnica **pendiente de ratificar** por el PO |
| Política de semilla por batalla / persistencia del cursor | **pendiente** (ADR-021); HU-17 usa la secuencia de proceso descrita en §7 |
| Abandono o desconexión durante la batalla | fuera de HU-17 (HU-21) |
| Bloqueo del equipamiento durante la batalla | HU-29 |
| Ataque, habilidades, daño, Poder, fin de batalla | HU-18, HU-19, HU-21 |
