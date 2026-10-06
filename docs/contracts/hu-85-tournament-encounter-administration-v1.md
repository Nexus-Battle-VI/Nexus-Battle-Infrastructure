# HU-85 — Preparación e inicio de justas independientes, revisión 1

Versión común: `torneos-hu77-84-78-hu83-v2.0.0` (sin cambios: HU-85 solo añade rutas y no modifica los contratos publicados).
Estado: **propuesta técnica para implementación local (HU-85.1, Management#485). Pendiente de revisión por los responsables; no se atribuye aprobación a ningún equipo.** Las decisiones de negocio marcadas «NO APROBADA» no se pueden implementar como reglas.

Fuente vigente: [HU-85 #470](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/470). Depende del bracket publicado ([HU-78](hu-78-tournament-bracket-v2.md)), de las consultas ([HU-83](hu-78-83-query-compatibility-v2.md)) y de las rutas internas de torneo de Combat (`/api/internal/v1/combat/tournament-rooms`).

## Alcance

Un administrador autorizado **prepara** y **inicia** cada justa del bracket de forma independiente. Preparar pide a Combat una sala y conserva su identificador; iniciar le pide arrancar esa misma sala. Cada acción deja un recibo con actor, justa, acción y fecha. No hay dependencia de la transmisión ni de un único operador: E1 y E2 (o cualquier par de justas con equipos resueltos) se preparan e inician sin esperarse.

Fuera de alcance: avance del bracket por resultados (HU-80), cálculo de ganadores, premios, calendario, ausencias, reprogramación y cancelación (ver «Decisiones pendientes»).

## Vocabulario

`battleId` del encargo es el `combatRoomId` que ya expone HU-83 y el `roomId` de Combat. No se crea un identificador nuevo; se conserva el mismo valor en los tres nombres.

| Campo | Valores | Dueño |
| --- | --- | --- |
| `status` (HU-83) | `WAITING_PARTICIPANTS`, `READY`, `IN_PROGRESS`, `FINISHED` | Tournament |
| `preparationStatus` (HU-83) | `WAITING_TEAMS`, `TEAMS_RESOLVED`, `PREPARING`, `PREPARED`, `START_PENDING`, `IN_BATTLE`, `FINISHED` | Tournament |
| Estado de sala | `PREPARING`, `IN_BATTLE`, `FINISHED` | Combat |

Transiciones de HU-85 (todas las demás las rechaza el servidor):

| Acción | Desde `preparationStatus` | Durante | Hacia (`status`, `preparationStatus`) |
| --- | --- | --- | --- |
| Preparar | `TEAMS_RESOLVED` | llamada a Combat | `READY`, `PREPARED` (+ `combatRoomId`; equipos y héroes los proyecta Combat, HU-83) |
| Iniciar | `PREPARED` | llamada a Combat | `IN_PROGRESS`, `IN_BATTLE` (+ `startedAt` autoritativo de Combat) |
| Repetir Preparar | `PREPARED`, `START_PENDING`, `IN_BATTLE`, `FINISHED` | — | sin cambios, misma sala (`replayed:true`) |
| Repetir Iniciar | `IN_BATTLE`, `FINISHED` | — | sin cambios, misma sala (`replayed:true`) |

`PREPARING` y `START_PENDING` son estados **reservados** del vocabulario de HU-83: la implementación local no los persiste. Cada justa se serializa por sí misma durante la llamada a Combat y, si Combat falla (503) o la respuesta se pierde, la justa conserva su estado anterior. El reintento llega a la misma sala porque el `operationId` de Combat es determinista por justa y acción. `FINISHED` es terminal y lo fija únicamente la proyección de Combat (HU-83); HU-85 nunca escribe un resultado.

## HTTP de Tournament

Todas bajo el prefijo `/api/v1/tournaments`, con las guardas existentes (JWT, rol administrador; superadministrador según la política actual).

| Ruta | Cuerpo | Resultado |
| --- | --- | --- |
| `POST /admin/:tournamentId/matches/:matchId/prepare` | `{operationId}` exclusivamente | 200 `EncounterAdminReceipt` |
| `POST /admin/:tournamentId/matches/:matchId/start` | `{operationId}` exclusivamente | 200 `EncounterAdminReceipt` |
| `GET /admin/:tournamentId/actions` | — | 200 `{actions: EncounterAdminReceipt[]}`, orden cronológico |

`matchId` es el identificador estable completo de HU-83 (`${tournamentId}:E1`), no la etiqueta del grafo. El actor se toma del `sub` del JWT verificado; el cuerpo no puede traer actor, equipos, héroes, sala ni roles. Las consultas de lectura (`GET /:tournamentId/matches[/:matchId]`) no cambian.

`EncounterAdminReceipt`:

```json
{
  "actionId": "uuid",
  "tournamentId": "t-1",
  "encounterId": "t-1:E1",
  "action": "PREPARE",
  "actor": "account-admin-1",
  "operationId": "prep-e1-001",
  "occurredAt": "2026-10-06T15:00:00.000Z",
  "replayed": false,
  "battleId": "room-e1",
  "status": "READY",
  "preparationStatus": "PREPARED"
}
```

`action` es `PREPARE` o `START`. `occurredAt` es el instante en que el servidor aceptó la acción por primera vez; en una repetición se devuelve el recibo original con `replayed:true`, sin crear otro. Una justa nunca tiene más de un recibo por acción aceptada.

## Contrato con Combat (acordado con la implementación existente en Combat `develop`)

Solo el llamador interno `tournament`, firmado con HMAC (`x-internal-service`, `x-internal-timestamp`, `x-internal-signature`).

| Llamada | Cuerpo | Respuesta |
| --- | --- | --- |
| `POST /api/internal/v1/combat/tournament-rooms` | `{operationId, tournamentId, encounterId, teams:[{teamId, memberIds:[a,b]},{teamId, memberIds:[c,d]}]}` | 201 `BattleRoomDto`, sala `PREPARING` |
| `POST /api/internal/v1/combat/tournament-rooms/:roomId/start` | `{operationId, tournamentId, encounterId}` | 200, idempotente también tras `FINISHED` |
| `GET /api/internal/v1/combat/tournament-rooms/:roomId/record?afterSeq=N` | — | registro HU-83 (ya consumido) |

Tournament deriva el `operationId` de Combat de forma determinista por justa y acción (`tournament:${encounterId}:prepare` / `:start`), de modo que cualquier reintento, reinicio o administrador distinto llega a la misma sala y Combat no puede crear dos. Un cuerpo distinto con el mismo `operationId` da 409 en Combat; Tournament nunca lo reenvía distinto porque los equipos salen del snapshot inmutable del bracket.

Errores de Combat y su traducción:

| Combat | Tournament | Efecto |
| --- | --- | --- |
| 422 roster inválido o `blockers[]` | 422 `COMBAT_REJECTED_PARTICIPANTS` con `blockers[]` tal cual | no se vincula sala; la justa vuelve a su estado anterior |
| 404 / 409 de identidad | 409 `COMBAT_ROOM_CONFLICT` | sin cambios |
| 503 / tiempo agotado | 503 `SERVICE_UNAVAILABLE` | la justa conserva su estado anterior; el reintento llega a la misma sala |

## Reglas y errores

Errores `{code,message}` (más `blockers` solo en `COMBAT_REJECTED_PARTICIPANTS`):

| HTTP | `code` | Cuándo |
| --- | --- | --- |
| 401/403 | — | sin sesión o sin rol administrador; el rechazo ocurre antes de leer o tocar nada |
| 404 | `TOURNAMENT_NOT_FOUND` | torneo inexistente |
| 404 | `ENCOUNTER_NOT_FOUND` | justa que no pertenece al bracket de ese torneo |
| 409 | `BRACKET_NOT_PUBLISHED` | el torneo no tiene bracket |
| 409 | `PARTICIPANTS_UNRESOLVED` | la justa está en `WAITING_TEAMS`: faltan equipos; no se crea sala ni se inventan participantes o ganador |
| 409 | `ENCOUNTER_NOT_PREPARED` | Iniciar sin haber preparado |
| 409 | `ENCOUNTER_FINISHED` | Preparar una justa ya terminada que no tenía sala |
| 409 | `OPERATION_CONFLICT` | `operationId` ya usado con otra justa o acción |
| 409 | `COMBAT_ROOM_CONFLICT` | Combat devolvió una sala incompatible con la justa |
| 422 | `INVALID_OPERATION` | `operationId` ausente, vacío o de más de 100 caracteres |
| 422 | `COMBAT_REJECTED_PARTICIPANTS` | Combat rechazó el roster o hay un participante sin héroe equipado |
| 503 | `SERVICE_UNAVAILABLE` | Combat o sus dependencias no disponibles |

## Casos trazados a los criterios de aceptación

| Caso | Criterio | Resultado esperado |
| --- | --- | --- |
| C1 Preparar E1 con equipos resueltos | CA-01 | una sala vinculada; `READY/PREPARED`; recibo `PREPARE` con actor, justa y fecha |
| C2 Iniciar E1 preparada | CA-01 | misma sala; `IN_PROGRESS/IN_BATTLE`; recibo `START` |
| C3 Preparar e iniciar E1 y E2 a la vez | CA-02 | salas distintas, ambas `IN_BATTLE`; sin bloqueo global ni dependencia de transmisión |
| C4 Preparar E5 (semifinal sin participantes) | CA-03 | 409 `PARTICIPANTS_UNRESOLVED`; sin sala, sin participantes, sin ganador |
| C5 Cuenta no administradora | CA-03 | 403; ninguna llamada a Combat; sin recibo |
| C6 Combat rechaza un participante | CA-03 | 422 con `blockers[]`; sin sala vinculada |
| C7 Iniciar dos veces con el mismo `operationId` | CA-04 | misma sala, `replayed:true`, un solo combate en Combat |
| C8 Iniciar dos veces con `operationId` distinto | CA-04 | misma sala, un solo recibo `START` aceptado |
| C9 Iniciar a la vez dos solicitudes concurrentes | CA-04 | una sola sala iniciada; las dos respuestas nombran la misma |
| C10 Combat caído al preparar, luego recupera | CA-01/CA-04 | 503; el reintento llega a la misma sala, sin duplicados |
| C11 Mismo `operationId` en otra justa | CA-03 | 409 `OPERATION_CONFLICT` |
| C12 Iniciar sin preparar | CA-03 | 409 `ENCOUNTER_NOT_PREPARED` |
| C13 Paso del tiempo sin iniciar | CA-03 | sin derrota, ganador ni cierre automáticos; nada pasa a `FINISHED` por ausencia |

Ejemplos de solicitud y respuesta de error en [hu-85-tournament-encounter-administration-v1.json](hu-85-tournament-encounter-administration-v1.json).

## Configuración requerida

Tournament necesita `COMBAT_BASE_URL` (en compose: `http://combat:3006`) y el mismo `INTERNAL_SERVICE_AUTH_SECRET` que Combat. Sin ellos las acciones responden 503 `SERVICE_UNAVAILABLE` y no cambian nada. Combat ya admite al llamador `tournament` en sus rutas internas. Caddy enruta `/api/v1/tournaments*`, que incluye `/api/v1/tournaments/admin/...`.

## Persistencia propuesta

Migración `004-tournament-admin-actions`, solo de adición: tabla `tournament_encounter_actions` con `action_id`, `tournament_id`, `encounter_id`, `action` (`PREPARE|START`), `actor`, `operation_id`, `combat_room_id`, `occurred_at`; restricción única `(tournament_id, encounter_id, action)` para que no existan dos recibos aceptados de la misma acción, y única `(tournament_id, operation_id)` para la idempotencia. No se tocan `tournament_encounters`, `tournament_combat_events` ni las migraciones 001–003.

La exclusión es **por justa** (serialización por `torneo|justa` en el servicio y restricciones únicas en PostgreSQL para varias instancias), nunca por torneo: dos justas distintas se procesan en paralelo.

## Datos de prueba vs contrato de producción

El archivo JSON de ejemplos contiene exclusivamente datos de prueba (`t-1`, `account-admin-1`, `room-e1`). No son valores de producción ni identificadores reales. Los adaptadores de Combat en memoria y los datos locales de Web son dobles de prueba, deben identificarse como tales y no sustituyen la verificación contra Combat real (HU-85.4).

## Regla firme de la HU: sin derrotas automáticas

La HU #470 prohíbe asignar derrotas automáticas por ausencia sin una regla aprobada. Por eso Preparar, Iniciar y los rechazos **nunca** escriben resultado, ganador, cierre ni estado `FINISHED`: el único origen de un resultado es el registro autoritativo de Combat (HU-83). El paso del tiempo, una justa sin iniciar o una fecha vencida no cambian ninguna justa. Caso de prueba **C13** (CA-03): un año después de la fecha del torneo ninguna justa tiene resultado ni cierre, un rechazo no cambia nada y el administrador aún puede iniciar sin que eso concluya la justa.

## Decisiones pendientes — NO APROBADAS

Estas decisiones **no** se implementan como reglas; la propuesta solo indica el comportamiento seguro por omisión.

1. **Ausencias, calendario, reprogramación y cancelación.** No existe regla aprobada, así que HU-85 no implementa reprogramar ni cancelar justas ni reaccionar a una fecha vencida. Lo único firme viene de la HU y se cumple: **no se asignan derrotas ni ganadores automáticos por ausencia** (ver «Regla firme de la HU»).
2. **Tamaño de equipo.** El contrato de torneo usa equipos de dos; Combat hoy fija dos equipos × dos humanos. La discusión de «hasta 6 por batalla» no está aprobada y esta propuesta no la soporta.
3. **Registro de intentos rechazados.** La propuesta registra solo acciones aceptadas (CA-01 pide actor/justa/acción/fecha de lo ejecutado). Si el negocio quiere auditar intentos rechazados, es una decisión pendiente.
4. **Iniciar sin transmisión.** La propuesta no exige ni consulta la transmisión (CA-02). Si algún día se exige coordinación con ella, requiere contrato nuevo.

## Validación pendiente

Pruebas reales de los casos C1–C13 contra PostgreSQL y contra el servidor HTTP de Tournament; verificación contra Combat real documentando qué dependencias (Account, Inventory) son reales y cuáles dobles; revisión de este documento por los responsables de Tournament y Combat. Hasta entonces el contrato queda como propuesta.
