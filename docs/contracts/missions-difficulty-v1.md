# Contrato conceptual — dificultad de misión (HU-75)

**Estado:** conceptual. **No implementado.** No hay OpenAPI ni rutas de negocio en `Nexus-Battle-Missions`. Este archivo no autoriza a marcar [service-catalog.md](service-catalog.md) como si las operaciones existieran.

Trazabilidad: [HU-75 #60](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/60), [TASK HU-75.1 #383](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/383). Diseño: [hu-75-dificultad-escalonada.md](../architecture/hu-75-dificultad-escalonada.md).

La matrícula pertenece a HU-70. HU-75 **extiende** ese acto; no crea un segundo inicio de misión.

## Vocabulario

```text
difficulty  = NORMAL | HEROIC | LEGENDARY | MYTHIC
rewardTier  = STANDARD | IMPROVED | PREMIUM | EXCLUSIVE
```

| difficulty | enemyStatMultiplier (literal HU) | rewardTier propuesto |
| --- | --- | --- |
| `NORMAL` | `1.0` | `STANDARD` |
| `HEROIC` | `1.5` | `IMPROVED` |
| `LEGENDARY` | `2.0` | `PREMIUM` |
| `MYTHIC` | *pendiente del PO — no inventar* | `EXCLUSIVE` |

## Operaciones conceptuales (jugador)

Prefijo previsto por ADR-019: `/api/v1/missions`. Autenticación: JWT de Cognito.

### Listar desbloqueo de una misión

```text
GET /api/v1/missions/{missionId}/difficulties
```

Respuesta 200 (forma, no esquema publicado):

```json
{
  "missionId": "msn_…",
  "items": [
    {
      "difficulty": "NORMAL",
      "unlocked": true,
      "lockReason": null,
      "enemyStatMultiplier": 1.0,
      "rewardTier": "STANDARD"
    },
    {
      "difficulty": "HEROIC",
      "unlocked": false,
      "lockReason": "Debes completar esta misión en Normal al menos una vez.",
      "enemyStatMultiplier": 1.5,
      "rewardTier": "IMPROVED"
    }
  ]
}
```

Para `MYTHIC`, `enemyStatMultiplier` se omite o va `null` hasta que el PO publique el número.

### Matricular eligiendo dificultad

Extiende el `POST` previsto de HU-70:

```text
POST /api/v1/missions/{missionId}/enrollments
```

Cuerpo adicional respecto de HU-70:

```json
{
  "heroId": "hero_…",
  "difficulty": "HEROIC"
}
```

| Código | Condición |
| --- | --- |
| 201 | Progresión cumplida y HU-70 acepta al héroe |
| 400 | `difficulty` ausente o fuera del vocabulario (`UNKNOWN_DIFFICULTY`) |
| 401 | Sin testimonio |
| 422 | Falta el clear del nivel anterior (`PROGRESSION_LOCKED`) |

Cuerpo de 422:

```json
{
  "code": "PROGRESSION_LOCKED",
  "message": "No puedes iniciar esta misión en Legendario: primero complétala en Heroico.",
  "missionId": "msn_…",
  "requested": "LEGENDARY",
  "required": "HEROIC"
}
```

Web muestra `message`. No inventa el texto.

## Operación interna hacia Combat (HU-72)

```text
POST /api/internal/v1/combat/simulations
```

Campos que Missions aporta además del perfil del héroe y las rotaciones:

```json
{
  "operationId": "op_…",
  "enrollmentId": "enr_…",
  "difficulty": "HEROIC",
  "enemyStatMultiplier": 1.5
}
```

Reglas:

- HMAC interno (ADR-019). No sale por Caddy.
- Missions **ya** validó progresión. Combat no la relaja.
- Si `difficulty = MYTHIC` y aún no hay multiplicador aprobado, **no** se fabrica uno en Missions. O se bloquea la simulación con error de configuración, o Combat usa una tabla publicada por el PO. Las dos opciones se registran; ninguna se implementa en 75.1.

## Hecho interno al éxito

Al `SUCCESS` de la simulación, Missions inserta un clear idempotente:

```text
(playerId, missionId, difficulty) único
```

Ese insert es lo que desbloquea el siguiente nivel. Matricular no desbloquea.

## Fuera de este contrato

- Tablón, bloqueo del héroe, temporizador: HU-70.
- Bitácora y motor de daño: HU-72 / Combat.
- Montos de créditos e ítems: HU-10.
- Reporte para el jugador: HU-74.
