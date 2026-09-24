# Contrato conceptual — matriculación en una misión (HU-70)

**Estado:** conceptual. **No implementado.** En `develop`, `Nexus-Battle-Missions` no tiene rutas de negocio. Este archivo no autoriza a marcar [service-catalog.md](service-catalog.md) como si las operaciones existieran.

Trazabilidad: [HU-70 #55](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/55) y [TASK HU-70.1 #365](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/365). Diseño: [hu-70-matriculacion-mision.md](../architecture/hu-70-matriculacion-mision.md). Borrador OpenAPI de las rutas públicas: [hu-70-mission-enrollment-v1.openapi.yaml](hu-70-mission-enrollment-v1.openapi.yaml). Escenarios: [hu-70-mission-enrollment-fixtures-v1.json](hu-70-mission-enrollment-fixtures-v1.json).

La matrícula es de HU-70. HU-75 la **extiende** con `difficulty`, `400 UNKNOWN_DIFFICULTY` y `422 PROGRESSION_LOCKED` ([Infrastructure#125](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/125)); HU-71 añade `strategyVersion` y `409 STRATEGY_VERSION_MISMATCH` ([contrato de HU-71](hu-71-mission-strategy-v1.md#extensión-de-la-matrícula-de-hu-70)).

Los datos de ejemplo salen de la misión «El Templo Olvidado» del documento del curso (§7.8.14). Son una muestra, no contenido aprobado.

## Vocabulario

```text
category         = STORY | CHALLENGE | EXPLORATION
playerStatus     = AVAILABLE | LOCKED | IN_PROGRESS | COMPLETED | FAILED | ABANDONED
enrollmentStatus = PENDING | IN_PROGRESS | COMPLETED | FAILED | ABANDONED | REJECTED | EXPIRED
difficulty       = NORMAL | HEROIC | LEGENDARY | MYTHIC        (HU-75)
busyWith         = MISSION | BATTLE | TOURNAMENT | AUCTION
```

- Duraciones en ISO-8601 (`PT12H`). Instantes en UTC (`2026-10-01T15:00:00Z`), siempre fijados por el servidor.
- Probabilidades como fracción entre `0` y `1`.
- `heroId` es el UUID del héroe del jugador en Player/Inventory. Missions no lo interpreta.

## Operaciones del jugador

Prefijo previsto por ADR-019: `/api/v1/missions`. Autenticación: JWT de Cognito con rol `PLAYER`. El jugador es siempre el `sub` del token; ninguna ruta acepta un `playerId`.

### Consultar el tablón

```text
GET /api/v1/missions?category=STORY&status=AVAILABLE
```

Los dos filtros son opcionales. Respuesta `200`:

```json
{
  "items": [
    {
      "missionId": "msn_templo_olvidado",
      "name": "El Templo Olvidado",
      "category": "STORY",
      "summary": "Un templo custodiado por criaturas corrompidas y un guardián milenario.",
      "imageRef": null,
      "estimatedDuration": "PT12H",
      "recommendedPower": 15,
      "highlightedRewards": [{ "label": "50 créditos" }, { "label": "1 Cofre de Bronce" }],
      "playerStatus": "AVAILABLE",
      "canEnroll": true,
      "lockReason": null,
      "activeEnrollmentId": null
    },
    {
      "missionId": "msn_camara_sellada",
      "name": "La Cámara Sellada",
      "category": "STORY",
      "summary": "Ejemplo de misión con requisito previo.",
      "imageRef": null,
      "estimatedDuration": "PT6H",
      "recommendedPower": 18,
      "highlightedRewards": [{ "label": "80 créditos" }],
      "playerStatus": "LOCKED",
      "canEnroll": false,
      "lockReason": "Completa primero «El Templo Olvidado».",
      "activeEnrollmentId": null
    }
  ]
}
```

`playerStatus` y `canEnroll` se derivan como explica el [diseño](../architecture/hu-70-matriculacion-mision.md#estado-de-la-misión-para-el-jugador). El tablón solo lista misiones activas.

### Ver el detalle de una misión

```text
GET /api/v1/missions/{missionId}
```

Respuesta `200`, con todos los bloques que exige CA-06:

```json
{
  "missionId": "msn_templo_olvidado",
  "name": "El Templo Olvidado",
  "category": "STORY",
  "narrative": "En las profundidades del Bosque Sombrío yace un antiguo templo dedicado a los Dioses Olvidados…",
  "objectives": [
    { "id": "obj_guardian", "text": "Derrotar al Guardián del Templo.", "primary": true },
    { "id": "obj_camaras", "text": "Explorar las 5 cámaras del templo.", "primary": true },
    { "id": "obj_vida", "text": "Completar la misión sin que la vida del héroe baje del 50 %.", "primary": false }
  ],
  "estimatedDuration": "PT12H",
  "recommendedPower": 15,
  "prerequisites": [],
  "enemies": [
    { "name": "Sombras Corrompidas", "count": 10, "description": "Enemigos básicos con ataque moderado." },
    { "name": "Guardianes de Piedra", "count": 5, "description": "Enemigos con alta defensa." },
    { "name": "Espectros Ancestrales", "count": 3, "description": "Enemigos con ataques mágicos." }
  ],
  "finalBoss": {
    "name": "El Guardián Eterno",
    "heroType": "GUERRERO_TANQUE",
    "description": "Guerrero Tanque con habilidades potenciadas.",
    "stats": { "health": 100 }
  },
  "masterEncounter": {
    "probability": 0.15,
    "candidates": [
      {
        "name": "Sombra del Olvido",
        "heroType": "PICARO_VENENO",
        "epic": {
          "name": "Velo de Sombras",
          "generalEffect": "+2 a la defensa para todos los héroes.",
          "epicEffect": "Solo Pícaro Veneno: intangible durante 1 turno y envenena al atacante (+3 de daño durante 2 turnos)."
        }
      }
    ]
  },
  "rewards": {
    "guaranteed": [{ "label": "50 créditos" }, { "label": "1 Cofre de Bronce" }],
    "potential": [
      { "label": "Fragmento del Sello Antiguo", "probability": 0.6, "rolls": 3 },
      { "label": "Armadura «Piel del Guardián»", "probability": 0.2, "rolls": 1 },
      { "label": "Arma «Espada del Templo»", "probability": 0.15, "rolls": 1 }
    ],
    "objectiveBonuses": [],
    "firstTime": [{ "label": "10 créditos adicionales" }, { "label": "Título «Explorador del Templo»" }]
  },
  "playerStatus": "AVAILABLE",
  "canEnroll": true,
  "lockReason": null
}
```

Misión inexistente o inactiva: `404 MISSION_NOT_FOUND`.

### Matricular un héroe

```text
POST /api/v1/missions/{missionId}/enrollments
Authorization: Bearer <JWT>
Idempotency-Key: 3b9f6c1e-8d2a-4f7b-9c4e-5a6b7c8d9e0f
```

```json
{
  "heroId": "7f3c2a9e-2d4b-4c1a-9e7f-1b2c3d4e5f60",
  "difficulty": "NORMAL",
  "strategyVersion": 1
}
```

- `Idempotency-Key`: UUID que Web genera al pulsar «Iniciar misión» y reutiliza en los reintentos de esa misma pulsación.
- `difficulty`: obligatorio; su vocabulario y su validación son de HU-75.
- `strategyVersion`: versión de la estrategia de rotaciones que el jugador tiene delante (HU-71), o `null` si no guardó ninguna. La matrícula congela esa estrategia para la simulación.

Respuesta `201`:

```json
{
  "enrollmentId": "enr_01JB8Y3K7Q",
  "missionId": "msn_templo_olvidado",
  "heroId": "7f3c2a9e-2d4b-4c1a-9e7f-1b2c3d4e5f60",
  "difficulty": "NORMAL",
  "status": "IN_PROGRESS",
  "startedAt": "2026-10-01T15:00:00Z",
  "endsAt": "2026-10-02T03:00:00Z"
}
```

`endsAt = startedAt + estimatedDuration`. Los dos los fija el servidor.

## Orden de validación

Missions evalúa en este orden y responde con el **primer** fallo (propuesta P-M4 del diseño):

1. Autenticación y rol (`401`, `403`).
2. Cuerpo y cabecera (`400`).
3. La misión existe y está activa (`404`).
4. La `Idempotency-Key` ya se usó: se responde lo guardado (ver [reintentos](#reintentos-con-la-misma-clave)).
5. Requisitos previos (`422 MISSION_LOCKED`, CA-07).
6. Progresión de dificultad (`422 PROGRESSION_LOCKED`, HU-75).
7. La versión de la estrategia coincide con la guardada (`409 STRATEGY_VERSION_MISMATCH`, HU-71).
8. El jugador ya tiene esta misión en curso (`409 MISSION_ALREADY_IN_PROGRESS`, propuesta P-M2).
9. El héroe tiene otra matrícula activa en Missions (`409 HERO_BUSY`, CA-02).
10. Compromiso `MISSION` en Player/Inventory (`409 HERO_BUSY`, `422` o `503`, CA-03 y CA-04).

## Errores

Todos los errores tienen la forma `{ "code": "…", "message": "…" }` más los campos propios de cada código. Web muestra `message`; no inventa el texto.

| HTTP | `code` | Cuándo | CA |
| --- | --- | --- | --- |
| `400` | `VALIDATION_ERROR` | Falta `heroId`, no es un UUID o `strategyVersion` no es un entero positivo ni `null` | — |
| `400` | `IDEMPOTENCY_KEY_REQUIRED` | Falta la cabecera `Idempotency-Key` o no es un UUID | — |
| `400` | `UNKNOWN_DIFFICULTY` | `difficulty` ausente o fuera del vocabulario (HU-75) | — |
| `401` | `UNAUTHENTICATED` | Sin token o token no válido | — |
| `403` | `FORBIDDEN` | El token no tiene el rol `PLAYER` | — |
| `404` | `MISSION_NOT_FOUND` | La misión no existe o no está activa | — |
| `409` | `HERO_BUSY` | El héroe está en otra misión, batalla, torneo o subasta | CA-02, CA-03 |
| `409` | `MISSION_ALREADY_IN_PROGRESS` | El jugador ya tiene esta misión en curso (P-M2) | — |
| `409` | `IDEMPOTENCY_KEY_REUSED` | La misma clave llegó con otro cuerpo o para otra misión | — |
| `409` | `ENROLLMENT_EXPIRED` | La matrícula de esa clave caducó sin confirmarse; hay que empezar con una clave nueva | — |
| `409` | `STRATEGY_VERSION_MISMATCH` | `strategyVersion` no coincide con la estrategia guardada (HU-71) | — |
| `422` | `MISSION_LOCKED` | Falta completar un requisito previo | CA-07 |
| `422` | `PROGRESSION_LOCKED` | Falta el clear del nivel anterior (HU-75) | — |
| `422` | `LOADOUT_INCOMPLETE` | El héroe no tiene el mazo completo | CA-04 |
| `422` | `HERO_NOT_READY` | El héroe o una pieza equipada no está disponible (bloqueos de *readiness* de Player/Inventory) | — |
| `422` | `HERO_NOT_OWNED` | El héroe no es del jugador | — |
| `503` | `DEPENDENCY_UNAVAILABLE` | Player/Inventory no confirmó la reserva; la matrícula sigue `PENDING` | — |

Cuerpos de ejemplo:

```json
{ "code": "HERO_BUSY", "message": "Este héroe ya está en otra misión.", "heroId": "7f3c2a9e-2d4b-4c1a-9e7f-1b2c3d4e5f60", "busyWith": "MISSION" }
```

```json
{ "code": "MISSION_LOCKED", "message": "Completa primero «El Templo Olvidado».", "missionId": "msn_camara_sellada", "missingPrerequisites": ["msn_templo_olvidado"] }
```

```json
{ "code": "LOADOUT_INCOMPLETE", "message": "Tu héroe necesita el mazo completo: faltan 1 arma y 2 ítems.", "missingSlots": [{ "family": "WEAPON", "missing": 1 }, { "family": "ITEM", "missing": 2 }] }
```

```json
{ "code": "HERO_NOT_READY", "message": "Una pieza equipada ya no está en tu inventario.", "blockers": [{ "code": "EQUIPPED_PRODUCT_NOT_OWNED", "slot": "WEAPON_1" }] }
```

```json
{ "code": "DEPENDENCY_UNAVAILABLE", "message": "No pudimos confirmar la reserva del héroe. Vuelve a intentarlo en unos segundos.", "enrollmentId": "enr_01JB8Y3K7Q", "enrollmentStatus": "PENDING" }
```

Los nombres de familia (`WEAPON`, `ARMOR`, `ITEM`) y de ranura son ilustrativos: los fija Player/Inventory.

## Reintentos con la misma clave

La clave es única por jugador. Cuando llega una `Idempotency-Key` ya usada con el mismo cuerpo y la misma misión:

| Estado guardado de la matrícula | Respuesta |
| --- | --- |
| `IN_PROGRESS` o un estado final posterior | `201` con la matrícula en su estado actual |
| `REJECTED` | El mismo error que se respondió la primera vez |
| `PENDING` | `503 DEPENDENCY_UNAVAILABLE` con `enrollmentStatus: PENDING` |
| `EXPIRED` | `409 ENROLLMENT_EXPIRED` |

Con otro cuerpo u otra misión: `409 IDEMPOTENCY_KEY_REUSED`. Los rechazos anteriores a guardar la matrícula (pasos 1 a 9 del orden de validación) no se guardan: un reintento se vuelve a evaluar.

## Operación interna propuesta hacia Player/Inventory

**Propuesta para Team Alfa**, dueño de Player/Inventory. No existe hoy. Sigue el esquema interno vigente: prefijo `/api/internal/v1/<contexto>`, cabeceras `x-internal-service`, `x-internal-timestamp` y `x-internal-signature` (HMAC-SHA256 sobre JSON canónico) y bloqueo en Caddy.

### Crear el compromiso del héroe

```text
POST /api/internal/v1/inventory/heroes/{heroId}/commitments
x-internal-service: missions
```

```json
{
  "operationId": "op_01JB8Y3K7R",
  "playerId": "cognito-sub-del-jugador",
  "purpose": "MISSION",
  "reference": "enr_01JB8Y3K7Q",
  "expiresAt": "2026-10-02T03:32:00Z",
  "requirements": { "completeLoadout": true }
}
```

`expiresAt = requestedAt + 2 min + duración + 30 min` (propuesta P-M8 del diseño).

| HTTP | Respuesta | Qué hace Missions |
| --- | --- | --- |
| `201` | `{ "commitmentId": "cmt_…", "heroId": "…", "purpose": "MISSION", "reference": "enr_…", "expiresAt": "…" }` | `PENDING → IN_PROGRESS` |
| `201` (mismo `operationId` y mismo cuerpo) | El mismo compromiso: la operación es idempotente | Igual |
| `409` `OPERATION_ID_REUSED` | El `operationId` llegó con otro cuerpo | Error de programación: no se reintenta, se registra |
| `422` `HERO_NOT_OWNED` | El héroe no es del jugador | `REJECTED` |
| `422` `HERO_NOT_READY` | Bloqueos de *readiness* | `REJECTED` |
| `422` `LOADOUT_INCOMPLETE` | Faltan ranuras con `requirements.completeLoadout` | `REJECTED` |
| `422` `HERO_COMMITTED` | Ya tiene un compromiso vigente; incluye su `purpose` | `REJECTED` y `409 HERO_BUSY` al jugador |
| `503` o sin respuesta | Resultado desconocido | Sigue `PENDING` y se reintenta con el mismo `operationId` |

Player/Inventory también debe rechazar los cambios de equipamiento de un héroe con compromiso vigente (CA-05), como HU-29 prevé para las batallas.

### Liberar el compromiso

```text
POST /api/internal/v1/inventory/commitments/{operationId}/release
x-internal-service: missions
```

Responde `204` tanto si liberó un compromiso vigente como si no había ninguno. Así Missions puede liberar aunque no sepa si el compromiso llegó a crearse, que es justo el caso de una matrícula `PENDING` que caduca.

## Hecho interno al confirmar (para HU-72)

En la misma transacción que pasa la matrícula a `IN_PROGRESS`, Missions registra:

```json
{
  "type": "MissionEnrollmentStarted",
  "enrollmentId": "enr_01JB8Y3K7Q",
  "missionId": "msn_templo_olvidado",
  "playerId": "cognito-sub-del-jugador",
  "heroId": "7f3c2a9e-2d4b-4c1a-9e7f-1b2c3d4e5f60",
  "difficulty": "NORMAL",
  "startedAt": "2026-10-01T15:00:00Z",
  "endsAt": "2026-10-02T03:00:00Z"
}
```

Es un hecho **interno** de Missions: no sale a otra cola ni a otro servicio. Con él, HU-72 arranca la simulación («la simulación comienza automáticamente», §7.8.6).

## Fuera de este contrato

- Simulación, bitácora y liberación al terminar: HU-72.
- Guardar y validar las rotaciones: HU-71.
- Niveles de dificultad: HU-75.
- Reporte e historial: HU-74.
- Montos de recompensas: HU-10.
- Cancelar una misión con penalización y el panel de misiones activas: sin HU en Sprint 2.

## Extensión «misiones jugables» (compatible)

Diseño: [misiones-jugabilidad.md](../architecture/misiones-jugabilidad.md). Solo añade campos y rutas; nada se quita ni se renombra.

- `GET /api/v1/missions/{missionId}` añade:
  - `imageRef` (P-J11);
  - `prerequisiteMissions: [{ missionId, name }]` (P-J10);
  - `rewards` con la forma de P-J2: `experience`, y `potential` solo con botín enlazado a un producto;
  - `masterEncounter.candidates[].epic` en `null` si la épica aún no es un producto.
- `masterEncounter.probability` pasa a ser la probabilidad de que aparezca algún Máster en la misión, calculada por Missions: el 15 % que fijó el PO, la mayor según el tipo de héroe. Antes era la mayor probabilidad configurada de un candidato; con un solo candidato vale lo mismo.
- `GET /api/v1/missions`: `highlightedRewards` son la experiencia, las épicas posibles y los dos botines más probables (P-J2).
- Nueva `GET /api/v1/missions/{missionId}/estimate?heroId=&difficulty=` (P-J7).
  - Respuesta: `{ missionId, heroId, difficulty, strategyVersion, runs, successPercent, defeatPercent, timeoutPercent, risk, riskLabel, averageTurns, averageMinHealthPercent, masterAppearancePercent, abilities: [{ abilityId, name, usable, reason }] }`.
  - Errores: `400 UNKNOWN_DIFFICULTY`, `400 VALIDATION_ERROR` (`heroId` no es un UUID), `404 MISSION_NOT_FOUND`, `422 HERO_NOT_OWNED` y `503 ESTIMATE_UNAVAILABLE`, que no bloquea la matrícula.
