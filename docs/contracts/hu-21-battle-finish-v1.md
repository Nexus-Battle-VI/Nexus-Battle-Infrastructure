# Contrato HU-21 — Finalización de batalla (v1)

- **Estado:** diseño de la Task [#417](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/417). Lo que dice «implementado» solo lo está cuando lo integran las Tasks [#418](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/418) (Combat) y [#419](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/419) (Web); la validación integrada es la Task [#420](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/420). Hasta entonces todo lo de este documento es **diseño**.
- **Historia:** [HU-21 #65](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/65) · **RF-21** · [EPIC-06 #6](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/6) · Team Alfa · módulo Jugar Online / Combat.
- **Bloqueada por:** HU-17 (#26), HU-18 (#62), HU-19 (#63) y HU-20 (#64), todas cerradas (la épica de HU-19 sigue bloqueada por HU-31 y **no** afecta a esta HU).
- **Consumida por (sin implementarse aquí):** HU-22 (#69, cofre), HU-23 (#70, apuesta), HU-30 (#77, caída de ítems), HU-29 (#76, liberación del bloqueo de equipamiento) y HU-09 (#18, experiencia por victoria).
- **Arquitectura aplicada, sin reabrirla:** [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md) (Combat única autoridad), [ADR-020](../adr/ADR-020-realtime-combat.md) (`Accepted`: comandos con `commandId`, `seq`, persistir antes de difundir, y **«cuándo una desconexión se convierte en abandono es una regla de producto (HU-21)»**) y [ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md) (no se usa: la finalización no sortea).
- **Contratos de los que parte:** [HU-17](hu-17-battle-turn-order-v1.md) (cola, `seq`, `resume`, latido), [HU-18](hu-18-basic-attack-v1.md) (Vida, `attack`), [HU-19](hu-19-skills-v1.md) (Poder, `useSkill`) y [HU-13](hu-13-chat-v1.md) (chat de sala).
- **Diagramas:** [estados](../diagrams/hu-21-state-battle-lifecycle.puml), [secuencia](../diagrams/hu-21-sequence-finish.puml), [actividades: condiciones de cierre](../diagrams/hu-21-activity-finish-conditions.puml) y [actividades: acción letal](../diagrams/hu-21-activity-lethal-action.puml).

## 1. Qué exige la HU y qué no

**Requisito explícito (RF-21, Issue #65 y Tasks #417–#420):**

- la batalla finaliza cuando ocurra **una** de tres causas: eliminación de todos los héroes de un equipo, desconexión de un jugador o vencimiento del temporizador global de **seis (6) minutos**;
- cada turno dispone además de un temporizador de **30 segundos**;
- si finaliza por tiempo, el ganador es el equipo con **mayor porcentaje de vida restante**;
- el sistema declara **un único resultado válido** antes de distribuir recompensas;
- al finalizar se **liberan los recursos** de la instancia de batalla y se habilitan las integraciones de recompensa (créditos y posibles caídas), **sin implementar** HU-22, HU-23 ni HU-30 aquí;
- los temporizadores son **del servidor**; Web no es autoridad (Task #417, #419).

**Fuente oficial («Proyecto Integrador II»):** §6.1.3 «la partida concluye cuando únicamente un héroe o equipo permanece activo en el campo de batalla»; §7.6 «al final de cada partida, el jugador ganador recibe dos (2) créditos si la batalla es uno contra uno o cuatro (4) si es grupal, los demás jugadores un (1) crédito por participar» y «el inicio y el final de la partida debe presentar una vista de alto impacto». El documento **no** define temporizadores, desconexión ni desempate.

**HU-11 (aplicada aquí):** «Al terminar el combate: `restorePower` de todos los participantes».

### Clasificación de lo decidido

| # | Tipo | Contenido |
| --- | --- | --- |
| 1 | Requisito explícito | Las tres causas, los temporizadores (6 min y 30 s), la regla de vida restante al vencer el tiempo, el resultado único y la liberación de recursos. |
| 2 | Fuente oficial | §6.1.3, §7.6 y HU-11 citados arriba. |
| 3 | Decisión arquitectónica `Accepted` | Combat es la única autoridad; persistir antes de difundir; una conexión caída queda «desconectada», no «abandonada» (ADR-020). |
| 4 | Decisión **solicitada por el PO por chat externo (2026-09-21, según Dabji)** — **no consta en el Issue** | (a) La desconexión da una **gracia de 30 s** para reconectar; (b) si al vencer los 6 min ambos equipos tienen **el mismo porcentaje**, gana el de **más vida restante absoluta**. |
| 5 | Decisión **elegida por Dabji (2026-09-21) entre opciones, pendiente de ratificar por el PO** | (c) El vencimiento del turno de 30 s **pierde el turno**: el servidor lo cierra sin acción y pasa al siguiente participante; **no** cierra la batalla ni castiga más. (d) Los **créditos del §7.6** se publican como **derecho** en la notificación a consumidores; Combat **no acredita nada** y Web **no los muestra como concedidos**. |
| 6 | Decisión técnica del autor (a confirmar) | Ganador por desconexión = el equipo rival (§4.2); porcentaje de equipo = Σ vida / Σ vida máxima con aritmética entera (§4.3); un héroe eliminado no juega turno (§4.1); precedencia y simultaneidad (§4.5); chat de sala cerrado al finalizar (§8); créditos de un empate y del desconectado (§9); batallas previas (§12). |
| 7 | Pendiente | **Empate total** (mismo porcentaje **y** misma vida absoluta): se declara `NO_WINNER` sin desempate inventado; **pendiente del PO**. Transporte de la señal hacia HU-29 y de las recompensas hacia HU-22/23/30 (§8, §9). |

## 2. Ciclo de vida

```text
WAITING_FOR_PLAYERS ──► PREPARING ──► IN_BATTLE ──► FINISHED   (terminal, NUEVO)
        │
        └──────────────────────────────────► CANCELLED           (terminal, solo antes de iniciar)
```

- `FINISHED` **solo** se alcanza desde `IN_BATTLE` y **una sola vez**. No hay salida de `FINISHED`.
- Una sala `FINISHED` conserva la batalla en su estado final, el `result` y la bitácora de eventos: `resume` reproduce todo, incluido el resultado.
- En `FINISHED` **no** se admite `join`, `leave`, `cancel`, `start`, `attack` ni `useSkill`: las reglas por estado que ya rechazan cualquier estado distinto del requerido siguen valiendo; `attack`/`useSkill` responden `BATTLE_NOT_ACTIVE` (código existente, sin códigos nuevos).
- La causa **no** es un estado: es un campo del resultado (§5).

## 3. Temporizadores (autoridad del servidor)

| Temporizador | Duración | Origen | Vence cuando |
| --- | --- | --- | --- |
| Global | 6 min = `360 000 ms` | `battle.startedAt` (el `occurredAt` de `battleStarted`) | `ahora >= startedAt + 360 000 ms` |
| Turno | 30 s = `30 000 ms` | `battle.turnStartedAt`: el inicio de la batalla para el primer turno y, después, el `occurredAt` del evento que avanzó el turno | `ahora >= turnStartedAt + 30 000 ms` |
| Gracia de desconexión | 30 s = `30 000 ms` | El instante en que el participante pierde su **última** conexión de batalla (§4.2) | `ahora >= desconectadoDesde + 30 000 ms` y sigue ausente |

- **El límite es inclusivo:** en el instante exacto del vencimiento ya venció (frontera: `deadline - 1 ms` no vence; `deadline` sí).
- **Reloj:** `ClockPort` (el del servidor). Nunca un reloj de Web ni un dato del cliente. Las constantes viven en una política de dominio; **no** hay variables de entorno que las cambien.
- **Cómo se hace cumplir (dos mecanismos, ambos obligatorios):**
  1. **Barrido:** un planificador revisa cada `1 s` los vencimientos pendientes y procesa la sala bajo su cerrojo. La resolución es de ~1 s.
  2. **Perezoso:** todo comando de combate (`attack`, `useSkill`) **primero** liquida los vencimientos de su sala (con el reloj del servidor) y **después** se valida. Así un comando que llega tras el vencimiento, antes del siguiente barrido, nunca se ejecuta sobre un turno o una batalla vencidos: recibe `NOT_YOUR_TURN` (el turno ya pasó) o `BATTLE_NOT_ACTIVE` (la batalla ya terminó).
- Los vencimientos **globales y de turno** son derivables del estado persistido, así que **sobreviven a un reinicio**: al arrancar, el planificador carga las salas `IN_BATTLE` y registra sus vencimientos; los que ya vencieron se procesan en el primer barrido.
- La **gracia** vive en memoria (la presencia es de la conexión, ADR-020): al arrancar, todo participante HUMANO de una batalla `IN_BATTLE` se considera ausente desde ese instante y tiene 30 s para reconectar.
- **Web solo muestra** el tiempo restante (§6.4); llegar a 0 en pantalla **no** ejecuta nada.

## 4. Condiciones de cierre y matriz condición → resultado

### 4.1 Eliminación (`ELIMINATION`)

- Se evalúa **en la misma escritura** de toda acción que cambie la Vida (`attack` y `useSkill`, incluida una habilidad degradada a ataque básico): si **todos** los combatientes de un equipo quedan con Vida `0`, la batalla finaliza y **gana el equipo del actor**.
- Un equipo solo puede ser eliminado si todos sus combatientes tienen Vida (un participante sin perfil, p. ej. `AI`, no tiene Vida y **impide** la eliminación de su equipo: HU-18 ya rechaza atacar hacia o desde él).
- **Un héroe eliminado no juega turno** (derivado de §6.1.3: solo permanece «activo» quien tiene Vida): al cerrar un turno, el avance salta a los participantes con Vida; cada posición saltada cuenta como turno completado (`turnsCompleted` sube, `round` sigue derivándose). No hay evento por cada salto. En 1 contra 1 nunca ocurre: la primera eliminación finaliza la batalla.
- Un golpe que deja a un equipo sin héroes **no** produce dos resultados: el evento de la acción y `battleFinished` van en la misma escritura (§7).

### 4.2 Desconexión (`DISCONNECTION`) — gracia de 30 s

- **Conexión de batalla:** una conexión autenticada que completó `resume` de esa sala **y** cuyo `sub` es un participante HUMANO. La suscripción al lobby (`subscribe`) **no** cuenta.
- **Presencia:** un participante está presente mientras tenga **al menos una** conexión de batalla abierta (varias pestañas cuentan una vez).
- **Al perder la última conexión de batalla**, el participante queda **ausente** y empieza su gracia de 30 s. Si vuelve a hacer `resume` antes del vencimiento, la gracia se **cancela**.
- **Al vencer la gracia con el participante aún ausente y la sala `IN_BATTLE`:** finaliza con `reason: DISCONNECTION`; **pierde el equipo del desconectado y gana el rival** (decisión técnica del autor: el Issue no nombra ganador).
- **Semilla de presencia:** al iniciar la batalla, quien no tiene conexión de batalla en ese instante empieza su gracia en `startedAt`; al reiniciar Combat, todos empiezan su gracia en el arranque.
- Un mismo evento con varios vencimientos de gracia decide por el **`desconectadoDesde` más antiguo** (empate: la posición menor en la cola).
- El latido (25 s, ADR-020) puede tardar hasta ~50 s en cerrar una conexión muerta: la desconexión efectiva es «cierre detectado + 30 s». Es una limitación conocida, no un defecto.
- **Consecuencia aceptada:** una recarga de página es una desconexión; si vuelve dentro de los 30 s, no pasa nada. Si **todos** caen a la vez y ninguno vuelve, pierde el que se desconectó primero.
- Los participantes `AI` no tienen conexión: nunca se «desconectan».

### 4.3 Vencimiento de los 6 minutos (`TIME_LIMIT`)

Regla de vida restante (Issue #65: «mayor porcentaje de vida restante entre los equipos»), sobre el estado de la batalla en el instante del vencimiento:

1. Por equipo: `vidaRestante = Σ Vida actual` y `vidaMáxima = Σ Vida máxima` de **todos** sus combatientes (un héroe eliminado aporta `0` a lo restante y su máxima cuenta).
2. **Porcentaje mayor gana.** La comparación es **entera**, sin decimales: A gana si `restanteA × máximaB > restanteB × máximaA` (y B gana en el sentido opuesto). `tiebreak: LIFE_PERCENT`.
3. **Mismo porcentaje (solicitud del PO):** gana el equipo con **mayor `vidaRestante` absoluta**. `tiebreak: ABSOLUTE_LIFE`.
4. **Mismo porcentaje y misma vida absoluta:** `outcome: NO_WINNER`, sin ganador ni perdedor. `tiebreak: null`. **Pendiente del PO** (§15). Es un caso real: con la misma Vida máxima y nadie atacando, ambos quedan al 100 % y con la misma Vida.
5. Una batalla **sin estado de combate** (anterior a HU-18: sin Vida) no permite calcular la regla: `NO_WINNER`, `tiebreak: null`.
- El campo `lifePercent` del resultado es **solo para mostrar** (dos decimales); la decisión nunca lo usa.

### 4.4 Temporizador de turno: **no** finaliza la batalla

Al vencer los 30 s del turno vigente (`turnTimedOut`): el servidor cierra el turno **sin acción**, avanza al siguiente participante **con Vida** y arranca su temporizador. Efectos colaterales idénticos a cerrar un turno (recargas y regeneración de Poder de HU-19). No consume sorteos. Si nadie actúa, los turnos se pierden uno tras otro hasta el vencimiento global.

### 4.5 Precedencia y simultaneidad

- La finalización por **eliminación** ocurre dentro de la acción; el resto la produce el procesador de vencimientos.
- Si en un mismo barrido hay varios vencimientos, se procesa el **más antiguo**; empate exacto: `DISCONNECTION`, luego `TIME_LIMIT`, luego `TURN_TIMEOUT` (esta última no finaliza). Tras finalizar, los demás se descartan.
- **Un único resultado** (§7): quien persiste primero gana; los demás intentos releen la sala, la ven `FINISHED` y no hacen nada.

### Matriz condición → resultado

| Condición | `reason` | `outcome` | Ganador | Cierra la batalla |
| --- | --- | --- | --- | --- |
| Todos los héroes de un equipo con Vida 0 | `ELIMINATION` | `WIN` | Equipo del actor | Sí |
| Gracia de un participante vencida y sigue ausente | `DISCONNECTION` | `WIN` | Rival del desconectado | Sí |
| 6 min y porcentajes distintos | `TIME_LIMIT` (`tiebreak: LIFE_PERCENT`) | `WIN` | Mayor porcentaje | Sí |
| 6 min, mismo porcentaje, vida absoluta distinta | `TIME_LIMIT` (`tiebreak: ABSOLUTE_LIFE`) | `WIN` | Mayor vida absoluta | Sí |
| 6 min, mismo porcentaje y misma vida absoluta | `TIME_LIMIT` (`tiebreak: null`) | `NO_WINNER` | — | Sí |
| 6 min en batalla sin datos de Vida | `TIME_LIMIT` (`tiebreak: null`) | `NO_WINNER` | — | Sí |
| 30 s del turno | — (`turnTimedOut`) | — | — | **No** |

## 5. Resultado (`BattleResult`)

Único, persistido con la sala y viajando en `battleFinished` y en el `snapshot`:

```jsonc
{
  "reason": "TIME_LIMIT",                 // ELIMINATION | DISCONNECTION | TIME_LIMIT
  "outcome": "WIN",                       // WIN | NO_WINNER
  "winnerTeamLabel": "B",                 // null si NO_WINNER
  "finishedAt": "2026-09-21T10:06:00.000Z",
  "tiebreak": "ABSOLUTE_LIFE",            // LIFE_PERCENT | ABSOLUTE_LIFE | null (solo TIME_LIMIT; null en las demás causas)
  "disconnected": null,                   // { "teamLabel": "A", "seat": 0 } si reason = DISCONNECTION
  "teams": [
    { "teamLabel": "A", "remainingHealth": 22, "maxHealth": 44, "lifePercent": 50, "eliminated": false },
    { "teamLabel": "B", "remainingHealth": 25, "maxHealth": 50, "lifePercent": 50, "eliminated": false }
  ],
  "participants": [
    { "teamLabel": "A", "seat": 0, "kind": "HUMAN", "playerId": "…", "displayName": "Ana", "heroId": "…", "result": "LOST" },
    { "teamLabel": "B", "seat": 0, "kind": "HUMAN", "playerId": "…", "displayName": "Bruno", "heroId": "…", "result": "WON" }
  ]
}
```

- `result` por participante: `WON` (su equipo ganó), `LOST` (su equipo perdió) o `NO_WINNER`.
- `teams` va **siempre** (también en una eliminación o desconexión): es el estado final que explica el resultado. Un equipo sin datos de Vida lleva `remainingHealth: 0`, `maxHealth: 0`, `lifePercent: 0`.
- **No** lleva créditos ni recompensas: esos son para consumidores (§9).
- Los valores de Vida del resultado se leen **antes** de restaurar el Poder; el Poder no aparece aquí.

## 6. Eventos y mensajes

Se sigue la regla de HU-17/18/19: **persistir antes de difundir**, `seq` creciente por sala sin huecos, **los mismos bytes** para todos los participantes, y `resume` reenvía la bitácora.

### 6.1 `turnTimedOut`

```jsonc
{ "type": "turnTimedOut", "seq": 5, "roomId": "…", "occurredAt": "…",
  "completedPosition": 1,                        // posición 0-based del turno que se perdió
  "timedOut": { "teamLabel": "B", "seat": 0 },   // quien perdió el turno
  "battle": { /* BattleView posterior: turno ya avanzado y `deadlines` nuevos */ } }
```

### 6.2 `battleFinished`

```jsonc
{ "type": "battleFinished", "seq": 9, "roomId": "…", "occurredAt": "…",
  "result": { /* BattleResult, §5 */ },
  "battle": { /* BattleView FINAL: Vida final, Poder restaurado al máximo (HU-11), sin `deadlines` */ } }
```

- **Eliminación:** el evento de la acción (`basicAttackResolved` o `skillUsed`, con su `seq`) y `battleFinished` (`seq + 1`) se persisten **juntos** en una sola escritura y se difunden en ese orden. El evento de la acción no cambia de forma respecto a HU-18/19.
- **Desconexión y tiempo:** un solo `battleFinished`.
- Tras `battleFinished` **no** hay más eventos en la sala.

### 6.3 Ampliaciones aditivas (nada de HU-13/17/18/19 cambia)

| Dónde | Campo | Detalle |
| --- | --- | --- |
| `BattleView` | `deadlines?: { turnEndsAt, battleEndsAt }` | Instantes absolutos ISO. Presente mientras la batalla está en curso; **ausente** en la vista final y en vistas anteriores a HU-21. |
| `resume.ok` | `serverTime` | ISO del servidor al confirmar la recuperación (para que Web muestre cuentas atrás sin fiarse de su reloj). |
| `snapshot` | `result` | `BattleResult` si la sala es `FINISHED`; `null` en otro caso. |
| `GET /api/v1/combat/rooms/{roomId}` | `result` | Igual que en el `snapshot`, con la misma visibilidad que el resto del estado. |
| Estado de sala | `FINISHED` | Nuevo valor de `status` en el `snapshot`, en `GET` y en `battle-room.updated`. |

### 6.4 Lo que Web hace con esto

Web **muestra** los tiempos y el resultado y **no decide nada**: no compara porcentajes, no declara ganador, no declara Vida 0 como fin. Convierte `deadlines` a «tiempo restante» con `resume.ok.serverTime` y un reloj **monótono** local (sin `Date.now()` como fuente de decisión); llegar a 0 solo deja el texto en `0:00` hasta que Combat publique el evento. Tras un refresh, el `snapshot` con `result` recupera la pantalla final.

## 7. Atomicidad, persistencia, idempotencia y concurrencia

- **Una sola escritura por transición**: estado de sala (`FINISHED`), `result`, Poder restaurado, evento(s) y `version`. Sin segunda escritura.
- **Un único resultado:** `BattleRoom.finish` solo admite `IN_BATTLE`; el bloqueo optimista por `version` impide que dos escrituras concurrentes prosperen; el cerrojo por sala (`RoomCommandLockPort`) serializa acciones, vencimientos y desconexiones. Quien pierde la carrera relee, ve `FINISHED` y **no** repite nada (no hay segundo `battleFinished`, ni segunda notificación a consumidores).
- **Repetir la finalización** (barrido, desconexión o acción) sobre una sala `FINISHED` es un **no-op**.
- **Acciones después del final:** `attack`/`useSkill` → `BATTLE_NOT_ACTIVE` sin sorteos y sin cambios.
- **Una acción y un vencimiento a la vez:** el que el cerrojo sirva primero decide; el segundo ve el estado ya cambiado (`NOT_YOUR_TURN`, `BATTLE_NOT_ACTIVE` o no-op). No hay re-sorteo: la finalización no sortea, y las acciones mantienen la regla de HU-18/19.
- **Conflicto de versión** al procesar un vencimiento: se relee la sala y se reevalúa (es determinista); nunca se aplica dos veces.

## 8. Liberación de recursos y señal para HU-29

Al persistir `FINISHED` (y solo entonces):

1. **Planificador:** se cancelan los vencimientos y las gracias de la sala.
2. **Presencia y suscripciones:** las conexiones dejan de estar suscritas a la sala como conexión de batalla; los sockets **no se cierran** (el cliente puede seguir leyendo el resultado y hacer `resume`; un `resume` sobre una sala `FINISHED` entrega el estado y **no** registra presencia).
3. **Chat de sala:** se **cierra** (`ROOM_CHAT_OPEN[FINISHED] = false`: «solo mientras la sala esté activa»; decisión técnica pendiente de ratificar por el PO). La notificación `battle-room.updated` con `status: FINISHED` hace que el chat revalide el acceso.
4. **Poder:** se restaura al máximo de todos los combatientes (HU-11) en la vista final.
5. **Cerrojos y colas por sala:** no quedan estructuras en memoria de esa sala.
6. **Señal para consumidores:** `status: FINISHED` + el evento `battleFinished` + la notificación de §9.

**HU-29 (bloqueo de equipamiento):** la señal de «la batalla terminó, se libera la restricción» es el estado terminal `FINISHED` de la sala (consultable por `GET` autenticado como el jugador) y la notificación `BattleFinishedNotification`. HU-21 **no** añade un endpoint servicio a servicio ni un transporte de mensajería: cómo Player-Inventory se entera (consulta HTTP interna o evento) es una decisión de HU-29 con Infrastructure. Queda documentado como punto de integración.

## 9. Integración de recompensas (sin implementarlas)

Puerto de salida `BattleResultPublisherPort.publish(notification)`, invocado **una vez** tras persistir y difundir (semántica *al menos una vez*, clave de idempotencia = `roomId`). Un fallo al publicar se registra y **no** revierte la batalla. El adaptador de esta HU **solo escribe un registro estructurado** (`battle_finished`): no hay transporte entre servicios todavía.

```ts
interface BattleFinishedNotification {
  roomId: string
  mode: string                      // PVP | PVE
  finishedAt: string                // ISO
  reason: 'ELIMINATION' | 'DISCONNECTION' | 'TIME_LIMIT'
  outcome: 'WIN' | 'NO_WINNER'
  winnerTeamLabel: string | null
  participants: {
    kind: 'HUMAN' | 'AI'
    playerId: string | null
    heroId: string | null           // el héroe beneficiario del resultado (HU-09)
    teamLabel: string
    seat: number
    result: 'WON' | 'LOST' | 'NO_WINNER'
    credits: number | null          // DERECHO según §7.6; null para AI; NO acreditado
  }[]
  configuredReward: { amount: number }   // la «posible recompensa» de la sala tal como se configuró; sin semántica de entrega (HU-23)
}
```

**Créditos (§7.6):** ganador **2** si la batalla es 1 contra 1 y **4** si es de equipos (cada jugador del equipo ganador); todos los demás **1** por participar; `NO_WINNER`: **1** para cada participante (participación); el desconectado, si pierde, recibe **1** como cualquier perdedor. **Combat no acredita nada** (Wallet no tiene API de acreditación) y **Web no los muestra** como concedidos. La entrega real, el conteo de HU-22 (20 créditos), la apuesta de HU-23 y la caída de HU-30 son de esas historias. Es una decisión elegida por Dabji y pendiente de ratificar por el PO.

## 10. Errores

No hay códigos nuevos en `command.rejected`: tras el final, `BATTLE_NOT_ACTIVE`; con turno vencido, `NOT_YOUR_TURN`. `POST /rooms/{id}/start` sobre una sala `FINISHED` responde el conflicto de estado ya existente (`RoomNotStartableError`). `join`, `leave` y `cancel` sobre `FINISHED` responden los errores de estado ya existentes (la sala no admite la operación).

## 11. Seguridad y minimización

- El actor, el turno y todos los instantes salen del servidor; ningún mensaje del cliente puede provocar, retrasar ni declarar una finalización.
- El resultado solo contiene identificadores que la vista de la batalla ya publica (`playerId`, `heroId`, `displayName`); nunca semilla, índices, estadísticas ni efectos.
- La notificación a consumidores no lleva inventario, estadísticas ni perfiles.
- Los registros llevan `roomId`, `reason`, `outcome` y `winnerTeamLabel`; no nombres.

## 12. Persistencia, migración y batallas previas

- **Migración `009`** (aditiva, autocontenida, con `down`): `status` admite `FINISHED`; `result` opcional en la sala; `battle.turnStartedAt` opcional; los tipos de evento `turnTimedOut` y `battleFinished`. Ninguna sala existente necesita *backfill*. Se ejecuta **antes** de arrancar la versión nueva (`npm run migrate`).
- **Invariante nuevo:** una sala tiene `battle` si y solo si está `IN_BATTLE` o `FINISHED`; tiene `result` si y solo si está `FINISHED`.
- **Batallas `IN_BATTLE` anteriores a HU-21** (sin `turnStartedAt`): el turno se considera iniciado en `startedAt`. Al desplegar, las que ya superaron los 6 minutos se **cierran solas** por `TIME_LIMIT` en el primer barrido (con la regla de §4.3, o `NO_WINNER` si no tienen Vida). Es un efecto deseado (liberan recursos), pero cambia su estado: **hay que avisarlo** al desplegar.

## 13. Matriz de escenarios (base de las pruebas)

| # | Escenario | CA |
| --- | --- | --- |
| S-01 | 1 contra 1: el golpe deja al rival con Vida 0 → un solo `battleFinished` (`ELIMINATION`), gana el atacante; el evento de la acción y el final con `seq` consecutivos | CA-01, CA-02, CA-09 |
| S-02 | Igual con `useSkill` y con una habilidad degradada a ataque básico | CA-02 |
| S-03 | 2 contra 2: eliminar a un héroe **no** finaliza; su turno se salta; eliminar al segundo finaliza | CA-02 |
| S-04 | Desconexión: cerrar la última conexión, esperar 30 s (con reloj controlado) → `DISCONNECTION`, gana el rival | CA-03, CA-09 |
| S-05 | Frontera de la gracia: a 29 999 ms no finaliza; a 30 000 ms sí | CA-03 |
| S-06 | Reconexión dentro de la gracia: no finaliza y la batalla sigue | CA-03 |
| S-07 | Varias pestañas: cerrar una no desconecta; cerrar la última sí | CA-03 |
| S-08 | Un participante sin conexión al iniciar: su gracia corre desde `startedAt` | CA-03 |
| S-09 | Reinicio de Combat: las gracias arrancan en el arranque; los vencimientos globales y de turno se recuperan de la base | CA-03, CA-04 |
| S-10 | A 6 min y porcentajes distintos → gana el mayor (`LIFE_PERCENT`) | CA-04, CA-06, CA-10 |
| S-11 | A 5:59.999 no finaliza; a 6:00.000 sí (frontera) | CA-04 |
| S-12 | Mismo porcentaje, distinta vida absoluta → gana la mayor (`ABSOLUTE_LIFE`) (p. ej. 22/44 frente a 25/50) | CA-06, CA-10 |
| S-13 | Mismo porcentaje y misma vida → `NO_WINNER`; nadie gana | CA-06, CA-07 |
| S-14 | La comparación es entera: sin errores de decimales (p. ej. 1/3 frente a 33/99) | CA-06 |
| S-15 | Turno de 30 s: a 29 999 ms sigue; a 30 000 ms `turnTimedOut` y avanza; el siguiente tiene 30 s nuevos | CA-05 |
| S-16 | Un comando llega tras el vencimiento del turno, antes del barrido → `NOT_YOUR_TURN` y el turno ya pasó (liquidación perezosa) | CA-05 |
| S-17 | Nadie actúa: los turnos se pierden y a los 6 min finaliza | CA-04, CA-05 |
| S-18 | Dos finalizaciones a la vez (acción letal y vencimiento; barrido y desconexión) → **un** resultado, un `battleFinished`, una notificación | CA-07 |
| S-19 | Repetir la finalización → no-op | CA-07 |
| S-20 | `attack`/`useSkill` tras el final → `BATTLE_NOT_ACTIVE`, sin sorteos ni cambios | CA-01 |
| S-21 | Ambos clientes reciben **los mismos bytes** de `battleFinished` | CA-01 |
| S-22 | Refresh: un cliente nuevo hace `resume` y recibe el resultado (replay y `snapshot` con `result`) | CA-01 |
| S-23 | Tras finalizar: chat cerrado, sin presencia, sin vencimientos; el Poder restaurado; una notificación a consumidores con créditos según §9 | CA-08 |
| S-24 | Reinicio con una sala `FINISHED`: sigue `FINISHED` con el mismo resultado | CA-07 |
| S-25 | Sala `IN_BATTLE` anterior a HU-21 y vencida: se cierra en el primer barrido | CA-04 |
| S-26 | Ningún mensaje del cliente puede fijar ganador, causa ni tiempos | CA-07 |

CA-11 (condición de aceptación) se cumple cuando todos los escenarios anteriores pasan y Task #420 valida el flujo con dos clientes reales.

## 14. Límites con otras historias

- **HU-22, HU-23, HU-30, HU-09:** consumen la notificación (§9); no se implementan aquí.
- **HU-29:** consume la señal de §8; el transporte lo define esa HU.
- **HU-12:** sin cambios (fuego amigo).
- **HU-31 / épica:** sin cambios; la épica sigue bloqueada.
- **Participantes `AI` / JcE:** sin fuente de su perfil de combate; la validación de esta HU es JcJ 1 contra 1.

## 15. Pendientes y supuestos (para el PO)

| Punto | Estado |
| --- | --- |
| Empate total (mismo % y misma vida absoluta) → `NO_WINNER` | **pendiente del PO** |
| Ganador por desconexión = equipo rival | decisión técnica a confirmar |
| Créditos del §7.6 como derecho sin acreditar; créditos del empate y del desconectado | elegido por Dabji, **pendiente de ratificar por el PO** |
| Turno vencido = turno perdido | elegido por Dabji, **pendiente de ratificar por el PO** |
| Chat de sala cerrado al finalizar | decisión técnica a confirmar |
| Porcentaje de equipo = Σ vida / Σ vida máxima (héroe eliminado cuenta en la máxima) | decisión técnica a confirmar |
| Un héroe eliminado no juega turno | decisión técnica derivada de §6.1.3 |
| Recarga de página = desconexión con gracia de 30 s; caída simultánea de todos: pierde el primero | consecuencia aceptada de la gracia |
| Transporte hacia HU-29 y hacia HU-22/23/30 | de esas historias con Infrastructure |
| Réplicas múltiples | ADR-020: presencia, cerrojo y planificador en memoria, **una** réplica |

## 16. Compatibilidad y orden de despliegue

Aditivo: los campos nuevos no cambian ningún mensaje de HU-13/17/18/19 y un Web anterior los ignora (**salvo** que una sala `FINISHED` llegue a un Web sin esta versión: verá un estado que no conoce). **Orden:** Infrastructure (este contrato) → **Combat** (`npm run migrate`, 009, antes de arrancar) → **Web**. Combat puede salir antes que Web sin romper la batalla en curso; Web sin Combat no muestra resultado alguno. Player-Inventory no cambia.
