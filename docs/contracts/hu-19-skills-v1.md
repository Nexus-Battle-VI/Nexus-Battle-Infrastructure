# Contrato HU-19 — Habilidades especiales (v1)

- **Estado:** contrato de la Task [#413](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/413). Lo implementan, en PR propios, Player-Inventory (publica `abilities` en `equipped-hero`), Combat ([#414](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/414)) y Web ([#415](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/415)). Las formas de este documento se **contrastaron con los bytes reales** que Combat envió a dos clientes `ws` en su prueba de extremo a extremo (MongoDB real); **no** se han verificado contra el sistema desplegado ni con navegadores reales: la Task [#416](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/416) sigue **pendiente**. La habilidad **épica** no está implementada (§11, HU-31).
- **Historia:** [HU-19 #63](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/63) · **RF-19** · [EPIC-06 #6](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/6) · Team Alfa · módulo Jugar Online / Combat.
- **Bloqueada por:** HU-11 ([#20](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/20), Poder, cerrada), HU-17 ([#26](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/26), turno, cerrada) y **HU-31 ([#78](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/78), abierta)**. La parte de **épica** depende de HU-31 y **no está definida en esta versión** (§11).
- **Arquitectura aplicada, sin reabrirla:** [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md) (Combat única autoridad), [ADR-020](../adr/ADR-020-realtime-combat.md) (`Accepted`: comandos por WebSocket con `commandId`, `seq`, persistir antes de difundir; nombra el comando `useSkill`) y [ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md) (`Accepted`: aleatoriedad HU-24/HU-25). **No hay ADR nuevo.**
- **Contratos de los que parte:** [HU-18](hu-18-basic-attack-v1.md) (`attack`, snapshot de combate, `command.rejected`), [HU-17](hu-17-battle-turn-order-v1.md) (cola, `seq`, `resume`) y el contrato interno `equipped-hero` de Player-Inventory (§10).
- **Diagramas:** [secuencia](../diagrams/hu-19-sequence-skill.puml), [actividades](../diagrams/hu-19-activity-skill.puml) y [estados de Poder y recarga](../diagrams/hu-19-state-power-cooldown.puml).

## 1. Qué exige la HU y qué no

**Requisito explícito (RF-19, Issue #63):**

- una habilidad especial o épica solo se ejecuta **durante el turno del jugador** y cuando cumple sus condiciones;
- las habilidades especiales **corresponden a la clase** del héroe;
- antes de ejecutar una habilidad especial se **verifica el Poder** disponible y su costo;
- las habilidades especiales **respetan su turno de recarga**; **no** puede usarse una que siga en recarga;
- después de una ejecución válida: el **efecto se aplica**, el **Poder se actualiza** cuando corresponde y la habilidad **queda marcada con su recarga**;
- la épica no consume Poder y tiene recarga de dos turnos (§11).

**Requisito explícito de HU-11 ([#20](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/20)), que este contrato aplica:** «Si el héroe no cuenta con Poder suficiente para ejecutar una habilidad especial o épica, el sistema debe **forzar el uso del ataque básico** (sin costo de Poder) en ese turno» (CA-01: «degradando la acción a ataque básico»). Por eso el **Poder insuficiente no es un rechazo**: la acción se degrada (§4.3). En cambio, una habilidad **en recarga** sí se rechaza (HU-19, «no debe permitirse»).

**Fuente oficial del juego:** «Proyecto Integrador II», §6.1.2 y Tabla 7: los héroes «cuentan con tres acciones especiales que mejoran su ataque o defensa. Estas acciones solo aplican en el turno, tiene un turno de carga y son afectadas por el multiplicador asociado al nivel». Tabla 6 (Poder inicial y dados), Tabla 20 (épicas).

### Clasificación de lo decidido

| # | Tipo | Contenido |
| --- | --- | --- |
| 1 | Requisito explícito | Las reglas de RF-19 y de HU-11 citadas arriba. |
| 2 | Fuente oficial | Tabla 7 (acciones, costo de Poder, efecto), §6.1.2 («solo aplican en el turno», «un turno de carga»). |
| 3 | Decisión arquitectónica `Accepted` | Combat es la única autoridad; comando `useSkill` con `commandId`; persistir antes de difundir; `seq` (ADR-019/020/021). |
| 4 | Decisión técnica **confirmada por el PO por chat externo el 2026-09-21** (no consta en el Issue) | (a) la habilidad es **la acción del turno**: un ataque mejorado cuyos modificadores propios valen solo para esa resolución (§4); (b) recarga = bloqueada durante los **N turnos propios siguientes** (§5.3); (c) el Poder se regenera **+2 al comenzar el turno propio**, con tope (§5.2); (d) las habilidades llegan a Combat **ampliando de forma aditiva** el contrato `equipped-hero` de Player-Inventory y se **congelan** al iniciar (§10). El PO indicó además **guiarse por el documento oficial** cuando el Catalog y el documento difieran (§16). |
| 5 | Decisión técnica del autor | Orden de sorteos (§4.2), `skillUsed`, `degradedFrom`, códigos de error, forma de la vista pública, criterio de «efecto soportado» (§10.2). Ninguna es un requisito. |
| 6 | Pendiente / bloqueado | §11 (épica) y §16. |

## 2. Transporte: comando `useSkill` por el WebSocket de ADR-020

**No hay endpoint REST.** El atacante **no viaja**: se deriva del `sub` autenticado de la conexión y del turno vigente.

```jsonc
// Cliente → servidor (máx. 16 KiB, como todo mensaje)
{
  "type": "useSkill",
  "commandId": "6f0b6f0e-…",                    // UUID generado por el cliente, 1..100 caracteres
  "roomId": "aaaaaaaa-…",                       // UUID v4 de la sala
  "abilityId": "2e97537a-…",                    // id de la habilidad (producto HABILIDAD de Catalog), UUID
  "target": { "teamLabel": "B", "seat": 0 }     // UN objetivo: identidad estable del participante
}
```

- **Exactamente esas cinco claves.** Cualquier otra (`effects`, `cost`, `power`, `cooldown`, `damage`, `attackBonus`, `heroId`, `targets`, `area`, …) hace el comando **mal formado** (`MALFORMED_COMMAND`, 0 sorteos): el servidor no las ignora en silencio.
- `abilityId` es **solo un identificador**: el nombre, el costo, la recarga y los efectos salen del **snapshot** que Combat congeló al iniciar (§5.1), nunca del cliente.
- `target` es un objeto `{teamLabel, seat}` (misma `memberKey` de HU-17). No se usa `heroId`.
- La conexión debe estar **autenticada** por ticket (ADR-020); sin autenticar se cierra con `4401`.
- Los comandos de combate de una conexión (`attack`, `useSkill`) se atienden **de uno en uno, en orden de llegada**.
- **La épica no tiene comando en esta versión** (§11): no existe `kind`, `epic` ni ranura en el mensaje.

## 3. Orden de validación (todo **antes** de consumir un solo sorteo)

Una petición inválida consume **0 índices** de la secuencia HU-24 y **no modifica nada** (ni Poder, ni recarga, ni turno).

| # | Comprobación | Código |
| --- | --- | --- |
| 1 | Forma del mensaje (claves exactas, tipos, `roomId` UUID v4, `abilityId` UUID, `target` objeto) | `MALFORMED_COMMAND` |
| 2 | `commandId` cadena de 1 a 100 caracteres | `INVALID_COMMAND_ID` |
| 3 | La sala existe | `ROOM_NOT_FOUND` |
| 4 | El solicitante es participante `HUMAN` de la sala | `NOT_A_PARTICIPANT` |
| 5 | **`commandId` ya procesado** → se devuelve el resultado guardado (§8), sin validar turno ni sortear | — (idempotente) |
| 6 | La sala está `IN_BATTLE` | `BATTLE_NOT_ACTIVE` |
| 7 | El solicitante es el participante de la posición activa | `NOT_YOUR_TURN` |
| 8 | El objetivo existe en la batalla | `INVALID_TARGET` |
| 9 | El objetivo **no** es del equipo del actor (incluido él mismo) | `SAME_TEAM_TARGET` |
| 10 | Actor y objetivo tienen perfil de combate y Vida > 0 | `UNSUPPORTED_COMBAT_PROFILE`, `ACTOR_UNAVAILABLE`, `TARGET_UNAVAILABLE` |
| 11 | La batalla tiene el estado de habilidades (Poder y habilidades congelados) | `SKILLS_NOT_AVAILABLE` |
| 12 | `abilityId` es **una de las habilidades del héroe del actor** (CA-02: habilidades de otra clase quedan fuera) | `UNKNOWN_SKILL` |
| 13 | Todos los efectos de la habilidad están **formalmente soportados** (§10.2) | `UNSUPPORTED_SKILL_EFFECT` |
| 14 | La habilidad **no está en recarga** (CA-04, CA-07) | `SKILL_ON_COOLDOWN` |
| 15 | Poder suficiente (CA-03): si **no**, **no es error**: se degrada a ataque básico (§4.3) | — |
| 16 | Ataque numérico y Daño soportado del actor (§4 de HU-18) | `UNSUPPORTED_COMBAT_PROFILE` |

El orden 13 → 14 → 15 es deliberado: una habilidad que el sistema **no sabe ejecutar** se rechaza antes de hablar de Poder (no se «fuerza» un ataque por una habilidad que nunca podría ejecutarse), y la recarga se comprueba antes que el Poder.

## 4. Resolución: la habilidad es la acción del turno

**Decisión confirmada por el PO (§1, #4a).** Tabla 7 describe acciones que «mejoran su ataque o defensa» y «solo aplican en el turno», y cada jugador «ejecuta una acción por turno» (§6.1.3). Se lee así: **usar una habilidad es la acción del turno** y se resuelve como **un ataque mejorado** contra el objetivo elegido, con los modificadores propios de la habilidad **solo para esa resolución**. HU-20 (`prepareAttack`, `ResolveAttack`) y HU-25 (`ResolveRandomEffect`) **se reutilizan, no se reescriben**.

### 4.1 Composición

```text
Ataque final  = ( Ataque efectivo − lo que resta el equipo del objetivo )        HU-20
              + bono de Ataque de la habilidad (fijo + dados)                    HU-19
              + dado de Ataque de la Tabla 6                                     HU-20
efectivo?     = Ataque final > Defensa del objetivo   (la igualdad NO supera)    HU-20
efecto        = ResolveRandomEffect (solo si es efectivo)                        HU-25
dañoBase      = tirada del Daño del héroe (DICE) o su valor fijo
              + bono de Daño de la habilidad (fijo + dados)                      HU-19
dañoCalculado = floor( dañoBase × porcentaje / 100 )                             aclaración #62
dañoAplicado  = min( dañoCalculado, Vida actual del objetivo )
```

- **Ataque y Daño no se confunden**: nunca `Vida −= Ataque` ni `daño = Ataque − Defensa`.
- El bono de Daño **se suma al daño base antes** de aplicar el porcentaje del efecto. El documento oficial no dice si el porcentaje (crítico, resistencia…) actúa sobre el bono; esta es la lectura más simple y **queda registrada como decisión técnica pendiente de confirmar** (§16), igual que el crítico 120–180 % de HU-20.
- La Defensa solo participa en la comparación (HU-20); no reduce además el daño.
- «Multiplicador asociado al nivel» (§6.1.2): **no se aplica**. El dominio no tiene nivel ni fórmula; no se inventa.

### 4.2 Consumo de la secuencia aleatoria (HU-24), en este orden exacto

| Paso | Sorteos | Cuándo |
| --- | --- | --- |
| 1. Dados del **bono de Ataque** de la habilidad (en el orden de sus efectos) | suma de `count` | siempre que la habilidad tenga un bono de Ataque en dados |
| 2. Dado de Ataque | `dice.count` (1 con la Tabla 6) | siempre que el actor lleve dado (HU-20, sin cambios) |
| 3. Efecto | **1** | solo si el golpe es efectivo (HU-20, sin cambios) |
| 4. Dado de Daño del héroe | `damage.count` | solo si es efectivo **y** el porcentaje es > 0 **y** el Daño es `DICE` |
| 5. Dados del **bono de Daño** de la habilidad | suma de `count` | solo si es efectivo **y** el porcentaje es > 0 |

Los dados del bono de Ataque se tiran **antes** que el de Ataque porque `ResolveAttack` tira el suyo al invocarse y compara enseguida: así HU-20 no cambia. Con un efecto del 0 % el daño es 0 sea cual sea el dado: **no se consume aleatoriedad que no puede afectar al resultado**. Todo sale de `RandomSequencePort.nextIndex()` y la cara de un dado es `dieFaceFromIndex` (mismo mapeo que HU-20 y HU-18); no hay `Math.random` ni otro generador.

### 4.3 Poder insuficiente: se degrada a ataque básico (HU-11)

Si el Poder actual **no alcanza** el costo (`FIXED n`: `actual < n`; `ALL_AVAILABLE`: `actual = 0`, porque debe consumir al menos un punto):

- la habilidad **no se ejecuta**: el Poder **no cambia** y la habilidad **no queda en recarga**;
- Combat ejecuta **en ese mismo turno un ataque básico** contra el objetivo del comando, con las reglas y el consumo de sorteos de [HU-18](hu-18-basic-attack-v1.md) (costo 0);
- el evento es `basicAttackResolved` con el campo adicional `degradedFrom` (§6.2): Web muestra por qué.

Un ataque básico que HU-18 rechazaría (objetivo inválido, actor sin Ataque…) se rechaza igual con su código; nada cambia.

## 5. Estado de batalla: Poder, habilidades y recarga

Combat es la **fuente de verdad** del Poder y de la recarga durante la batalla. El **snapshot de combate** de HU-18 se amplía (aditivo) con, por participante:

| Campo interno | Origen |
| --- | --- |
| `maxPower` | `effectiveStats.power` de Player-Inventory (HU-11: base de Catalog + modificadores permanentes del equipo) |
| `currentPower` | inicia en `maxPower` (HU-11: «arranca completo») |
| `abilities[]` | las habilidades del héroe que publica Player-Inventory (§10): `abilityId`, `name`, costo, `chargeTurns`, efectos |
| `cooldowns` | por habilidad: turnos propios que le faltan; solo se guardan los > 0 |

### 5.1 Se congela al iniciar

Con la **misma respuesta** de Player-Inventory que `StartBattle` ya obtiene para revalidar HU-16 (sin segunda llamada). **No hay llamadas a Player-Inventory ni a Catalog por acción.** Cambiar el equipo o el Catalog después de iniciar no modifica la batalla.

### 5.2 Poder (HU-11, política `HeroPowerPolicy` ya espejada en Combat)

| Regla | Comportamiento |
| --- | --- |
| Inicio | `actual = máximo` |
| Consumo | una habilidad ejecutada válidamente descuenta su costo (`FIXED n`; `ALL_AVAILABLE` descuenta todo el saldo, mínimo 1) |
| Ataque básico | costo 0: **no lee ni escribe** el Poder del atacante |
| Regeneración | **+2** al **comenzar el turno propio**, sin superar el máximo (decisión confirmada, §1 #4c). Al avanzar el turno, el participante que pasa a ser el activo recibe +2. El primer turno no regenera (inicia completo) |
| Límites | `0 ≤ actual ≤ máximo`, siempre |
| Fin de batalla | restaurar al máximo es responsabilidad de HU-21 (fin de batalla) |
| Identidad | el Poder es de **cada participante** `(teamLabel, seat)`, nunca del `heroId`: dos jugadores con el mismo héroe no comparten saldo |

### 5.3 Recarga (turno de carga)

Fuente: Catalog v1 `HABILIDAD.chargeTurns = 1` («tiene un turno de carga», Tabla 7); la épica lleva `cooldownTurns = 2`. **Decisión confirmada (§1 #4b):** tras usar una habilidad en el turno propio **T**, queda **bloqueada durante los `N` turnos propios siguientes** y vuelve a estar disponible en el turno propio `T + N + 1`.

- `cooldownRemaining` = turnos propios que **faltan**; tras usar la habilidad vale `N`. **Disminuye en 1 al cerrar cada turno propio** del participante. Mientras sea > 0 está bloqueada (`SKILL_ON_COOLDOWN`); con 0 está disponible.
- Ejemplo con `N = 1`: usada en T → bloqueada en T + 1 → disponible en T + 2. Con `N = 2` (épica): bloqueada en T + 1 y T + 2, disponible en T + 3.
- La recarga es **por participante y por habilidad**; usar otra habilidad no la altera.
- Una acción **rechazada** o **degradada** (Poder insuficiente) **no** marca recarga.
- Cuenta **turnos propios**, no rondas ni tiempo real.

### 5.4 Vista pública (`BattleView`, aditiva)

Web recibe lo necesario para pintar Poder, habilidades y recarga; **no** recibe Ataque, Defensa, Daño ni `activeEffects`, y **tampoco los efectos de la habilidad**. Cada elemento de `combatants` (mismo orden que la cola) se amplía con:

```jsonc
{ "teamLabel": "A", "seat": 0,
  "health": { "current": 44, "max": 44 },
  "power":  { "current": 8, "max": 10 },                       // null sin perfil o en batalla anterior a HU-19
  "skills": [                                                  // [] sin perfil o en batalla anterior a HU-19
    { "abilityId": "2e97537a-…", "name": "Golpe con escudo",
      "powerCost": { "mode": "FIXED", "amount": 2 },            // o { "mode": "ALL_AVAILABLE" }
      "chargeTurns": 1,
      "cooldownRemaining": 1,
      "status": "RECHARGING" }                                  // READY | RECHARGING | UNSUPPORTED
  ] }
```

- `status` lo decide **Combat** (Web no decide si la recarga terminó ni si la habilidad es ejecutable): `RECHARGING` si `cooldownRemaining > 0`; `UNSUPPORTED` si algún efecto no está soportado (§10.2); si no, `READY`. **El Poder no cambia el estado**: con Poder insuficiente sigue `READY` porque la acción se degrada (§4.3); Web muestra el costo junto al medidor y Combat decide.
- La vista es **idéntica** para todos los participantes (los mismos bytes se persisten y se difunden). El Poder y las habilidades de un héroe no son secretos (Tabla 7 es pública).

## 6. Eventos

**Un único evento por acción**, con el estado ya avanzado (mismo criterio que HU-18): un solo `seq`, Web nunca ve el Poder nuevo con el turno viejo, `resume` reproduce exactamente la acción.

### 6.1 `skillUsed` (habilidad ejecutada)

```jsonc
{
  "type": "skillUsed",
  "seq": 3, "roomId": "…", "occurredAt": "2026-09-21T10:02:00.000Z",
  "commandId": "6f0b6f0e-…",
  "completedPosition": 0,
  "actor":  { "teamLabel": "A", "seat": 0 },
  "target": { "teamLabel": "B", "seat": 0 },
  "skill": { "abilityId": "2e97537a-…", "name": "Golpe con escudo",
             "powerCost": { "mode": "FIXED", "amount": 2 }, "chargeTurns": 1 },
  "power":    { "before": 10, "after": 8 },          // del actor: antes y después de pagar
  "cooldown": { "remainingTurns": 1 },               // lo que le falta a ESTA habilidad tras la acción
  "bonus":    { "attack": 2, "damage": 1 },          // lo que aportó la habilidad; damage null si no se tiró
  "resolution": { /* igual que en basicAttackResolved (HU-18) */ },
  "targetHealth": { "before": 40, "after": 33 },
  "battle": { /* BattleView posterior: Vida, Poder, recargas y turno avanzado */ }
}
```

- `resolution.attackValue` **ya incluye** el bono de Ataque; `bonus.attack` permite explicarlo («10 + 4 + 2 contra 11»). `resolution.baseDamage` incluye el bono de Daño; `bonus.damage` es `null` si el golpe no fue efectivo o el efecto fue 0 %.
- **Minimización:** no viajan la tirada del dado de Ataque por separado, los efectos de la habilidad, `activeEffects`, estadísticas, índices ni la semilla.

### 6.2 `basicAttackResolved` con `degradedFrom` (Poder insuficiente)

El evento de HU-18 **sin cambios**, más un campo **opcional** que solo existe cuando una `useSkill` se degradó:

```jsonc
{ "type": "basicAttackResolved", "…": "…igual que HU-18…",
  "degradedFrom": { "command": "useSkill", "abilityId": "2e97537a-…", "reason": "INSUFFICIENT_POWER" } }
```

`turnAdvanced` (HU-17) no cambia.

**`command.rejected`** (solo a quien envió el comando; el estado no cambia): `{ "type": "command.rejected", "command": "useSkill", "commandId": "…", "code": "SKILL_ON_COOLDOWN" }` — mismo formato que HU-13/HU-18. Web decide por `code`, **nunca** por texto.

## 7. Atomicidad, persistencia y publicación

Una acción es **una sola transición lógica del agregado** `BattleRoom` con **una sola escritura** (bloqueo optimista por `version`): Vida del objetivo + Poder del actor + recarga + evento con su `seq` + `commandId` procesado + turno avanzado (con el cierre de recarga del actor y la regeneración del siguiente), en **una** versión nueva. **Persistir antes de difundir.** Nunca dos escrituras. Si el `save` falla, no se difunde nada.

## 8. Idempotencia y concurrencia

- **`commandId` repetido:** se reconoce por `handledCommands` **antes** de validar turno. Se devuelve **ese mismo evento persistido solo a quien lo repite**: no sortea, no descuenta Poder, no marca recarga, no avanza el turno y no difunde. Vale igual para una acción degradada. Los `commandId` son únicos por sala y **comunes a `attack` y `useSkill`**.
- **Doble envío / dos pestañas:** solo **uno** muta; el otro recibe `NOT_YOUR_TURN` sin consumir sorteos: **no hay doble consumo de Poder ni doble recarga**.
- **Serialización por sala** (una réplica, ADR-020) y **nunca se vuelve a sortear tras un conflicto de versión** (se relee; si el `commandId` ya está procesado se devuelve ese resultado; si no, `COMMAND_CONFLICT` y el cliente reintenta con el **mismo** `commandId`).

## 9. Errores (códigos estables)

Web decide por `code`; los textos son de la interfaz. Se **reutilizan** los de HU-18 y se **añaden** cuatro.

| Código | Cuándo | Origen |
| --- | --- | --- |
| `MALFORMED_COMMAND` | claves de más o de menos, tipos incorrectos, `roomId` no UUID v4, `abilityId` no UUID, `target` no objeto | HU-18 |
| `INVALID_COMMAND_ID`, `ROOM_NOT_FOUND`, `NOT_A_PARTICIPANT`, `BATTLE_NOT_ACTIVE`, `NOT_YOUR_TURN` | ver §3 | HU-17/HU-18 |
| `INVALID_TARGET`, `SAME_TEAM_TARGET`, `TARGET_UNAVAILABLE`, `ACTOR_UNAVAILABLE`, `UNSUPPORTED_COMBAT_PROFILE` | ver §3 | HU-18 |
| `SKILLS_NOT_AVAILABLE` | la batalla no tiene estado de habilidades (iniciada antes de HU-19) | **nuevo** |
| `UNKNOWN_SKILL` | `abilityId` no es una habilidad del héroe del actor (incluye habilidades de otra clase) | **nuevo** |
| `UNSUPPORTED_SKILL_EFFECT` | algún efecto de la habilidad no está formalmente soportado (§10.2); no se ejecuta nada | **nuevo** |
| `SKILL_ON_COOLDOWN` | la habilidad sigue en recarga | **nuevo** |
| `COMMAND_CONFLICT`, `INTERNAL_ERROR` | conflicto de versión no resoluble / fallo inesperado | HU-18 |

**El Poder insuficiente no es un código de error** (§4.3). Un `commandId` repetido **no** es un error.

## 10. De dónde salen las habilidades

### 10.1 Ruta de datos (decisión confirmada, §1 #4d)

```text
Catalog  ─(producto HEROE.abilities = ids de HABILIDAD)─►  Player-Inventory  ─(equipped-hero.abilities)─►  Combat
   ▲ fuente de los datos                                     resuelve y normaliza (una vez por petición)        congela al iniciar
```

Player-Inventory ya lee Catalog (HU-07/HU-28) y **no** hay topología nueva: Combat sigue hablando con **un solo** servicio para el héroe. Se amplía **de forma aditiva** `GET /api/internal/v1/players/{playerId}/equipped-hero` con:

```jsonc
"abilities": [
  { "abilityId": "2e97537a-…",              // productId de Catalog
    "reference": "golpe-con-escudo",         // alias (sku) si Catalog lo publica
    "name": "Golpe con escudo",
    "powerCost": { "mode": "FIXED", "amount": 2 },   // o { "mode": "ALL_AVAILABLE" }
    "chargeTurns": 1,
    "effects": [ { "kind": "STAT_MODIFIER", "target": "SELF", "statistic": "ATTACK",
                   "operation": "INCREASE", "magnitude": { "mode": "FIXED", "amount": 2 },
                   "hasActivationCondition": false } ] }
]
```

- **Lista blanca campo a campo**, sin `raw` ni la condición de activación (solo su indicador), igual que `activeEffects`. Mismo orden que `abilities` del héroe en Catalog. Una habilidad que Catalog no resuelva o cuyos atributos no cumplan el contrato canónico **se omite** (no se inventa) y no tumba la respuesta; el héroe simplemente no la tiene.
- **Combat exige el campo** (no lo sustituye por `[]`): igual que `activeEffects`, un `equipped-hero` sin `abilities` es una respuesta inválida (`503`, sin inventar). **Por eso Player-Inventory se despliega primero** (§17).
- Costos y recarga se toman **tal como los publica Catalog** (`powerCostMode`/`powerCost`, `chargeTurns`).

### 10.2 Qué efectos están soportados

El Catalog v1 puede describir efectos que el documento oficial no define con precisión (duración, condición, sanación, reanimación, inmunidad, reflejo, efectos sobre el oponente). **Se ejecuta únicamente lo formalmente soportado**; lo demás se **rechaza explícitamente** (`UNSUPPORTED_SKILL_EFFECT`, y `status = UNSUPPORTED` en la vista) sin mutar nada — no se aplica a medias, no se descarta en silencio.

Una habilidad está **soportada** si **todos** sus efectos cumplen: `kind = STAT_MODIFIER` · `target = SELF` · `operation = INCREASE` · `statistic ∈ {ATTACK, DAMAGE}` · `magnitude ∈ {FIXED, DICE}` (entero ≥ 1; dados con `count ≥ 1` y `sides ≥ 2`) · **sin** `durationTurns` · **sin** condición de activación. Es exactamente el patrón «`+N` (o `+NdM`) al ataque / al daño» de la Tabla 7 que se aplica a **esa** acción.

Sobre los datos publicados en el Catalog desplegado a 2026-09-21 (24 habilidades, leídas por la API pública de solo lectura):

| Clase | Soportadas | No soportadas (motivo) |
| --- | --- | --- |
| Guerrero Tanque | Golpe con escudo | Mano de piedra (defensa: exige estado más allá del turno) · Defensa feroz (inmunidad) |
| Guerrero Armas | Embate sangriento · Lanza de los dioses · Golpe de tormenta | — |
| Mago Fuego | Misiles de magma · Vulcano | Pare de fuego (condición y reflejo de daño) |
| Mago Hielo | Lluvia de hielo | Cono de hielo (efecto sobre el oponente con duración) · Bola de hielo (efecto sobre el oponente) |
| Pícaro Veneno | Flor de loto | Agonía (codificada como `DAMAGE` sobre el oponente, sin semántica definida) · Piquete (duración) |
| Pícaro Machete | Machetazo · Planazo | Cortada (duración) |
| Chamán | — | Toque de la Vida · Vínculo Natural · Canto del Bosque (sanación, grupo, duración) |
| Médico | — | Curación Directa · Neutralización de Efectos · Reanimación (sanación y reanimación) |

**10 de 24 soportadas** en esta versión. Un cambio en el Catalog cambia esta tabla sin tocar código; una regla nueva (p. ej. duración, sanación, reanimación) requiere una **versión nueva de este contrato**.

## 11. Épica — **bloqueada (HU-31)**: no definida en v1

Lo que **está** definido: la épica **no consume Poder** (`powerCost: 0`) y tiene **dos turnos de recarga** (`cooldownTurns: 2`); el bono adicional por coincidencia de tipo lo resuelve `applyEpicEffects` de Player-Inventory (HU-31, ya integrado como resolver puro, sin ejecutar efectos).

Lo que **no está** definido y por eso **no se implementa ni se inventa** (auditoría de HU-31, [#78](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/78), 2026-09-21):

1. **No existe fuente ni estado persistido de «épica activa/equipada»** (`HeroLoadout` no tiene ranura de épica; HU-28 excluye épicas; HU-32 solo define cómo se obtiene). Quién la posee, dónde se persiste, cuántas puede activar un héroe, si ocupa ranura, cómo se selecciona y cuándo puede cambiarse **lo decide el PO/arquitectura**. No hay `activeEpic`, `epicSlot` ni equivalente en este contrato.
2. **Catalog v1 solo admite un efecto específico por épica** (`EpicAttributes.specificEffect`), y al menos cinco de las ocho filas de la Tabla 20 combinan varios componentes (p. ej. +4 daño **y** +2 % de crítico). Requiere el proceso de contrato/ADR con Catalog e Infrastructure.

Cuando ambos se resuelvan, se publica **`hu-19-skills-v2`**: comando/`kind` para la épica, costo 0, recarga 2 y la salida de `applyEpicEffects`, reutilizando la misma máquina de estados de Poder y recarga de este contrato.

## 12. Seguridad y minimización

- El navegador **nunca** envía Poder, costo, recarga, efectos, bono, daño, Vida, semilla ni turno: solo `roomId`, `commandId`, `abilityId` y el objetivo. Combat deriva al actor del `sub` de la conexión y del turno, y la habilidad del snapshot.
- Nunca viajan semilla, estado del generador, índices ni resultados futuros; tampoco inventario, `activeEffects` crudos ni los efectos de la habilidad.
- No se registran JWT, tickets, semilla ni carga completa; sí `roomId`, `commandId`, `abilityId`, tipo de evento, `seq` y resultado.

## 13. Límites con otras historias

- **HU-12 (fuego amigo, abierta):** las habilidades soportadas atacan, así que **rechazan** objetivos del mismo equipo (`SAME_TEAM_TARGET`). Curar o potenciar a un aliado o a un grupo depende de HU-12 y **no** se implementa.
- **HU-21 (fin de batalla, abierta):** una Vida en 0 no finaliza la batalla; no hay ganador, reanimación ni restauración de Poder al terminar.
- **Sanadores (Chamán, Médico):** el documento no les da Ataque ni Daño (HU-18 rechaza su ataque básico) y HU-16 los excluye del 1 contra 1. Sus habilidades quedan **no soportadas** hasta que exista su acción base y HU-12/HU-21.
- **HU-29 (bloqueo de equipamiento):** el snapshot congelado es compatible.
- **HU-11:** Combat reimplementa la política de Poder con los mismos vectores (ADR-001); Web ya tiene el medidor (`PowerMeter`), sin montar hasta que exista el evento con el Poder (este contrato).

## 14. Persistencia y migración

`battle-rooms` amplía el validador `$jsonSchema` con una migración **aditiva** (siguiente libre a la fecha: `008`; la `007` es de HU-18): en `battle.combatants[].profile` los campos opcionales `maxPower` y `abilities`, en `battle.combatants[]` los opcionales `currentPower` y `cooldowns`, y el tipo de evento `skillUsed`. Documentos sin esos campos siguen siendo válidos y se restauran **sin** estado de habilidades (`SKILLS_NOT_AVAILABLE`); **no hay backfill** ni se consulta a Player-Inventory al restaurar.

## 15. Matriz de escenarios

| # | Escenario | Resultado esperado |
| --- | --- | --- |
| 1 | Habilidad soportada, Poder suficiente, turno propio | `skillUsed`; Poder − costo; recarga = `N`; Vida según §4; turno + 1 |
| 2 | Poder exactamente igual al costo (frontera) | se ejecuta; Poder queda en 0 |
| 3 | Poder un punto por debajo del costo (frontera) | `basicAttackResolved` con `degradedFrom`; Poder y recarga intactos |
| 4 | Habilidad en recarga | `SKILL_ON_COOLDOWN`; nada cambia; 0 sorteos |
| 5 | Recarga: usada en T, T + 1 y T + 2 (con `N = 1`) | T + 1 rechazada; T + 2 disponible |
| 6 | Habilidad de otra clase / inexistente | `UNKNOWN_SKILL`; 0 sorteos |
| 7 | Habilidad con efecto no soportado (duración, sanación…) | `UNSUPPORTED_SKILL_EFFECT`; nada cambia; **no** se degrada |
| 8 | Fuera de turno / actor ajeno / no participante | `NOT_YOUR_TURN` / `NOT_A_PARTICIPANT`; nada cambia |
| 9 | Objetivo inválido / aliado / sin Vida | `INVALID_TARGET` / `SAME_TEAM_TARGET` / `TARGET_UNAVAILABLE` |
| 10 | Ataque final ≤ Defensa | `effective=false`, daño 0; **Poder gastado y recarga marcada igualmente**; turno avanza |
| 11 | Efecto 0 % | daño 0; sin dados de daño; Poder y recarga aplicados |
| 12 | Bono en dados (Golpe de tormenta, Vulcano…) | sorteos en el orden de §4.2; `bonus` lo refleja |
| 13 | `commandId` repetido | mismo evento al remitente; sin sorteo, sin Poder, sin recarga, sin turno, sin difusión |
| 14 | Dos envíos simultáneos | uno gana; el otro `NOT_YOUR_TURN`; **un solo** consumo de Poder y **una sola** recarga |
| 15 | Turno del siguiente | recibe +2 de Poder (tope al máximo) y `cooldownRemaining` del actor anterior baja 1 |
| 16 | Ataque básico | no cambia el Poder del atacante; sí cierra la recarga de sus habilidades |
| 17 | Corte de conexión tras persistir | `resume` reconstruye Poder, recargas, Vida y turno exactos |
| 18 | Batalla iniciada antes de HU-19 | `SKILLS_NOT_AVAILABLE`; el ataque básico sigue funcionando |
| 19 | Mensaje con `effects`/`cost`/`power`/`targets` | `MALFORMED_COMMAND` |
| 20 | Épica | **sin escenario**: bloqueada (§11) |

## 16. Pendientes y divergencias

| Punto | Estado |
| --- | --- |
| Épica activa (dueño, persistencia, cardinalidad, selección) | **bloqueado (HU-31)**: decide el PO/arquitectura; no se implementa |
| Catalog v1 con un solo efecto específico por épica | **bloqueado**: proceso de contrato/ADR con Catalog e Infrastructure |
| Efectos con duración, condición, sanación, reanimación, inmunidad, reflejo y efectos sobre el oponente | **pendiente**: sin regla formal; se rechazan (`UNSUPPORTED_SKILL_EFFECT`). Requieren estado de batalla más allá del turno y HU-12/HU-21 |
| Acción base de los sanadores | **pendiente**: HU-18 rechaza su ataque; sin ella sus habilidades no tienen sentido |
| El porcentaje del efecto sobre el bono de Daño (§4.1) | **decisión técnica pendiente de confirmar por el PO** |
| Efectos temporales/condicionados **del equipamiento** (`activeEffects`) | **pendiente**: HU-18 los dejó para HU-19, pero el texto de HU-19 no los pide; no se evalúan. Confirmar con el PO si deben entrar |
| «Multiplicador asociado al nivel» | **no aplicado**: no hay nivel ni fórmula en el dominio |
| Restauración del Poder al terminar la batalla | HU-21 |
| Objetivos aliados y de grupo | HU-12 |
| Participantes `AI` (JcE) | sin perfil de combate; se rechazan (`UNSUPPORTED_COMBAT_PROFILE`), como en HU-18 |
| Combat en una sola réplica (serialización y difusión en memoria) | ADR-020 |

**Divergencias detectadas entre el Catalog desplegado y el documento oficial** (mi lectura de un PDF convertido con columnas partidas; **verificar contra el original**). El PO indicó guiarse por el documento; aquí **no cambian el comportamiento** porque las habilidades afectadas no están soportadas, pero deben corregirse en el Catalog antes de soportarlas:

- **Reanimación** cuesta `FIXED 6` en el Catalog; el documento dice «todos los puntos de poder» (`ALL_AVAILABLE`, que el contrato de Catalog v1 sí admite).
- **Defensa feroz** solo lleva inmunidad al daño físico; el documento añade «(3d6) al daño mágico».
- **Pare de fuego** y **Bola de hielo**: el documento trae marcadores sin definir (`(0dx)`, `(0d4)`) y el Catalog los cargó como 100 % de reflejo y `1d4`.
- **Té changua** tiene en el Catalog un efecto general (curación de grupo 4d8); la Tabla 20 marca el general como «No aplica». **Intimidación sangrienta** parece tener un efecto general distinto.
- A las **épicas** les falta la parte de crítico de su efecto específico (consecuencia del bloqueo 2).

## 17. Compatibilidad y orden de despliegue

- **Aditivo:** `power`, `skills`, `skillUsed` y `degradedFrom` no cambian ningún campo ni mensaje de HU-13/HU-17/HU-18; un cliente que ignore campos desconocidos no se rompe.
- **Orden:** Infrastructure (este contrato) → **Player-Inventory** (`abilities` en `equipped-hero`; verificar el endpoint) → **Combat** (ejecutar `npm run migrate` antes de arrancar) → verificar → **Web**. Combat exige `abilities` y falla el ingreso a sala (`503`) si Player-Inventory aún no lo publica; Web nuevo depende del comando y de los campos nuevos y no se despliega antes que Combat.
- **Validación integrada (Task [#416](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/416)):** requiere el sistema desplegado en ese orden; hasta entonces las pruebas automatizadas del protocolo no sustituyen la evidencia de integración.
