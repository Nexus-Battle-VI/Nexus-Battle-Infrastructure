# HU-78/HU-83 — Compatibilidad de consulta, revisión 2

Versión común: `torneos-hu77-84-78-hu83-v2.0.0`.
Estado: especificación para implementación local; revisión de consumidores y aceptación funcional pendientes.

La base verificada es [Tournament PR #5](https://github.com/Nexus-Battle-VI/Nexus-Battle-Tournament/pull/5), integrado en `develop` como `21951787de52c47ba29891ada412ff187162f0b5`. Las [HU-78](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/469) y [HU-83](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/465) permanecen abiertas. Los fixtures del PR son evidencia de desarrollo, no un bracket ni un combate reales.

## Contrato publicado que se conserva

Un solo controlador posee las dos rutas GET. Se extiende `TournamentMatchesController`; la copia local de `encounters.controller.ts` no puede registrar otros GET para estas rutas.

| Ruta con JWT | Respuesta conservada |
| --- | --- |
| `GET /api/v1/tournaments/:tournamentId/matches` | Array `MatchSummaryResponse[]`; nunca `{matches: [...]}` |
| `GET /api/v1/tournaments/:tournamentId/matches/:matchId?afterSeq=0` | Objeto `MatchDetailResponse`; `teams`, nunca reemplazado por `roster` |

Campos existentes de cada resumen: `tournamentId`, `matchId`, `round`, `bracketLabel`, `status`, `startedAt`, `closedAt`.

El detalle añade los campos existentes `teams`, `result`, `events`, `afterSeq`, `nextSeq`, `hasMore`, `logComplete`. Cada equipo resuelto conserva `{teamId, teamLabel, participants:[{playerId, heroId}]}`; cada evento conserva `{seq,type,occurredAt,payload}`. El resultado conserva `{winnerTeamLabel,reason,outcome,finishedAt}` o `null`.

Se mantienen JWT, los errores Nest de 400/401/404 y la lectura del detalle con `afterSeq` entero no negativo, por defecto 0. Una referencia de otra justa o torneo devuelve 404. El listado de un torneo sin justas conocidas devuelve `[]`, como la base publicada. No se cambia ese comportamiento a 404 en este incremento.

## Identidad y extensión aditiva

Para justas nuevas, `bracketLabel` es `E1`–`E13` o `Final`; `encounterId` es `${tournamentId}:${bracketLabel}`. El `matchId` público conserva la semántica del PR: contiene el identificador estable de la justa, no solo su etiqueta. Web obtiene `matchId` del servidor y lo codifica al construir la URL; no lo reconstruye. Se conservan sin renombrar los identificadores de registros históricos.

Se pueden agregar a los resúmenes y detalles:

- `encounterId`: mismo valor que `matchId`.
- `bracketTrack`: `MAIN`, `SECONDARY` o `FINAL`.
- `registeredTeams`: dos posiciones; cada una es `null` o `{teamId,name,avatar,memberIds}` proveniente de las inscripciones y del snapshot del bracket. Los identificadores de miembros son sujetos de Account, no IDs internos de sus filas.
- `preparationStatus`: `WAITING_TEAMS`, `TEAMS_RESOLVED`, `PREPARING`, `PREPARED`, `START_PENDING`, `IN_BATTLE` o `FINISHED`.
- `combatRoomId`: ID recibido de Combat o `null`.
- `lastSyncedSeq`, `engineLastSeq`, `syncedAt`: respectivamente el cursor persistido, el cursor conocido del motor o `null`, y el instante de sincronización o `null`.

Estos campos son obligatorios para las justas nuevas del bracket real y pueden estar ausentes en registros anteriores. Los consumidores previos pueden seguir leyendo los campos publicados. No se cambian las formas ni los significados de los campos existentes. Esta extensión no sustituye el controlador ni la entidad de HU-83 por el modelo JSON local anterior.

## Estados sin inventar héroes o salas

| Evidencia disponible | `status` de HU-83 | `preparationStatus` | `teams` | Sala, tiempos y resultado |
| --- | --- | --- | --- | --- |
| Falta uno o ambos equipos | `WAITING_PARTICIPANTS` | `WAITING_TEAMS` | `[]` | `null` |
| Ambos equipos y cuatro miembros conocidos; héroes sin resolver | `WAITING_PARTICIPANTS` | `TEAMS_RESOLVED` | `[]` | `null` |
| Preparación solicitada, respuesta todavía incierta | `WAITING_PARTICIPANTS` mientras falten héroes | `PREPARING` | Sin héroes supuestos | Solo datos ya confirmados |
| Equipos y héroes autoritativos resueltos; aún no inició | `READY` | `PREPARED` o `START_PENDING` | Roster real | Inicio/cierre/resultado `null` hasta evidencia |
| Combat informa `IN_BATTLE` | `IN_PROGRESS` | `IN_BATTLE` | Roster real | Inicio autoritativo; cierre/resultado `null` |
| Combat informa `FINISHED` con resultado autoritativo | `FINISHED` | `FINISHED` | Roster real | Cierre y resultado del motor |

HU-78 publica inicialmente E1–E4 con equipos resueltos, pero no con héroes. En HU-83 siguen `WAITING_PARTICIPANTS`, con `TEAMS_RESOLVED` y los equipos en `registeredTeams`. Web muestra «Equipos definidos; preparación pendiente». E5–Final esperan resultados y muestran `WAITING_TEAMS`. No se introduce otro valor en el enum público de `status`.

`READY` conserva su significado publicado: equipos **y héroes** resueltos. No acredita por sí solo que todas las validaciones de inicio de Combat hayan pasado. `IN_BATTLE` es vocabulario interno de Combat y se traduce a `IN_PROGRESS` en HU-83. `PREPARING`, `START_PENDING` y `PREPARED` no reemplazan el enum publicado.

El registro de HU-77 no fija héroes. La preparación pertenece a HU-85; los héroes llegan de Combat, que ya consulta el héroe equipado de cada jugador. La consulta no crea salas, inicia batallas, decide ganadores ni modifica el bracket. La materialización/proyección idempotente del archivo no puede tener esos efectos de negocio.

## Adaptación del Combat publicado

Referencia verificada: Combat `develop` en `d0a9cc49be3f2914a569f2cf7f2197af5154cf1e`. Las rutas existen; las notas antiguas «todavía no existe #517» no describen este corte. Este contrato no altera Combat.

| Llamada HMAC de Tournament | Cuerpo o respuesta real |
| --- | --- |
| `POST /api/internal/v1/combat/tournament-rooms` | `{operationId,tournamentId,encounterId,teams:[{teamId,memberIds}, {teamId,memberIds}]}`; devuelve 201 `BattleRoomDto` con `id`, `teams[].label`, `status`, `battle` y `result` |
| `POST /api/internal/v1/combat/tournament-rooms/:roomId/start` | `{operationId,tournamentId,encounterId}`; devuelve 200 `BattleRoomDto` |
| `GET /api/internal/v1/combat/tournament-rooms/:roomId/record?afterSeq=N` | `{roomId,tournamentId,encounterId,status,startedAt,result,teams,events:{afterSeq,lastSeq,items}}` |

No se envían héroes ni participantes AI desde Web. Crear la sala exige dos equipos humanos de dos miembros; Combat resuelve Account/Inventory y rechaza jugadores sin héroe equipado. La recuperación usa la misma intención duradera y `operationId`; una respuesta incierta no autoriza crear otra sala.

El formato real difiere del doble local anterior:

- `id` de la respuesta de creación se traduce a `combatRoomId`; no se espera un objeto plano con `roomId` en esa respuesta.
- `events.items` y `events.lastSeq` se traducen al puerto local; no se espera un arreglo `events` en la raíz.
- Los eventos de Combat son `BattleEventWire`, con sus campos de acción en la raíz. Se conserva el objeto original como `payload` de HU-83, junto con `seq/type/occurredAt`; no se fabrica un payload diferente para el motor.
- El DTO de lectura real expone `teams[].teamId` como etiqueta del motor. El adaptador liga esa etiqueta al equipo de inscripción por la sala guardada y por igualdad exacta de los dos miembros. Se comprueban unicidad y cardinalidad; nunca se asigna un equipo por una suposición sobre el orden de respuesta. `winnerTeamLabel` se conserva tal como lo emitió Combat.
- Se validan sala, torneo, justa, miembros, héroes, secuencias y resultado antes de persistir. Un resultado `NO_WINNER` sigue siendo un resultado final; no autoriza inventar un ganador ni avance.

`DevFixtureTournamentEncounterSource` se sustituye por una fuente del bracket persistido para el flujo real. `DevFixtureCombatRecordAdapter` queda limitado a pruebas/desarrollo explícito. El reemplazo no debe eliminar los tests publicados de HU-83. La captura de fuentes y commits consta en el acuerdo común.

## Paginación y conservación

Hasta 100 eventos por página; secuencias crecientes, exclusivas respecto de `afterSeq`. `nextSeq` es la última secuencia devuelta o `afterSeq` si la página está vacía. `hasMore` indica más eventos **ya archivados** después de esa página. `logComplete` indica que la proyección alcanzó el último cursor conocido de Combat; no significa que un combate activo no pueda producir más eventos. `hasMore` puede ser `true` con `logComplete:true`.

El proceso de sincronización toma páginas de Combat hasta alcanzar el cursor conocido y persiste progreso. No depende de consultas del navegador, YouTube u OBS. Ante caída de Combat, se conserva el archivo disponible, los estados comprobados y su última sincronización. No se marca `logComplete:true` sin lectura suficiente del motor. Los saltos o reescrituras no se silencian como éxito.

La clave publicada `(tournament_id,encounter_id)` y la unicidad `(tournament_id,encounter_id,seq)` permanecen. No se recrean `tournament_encounters` ni `tournament_combat_events`. La migración `001-tournament-encounters` conserva nombre y contenido. El plan de evolución está en [integración v2](hu-77-84-78-integration-plan-v2.md).

## Verificación requerida, aún no ejecutada sobre el incremento

Contrato HTTP anterior y extensión; 14 justas recién publicadas sin héroes/salas ficticios; fuente del bracket real; detalle con más de 100 eventos; referencias ajenas; traducción `IN_BATTLE`→`IN_PROGRESS`; terminalidad y deduplicación; tres justas simultáneas; archivo con emisión caída; conservación de datos al migrar desde el esquema publicado. Una suite con fixtures no acepta HU-83 ni demuestra el recorrido real.
