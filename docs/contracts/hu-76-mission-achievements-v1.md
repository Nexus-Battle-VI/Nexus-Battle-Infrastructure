# Contrato conceptual — logros de misiones (HU-76)

**Estado:** conceptual. **No implementado.** El catálogo es **de ejemplo**: ningún logro está otorgado en producción. Este archivo no autoriza a marcar [service-catalog.md](service-catalog.md) como si las operaciones existieran.

Trazabilidad: [HU-76 #61](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/61) y [TASK HU-76.1 #387](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/387). Diseño: [hu-76-logros-misiones.md](../architecture/hu-76-logros-misiones.md). Escenarios: [hu-76-mission-achievements-fixtures-v1.json](hu-76-mission-achievements-fixtures-v1.json).

## Vocabulario

```text
criterion         = ALL_CATEGORY_MISSIONS | ALL_MASTERS_DEFEATED | FLAWLESS_MISSION
                  | RECORD_TIME | ALL_MASTER_EPICS
achievementStatus = LOCKED | IN_PROGRESS | UNLOCKED
recognitionKind   = TITLE | BADGE | COSMETIC_PRODUCT
```

## Catálogo de ejemplo

```json
[
  { "achievementId": "ach_historia_completa", "version": 1, "criterion": "ALL_CATEGORY_MISSIONS", "params": { "category": "STORY" }, "recognition": { "kind": "TITLE", "name": "Cronista del Nexus" } },
  { "achievementId": "ach_desafio_completo", "version": 1, "criterion": "ALL_CATEGORY_MISSIONS", "params": { "category": "CHALLENGE" }, "recognition": { "kind": "BADGE", "name": "Insignia del Desafío" } },
  { "achievementId": "ach_exploracion_completa", "version": 1, "criterion": "ALL_CATEGORY_MISSIONS", "params": { "category": "EXPLORATION" }, "recognition": { "kind": "BADGE", "name": "Insignia del Explorador" } },
  { "achievementId": "ach_cazador_de_master", "version": 1, "criterion": "ALL_MASTERS_DEFEATED", "params": {}, "recognition": { "kind": "TITLE", "name": "Cazador de Máster" } },
  { "achievementId": "ach_sin_rasgunos", "version": 1, "criterion": "FLAWLESS_MISSION", "params": {}, "recognition": { "kind": "BADGE", "name": "Sin un rasguño" } },
  { "achievementId": "ach_templo_veloz", "version": 1, "criterion": "RECORD_TIME", "params": { "missionId": "msn_templo_olvidado", "maxSimulatedDuration": null }, "recognition": { "kind": "BADGE", "name": "Paso veloz" } },
  { "achievementId": "ach_coleccionista", "version": 1, "criterion": "ALL_MASTER_EPICS", "params": {}, "recognition": { "kind": "COSMETIC_PRODUCT", "name": "Estandarte del Coleccionista", "productId": null } }
]
```

- Nombres y reconocimientos son de ejemplo: el catálogo definitivo lo decide el PO (decisión 1 del diseño).
- `maxSimulatedDuration: null`: el umbral de «tiempo récord» está pendiente (decisión 3). Mientras sea `null`, ese logro no se evalúa.
- `productId: null`: el cosmético todavía no existe en Catalog.

## Hecho normalizado de misión terminada

Lo arma el evaluador a partir de `MissionSettled` (HU-72), la evidencia del Máster (HU-73) y el reporte (HU-74):

```json
{
  "type": "MissionFinishedForAchievements",
  "playerId": "cognito-sub-jugador-demo",
  "enrollmentId": "enr_01JB8Y3K7Q",
  "missionId": "msn_templo_olvidado",
  "category": "STORY",
  "difficulty": "NORMAL",
  "outcome": "COMPLETED",
  "damageTaken": 0,
  "simulatedDuration": "PT9H40M",
  "mastersDefeated": ["sombra-del-olvido"],
  "epicsCredited": ["velo-de-sombras"],
  "finishedAt": "2026-10-02T03:00:00Z"
}
```

Las misiones `ABANDONED` y `VOIDED` no generan este hecho (decisión 5 del diseño).

## Consultar los logros

```text
GET /api/v1/missions/me/achievements
```

JWT de Cognito con rol `PLAYER`. Respuesta `200`:

```json
{
  "items": [
    {
      "achievementId": "ach_sin_rasgunos",
      "name": "Sin un rasguño",
      "criterion": "FLAWLESS_MISSION",
      "status": "UNLOCKED",
      "progress": { "current": 1, "target": 1 },
      "unlockedAt": "2026-10-02T03:00:07Z",
      "recognition": { "kind": "BADGE", "name": "Sin un rasguño", "status": "RECORDED" }
    },
    {
      "achievementId": "ach_historia_completa",
      "name": "Cronista del Nexus",
      "criterion": "ALL_CATEGORY_MISSIONS",
      "status": "IN_PROGRESS",
      "progress": { "current": 1, "target": 2 },
      "unlockedAt": null,
      "recognition": { "kind": "TITLE", "name": "Cronista del Nexus", "status": null }
    },
    {
      "achievementId": "ach_coleccionista",
      "name": "Estandarte del Coleccionista",
      "criterion": "ALL_MASTER_EPICS",
      "status": "IN_PROGRESS",
      "progress": { "current": 1, "target": 2 },
      "unlockedAt": null,
      "recognition": { "kind": "COSMETIC_PRODUCT", "name": "Estandarte del Coleccionista", "status": null }
    }
  ]
}
```

- `progress.target` se calcula al leer: por ejemplo, las misiones activas de la categoría o los Máster disponibles (P-L6 del diseño).
- Un logro desbloqueado mantiene su `target` del momento del desbloqueo y no se revoca (P-L5).
- `401` / `403`: sin token o sin rol `PLAYER`.

## Entrega de un cosmético (Player/Inventory, contrato de HU-59)

Solo para `COSMETIC_PRODUCT`:

```text
POST /api/internal/v1/inventory/grants
{ "operationId": "<UUID v5 de jugador y logro>", "playerId": "…", "items": [{ "productId": "<recognition.productId>", "quantity": 1 }] }
```

El mismo jugador y logro producen siempre el mismo `operationId`: nunca dos entregas.

## Fuera de este contrato

- Mostrar los logros en el perfil: HU-76.3 (Web).
- Guardar títulos e insignias en el perfil de Account, si se decide así (decisión 4).
- Logros de otros módulos (JcJ, torneos).
