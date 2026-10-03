# HU-31 — Evidencia de la implementación de la épica equipada

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#78](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/78)
- **Tasks:** [#539](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/539) (contrato) · [#540](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/540) (Player-Inventory) · [#541](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/541) (Combat) · [#542](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/542) (Web) · [#543](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/543) (E2E + evidencia)
- **Fecha de esta revisión:** 2026-10-02
- **Requisito trazado:** HU-31 ("Aplicación de efecto de habilidad épica según tipo de héroe", RF-31)
- **Bounded context:** Player-Inventory (ownership, selección, persistencia, proyección) · Catalog (definición canónica, sin cambios) · Combat (snapshot de batalla, congelamiento) · Web (presentación en Mi Inventario)
- **Contrato de la integración:** [`hu-31-equipped-epic-v1`](../contracts/hu-31-equipped-epic-v1.md)

## Estado a 2026-10-02

**Esta HU no partía de cero.** Las Tasks #206/#207/#208 (cerradas) y Player-Inventory PR #18
(mergeado) ya habían implementado el resolver puro `applyEpicEffects`/`computeHeroEffectsWithEpic`
(base siempre se aplica; específico solo si el subtipo del héroe coincide con
`compatibleHeroSubtype`; ambos se combinan cuando coinciden). La brecha real, confirmada por la
auditoría inicial y por los comentarios de Management#78, era la ausencia de una fuente autoritativa
de "qué épica tiene equipada un héroe" que conectara jugador → héroe → Player-Inventory → Combat.
Esa brecha es lo que esta HU cierra.

**Los tres repos de implementación (Player-Inventory, Combat, Web) están completos y verificados,
cada uno en su propio PR abierto hacia `develop`, ninguno mergeado todavía.** La verificación de
extremo a extremo entre Player-Inventory y Combat reales vive en el PR de Combat, en 6 escenarios,
**6/6 en verde**. Catalog no requirió cambios: queda de solo lectura (ver auditoría §1).

| Pieza | Repositorio / PR | SHA (head) | Estado |
| --- | --- | --- | --- |
| Contrato `hu-31-equipped-epic-v1` + esta evidencia | Infrastructure (esta rama, `docs/hu-31-equipped-epic-contract-and-evidence`) | `6265628` | **Abierta, sin mergear** |
| `HeroEpicSelection`, rutas `GET/PUT .../epic`, proyección en `equipped-hero`, fix de migración UUID | Player-Inventory [#72](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/72) | `6d346e4` | **Abierto, sin mergear** |
| Congelamiento de la épica en el snapshot de batalla, migración `020`, E2E real | Combat [#68](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/68) | `0fb88ed` | **Abierto, sin mergear** |
| `EpicManagerPanel` en Mi Inventario | Web [#198](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/198) | `0de0f2b` | **Abierto, sin mergear** |
| Catalog | — | — | **Sin cambios** (auditado, de solo lectura) |

**Este documento no declara la HU aceptada.** La aceptación de `#78` requiere que los PRs se
mergeen y la decisión explícita del equipo/PO (ver «Pendientes reales»).

## 1. Auditoría inicial (por repositorio)

| Repo | Ya existía | Faltaba | Se reutilizó |
| --- | --- | --- | --- |
| Catalog | Esquema `EpicAttributes` (`compatibleHeroSubtype`, `generalEffect?`, `specificEffect`), PR #22 (HU-33.3) | Nada que bloquee CA-01..07; brecha conocida (`specificEffect` admite un solo efecto) documentada como `P-HU31-CATALOG-MULTI-EFFECT`, no resuelta | Esquema tal cual, sin tocar |
| Player-Inventory | `HeroLoadout` (HU-28, ranuras 2/6/2), `BattleStatePort`/`EquipmentCombatLockPolicy` (HU-29), resolver `applyEpicEffects`/`computeHeroEffectsWithEpic` (PR #18), `equipped-hero` proyectado hacia Combat, bloqueo optimista por `version` | Agregado propio para la épica equipada (0/1 por héroe, fuera de las ranuras 2/6/2); rutas públicas; persistencia Mongo con validador; publicación aditiva en `equipped-hero` | Mismo patrón de `HeroLoadout`/`MongoHeroLoadoutRepository` (version + `replaceOne`); `EquipmentCombatLockPolicy` extendida con `decideEpicChange` (sin segundo mecanismo de bloqueo); resolver existente invocado tal cual, sin duplicar |
| Combat | `EquippedHero`/`CombatProfile`/`CombatProfileFactory`, snapshot congelado en `StartBattle.start()`, HU-19 (ejecución de habilidades), HU-29 (compromiso), HU-30 (drop) | Campo `epic` en el puerto/cliente HTTP y en el perfil de combate, congelado en el mismo punto que `activeEffects`/`abilities` | Mismo punto de congelamiento (`revalidate()` → `freeze()` → `combatProfileFrom()`); `StartTournamentRoom` hereda gratis vía `StartBattle.startRoom()`; migración `020` con la misma técnica genérica de `017`/`018` |
| Web | Grid de inventario y patrón de tarjeta del gestor de equipamiento (HU-28), React Query sin optimismo, `isBattleLockError` (HU-29) | Panel para seleccionar/equipar la épica | `EpicManagerPanel` hermano del gestor de equipamiento, mismos hooks/patrón de invalidación, mismo mecanismo de battle-lock, sin lógica de dominio propia |

## 2. Fuentes funcionales usadas (requisito explícito vs. decisión)

| Fuente | Contenido usado |
| --- | --- |
| Management#78 (comentarios de auditoría previos) | Confirma que el resolver ya existe y que la brecha es la fuente autoritativa de "épica equipada" |
| Player-Inventory PR #18 (mergeado) | `applyEpicEffects`/`computeHeroEffectsWithEpic`: semántica base+específico, reutilizada sin cambios |
| HU-28 (contrato de equipamiento) | `EquipmentCategory` excluye `EPICA` explícitamente → la épica no puede mezclarse con las ranuras 2/6/2 (decisión técnica, no inventada) |
| HU-29 (bloqueo de batalla) | `BattleStatePort`/`EquipmentCombatLockPolicy` existentes, extendidos sin duplicar el mecanismo |
| HU-19 (ejecución de habilidades) | Confirma que la ejecución de la épica como acción de turno sigue bloqueada por la cardinalidad de efecto único de Catalog (`P-HU31-CATALOG-MULTI-EFFECT`); HU-31 resuelve la FUENTE, no la EJECUCIÓN |
| Catalog `product-attributes.ts` (código) | Esquema `EpicAttributes` confirmado sin cambios desde PR #22 hasta `develop` actual |

## 3. Decisiones vs. pendientes

**Decisiones tomadas (con razón citada):**

1. Cardinalidad 0/1 por héroe — no hay tabla/contrato que exija más de una épica equipada simultánea; se registra como pendiente de producto, no se asume (`P-HU31-EPIC-CARDINALITY`).
2. Player-Inventory es dueño del nuevo agregado — mismo bounded context que `HeroLoadout`, mismas invariantes de ownership.
3. Catalog permanece de solo lectura — ninguna CA de HU-31 lo exige.
4. Se reutiliza `EquipmentCombatLockPolicy` (HU-29) en vez de un segundo mecanismo de bloqueo.
5. El resolver de PR #18 se invoca tal cual — no se crea `applyEpicEffectsV2`.
6. Combat no toca los 3 ficheros de ejecución de HU-19 — la ejecución de la épica como acción de turno sigue fuera de alcance.
7. HU-30 (drop) no se contamina — su canal (`battle-drops/snapshots`) nunca lee `HeroEpicSelection` ni el campo `epic` (confirmado por auditoría de código).
8. La brecha de Catalog (un solo `specificEffect`) se documenta, no se arregla — no es mandatoria para CA-01..07.
9. Web no implementa lógica de dominio — solo presenta lo que el contrato ya resuelve.

**Pendientes genuinos (no inventados, no resueltos por esta HU):**

- `P-HU31-EPIC-CARDINALITY`: si un héroe debería poder tener más de una épica equipada simultáneamente no está definido en ningún requisito o tabla oficial disponible.
- `P-HU31-CATALOG-MULTI-EFFECT`: Catalog solo admite un `specificEffect` por épica; si una épica necesitara más de un efecto específico, Catalog necesitaría un ADR/contrato nuevo.
- Ejecutar la épica como una acción de turno propia (HU-19-v2) sigue bloqueada por el punto anterior; HU-31 resuelve la fuente (qué épica está equipada y sus efectos resueltos), no la ejecución.
- No existe `unequip` explícito: ningún escenario formal lo exige; equipar una épica distinta reemplaza directamente la anterior.

## 4. Arquitectura final HU-31

```text
Jugador posee Epica (compra real, Player-Inventory)
   |
   v
PUT /api/inventories/me/heroes/:heroId/epic  -- ownership heroe+epica, HU-29 lock
   |
   v
HeroEpicSelection (agregado propio, 0/1 por heroe, version optimista)
   |
   v
GetEquippedHeroForCombat -- resuelve Catalog (definicion canonica) una vez
   |                         -- invoca applyEpicEffects/computeHeroEffectsWithEpic (PR #18, sin duplicar)
   v
equipped-hero { ..., epic?: { ...whitelist... } }  -- campo ADITIVO y OPCIONAL
   |
   v
Combat: StartBattle.start() -> revalidate() -> freeze() -> combatProfileFrom()
   |                                              (mismo punto que activeEffects/abilities)
   v
CombatProfile.epic  -- CONGELADO en el snapshot; nunca se re-consulta mid-battle
   |
   +--> StartTournamentRoom.startRoom() hereda gratis, cero codigo especifico de Tournament
   |
   v
(Ejecucion de la epica como accion de turno: BLOQUEADA, ver P-HU31-CATALOG-MULTI-EFFECT)
```

Catalog nunca se consulta desde Combat; Combat nunca vuelve a consultar Player-Inventory ni Catalog
dentro de una batalla ya iniciada.

## 5. Cambios por repositorio

### Player-Inventory (PR [#72](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/72))

- `HeroEpicSelection` (dominio), `HeroEpicSelectionRepositoryPort`, `MongoHeroEpicSelectionRepository` +
  migración `016-hero-epic-selections` (validador `$jsonSchema`, bloqueo optimista por `version`).
- `EquipEpicOnHero`/`GetHeroEpic` (casos de uso), `hero-epic.controller.ts` (`GET/PUT
  /api/inventories/me/heroes/:heroId/epic`).
- `EquipmentCombatLockPolicy.decideEpicChange` (extensión, no duplicación del mecanismo de HU-29).
- `GetEquippedHeroForCombat` extendido: resuelve y publica `epic?` en `equipped-hero` de forma
  aditiva y opcional.
- Fix real de producción: migración `016` solo aceptaba `epicItemId` en kebab-case; una compra real
  guarda el `productId` (UUID) como `itemId`. Mismo patrón de bug ya corregido históricamente en
  `006-hero-loadouts-uuid-itemid.ts`. Descubierto por el E2E real de Combat (ver §7).

### Catalog

- Sin cambios. Auditado: el esquema `EpicAttributes` no requiere modificación para CA-01..07.
  Brecha documentada (`P-HU31-CATALOG-MULTI-EFFECT`), no resuelta en esta HU.

### Combat (PR [#68](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/68))

- `PlayerInventoryEquippedHeroPort`/`PlayerInventoryHttpClient`: campo `epic?` parseado con lista
  blanca.
- `CombatProfile`/`CombatProfileFactory`: `epic?` congelado en el mismo punto que `activeEffects`.
- Migración `020-battle-rooms-epic` (técnica genérica de `017`/`018`, aditiva).
- Guard estático de HU-19 (`hu-19-skills-guards.spec.ts`) acotado, no removido: sigue protegiendo
  los 3 ficheros de ejecución; documentado en `docs/hu-19-skills.md`.
- E2E real HU-31 (`test/e2e/hu-31/equipped-epic.e2e.spec.ts`, `npm run test:e2e:hu-31`, fuera de CI).

### Web (PR [#198](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/198))

- `EpicManagerPanel` (+ `epicApi.ts`/`useHeroEpic.ts`, ubicados dentro de `equipment/` por la regla
  `no-restricted-imports` del repo) integrado en `HeroConfigurator`/`PlayerInventoryPage`.
- Sin lógica de dominio: solo presenta `baseApplied`/`additionalApplied` ya resueltos.
- Sin asset PixelLab nuevo (auditado: "Mi Inventario" no tiene paquete de rediseño aprobado todavía;
  se reutiliza `ProductThumb` y el glifo visual `epic` ya existente).
- i18n: `es`/`en`/`fr`/`pt`.

## 6. Resultado de los criterios de aceptación (CA-01..07, contrato §9)

| CA | Escenario | Resultado |
| --- | --- | --- |
| CA-01 | Jugador equipa una épica que posee en un héroe propio | PASS — Player-Inventory unit+db, E2E-01/03 |
| CA-02 | Rechazo si no posee la épica o el héroe (404, sin filtrar datos de otro jugador) | PASS — Player-Inventory unit, E2E-04 (ownership real, 404) |
| CA-03 | Subtipo coincide → efecto base + específico combinados | PASS — resolver PR #18 (reutilizado), `start-battle-combat-snapshot.spec.ts`, E2E (snapshot con match) |
| CA-04 | Subtipo no coincide → solo efecto base (o "No aplica" si `generalEffect` es `null`) | PASS — mismos suites, escenario T-C-03 / E2E (snapshot sin match) |
| CA-05 | Selección persiste entre peticiones/reinicio | PASS — Player-Inventory `test:db` (Mongo real, Testcontainers) |
| CA-06 | Mutación rechazada mientras el héroe tiene un compromiso de batalla activo (HU-29), permitida tras finalizar | PASS — Player-Inventory unit (battle-lock), E2E-05 (409 real durante batalla real, reintento exitoso tras finalizar) |
| CA-07 | Snapshot de batalla congela la épica al inicio; un cambio externo posterior no la afecta | PASS — Combat `start-battle-combat-snapshot.spec.ts`, E2E (snapshot inmutable) |

## 7. E2E real (HU-31.8)

`Combat/test/e2e/hu-31/equipped-epic.e2e.spec.ts`, ejecutado con `npm run test:e2e:hu-31` (fuera de
CI, mismo patrón ya establecido por `hu-29`/`hu-30`). Componentes:

- **Reales:** Player-Inventory completo en un proceso Node separado (`npm run build` + `node
  dist/main.js`), con su propio MongoDB real (Testcontainers); Combat (proceso de este mismo test),
  con su propio MongoDB real; autenticación interna HMAC-SHA256 real
  (`signInternalRequest`/cabeceras `INTERNAL_SERVICE_HEADER`/`INTERNAL_TIMESTAMP_HEADER`/
  `INTERNAL_SIGNATURE_HEADER`); `BattleHeroCommitmentPort` real sobre HTTP real.
- **Doblados (declarados explícitamente en el encabezado del fichero):** Catalog (HTTP doble
  mínimo en el propio proceso, mismo patrón que `hu-29`/`hu-30`); `PLAYER_INVENTORY_EQUIPPED_HERO`
  (doblado y sincronizado manualmente tras cada `PUT` real contra Player-Inventory, convención ya
  establecida en los dos precedentes); `BATTLE_DROP_INVENTORY`/`BATTLE_DROP_NOTIFIER` (stubs
  triviales — HU-30 no es el objeto de esta prueba y no debe fallar por su causa).

| Escenario | Descripción | Resultado |
| --- | --- | --- |
| E2E-04 | Ownership real: equipar una épica que el jugador no posee → 404 real, sin datos de otro jugador | PASS |
| E2E-01/03 | Equipar una épica real propia, persistir en Mongo real, releer y confirmar selección | PASS |
| E2E-07 (PvE) / T-C-01 | `StartBattle` real, `BattleHeroCommitment` real, snapshot persistido congela base+específico (subtipo coincidente) | PASS |
| E2E-05 | Mutación de épica durante batalla real activa → 409 `battle_lock` real | PASS |
| E2E-05 (cont.) | Batalla real finaliza → compromiso se libera → reintento de mutación exitoso | PASS |
| T-C-03 | Segunda batalla real con subtipo no coincidente → snapshot solo con efecto base | PASS |

**Resultado final: 6/6 escenarios en verde** (confirmado en la corrida final, tras el fix de la
migración `016` descrito en §5).

## 8. Resultados de pruebas y cobertura por repositorio

| Repo | Suite | Resultado | Cobertura (stmts/branch/func/line) |
| --- | --- | --- | --- |
| Player-Inventory | unit+integration (`test:coverage`) | 1227/1227 | 89.77% / 81.29% / 88.08% / 89.62% |
| Player-Inventory | db (Testcontainers) | 132/132 | 92.67% / 83.21% / 97.67% / 93.95% |
| Combat | unit (`test:coverage`) | 2968/2968 | verde (umbral 80%) |
| Combat | db (Testcontainers) | 220/220 | — |
| Combat | e2e (`test:e2e:hu-31`, manual, fuera de CI) | 6/6 | — |
| Web | suite completa | 2973/2973 | verde (umbral del proyecto) |
| Catalog | — (sin cambios) | no aplica | no aplica |

Todos los repos: `lint`/`format:check`/`typecheck`/`build` en verde. Ningún umbral de cobertura fue
bajado ni se excluyó código nuevo de la medición para pasar CI.

## 9. Regresión y no-contaminación confirmadas

- **HU-29 (bloqueo de equipamiento en batalla):** sigue funcionando sin cambios; `decideEpicChange`
  es una función hermana de `decideEquipmentChange`, mismo `BATTLE_LOCK_MESSAGE`, mismo
  `BattleStatePort`. Verificado por unit (Player-Inventory) y E2E-05 real (Combat).
- **HU-30 (drop por derrota en Versus):** confirmado por auditoría de código que
  `battle-drops/snapshots` se construye exclusivamente desde `HeroLoadout` (ARMA/ARMADURA/ITEM) y
  nunca lee `HeroEpicSelection` ni `CombatProfile.epic`. La épica **no** es candidata a drop.
- **Tournament:** cero código específico de HU-31 en Tournament. `StartTournamentRoom` reutiliza
  `StartBattle.startRoom()` sin modificación; hereda el congelamiento de la épica "gratis".
- **HU-19 (ejecución de habilidades):** el guard estático que impedía mezclar conceptos de épica en
  los ficheros de ejecución se acotó (no se removió) para seguir protegiendo exactamente
  `UseSkill`/`SkillEffectPolicy`/`SkillRealtimeHandler`; ninguno de los tres lee
  `CombatProfile.epic`.
- **Missions y demás consumidores de `equipped-hero`:** el campo `epic` es aditivo y opcional;
  ningún consumidor existente fue auditado como roto por su presencia (el campo se omite si no hay
  épica equipada, igual que antes de esta HU).

## 10. Seguridad y ownership

- El `playerId` nunca viaja desde el cliente: se deriva de `VerifiedIdentity.subject` en el JWT
  público, igual que el resto de rutas de Player-Inventory.
- `EquipEpicOnHero` verifica ownership real de la épica (vía inventario del jugador) y del héroe
  antes de persistir cualquier cambio; el rechazo (404) no filtra si la épica existe para otro
  jugador.
- Combat solo recibe un DTO en lista blanca (`CombatEpic`: sin metadata administrativa, sin precio,
  sin datos crudos de Catalog) — construido explícitamente por `parseEpic`/`validateEpic`.
- Comunicación interna Player-Inventory↔Combat firmada con HMAC real en el E2E, allow-list de
  llamador, fail-closed.

## 11. Estado de Management

`#539`, `#540`, `#541`, `#542`, `#543` y `#78` permanecen **OPEN**. Ningún PR fue mergeado. Ninguna
rama se tocó en `main`. Ningún issue de Management fue cerrado por este trabajo.

## 12. Pendientes reales (no inventados)

- `P-HU31-EPIC-CARDINALITY`: confirmar con producto si un héroe puede tener más de una épica
  equipada.
- `P-HU31-CATALOG-MULTI-EFFECT`: si una épica necesitara más de un `specificEffect`, Catalog
  requiere un ADR/contrato nuevo (fuera de alcance de HU-31).
- Ejecución de la épica como acción de turno propia (HU-19-v2): sigue bloqueada por el punto
  anterior.
- `unequip` explícito: no implementado; ningún escenario formal lo exige todavía.
- Gap operativo no relacionado con HU-31, descubierto durante el debugging del E2E: Player-Inventory
  arranca con `NestFactory.create(AppModule, { logger: false })`, silenciando todo log de
  excepciones no traducidas del framework. Reportado por separado como tarea sugerida
  (`task_0e39714d`), no corregido aquí por estar fuera de alcance de HU-31.

## 13. Reproducibilidad

```bash
# Player-Inventory
cd Nexus-Battle-Player-Inventory && npm run test:coverage && npm run test:db

# Combat
cd Nexus-Battle-Combat && npm run test:coverage && npm run test:db
# E2E real (requiere Nexus-Battle-Player-Inventory como hermano en disco, o
# PLAYER_INVENTORY_REPO_PATH apuntando a su checkout):
npm run test:e2e:hu-31

# Web
cd Nexus-Battle-Web && npm test && npm run build
```

## 14. Confirmaciones explícitas

- No se inventó ningún requisito no respaldado por Management#78, el SRS o el código auditado.
- No se duplicó el resolver `applyEpicEffects`/`computeHeroEffectsWithEpic` (PR #18).
- No se creó una segunda fuente de verdad para "qué épica está equipada": Player-Inventory es la
  única.
- No se mezcló la épica con las ranuras 2/6/2 de HU-28 (`EquipmentCategory` sigue sin `EPICA`).
- No se implementó lógica de dominio de HU-31 en Web ni en Tournament.
- No se filtraron secretos, tokens ni metadata administrativa de Catalog hacia Combat o Web.
- No se trabajó sobre `main` en ningún repositorio.
- No se hizo merge de ningún PR.
- No se cerró ningún issue de Management.
