# HU-30 — Evidencia de la implementación del drop de piezas equipadas por derrota en Versus

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#77](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/77)
- **Tasks:** [#534](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/534) (contrato) · [#535](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/535) (Combat) · [#536](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/536) (Player-Inventory) · [#537](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/537) (Notifications + Web) · [#538](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/538) (E2E + evidencia)
- **Fecha de esta revisión:** 2026-10-01
- **Requisito trazado:** HU-30, §6.1.3 del SRS (tablas 8–19, tasas de caída)
- **Bounded context:** Combat (resolución y liquidación diferida) · Player-Inventory (ownership, loadout, transferencia) · Notifications (avisos) · Catalog (tasa canónica) · Web (presentación)
- **Contrato de la integración:** [`hu-30-versus-drop-v1`](../contracts/hu-30-versus-drop-v1.md)

## Estado a 2026-10-01

**El backend (Combat, Player-Inventory, Notifications, Catalog) y la presentación en Web están
implementados y verificados, cada uno en su propio PR abierto hacia `develop`, ninguno mergeado
todavía.** La verificación de extremo a extremo entre los tres servicios reales (Combat, Player-Inventory,
Notifications) vive en el mismo PR de Combat, en 5 escenarios, **3 corridas consecutivas en verde**.

| Pieza | Repositorio / PR | SHA | Estado |
| --- | --- | --- | --- |
| Contrato `hu-30-versus-drop-v1` + esta evidencia | Infrastructure (esta rama, `docs/hu-30-drop-contract-and-evidence`) | — | **Abierta, sin mergear** |
| Tasa de caída canónica (`dropChanceBasisPoints`) + operación administrativa para productos existentes | Catalog [#69](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/69) | `9b7b2fc6d2f7b13a09465e9b50058bfa18a123ee` | **Abierto, sin mergear** |
| Resolución del drop (RNG, selección, liquidación diferida), reconciliador, E2E real | Combat [#66](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/66) | `1c474f39af3c4e3ceb299486673dcc1f9b18d1f9` | **Abierto, sin mergear** |
| Identidad por unidad, transferencia atómica idempotente | Player-Inventory [#71](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/71) | `0e817e7adcb1a6e924a7633c096d0d50f42a4917` | **Abierto, sin mergear** |
| Notificación de ganador/perdedor | Notifications [#44](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/44) | `569954613a060232a317ce2181e905f1b24dcd51` | **Abierto, sin mergear** |
| Presentación en Mi Inventario / novedades | Web [#195](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/195) | `98e32c4fc9e9ba6f5f60a7ddab83f0d61e40af41` | **Abierto, sin mergear** |

**Este documento no declara la HU aceptada.** La aceptación de `#77` requiere que los cinco PRs se
mergeen y la decisión explícita del equipo/PO (ver «Pendientes reales»).

## 1. Auditoría inicial (por repositorio)

| Repo | Ya existía | Faltaba | Se reutilizó |
| --- | --- | --- | --- |
| Catalog | Contrato canónico de producto (ADR-013), `attributes` por tipo | `dropChanceBasisPoints`; una vía para configurarlo en un producto **ya existente** | Mismo patrón transaccional (producto + auditoría RNF-06 + outbox) que `ConfigureProductPremium`/`AdjustProductInventory`; mismo rol/MFA |
| Combat | RNG central HU-24 (`RandomSequencePort`, `BoundedRandom`), ciclo de vida de batalla HU-14 a HU-23, compromiso HU-29 | Detección del evento letal real en PvP, evaluación individual por candidato, selección por tasa máxima, liquidación diferida, reconciliador | `ExecuteBasicAttack`/`UseSkill` (hook del evento letal), `BattleHeroCommitmentPort` (mismo patrón de liberación diferida), `IntervalRewardWorkflowScheduler`/`IntervalBattleDeadlineScheduler` (mismo patrón de barrido) |
| Player-Inventory | Loadout por slot (HU-28), inventario por cantidad (HU-27), compromiso de batalla (HU-29), HMAC interno | Identidad física por unidad equipada; transferencia atómica de ownership entre dos jugadores | Transacción Mongo (mismo patrón que `MongoBattleHeroCommitmentRepository`), `inventory/grants` como referencia de operación HMAC-firmada (sin reutilizar su semántica de *otorgar* para *transferir*) |
| Notifications | Servidor interno HMAC multi-ruta para Auction (HU-63.5/HU-64.5/HU-67), repositorio de notificaciones dirigidas por `playerId` | Ruta para Combat, tipos de cambio propios | Mismo servidor (`createAuctionOutbidServer`, ahora multi-origen), mismo repositorio |
| Web | Novedades de catálogo (HU-38), TanStack Query con `staleTime: 30s` | Etiqueta propia para los dos tipos nuevos; invalidación de inventario al enterarse de un drop | `usePendingCatalogNotifications` (mismo hook), `CatalogNotificationBadge` (mismo componente, nuevas entradas en sus diccionarios) |

## 2. Arquitectura final HU-30

```text
DefeatEvent (ExecuteBasicAttack / UseSkill, PvP real)
   |
   v
PersistVersusDropDecision -- candidatos = loadout congelado al iniciar
   |                          (snapshot real de Player-Inventory)
   v
ResolveVersusDrop -- RNG central (HU-24), 2 indices por candidato
   |
   +--> NO_DROP (ninguno elegible)
   +--> AWAITING_TIE_RULE (empate maximo, P-HU30-TIE)
   +--> PENDING (seleccionado; ownership SIN TOCAR)
   |
Battle FINISHED (persistido)
   |
   v
IntervalBattleDropScheduler (reconciliador, solo tras FINISHED)
   |
   v
Player-Inventory -- transaccion Mongo real --
   +--> source pierde la instancia (misma productInstanceId)
   +--> target recibe la MISMA instancia
   +--> loadout del derrotado se limpia
   |
   v
Notifications -- HMAC real -- aviso GANADOR + aviso PERDEDOR
   |
   v
Combat libera el compromiso HU-29 de cada humano (closeBattle)
   |
   v
Web -- GET autoritativo (invalidacion tras notificacion) --> Mi Inventario
```

## 3. Cambios por repositorio

### Catalog

- `dropChanceBasisPoints` opcional en `ARMA`/`ARMADURA`/`ITEM` al crear un producto (`product-attributes.ts`).
- `ConfigureProductDropChance` + `PATCH /api/v1/admin/products/{id}/drop-chance`: única vía para fijar la tasa en un producto **ya existente**, sin reabrir la inmutabilidad general de `attributes` que `UpdateProductDetails` declara a propósito.

### Combat

- `VersusDrop` (dominio), `ResolveVersusDrop` (evaluación individual + selección), `PersistVersusDropDecision` (hook del evento letal, guardado junto al evento, sin re-sortear en replay).
- `BattleDropWorkflowRepositoryPort`/`MongoBattleDropWorkflowRepository` (`battle-drop-workflows`, `battle-drop-settlements`), `IntervalBattleDropScheduler` (reconciliador real, 2s).
- `PlayerInventoryBattleDropHttpClient`, `NotificationsBattleDropHttpClient` (clientes HTTP+HMAC reales).
- `StartBattle` captura la instantánea de cada humano al iniciar; `BattleFinalizer` difiere la liberación del compromiso HU-29 si hay drops pendientes.
- `test/e2e/hu-30/`: E2E real (fuera de CI, documentado el motivo igual que HU-29).
- `test/unit/hu30-team-drop-attribution.spec.ts`: 2v2, atribución por equipo.

### Player-Inventory

- `battle-drop-units`/`battle-drop-snapshots`/`battle-drop-transfers` (migración `015`).
- `CaptureBattleDropSnapshot` (materializa identidad física, exige tasa canónica), `TransferBattleDrop` (transacción Mongo real, idempotente).
- Cuatro rutas internas nuevas, caller `combat` exclusivo.

### Notifications

- `CreateBattleDropNotification`, tipos `BATTLE_DROP_GAINED`/`BATTLE_DROP_LOST`.
- `POST /api/internal/v1/notifications/combat/drop` en el mismo servidor HMAC que ya atendía a Auction, ahora documentado como multi-origen.

### Web

- `CatalogNotificationBadge`/`contract.ts`: etiqueta y tono para los dos tipos nuevos.
- `usePendingCatalogNotifications`: invalida `['inventory','me']` al detectar una notificación de drop, forzando una relectura autoritativa sin mutación optimista.

### Torneo

No hay repositorio/servicio Tournament local ni integración de justas verificada al 2026-10-01
(`ADR-022` sigue `Proposed`). **`SKIPPED`** — no se le atribuye evidencia E2E a un torneo inexistente.
La mecánica central queda reutilizable sin cambios de dominio cuando Tournament exista.

## 4. Contratos

| Endpoint/evento | Autoridad | Caller |
| --- | --- | --- |
| `POST /api/internal/v1/inventory/battle-drops/snapshots` | Player-Inventory | `combat` (HMAC) |
| `GET /api/internal/v1/inventory/battle-drops/snapshots/:battleId/:playerId` | Player-Inventory | `combat` (HMAC) |
| `POST /api/internal/v1/inventory/battle-drops/transfers` | Player-Inventory | `combat` (HMAC) |
| `POST /api/internal/v1/inventory/battle-drops/battles/:battleId/close` | Player-Inventory | `combat` (HMAC) |
| `POST /api/internal/v1/notifications/combat/drop` | Notifications | `combat` (HMAC) |
| `PATCH /api/v1/admin/products/{id}/drop-chance` | Catalog | `Administrator` + MFA |

## 5. RNG

`ResolveVersusDrop` consume la ÚNICA fuente de aleatoriedad de Combat (`RandomSequencePort`, HU-24,
MT19937 uniforme 1..8000): dos índices por candidato, `(first·8000+second) mod 10000` para un valor
uniforme 0..9999 sin sesgo siquiera en una tasa de 0,01 %. Nunca `Math.random`, nunca una secuencia
paralela. El E2E real fija la tasa del producto en 0 %/100 % para ser determinista **sin** tocar el RNG
central (el mismo patrón que `test/db/basic-attack.e2e.spec.ts`/`skills.e2e.spec.ts` ya usan para fijar
el dado de HU-18).

## 6. 1v1

E2E real (Combat + Player-Inventory + Notifications + Mongo x3): E-01 (0%, `NO_DROP`, cero
transferencias, ownership intacto, cero notificación) y E-02 (100%, `PENDING` durante la partida,
`CREDITED` solo tras `FINISHED`, ownership real movido, dos notificaciones reales, compromisos HU-29
liberados). **PASS**, 3/3 corridas.

## 7. 2v2 / equipos

`test/unit/hu30-team-drop-attribution.spec.ts` (Combat, real excepto el cliente HTTP de
Player-Inventory, declarado): A1 derrota a B1 y muere después a manos de B2; B2 también derrota a A2;
equipo B gana la partida. El derecho `B1→A1` se liquida igual aunque A1 termine en el equipo perdedor
y muerto — el resultado final del equipo **no** lo reasigna. **PASS**.

## 8. Multi-kill

Mismo test de la sección 7: B2 acumula **dos** derechos independientes (`A1→B2`, `A2→B2`) en la misma
partida, uno por cada derrota que produjo. **PASS**.

## 9. Liquidación diferida

E-02 verifica directamente en Mongo de Player-Inventory que, mientras la sala sigue `IN_BATTLE`, la
unidad equipada está **reservada** (`battleId = roomId`) pero su `ownerId` sigue siendo el derrotado.
Ningún ownership cambia hasta después de `FINISHED` + reconciliación. **PASS**.

## 10. Ownership final

`productInstanceId` antes: `ownerId = jugador-b-e2e-hu30(2)`. Después de la liquidación: **el mismo**
`productInstanceId`, `ownerId = jugador-a-e2e-hu30`, `battleId = ''` (reserva cerrada). Cantidad en
`inventories` del ganador +1, del derrotado −1. Sin clon, sin segunda instancia. **PASS**.

## 11. Idempotencia y recovery

- Un segundo `tick()` del reconciliador tras `CREDITED` no vuelve a transferir (`battle-drop-transfers`
  no crece) y el ownership no cambia. **PASS**.
- `TransferBattleDrop` (Player-Inventory, DB real): mismo `operationId` + mismo payload devuelve el
  mismo resultado; el mismo `operationId` con un `targetPlayerId` distinto es un conflicto real
  (`BattleDropTransferConflictError`). **PASS**.

## 12. Notifications

Tras la acreditación real, exactamente dos filas en `catalog_notifications` de Notifications:
`BATTLE_DROP_GAINED` para el ganador, `BATTLE_DROP_LOST` para el derrotado, cada una con su
`sourceEventId` propio (`battleId:defeatEventSeq`). Sin drop, cero notificaciones. **PASS**.

## 13. Web / Mi Inventario

Sin cambios de pantalla. `usePendingCatalogNotifications.test.tsx` demuestra que una notificación
`BATTLE_DROP_GAINED` dispara una relectura real de `/inventories/me/items` **además** de la carga
inicial (prueba de que la invalidación ocurre, no solo que el montaje inicial funciona), y que una
notificación de otro tipo no la dispara. **PASS**.

## 14. Torneo

**`SKIPPED` — integración de Torneo pendiente del contrato/servicio propietario correspondiente**, no
verificable localmente al 2026-10-01 (sin repositorio/servicio Tournament, `ADR-022` sigue
`Proposed`). No se fabricó un torneo falso presentado como E2E.

## 15. Pruebas

| Repo | Suite | Pass | Fail | Skip |
| --- | ---: | ---: | ---: | ---: |
| Catalog | unit | 507 | 0 | 0 |
| Catalog | integration | 170 | 0 | 1 (pre-existente) |
| Combat | unit | 2900 | 0 | 0 |
| Combat | integration | 190 | 0 | 0 |
| Combat | db (Mongo real) | 211 | 0 | 0 |
| Combat | e2e-hu30 (Combat+PI+Notifications reales, 3 corridas) | 15 (5×3) | 0 | 0 |
| Player-Inventory | unit | 967 | 0 | 0 |
| Player-Inventory | integration | 191 | 0 | 0 |
| Player-Inventory | db (Mongo real) | incluye `mongo-battle-drop-transfer.spec.ts` | 0 | 0 |
| Notifications | unit+integration | 419 | 0 | 0 |
| Web | vitest (unit+component) | 2928 | 0 | 0 |

## 16. Coverage

| Repo | Statements | Branches | Functions | Lines | Umbral |
| --- | ---: | ---: | ---: | ---: | ---: |
| Combat (`test:db`) | 95.04% | 82.35% | 98.18% | 95.65% | 80% |
| Notifications | 92.54% | 84.99% | 94.13% | 92.74% | — |
| Web | 90.23% | 83.81% | 86.24% | 90.42% | 80% |

## 17. Regresiones HU-28/HU-29

- **HU-29 (bloqueo de equipamiento):** su propio E2E (`test/e2e/hu-29`) sigue en el repo y no se tocó;
  `IntervalBattleDropScheduler` reutiliza exactamente el mismo mecanismo de liberación
  (`BattleHeroCommitmentPort.release`), solo diferido cuando hay drops pendientes. Verificado en el
  propio E2E de HU-30 (E-01/E-02: ambos compromisos terminan `RELEASED`).
- **HU-28 (equipar):** sin cambios de producción en Player-Inventory; `EquipItemOnHero` sigue
  rechazando equipar sobre una ranura ya ocupada exactamente igual que antes (observado como
  comportamiento real, no simulado, al construir el fixture del E2E).
- Combat: 2900 unit + 190 integration + 211 db, todas verdes, sin tocar HU-14 a HU-23.

## 18. Git

| Repo | Rama | Commit | Estado |
| --- | --- | --- | --- |
| Catalog | `feat/hu-30-drop-probability-contract` | `9b7b2fc` | limpio |
| Combat | `feat/hu-30-versus-drop-resolution` | `1c474f3` | limpio |
| Player-Inventory | `feat/hu-30-drop-settlement` | `0e817e7` | limpio |
| Notifications | `feat/hu-30-drop-notifications` | `5699546` | limpio |
| Web | `feat/hu-30-drop-inventory-feedback` | `98e32c4` | limpio |
| Infrastructure | `docs/hu-30-drop-contract-and-evidence` | (este commit) | limpio |

## 19. Pull Requests

- Catalog: [#69](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/69)
- Combat: [#66](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/66)
- Player-Inventory: [#71](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/71)
- Notifications: [#44](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/44)
- Web: [#195](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/195)

Ninguno mergeado. Ninguno con `Closes`; todos referencian `#77` y su Task correspondiente con `Refs`.

## 20. Management

**#534/#535/#536/#537/#538/#77 siguen abiertas y no se hizo merge de ninguno de los cinco PRs.**

## 21. Pendientes reales

1. **`P-HU30-TIE` (empate de probabilidad máxima) sin regla de desempate.** Ni el comentario vigente de
   `#77`, ni las Tasks, ni las tablas 8–19 del SRS, ni los contratos/ADR fijan una. Requiere decisión
   explícita de Management/PO antes de poder acreditar esos casos; mientras tanto quedan en
   `AWAITING_TIE_RULE`, sin transferir nada.
2. **Torneo.** Sin repositorio/servicio local ni integración de justas verificada
   (`ADR-022` `Proposed`). La mecánica queda reutilizable sin cambios de dominio; la integración en sí
   es responsabilidad del contrato/servicio propietario cuando exista.
3. **Revisión por pares y aceptación del PO**, como con cualquier HU — ningún documento técnico
   sustituye ese paso.

## 22. Confirmaciones

- No se inventaron requisitos: toda regla de HU-30 trazada a la HU, a la aclaración vigente de `#77`,
  a una decisión arquitectónica ya aprobada (ADR-019, HU-24, HU-29), a una necesidad técnica
  justificada (identidad por unidad, tasa canónica administrable), o declarada como pendiente
  (`P-HU30-TIE`).
- No hay cross-database: toda comunicación entre Combat y Player-Inventory es HTTP+HMAC interno.
- No se usó `Math.random` ni un RNG alternativo: el único generador es el central de HU-24.
- No hay ownership duplicado: verificado con el mismo `productInstanceId` antes/después en el E2E real.
- No se exponen secretos en el diff de ningún repositorio (verificado con patrones AKIA/ghp\_/BEGIN
  PRIVATE KEY antes de cada commit).
- No se tocó `main` en ningún repositorio.
- No se hizo merge de ningún PR.
- No se cerró ninguna Task ni la HU en Management.
- No se tocaron Missions, Wallet, Auction, Commerce, Account ni Community.
