# Contrato conceptual — estrategia de rotaciones (HU-71)

**Estado:** conceptual. **No implementado.** Este archivo no autoriza a marcar [service-catalog.md](service-catalog.md) como si las operaciones existieran.

Trazabilidad: [HU-71 #56](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/56) y [TASK HU-71.1 #369](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/369). Diseño: [hu-71-rotaciones-habilidades.md](../architecture/hu-71-rotaciones-habilidades.md). Escenarios: [hu-71-mission-strategy-fixtures-v1.json](hu-71-mission-strategy-fixtures-v1.json).

Los ejemplos usan la configuración del curso para un Guerrero Armas (§7.8.5). Los `abilityId` son legibles para el ejemplo; los reales los publica Player/Inventory.

## Vocabulario

```text
priority   = HIGH | MEDIUM | LOW          (Rotación 1, 2 y 3)
stepKind   = ABILITY | BASIC_ATTACK
skipReason = NOT_ENOUGH_POWER | ON_COOLDOWN | HEALTH_CONDITION
```

## Operaciones del jugador

Prefijo `/api/v1/missions`. JWT de Cognito con rol `PLAYER`; el jugador es el `sub` del token.

### Consultar la estrategia

```text
GET /api/v1/missions/{missionId}/strategies/{heroId}
```

Respuesta `200`:

```json
{
  "missionId": "msn_templo_olvidado",
  "heroId": "7f3c2a9e-2d4b-4c1a-9e7f-1b2c3d4e5f60",
  "version": 1,
  "rotations": [
    {
      "priority": "HIGH",
      "steps": [
        { "kind": "ABILITY", "abilityId": "golpe-de-tormenta" },
        { "kind": "ABILITY", "abilityId": "embate-sangriento" },
        { "kind": "BASIC_ATTACK" }
      ]
    },
    {
      "priority": "MEDIUM",
      "steps": [
        { "kind": "ABILITY", "abilityId": "lanza-de-los-dioses" },
        { "kind": "BASIC_ATTACK" },
        { "kind": "BASIC_ATTACK" }
      ]
    },
    {
      "priority": "LOW",
      "steps": [
        { "kind": "ABILITY", "abilityId": "embate-sangriento" },
        { "kind": "BASIC_ATTACK" },
        { "kind": "BASIC_ATTACK" }
      ]
    }
  ],
  "updatedAt": "2026-10-01T14:55:00Z"
}
```

Sin estrategia guardada: `404 STRATEGY_NOT_FOUND`. Misión inexistente: `404 MISSION_NOT_FOUND`.

### Guardar la estrategia

```text
PUT /api/v1/missions/{missionId}/strategies/{heroId}
```

```json
{
  "expectedVersion": null,
  "rotations": [
    { "priority": "HIGH", "steps": [{ "kind": "ABILITY", "abilityId": "golpe-de-tormenta" }, { "kind": "ABILITY", "abilityId": "embate-sangriento" }, { "kind": "BASIC_ATTACK" }] },
    { "priority": "MEDIUM", "steps": [{ "kind": "ABILITY", "abilityId": "lanza-de-los-dioses" }, { "kind": "BASIC_ATTACK" }, { "kind": "BASIC_ATTACK" }] },
    { "priority": "LOW", "steps": [{ "kind": "ABILITY", "abilityId": "embate-sangriento" }, { "kind": "BASIC_ATTACK" }, { "kind": "BASIC_ATTACK" }] }
  ]
}
```

- `expectedVersion`: la versión que el jugador leyó; `null` para crear la primera.
- Respuesta `201` al crear y `200` al reemplazar, con la estrategia completa y la versión nueva.

Reglas de validación, en este orden:

1. Entre 1 y 3 rotaciones. Con más: `422 TOO_MANY_ROTATIONS` (CA-04).
2. Prioridades sin repetir y sin huecos: `HIGH`; `HIGH` y `MEDIUM`; o las tres.
3. Entre 1 y 3 acciones por rotación.
4. Cada `ABILITY` usa un `abilityId` que el héroe tiene según Player/Inventory.
5. `expectedVersion` coincide con la versión guardada.

| HTTP | `code` | Cuándo |
| --- | --- | --- |
| `400` | `VALIDATION_ERROR` | Cuerpo mal formado: `priority` o `kind` desconocidos, o `ABILITY` sin `abilityId` |
| `404` | `MISSION_NOT_FOUND` | La misión no existe o no está activa |
| `409` | `VERSION_CONFLICT` | La versión guardada no es `expectedVersion` |
| `422` | `TOO_MANY_ROTATIONS` | Más de tres rotaciones (CA-04) |
| `422` | `INVALID_ROTATION` | Prioridades repetidas o con huecos, rotación vacía o con más de 3 acciones |
| `422` | `UNKNOWN_ABILITY` | Una habilidad que el héroe no tiene |
| `422` | `HERO_NOT_OWNED` | El héroe no es del jugador |
| `503` | `DEPENDENCY_UNAVAILABLE` | No se pudieron consultar las habilidades en Player/Inventory |

Cuerpos de ejemplo:

```json
{ "code": "TOO_MANY_ROTATIONS", "message": "Puedes configurar hasta tres rotaciones.", "max": 3, "received": 4 }
```

```json
{ "code": "INVALID_ROTATION", "message": "Las prioridades deben ser Alta, Media y Baja, en ese orden y sin saltos.", "violations": [{ "field": "rotations[1].priority", "reason": "PRIORITY_GAP" }] }
```

```json
{ "code": "UNKNOWN_ABILITY", "message": "Tu héroe no tiene la habilidad «lanza-de-los-dioses».", "abilityIds": ["lanza-de-los-dioses"] }
```

```json
{ "code": "VERSION_CONFLICT", "message": "Otra sesión cambió esta estrategia. Recárgala antes de guardar.", "expectedVersion": 1, "currentVersion": 2 }
```

## Extensión de la matrícula de HU-70

La matrícula lleva la versión de la estrategia que el jugador ve, en lugar de las rotaciones:

```json
{
  "heroId": "7f3c2a9e-2d4b-4c1a-9e7f-1b2c3d4e5f60",
  "difficulty": "NORMAL",
  "strategyVersion": 1
}
```

| Estrategia guardada | `strategyVersion` recibido | Resultado |
| --- | --- | --- |
| Versión 1 | `1` | Se congela la versión 1 en la matrícula |
| Versión 2 | `1` | `409 STRATEGY_VERSION_MISMATCH` |
| Versión 1 | `null` | `409 STRATEGY_VERSION_MISMATCH` |
| Ninguna | `null` | Matrícula sin estrategia: la IA solo usará el ataque básico |
| Ninguna | `1` | `409 STRATEGY_VERSION_MISMATCH` |

```json
{ "code": "STRATEGY_VERSION_MISMATCH", "message": "Tu estrategia cambió. Revísala antes de iniciar la misión.", "expectedVersion": 1, "currentVersion": 2 }
```

## Bloque `strategy` en la simulación (HU-72)

Missions envía a Combat la copia congelada:

```json
{
  "strategy": {
    "version": 1,
    "rotations": [
      { "priority": "HIGH", "steps": [{ "kind": "ABILITY", "abilityId": "golpe-de-tormenta" }, { "kind": "ABILITY", "abilityId": "embate-sangriento" }, { "kind": "BASIC_ATTACK" }] },
      { "priority": "MEDIUM", "steps": [{ "kind": "ABILITY", "abilityId": "lanza-de-los-dioses" }, { "kind": "BASIC_ATTACK" }, { "kind": "BASIC_ATTACK" }] },
      { "priority": "LOW", "steps": [{ "kind": "ABILITY", "abilityId": "embate-sangriento" }, { "kind": "BASIC_ATTACK" }, { "kind": "BASIC_ATTACK" }] }
    ],
    "fallback": "BASIC_ATTACK"
  }
}
```

Sin estrategia, `rotations` va vacío y todas las acciones del héroe son el respaldo.

## Anotación en la bitácora (propuesta para Combat)

Cada acción del héroe indica de dónde salió:

```json
{
  "seq": 12, "type": "skillUsed", "encounter": 1, "turn": 4, "actor": "hero",
  "abilityId": "lanza-de-los-dioses",
  "strategy": { "rotation": "MEDIUM", "step": 1, "fallback": false, "skipped": [{ "rotation": "HIGH", "reason": "ON_COOLDOWN" }] }
}
```

```json
{
  "seq": 20, "type": "basicAttackResolved", "encounter": 1, "turn": 7, "actor": "hero", "powerSpent": 0,
  "strategy": {
    "rotation": null, "step": null, "fallback": true,
    "skipped": [
      { "rotation": "HIGH", "reason": "NOT_ENOUGH_POWER" },
      { "rotation": "MEDIUM", "reason": "NOT_ENOUGH_POWER" },
      { "rotation": "LOW", "reason": "ON_COOLDOWN" }
    ]
  }
}
```

El primero demuestra CA-02 (se saltó la rotación alta y se usó la media); el segundo, CA-03 (respaldo sin consumir Poder).

## Fuera de este contrato

- Cómo calcula Combat el Poder, la recarga, la salud y el daño: HU-11, HU-18, HU-19 y HU-20.
- El editor en Web: HU-71.3.
- Borrar una estrategia: no lo pide la HU.
