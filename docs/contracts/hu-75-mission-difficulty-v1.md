# Contrato de dificultad de misión (HU-75)

**Estado verificado:** `GET /api/v1/missions/{missionId}/difficulties` está en `develop` de Missions desde [#9](https://github.com/Nexus-Battle-VI/Nexus-Battle-Missions/pull/9), con OpenAPI generado por el servicio. `POST /api/v1/missions/{missionId}/enrollments` con `difficulty` está implementado en la rama de [Missions #15](https://github.com/Nexus-Battle-VI/Nexus-Battle-Missions/pull/15), aún en borrador; no se declara integrado en `develop`. La aplicación del escalado por Combat sigue pendiente.

Trazabilidad: [HU-75 #60](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/60), [TASK HU-75.1 #383](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/383). Diseño: [hu-75-dificultad-escalonada.md](../architecture/hu-75-dificultad-escalonada.md).

La matrícula pertenece a HU-70. HU-75 **extiende** ese acto; no crea un segundo inicio de misión.

## Vocabulario

```text
difficulty  = NORMAL | HEROIC | LEGENDARY | MYTHIC
rewardTier  = STANDARD | IMPROVED | PREMIUM | EXCLUSIVE
```

Descriptor de escalado: Missions publica los factores en `GET` y la rama de HU-72 los incluye en la solicitud a **Combat**. Missions no modifica estadísticas de enemigos.

| difficulty | enemyStatMultiplier (literal HU) | Estadísticas afectadas | Redondeo | rewardTier propuesto |
| --- | --- | --- | --- | --- |
| `NORMAL` | `1.0` | ninguna (base) | — | `STANDARD` |
| `HEROIC` | `1.5` | propuesta P-D6: Vida, Ataque y Defensa enemigas | **pendiente del PO** | `IMPROVED` |
| `LEGENDARY` | `2.0` | propuesta P-D6 | **pendiente del PO** | `PREMIUM` |
| `MYTHIC` | `null`: pendiente del PO, sin valor inventado | **pendiente del PO** | **pendiente del PO** | `EXCLUSIVE` |

Las celdas marcadas pendientes son las decisiones abiertas 1 y 2 del [diseño](../architecture/hu-75-dificultad-escalonada.md#decisiones-pendientes-visibles-no-resueltas), no huecos que HU-75.2 pueda rellenar por su cuenta.

## Operaciones del jugador

Prefijo HTTP: `/api/v1/missions`. Autenticación: JWT de Cognito con rol `PLAYER` en el servicio productivo; la identidad se toma del testimonio, nunca de un parámetro de jugador.

### Listar desbloqueo de una misión

```text
GET /api/v1/missions/{missionId}/difficulties
```

Respuesta 200 (forma publicada por Missions):

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

Para `MYTHIC`, `enemyStatMultiplier` es `null` hasta que el PO publique el número. Un `missionId` con formato válido pero ausente del catálogo recibe actualmente los cuatro niveles sin progreso: esta ruta todavía no valida la existencia de la misión. El `missionId` mal formado produce `400`; sin testimonio o sin rol `PLAYER`, `401` o `403`; una caída del repositorio de progreso, `503`.

### Matricular eligiendo dificultad

Extiende el `POST` de HU-70, implementado en la rama de [Missions #15](https://github.com/Nexus-Battle-VI/Nexus-Battle-Missions/pull/15), que también documenta la matrícula. Esta sección fija solo la parte de dificultad.

```text
POST /api/v1/missions/{missionId}/enrollments
```

La petición requiere `Idempotency-Key` con un UUID. Cuerpo mínimo relevante:

```json
{
  "heroId": "7f3c2a9e-2d4b-4c1a-9e7f-1b2c3d4e5f60",
  "difficulty": "HEROIC"
}
```

| Código | Condición |
| --- | --- |
| 201 | Progresión cumplida y HU-70 acepta al héroe; la respuesta conserva `difficulty` |
| 400 | `difficulty` ausente o fuera del vocabulario (`UNKNOWN_DIFFICULTY`), o cabecera idempotente inválida |
| 401 | Sin testimonio |
| 403 | Testimonio sin rol `PLAYER` |
| 404 | Misión inexistente (`MISSION_NOT_FOUND`) |
| 409 | Héroe ocupado o matrícula ya activa, entre otros errores de HU-70 |
| 422 | Falta el clear del nivel anterior (`PROGRESSION_LOCKED`) |
| 503 | Dependencia de reserva no disponible; se reintenta con la misma clave |

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

Web muestra `message`. No inventa el texto ni calcula el desbloqueo. La matrícula guarda `difficulty`; `rewardTier` no forma parte de su entidad persistida ni de su respuesta actual. Es un descriptor publicado por `GET`, pendiente de la liquidación de HU-10.

## Fixtures por estado de progresión

Respuestas de `GET /api/v1/missions/{missionId}/difficulties` para un mismo jugador y una misma misión, según sus clears. Solo se muestran `difficulty`, `unlocked` y `lockReason`; el resto de campos no cambia entre estados.

Sin clears:

```json
[
  { "difficulty": "NORMAL", "unlocked": true, "lockReason": null },
  { "difficulty": "HEROIC", "unlocked": false, "lockReason": "Debes completar esta misión en Normal al menos una vez." },
  { "difficulty": "LEGENDARY", "unlocked": false, "lockReason": "Debes completar esta misión en Heroico al menos una vez." },
  { "difficulty": "MYTHIC", "unlocked": false, "lockReason": "Debes completar esta misión en Legendario al menos una vez." }
]
```

Clear en `NORMAL`:

```json
[
  { "difficulty": "NORMAL", "unlocked": true, "lockReason": null },
  { "difficulty": "HEROIC", "unlocked": true, "lockReason": null },
  { "difficulty": "LEGENDARY", "unlocked": false, "lockReason": "Debes completar esta misión en Heroico al menos una vez." },
  { "difficulty": "MYTHIC", "unlocked": false, "lockReason": "Debes completar esta misión en Legendario al menos una vez." }
]
```

Clears en `NORMAL` y `HEROIC`: `LEGENDARY` pasa a `unlocked: true`; `MYTHIC` sigue bloqueado con el mismo `lockReason`.

Clears en `NORMAL`, `HEROIC` y `LEGENDARY`: los cuatro niveles `unlocked: true`; `MYTHIC` lleva `enemyStatMultiplier: null` hasta que el PO lo publique.

Rechazo de matrícula que estos estados producen:

```json
{ "code": "PROGRESSION_LOCKED", "message": "No puedes iniciar esta misión en Legendario: primero complétala en Heroico.", "requested": "LEGENDARY", "required": "HEROIC" }
```

Ese mismo cuerpo responde tanto al salto de nivel (solo hay clear en `NORMAL`) como a un clear de `HEROIC` conseguido en **otra** misión o por **otro** jugador: la política solo mira `clears(playerId, missionId)`. La tabla completa de casos está en la [matriz de transición y aislamiento](../architecture/hu-75-dificultad-escalonada.md#matriz-de-transición-y-aislamiento).

## Operación interna hacia Combat (HU-72)

```text
POST /api/internal/v1/combat/simulations
```

La solicitud completa se prepara y documenta en la rama de [Missions #15](https://github.com/Nexus-Battle-VI/Nexus-Battle-Missions/pull/15) como parte de HU-72. Aporta, entre otros, estos campos además del perfil del héroe y las rotaciones:

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
- Si `difficulty = MYTHIC`, Missions envía `enemyStatMultiplier: null`. Combat todavía no aplica ningún escalado de misión; su [PR #44](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/44) solo recibe y registra la solicitud y responde `503`. La política real para Mítico requiere definición del PO.

## Hecho interno al éxito

La rama de HU-72 en Missions #15 inserta el clear idempotente al cerrar una matrícula `COMPLETED`; fallo, anulación y matrícula sin terminar no lo insertan:

```text
(playerId, missionId, difficulty) único
```

Ese insert es lo que desbloquea el siguiente nivel. Matricular no desbloquea. La ruta de Combat que devuelve una simulación real todavía no existe, de modo que esta transición no está demostrada entre servicios en producción.

## Fuera de este contrato

- Tablón, bloqueo del héroe, temporizador: HU-70.
- Bitácora y motor de daño: HU-72 / Combat.
- Montos de créditos e ítems: HU-10.
- Reporte para el jugador: HU-74.

## Extensión «misiones jugables» (compatible)

Diseño: [misiones-jugabilidad.md](../architecture/misiones-jugabilidad.md). Solo añade campos y rutas; nada se quita ni se renombra.

- `GET /api/v1/missions/{missionId}/difficulties`: cada nivel añade `extraEnemiesPerEncounter`, `bossEnrageBonus` y `lootBonusPercent` (P-J8). Los valores están en la tabla del diseño. La probabilidad del Máster no cambia con el nivel: el PO la fijó en el 15 % por misión.
