# Contrato conceptual — simulación de misión (HU-72)

**Estado:** conceptual. **No implementado.** La operación interna hacia Combat es una **propuesta para Team Alfa**, dueño de Combat: hoy no existe `POST /api/internal/v1/combat/simulations`. Este archivo no autoriza a marcarla como capacidad en [service-catalog.md](service-catalog.md).

Trazabilidad: [HU-72 #57](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/57) y [TASK HU-72.1 #373](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/373). Diseño: [hu-72-simulacion-mision.md](../architecture/hu-72-simulacion-mision.md). Parte de la matrícula de [HU-70](hu-70-mission-enrollment-v1.md). Escenarios: [hu-72-mission-simulation-fixtures-v1.json](hu-72-mission-simulation-fixtures-v1.json).

Los ejemplos usan la misión «El Templo Olvidado» del curso (§7.8.14). Donde el curso no da un valor, el ejemplo pone `null`: **no se inventan estadísticas**.

## Vocabulario

```text
executionStatus = QUEUED | REQUESTED | SIMULATED | SETTLED | VOIDED
combatOutcome   = HERO_VICTORIOUS | HERO_DEFEATED | TIME_BUDGET_EXHAUSTED
missionOutcome  = COMPLETED | FAILED | ABANDONED | VOIDED
encounterKind   = REGULAR | BOSS
objectiveType   = DEFEAT_BOSS | CLEAR_ENCOUNTERS | MIN_HEALTH_PERCENT | DEFEAT_MASTER
logEventType    = encounterStarted | basicAttackResolved | skillUsed | randomEffectApplied
                | combatantDefeated | masterAppeared | encounterFinished | simulationFinished
```

`basicAttackResolved` y `skillUsed` son los nombres de evento que Combat ya usa en las batallas (HU-18 y HU-19). El resto son propuestas.

## Operación interna Missions → Combat (propuesta para Team Alfa)

```text
POST /api/internal/v1/combat/simulations
x-internal-service: missions
x-internal-timestamp: <epoch ms>
x-internal-signature: <HMAC-SHA256 sobre JSON canónico>
```

Esquema interno vigente de ADR-019: HMAC, lista cerrada de servicios autorizados por ruta y bloqueo en Caddy (`/api/internal*` responde `404` desde fuera).

### Solicitud

```json
{
  "schemaVersion": 1,
  "operationId": "op_sim_01JB8Y4A",
  "enrollmentId": "enr_01JB8Y3K7Q",
  "missionId": "msn_templo_olvidado",
  "difficulty": "NORMAL",
  "enemyStatMultiplier": 1.0,
  "timeBudget": "PT12H",
  "hero": {
    "heroId": "7f3c2a9e-2d4b-4c1a-9e7f-1b2c3d4e5f60",
    "profile": { "$ref": "EquippedHeroDto de Player/Inventory (HU-15), congelado al comprometer al héroe" }
  },
  "strategy": {
    "version": 1,
    "rotations": [
      { "priority": "HIGH", "steps": [{ "kind": "ABILITY", "abilityId": "golpe-de-tormenta" }, { "kind": "ABILITY", "abilityId": "embate-sangriento" }, { "kind": "BASIC_ATTACK" }] },
      { "priority": "MEDIUM", "steps": [{ "kind": "ABILITY", "abilityId": "lanza-de-los-dioses" }, { "kind": "BASIC_ATTACK" }, { "kind": "BASIC_ATTACK" }] },
      { "priority": "LOW", "steps": [{ "kind": "ABILITY", "abilityId": "embate-sangriento" }, { "kind": "BASIC_ATTACK" }, { "kind": "BASIC_ATTACK" }] }
    ],
    "fallback": "BASIC_ATTACK"
  },
  "encounters": [
    { "index": 1, "kind": "REGULAR", "powerStep": null, "enemies": [{ "enemyRef": "sombra-corrompida", "name": "Sombra Corrompida", "count": 4, "profile": null }] },
    { "index": 2, "kind": "REGULAR", "powerStep": null, "enemies": [{ "enemyRef": "sombra-corrompida", "name": "Sombra Corrompida", "count": 6, "profile": null }] },
    { "index": 3, "kind": "REGULAR", "powerStep": null, "enemies": [{ "enemyRef": "guardian-de-piedra", "name": "Guardián de Piedra", "count": 5, "profile": null }] },
    { "index": 4, "kind": "REGULAR", "powerStep": null, "enemies": [{ "enemyRef": "espectro-ancestral", "name": "Espectro Ancestral", "count": 3, "profile": null }] },
    {
      "index": 5,
      "kind": "BOSS",
      "powerStep": null,
      "enemies": [{
        "enemyRef": "guardian-eterno",
        "name": "El Guardián Eterno",
        "count": 1,
        "profile": { "subtype": "GUERRERO_TANQUE", "maxHealth": 100, "attack": null, "defense": null, "damage": null, "abilities": null }
      }]
    }
  ],
  "master": {
    "evaluationPoints": [{ "afterEncounter": 3 }],
    "maxAppearances": 1,
    "candidates": [{ "masterRef": "sombra-del-olvido", "subtype": "PICARO_VENENO", "probability": 0.15, "levelOffset": 2, "profile": null, "epicRef": "velo-de-sombras" }]
  }
}
```

Qué significa cada bloque y quién lo define:

| Campo | Lo define | Estado |
| --- | --- | --- |
| `operationId` | Missions, uno por ejecución | Propuesta |
| `difficulty`, `enemyStatMultiplier` | HU-75 | Propuesta de HU-75; `MYTHIC` sin número |
| `timeBudget` | Duración de la misión (HU-70) | Semántica pendiente (decisión 1 del diseño) |
| `hero.profile` | Player/Inventory, congelado al comprometer | **Pendiente de Team Alfa** (decisión 10) |
| `strategy` | HU-71 | Forma del [contrato de HU-71](hu-71-mission-strategy-v1.md#bloque-strategy-en-la-simulación-hu-72); el ejemplo es el del curso (§7.8.5) |
| `encounters[].enemies[].profile` | Contenido de la misión | **Pendiente de contenido** (§7.8.4); `null` en el ejemplo |
| `encounters[].powerStep` | Contenido de la misión | **Pendiente** (decisión 8) |
| `master` | HU-73 | Forma del [contrato de HU-73](hu-73-master-encounter-v1.md#fragmento-de-la-solicitud-de-simulación-hu-72) |

El reparto de enemigos en cinco encuentros es ilustrativo: el curso da las cantidades (10, 5 y 3) y «las 5 cámaras», no el orden.

### Respuesta `200`

Valores ilustrativos:

```json
{
  "schemaVersion": 1,
  "simulationId": "sim_01JB8Y4B",
  "operationId": "op_sim_01JB8Y4A",
  "seedRef": "seed_7Q2M",
  "combatOutcome": "HERO_VICTORIOUS",
  "summary": {
    "encountersCompleted": 5,
    "encountersTotal": 5,
    "totalTurns": 142,
    "damageDealt": 1830,
    "damageTaken": 640,
    "minHealthPercent": 41.5,
    "skillsUsed": [
      { "abilityRef": "golpe-de-tormenta", "count": 22 },
      { "abilityRef": "embate-sangriento", "count": 17 },
      { "abilityRef": "BASIC_ATTACK", "count": 61 }
    ],
    "criticalEffects": 9,
    "enemiesDefeated": [
      { "enemyRef": "sombra-corrompida", "count": 10 },
      { "enemyRef": "guardian-de-piedra", "count": 5 },
      { "enemyRef": "espectro-ancestral", "count": 3 },
      { "enemyRef": "guardian-eterno", "count": 1 }
    ],
    "bossDefeated": true,
    "master": { "appeared": false, "masterRef": null, "defeated": false },
    "simulatedDuration": "PT9H40M"
  },
  "combatLog": [
    { "seq": 1, "type": "encounterStarted", "encounter": 1 },
    { "seq": 2, "type": "skillUsed", "encounter": 1, "turn": 1, "actor": "hero", "abilityId": "golpe-de-tormenta", "strategy": { "rotation": "HIGH", "step": 1, "fallback": false, "skipped": [] }, "target": "sombra-corrompida#1", "damage": 18, "targetHealthAfter": 0 },
    { "seq": 3, "type": "randomEffectApplied", "encounter": 1, "turn": 1, "actor": "hero", "effect": "CRITICAL", "critical": true },
    { "seq": 4, "type": "combatantDefeated", "encounter": 1, "turn": 1, "combatant": "sombra-corrompida#1" },
    { "seq": 611, "type": "simulationFinished", "combatOutcome": "HERO_VICTORIOUS" }
  ]
}
```

- `seedRef` es una referencia opaca para auditoría. **La semilla nunca sale de Combat** (ADR-019 y ADR-021).
- El bloque `strategy` de cada acción del héroe (forma de HU-71) permite verificar CA-02 en la bitácora.
- Toda la aleatoriedad (dados, efectos, aparición del Máster) sale del generador de Combat (CA-03).

### Idempotencia y errores

Combat guarda la simulación asociada al `operationId`. Con el mismo `operationId` y el mismo cuerpo responde **la misma** simulación, sin volver a sortear.

| HTTP | `code` | Cuándo | Qué hace Missions |
| --- | --- | --- | --- |
| `200` | — | Simulación hecha (o repetida con el mismo `operationId`) | Guarda y pasa a `SIMULATED` |
| `400` | `SCHEMA_INVALID` | La solicitud no cumple el esquema | `VOIDED` y alerta |
| `401` | `INTERNAL_SIGNATURE_INVALID` | Firma HMAC ausente o no válida | Alerta; no se reintenta |
| `409` | `OPERATION_ID_REUSED` | El `operationId` llegó con otro cuerpo | `VOIDED` y alerta |
| `422` | `UNSUPPORTED_ABILITY`, `INVALID_ENEMY_PROFILE` o `DIFFICULTY_NOT_CONFIGURED` | Configuración que Combat no puede simular | `VOIDED` |
| `503` | `SIMULATION_UNAVAILABLE` | Combat no puede simular ahora | Reintenta con el mismo `operationId` |

La simulación es acelerada (§7.8.12) y debe responder dentro del tiempo de espera de la llamada interna. Si no es viable, Combat puede proponer un modo asíncrono; hoy ADR-019 fija el modo síncrono.

## Evaluación de objetivos (en Missions)

| `objectiveType` | Parámetro | Se cumple si |
| --- | --- | --- |
| `DEFEAT_BOSS` | — | `summary.bossDefeated` |
| `CLEAR_ENCOUNTERS` | `count` | `summary.encountersCompleted >= count` |
| `MIN_HEALTH_PERCENT` | `percent` | `summary.minHealthPercent >= percent` |
| `DEFEAT_MASTER` | — | `summary.master.defeated`. Si el Máster no apareció, el objetivo **no aplica** (`met: null`) |

Objetivos del ejemplo del curso:

| Objetivo | Tipo | Principal |
| --- | --- | --- |
| Derrotar al Guardián del Templo | `DEFEAT_BOSS` | Sí |
| Explorar las 5 cámaras | `CLEAR_ENCOUNTERS` (5) | Sí |
| No bajar del 50 % de vida | `MIN_HEALTH_PERCENT` (50) | No |
| Derrotar al Máster si aparece | `DEFEAT_MASTER` | No |
| Encontrar los 3 fragmentos del Sello | Botín: **no evaluable en v1** (HU-10) | No |

## Hecho interno al cerrar

En la transacción del cierre, Missions registra una sola vez:

```json
{
  "type": "MissionSettled",
  "enrollmentId": "enr_01JB8Y3K7Q",
  "missionId": "msn_templo_olvidado",
  "playerId": "cognito-sub-del-jugador",
  "heroId": "7f3c2a9e-2d4b-4c1a-9e7f-1b2c3d4e5f60",
  "difficulty": "NORMAL",
  "missionOutcome": "COMPLETED",
  "reason": null,
  "objectives": [
    { "id": "obj_guardian", "type": "DEFEAT_BOSS", "primary": true, "met": true },
    { "id": "obj_camaras", "type": "CLEAR_ENCOUNTERS", "primary": true, "met": true },
    { "id": "obj_vida", "type": "MIN_HEALTH_PERCENT", "primary": false, "met": false },
    { "id": "obj_master", "type": "DEFEAT_MASTER", "primary": false, "met": null }
  ],
  "simulationId": "sim_01JB8Y4B",
  "settledAt": "2026-10-02T03:00:05Z"
}
```

Lo consumen HU-74 (reporte), HU-76 (logros), HU-10 (recompensas) y la notificación de fin de misión. Es un hecho **interno** de Missions: no es un evento publicado en otra cola.

## Liberación del héroe

Missions reutiliza la liberación propuesta en el [contrato de HU-70](hu-70-mission-enrollment-v1.md#liberar-el-compromiso), con el `operationId` **del compromiso** (no el de la simulación):

```text
POST /api/internal/v1/inventory/commitments/{operationId}/release
```

`204` confirma. Se reintenta hasta confirmarse; liberar dos veces no tiene efecto.

## Renovar el compromiso (propuesta para Player/Inventory)

Solo si Combat tarda más que el margen del compromiso (decisión 11 del diseño):

```text
POST /api/internal/v1/inventory/commitments/{operationId}/extend
{ "expiresAt": "2026-10-02T04:32:00Z" }
```

## Fuera de este contrato

- Forma de las rotaciones: HU-71.
- Reglas de aparición y recompensa del Máster: HU-73.
- Reporte e historial: HU-74.
- Niveles de dificultad y su escalado: HU-75.
- Montos y botín: HU-10.
- Logros: HU-76.
- Cancelación y penalización: sin HU en Sprint 2.
