# HU-10 — Evidencia de liquidación de recompensas de finalización

- **Historia:** [HU-10 #19](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/19) · `RF-10`
- **Task de evidencia:** [HU-10.7 #457](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/457)
- **Ejecución registrada:** 2026-10-01, 18 escenarios `PASS`, 0 `FAILED`, 2 `SKIPPED`.
- **Reporte generado:** [`hu-10-ejecucion-e2e.json`](hu-10-ejecucion-e2e.json). Es la salida del runner; no se editaron resultados a mano.
- **Estado:** la capacidad contractual de liquidación está verificada en sus tres autoridades. Esta evidencia **no cierra** la Task ni la HU: quedan revisión humana, CI de los PR y dos escenarios de Combat declaradamente fuera de la cadena real.

## Objetivo y arquitectura comprobada

Una misión terminal crea derechos desde su snapshot, persiste cada entrega como
`PENDING` y la coordina por línea. Las llamadas internas reales y autenticadas
por HMAC acreditan XP y productos en Player-Inventory y créditos en Wallet.
Missions persiste el estado final de la línea y el reporte lo expone.

```text
resultado terminal + contentSnapshot
  -> Missions / PostgreSQL: deliveries PENDING
  -> HTTP + HMAC -> Player-Inventory / MongoDB: XP y productos
  -> HTTP + HMAC -> Wallet / PostgreSQL: créditos
  -> Missions / PostgreSQL: CREDITED o FAILED
  -> GET /api/v1/missions/me/reports/{enrollmentId}
```

No hay transacción distribuida ni acceso productivo entre bases ajenas. El
harness solo las inspecciona por separado como evidencia. Caddy/proxy no es
necesario: el runner aísla puertos, espera health checks y conecta directamente
a los procesos efímeros.

## Versiones y configuración

| Repositorio | SHA ejecutado | Árbol |
| --- | --- | --- |
| Missions | `56bb6481498fc2834e1cd2d9e55266d4eb88e2bd` | limpio |
| Player-Inventory | `809ba1609d5157eef15724bfcb0cab7f5d9e8c2f` | limpio |
| Wallet | `c8d8f4357a14d605239e6abddc54bb8120b21d5a` | limpio |
| Combat | `2c568394dc77362ddcd5016592339680a264a526` | con cambios locales preexistentes en `tools/` |

El runner usa PostgreSQL 17 de Testcontainers para Missions y Wallet, y MongoDB
8 en replica set de Testcontainers para Player-Inventory y los rolls de Combat.
Configura `MISSION_COMPLETION_REWARD_ENABLED=true`,
`MISSION_COMPLETION_REWARDS_DRIVER=http`, `EPIC_GRANTS_DRIVER=http`,
`PLAYER_INVENTORY_BASE_URL`, `WALLET_BASE_URL` e
`INTERNAL_SERVICE_AUTH_SECRET` sintético. No requiere AWS, Cognito, S3 ni
credenciales reales.

| Pieza | Clasificación | Qué se ejecutó |
| --- | --- | --- |
| Missions y PostgreSQL | **REAL** | App Nest, migraciones y persistencia propia |
| Player-Inventory y MongoDB | **REAL** | Proceso hijo, endpoint de XP y `inventory/grants` |
| Wallet y PostgreSQL | **REAL** | Proceso hijo y `mission-reward` |
| HTTP Missions → Player-Inventory / Wallet | **REAL** | Clientes reales con HMAC sintético |
| Rolls HU-09 de Combat y MongoDB | **REAL** | Endpoint y persistencia reales |
| Resultado de simulación Combat | **DOBLE DECLARADO** | Solo fija desenlaces HU-10 reproducibles |
| Lectura Catalog | **DOBLE DECLARADO** | Respondedor 404 para ejercitar el adaptador HTTP real de P/I con producto no-HEROE |
| Identidad de jugador | **DOBLE DECLARADO** | Verificador Nest de prueba; no Cognito |
| Web / navegador / Caddy | **NO NECESARIO** | El contrato se verifica en el endpoint real; Web #188 cubre presentación |

El doble de Combat es inevitable hoy para el cierre de misión: la simulación
real requiere el perfil de héroe de Player-Inventory, cuya resolución depende
de Catalog. No se fabricó un `combatLog` ni se declaró que Combat estuviera
integrado donde no lo está.

## Escenarios ejecutados

| Caso | Resultado | Evidencia observada |
| --- | --- | --- |
| T-00 | PASS | Apps reales, migraciones y motores disponibles |
| T-01 | PASS | XP `10 → 31`, ledger `MISSION_COMPLETION` único y progresión |
| T-02 | PASS | Saldo Wallet `0 → 7` y un ledger propio |
| T-03 | PASS | Inventario `0 → 2` y `operationId` UUID v5 |
| T-04 | PASS | XP, crédito y producto terminan `CREDITED` |
| T-05 | PASS | `FAILED` acredita XP de finalización |
| T-06 | PASS | `grantOn=[COMPLETED]` no crea crédito ni producto al fallar |
| T-07 | PASS | `IN_PROGRESS` no crea deliveries ni efectos externos |
| T-08 | PASS | `VOIDED` no liquida |
| T-09 | PASS | Cierre usa snapshot A: XP 21, créditos 7 y producto 2; no B |
| T-10 | PASS | Replay no duplica XP, ledger, grant, líneas ni delivery |
| T-11 | PASS | Wallet caída: XP/producto acreditan; crédito `PENDING → CREDITED` al recuperar |
| T-12 | PASS | P/I caída: crédito acredita; XP/producto recuperan sin duplicar |
| T-13 | PASS | Fuentes HU-09 y HU-10 y sus `operationId` permanecen separadas |
| T-14 | SKIPPED | No se afirma convivencia de loot HU-72 sin Combat+Catalog real |
| T-15 | SKIPPED | No se afirma convivencia de épica HU-73 sin aparición real determinista |
| T-16 | PASS | Solo el jugador/héroe A recibe las tres recompensas |
| T-17 | PASS | HEROIC usa XP 34 del snapshot |
| T-18 | PASS | Reporte real expone `PENDING → CREDITED` y progresión solo para XP acreditada |
| T-19 | PASS | `victory_progress` y `weekly_chest_count` siguen en 0 |

Los importes 21/34 XP, 7/9 créditos y 2/3 productos son **fixtures técnicos
distintivos**. No son montos, economía ni contenido aprobado.

## Matriz de criterios de aceptación

| CA | Escenario(s) | Evidencia | Resultado |
| --- | --- | --- | --- |
| CA-01 | T-04, T-10 | Deliveries y efectos físicos únicos | PASS |
| CA-02 | T-01, T-05, T-13 | XP de finalización para COMPLETED/FAILED; fuente separada en P/I | PASS |
| CA-03 | T-02, T-11, T-19 | Wallet, recovery y estado HU-22 sin alterar | PASS |
| CA-04 | T-03, T-12 | `inventory/grants` y recuperación | PASS |
| CA-05 | T-14, T-15 | Ambos escenarios quedan explícitamente sin verificar | **SKIPPED** |
| CA-06 | T-09 | Snapshot A prevalece sobre contenido B | PASS |
| CA-07 | T-10, T-11, T-12 | Replay y recuperación con la misma clave | PASS |
| CA-08 | T-07, T-08 | IN_PROGRESS y VOIDED sin liquidación | PASS |
| CA-09 | T-18 + Web #188 | Endpoint real y presentación/polling ya integrados en Web | PASS para el contrato publicado |
| CA-10 | T-16 | A recibe; B no recibe | PASS |
| CA-11 | T-04 | Las tres autoridades concluyen `CREDITED` | PASS para la liquidación; CA-05 sigue SKIPPED |

## Reporte, Web y regresiones

El endpoint real `GET /api/v1/missions/me/reports/{enrollmentId}` muestra las
líneas HU-10 y su transición. La línea XP incluye progresión únicamente después
de `CREDITED`; créditos y productos conservan cantidad sin progresión.

Web no se modificó ni se lanzó un navegador por ceremonia. La PR
[Web #188](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/188), ya
integrada en `develop`, cubre XP, créditos con cantidad, producto, estados,
polling, progresión y ausencia de autoridad de dominio en el cliente.

La cadena HU-09 existente se ejecutó como regresión (`S-00…S-12`, 13/13 en su
reporte versionado); T-13 añade la comprobación de coexistencia: HU-10 no
recalcula ni reutiliza `MISSION_RIVAL_DEFEAT`. La cobertura E2E informativa
del runner fue 54.04% líneas, 55.21% statements, 44.83% funciones y 29.09%
branches; no representa una puerta de cobertura global.

## Pendientes y límites

- **P-HU10-1:** semántica de `ABANDONED`.
- **P-HU10-2:** montos productivos definitivos.
- **P-HU10-3:** qué créditos/productos reales aplican a `FAILED`.
- **P-HU10-4:** semántica de `FIRST_TIME`.
- T-14 y T-15 no se maquillan como verdes: requieren una cadena
  Combat + perfil Catalog real y, para la épica, una aparición reproducible.
- El Catalog 404 y el verificador de identidad son dobles declarados; solo
  permiten probar las fronteras reales HU-10 sin servicios externos.

No se modificó Management, no se cerró ninguna Task o HU, no se fusionó ningún
PR y no se introdujeron valores productivos.
