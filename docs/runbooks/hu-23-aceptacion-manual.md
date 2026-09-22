# Aceptación manual de HU-23 con dos sesiones reales

Complementa la validación automatizada de la Task [#437](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/437):

- Wallet, `test/db/postgres-stake-repository.spec.ts` y `test/integration/wallet-stakes-http.spec.ts`:
  reserva, liberación y liquidación contra **PostgreSQL real** y HTTP real con firma HMAC.
- Combat, `test/integration/battle-room-stake-http.spec.ts` y las suites `*.stake.spec.ts`: ciclo de
  sala real con el puerto de Wallet doblado.
- Lo que **no** quedó demostrado de extremo a extremo y por qué está en
  [`docs/hu-23-validacion-cruzada.md`](../hu-23-validacion-cruzada.md) (plan B de la Task #437).

Este procedimiento cubre ese hueco con dos navegadores y **saldo real en Wallet**. Contrato:
[`hu-23-battle-stake-v1.md`](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/blob/develop/docs/contracts/hu-23-battle-stake-v1.md).

**No es una automatización de navegador.** Es un procedimiento reproducible con evidencia documentada.

## 1. Requisitos y orden de despliegue

| Condición                                                                                                                   | Comprobación                                                                                                          |
| --------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Contrato de Infrastructure **mergeado** (orden 1)                                                                           | `docs/contracts/hu-23-battle-stake-v1.md` en `develop`                                                                |
| Wallet **desplegado con la migración `002-wallet-stakes` ejecutada ANTES de arrancar** (orden 2)                            | `npm run migrate` contra la base de Wallet; la tabla `wallet_stake_holds` existe y `wallet_accounts` tiene `reserved` |
| Combat **desplegado después** (orden 3)                                                                                     | `npm run migrate` contra la base `combat`; el registro `_migrations` incluye `011-battle-rooms-stake`                 |
| Web **desplegado al final** (orden 4)                                                                                       | Sin el campo de apuesta, la sala se crea por API pero Web no muestra el estado de la reserva                          |
| Dos cuentas de jugador **reales y distintas**, cada una con un héroe equipado elegible para 1 contra 1 **que pueda atacar** | Ver HU-07 y HU-16                                                                                                     |
| **Saldo real en Wallet** para ambas cuentas (créditos ganados en batallas de HU-22 o el mecanismo de desarrollo que exista) | `GET /api/v1/wallet/me` con la sesión de cada cuenta: `balance` y `available`                                         |
| Dos sesiones aisladas                                                                                                       | Chrome normal → cuenta A; ventana de incógnito **o** otro perfil → cuenta B                                           |

**Antes de dar nada por desplegado, comprueba el digest de la imagen que corre**, no el mensaje de un
`apply`:

```bash
docker images --digests ghcr.io/nexus-battle-vi/nexus-battle-wallet
docker images --digests ghcr.io/nexus-battle-vi/nexus-battle-combat
# y, en el nodo app (por SSM):
docker ps --format '{{.Image}} {{.Status}}' | grep -E 'wallet|combat'
```

**No se guardan en la evidencia** contraseñas, códigos TOTP, tokens ni cabeceras `Authorization`.
Las capturas se recortan o se difuminan si los muestran.

## 2. Preparación

1. Anota el saldo de las dos cuentas (`GET /api/v1/wallet/me`): `balance`, `reserved` y `available`.
2. Cuenta A crea una sala **PVP 1 contra 1** con **apuesta 10** y **recompensa de la sala 0** (son
   campos distintos: la recompensa de HU-14 no se toca).
3. Cuenta B se une a esa sala con **su propia apuesta** (por ejemplo 25; D1: nadie iguala a nadie).
4. Comprueba en la base de Wallet (`wallet_stake_holds` y `wallet_accounts`) que hay **un** hold
   `ACTIVE` por jugador y que `reserved` subió exactamente el monto de cada uno, con `balance`
   **intacto**.

## 3. Recorrido por condición

| #   | Condición                                | Acción                                                                                         | Resultado esperado en pantalla                                                                                                              | Dato a comprobar en el servidor                                                                                                                                                            | Evidencia             |
| --- | ---------------------------------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------- |
| 1   | **Reserva (S-01/S-02/S-18)**             | Crear con apuesta y unirse con apuesta                                                         | El lobby muestra «Apuesta reservada: N créditos» a cada jugador con su propio monto                                                         | `wallet_accounts.reserved` = suma de apuestas; `balance` sin cambios; `available` = `balance - reserved`; un hold `ACTIVE` por jugador                                                     | Captura + consulta    |
| 2   | **Saldo insuficiente (S-03)**            | Intentar unirse apostando más que el disponible de esa cuenta                                  | La tarjeta muestra el mensaje de saldo insuficiente; la persona **no** queda en la sala                                                     | Ningún hold nuevo y `reserved` sin cambios; la sala no gana participantes                                                                                                                  | Captura + consulta    |
| 3   | **Cancelar antes de iniciar (S-05)**     | Cuenta A cancela la sala                                                                       | Ambas sesiones ven la sala cancelada; el estado de la apuesta pasa de «Apuesta reservada» a «Se liberó tu apuesta de N créditos» (no antes) | `reserved` de ambos vuelve a su valor inicial; los dos holds quedan `RELEASED`                                                                                                             | Captura + consulta    |
| 4   | **Abandonar una sala de equipo (S-06)**  | En una sala 2v2 (A + tercero contra B), abandonar antes de iniciar                             | El que abandona ve su apuesta liberada; los demás siguen «Apuesta reservada»                                                                | Solo el hold del que se fue queda `RELEASED`; `reserved` de los demás intacto                                                                                                              | Captura + consulta    |
| 5   | **Victoria con liquidación (S-07/S-10)** | Jugar 1v1 con apuestas hasta que alguien gane (eliminación o desconexión)                      | Ganador: «Apuesta ganada: N créditos»; perdedor: «Perdiste tu apuesta de M créditos»; el saldo mostrado es el del servidor                  | Una sola llamada a `/settle` por batalla; el perdedor baja exactamente lo capturado y el ganador sube exactamente lo mismo; ambos `reserved` a 0; los holds quedan `CAPTURED` y `RELEASED` | Captura + consulta    |
| 6   | **Empate / `NO_WINNER` (S-09)**          | Si es reproducible a mano: jugar sin que nadie quede a 0 y dejar vencer el tiempo global       | Ambas sesiones: «Se liberó tu apuesta de N créditos»                                                                                        | Ningún `balance` cambia; los dos holds `RELEASED`; **no** hay llamada a `/settle`                                                                                                          | Captura + consulta    |
| 7   | **PVE sin apuesta (S-16)**               | Intentar crear una sala JcE: el campo de apuesta **no** debe existir                           | El formulario JcE no muestra «Apostar créditos (opcional)»                                                                                  | Sin holds nuevos                                                                                                                                                                           | Captura               |
| 8   | **Idempotencia (S-12/S-13)**             | Reintentar `reserve`/`release`/`settle` con el mismo `operationId` (DevTools o script firmado) | Sin cambio visible (replay)                                                                                                                 | Segunda respuesta `applied: false`; mismo `operationId` con otro cuerpo → `409`; ningún saldo se mueve dos veces                                                                           | Salida de la petición |

> El **reparto 2v2 en partes iguales** (S-08) y la **invariante de suma cero** (S-15) se validan con
> dos cuentas solo si se completa una 2v2 real; si no, quedan cubiertos por las suites de PostgreSQL
> real de Wallet (pozo 30 → 15/15 y `SETTLEMENT_NOT_ZERO_SUM`) y se anota tal cual.

## 4. Comprobaciones en servidor

```text
1. Registro estructurado de combat: la linea "battle_finished" sigue trayendo SOLO
   roomId, reason, outcome y winnerTeamLabel (la apuesta no anade datos al registro).
2. PostgreSQL de Wallet (base wallet):
   - wallet_stake_holds: un hold por operationId, con status ACTIVE -> RELEASED/CAPTURED/EXPIRED
   - wallet_stake_ledger: RESERVE / RELEASE / SETTLE_CAPTURE / SETTLE_CREDIT (uno por movimiento)
   - wallet_accounts: balance solo cambia con SETTLE_CAPTURE/SETTLE_CREDIT; reserved solo con
     RESERVE/RELEASE/settle
   - Suma de control: Σ(CAPTURED) == Σ(CREDITED) por cada operationId de tipo settle
3. MongoDB de combat (base combat, coleccion battle-rooms):
   - teams[].participants[].stake.status coherente con el resultado (CAPTURED/SETTLED_WON/RELEASED)
   - ningun participante sin apuesta lleva el campo stake
4. Contrato de sala (GET /api/v1/combat/rooms/{roomId}): stakePool.total = suma de apuestas ACTIVE;
   la apuesta de un rival NO viaja en el DTO (solo la propia).
```

Consultas de ejemplo (sustituye `<playerId>`/`<battleId>`):

```bash
docker exec -it <contenedor-postgres> psql -U <usuario> -d wallet -c \
  "select player_id, balance, reserved from wallet_accounts where player_id = '<playerId>';"
docker exec -it <contenedor-postgres> psql -U <usuario> -d wallet -c \
  "select operation_id, player_id, amount, status from wallet_stake_holds where battle_id = '<battleId>';"
docker exec -it <contenedor-mongo> mongosh combat --quiet --eval \
  'db["battle-rooms"].findOne({_id:"<battleId>"},{"teams.participants.stake":1,result:1})'
```

## 5. Matriz CA → paso → evidencia (la rellena quien ejecuta)

| CA    | Criterio                                                       | Paso(s) del runbook             | Evidencia | Resultado       |
| ----- | -------------------------------------------------------------- | ------------------------------- | --------- | --------------- |
| CA-01 | Apostar es opcional y solo con créditos disponibles            | 1, 2, 7                         | ☐         | ☐ PASS / ☐ FAIL |
| CA-02 | El monto se indica al crear o al unirse, individual            | 1                               | ☐         | ☐ PASS / ☐ FAIL |
| CA-03 | Los créditos quedan reservados mientras la batalla está activa | 1, 3                            | ☐         | ☐ PASS / ☐ FAIL |
| CA-04 | Reservar no toca el `balance`; el máximo es el disponible      | 1, 2                            | ☐         | ☐ PASS / ☐ FAIL |
| CA-05 | Con ganador válido el monto se transfiere al ganador           | 5, 6                            | ☐         | ☐ PASS / ☐ FAIL |
| CA-06 | Cancelar o abandonar antes de iniciar libera los créditos      | 3, 4                            | ☐         | ☐ PASS / ☐ FAIL |
| CA-07 | La operación no duplica ni pierde créditos en ningún paso      | 1 a 6, 8 + §4                   | ☐         | ☐ PASS / ☐ FAIL |
| CA-08 | `room.reward.amount` no cambia de semántica ni de interfaz     | 2 (recompensa 0 y campo aparte) | ☐         | ☐ PASS / ☐ FAIL |

## Plantilla de evidencia (para el comentario de cierre de #437)

```text
Fecha:
Ejecutado por:
Commit/version de Wallet (digest):
Commit/version de Combat (digest):
Commit/version de Web:

Saldos iniciales (A / B): balance ___ / ___, available ___ / ___
Paso 1 (reserva): holds ___ / ___, reserved ___ / ___, balance ___ / ___
Paso 3 (cancelar): reserved final ___ / ___, estado de holds ___
Paso 5 (victoria): balance final ___ / ___, suma capturada ___, suma acreditada ___
Paso 8 (replay/conflicto): applied ___ , codigo 409 ___
CA-01..CA-08: resultado por criterio y enlace a la captura/consulta
```
