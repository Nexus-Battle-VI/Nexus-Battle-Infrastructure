# Contrato conceptual — reporte e historial de misiones (HU-74)

**Estado:** conceptual. **No implementado.** Este archivo no autoriza a marcar [service-catalog.md](service-catalog.md) como si las operaciones existieran. Los bloques que dependen de las propuestas de HU-72 y HU-73 son **provisionales** (ver el [diseño](../architecture/hu-74-reporte-mision.md#campos-y-quién-los-produce)).

Trazabilidad: [HU-74 #59](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/59) y [TASK HU-74.1 #379](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/379). Escenarios: [hu-74-mission-report-fixtures-v1.json](hu-74-mission-report-fixtures-v1.json).

## Vocabulario

```text
outcome      = COMPLETED | FAILED | ABANDONED            (reporte)
historyOutcome = COMPLETED | FAILED | ABANDONED | VOIDED (historial; VOIDED sin reporte)
rewardKind   = CREDITS | PRODUCT | EPIC | EXPERIENCE
rewardStatus = PENDING | CREDITED | FAILED
```

## Operaciones del jugador

Prefijo `/api/v1/missions/me`. JWT de Cognito con rol `PLAYER`; siempre del jugador del token.

### Consultar un reporte

```text
GET /api/v1/missions/me/reports/{enrollmentId}
```

Respuesta `200` (misión del curso completada; valores ilustrativos):

```json
{
  "schemaVersion": 1,
  "enrollmentId": "enr_01JB8Y3K7Q",
  "mission": { "missionId": "msn_templo_olvidado", "name": "El Templo Olvidado", "category": "STORY", "difficulty": "NORMAL" },
  "summary": {
    "outcome": "COMPLETED",
    "outcomeReason": null,
    "hero": { "heroId": "7f3c2a9e-2d4b-4c1a-9e7f-1b2c3d4e5f60", "name": "Kaelen", "subtype": "PICARO_VENENO" },
    "startedAt": "2026-10-01T15:00:00Z",
    "finishedAt": "2026-10-02T03:00:00Z",
    "simulatedDuration": "PT9H40M"
  },
  "combatStats": {
    "encountersCompleted": 5,
    "encountersTotal": 5,
    "totalTurns": 142,
    "damageDealt": 1830,
    "damageTaken": 640,
    "criticalEffects": 9,
    "skillsUsed": [{ "abilityId": "golpe-de-tormenta", "count": 22 }, { "abilityId": "BASIC_ATTACK", "count": 61 }]
  },
  "enemies": {
    "defeated": [
      { "enemyRef": "sombra-corrompida", "name": "Sombra Corrompida", "count": 10 },
      { "enemyRef": "guardian-de-piedra", "name": "Guardián de Piedra", "count": 5 },
      { "enemyRef": "espectro-ancestral", "name": "Espectro Ancestral", "count": 3 }
    ],
    "boss": { "enemyRef": "guardian-eterno", "name": "El Guardián Eterno", "defeated": true },
    "masters": [{ "masterRef": "sombra-del-olvido", "name": "Sombra del Olvido", "status": "APPEARED_DEFEATED" }]
  },
  "objectives": [
    { "id": "obj_guardian", "text": "Derrotar al Guardián del Templo.", "primary": true, "met": true, "bonus": null },
    { "id": "obj_camaras", "text": "Explorar las 5 cámaras del templo.", "primary": true, "met": true, "bonus": null },
    { "id": "obj_vida", "text": "Completar la misión sin que la vida del héroe baje del 50 %.", "primary": false, "met": false, "bonus": null },
    { "id": "obj_master", "text": "Derrotar al Máster si aparece.", "primary": false, "met": true, "bonus": null }
  ],
  "rewards": [
    { "kind": "EPIC", "reference": "velo-de-sombras", "name": "Velo de Sombras", "rarity": null, "quantity": 1, "status": "CREDITED", "source": "HU-73" },
    { "kind": "CREDITS", "reference": null, "name": "Créditos", "rarity": null, "quantity": 50, "status": "PENDING", "source": "HU-10" }
  ],
  "generatedAt": "2026-10-02T03:00:05Z"
}
```

- `rewards[].status` es lo único que cambia con el tiempo. El resto es la foto del cierre.
- `objectives[].met: null` significa que el objetivo no aplicó (por ejemplo, el Máster no apareció).
- `bonus` queda en `null` hasta que HU-10 defina las bonificaciones por objetivo.

| HTTP | `code` | Cuándo |
| --- | --- | --- |
| `404` | `REPORT_NOT_AVAILABLE` | La matrícula es del jugador y sigue en curso (CA-04) |
| `404` | `REPORT_NOT_FOUND` | No existe, es de otro jugador o terminó `VOIDED` |
| `401` / `403` | `UNAUTHENTICATED` / `FORBIDDEN` | Sin token o sin rol `PLAYER` |

```json
{ "code": "REPORT_NOT_AVAILABLE", "message": "La misión sigue en curso. El reporte estará listo cuando termine.", "enrollmentId": "enr_01JB8Y3K7Q", "endsAt": "2026-10-02T03:00:00Z" }
```

### Consultar el historial

```text
GET /api/v1/missions/me/history?limit=20&cursor=<opaco>
```

```json
{
  "items": [
    {
      "enrollmentId": "enr_01JB8Y3K7Q",
      "missionId": "msn_templo_olvidado",
      "name": "El Templo Olvidado",
      "category": "STORY",
      "difficulty": "NORMAL",
      "outcome": "COMPLETED",
      "finishedAt": "2026-10-02T03:00:00Z",
      "simulatedDuration": "PT9H40M",
      "reportAvailable": true
    },
    {
      "enrollmentId": "enr_01JB9A0000",
      "missionId": "msn_templo_olvidado",
      "name": "El Templo Olvidado",
      "category": "STORY",
      "difficulty": "NORMAL",
      "outcome": "VOIDED",
      "finishedAt": "2026-09-30T10:00:00Z",
      "simulatedDuration": null,
      "reportAvailable": false
    }
  ],
  "nextCursor": null
}
```

Orden: `finishedAt` descendente. `limit` entre 1 y 50 (por defecto 20). Solo misiones terminadas; las `VOIDED` aparecen sin reporte (P-T3 del diseño).

### Consultar el resumen del historial (CA-05)

```text
GET /api/v1/missions/me/history/summary
```

```json
{
  "byCategory": [
    { "category": "STORY", "completed": 3, "failed": 1, "abandoned": 0, "damageDealt": 5210, "damageTaken": 2240 },
    { "category": "EXPLORATION", "completed": 0, "failed": 0, "abandoned": 0, "damageDealt": 0, "damageTaken": 0 }
  ],
  "bestTimes": [
    { "missionId": "msn_templo_olvidado", "difficulty": "NORMAL", "simulatedDuration": "PT8H55M", "enrollmentId": "enr_01JB7Z" }
  ],
  "epicCollection": [
    { "epicRef": "velo-de-sombras", "name": "Velo de Sombras", "masterRef": "sombra-del-olvido", "obtainedAt": "2026-10-02T03:00:05Z", "status": "CREDITED" }
  ],
  "narrativeProgress": [
    { "chainId": "templo", "missions": ["msn_templo_olvidado", "msn_camara_sellada"], "completed": 1, "total": 2 }
  ]
}
```

- `bestTimes`: mínimo de `simulatedDuration` entre las misiones completadas, por misión y dificultad (P-T5).
- `narrativeProgress`: cadenas de misiones `STORY` unidas por requisitos previos (P-T6).
- `epicCollection`: épicas ganadas en misiones, con el estado de su entrega.

## Fuera de este contrato

- Calcular y entregar créditos, productos y experiencia: HU-10.
- Acreditar las épicas: HU-32 y Player/Inventory.
- Exponer la bitácora completa: no se incluye en el reporte (decisión 7 del diseño).
