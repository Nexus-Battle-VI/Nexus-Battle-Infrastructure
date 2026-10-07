# Torneos — contrato común torneos-v3.0.0

Revisión documental 2, 7 de octubre de 2026. Estado: **especificación técnica disponible para B/C/D; implementación y aceptación integrada pendientes**. Refs Nexus-Battle-VI/Nexus-Battle-Management#470, #467, #468, #469 y #465.

La ampliación conserva los consumidores y torneos `torneos-hu77-84-78-hu83-v2.0.0`. La versión del contrato viaja en los datos: **las rutas continúan bajo `/api/v1`**. No se crea un prefijo HTTP `/api/v3`. Los esquemas normativos y los ejemplos de prueba están en [schema](torneos-v3.0.0.schema.json) y [fixtures](torneos-v3.0.0.fixtures.json).

Las reglas provienen del encargo del usuario y de la [precisión vigente de HU-85](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/470#issuecomment-6039231084), reconsultada mediante GitHub API. Los nombres, formas y reserva DDL son decisiones técnicas de coordinación; no representan aprobación técnica ni aceptación funcional del PO.

## Modalidad, registro y compatibilidad

| tournamentMode | teamSize derivado | cupos | personas al completar | personas por justa |
| --- | ---: | ---: | ---: | ---: |
| SOLO | 1 | 8 | 8 | 2 |
| DUO | 2 | 8 | 16 | 4 |
| TRIO | 3 | 8 | 24 | 6 |

Crear fija modalidad, tamaño y hora. El cliente envía `tournamentMode`; el servidor deriva `teamSize`. Se conservan `entryPolicy`, creador pagador, intervalos de registro, distancia de 91 días y política de premios de [registro v2](hu-77-84-tournament-registration-v2.md). La modalidad no multiplica precios ni modifica repartos.

Crear v3: `POST /api/v1/tournaments/admin`:
```json
{"operationId":"create-demo","name":"Torneo de prueba","tournamentMode":"TRIO","entryPolicy":{"version":1,"free":true,"methods":[]},"opensAt":"2026-10-07T12:00:00Z","closesAt":"2026-10-07T23:55:00Z","startsAt":"2026-10-08T00:00:00Z"}
```
La respuesta es `PublicTournament` v2 más `contractVersion:"torneos-v3.0.0"`, `tournamentMode`, `teamSize` y `roundSchedule` (seis entradas). Crear con la forma histórica, sin modalidad, mantiene un torneo DUO **v2 y sin ausencias**. Un DUO nuevo con modalidad explícita usa v3.

Registrar: `POST /api/v1/tournaments/:id/teams`:
```json
{"operationId":"register-demo","name":"Equipo demo","avatar":{"kind":"ACCOUNT_AVATAR","subject":"p1"},"invitedMemberIds":["p2","p3"]}
```
El JWT aporta el creador; no se acepta `ownerId` del cuerpo. `invitedMemberIds` excluye al creador y contiene exactamente 0/1/2 identidades según SOLO/DUO/TRIO. Sin duplicados dentro o entre equipos activos; avatar de uno de sus integrantes y política de nombre/identidad de Account conservadas. Para DUO se admite la forma histórica `companionId`, exclusivamente cuando no se envía `invitedMemberIds`. SOLO/TRIO usan la forma nueva. No se aceptan ambas formas a la vez.

Cada mutación devuelve `TeamRegistration` v2 más:
```ts
type Member = {
  subject: string; position: 0 | 1 | 2;
  consentAt: string | null; consentVersion: string | null;
};
type MembersExtension = { members: Member[]; companionId: string | null };
```
`position:0` es el creador. `ownerId` se conserva; `companionId` es el segundo integrante o null. En TRIO no describe por sí solo el roster: `members` ordenados son autoritativos. Los recibos mantienen IDs y semántica; `registrationReceipt.memberIds` contiene el roster exacto.

El creador consiente al registrar, con `team-registration-v3`. Cada invitado utiliza su JWT en `POST /:id/teams/:teamId/consent {operationId,accept}`. Solo su consentimiento se modifica. Aceptar el último integrante deja `PENDING_PAYMENT`; SOLO llega ahí al registrarse. Rechazar/cancelar sigue la política pre-pago vigente. Cobrar/confirmar requiere todos los consentimientos, elegibilidad y cupo. Un integrante no consiente por otro.

`GET /:id/registration` conserva `capacity.confirmed/reserved/available` como **equipos** y añade `teamSize`, `confirmedPeople=confirmed*teamSize`, `totalPeople=8*teamSize`. `reserved` cuenta pagos pendientes/compensación, no personas confirmadas. Las respuestas de registro solo incluyen equipos del actor.

## Bracket y calendario persistidos

Publicar requiere ocho equipos CONFIRMED, cupos 1–8, recibos válidos, todos los consentimientos y exactamente 8×teamSize sujetos únicos. TRIO con 23 personas, tamaño incorrecto o un duplicado rechaza con 409 `INVALID_BRACKET_ROSTER` o `INSUFFICIENT_CONFIRMED_TEAMS`; no publica parcialmente.

Rutas existentes: `POST /admin/:id/bracket {operationId}` y `GET /:id/bracket`. El snapshot v3 conserva los campos de [bracket v2](hu-78-tournament-bracket-v2.md), fija `version:3`, `contractVersion`, `tournamentMode`, `teamSize` y `roundSchedule`. `seeds.memberIds` contiene 1/2/3 sujetos ordenados. La proyección HU-80 se actualiza aparte: el snapshot sigue inmutable.

La etiqueta del grafo (`E1`, ..., `Final`) no es el ID HTTP. El servidor devuelve `encounterId` **opaco** y estable. Web/B/C lo conservan y codifican con encodeURIComponent para la ruta; no lo reconstruyen concatenando ni extraen la etiqueta mediante split. Las identidades antiguas `torneo:E1` permanecen intactas.

```ts
type RoundSchedule = {
  round: 1 | 2 | 3 | 4 | 5 | 6;
  acceptanceOpensAt: string; acceptanceClosesAt: string; scheduledStartAt: string;
};
```
Hora inicial `startsAt` = apertura de primera aceptación. Para ronda r:
`opens=startsAt+(r-1)*600000`, `closes=opens+120000`, `scheduledStartAt=closes`.
Los seis valores se calculan en UTC y se guardan al crear; el cliente no los suministra. Cada justa usa la ronda del grafo. `startedAt` sigue siendo el instante real informado por Combat, no el previsto.

Ejemplo: el 7 de octubre a las 19:00 en America/Bogota equivale al **8 de octubre a las 00:00 UTC**:

| ronda | justas | abre UTC | cierra / inicio previsto UTC |
| --- | --- | --- | --- |
| 1 | E1, E2, E3, E4 | 2026-10-08T00:00:00.000Z | 2026-10-08T00:02:00.000Z |
| 2 | E5, E6, E7, E8 | 2026-10-08T00:10:00.000Z | 2026-10-08T00:12:00.000Z |
| 3 | E9, E10, E11 | 2026-10-08T00:20:00.000Z | 2026-10-08T00:22:00.000Z |
| 4 | E12 | 2026-10-08T00:30:00.000Z | 2026-10-08T00:32:00.000Z |
| 5 | E13 | 2026-10-08T00:40:00.000Z | 2026-10-08T00:42:00.000Z |
| 6 | Final | 2026-10-08T00:50:00.000Z | 2026-10-08T00:52:00.000Z |

Combat mantiene 360000 ms máximos. Aceptar todos temprano no adelanta la batalla. No se cambian fechas ni se abren ventanas tardías automáticamente.

## Aceptación, estados y bloqueos

Nueva mutación: `POST /api/v1/tournaments/:id/matches/:encounterId/acceptance`, JWT de jugador, cuerpo **exclusivo** `{operationId}`. La acción es aceptar; no hay retirada ni alternador booleano en este incremento. El actor pertenece al roster proyectado y fijado de esa justa. Cuerpo con sujeto, equipo, fecha, conteo, ganador o campo extra produce 400.

```ts
type AcceptanceReceipt = {
  receiptId: string; tournamentId: string; encounterId: string;
  operationId: string; subject: string; teamId: string;
  acceptedAt: string; acceptanceOpensAt: string; acceptanceClosesAt: string;
  replayed: boolean;
};
```
Fecha y deadline del servidor; nunca reloj del navegador. La primera escritura exige `opens <= now < closes`. Se autoriza al actor **antes** de revelar un replay. El recibo es único por justa/sujeto; reintentos no cuentan dos veces. Un recibo ya aceptado puede recuperarse después del cierre sin reabrir la ventana; una primera aceptación al deadline o después da 409 `ACCEPTANCE_CLOSED`. Antes de abrir: 409 `ACCEPTANCE_NOT_OPEN`. Otra intención con el mismo ID: 409 `OPERATION_CONFLICT`.

Consultas únicas conservadas: `GET /:id/matches` y `GET /:id/matches/:encounterId?afterSeq=N`. Una justa v3 añade:
```ts
type ConvocationExtension = {
  contractVersion: "torneos-v3.0.0"; tournamentMode: "SOLO" | "DUO" | "TRIO"; teamSize: 1 | 2 | 3;
  acceptanceOpensAt: string; acceptanceClosesAt: string; scheduledStartAt: string;
  acceptanceStatus: "SCHEDULED" | "OPEN" | "CLOSED" | "BLOCKED_DELAY" | "RESOLVED";
  operationalStatus: "IDLE" | "RESOLUTION_PENDING" | "PREPARE_PENDING" | "START_PENDING" | "IN_BATTLE" | "FINISHED" | "DEPENDENCY_ERROR";
  acceptedCounts: [number, number];
  myAcceptance: AcceptanceReceipt | null;
  blockReason: {code: string; message: string; since: string} | null;
  resolution: TournamentResolution | null;
};
```
Conteos siguen los lados 0/1 del roster. Solo el propio recibo viaja a una sesión; no se publican fechas/recibos de aceptación individual de terceros. Los campos originales `status`, `preparationStatus`, `startedAt` y `result` se conservan con su autoridad; no se reutilizan como estados de convocatoria ni se altera el estado de una sala de Combat.

Al abrir, si faltan resultados previos o roster autoritativo, queda `BLOCKED_DELAY` y `blockReason.code=PREVIOUS_RESULT_PENDING`. No acepta, sortea, adjudica ausencia ni solicita una sala. Una dependencia resuelta tarde no genera una nueva ventana. Los fallos operativos comprobados que impiden evaluar la convocatoria quedan visibles como dependencia/incidencia, sin inferir ausencia. Recuperar una incidencia que agotó el horario sigue pendiente de política de producto.

Un worker propio de Tournament procesa aperturas/cierres e intenciones pendientes **sin navegador**. Guarda deadline, roster, aceptaciones, resolución y operaciones antes de efectos externos. Retoma después de reinicio. La exclusión es por justa; no mantiene un lock global de torneo ni un lock SQL durante red. Dos workers o administrador y scheduler usan las mismas restricciones durables e intenciones.

## Resolución tipada, avance y estadísticas

```ts
type HU83Result = {winnerTeamLabel: string | null; reason: string; outcome: "WIN" | "NO_WINNER"; finishedAt: string};
type PlayedResolution = {
  resultType: "PLAYED"; resolutionId: string; resolvedAt: string;
  teamIds: [string,string]; winnerTeamId: string | null; loserTeamId: string | null;
  combatRoomId: string; combatResult: HU83Result;
};
type AbsenceResolution = {
  resultType: "ABSENCE"; resolutionId: string; resolvedAt: string;
  teamIds: [string,string]; winnerTeamId: string; loserTeamId: string;
  acceptedCounts: [number,number]; teamSize: 1 | 2 | 3;
  ruleApplied: "ONE_COMPLETE" | "HIGHER_ACCEPTANCE_COUNT" | "TIED_ACCEPTANCE_COUNT";
  reason: "ACCEPTANCE_WINDOW_CLOSED";
  tieBreak: {kind:"UNBIASED_50_50"; drawId:string; selectedSide:0|1} | null;
};
type TournamentResolution = PlayedResolution | AbsenceResolution;
```
`combatResult` es la proyección real HU-83, nunca otra simulación. PLAYED con NO_WINNER conserva winner/loser null y bloquea avance con `RESOLUTION_REQUIRED`; no se usa sorteo de ausencias después de jugar.

Al cerrar, ambos completos pasan a preparación/inicio de Combat; uno completo gana por ONE_COMPLETE; ambos incompletos con distinto conteo, por HIGHER_ACCEPTANCE_COUNT; igualdad, incluso 0–0, por TIED_ACCEPTANCE_COUNT con 50/50. El sorteo utiliza aleatoriedad del servidor y conserva `drawId`, lado elegido y `resolutionId` durables; repetir/reiniciar conserva la resolución. No se vuelven a sortear resultados persistidos.

ABSENCE no contiene combatRoomId ni BattleResult. En la consulta HU-83, `combatRoomId:null`, `startedAt:null`, `result:null`, sin héroes fabricados ni eventos de motor; el desenlace está en `resolution`. `closedAt` es resolvedAt y el cierre del dominio de Tournament puede ser FINISHED sin afirmar una sala FINISHED. El cliente identifica ausencia por resultType, no por un texto de BattleResult.

HU-80 consume ambas variantes una vez por resolutionId; deriva winner/loser y proyecta las aristas del grafo. Un resultado contradictorio se rechaza, no se corrige en silencio. Las estadísticas de torneo contabilizan victoria/derrota y motivo también por ausencia; las estadísticas de motor (daño, turnos, etc.) solo usan PLAYED. La declaración de campeón conserva la fuente de la Final y puede no tener finalRoomId ni héroes conocidos.

## Combat: forma exacta y traducción requerida

`POST /api/internal/v1/combat/tournament-rooms`, caller HMAC exclusivo **tournament**:
```json
{"operationId":"tournament:opaque-e1:prepare","tournamentId":"T1","encounterId":"opaque-e1","mode":"TRIO","teamSize":3,"teams":[{"teamId":"a","memberIds":["p1","p2","p3"]},{"teamId":"b","memberIds":["p4","p5","p6"]}]}
```
**Tournament traduce tournamentMode → mode** en su adaptador HTTP; no envía tournamentMode en ese wire. Combat valida mode/teamSize concordantes, exactamente dos lados completos del tamaño derivado, teamIds distintos y humanos únicos antes de llamadas innecesarias a Account/Inventory. No admite héroes, ganador, IA ni roomId del cliente. El roster persistido ordenado y el cuerpo firmado son idénticos en todo retry.

La respuesta existente es **BattleRoomDto** con `id`, `mode` del motor PVP, `status`, `teams[{label,capacity,participants}]`, `createdBy`, etc. No se sustituye por un sobre inventado con roomId/operationId en la raíz. `mode:PVP` del DTO y `mode:TRIO` de esta petición son conceptos diferentes. Tournament valida dos lados y roster; vincula data.id.

Inicio conserva `POST /.../:roomId/start {operationId,tournamentId,encounterId}`; registro conserva `GET /.../:roomId/record?afterSeq=N`, páginas/eventos HU-83 existentes. Operaciones internas deterministas: `tournament:${encounterId}:prepare` y `:start`. Un 503/timeout mantiene estado operativo pendiente, y se repite la misma sala/intención. No convierte fallos de Combat o elegibilidad en derrota.

Compatibilidad: peticiones históricas sin mode/teamSize siguen exigiendo DUO, se reenvían **byte/semántica de cuerpo sin adiciones**, conservando su requestHash. Los documentos/salas existentes no se transforman. La huella de una petición nueva incluye modalidad/tamaño/roster; cambiar cualquier parte con el mismo ID es 409.

**Entrega C observada:** 7df51d8 admite mode y capacidad 1/2/3 en parser/caso/agregado, pero todavía no valida teamSize; parte de d0a9cc4, seis commits detrás de develop dd67d47. La certificación v3 requiere la adaptación y pruebas sobre la base vigente. No se considera esta entrega integrada.

## Administrador, worker, HMAC y errores

Se conservan roles/guardas JWT publicados. Preparar/iniciar v2 mantienen su contrato; las justas v3 aplican la misma puerta durable del calendario/aceptación al administrador y al worker. Ninguno puede adelantar batalla ni evadir una ausencia/bloqueo confirmado. Las acciones administrativas llevan el sujeto JWT; el worker registra actorType WORKER y su identidad de servicio, sin suplantar una cuenta.

Sobre la red hacia Combat se usa siempre caller `tournament`; **no se concede caller worker**. Cabeceras: x-internal-service, x-internal-timestamp, x-internal-signature. HMAC-SHA256 sobre caller, método mayúscula, path sin query, timestamp y SHA256 del JSON canónico, separados por saltos de línea. Se conservan orden de claves, orden de arrays, ventana de reloj de 30 segundos y secreto configurado fuera del repositorio. El aviso de Combat es autenticado según su ruta existente y no admite resultados autoritativos del navegador.

Errores públicos con `{code,message}` seguro: 400 forma/campos extra; 401 sesión ausente; 403 rol/pertenencia (antes de efectos o revelar replay); 404 torneo/justa; 409 estado/operation conflict/deadline/dependencia de grafo; 422 modalidad/roster/elegibilidad comprobada; 503 dependencia operativa. Se conservan los códigos HU-85 existentes para Combat y sus blockers sanitizados. El detalle durable muestra blockReason/operationalStatus aunque una operación responda error.

## Premios: dependencia real y contrato de ampliación separado

Se conserva la política HU-86. En los consumidores **preparados** de Wallet e Inventory, el comando tiene exactamente diez campos y exige finalRoomId y heroId strings. Ese wire no representa una Final por ausencia. En develop reconsultado, Wallet 47f9799 e Inventory 7c76dda no contienen esas rutas de premios preparadas. No se afirman publicadas ni se envían IDs ficticios.

Tournament conserva campeón, estadísticas y derechos aplicables con estado PENDING y código **PRIZE_RESOLUTION_CONTRACT_REQUIRED** si la fuente es ABSENCE o falta un consumidor certificado. Web muestra premio pendiente y motivo; no «entregado».

La futura ampliación a consumidores necesita una versión de ruta/wire separada, conserva operationId/política/importes y sustituye la referencia obligatoria de sala por:
```ts
type PrizeSource =
  | {resultType:"PLAYED"; finalEncounterId:string; resolutionId:string; finalRoomId:string}
  | {resultType:"ABSENCE"; finalEncounterId:string; resolutionId:string};
```
Wallet/Inventory validan/idempotentizan esa fuente. Si un derecho requiere héroe propio y no hay uno validado, queda pendiente, sin inventarlo. **Esta forma es propuesta para sus dueños; no se despacha sobre las rutas v1 estrictas.** A documenta dependencia; B/C/D no escriben esos repositorios.

## Grafo G1 completo (una Final)

| justa | ronda/árbol | lado 0 | lado 1 | ganador → | perdedor → |
| --- | --- | --- | --- | --- | --- |
| E1 | 1 MAIN | cupo 1 | cupo 2 | E5/0 | E7/0 |
| E2 | 1 MAIN | cupo 3 | cupo 4 | E5/1 | E7/1 |
| E3 | 1 MAIN | cupo 5 | cupo 6 | E6/0 | E8/0 |
| E4 | 1 MAIN | cupo 7 | cupo 8 | E6/1 | E8/1 |
| E5 | 2 MAIN | ganador E1 | ganador E2 | E11/0 | E10/0 |
| E6 | 2 MAIN | ganador E3 | ganador E4 | E11/1 | E9/0 |
| E7 | 2 SECONDARY | perdedor E1 | perdedor E2 | E9/1 | — |
| E8 | 2 SECONDARY | perdedor E3 | perdedor E4 | E10/1 | — |
| E9 | 3 SECONDARY | perdedor E6 | ganador E7 | E12/0 | — |
| E10 | 3 SECONDARY | perdedor E5 | ganador E8 | E12/1 | — |
| E11 | 3 MAIN | ganador E5 | ganador E6 | Final/0 | E13/0 |
| E12 | 4 SECONDARY | ganador E9 | ganador E10 | E13/1 | — |
| E13 | 5 SECONDARY | perdedor E11 | ganador E12 | Final/1 | — |
| Final | 6 FINAL | ganador E11 | ganador E13 | campeón | — |

Conectores Web usan sources/destinations del servidor; no duplican cruces. La identidad HTTP de cada justa procede de encounterId. Los datos demo se rotulan como tales y nunca cuentan como QA real.

## Versionado y verificación

Esta revisión sustituye el borrador local genérico v3 (prefijo /v3, memberIds/consents y nombres no fijados). Aquel borrador no estuvo certificado como cliente ni se publicó. La forma disponible se fija como torneos-v3.0.0 y revisión documental 2. Cambios futuros de wire/transiciones requieren nueva versión y actualización de consumidores por su dueño.

El [registro de ejecución](../evidence/torneos-v3-20261007/registro.md) reserva DDL, identifica bases/entregas y hallazgos. La [matriz](../evidence/torneos-v3-20261007/matriz.json) distingue evidencia documental, pruebas del dueño y recorrido integrado. Ni validar el schema ni aprobar types demuestra usuarios reales, premios o aceptación funcional.
