# Contrato HU-18 — Ataque básico (v1)

- **Estado:** diseño de la Task [#409](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/409). Lo que dice «implementado» solo lo está cuando lo integran las Tasks [#410](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/410) (Combat) y [#411](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/411) (Web); hasta entonces todo lo de este documento es **diseño**.
- **Historia:** [HU-18 #62](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/62) · **RF-18** · [EPIC-06 #6](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/6) · Team Alfa · módulo Jugar Online / Combat.
- **Bloqueada por:** HU-17 ([#26](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/26), turno y cola) y HU-20 ([#64](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/64), Ataque contra Defensa), ambas cerradas.
- **Arquitectura aplicada, sin reabrirla:** [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md) (Combat única autoridad), [ADR-020](../adr/ADR-020-realtime-combat.md) (`Accepted`: WebSocket, comandos con `commandId`, `seq`, persistir antes de difundir) y [ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md) (`Accepted`: aleatoriedad HU-24/HU-25). **No hay ADR nuevo:** ninguna decisión arquitectónica nueva; lo que sigue son decisiones técnicas de aplicación.
- **Contrato del que parte:** [HU-17](hu-17-battle-turn-order-v1.md) (cola, `turnsCompleted`, `seq`, `resume`, `snapshot`) y [HU-13](hu-13-chat-v1.md) (mismo socket, mismas convenciones de `command.rejected`).
- **Diagramas:** [secuencia](../diagrams/hu-18-sequence-basic-attack.puml), [actividades](../diagrams/hu-18-activity-basic-attack.puml) y [estados](../diagrams/hu-18-state-battle-health.puml).

## 1. Qué exige la HU y qué no

**Requisito explícito (RF-18, Issue #62):**

- solo puede ejecutarse durante el turno del jugador que controla al héroe atacante;
- el jugador selecciona **un único** objetivo; el ataque básico **no** produce daño en área;
- **no consume Poder** y permanece disponible aunque el héroe no tenga Poder para otras acciones;
- el resultado se calcula con las reglas de **Ataque contra Defensa**;
- cuando el ataque produce efecto, la **Vida** del objetivo se actualiza;
- después de resolver el ataque, el **turno** del jugador finaliza.

**Aclaración formal registrada:** el redondeo del daño es **`floor`** ([comentario en #62](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/62#issuecomment-5761290722), 2026-09-21). El documento oficial no lo definía; **no es un requisito original** de la HU.

**Fuera de alcance (no se implementa ni se cierra aquí):** habilidades y épicas (HU-19), fuego amigo con excepciones (HU-12), fin de batalla, ganador, temporizadores y recompensas (HU-21), bloqueo de equipamiento (HU-29), cofres y créditos (HU-22/23/30).

### Clasificación de lo decidido

| # | Tipo | Contenido |
| --- | --- | --- |
| 1 | Requisito explícito | Las seis reglas de arriba (RF-18). |
| 2 | Aclaración formal | Daño = `floor(dañoBase × porcentaje / 100)`; Vida entera. |
| 3 | Decisión arquitectónica `Accepted` | Combat es la única autoridad; el cliente envía **comandos** con `commandId`, no estado; persistir antes de difundir; `seq` (ADR-019/020). El comando se llama `attack`, tal como lo nombra ADR-020. |
| 4 | Contrato vigente | HU-17 (cola, `seq`, `resume`), HU-20 (`prepareAttack`, `ResolveAttack`), HU-25 (`ResolveRandomEffect`), contrato interno de Player-Inventory (`effectiveStats`, `activeEffects`). Se **reutilizan**, no se reescriben. |
| 5 | Decisión técnica | Un **único evento** por ataque con el estado ya avanzado; snapshot de combate congelado al iniciar; orden de sorteos; serialización por sala; códigos de error. Todas en este documento. |
| 6 | Recomendación | Ninguna se presenta como requisito. |
| 7 | Pendiente | Ver §14. |

## 2. Transporte: comando por el WebSocket de ADR-020

**No hay endpoint REST de ataque.** El protocolo de comandos de tiempo real ya es la superficie aprobada (ADR-020 nombra el comando `attack`; `useSkill` es de HU-19). El atacante **no viaja**: se deriva del `sub` autenticado de la conexión y del turno vigente.

```jsonc
// Cliente → servidor (máx. 16 KiB, como todo mensaje)
{
  "type": "attack",
  "commandId": "6f0b6f0e-…",        // UUID generado por el cliente, 1..100 caracteres
  "roomId": "aaaaaaaa-…",           // UUID v4 de la sala
  "target": { "teamLabel": "B", "seat": 0 }   // UN objetivo: identidad estable del participante
}
```

- **Exactamente esas cuatro claves.** Cualquier otra (`attackValue`, `defense`, `damage`, `percent`, `healthAfter`, `attackerId`, `currentTurn`, `targets`, `area`, …) hace el comando **mal formado** (`MALFORMED_COMMAND`, 0 sorteos): el servidor **no las ignora en silencio**, las rechaza para que un cliente que intente aportar un resultado lo descubra.
- `target` es **un objeto** con `teamLabel` (cadena no vacía) y `seat` (entero ≥ 0). Un arreglo, `targets: []`, `targets: [A, B]` o `area: true` son mal formados.
- La identidad del objetivo es `(teamLabel, seat)`, la misma `memberKey` de HU-17. **No** se usa `heroId`: dos jugadores pueden llevar el mismo héroe de Catalog.
- La conexión debe estar **autenticada** (ticket, ADR-020); sin autenticar se cierra con `4401`, igual que `subscribe`/`resume`.
- Los comandos de combate de una conexión se atienden **de uno en uno**, en el orden en que llegan.

## 3. Orden de validación (todo **antes** de consumir un solo sorteo)

Una petición inválida consume **0 índices** de la secuencia HU-24 y no modifica nada.

| # | Comprobación | Código |
| --- | --- | --- |
| 1 | Forma del mensaje (claves, tipos, `roomId` UUID v4, `target` objeto) | `MALFORMED_COMMAND` |
| 2 | `commandId` cadena de 1 a 100 caracteres | `INVALID_COMMAND_ID` |
| 3 | La sala existe | `ROOM_NOT_FOUND` |
| 4 | El solicitante es participante `HUMAN` de la sala | `NOT_A_PARTICIPANT` |
| 5 | **`commandId` ya procesado** → se devuelve el resultado guardado (§8), sin validar turno ni sortear | — (idempotente) |
| 6 | La sala está `IN_BATTLE` | `BATTLE_NOT_ACTIVE` |
| 7 | El solicitante es el participante de la posición activa de la cola | `NOT_YOUR_TURN` |
| 8 | El objetivo existe en la batalla | `INVALID_TARGET` |
| 9 | El objetivo **no** es del equipo del atacante (incluido él mismo) | `SAME_TEAM_TARGET` |
| 10 | El atacante y el objetivo tienen perfil de combate y Vida > 0 | `UNSUPPORTED_COMBAT_PROFILE`, `ACTOR_UNAVAILABLE`, `TARGET_UNAVAILABLE` |
| 11 | El atacante tiene Ataque numérico y un Daño soportado (§5) | `UNSUPPORTED_COMBAT_PROFILE` |

Solo entonces se prepara y se resuelve el golpe. La Vida del objetivo y la del atacante se leen del **estado de la batalla persistido**, nunca del cliente.

## 4. Resolución: HU-20 se reutiliza, no se reimplementa

```text
prepareAttack(atacante, objetivo)            HU-20 (dominio/aplicación, puro)
  └─ ResolveAttack.execute(...)              HU-20: dado de Ataque → Ataque > Defensa ?
       ├─ no  → effective=false, effect=null                     (la igualdad NO supera)
       └─ sí  → ResolveRandomEffect (HU-25) → efecto + porcentaje
materializar el Daño del atacante            HU-18 (nuevo, política pura)
daño calculado = floor( dañoBase × porcentaje / 100 )            (aclaración formal)
daño aplicado  = min( daño calculado, Vida actual )
Vida nueva     = Vida actual − daño aplicado                     (0 ≤ Vida ≤ Vida máxima)
```

- **Ataque y Daño no se confunden.** El Ataque solo se compara con la Defensa. **Nunca** se hace `Vida −= Ataque` ni `daño = Ataque − Defensa`.
- El **daño base** sale de `effectiveStats.damage` del atacante (snapshot, §6): `DICE {count, sides}` se tira con la secuencia HU-24; `FIXED {amount}` se usa tal cual, **sin sorteo**; `PERCENTAGE` (o `null`, o valores inválidos) **no está soportado** y se rechaza *antes* de sortear (`UNSUPPORTED_COMBAT_PROFILE`): ninguna fuente formal dice sobre qué base actuaría un porcentaje. La Tabla 6 del documento oficial es la **verificación** de esos dados (Tanque 1d4, Armas 1d6, Fuego 1d8, Hielo 1d6, Veneno 1d6, Machete 1d8); no hay tercera copia en Combat.
- **Porcentajes** (los que entrega HU-25): 100 % causar daño, 120–180 % crítico, 80 % evaden, 60 % resisten, 20 % escapan, 0 % no causa daño. Se reutilizan sin reinterpretarlos.
- **Bonos de daño del equipamiento** («+2 al daño»…): `effectiveStats.damage` **no** los incluye (`appliedToStats = false`) y ningún requisito aprobado define cómo componerlos con el dado y el porcentaje. **No se aplican**; siguen como efectos pendientes (HU-20, HU-19). Se declara como pendiente, no como aplicado.
- La **Defensa** solo participa en la comparación (HU-20). No reduce además el daño: eso no lo define ninguna fuente y se descarta como invención.

### Consumo de la secuencia aleatoria (HU-24), en este orden exacto

| Paso | Sorteos | Cuándo |
| --- | --- | --- |
| 1. Dado de Ataque | `dice.count` (1 con la Tabla 6) | siempre que el atacante lleve dado (HU-20, sin cambios) |
| 2. Efecto | **1** | solo si el golpe es efectivo (HU-20, sin cambios) |
| 3. Dado de Daño | `damage.count` | solo si el golpe es efectivo **y** el porcentaje es > 0 **y** el daño es `DICE` |

Decisión técnica: con un efecto del 0 % el daño calculado es 0 sea cual sea el dado, así que **no se consume aleatoriedad que no puede afectar al resultado**. Un golpe no efectivo consume solo el paso 1; un rechazo previo, ninguno. Todo sale de `RandomSequencePort.nextIndex()`; no hay `Math.random`, `crypto` ni otro generador, y la cara de un dado reutiliza `dieFaceFromIndex` (mismo mapeo que el dado de Ataque).

**Casos:**

| Caso | `effective` | Efecto | Daño calculado | Vida | Turno |
| --- | --- | --- | ---: | --- | --- |
| Ataque ≤ Defensa | `false` | `null` | 0 | igual | **avanza** |
| Efecto `NO_DAMAGE` (0 %) | `true` | `NO_DAMAGE` | 0 | igual | **avanza** |
| Daño > 0 | `true` | `DAMAGE` / `CRITICAL_DAMAGE` / `EVADE` / `RESIST` / `ESCAPE` | ≥ 0 | baja `min(daño, Vida)` | **avanza** |
| Daño que supera la Vida restante (*overkill*) | `true` | cualquiera | daño | queda en **0** | **avanza** |

Un `floor` que deja el daño en 0 **no es un error**: el golpe fue efectivo, se resolvió y el turno finaliza.

## 5. Estado de batalla: snapshot de combate congelado

HU-17 solo conserva `turnOrder` y `turnsCompleted`; para HU-18 la batalla necesita Vida y estadísticas. **Combat es la fuente de verdad de la Vida durante la batalla**; Player-Inventory conserva la configuración fuera de ella y **no** guarda la Vida de cada golpe.

**Al iniciar (`StartBattle`)**, con la respuesta de Player-Inventory que **ya** se obtiene para revalidar HU-16 (sin segunda llamada), se construye un **snapshot de combate local y mínimo** por participante:

| Campo interno (no viaja completo a Web) | Origen |
| --- | --- |
| `teamLabel`, `seat` | identidad estable de HU-17 |
| `heroId`, `subtype` | ya presentes en la cola |
| `maxHealth` = `currentHealth` inicial | `effectiveStats.health` |
| `attack`, `defense` | `effectiveStats.attack` / `.defense` |
| `damage` | `effectiveStats.damage` (`DICE`/`FIXED`/`PERCENTAGE`/`null`) |
| `activeEffects` | los efectos que HU-20 necesita (crítico propio, «−1 al ataque del oponente») |

- **Se congela**: cambiar el equipamiento en Player-Inventory *después* de iniciar no modifica la batalla. **No hay llamadas a Player-Inventory ni a Catalog por golpe** (consistencia, sin TOCTOU, y compatible con HU-29).
- **No se persiste** el inventario, el nombre, la referencia del héroe ni la fecha de selección. Combat no accede a la base de otro servicio.
- **Identidad:** `(teamLabel, seat)`. Nunca `heroId`.
- **Poder:** Combat **todavía no modela un Poder de batalla** (HU-11 define la política y el medidor; falta el agregado que lo guarde y HU-19 que lo consuma). El ataque básico **no lee ni escribe Poder**: no hay puerta de Poder que pueda deshabilitarlo. Se declara como límite, no como ausencia de regla.
- **`AI`:** no existe una fuente autoritativa del perfil de combate de un participante `AI`, y **no se inventan** valores. Su snapshot es `null`; un ataque desde o hacia un `AI` se rechaza (`UNSUPPORTED_COMBAT_PROFILE`). La validación se hace primero **JcJ 1 contra 1 con dos humanos**; JcE queda pendiente (§14).
- **Sanadores** (Chamán, Médico): el documento oficial no les da Ataque ni Daño. Su ataque básico se rechaza (`UNSUPPORTED_COMBAT_PROFILE`); pueden ser objetivo. En 1 contra 1 ni siquiera entran (HU-16).
- **Batallas anteriores a HU-18** (`IN_BATTLE` sin snapshot): se restauran sin error, **sin** Vida, y no admiten ataque (`UNSUPPORTED_COMBAT_PROFILE`); no se consulta Player-Inventory al restaurar. Un documento sin batalla activa no cambia.

### Vista pública (`BattleView`, aditiva)

Web recibe solo lo necesario para pintar Vida; **no** recibe Ataque, Defensa, Daño ni `activeEffects`. La Vida viaja en **un único sitio**, `combatants`, con la misma identidad que la cola:

```jsonc
"battle": {
  "battleId": "…", "startedAt": "…", "turnOrder": [ /* HU-17, inmutable */ ],
  "turnsCompleted": 1, "round": 1, "currentTurn": { "position": 1, "…": "…" },
  "combatants": [
    { "teamLabel": "B", "seat": 0, "health": { "current": 34, "max": 40 } },
    { "teamLabel": "A", "seat": 0, "health": { "current": 44, "max": 44 } }
  ]
}
```

- Mismo orden que `turnOrder`. `health` es `null` para un participante sin perfil (`AI` o batalla anterior a HU-18).
- `current` y `max` son enteros con `0 ≤ current ≤ max`. La Vida es un **entero** (aclaración de redondeo).
- `snapshot` y cada evento llevan el `battle` **vigente en su `seq`**: un refresco reconstruye la pantalla sin haber visto los ataques anteriores.

## 6. Evento `basicAttackResolved`

**Decisión técnica: un único evento por ataque que ya trae el estado avanzado** (en lugar de `basicAttackResolved` + `turnAdvanced`). Motivos: una acción produce **un solo `seq`** (sin huecos ni orden ambiguo entre dos eventos), Web **nunca** observa la Vida nueva con el turno viejo, la deduplicación por `commandId` apunta a un único evento y `resume` reproduce exactamente la acción. El evento lleva el resultado **y** el `battle` posterior (Vida actualizada, `turnsCompleted + 1`, `currentTurn` siguiente).

```jsonc
// Servidor → participantes que hicieron `resume` (persistido ANTES de difundir)
{
  "type": "basicAttackResolved",
  "seq": 2, "roomId": "…", "occurredAt": "2026-09-21T10:01:00.000Z",
  "commandId": "6f0b6f0e-…",
  "completedPosition": 0,                        // posición del turno que acaba de cerrarse
  "attacker": { "teamLabel": "A", "seat": 0 },
  "target":   { "teamLabel": "B", "seat": 0 },
  "resolution": {
    "attackValue": 14, "defenseValue": 11,       // lo que se comparó (Ataque final vs Defensa)
    "effective": true,
    "effect": "CRITICAL_DAMAGE",                 // DAMAGE|CRITICAL_DAMAGE|EVADE|RESIST|ESCAPE|NO_DAMAGE|null
    "percent": 137,                              // 0..180 | null si no fue efectivo
    "baseDamage": 5,                             // daño base materializado | null si no se tiró
    "calculatedDamage": 6,                       // floor(5 × 137 / 100)
    "appliedDamage": 6                           // min(calculatedDamage, Vida antes)
  },
  "targetHealth": { "before": 40, "after": 34 },
  "battle": { /* BattleView posterior: combatants y turno avanzado */ }
}
```

- **Minimización:** no viajan la tirada del dado de Ataque por separado, `activeEffects`, estadísticas, el índice sorteado, la semilla ni el estado del generador. `attackValue` y `defenseValue` sí, porque son lo que explica «golpe no efectivo (14 contra 11)».
- El evento persistido es **idéntico** al que reciben todos los clientes y al que reenvía `resume`.
- **Web** actualiza Vida y turno **solo** con este mensaje o con un `snapshot`; nunca calcula daño, Ataque contra Defensa ni el turno siguiente.
- `turnAdvanced` (HU-17) no cambia y lo emite el avance de turno del servidor que no es un ataque.

**`command.rejected`** (solo a quien envió el comando; el estado no cambia):

```jsonc
{ "type": "command.rejected", "command": "attack", "commandId": "…", "code": "NOT_YOUR_TURN" }
```

Mismo formato que el resto de comandos (HU-13). `commandId` va cuando el comando lo traía como cadena válida. Web decide por `code`, **nunca** por texto.

## 7. Atomicidad, persistencia y publicación

Una acción es **una sola transición lógica del agregado** `BattleRoom`, con **una sola escritura** en MongoDB (bloqueo optimista por `version`):

```text
validar → sortear y resolver → BattleRoom.applyBasicAttack(...)
   (Vida del objetivo + evento con su seq + commandId procesado + turno avanzado, en UNA versión nueva)
→ save (UNA escritura) → publicar a los participantes
```

- **Nunca** dos escrituras (daño y después fin de turno): no puede quedar Vida bajada con el turno sin avanzar, ni turno avanzado sin resultado. La regla de avance de turno de HU-17 (`BattleState.completeTurn`) se **reutiliza** dentro de la misma mutación; no se invoca `CompleteBattleTurn` como segundo `save`.
- **Persistir antes de difundir**: si el `save` falla, no se difunde nada. Si la difusión falla, el estado ya está persistido y el cliente lo recupera con `resume`.
- **Documento:** `battle.combatants` (snapshot + Vida actual), el evento en `events` y el `commandId` en `handledCommands`. Migración **aditiva** (§12).

## 8. Idempotencia y concurrencia

- **`commandId` repetido:** se reconoce por `handledCommands` (ya guarda el `seq` del evento que produjo). El servidor devuelve **ese mismo evento persistido solo a quien lo repite**: no sortea, no consume índices, no resta Vida, no avanza el turno y no difunde otra vez. Se comprueba **antes** de validar el turno (tras el ataque el turno ya no es del atacante y el reintento no debe fallar). Los `commandId` son únicos por sala.
- **Dos comandos distintos del mismo jugador en el mismo turno (dos pestañas):** solo **uno** muta la batalla; el otro recibe `NOT_YOUR_TURN` sin tocar Vida ni turno.
- **Serialización por sala** (una réplica, ADR-020): los comandos de una sala se ejecutan de uno en uno, así el segundo relee el estado *ya* actualizado y termina como duplicado o como `NOT_YOUR_TURN` **sin haber consumido sorteos**. El bloqueo optimista por `version` sigue siendo la red de seguridad.
- **Nunca se vuelve a sortear tras un conflicto de versión.** Si el guardado falla por versión, se relee la sala: si el `commandId` ya está procesado se devuelve ese resultado; si no, se responde `COMMAND_CONFLICT` y el cliente puede reintentar **con el mismo `commandId`**. Reintentar ciegamente resolvería otra aleatoriedad con el mismo comando y podría duplicar o cambiar el daño.
- Los sorteos de un intento que pierde el guardado se descartan con él (no hay nada persistido a medias).

## 9. Errores (códigos estables)

Web decide por `code`; los textos son de la interfaz.

| Código | Cuándo | Reutiliza |
| --- | --- | --- |
| `MALFORMED_COMMAND` | claves de más o de menos, tipos incorrectos, `roomId` no UUID v4, `target` no es un objeto `{teamLabel, seat}` | nuevo |
| `INVALID_COMMAND_ID` | `commandId` no es cadena de 1 a 100 caracteres | `InvalidCommandIdError` (HU-17) |
| `ROOM_NOT_FOUND` | la sala no existe | HU-17 |
| `NOT_A_PARTICIPANT` | quien envía no es participante humano de la sala | HU-17 |
| `BATTLE_NOT_ACTIVE` | la sala no está `IN_BATTLE` | `BattleNotInProgressError` |
| `NOT_YOUR_TURN` | no es la posición activa | `NotYourTurnError` |
| `INVALID_TARGET` | el objetivo no existe en la batalla | nuevo |
| `SAME_TEAM_TARGET` | objetivo del mismo equipo, incluido el propio atacante | nuevo |
| `TARGET_UNAVAILABLE` | el objetivo ya no tiene Vida | nuevo |
| `ACTOR_UNAVAILABLE` | el atacante ya no tiene Vida | nuevo |
| `UNSUPPORTED_COMBAT_PROFILE` | sin snapshot (`AI`, batalla anterior a HU-18), sanador sin Ataque, Daño ausente o no soportado (`PERCENTAGE`) | nuevo |
| `COMMAND_CONFLICT` | conflicto de versión no resoluble; reintentar con el mismo `commandId` | `RoomConflictError` |
| `INTERNAL_ERROR` | fallo inesperado | HU-17 |

Un `commandId` repetido **no es un error** (§8).

## 10. Seguridad y minimización

- El navegador **nunca** envía Ataque, Defensa, Daño, Vida, efecto, porcentaje, semilla ni turno: solo `roomId`, `commandId` y el objetivo. Combat deriva al atacante del `sub` de la conexión y del turno.
- Nunca viajan semilla, estado del generador, índices ni resultados futuros; tampoco inventario, `activeEffects` crudos ni el perfil completo.
- No se registran JWT, tickets, semilla ni carga completa; sí `roomId`, `commandId`, tipo de evento, `seq` y resultado (`outcome`).
- Un no participante no recibe ni puede provocar eventos de batalla.

## 11. Límites con otras historias

- **HU-12 (fuego amigo, abierta):** el ataque básico **rechaza** objetivos del mismo equipo (`SAME_TEAM_TARGET`). Es una *validación local coherente con RF-12*; **no** cierra HU-12 ni implementa excepciones de habilidades. Si HU-12 define después una política formal, se reutiliza.
- **HU-19:** habilidades, épica, costo de Poder y recarga quedan fuera.
- **HU-21:** una Vida en 0 **no** finaliza la batalla, no declara ganador ni salta turnos. Un participante sin Vida no puede ser objetivo ni atacar; hasta que HU-21 defina la finalización, esa batalla queda sin más acciones válidas del participante caído. Los temporizadores (30 s por turno, 6 min globales) tampoco son de HU-18.
- **HU-29:** el snapshot congelado es compatible con el bloqueo de equipamiento, que HU-29 hará cumplir.

## 12. Persistencia y migración

- `battle-rooms` amplía el validador `$jsonSchema` con una migración **aditiva**: `battle.combatants` (opcional) y el tipo de evento `basicAttackResolved`. El número de migración es el **siguiente libre** al implementar (a la fecha de este contrato, la `006` la usa el chat de HU-13); no se asume.
- Documentos sin `combatants` siguen siendo válidos y se restauran sin batalla atacable (§5). No hay *backfill*: no existe una fuente segura de las estadísticas de una batalla ya iniciada y no se consulta Player-Inventory al restaurar.
- Los eventos de HU-17 ya persistidos (sin `combatants` en su `battle`) se reenvían tal cual en un `resume`; Web trata la ausencia como «sin información de Vida».

## 13. Matriz de escenarios

| # | Escenario | Resultado esperado |
| --- | --- | --- |
| 1 | Ataque en turno propio contra un rival | Un evento; Vida según §4; `turnsCompleted + 1`; ambos clientes ven lo mismo |
| 2 | Ataque fuera de turno | `NOT_YOUR_TURN`; nada cambia; 0 sorteos |
| 3 | Objetivo inexistente / propio / aliado | `INVALID_TARGET` / `SAME_TEAM_TARGET`; 0 sorteos |
| 4 | Objetivo sin Vida | `TARGET_UNAVAILABLE` |
| 5 | Ataque ≤ Defensa | `effective=false`, daño 0, turno avanza; solo el dado de Ataque |
| 6 | Efecto 0 % | daño 0, turno avanza; sin dado de Daño |
| 7 | Efecto 100 %, 80 %, 60 %, 20 %, crítico | daño = `floor(base × %/100)` |
| 8 | Daño mayor que la Vida restante | Vida en 0, `appliedDamage` = Vida previa |
| 9 | `commandId` repetido | mismo evento al remitente; sin sorteo, sin daño, sin turno, sin difusión |
| 10 | Dos comandos simultáneos | uno gana; el otro `NOT_YOUR_TURN`; sin doble daño ni doble avance |
| 11 | Corte de conexión tras persistir | `resume` reconstruye Vida y turno exactos; nada se recalcula |
| 12 | Recarga (`snapshot` sin `lastSeq`) | Vida y turno actuales |
| 13 | Cambiar el equipo en Player-Inventory después de iniciar | la batalla no cambia; sin llamadas a Player-Inventory por golpe |
| 14 | Sanador atacante, `AI`, daño `PERCENTAGE` | `UNSUPPORTED_COMBAT_PROFILE`; 0 sorteos |
| 15 | Mensaje con `attackValue`/`damage`/`targets` | `MALFORMED_COMMAND` |

## 14. Pendientes

| Punto | Estado |
| --- | --- |
| Bonos de daño del equipamiento y de habilidades | **pendiente**: sin regla que los componga con el dado y el porcentaje (HU-19 / aclaración) |
| Participantes `AI` (JcE) | **pendiente**: sin fuente autoritativa de su perfil de combate |
| Ataque básico de los sanadores (Chamán, Médico) | **pendiente**: el documento oficial no les da Ataque ni Daño; se rechaza |
| Daño con modo `PERCENTAGE` como base | **pendiente**: sin definición formal; se rechaza |
| Poder de batalla (`currentPower`) | HU-11/HU-19; el ataque básico no lo toca |
| Eliminación, ganador y fin de batalla | HU-21 |
| Fuego amigo con excepciones | HU-12 / HU-19 |
| Combat en una sola réplica (serialización y difusión en memoria) | ADR-020 |

## 15. Compatibilidad y orden de despliegue

- **Aditivo:** `battle.combatants` y el evento `basicAttackResolved` no cambian ningún campo ni mensaje de HU-13/HU-17; un cliente que ignore campos desconocidos no se rompe.
- **Orden:** Infrastructure (este contrato) → **Combat** (ejecutar la migración vigente antes de arrancar) → verificar → **Web**. Web nuevo depende del comando `attack` y del evento; no se despliega antes que Combat.
