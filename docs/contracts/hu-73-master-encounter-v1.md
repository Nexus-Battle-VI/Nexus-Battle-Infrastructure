# Contrato conceptual — encuentro con enemigo Máster (HU-73)

**Estado:** conceptual. **No implementado.** Los fragmentos hacia Combat amplían la **propuesta** de [HU-72](hu-72-mission-simulation-v1.md) para Team Alfa; la entrega de la épica usa un contrato existente de Player/Inventory que todavía no acepta a `missions`.

Trazabilidad: [HU-73 #58](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/58) y [TASK HU-73.1 #376](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/376). Diseño: [hu-73-encuentro-master.md](../architecture/hu-73-encuentro-master.md). Escenarios: [hu-73-master-encounter-fixtures-v1.json](hu-73-master-encounter-fixtures-v1.json).

El ejemplo es el Máster «Sombra del Olvido» de la misión del curso (§7.8.14). `null` marca lo que el curso no define.

## Vocabulario

```text
masterEncounterStatus = NOT_APPLICABLE | NOT_APPEARED | APPEARED_DEFEATED
                      | APPEARED_HERO_DEFEATED | APPEARED_ESCAPED | SKIPPED_MAX_REACHED
```

## Configuración en la definición de la misión

```json
{
  "masterEncounter": {
    "evaluationPoints": [{ "afterEncounter": 3 }],
    "maxAppearances": 1,
    "candidates": [
      {
        "masterRef": "sombra-del-olvido",
        "name": "Sombra del Olvido",
        "subtype": "PICARO_VENENO",
        "levelOffset": 2,
        "profile": null,
        "probabilityByHeroType": { "*": 0.15 },
        "epic": {
          "epicRef": "velo-de-sombras",
          "name": "Velo de Sombras",
          "generalEffect": "+2 a la defensa para todos los héroes.",
          "epicEffect": "Solo Pícaro Veneno: intangible durante 1 turno y envenena al atacante (+3 de daño durante 2 turnos).",
          "productId": null
        }
      }
    ]
  }
}
```

- `probabilityByHeroType` admite la clave `"*"` como valor para cualquier subtipo. El ejemplo del curso da una sola probabilidad; la Tabla 20 da una por tipo. La fuente queda pendiente (decisión 1 del diseño).
- `levelOffset: 2` es literal de la HU. `profile: null`: las estadísticas base son contenido pendiente.
- `epic.productId`: el producto de Catalog que se entregará. Hoy no existe (decisión 7).

Validaciones al cargar la definición:

| Regla | Error |
| --- | --- |
| Cada probabilidad entre `0` y `1` | `INVALID_MASTER_CONFIG`, `reason: PROBABILITY_OUT_OF_RANGE` |
| `masterRef`, `subtype` y `epic.epicRef` presentes | `INVALID_MASTER_CONFIG`, `reason: MISSING_REFERENCE` |
| Cada `afterEncounter` entre 1 y el número de encuentros | `INVALID_MASTER_CONFIG`, `reason: EVALUATION_POINT_OUT_OF_RANGE` |
| `maxAppearances` ≥ 1 | `INVALID_MASTER_CONFIG`, `reason: INVALID_MAX_APPEARANCES` |

## Fragmento de la solicitud de simulación (HU-72)

Missions resuelve la probabilidad para el subtipo del héroe matriculado y envía solo lo que Combat necesita:

```json
{
  "master": {
    "evaluationPoints": [{ "afterEncounter": 3 }],
    "maxAppearances": 1,
    "candidates": [
      { "masterRef": "sombra-del-olvido", "subtype": "PICARO_VENENO", "probability": 0.15, "levelOffset": 2, "profile": null, "epicRef": "velo-de-sombras" }
    ]
  }
}
```

Si ningún candidato tiene probabilidad para el subtipo del héroe, Missions **no** envía el bloque y registra `NOT_APPLICABLE`.

## Fragmento del resultado (en `summary.master` de HU-72)

Máster que aparece y cae (M-3):

```json
{
  "master": {
    "appeared": true,
    "masterRef": "sombra-del-olvido",
    "defeated": true,
    "evaluations": [
      { "afterEncounter": 3, "masterRef": "sombra-del-olvido", "appeared": true }
    ],
    "encounters": [
      { "masterRef": "sombra-del-olvido", "afterEncounter": 3, "levelOffset": 2, "outcome": "DEFEATED", "turns": 14 }
    ]
  }
}
```

- `outcome` del encuentro: `DEFEATED` (cae el Máster), `HERO_DEFEATED` (cae el héroe) o `ESCAPED` (nadie cae dentro del límite).
- `appeared`, `masterRef` y `defeated` se conservan como resumen para HU-72 y HU-74.
- La bitácora añade los eventos `masterAppeared` y `combatantDefeated` del encuentro.

## Entrega de la épica (Player/Inventory, contrato de HU-59)

```text
POST /api/internal/v1/inventory/grants
x-internal-service: missions
```

```json
{
  "operationId": "8f1d2c3b-4a5e-5f60-9b7c-1d2e3f4a5b6c",
  "playerId": "cognito-sub-del-jugador",
  "items": [{ "productId": "<epic.productId>", "quantity": 1 }]
}
```

- `operationId`: UUID v5 calculado con la matrícula, el `masterRef` y el número de aparición. El mismo cierre, repetido, produce el mismo `operationId`, y Player/Inventory no entrega dos veces.
- Condiciones: estado `APPEARED_DEFEATED` y misión distinta de `VOIDED`.
- Requiere que Player/Inventory autorice a `missions` en esta ruta (decidido en ADR-019, sin implementar) y que la épica exista como producto en Catalog.

| Respuesta | Qué hace Missions |
| --- | --- |
| `200` | Anota `grantedAt` |
| `503` o sin respuesta | Reintenta con el mismo `operationId` |
| `409` | El `operationId` llegó con otro cuerpo: error de programación, se registra |
| `422` | Producto inexistente o no entregable: se registra y queda para revisión |

## Añadido al hecho `MissionSettled` (HU-72)

```json
{
  "masterEncounters": [
    { "sequence": 1, "afterEncounter": 3, "masterRef": "sombra-del-olvido", "status": "APPEARED_DEFEATED", "epicRef": "velo-de-sombras" }
  ]
}
```

## Fuera de este contrato

- Cómo convierte Combat su índice aleatorio en una tirada y cómo calcula las estadísticas del Máster: Combat (ADR-021).
- Acreditar la épica y rechazar otras vías de obtención: HU-32 y Player/Inventory.
- Usar la épica en combate: HU-31 y Combat.

## Extensión «misiones jugables» (compatible)

Diseño: [misiones-jugabilidad.md](../architecture/misiones-jugabilidad.md). Solo añade campos y rutas; nada se quita ni se renombra.

- Cada épica oficial de la Tabla 20 la entrega exactamente un Máster de su tipo, y una misión puede tener varios candidatos (P-J3). La Sombra del Olvido entrega «Toma y lleva».
- El detalle muestra `epic: null` para un candidato cuya épica aún no es un producto (P-J2).
- La probabilidad de aparición mejora con la dificultad (P-J8).
