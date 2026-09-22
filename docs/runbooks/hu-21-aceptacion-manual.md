# Aceptación manual de HU-21 con dos sesiones reales

Complementa la validación automatizada de **protocolo** de la Task #420:

- Combat, `test/db/battle-finish.e2e.spec.ts`: MongoDB real (Testcontainers), servidor Nest real y
  **dos clientes `ws` reales**, con el reloj controlado (`MutableClock`), el planificador movido a
  mano (`tick()`) y la secuencia aleatoria (HU-24) guionizada para que cada frontera de tiempo sea
  reproducible (S-01 a S-26 del contrato).
- La interfaz de resultado de Web (#419) y su fixture con **bytes reales** de esa suite.

Esas pruebas **no** demuestran lo que ven **dos navegadores reales**; este procedimiento sí, y es lo
que falta para cerrar la Task #420 y la HU-21 (#65). Contrato:
[`hu-21-battle-finish-v1.md`](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/blob/develop/docs/contracts/hu-21-battle-finish-v1.md).

**No es una automatización de navegador.** Es un procedimiento reproducible con evidencia
documentada.

## 1. Requisitos y orden de despliegue

| Condición | Comprobación |
| --- | --- |
| Contrato de Infrastructure **mergeado** (orden 1) | `docs/contracts/hu-21-battle-finish-v1.md` en `develop` |
| Combat **desplegado con la migración `009` ejecutada ANTES de arrancar** (orden 2) | `npm run migrate` contra la base `combat`; el registro `_migrations` incluye `009-battle-rooms-finish` |
| Web con la vista de resultado **desplegado después** (orden 3) | Una sala `FINISHED` en un Web anterior mostraria un estado desconocido; no lo uses para validar |
| Combat con **una sola réplica** | Presencia, cerrojo y planificador viven en memoria del proceso (ADR-020) |
| Dos cuentas de jugador **reales y distintas**, cada una con un héroe equipado elegible para 1 contra 1 **que pueda atacar** | Un héroe ofensivo con Ataque y Daño (no Chamán ni Médico: el documento oficial no les da Ataque ni Daño). Ver HU-07 y HU-16 |
| Dos sesiones aisladas | Chrome normal → cuenta A; ventana de incógnito **o** otro perfil → cuenta B |

**Antes de dar nada por desplegado, comprueba el digest de la imagen que corre**, no el mensaje de
un `apply`:

```bash
docker images --digests ghcr.io/nexus-battle-vi/nexus-battle-combat
# y, en el nodo app (por SSM):
docker ps --format '{{.Image}} {{.Status}}' | grep combat
curl -s https://nexus.simuladorupbbga.app/api/v1/combat/version
```

**No se guardan en la evidencia** contraseñas, códigos TOTP, tokens, tickets ni cabeceras
`Authorization`. Las capturas se recortan o se difuminan si los muestran.

## 2. Preparación

1. Cuenta A crea una sala **PVP 1 contra 1** y cuenta B se une (como en HU-17).
2. Con la sala llena, ambas pantallas pasan a la batalla; comprueba que **el temporizador de turno y
   el global aparecen** (HU-21 los publica como `deadlines`) y que ambos ven lo mismo.
3. Comprueba en `GET /api/v1/combat/rooms/{roomId}` (o en la base) que la sala esta `IN_BATTLE` y
   que la vista trae `deadlines.turnEndsAt` y `deadlines.battleEndsAt`.

## 3. Recorrido por condición

| # | Condición | Acción | Resultado esperado en pantalla | Dato a comprobar en el servidor | Evidencia |
| --- | --- | --- | --- | --- | --- |
| 1 | **Eliminación** | Atacar por turnos hasta que la Vida del rival llegue a 0 | Ambas pantallas pasan a la vista de resultado: ganador «¡Victoria!» / perdedor «Derrota»; **no** hay botones de ataque ni de habilidad; el Poder aparece al máximo | Documento de la sala: `status: FINISHED`, `result.reason: ELIMINATION`, `result.winnerTeamLabel` = equipo del atacante, `events` con `basicAttackResolved` y `battleFinished` de `seq` consecutivos, Poder restaurado; **una** sola version nueva | Captura de las dos pantallas + documento |
| 2 | **Desconexión (vence la gracia)** | Cerrar la **pestaña** de A y esperar **30 s** sin reconectar | B ve «Victoria: tu rival se desconectó y no volvió a tiempo.»; A, si vuelve, ve «Te desconectaste y no volviste a tiempo.» | `result.reason: DISCONNECTION`, `result.disconnected {teamLabel, seat}`, ganador = rival; el registro `battle_finished` con `reason: DISCONNECTION` | Captura + documento |
| 3 | **Desconexión (vuelve dentro de la gracia)** | Cerrar la pestaña de A y **recargar antes de 30 s** | La batalla **continúa**: misma Vida, mismo turno; no hay vista de resultado | La sala sigue `IN_BATTLE`; no hay `battleFinished` en `events` | Captura + documento |
| 4 | **Turno de 30 s** | No actuar durante **30 s** | «{Nombre} perdió el turno por tiempo.» y el turno pasa al rival, con 30 s nuevos en el contador | `events` con `turnTimedOut` (`completedPosition`, `timedOut`); `battle.deadlines.turnEndsAt` renovado; **no** finaliza la batalla | Captura + documento |
| 5 | **6 minutos (porcentaje)** | Jugar **6 minutos reales** sin que nadie quede a 0, con vidas distintas | Vista de resultado con «Se acabó el tiempo (6 minutos).» y, si aplica, «Ganó el equipo con mayor porcentaje de vida restante.» | `result.reason: TIME_LIMIT`, `tiebreak: LIFE_PERCENT` (o `ABSOLUTE_LIFE` si empataron en porcentaje) | Captura + documento |
| 6 | **6 minutos (empate total)** | **Nadie ataca** durante los 6 minutos (vidas idénticas) | «Sin ganador (empate)»; ningún equipo gana | `result.outcome: NO_WINNER`, `winnerTeamLabel: null`, `tiebreak: null` | Captura + documento |
| 7 | **Refresh tras el final** | Recargar (`F5`) cualquiera de las dos sesiones ya terminada | La vista de resultado **sigue**: mismo ganador, misma causa, mismo marcador | El `snapshot` de `resume` trae `result`; la sala sigue `FINISHED` | Captura + documento |
| 8 | **Acciones tras el final** | (DevTools → *WS*) enviar `attack` a mano tras el final | La pantalla no ofrece acciones; el comando se rechaza | `command.rejected {command:"attack", code:"BATTLE_NOT_ACTIVE"}`; sin sorteos y sin cambios en la sala | Captura del *frame* |
| 9 | **Chat de sala cerrado** | Intentar escribir en el chat de la sala terminada | El panel indica que el chat se cerró al terminar la batalla | `chat.subscribe` rechazado (`ROOM_NOT_ACTIVE`) | Captura + *frames* |

> El **desempate absoluto** (mismo porcentaje, distinta vida) no se puede forzar a mano con
> precisión: se comprueba con la evidencia del paso 5 si ocurre y, sobre todo, con los escenarios
> S-12/S-14 de la suite de protocolo.

## 4. Comprobaciones en servidor

```text
1. Registro estructurado: buscar la linea "battle_finished" del servicio combat.
   Debe traer SOLO roomId, reason, outcome y winnerTeamLabel (sin nombres ni creditos por jugador).
2. Documento de la sala (MongoDB, base combat, coleccion battle-rooms):
   - status: FINISHED
   - result: con reason/outcome/winnerTeamLabel/finishedAt/tiebreak/disconnected/teams/participants
   - events: battleFinished aparece UNA sola vez y es el ultimo evento
   - battle.combatants[].currentPower: el maximo (Poder restaurado, HU-11)
3. Chat de la sala: ROOM_CHAT_OPEN[FINISHED] = false (chat.subscribe rechazado con ROOM_NOT_ACTIVE).
4. Planificador: la sala ya no esta en el libro de vencimientos (no se repite ningun barrido).
```

Consulta de ejemplo (sustituye `<roomId>`):

```bash
docker exec -it <contenedor-mongo> mongosh combat --quiet --eval \
  'db["battle-rooms"].findOne({_id:"<roomId>"},{status:1,result:1,"events.type":1})'
```

## 5. Matriz CA → paso → evidencia (la rellena quien ejecuta)

| CA | Criterio | Paso(s) del runbook | Evidencia | Resultado |
| --- | --- | --- | --- | --- |
| CA-01 | Ambos clientes reciben el mismo resultado y se liberan recursos | 1, 7 | ☐ | ☐ PASS / ☐ FAIL |
| CA-02 | Eliminación 1v1 y 2v2 | 1 | ☐ | ☐ PASS / ☐ FAIL |
| CA-03 | Desconexión con gracia (fronteras, reconexión, varias pestañas) | 2, 3 | ☐ | ☐ PASS / ☐ FAIL |
| CA-04 | 6 minutos (frontera 5:59.999/6:00.000) | 5, 6 | ☐ | ☐ PASS / ☐ FAIL |
| CA-05 | Turno de 30 s y liquidación perezosa | 4 | ☐ | ☐ PASS / ☐ FAIL |
| CA-06 | Porcentaje, desempate absoluto y `NO_WINNER` | 5, 6 | ☐ | ☐ PASS / ☐ FAIL |
| CA-07 | Un único resultado, idempotencia, reinicio | 1, 8 | ☐ | ☐ PASS / ☐ FAIL |
| CA-08 | Liberación y notificación con créditos como derecho | 1, 9 + §4 | ☐ | ☐ PASS / ☐ FAIL |
| CA-09 | 2v2 (varios héroes) | 1 (con una sala 2v2) | ☐ | ☐ PASS / ☐ FAIL |
| CA-10 | Vidas por equipo (marcador final) | 5, 6 | ☐ | ☐ PASS / ☐ FAIL |
| CA-11 | Todos los escenarios + validación integrada | Todo lo anterior | ☐ | ☐ PASS / ☐ FAIL |

## 6. HU consumidoras desbloqueadas (NO implementadas aquí)

La HU-21 deja el **estado terminal `FINISHED`** y **una notificación** por el puerto de resultados.
Eso es lo que esas historias necesitan como punto de partida; **ninguna esta implementada todavia**:

| HU | Qué consumira |
| --- | --- |
| HU-22 (#69) | Cofre de recompensa por acumulacion de creditos |
| HU-23 (#70) | Apuesta de creditos en batalla |
| HU-30 (#77) | Caida de items al terminar |
| HU-29 (#76) | Liberacion del bloqueo de equipamiento (consume el estado terminal) |
| HU-09 (#18) | Experiencia por victoria |

## Plantilla de evidencia (para el comentario de cierre de #420)

```text
Entorno: <URL / digest de Combat, Web e Infrastructure>
Fecha y hora:
Cuenta A / Cuenta B: <identificadores no sensibles>, sesiones aisladas: sí
Pasos 1 a 9: PASS / FAIL (con enlace a la captura de cada paso)
Comprobaciones de servidor (§4): PASS / FAIL
Matriz CA-01 a CA-11 (§5): rellenada
Observaciones y desviaciones:
```

Si algún paso falla, la Task **no** se cierra: se documenta el fallo con su captura y se corrige en
el PR que corresponda. El cierre de la HU lo hace quien tenga autoridad sobre ella, con la matriz
consolidada, y nunca un `Closes` en un PR.
