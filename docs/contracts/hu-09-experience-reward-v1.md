# Contrato HU-09 — Recompensa de experiencia por derrota de un rival (v1)

- **Estado:** diseño de la Task [#439](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/439). Lo que este documento llame «implementado» solo lo estará cuando lo integren las Tasks [#440](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/440) (Combat), [#441](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/441) (Player-Inventory), [#442](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/442) (Missions) y [#443](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/443) (Web); la validación integrada es la Task [#444](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/444). Hasta entonces todo lo de este documento es **diseño**.
- **Historia:** [HU-09 #18](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/18) · `RF-09` · [EPIC-01 #1](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/1) · Team Alfa (Player/Inventory) + Team Beta (Missions) + Team Alfa (Combat) · `ACT-02 — Preparar héroe, equipo e inventario` → `Gestionar progresión y Poder`.
- **Bloqueada por:** `HU-08` ([#17](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/17)), **entregada en los PRs [Nexus-Battle-Player-Inventory#42](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/42), [#43](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/43) y [#44](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/44)**, pendientes de merge; y `HU-24` ([#71](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/71)), **cerrada**. Consume el umbral de niveles de HU-08 y el motor de aleatoriedad de HU-24 sin reabrir ninguno de los dos.
- **Arquitectura aplicada, sin reabrirla:** [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md) (Player/Inventory es dueño del estado del héroe y solo él escribe su Mongo; HMAC interno; listas cerradas de servicios por ruta) y [ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md) (Combat es la única autoridad de aleatoriedad; no hay `/random`, `/rng` ni `/seed`, ni microservicio de RNG).
- **Aclaración funcional del PO:** la fórmula `10 × 1,2^(1d8)` pertenece a la **muerte de un rival NPC en una misión (JvE)**; **no** se otorga por PvP ni por «Jugar Online». Missions coordina y calcula la recompensa; Combat no conoce la fórmula. Registrada en el comentario de trazabilidad de [#18](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/18).
- **Unidad de la recompensa (decidida):** **una recompensa, una tirada y una acreditación por cada NPC derrotado**, identificadas por la **instancia real de la derrota** (encuentro + enemigo), no por el arquetipo. Ver §4.
- **Diagramas:** [caso de uso](../diagrams/hu-09-use-case.puml), [actividad](../diagrams/hu-09-activity.puml), [secuencia](../diagrams/hu-09-sequence.puml), [dominio](../diagrams/hu-09-domain.puml).
- **Contratos vecinos, referenciados y no reabiertos:** [hu-72-mission-simulation-v1](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/132) (**propuesta abierta, sin mergear**), [hu-74-mission-report-v1](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/135) (**propuesta abierta, sin mergear**) y [hu-22-reward-contract-v1](hu-22-reward-contract-v1.md) §7, que es la **plantilla** del endpoint interno de acreditación.

## 1. Qué exige la HU y qué no

**Requisito explícito (`RF-09`, Issue #18):**

- al terminar un combate con victoria se calcula y se acredita al héroe ganador una cantidad de experiencia igual a `10 × 1,2^(1d8)`;
- `1d8` es un entero pseudoaleatorio entre 1 y 8 obtenido del motor centralizado de HU-24; **HU-09 no lo genera localmente**;
- el valor de `1d8` se usa como **exponente**: no se suma ni se multiplica directamente;
- la experiencia se **acumula** a la que el héroe ya tenía; no la reemplaza;
- después de acreditarla se verifica el umbral del siguiente nivel con las reglas de **HU-08** y, si se alcanza, se ejecuta la progresión;
- si no existe un resultado válido que dé derecho a la recompensa, **no se otorga**.

### 1.1 Clasificación de lo decidido

| # | Tipo | Contenido |
| --- | --- | --- |
| 1 | Requisito explícito (Issue #18) | Fórmula `10 × 1,2^(1d8)`; `1d8` entero `1..8` del motor centralizado; la XP se acumula; se verifica el umbral tras acreditar; sin victoria válida no hay recompensa. |
| 2 | Aclaración funcional del PO (posterior al enunciado) | La fórmula es de **JvE (muerte de NPC en misión)**; PvP / «Jugar Online» **no** la otorga. Missions coordina y calcula; Combat solo tira; Player/Inventory solo acredita. |
| 3 | Decisión arquitectónica `Accepted`, reutilizada | ADR-019 (ownership y HMAC interno), ADR-021 (única autoridad de aleatoriedad). |
| 4 | Contrato existente, reutilizado como plantilla | `POST /api/internal/v1/inventory/grants` (Player-Inventory, HU-59/HU-69) para la forma del endpoint interno y del ledger idempotente. |
| 5 | Decisión técnica interna (este documento) | Forma exacta de las dos operaciones internas, `operationId` deterministas, estados de la recompensa en Missions, matriz de fallos y contrato de la tirada. |
| 6 | Fuera de alcance | HU-10 (recompensa por misión completada), HU-30 (caída de ítems), HU-32/HU-73 (épica por derrota de Máster), PvP, y `CA-06` de HU-08 (el nivel como multiplicador de estadísticas). |

## 2. Ownership (recap de ADR-019, no se reabre)

| Contexto | Dueño de |
| --- | --- |
| **Combat** | La aleatoriedad (HU-24/25), el resultado de la batalla o simulación, y **la producción de la tirada** de la recompensa. |
| **Missions** | El enfrentamiento JvE, la coordinación de la recompensa, **el cálculo de la fórmula** y el estado de la recompensa. |
| **Player/Inventory** | El nivel, la experiencia acumulada y la acreditación persistida e idempotente. |
| **Web** | Presentar lo que los servicios devuelven. No calcula nada. |
| **Infrastructure** | Este contrato y sus diagramas. |

**Prohibido, y es la parte que más fácilmente se rompe:**

- Combat **no** conoce `10 × 1,2^(1d8)` ni ningún importe de experiencia. Devuelve la tirada.
- Missions **no** genera aleatoriedad de ninguna clase, ni usa `Math.random`, ni guarda una semilla.
- Player/Inventory **no** redondea, **no** aplica la fórmula y **no** conoce el `1d8` como regla: recibe un importe entero.
- Nadie lee la base de datos de otro contexto.

## 3. Reparto, paso a paso

| # | Quién | Qué hace | Dónde vive |
| --- | --- | --- | --- |
| 1 | Missions | Ejecuta la misión JvE y pide la simulación a Combat | `HU-72` |
| 2 | Combat | Simula y determina el resultado del enfrentamiento **y qué enemigos concretos cayeron** | `HU-72` |
| 3 | **Combat** | Por **cada NPC derrotado**, obtiene un `1d8` del motor centralizado, lo persiste y lo devuelve | §5 (Task `#440`) |
| 4 | **Missions** | Por cada derrota, calcula `10 × 1,2^(1d8)`, lo redondea a entero y lo persiste | §6 (Task `#442`) |
| 5 | **Player/Inventory** | Por cada derrota, acredita la XP, acumula y recalcula el nivel con la tabla de HU-08 | §7 (Task `#441`) |
| 6 | Missions | Marca cada recompensa como acreditada y las refleja en el reporte | `HU-74` |

**Los pasos 3, 4 y 5 se ejecutan una vez por enemigo derrotado**, no una vez por misión (§4).

**La frontera con HU-10.** HU-09 otorga la experiencia **por derrota de un rival**. HU-10 ([#19](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/19)) otorga la recompensa de **misión completada** (créditos, productos, épicas y su propia línea de experiencia). El diseño del reporte de misión sitúa esa línea bajo HU-10; este contrato **no** la implementa ni la reserva.

## 4. Unidad de la recompensa: una por rival derrotado

**Decidido, y no provisional:** cada **NPC derrotado** produce **una recompensa**, **una tirada `1d8`** y **una acreditación** al héroe.

```text
cada NPC derrotado
  -> una recompensa de XP
  -> una tirada 1d8
  -> una acreditación al héroe
```

**No hay una sola tirada por ganar la misión.** La recompensa se devenga por **derrota**, no por victoria global: una misión cuyo resumen enumera 10 + 5 + 3 + 1 enemigos produce **19 recompensas**, cada una con su tirada y su acreditación.

### 4.1 La clave es la instancia, no el arquetipo

El identificador **no puede ser `rivalRef`** (el arquetipo del enemigo): una misma misión puede enfrentar dos veces al mismo tipo — en el ejemplo de HU-72, `sombra-corrompida` aparece con `count: 4` en un encuentro y con `count: 6` en otro. Identificar por arquetipo colisionaría y **duplicaría o perdería recompensas**.

**HU-72 ya produce la identidad que hace falta, sin inventar nada:** su `combatLog` registra cada baja como

```jsonc
{ "seq": 4, "type": "combatantDefeated", "encounter": 1, "turn": 1, "combatant": "sombra-corrompida#1" }
```

donde `encounter` es el índice del encuentro y `combatant` es `<enemyRef>#<n>`, la instancia concreta. **La clave de una derrota es `encounter` + `combatant`.**

- `summary.enemiesDefeated[]` (conteos por arquetipo) **no sirve** para identificar recompensas: agrega y pierde la instancia. Sirve para cuadrar totales, no para devengar.
- El nombre exacto de los campos depende del contrato de HU-72, que sigue siendo una **propuesta abierta** (PR #132). Lo que este contrato exige es la **propiedad**, no el nombre: **la clave tiene que ser única por derrota real**, y si HU-72 renombra los campos, la clave se renombra con ellos.
- Si el modelo de HU-72 cambiara y dejara de exponer las bajas una a una, **HU-09 no puede degradarse a una tirada por misión**: eso cambiaría la regla de negocio. Lo que habría que cambiar es HU-72.

### 4.2 Consecuencia de escala, asumida

Una misión con muchos enemigos produce muchas operaciones. El diseño lo reparte así:

| Operación | Granularidad | Motivo |
| --- | --- | --- |
| Tirada (Missions → Combat) | **Un lote por misión**, con una tirada por derrota | El consumo del cursor de azar debe resolverse de una vez y persistirse junto; 19 llamadas sueltas permitirían conjuntos de tiradas a medias |
| Acreditación (Missions → Player/Inventory) | **Una por derrota** | Cada recompensa tiene su propia clave de idempotencia y su propia traza; sumarlas en un importe único perdería ambas cosas |

## 5. La tirada: contrato Missions → Combat

### 5.1 De dónde sale el número

```text
RandomSequencePort.nextIndex()  (HU-24, MISMA secuencia de proceso que turnos y ataques)
        ↓
BoundedRandom(sequence).nextInt(8) + 1   →   1d8 ∈ {1..8}, uniforme y sin sesgo
```

`BoundedRandom.nextInt(bound)` usa muestreo por rechazo, así que el reparto es uniforme. **No** hay una secuencia por batalla ni por misión: es la única secuencia del proceso, sembrada al arrancar con `COMBAT_RANDOM_SEED` (HU-26), y HU-09 consume de ella igual que HU-17, HU-18, HU-19 y HU-22. Consecuencia aceptada y escrita: **el orden de consumo importa** y el `1d8` de HU-09 comparte cursor con los turnos, los ataques y el cofre.

**Se consume un `1d8` por cada NPC derrotado.** Como el orden de consumo forma parte del resultado, el lote (§5.2) se resuelve **en el orden de las derrotas** que Missions envía, y ese orden es el del `combatLog` de la simulación: mismo `operationId` y mismo cuerpo ⇒ mismas tiradas, en el mismo orden.

### 5.2 Operación interna

```text
POST /api/internal/v1/combat/experience-rolls
```

Cabeceras del esquema vigente de ADR-019: `x-internal-service: missions`, `x-internal-timestamp`, `x-internal-signature` (HMAC-SHA256 sobre JSON canónico), secreto `INTERNAL_SERVICE_AUTH_SECRET` y lista cerrada de servicios por ruta. `/api/internal*` responde `404` desde Caddy.

**Una llamada por misión, una tirada por derrota.** El lote lleva todas las derrotas de la misión y devuelve una tirada por cada una, en el mismo orden.

```jsonc
{
  "schemaVersion": 1,
  "operationId": "mission:{enrollmentId}:xp-rolls", // determinista, la cadena literal, SIN hashear
  "enrollmentId": "enr_01JB8Y3K7Q",
  "simulationId": "sim_01JB8Y4B",
  "heroId": "7f3c2a9e-2d4b-4c1a-9e7f-1b2c3d4e5f60",
  "defeats": [
    { "encounterId": "1", "enemyInstanceId": "sombra-corrompida#1", "rivalRef": "sombra-corrompida" },
    { "encounterId": "1", "enemyInstanceId": "sombra-corrompida#2", "rivalRef": "sombra-corrompida" },
    { "encounterId": "5", "enemyInstanceId": "guardian-eterno#1", "rivalRef": "guardian-eterno" }
  ]
}
```

```jsonc
{
  "schemaVersion": 1,
  "operationId": "mission:{enrollmentId}:xp-rolls",
  "applied": true,                  // false si es un replay idempotente del mismo operationId+cuerpo
  "rolls": [
    { "encounterId": "1", "enemyInstanceId": "sombra-corrompida#1", "roll": 5, "persistedAt": "2026-10-02T03:00:04.120Z" },
    { "encounterId": "1", "enemyInstanceId": "sombra-corrompida#2", "roll": 1, "persistedAt": "2026-10-02T03:00:04.121Z" },
    { "encounterId": "5", "enemyInstanceId": "guardian-eterno#1", "roll": 8, "persistedAt": "2026-10-02T03:00:04.122Z" }
  ]
}
```

- **Cada tirada se persiste con su propia clave**, `mission:{enrollmentId}:encounter:{encounterId}:enemy:{enemyInstanceId}:xp-roll`, **antes de responder**. El `operationId` del lote es la clave de idempotencia de la llamada; la clave por derrota es la de la tirada.
- Un lote de **una** derrota es un caso particular del mismo contrato: no hay una operación aparte.
- `enemyInstanceId` es el `combatant` de HU-72 (`<enemyRef>#<n>`), y `encounterId` su `encounter`. Los dos juntos identifican la derrota real.

| HTTP | `code` | Cuándo | Qué hace Missions |
| --- | --- | --- | --- |
| `200` | — | Tirada hecha, o repetida con el mismo `operationId` y el mismo cuerpo | Guarda y pasa a `ROLLED` |
| `400` | `SCHEMA_INVALID` | El cuerpo no cumple el esquema | `FAILED` y alerta |
| `401` | `INTERNAL_SIGNATURE_INVALID` | Firma ausente o inválida | Alerta; no reintenta |
| `409` | `OPERATION_ID_REUSED` | El `operationId` llegó con otro cuerpo | `FAILED` y alerta |
| `422` | `HERO_NOT_ELIGIBLE` | El héroe no puede recibir la recompensa | `FAILED`; no reintenta |
| `503` | `ROLL_UNAVAILABLE` | Combat no puede atender ahora | Reintenta con el **mismo** `operationId` |

**La tirada se persiste antes de responder.** Es la garantía de que un reintento de Missions —o un reinicio de Combat— **no vuelve a consumir el cursor aleatorio**: un segundo `1d8` daría otra recompensa por el mismo hecho.

### 5.3 Por qué una operación propia y no un campo de la simulación de HU-72

| Opción | Contenido | Valoración |
| --- | --- | --- |
| **A** | Extender la respuesta de `POST /api/internal/v1/combat/simulations` (HU-72) con la tirada | Un viaje menos, pero **acopla HU-09 a un contrato que aún no está mergeado** (PR #132) y obliga a producir la tirada dentro de la simulación, incluso cuando el resultado no da derecho a recompensa |
| **B (elegida)** | Operación propia de Combat, invocada por Missions **después** de saber que hubo victoria | Desacopla HU-09 de HU-72, mantiene intacto el contrato de simulación, permite persistir la tirada antes de cualquier efecto remoto y es directamente verificable con `operationId` |

**No es exponer aleatoriedad**, que es lo que `ADR-021` prohíbe: la operación no acepta un rango, no devuelve el índice ni la semilla, no es parametrizable y es idempotente por `operationId`. Es una operación de dominio («resolver la tirada de la recompensa de esta derrota»), el mismo criterio con el que HU-22 resuelve el cofre dentro de Combat.

## 6. La fórmula y el redondeo

**Dueño único: Missions.** Ni Combat ni Player/Inventory contienen la expresión.

```text
experiencia = redondear(10 × 1,2^(1d8))     con 1d8 ∈ {1..8}
```

| `1d8` | Valor exacto | Al entero más próximo (**propuesta**) | Con truncamiento (alternativa) |
| ---: | ---: | ---: | ---: |
| 1 | 12 | **12** | 12 |
| 2 | 14,4 | **14** | 14 |
| 3 | 17,28 | **17** | 17 |
| 4 | 20,736 | **21** | 20 |
| 5 | 24,8832 | **25** | 24 |
| 6 | 29,85984 | **30** | 29 |
| 7 | 35,831808 | **36** | 35 |
| 8 | 42,9981696 | **43** | 42 |

**`P-2` — decisión abierta.** El PO describió el redondeo **al entero más próximo** y ofreció el **truncamiento** como alternativa; ninguna de las dos está fijada por escrito en el Issue. El contrato adopta el redondeo al más próximo **como provisional** y la implementación debe dejar la regla en un único punto (la política pura de Missions) para que cambiarla no toque nada más.

**La experiencia que cruza la frontera es siempre entera.** La tabla de umbrales de HU-08 está en enteros y comparar un acumulado fraccionario con ella sería una fuente de errores de frontera imposible de justificar. Player/Inventory **rechaza** un importe no entero en lugar de redondearlo por su cuenta.

**Nota de aritmética:** con `1d8 = 8` la recompensa es `43`, y el umbral del nivel 1→2 es `200` (HU-08). Una sola victoria **no** sube de nivel a un héroe recién creado; sí puede subirlo si ya estaba cerca del umbral, y una sola acreditación puede cruzar **más de un umbral** si el acumulado previo lo permite.

## 7. La acreditación: contrato Missions → Player/Inventory

Se modela sobre el contrato ya implementado de HU-59/HU-69 (`POST /api/internal/v1/inventory/grants`, Player-Inventory) **sin reutilizar su ruta**: la experiencia no es un producto del inventario.

```text
POST /api/internal/v1/players/{playerId}/heroes/{heroId}/experience
```

Mismas cabeceras internas que §5.2, con `x-internal-service: missions`.

**Una llamada por derrota.** Cada NPC derrotado tiene su propia acreditación, con su importe y su clave; no se suman en un importe único porque eso perdería la traza y la idempotencia por derrota.

```jsonc
{
  "schemaVersion": 1,
  "operationId": "mission:{enrollmentId}:encounter:{encounterId}:enemy:{enemyInstanceId}:hero:{heroId}:xp",
  "amount": 25,                       // entero; ya redondeado por Missions
  "source": {
    "kind": "MISSION_RIVAL_DEFEAT",
    "enrollmentId": "enr_01JB8Y3K7Q",
    "simulationId": "sim_01JB8Y4B",
    "encounterId": "5",
    "enemyInstanceId": "guardian-eterno#1",
    "rivalRef": "guardian-eterno",
    "roll": 5
  }
}
```

```jsonc
{
  "operationId": "…",
  "applied": true,          // false en un replay idempotente
  "heroId": "…",
  "level": 4,
  "currentXp": 890,         // ACUMULADO total; nunca se descuenta
  "leveledUp": true,
  "levelsGained": 1,
  "nextLevel": { "status": "AVAILABLE", "forNextLevel": 5, "amount": 1600 },
  "maxLevel": 8
}
```

`nextLevel` y `maxLevel` son **derivados en la lectura** con `thresholdForNextLevel()` de HU-08; no se persisten y no forman parte de la clave de idempotencia.

| HTTP | `code` | Cuándo |
| --- | --- | --- |
| `200` | — | Acreditado, o repetido con el mismo `operationId` y el mismo cuerpo |
| `400` | `SCHEMA_INVALID` | El cuerpo no cumple el esquema |
| `401` | `INTERNAL_SIGNATURE_INVALID` | Firma ausente o inválida |
| `409` | `EXPERIENCE_GRANT_CONFLICT` | El mismo `operationId` llegó con otro cuerpo |
| `422` | `EXPERIENCE_GRANT_REJECTED` | Importe no entero o negativo, o héroe no acreditable |
| `503` | `PLAYER_INVENTORY_UNAVAILABLE` | El servicio no puede atender ahora |

**Servicio permitido.** El allow-list global de Player/Inventory es hoy `['commerce', 'notifications', 'combat']` y **no incluye `missions`**. La ruta se protege con `@InternalOnly()` **y** `@InternalCallers('missions')`, que acota el permiso a esta ruta concreta **sin** ampliar el allow-list global: el mecanismo ya existe (`INTERNAL_CALLERS`) y es el de menor privilegio.

**Ledger y transacción.** La acreditación escribe un documento de ledger con `_id = operationId` (único) y actualiza la progresión **en la misma transacción**, como `GrantPurchasedItems`. El `_id` del documento de progresión sigue siendo `"<ownerId>::<heroId>"` (HU-08) y el bloqueo optimista sigue siendo responsabilidad del repositorio.

**Creación perezosa.** Un héroe sin documento de progresión se interpreta como nivel 1 con 0 (HU-08) y la acreditación crea el documento. No hay backfill.

## 8. Idempotencia (resumen)

| Operación | Clave | Mismo cuerpo | Cuerpo distinto |
| --- | --- | --- | --- |
| Missions → Combat (lote de tiradas) | `mission:{enrollmentId}:xp-rolls` | Mismas tiradas, `applied:false`. **No se vuelve a tirar** | `409 OPERATION_ID_REUSED` |
| — tirada de una derrota (persistida) | `mission:{enrollmentId}:encounter:{encounterId}:enemy:{enemyInstanceId}:xp-roll` | Se relee la tirada guardada de esa instancia | — |
| Missions → Player/Inventory (acreditación) | `mission:{enrollmentId}:encounter:{encounterId}:enemy:{enemyInstanceId}:hero:{heroId}:xp` | Mismo resultado, `applied:false`. **No se vuelve a acreditar** | `409 EXPERIENCE_GRANT_CONFLICT` |

**Semántica de entrega: al menos una vez, con efectos idempotentes.** No se promete transporte exactamente-una-vez, igual que HU-21 y HU-22. La regla que no se puede romper: **un reintento nunca cambia el resultado**.

## 9. Estados de la recompensa en Missions y fallos parciales

```text
PENDING ──► ROLLED ──► CREDITED
   │           │
   └───────────┴──► FAILED   (rechazo terminal o cuerpo incoherente)
```

| Estado | Significa | Se recupera tras reinicio |
| --- | --- | --- |
**Hay una recompensa por cada NPC derrotado**, y cada una tiene su propio estado, su propia clave y su propio ciclo de recuperación. No hay una recompensa agregada por misión.

| `PENDING` | Recompensa de esa derrota creada; aún no se pidió su tirada | Reintenta `POST §5.2` con el mismo `operationId` del lote |
| `ROLLED` | La tirada de esa derrota está persistida en Combat; falta acreditar | Reintenta `POST §7` con el importe **ya calculado** y el mismo `operationId`; **no** vuelve a tirar |
| `CREDITED` | Terminal. La acreditación de esa derrota está confirmada | No-op |
| `FAILED` | Terminal. Rechazo definitivo (`422`) o cuerpo incoherente (`409`) | No reintenta solo; queda visible en observabilidad |

Cada transición se persiste **antes** de avanzar al paso siguiente, para que un reinicio recupere la recompensa donde quedó.

### 9.1 La garantía que sí se puede prometer

Una versión anterior de este contrato decía que no podía existir una tirada sin recompensa. **Eso es demasiado fuerte y no es lo que hace falta.** Una caída entre persistir la tirada y acreditarla deja, por definición, una tirada guardada sin acreditar; eso **no es un defecto**.

Lo que se exige es esto:

> **Una tirada persistida sin acreditar es aceptable mientras exista una recompensa en estado no terminal que la reclame y el barrido pueda terminarla. Lo que no puede existir es una tirada huérfana: guardada en Combat, sin ninguna recompensa que la reclame y sin camino de recuperación.**

De ahí la **regla de orden**, que es la que sostiene la garantía:

```text
1. Missions persiste la recompensa de cada derrota (PENDING)   <- ANTES de pedir nada
2. Missions pide el lote de tiradas y las guarda (ROLLED)
3. Missions acredita cada derrota (CREDITED)
```

Persistir **antes** es lo que hace imposible la tirada huérfana: toda tirada que Combat llegue a guardar corresponde a una recompensa que ya existe y que el barrido recogerá. Si el paso 1 se hiciera después, una caída dejaría tiradas sin dueño.

| Punto de falla | Estado persistido | Reintento | Resultado visible |
| --- | --- | --- | --- |
| Missions cae antes de pedir el lote de tiradas | Las recompensas de esa misión en `PENDING` | Sí, mismo `operationId` del lote | Recompensas pendientes |
| Combat persiste las tiradas pero Missions cae antes de leer la respuesta | Las tiradas **ya están persistidas**, una por derrota | Sí; el replay devuelve las **mismas** tiradas | Ninguna perdida |
| Missions guarda las tiradas pero cae antes de acreditar alguna | Esa derrota queda en `ROLLED`, con su importe persistido | Sí, mismo `operationId`; **no** vuelve a tirar | Recompensas pendientes |
| Player/Inventory acredita pero Missions cae antes de leer la respuesta | Player/Inventory ya aplicó (idempotente) | Sí; el replay devuelve el mismo resultado | Ninguna perdida |
| Player/Inventory rechaza una derrota con `422` | Esa derrota queda `FAILED`; **las demás siguen su curso** | No automático | Sin experiencia para esa derrota; la misión no se revierte |
| Combat o Player/Inventory devuelven `503` | Las recompensas se quedan en su estado de origen | Sí, mismo `operationId` | Recompensas pendientes |

**Ningún fallo revierte la misión ni el resultado de la batalla**: la recompensa es un efecto posterior, no una condición del cierre. Y **una derrota que falla no arrastra a las demás**: cada recompensa es independiente.

## 10. Cómo se entera Web

Web **no** aplica la fórmula ni conoce la tabla de umbrales. Consume:

- el **reporte de misión** (`HU-74`), que ya prevé líneas de recompensa con tipo `EXPERIENCE` y estado (`PENDING`, `CREDITED`, `FAILED`), y
- el nivel y el acumulado que Missions devuelva con la recompensa confirmada.

La representación del **estado** es obligatoria: mostrar como concedida una recompensa `PENDING` es el error que el diseño de HU-74 (`P-T2`) ya quiso evitar separando la foto del reporte del estado de cada línea.

**Superficie pública:** este contrato **no** añade ninguna. Si `HU-09.5` necesita el nivel actual del héroe y el reporte no lo da, esa decisión se toma aquí y se convierte en una Task propia; **no** se inventa un endpoint público dentro de la Task de Web.

## 11. Seguridad

- Interno (`Missions → Combat`, `Missions → Player/Inventory`): HMAC-SHA256, ventana de sello, lista cerrada de servicios **por ruta**, y `/api/internal*` bloqueado en Caddy.
- `missions` **no** entra en el allow-list global de Player/Inventory: se acota con `@InternalCallers('missions')` en la ruta de experiencia, que es el permiso mínimo suficiente.
- El `heroId` y el `playerId` viajan en la ruta porque el llamante es un servicio autenticado; nunca se aceptan de un cliente.
- No se registran secretos HMAC ni el estado interno del generador. Sí se correlacionan `enrollmentId`, `operationId`, `roll` y estado.
- **No se expone la semilla** en ninguna respuesta (HU-24/ADR-021), y la operación de tirada no acepta rango ni parámetros de azar.

## 12. Fuera de alcance

- **HU-10** ([#19](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/19)): recompensas por misión completada, incluida su línea de experiencia en el reporte.
- **HU-30** ([#77](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/77)): probabilidad de caída de ítems.
- **HU-32/HU-73**: épica obtenida por derrota de un Máster.
- **PvP / «Jugar Online»**: no otorga experiencia por esta fórmula.
- **`CA-06` de HU-08**: el nivel como multiplicador de estadísticas base; sigue sin implementar y sin ser de esta historia.
- Cambios a HU-21 (notificación de fin de batalla), HU-24/25/26 (motor y tablas) y al contrato de simulación de HU-72.

## 13. Compatibilidad y orden de despliegue

**Aditivo.** Ningún mensaje existente cambia de forma y ninguna ruta existente se modifica.

**Orden:** Infrastructure (este contrato) → **Player/Inventory** (`#441`: ruta interna, ledger y `@InternalCallers`) → **Combat** (`#440`: operación de tirada y su colección) → **Missions** (`#442`: coordinación, política y estado) → **Web** (`#443`). Missions no debe llamar a un contrato que Combat o Player/Inventory todavía no exponen.

**Dependencias de calendario, dichas sin adornos:** `#442` no puede existir antes que el flujo de misión (`HU-72.2`, [#374](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/374)) ni antes del reporte (`HU-74.2`, [#380](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/380)), y **Missions no tiene hoy ninguna ruta de negocio ni ninguna tabla**. `#441` no puede compilar hasta que HU-08 esté en `develop`.

## 14. Casos límite

| Caso | Comportamiento exigido |
| --- | --- |
| Sin victoria válida ni NPC derrotado (`CA-08`) | No se crean recompensas, no se pide tirada, no se acredita |
| Participante `AI` o `heroId` nulo | No hay beneficiario: no hay recompensas |
| **Dos enemigos del mismo arquetipo en la misma misión** | **Dos recompensas distintas**, con claves distintas por `encounter` + `enemyInstanceId`; identificar por `rivalRef` está prohibido |
| El mismo arquetipo repetido dentro del mismo encuentro | La instancia (`#1`, `#2`, …) los separa |
| Reintento con el mismo `operationId` | Misma tirada y misma acreditación; nunca se vuelve a tirar |
| `operationId` repetido con otro cuerpo | `409` en la frontera correspondiente |
| Una acreditación cruza dos o más umbrales | Sube al nivel más alto alcanzado (HU-08, `levelFromTotalXp`) |
| Varias derrotas seguidas elevan el acumulado | Cada una acredita sobre el acumulado de la anterior; la última deja el nivel que corresponda |
| Héroe ya en nivel 8 | La experiencia sigue creciendo y **no se descarta**; no se rechaza |
| Importe no entero | `422`: el redondeo ocurre en Missions, antes de la frontera |
| El héroe no pertenece al jugador indicado | `422`; no se acredita a un héroe ajeno |
| Una derrota falla con `422` | Esa recompensa queda `FAILED`; **las demás no se arrastran** |
| Combat o Player/Inventory caídos | Reintento con el mismo `operationId`; las recompensas quedan pendientes y el barrido las termina |

## 15. Decisiones abiertas

| # | Decisión | Estado | Efecto si cambia |
| --- | --- | --- | --- |
| `P-1` | Una recompensa por **rival derrotado** o una por victoria | **CERRADA: una por rival derrotado**, con clave por instancia real (§4) | — |
| `P-2` | Redondeo **al más próximo** o **truncamiento** | **PROVISIONAL: al más próximo** | Cambia un valor por cada `1d8` (`21`↔`20`, `25`↔`24`, `30`↔`29`, `36`↔`35`, `43`↔`42`); la regla vive en un único punto |
| `P-3` | Corrección del enunciado del Issue #18 | **Ejecutada** el 2026-09-23: el cuerpo dice ya Missions/JvE y declara la cadena de Misiones | — |

**`P-2` sigue marcada como provisional a propósito.** Que la experiencia tenga que ser entera **sí** es una decisión tomada; **cómo** se convierte `14,4` en un entero no lo es hasta que se confirme «redondeo al entero más cercano» frente a truncamiento. La marca no se retira por conveniencia: mientras siga ahí, la política vive en un único punto para que confirmarla o cambiarla no toque nada más.
