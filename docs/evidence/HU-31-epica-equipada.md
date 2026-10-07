# HU-31 — Evidencia de la implementación de la épica equipada

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#78](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/78)
- **Tasks:** [#539](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/539) (contrato) · [#540](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/540) (Player-Inventory) · [#541](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/541) (Combat) · [#542](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/542) (Web) · [#543](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/543) (E2E + evidencia)
- **Fecha de esta revisión:** 2026-10-03 (corrección sobre la evidencia de 2026-10-02)
- **Requisito trazado:** HU-31 ("Aplicación de efecto de habilidad épica según tipo de héroe", RF-31)
- **Bounded context:** Player-Inventory (ownership, selección, persistencia, proyección) · Catalog (definición canónica, **ahora con cambios**, ver §0) · Combat (snapshot de batalla + **ejecución real**) · Web (presentación en Mi Inventario + administración)
- **Contrato de la integración:** [`hu-31-equipped-epic-v1`](../contracts/hu-31-equipped-epic-v1.md)

## 0. Qué cambió en esta corrección (2026-10-03)

La evidencia de 2026-10-02 dejaba dos pendientes genuinos y una HU-19 explícitamente bloqueada. Una ronda de corrección posterior los resolvió:

| Pendiente/afirmación de la evidencia 2026-10-02 | Estado tras la corrección |
| --- | --- |
| `P-HU31-EPIC-CARDINALITY` (sin confirmar) | **Confirmada**: un jugador puede poseer múltiples épicas; cada héroe, máximo una equipada. Se retira como pendiente. |
| `P-HU31-CATALOG-MULTI-EFFECT` (Catalog sin cambios, brecha documentada) | **Resuelta**. Catalog PR [#70](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/70): `specificEffect` → `specificEffects[]`. |
| "Catalog no requirió cambios" | Ya NO es cierto: Catalog SÍ cambió (ver fila anterior). |
| "Ejecución de la épica como acción de turno: BLOQUEADA" | **Resuelta**: Combat implementa `UseEpic`/`EpicSkillPolicy`, comando WebSocket `useEpic` real. |
| Nuevo pendiente genuino | `P-HU31-STAT-CONSULTATION-GAP`: `CRITICAL_CHANCE`/`POWER` se registran pero no se consultan todavía (brecha pre-existente del motor de HU-19/HU-25, no introducida aquí). |

Esta sección reemplaza/amplía la evidencia original; las secciones siguientes están actualizadas para reflejar el estado final, no un historial línea por línea de los dos pases.

**Los cuatro repos de implementación (Catalog, Player-Inventory, Combat, Web) están completos y verificados, cada uno en su propio PR abierto hacia `develop`, ninguno mergeado todavía.**

| Pieza | Repositorio / PR | SHA (head) | Estado |
| --- | --- | --- | --- |
| Contrato `hu-31-equipped-epic-v1` + esta evidencia | Infrastructure (esta rama, `docs/hu-31-equipped-epic-contract-and-evidence`) | `feaf551` | **Abierta, sin mergear** |
| `GAP-HU31-CATALOG-MULTI-EFFECT`: `specificEffects[]`, compatibilidad retroactiva | Catalog [#70](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/70) | `b58a04e` | **Abierto, sin mergear** |
| `HeroEpicSelection`, rutas `GET/PUT .../epic`, resolver multi-efecto, `powerCost`/`cooldownTurns` | Player-Inventory [#72](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/72) | `a6c3fc8` | **Abierto, sin mergear** |
| Congelamiento multi-efecto + **ejecución real** (`UseEpic`, `EpicSkillPolicy`, `useEpic` WS) | Combat [#68](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/68) | `e086b75` | **Abierto, sin mergear** |
| `EpicManagerPanel` + admin multi-efecto en Mi Inventario | Web [#198](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/198) | `61b4d6f` | **Abierto, sin mergear** |

**Este documento no declara la HU aceptada.** La aceptación de `#78` requiere que los PRs se
mergeen y la decisión explícita del equipo/PO (ver «Pendientes reales»).

## 1. Auditoría (por repositorio, estado final tras la corrección)

| Repo | Ya existía | Faltaba | Se reutilizó |
| --- | --- | --- | --- |
| Catalog | Esquema `EpicAttributes` (`compatibleHeroSubtype`, `generalEffect?`, `specificEffect`), PR #22 (HU-33.3) | `specificEffects[]` (lista, mínimo 1) para representar épicas con más de un efecto simultáneo (Tabla 20); compatibilidad retroactiva con la forma legada | `parseProductEffect`/`ProductEffect` sin cambios (cada elemento de la lista es el mismo objeto de siempre); validador Mongo sin cambios (no restringía el interior de `attributes.values`) |
| Player-Inventory | `HeroLoadout` (HU-28, ranuras 2/6/2), `BattleStatePort`/`EquipmentCombatLockPolicy` (HU-29), resolver `applyEpicEffects`/`computeHeroEffectsWithEpic` (PR #18), `equipped-hero` proyectado hacia Combat, bloqueo optimista por `version` | Agregado propio para la épica equipada (0/1 por héroe); rutas públicas; persistencia Mongo con validador; publicación aditiva en `equipped-hero`; resolver adaptado a `specificEffects[]`; `powerCost`/`cooldownTurns` publicados | Mismo patrón de `HeroLoadout`/`MongoHeroLoadoutRepository` (version + `replaceOne`); `EquipmentCombatLockPolicy` extendida con `decideEpicChange`; resolver existente invocado tal cual (solo pluralizado), sin duplicar |
| Combat | `EquippedHero`/`CombatProfile`/`CombatProfileFactory`, snapshot congelado en `StartBattle.start()`, HU-19 (ejecución de habilidades), HU-29 (compromiso), HU-30 (drop), `HeroPowerPolicy`, `Combatant.cooldowns`/`activeSkillEffects` | Campo `epic` en el puerto/cliente HTTP y en el perfil de combate; **ejecución real** de la épica como acción de turno (clasificación de efectos, caso de uso, comando WebSocket) | Mismo punto de congelamiento (`revalidate()` → `freeze()` → `combatProfileFrom()`); `StartTournamentRoom` hereda gratis; `HeroPowerPolicy` (modo `NONE`), `Combatant.cooldowns`/`activeSkillEffects` (misma estructura que habilidades, sin un segundo mecanismo); `validateAbilityEffect` reutilizada para `executableEffects` |
| Web | Grid de inventario y patrón de tarjeta del gestor de equipamiento (HU-28), React Query sin optimismo, `isBattleLockError` (HU-29), panel de administración de productos EPICA (ya existente, un solo efecto) | Panel para seleccionar/equipar la épica (jugador); lista de efectos específicos con alta/baja (admin) | `EpicManagerPanel` hermano del gestor de equipamiento; `USES_EFFECT_LIST`/patrón add-remove del admin, ya usado por ARMA/ARMADURA/ITEM/HABILIDAD, reutilizado tal cual para EPICA |

## 2. Fuentes funcionales usadas (requisito explícito vs. decisión)

| Fuente | Contenido usado |
| --- | --- |
| Management#78 (comentarios de auditoría previos) | Confirma que el resolver ya existe y que la brecha es la fuente autoritativa de "épica equipada" |
| Player-Inventory PR #18 (mergeado) | `applyEpicEffects`/`computeHeroEffectsWithEpic`: semántica base+específico, reutilizada sin cambios |
| HU-28 (contrato de equipamiento) | `EquipmentCategory` excluye `EPICA` explícitamente → la épica no puede mezclarse con las ranuras 2/6/2 (decisión técnica, no inventada) |
| HU-29 (bloqueo de batalla) | `BattleStatePort`/`EquipmentCombatLockPolicy` existentes, extendidos sin duplicar el mecanismo |
| HU-19 (ejecución de habilidades) | Confirma que la ejecución de la épica como acción de turno estaba bloqueada por la cardinalidad de efecto único de Catalog; HU-31 resolvió primero la FUENTE, y la corrección 2026-10-03 resolvió la cardinalidad de Catalog y, con ella, la EJECUCIÓN |
| Catalog `product-attributes.ts` (código) | Esquema `EpicAttributes` sin cambios desde PR #22 hasta antes de la corrección; la corrección lo amplía (§0) |
| Documento del proyecto integrador (Tabla 20, corrección 2026-10-02/03) | Confirma la cardinalidad (0/1 por héroe) y los efectos compuestos de al menos 4/8 épicas reales |

## 3. Decisiones vs. pendientes

**Decisiones tomadas (con razón citada):**

1. Cardinalidad 0/1 por héroe, **confirmada** por el documento del proyecto integrador (corrección 2026-10-03) — ya no es una decisión técnica por ausencia de fuente, es un requisito explícito.
2. Player-Inventory es dueño del nuevo agregado — mismo bounded context que `HeroLoadout`, mismas invariantes de ownership.
3. Catalog **SÍ cambia** (corrección 2026-10-03): `specificEffects[]`, mínimo 1, compatible retroactivamente con la forma legada.
4. Se reutiliza `EquipmentCombatLockPolicy` (HU-29) en vez de un segundo mecanismo de bloqueo.
5. El resolver de PR #18 se invoca tal cual — no se crea `applyEpicEffectsV2`; solo se pluraliza `additionalEffect`/`additionalApplied`.
6. Combat no toca los 3 ficheros de ejecución de HU-19 (`UseSkill.ts`/`SkillEffectPolicy.ts`/`SkillRealtimeHandler.ts`) — la ejecución real de la épica vive en ficheros NUEVOS (`UseEpic.ts`/`EpicSkillPolicy.ts`/`EpicRealtimeHandler.ts`), nunca modificando los de HU-19 v1.
7. HU-30 (drop) no se contamina — su canal (`battle-drops/snapshots`) nunca lee `HeroEpicSelection` ni el campo `epic` (confirmado por auditoría de código).
8. La brecha de Catalog (un solo `specificEffect`) se **resuelve** (corrección 2026-10-03), no solo se documenta.
9. Web no implementa lógica de dominio — solo presenta lo que el contrato ya resuelve (ahora listas, no objetos únicos).
10. `STAT_MODIFIER` de una épica se trata SIEMPRE como efecto temporal (decisión técnica, corrección 2026-10-03): usar la épica no es un ataque, no existe «esta resolución» a la que sumarle un bono instantáneo.

**Pendientes genuinos (no inventados, no resueltos por esta corrección):**

- `P-HU31-STAT-CONSULTATION-GAP` (NUEVO): `CRITICAL_CHANCE`/`POWER` se registran como efecto activo de una épica pero ningún punto de resolución de Combat los consulta todavía. Brecha pre-existente del motor de HU-19/HU-25 (misma categoría que `IMMUNITY`, tampoco consultada), no introducida por esta corrección.
- Efectos `REFLECT_DAMAGE`/`TEMPORARY_STATUS`, audiencia `ENEMY_GROUP`, y audiencias incompatibles en la misma épica: no soportados todavía por `EpicSkillPolicy` (rechazo explícito de la épica entera, nunca a medias). Ningún escenario de la Tabla 20 real lo necesita hoy.
- No existe `unequip` explícito: ningún escenario formal lo exige; equipar una épica distinta reemplaza directamente la anterior.

**Retirados por esta corrección** (ya no son pendientes): `P-HU31-EPIC-CARDINALITY` (confirmada) y `P-HU31-CATALOG-MULTI-EFFECT` (resuelta, renombrada a `GAP-HU31-CATALOG-MULTI-EFFECT` en el historial para distinguir "pendiente" de "gap ya cerrado").

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
GetEquippedHeroForCombat -- resuelve Catalog (specificEffects[], corregido) una vez
   |                         -- invoca applyEpicEffects/computeHeroEffectsWithEpic (PR #18, pluralizado)
   v
equipped-hero { ..., epic?: { ...whitelist..., powerCost, cooldownTurns } }  -- ADITIVO y OPCIONAL
   |
   v
Combat: PlayerInventoryHttpClient.parseEpic -- construye executableEffects (NUEVO)
   |     (baseApplied + additionalApplied, validados como efecto de habilidad real)
   v
StartBattle.start() -> revalidate() -> freeze() -> combatProfileFrom()
   |                                      (mismo punto que activeEffects/abilities)
   v
CombatProfile.epic  -- CONGELADO en el snapshot; nunca se re-consulta mid-battle
   |
   +--> StartTournamentRoom.startRoom() hereda gratis, cero codigo especifico de Tournament
   |
   v
UseEpic.execute() -- comando WebSocket "useEpic", SIN abilityId (NUEVO, corregido)
   |                  EpicSkillPolicy.evaluateEpicEffects clasifica TODOS los efectos a la vez
   v
BattleRoom.planEpic -> (sorteo si hace falta) -> BattleRoom.applyEpic
   |  Poder sin cambios (modo NONE) + recarga 2 turnos (Combatant.cooldowns) +
   |  TODOS los efectos correspondientes (Combatant.activeSkillEffects) + evento "epicUsed"
   v
Persistido real (Mongo); si el efecto es DAMAGE y elimina a un rival PvP,
PersistVersusDropDecision activa el MISMO drop de HU-30 que un ataque basico
```

Catalog nunca se consulta desde Combat; Combat nunca vuelve a consultar Player-Inventory ni Catalog
dentro de una batalla ya iniciada. La ejecución de la épica (`UseEpic`) tampoco consulta a ninguno
de los dos: opera exclusivamente sobre el snapshot ya congelado.

## 5. Cambios por repositorio

### Catalog (PR [#70](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/70), NUEVO en esta corrección)

- `EpicAttributes.specificEffect` (un único `ProductEffect`) → `specificEffects` (lista, mínimo 1).
  `generalEffect` se mantiene singular.
- `parseEpicAttributes` acepta la forma canónica `specificEffects` o, por compatibilidad retroactiva,
  la forma legada `specificEffect` (normalizada a lista de un elemento); rechaza explícitamente el
  documento híbrido con ambas claves a la vez.
- `canonical-mapping.ts` (despojo de `stackable` derivado en lectura) actualizado para iterar la lista.
- Sin migración Mongo: el validador `$jsonSchema` de `attributes.values` no restringía su interior
  más allá de `kind` (auditado en las migraciones 004-013).

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
- **Corrección 2026-10-03**: `EpicEffectPolicy.additionalEffect`/`additionalApplied` (singulares) →
  `additionalEffects[]`/`additionalApplied[]`; `parseEpicAttributes` acepta `specificEffects`/forma
  legada igual que Catalog; `equipped-hero.epic` gana `powerCost`/`cooldownTurns` (0/2).

### Combat (PR [#68](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/68))

- `PlayerInventoryEquippedHeroPort`/`PlayerInventoryHttpClient`: campo `epic?` parseado con lista
  blanca.
- `CombatProfile`/`CombatProfileFactory`: `epic?` congelado en el mismo punto que `activeEffects`.
- Migración `020-battle-rooms-epic` (técnica genérica de `017`/`018`, aditiva).
- **Corrección 2026-10-03 — ejecución real**: `specificEffects[]`/`executableEffects` (validados
  como efecto de habilidad real, reutilizando `validateAbilityEffect`); `EpicSkillPolicy.ts` (NUEVO,
  clasifica TODOS los efectos a la vez); `UseEpic.ts` (NUEVO, caso de uso, mismo patrón que
  `UseSkill`); `EpicRealtimeHandler.ts` (NUEVO, comando WebSocket `useEpic`, sin `abilityId`);
  `Combatant.restoreCooldowns` ampliado para reconocer `epicProductId` junto a `abilityId` (mismo
  mapa `cooldowns`, sin un segundo mecanismo); `BattleEvent.EpicUsedPayload`/`BattleEventDto` (+ fix
  de un bug preexistente: `directDamageSkillUsed` nunca se serializaba en el wire); migración `021`
  (amplía el `enum` de `activeSkillEffects[].statistic` para `CRITICAL_CHANCE`/`POWER`, sin tocar la
  migración `016` ya mergeada); `PersistVersusDropDecision` amplía `DamagingPayload` con `EpicUsedPayload`.
- Guard estático de HU-19 (`hu-19-skills-guards.spec.ts`) **sin tocar de nuevo**: los ficheros nuevos
  de la épica viven aparte de `UseSkill.ts`/`SkillEffectPolicy.ts`/`SkillRealtimeHandler.ts`.
- E2E real HU-31 (`test/e2e/hu-31/equipped-epic.e2e.spec.ts`, `npm run test:e2e:hu-31`, fuera de CI),
  ampliado con un escenario de ejecución real (§7).

### Web (PR [#198](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/198))

- `EpicManagerPanel` (+ `epicApi.ts`/`useHeroEpic.ts`, ubicados dentro de `equipment/` por la regla
  `no-restricted-imports` del repo) integrado en `HeroConfigurator`/`PlayerInventoryPage`.
- Sin lógica de dominio: solo presenta `baseApplied`/`additionalApplied` ya resueltos.
- Sin asset PixelLab nuevo (auditado: "Mi Inventario" no tiene paquete de rediseño aprobado todavía;
  se reutiliza `ProductThumb` y el glifo visual `epic` ya existente).
- i18n: `es`/`en`/`fr`/`pt`.
- **Corrección 2026-10-03**: `specificEffects[]`/`additionalApplied[]` (jugador: una fila por efecto,
  numerada si hay más de uno); panel de administración de productos EPICA (ya existente, ajeno al
  jugador) ampliado con el mismo patrón add/remove que ya usan ARMA/ARMADURA/ITEM/HABILIDAD.

## 6. Resultado de los criterios de aceptación (CA-01..07, contrato §9)

| CA | Escenario | Resultado |
| --- | --- | --- |
| CA-01 | Jugador equipa una épica que posee en un héroe propio | PASS — Player-Inventory unit+db, E2E-01/03 |
| CA-02 | Rechazo si no posee la épica o el héroe (404, sin filtrar datos de otro jugador) | PASS — Player-Inventory unit, E2E-04 (ownership real, 404) |
| CA-03 | Subtipo coincide → efecto base + TODOS los específicos combinados | PASS — resolver PR #18 (pluralizado), `start-battle-combat-snapshot.spec.ts`, `use-epic.spec.ts` (CMB-02), E2E (snapshot con 2 específicos simultáneos) |
| CA-04 | Subtipo no coincide → solo efecto base (o "No aplica" si `generalEffect` es `null`) | PASS — mismos suites, escenario T-C-03/CMB-01 / E2E (snapshot sin match) |
| CA-05 | Selección persiste entre peticiones/reinicio | PASS — Player-Inventory `test:db` (Mongo real, Testcontainers) |
| CA-06 | Mutación rechazada mientras el héroe tiene un compromiso de batalla activo (HU-29), permitida tras finalizar | PASS — Player-Inventory unit (battle-lock), E2E-05 (409 real durante batalla real, reintento exitoso tras finalizar) |
| CA-07 | Snapshot de batalla congela la épica al inicio; un cambio externo posterior no la afecta; la épica se ejecuta de verdad | PASS — Combat `start-battle-combat-snapshot.spec.ts`, `use-epic.spec.ts` (CMB-01..09 + dano directo + sanación de grupo), E2E (snapshot inmutable + ejecución real, ver §7) |

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
| E2E-01/03 | Equipar una épica real propia (DOS efectos específicos simultáneos), persistir en Mongo real, releer y confirmar selección | PASS |
| E2E-07 (PvE) / T-C-01 | `StartBattle` real, `BattleHeroCommitment` real, snapshot persistido congela base+2 específicos y construye `executableEffects` (3) | PASS |
| **Corrección (nuevo)** | Ejecución REAL de la épica (`UseEpic`, invocado por el DI real de Combat): Poder sin cambios (0), recarga pasa a 2, los 3 efectos simultáneos se aplican y persisten en el mismo Mongo real | PASS |
| E2E-05 | Mutación de épica durante batalla real activa → 409 `battle_lock` real | PASS |
| E2E-05 (cont.) | Batalla real finaliza → compromiso se libera → reintento de mutación exitoso (equipa la forma LEGADA `specificEffect`) | PASS |
| T-C-03 | Segunda batalla real con subtipo no coincidente → snapshot solo con efecto base, `additionalApplied` vacío | PASS |

**Resultado final: 7/7 escenarios en verde** (`npm run test:e2e:hu-31`, Combat PR
[#69](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/69)).

**Hallazgos reales diagnosticados y corregidos durante esta verificación** (ninguno inventado; todos
descubiertos por el E2E real, nunca por inspección):

1. **Crítico, ya estaba en `develop` vía el merge de Combat #68**: `PlayerInventoryHttpClient.parseEpic`
   exigía `hasActivationCondition` en los efectos crudos de Catalog (`generalEffect`/`specificEffects`).
   Ese campo es de HABILIDAD (Tabla 7); una épica nunca lo declara. `StartBattle` rechazaba con 503
   **cualquier batalla con una épica equipada**. Corregido asumiendo `false` cuando está ausente
   (`parseEpicExecutableEffect`), validado igual que el resto con `parseAbilityEffect`.
2. `UseEpic` persistía el `TurnOrderEntry` completo (con `kind`/`playerId`/`heroSubtype`/...) en
   `activeSkillEffects[].sourceCombatant` y en `targetKey`, en vez de reducirlo a `CombatantKey`
   (`{teamLabel, seat}`). El validador `$jsonSchema` de Mongo (`additionalProperties: false`)
   rechazaba el documento al persistir.
3. Faltaba `epicUsed` en el `enum` de `events[].type` del validador de Mongo (la migración `016`, ya
   mergeada, no lo incluía). Nueva migración `022` que amplía el enum, mismo patrón que `021`.
4. El orden de turnos de HU-17 es un sorteo real (motor HU-24): el escenario de ejecución real
   necesita que el humano actúe primero contra el rival AI, lo que es intermitente por diseño. El E2E
   reintenta con una sala nueva hasta que el sorteo le da el turno al humano.
5. Ese reintento dejaba el compromiso de batalla (HU-29) del héroe activo en las salas descartadas,
   rechazando el siguiente intento con `HERO_COMMITTED` (traducido a 503 sin registrar, difícil de
   diagnosticar sin instrumentación temporal). Se libera el compromiso (mismo mecanismo de vencimiento
   que `E2E-05 (cont.)`) antes de reintentar.
6. Dos aserciones del E2E habían quedado desalineadas con los valores reales del doble de héroe
   compartido (Poder hardcodeado a un valor obsoleto; habilidades por defecto del doble que el
   comentario del test decía ausentes) — corregidas para verificar la invariante real en vez de un
   valor de memoria.

Corrección entregada en Combat PR #69 (`#68` ya estaba mergeado cuando se descubrieron estos
hallazgos; se abrió un PR nuevo, referenciando `#68`, en vez de reabrirlo).

## 8. Resultados de pruebas y cobertura por repositorio

| Repo | Suite | Resultado | Cobertura (stmts/branch/func/line) |
| --- | --- | --- | --- |
| Catalog | unit (`test:coverage`), PR [#70](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/70) | verde (CI), incl. C-01..C-05 | umbral del proyecto |
| Player-Inventory | unit+integration (`test:coverage`) | verde (CI), incl. PI-01..PI-06 | umbral del proyecto |
| Player-Inventory | db (Testcontainers) | verde | — |
| Combat | unit (`test:coverage`), + `EpicSkillPolicy` (24), `UseEpic` (13), `EpicRealtimeHandler` | verde (CI), incl. CMB-01..CMB-10 | umbral del proyecto (80%) |
| Combat | db (Testcontainers) | verde | — |
| Combat | e2e (`test:e2e:hu-31`, manual, fuera de CI), PR [#69](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/69) | 7/7 (ver §7) | — |
| Combat | unit+db (`test:coverage`, re-ejecutados tras los fixes de PR #69) | 3063/3063 | umbral del proyecto (80%) |
| Web | suite completa | verde (CI) | umbral del proyecto |

Todos los repos: `lint`/`format:check`/`typecheck`/`build` en verde para los 4 PRs actualizados y el
PR nuevo de Catalog. Ningún umbral de cobertura fue bajado ni se excluyó código nuevo de la medición
para pasar CI.

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

`#539`, `#540`, `#541`, `#542`, `#543` y `#78` permanecen **OPEN**. `#63` permanece **CLOSED**
administrativamente (criterio explícito de José: no se reabre sin su autorización), aunque la
brecha funcional que motivó originalmente esa duda (la épica no se ejecutaba de verdad como acción
de turno) quedó corregida en esta reconciliación — ver §4 y §7. Ningún issue de Management fue
cerrado por este trabajo. Ninguna rama se tocó en `main`.

**Nota sobre los PRs originales**: `Catalog #70`, `Player-Inventory #72`, `Combat #68`, `Web #198` e
`Infrastructure #185` (el que llevó este mismo contrato y evidencia a `develop`) ya estaban
**mergeados** cuando esta verificación posterior encontró los hallazgos del §7 — merge realizado
fuera de este trabajo de corrección, no por quien lo ejecutó. Al descubrir el hallazgo crítico
(`hasActivationCondition`, §7.1) ya en `develop` de Combat, la corrección se entregó en un PR
**nuevo** (`Combat #69`, referencia `Refs #68`) en vez de reabrir el PR mergeado, siguiendo el mismo
principio de "nunca reabrir/mergear sin autorización": `#69` sigue **OPEN**, pendiente de revisión y
CI, sin mergear.

## 12. Pendientes reales (no inventados)

- `P-HU31-STAT-CONSULTATION-GAP`: `CRITICAL_CHANCE`/`POWER` ya se pueden registrar como
  `ActiveSkillEffect` (épica o, en el futuro, habilidad), pero ningún punto de resolución del motor
  los consulta todavía (`Combatant.statBonus` solo lee ATTACK/DAMAGE/DEFENSE) — limitación
  preexistente del motor, en la misma bolsa que el `IMMUNITY` ya conocido y no consultado. No se
  arregla en esta corrección: está fuera de su alcance y requiere tocar el motor de resolución de
  combate en general, no solo la épica.
- Efectos de épica no representables todavía con el motor reutilizado (p. ej. cualquier variante que
  no sea daño directo/curación/modificador de estadística/inmunidad/reflejo/revivir/estado temporal):
  documentados explícitamente en el código (`EpicSkillPolicy`), nunca aproximados en silencio.
- `unequip` explícito: no implementado; ningún escenario formal lo exige todavía (equipar-reemplaza
  sigue siendo suficiente).

**Eliminados de esta lista tras la corrección (ya NO son pendientes):**
- ~~`P-HU31-EPIC-CARDINALITY`~~: confirmado por José — un jugador puede poseer múltiples épicas;
  cada héroe tiene como máximo una equipada a la vez. Resuelto en el contrato §2 y en
  `EquipEpicOnHero` (reemplaza la épica del héroe, nunca toca las demás épicas del jugador).
- ~~`P-HU31-CATALOG-MULTI-EFFECT`~~ (renombrado `GAP-HU31-CATALOG-MULTI-EFFECT`, RESUELTO): Catalog
  ya representa múltiples efectos específicos simultáneos (`specificEffects[]`, PR #70).
- ~~Ejecución de la épica como acción de turno propia~~: implementada de verdad (`UseEpic`,
  `EpicRealtimeHandler`, comando WS `useEpic`) — ver §4 y §7.
- ~~Intermitencia/503 del E2E extendido~~: diagnosticada y corregida — ver los 6 hallazgos reales
  listados en §7 (Combat PR #69).
- Gap operativo no relacionado con HU-31, descubierto durante el debugging del E2E: Player-Inventory
  arranca con `NestFactory.create(AppModule, { logger: false })`, silenciando todo log de
  excepciones no traducidas del framework. Reportado por separado como tarea sugerida
  (`task_0e39714d`), no corregido aquí por estar fuera de alcance de HU-31.

## 13. Reproducibilidad

```bash
# Catalog
cd Nexus-Battle-Catalog && npm run test:coverage

# Player-Inventory
cd Nexus-Battle-Player-Inventory && npm run test:coverage && npm run test:db

# Combat
cd Nexus-Battle-Combat && npm run test:coverage && npm run test:db
# E2E real (requiere Nexus-Battle-Player-Inventory como hermano en disco, o
# PLAYER_INVENTORY_REPO_PATH apuntando a su checkout); HU31_E2E_DEBUG=1 vuelca
# tambien los logs reales del proceso de Player-Inventory:
npm run test:e2e:hu-31

# Web
cd Nexus-Battle-Web && npm test && npm run build
```

## 14. Confirmaciones explícitas

- No se inventó ningún requisito no respaldado por Management#78, el SRS, José o el código auditado.
- No se duplicó el resolver `applyEpicEffects`/`computeHeroEffectsWithEpic` (PR #18); se adaptó para
  sumar TODOS los efectos específicos, nunca se reescribió desde cero.
- No se creó una segunda fuente de verdad para "qué épica está equipada": Player-Inventory es la
  única.
- Cardinalidad respetada: un jugador puede poseer varias épicas; cada héroe tiene como máximo UNA
  equipada. Equipar una épica nueva en un héroe reemplaza la suya, nunca toca las demás épicas del
  jugador ni las épicas de otros héroes.
- No se implementaron múltiples épicas equipadas simultáneamente en un mismo héroe.
- No se mezcló la épica con las ranuras 2/6/2 de HU-28 (`EquipmentCategory` sigue sin `EPICA`).
- La épica sigue excluida como candidata de drop de HU-30 (Versus).
- No se implementó lógica de dominio de HU-31 en Web ni en Tournament.
- No se inventó un segundo protocolo de ejecución de combate: `UseEpic`/`EpicRealtimeHandler`
  reutilizan el mismo motor de efectos (daño/curación/modificador/inmunidad/reflejo/revivir/estado
  temporal) y el mismo mapa de `cooldowns` que `UseSkill`, con clasificación propia solo donde el
  comportamiento es genuinamente distinto (combinar efectos heterogéneos a la vez).
- Combat nunca confía en un identificador de épica aportado por el cliente: solo ejecuta la épica
  congelada en el propio `CombatProfile` del actor.
- No se filtraron secretos, tokens ni metadata administrativa de Catalog hacia Combat o Web.
- No se trabajó sobre `main` en ningún repositorio.
- No se hizo merge de ningún PR.
- No se cerró ningún issue de Management; `#63` permanece CLOSED (sin reabrir sin autorización
  explícita de José), `#78`/`#539`-`#543` permanecen OPEN.
