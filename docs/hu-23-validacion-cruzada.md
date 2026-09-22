# HU-23 — Validación cruzada de la apuesta de créditos (Task #437)

Complementa la validación automatizada de la Task [#437](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/437):
qué se probó con servicios reales, qué **no** quedó demostrado de extremo a extremo y por qué el
plan B lo compensa. Contrato:
[`hu-23-battle-stake-v1.md`](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/blob/develop/docs/contracts/hu-23-battle-stake-v1.md).

## 1. V1 (E2E cross-service real): intentado y por qué no se entrega

El plan de #437 pedía un `test/db/battle-stake.e2e.spec.ts` en Combat que levantara **dos
aplicaciones Nest reales en el mismo proceso de Jest** (Combat con su MongoDB y Wallet con su
PostgreSQL, ambas por Testcontainers) y ejercitara el camino completo por HTTP+HMAC.

Se intentó. La importación cruzada del `AppModule` de Wallet desde un test de Combat **compila y
carga** (Node resuelve las dependencias de Wallet desde su propio `node_modules`), pero el arranque
falla por un límite real de la topología de repos:

1. **Dos copias de `@nestjs/core`.** Wallet tiene su propia copia y sus guards globales
   (`APP_GUARD`) inyectan **su** `Reflector`. El módulo de pruebas de Combat registra el suyo, y los
   proveedores del módulo raíz **no son visibles** para un módulo importado: Nest no puede resolver
   `Reflector at index [1]` del guard de Wallet. Resolverlo exigiría tocar el `AppModule` de Wallet
   solo para un test de Combat (o duplicar el `Reflector` con una ruta dentro de
   `node_modules`, que es peor).
2. **La CI de Combat no ve el repo hermano.** `ci.yml` de Combat ejecuta `npm run test:db` y clona
   únicamente Combat. Un test que importa `../Nexus-Battle-Wallet` **rompe la CI** en cuanto el
   repositorio no esté al lado. Una prueba que no puede correr en la puerta de calidad del propio
   repo no es una prueba: es una deuda.

La alternativa de arrancar Wallet como **proceso hijo** con su `dist` sí funciona en local, pero
tiene el mismo problema de CI (necesita el repo hermano) y añade fragilidad de puertos/arranque.

**Decisión:** plan B, que el propio plan de #437 autoriza explícitamente
(`04-VALIDACION-437.md` §V2), **más** el runbook de aceptación manual
([`hu-23-aceptacion-manual.md`](../runbooks/hu-23-aceptacion-manual.md)) para el camino real sobre
el sistema desplegado.

## 2. Qué SÍ quedó demostrado, por lado

| Escenario (contrato §12)                                | Dónde se demuestra                                                                                                                                           | Con qué                                                                                 |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------- |
| S-01 crear con apuesta → reserva y `available` baja     | Combat `test/integration/battle-room-stake-http.spec.ts`; Wallet `test/integration/wallet-stakes-http.spec.ts` y `test/db/postgres-stake-repository.spec.ts` | HTTP real de Combat (doble de Wallet), HTTP real de Wallet (HMAC) y **PostgreSQL real** |
| S-02 unirse con apuesta                                 | Combat `test/unit/join-battle-room.stake.spec.ts` + `test/integration/battle-room-stake-http.spec.ts`                                                        | Orquestación real de Combat + reserva contra el puerto                                  |
| S-03 apostar más del disponible → 422 y nada reservado  | Combat `test/integration/battle-room-stake-http.spec.ts` (code propagado) y Wallet `test/db/postgres-stake-repository.spec.ts` (rollback real)               | Ambos lados                                                                             |
| S-04 sin apuesta: comportamiento intacto                | Combat `test/unit/*.stake.spec.ts` y suites de regresión de HU-14/15                                                                                         |                                                                                         |
| S-05 cancelar libera todo                               | Combat `test/unit/cancel-battle-room.stake.spec.ts`; Wallet `test/db/postgres-stake-repository.spec.ts` (release)                                            |                                                                                         |
| S-06 `leave` libera solo la propia                      | Combat `test/unit/leave-battle-room.stake.spec.ts`                                                                                                           |                                                                                         |
| S-07 1v1 con ganador: transferencia exacta              | Wallet `test/db/postgres-stake-repository.spec.ts` (PostgreSQL real); reparto en Combat `test/unit/battle-stake-policy.spec.ts`                              |                                                                                         |
| S-08 2v2 reparto igual                                  | Wallet `test/db/...` (pozo 30 → 15/15) y política pura de Combat                                                                                             |                                                                                         |
| S-09 `NO_WINNER` libera todo                            | Combat `test/unit/reconcile-stakes.spec.ts` y `test/unit/reward-workflow-result-publisher.spec.ts`; Wallet `test/db/...` (release)                           |                                                                                         |
| S-10 `DISCONNECTION` liquida igual                      | Combat `test/unit/battle-stake-policy.spec.ts` (resultado `WIN`)                                                                                             |                                                                                         |
| S-11 sala sin apuestas: Wallet nunca recibe `/stakes/*` | Combat `test/unit/reward-workflow-result-publisher.spec.ts` y `test/integration/battle-room-stake-http.spec.ts`                                              |                                                                                         |
| S-12 replay idempotente                                 | Wallet `test/db/...` y `test/integration/wallet-stakes-http.spec.ts` (S-12 HTTP)                                                                             |                                                                                         |
| S-13 mismo `operationId`, otro cuerpo → 409             | Wallet `test/db/...` y HTTP; cliente de Combat `test/unit/wallet-stake-http-client.spec.ts`                                                                  |                                                                                         |
| S-14 reservas concurrentes                              | Wallet `test/db/postgres-stake-repository.spec.ts` (dos conexiones reales)                                                                                   |                                                                                         |
| S-15 `/settle` no cero suma → 422 y nada aplicado       | Wallet `test/db/...` (rollback real) y HTTP                                                                                                                  |                                                                                         |
| S-16 PVE con apuesta → 422 sin llamar a Wallet          | Combat dominio + `test/integration/battle-room-stake-http.spec.ts`                                                                                           |                                                                                         |
| S-17 recuperación al arrancar                           | Combat `test/unit/reconcile-stakes.spec.ts`                                                                                                                  |                                                                                         |
| S-18 `GET /wallet/me` con reserva activa                | Wallet `test/integration/wallet-stakes-http.spec.ts` (HTTP) y `test/unit/get-wallet-snapshot.spec.ts`                                                        |                                                                                         |

Además, la **firma HMAC** de las llamadas de apuesta tiene prueba por los dos lados del mismo
esquema canónico: Combat firma con `signInternalRequest` y `test/unit/wallet-stake-http-client.spec.ts`
recalcula la firma esperada; Wallet la verifica con `InternalServiceGuard` en
`test/integration/wallet-stakes-http.spec.ts` (firma válida/inválida/servicio no autorizado).

## 3. Qué NO quedó demostrado de extremo a extremo

- **La firma HMAC real entre los dos procesos desplegados**: cada lado prueba su mitad del esquema,
  pero no hay una ejecución en la que el cliente real de Combat hable con el Wallet real por la red.
- **El camino completo Combat → Wallet en una sola corrida** (crear/unirse/cancelar/terminar con los
  dos servicios reales), incluida la liquidación disparada por `battleFinished` contra el Wallet
  real y la comprobación del saldo con una consulta directa.
- **La concurrencia entre los dos servicios** (por ejemplo, cancelar mientras liquida): se prueba la
  concurrencia dentro de Wallet (PostgreSQL real) y la orquestación de Combat por separado.

Estos tres puntos son exactamente los pasos 1 a 5 del runbook manual, que se ejecuta sobre el
sistema desplegado con saldo real y dos cuentas reales.

## 4. Cómo se compensa

1. Los contratos de ambos lados están fijados por el contrato `hu-23-battle-stake-v1.md` y las
   pruebas de cada lado comprueban los **mismos códigos y cuerpos** (§5 y §11) que cruzan la red.
2. Wallet se prueba contra **PostgreSQL real** (constraints, `pg_advisory_xact_lock`, concurrencia y
   rollback), que es donde vive el dinero; Combat se prueba contra **HTTP real** de su propio
   servicio (guards, DTOs, controlador y casos de uso).
3. El runbook manual cubre el hueco restante con evidencia documentada (matriz CA-01 a CA-08 con
   casillas **vacías** hasta que alguien la ejecute).
