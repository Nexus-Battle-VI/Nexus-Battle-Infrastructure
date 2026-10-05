# HU-78 — Publicación de llaves, revisión 2

Versión común: `torneos-hu77-84-78-hu83-v2.0.0`.
Estado: contrato técnico para implementación local. La revisión de la tabla por los responsables y la aceptación funcional están pendientes; no se atribuye aprobación a los equipos.

Fuente vigente: [HU-78 #469](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/469). Extiende [registro y pago](hu-77-84-tournament-registration-v2.md) y conserva las consultas publicadas según [compatibilidad HU-83](hu-78-83-query-compatibility-v2.md). El contrato local anterior v1 no fue publicado y no es la base de migración de HU-83.

## Participantes y publicación

Exactamente ocho equipos **humanos** `CONFIRMED`, cupos persistidos 1–8 y dieciséis sujetos distintos. Cada equipo tiene dos cuentas elegibles diferentes. No se incluyen registros sin consentimiento, pagos pendientes, compensaciones o cancelaciones. No se agregan participantes IA ni se depende de JcE.

Las posiciones provienen del cupo persistido al confirmar la inscripción. No se ordenan por nombre, UUID, orden de consulta o propuestas del navegador. Publicar toma un snapshot de los ocho equipos y sus miembros, cierra la inscripción y materializa las catorce identidades de justa en una sola transacción. Si faltan equipos o falla alguna validación, no se guarda un bracket parcial ni se cierra anticipadamente el registro.

Existe un único bracket por torneo. Es inmutable: no se regenera, no se reemplazan equipos, no se cambian cupos y no se usan fechas distintas en un reintento. Solicitudes concurrentes y reintentos posteriores recuperan el mismo snapshot; un ID ya usado con otra intención da conflicto. El avance por resultados modifica una proyección posterior de HU-80, no este snapshot inicial.

Publicar no crea salas, no selecciona héroes, no inicia batallas ni decide ganadores. Las justas independientes pueden prepararse simultáneamente en HU-85. No hay bloqueo por transmisión ni por un único operador externo.

## Calendario

Mínimo global: `91 * 24 * 60 * 60 * 1000 = 7862400000` milisegundos entre los instantes UTC `startsAt` de **cualquier par** de torneos. Se compara la diferencia absoluta, tanto para inicios anteriores como posteriores. No se utiliza solo el último torneo ni el último terminado.

Se normalizan entradas ISO con zona horaria a instantes UTC; las fechas de apertura, pago, publicación o cierre no cambian el calendario. Se exige `opensAt < closesAt <= startsAt`. El intervalo de registro es `opensAt <= now < closesAt`, evaluado en el servidor, y publicar lo cierra inmediatamente.

A 90 días y a 91 días menos 1 ms se rechaza; a 91 días exactos se permite si cumple las demás reglas. Se protegen servidor y PostgreSQL contra solicitudes concurrentes, con exclusión persistente de los intervalos de inicio, no solo una comprobación previa en memoria. No se automatiza el calendario y no se libera un inicio por una cancelación supuesta; cambiarlo requiere una política posterior explícita.

## HTTP

| Ruta | Permiso y cuerpo | Resultado |
| --- | --- | --- |
| `POST /api/v1/tournaments/admin/:id/bracket` | Administrador autorizado; `{operationId}` exclusivamente | 200 `PublishedBracket` |
| `GET /api/v1/tournaments/:id/bracket` | JWT verificado | 200 `{bracket: PublishedBracket \| null}` |

Se utilizan las guardas actuales; superadministrador tiene acceso según la política de roles existente. No se confía en roles o sujetos del cuerpo. Las lecturas de inscripción/listado incluyen `startsAt`, `bracketPublished` y `open`; tras publicar `open:false` aunque el cierre programado sea posterior.

`PublishedBracket` contiene:

- `version:2`, `contractVersion`, `tournamentId`, `operationId`, `publishedAt`, `publishedBy`, `startsAt`.
- `seeds`: ocho `{position,teamId,name,avatar,memberIds}`, tomados de las inscripciones confirmadas; los miembros tienen longitud dos y el orden creador/compañero queda fijo.
- `matches`: catorce `{id,encounterId,track,round,sources,teamIds,status,destinations}`. `id` es la etiqueta local, `encounterId` es `${tournamentId}:${id}`, `track` es `MAIN|SECONDARY|FINAL`; `teamIds` son dos posiciones, cada una ID o `null`.

Cada origen es `{kind:'SEED',position}` o `{kind:'WINNER'|'LOSER',matchId}`. Cada destino es `{matchId,side}` o `null`, con `side` 0 o 1. Las referencias `matchId` dentro del **grafo** son etiquetas E1–Final; el `matchId` de las **consultas HU-83** es el identificador estable completo recibido del servidor. No se confunden ambos espacios de identidad.

El estado inicial del nodo es `TEAMS_RESOLVED` si ambos equipos están definidos, o `WAITING` si falta alguno. El cambio frente al v1 local es explícito: ese v1 llamaba `READY` a «equipos conocidos»; HU-83 reserva `READY` para equipos y héroes resueltos. La revisión 2 elimina esa ambigüedad. E1–E4 son `TEAMS_RESOLVED`; E5–Final son `WAITING`. No hay campos `heroId`, `battleId`, ganador o sala inventados en el snapshot.

Errores de negocio nuevos `{code,message}`: 403 sin permiso; 404 `TOURNAMENT_NOT_FOUND`; 409 `INSUFFICIENT_CONFIRMED_TEAMS`, `INVALID_BRACKET_ROSTER`, `OPERATION_CONFLICT` o `ENCOUNTER_IDENTITY_CONFLICT`; 422 `INVALID_OPERATION`. La validación de formato conserva el 400 de la frontera HTTP. `CALENDAR_CONFLICT` es 409 al crear el torneo mediante `/admin`, no al leer el bracket.

## Tabla transcrita, pendiente de revisión entre responsables

Referencia: figura 2, §7.9, página impresa 67 de `proyecto_integrador_2.pdf`, según la transcripción del contrato local de referencia. **No se volvió a cotejar el PDF en este encargo ni existe aprobación nueva de consumidores.** Esta tabla es la propuesta común para revisar; no se habilita implementar el avance HU-80 como si estuviera aprobado.

| Justa | Árbol | Ronda | Lado 0 | Lado 1 | Ganador → | Perdedor → |
| --- | --- | --- | --- | --- | --- | --- |
| E1 | MAIN | 1 | Cupo 1 | Cupo 2 | E5, lado 0 | E7, lado 0 |
| E2 | MAIN | 1 | Cupo 3 | Cupo 4 | E5, lado 1 | E7, lado 1 |
| E3 | MAIN | 1 | Cupo 5 | Cupo 6 | E6, lado 0 | E8, lado 0 |
| E4 | MAIN | 1 | Cupo 7 | Cupo 8 | E6, lado 1 | E8, lado 1 |
| E5 | MAIN | 2 | Ganador E1 | Ganador E2 | E11, lado 0 | E10, lado 0 |
| E6 | MAIN | 2 | Ganador E3 | Ganador E4 | E11, lado 1 | E9, lado 0 |
| E7 | SECONDARY | 2 | Perdedor E1 | Perdedor E2 | E9, lado 1 | Sin destino |
| E8 | SECONDARY | 2 | Perdedor E3 | Perdedor E4 | E10, lado 1 | Sin destino |
| E9 | SECONDARY | 3 | Perdedor E6 | Ganador E7 | E12, lado 0 | Sin destino |
| E10 | SECONDARY | 3 | Perdedor E5 | Ganador E8 | E12, lado 1 | Sin destino |
| E11 | MAIN | 3 | Ganador E5 | Ganador E6 | Final, lado 0 | E13, lado 0 |
| E12 | SECONDARY | 4 | Ganador E9 | Ganador E10 | E13, lado 1 | Sin destino |
| E13 | SECONDARY | 5 | Perdedor E11 | Ganador E12 | Final, lado 1 | Sin destino |
| Final | FINAL | 6 | Ganador E11 | Ganador E13 | Campeón, sin otra justa | Sin destino |

Una sola final, **sin reset**. E9 recibe al perdedor E6 y E10 al perdedor E5: los cruces no se intercambian silenciosamente. La tabla legible y el grafo del archivo `hu-77-84-78-integration-v2.json` deben coincidir; los destinos son la relación inversa de los orígenes. Las rondas representan capas de dependencia de esta propuesta, no fechas ni obligación de ejecutar una sola justa por vez.

## Persistencia y aceptación

Se conserva `001-tournament-encounters`. Registro se añade después como `002-tournament-registration`; bracket como `003-tournament-bracket`. La publicación usa las tablas de HU-83 para las justas, con `teams:[]`, `WAITING_PARTICIPANTS`, sin sala/timestamps/resultados y cursor inicial 0. Los equipos registrados se consultan desde el snapshot. No se recrean tablas de archivo ni se copia la antigua `003-encounters`.

Validación pendiente: ocho humanos; rechazo con cinco/siete o pagos pendientes; catorce identidades estables; grafo y cruces completos; permiso; frontera de 90/91 días, ambos sentidos y concurrencia en PostgreSQL; publicación atómica ante reintento/reinicio; consultas HU-83 compatibles; conservación de justas/eventos anteriores a la migración. Las pruebas históricas no verifican esta combinación. Publicar un bracket local de prueba no equivale a aprobar la tabla ni aceptar la historia.
