# Contrato HU-31 — habilidad épica equipada (v1)

- **Estado:** **diseño + implementación en curso.** Cierra la brecha auditada en [Management#78](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/78): el resolver puro `applyEpicEffects`/`computeHeroEffectsWithEpic` (Player-Inventory [PR #18](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/18), Tasks [#206](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/206)–[#208](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/208)) ya existe y **no se reimplementa**; lo que faltaba es una fuente autoritativa de «épica activa/equipada» conectada a Player-Inventory → Combat. Tasks [#539](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/539)–[#543](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/543).
- **Historia:** [HU-31 #78](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/78) · `RF-31`.
- **Este documento es HU-31.4** (Task #539): auditoría + contrato autoritativo. No reabre el resolver de #206–#208 ni el diseño de HU-28/HU-29.
- **Fuentes auditadas:** comentarios consolidados de [#78](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/78) (estado auditado 2026-08-27, avance local 2026-09-15, auditoría final de `josemora090525` 2026-09-20, aclaración de ejecución 2026-10-02); HU-27 [#74](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/74) (cerrada); HU-28 [#75](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/75) (cerrada, excluye épicas); HU-19 [#63](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/63) (cerrada, ejecución de habilidades); HU-32 [#79](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/79) (abierta, obtención vía Máster); [hu-29-battle-commitment-v1](hu-29-battle-commitment-v1.md); [hu-19-skills-v1](hu-19-skills-v1.md) §11; [hu-30-versus-drop-v1](hu-30-versus-drop-v1.md); código real de `develop` en Player-Inventory, Catalog, Combat y Web (auditoría línea por línea, 2026-10-02).

## 1. Qué resuelve este contrato, y qué no

**El problema.** `applyEpicEffects` (Player-Inventory, dominio puro) decide qué capas de efecto de una épica aplican a un héroe según su subtipo. Es correcto y está probado, pero nadie lo invoca con datos reales: no existe un sitio donde se registre *qué* épica tiene equipada un héroe. Sin eso, CA-02 de HU-31 (identificar la épica equipada) queda sin demostrar y CA-07 (aceptación) está bloqueado.

**La solución.** Player-Inventory añade una nueva pieza de estado, **separada** del `HeroLoadout` de HU-28: la selección de épica equipada de un héroe. Resuelve su definición en Catalog, aplica `applyEpicEffects` con el subtipo real del héroe, y publica el resultado en `equipped-hero` como campo aditivo. Combat lo consume y lo congela en el snapshot de batalla. Web lo presenta y permite seleccionarlo, sin decidir nada.

**Lo que este contrato NO hace:**

- **No reimplementa `applyEpicEffects`/`computeHeroEffectsWithEpic`.** Se reutilizan tal cual existen hoy en `src/domain/policies/EpicEffectPolicy.ts` y `hero-epic-effects.ts` de Player-Inventory.
- **No mezcla la épica con las ranuras 2/6/2 de HU-28.** `EquipmentCategory` sigue siendo `WEAPON | ARMOR | ITEM`; `HeroLoadout` no gana una ranura de épica. La épica es un agregado hermano, no una undécima ranura.
- **No implementa la ejecución de la épica como acción de turno.** Eso es `hu-19-skills-v2` (§7) y depende además de que Catalog resuelva su brecha de `specificEffect` único (§6). Este contrato solo congela la épica en el snapshot; no añade comando `useSkill` ni gasta Poder ni aplica recarga.
- **No resuelve cómo se obtiene una épica.** Eso es HU-32/HU-73. Este contrato asume que el jugador ya posee la épica en su inventario (unidad ≥ 1, `type = EPICA`).
- **No cambia el contrato de Catalog.** Catalog permanece de solo lectura para HU-31 (§6).

## 2. Decisiones de diseño (y su fuente)

| # | Decisión | Tipo | Fuente |
| --- | --- | --- | --- |
| 1 | Cardinalidad: **como máximo una épica equipada por héroe** (0 o 1). | Decisión técnica, por ausencia de fuente en contra | Ninguna fuente formal fija un número explícito. Toda redacción encontrada es singular: HU-19 «su habilidad épica equipada», HU-31 (auditoría de #78) «la épica activa», Tabla 20 define épicas discretas una por tipo de héroe. Ninguna fuente sugiere múltiples épicas simultáneas. Se registra el residuo como `P-HU31-EPIC-CARDINALITY`: si Management fija explícitamente otra cardinalidad, este contrato se revisa antes de ampliarla. |
| 2 | Ownership: **Player-Inventory**, agregado nuevo y separado de `HeroLoadout`. | Decisión técnica | Task #539/#540 lo asignan explícitamente a Player-Inventory («candidato natural», ya posee ownership de héroe/inventario). Separado de `HeroLoadout` porque HU-28 excluye expresamente `EPICA` de `EquipmentCategory` (`equipmentCategoryOfProductType` devuelve `null`) y porque mezclar capacidad 2/6/2 con una selección 0/1 reabriría HU-28 sin necesidad. |
| 3 | Catalog sigue siendo la única fuente de la definición (`compatibleHeroSubtype`, `generalEffect`, `specificEffect`). Player-Inventory no la copia ni la reinterpreta: la resuelve en cada publicación de `equipped-hero`. | Requisito explícito | Task #539/#540; mismo patrón ya usado por `GetHeroEquipment`/`EquipItemOnHero` para ARMA/ARMADURA/ITEM. |
| 4 | El bloqueo de batalla de HU-29 (`BattleStatePort.isHeroInActiveBattle`) se **reutiliza** para la mutación de épica. No es una ampliación del alcance textual de HU-29 (que nombra arma/armadura/ítem): es la aplicación del mismo mecanismo de «compromiso de batalla» a una mutación nueva que no existía cuando se escribió ese contrato. | Decisión técnica, instruida explícitamente | Task #540: «No cambiar la épica mientras exista un compromiso de batalla HU-29 si la mutación corresponde al loadout persistido»; master-prompt §14. [hu-29-battle-commitment-v1](hu-29-battle-commitment-v1.md) §10.4 decía «la épica. No entra en el bloqueo» porque en 2026-09 no existía todavía una mutación de épica que bloquear — no porque se decidiera excluirla a propósito. Este contrato cierra ese punto, aditivamente (§9). |
| 5 | Combat **no** re-ejecuta `applyEpicEffects`. Player-Inventory resuelve y normaliza una vez por petición (igual que ya hace con `abilities`, [hu-19-skills-v1](hu-19-skills-v1.md) §10.1); Combat solo congela el resultado ya resuelto. | Decisión técnica (reutiliza patrón existente) | Evita duplicar el resolver en dos servicios; mismo patrón que `abilities` en `equipped-hero`. |
| 6 | Combat **no** toca `UseSkill.ts`, `SkillEffectPolicy.ts`, `SkillRealtimeHandler.ts`, ni el protocolo `useSkill` del WebSocket. Solo extiende el DTO/snapshot (`PlayerInventoryEquippedHeroPort`, `CombatProfile`, `Combatant`). | Decisión técnica, instruida explícitamente | Task #541: «No convertir HU-31 en una reimplementación de HU-19»; [hu-19-skills-v1](hu-19-skills-v1.md) §11: «Cuando HU-31 defina la fuente, la épica se añade sin cambiar el contrato de `useSkill` salvo un identificador nuevo». El guard estático `test/unit/hu-19-skills-guards.spec.ts` (Combat) que impedía nombrar `activeEpic/epicSlot/selectedEpic/equippedEpic/epicId` en los 5 ficheros de ejecución de habilidades se **actualiza** (no se elimina) para seguir protegiendo los 3 ficheros de ejecución real (`SkillEffectPolicy.ts`, `UseSkill.ts`, `SkillRealtimeHandler.ts`) y dejar de cubrir `CombatProfile.ts`/`Combatant.ts`, que ahora sí declaran el campo `epic` por contrato, no por intuición. |
| 7 | HU-30 (drop PvP) no se toca. La épica nunca entra en `battle-drops/snapshots`: ese canal lo construye Player-Inventory a partir de `HeroLoadout` (ARMA/ARMADURA/ITEM únicamente); el nuevo agregado de épica no es una fuente que ese código lea. | Confirmación, no cambio | Auditoría de código: `CaptureBattleDropSnapshot` (Player-Inventory) y `ResolveVersusDrop`/`VersusDropCandidate` (Combat) no referencian el nuevo agregado; [hu-30-versus-drop-v1](hu-30-versus-drop-v1.md) ya excluye épicas explícitamente (§1). |
| 8 | Catalog **no se modifica**. El único defecto real (`EpicAttributes.specificEffect` admite un solo efecto; al menos 5/8 filas de Tabla 20 combinan dos) no bloquea CA-01…CA-07 de HU-31: el resolver y sus pruebas ya demuestran base+específico con un único efecto por capa. Es una brecha de **riqueza de datos** para representar las 8 épicas reales con fidelidad total, no una brecha de **comportamiento** del resolver. Se registra como `P-HU31-CATALOG-MULTI-EFFECT`, ya documentada en código (`docs/hu-19-skills.md` de Combat, `docs/hu-31-epic-effects.md` de Player-Inventory) y aquí consolidada; requiere su propio proceso de ADR/contrato con Catalog cuando Management decida resolverla. | Pendiente genuino, no inventado | Auditoría de `src/domain/value-objects/product-attributes.ts` (Catalog, `develop`): `specificEffect: ProductEffect` (singular), sin cambios desde su introducción (PR #22, HU-33.3) hasta hoy. |
| 9 | Web no calcula compatibilidad ni efectos. Presenta lo que el backend resuelve; reutiliza `isBattleLockError`/`locked` de HU-29 sin un segundo mecanismo. No se añade un asset/skin PixelLab nuevo para épica: no existe un paquete de rediseño aprobado para «Mi Inventario» (auditado: solo Commerce y Jugar Online tienen paquetes PixelLab propios). La UI usa los tokens/componentes actuales (`ProductThumb`, patrón de tarjeta de `InventoryGrid`/`EquipmentSlots`), ya preparados para que el rediseño futuro sustituya solo la capa visual. | Requisito explícito + decisión técnica | Task #542; master-prompt §29–§33. |

## 3. Nuevo agregado: selección de épica equipada (Player-Inventory)

Agregado nuevo, **hermano** de `HeroLoadout`, mismo patrón de bloqueo optimista por versión:

```text
HeroEpicSelection
  ownerId: PlayerId
  heroId: string            (productId canonico del heroe, igual que HeroLoadout.heroId)
  epicItemId: string        (itemId/sku del inventario, igual significado que HeroLoadoutEntrySnapshot.itemId)
  epicProductId: string     (productId canonico de Catalog)
  version: number           (bloqueo optimista, mismo mecanismo que HeroLoadout.version)
```

- `_id` de persistencia: `${ownerId}:${heroId}` (idéntico patrón a `HeroLoadout`). Como máximo un documento por héroe ⇒ cardinalidad 0/1 queda garantizada por la clave, no por una regla aplicativa adicional.
- **Equipar reemplaza** la selección anterior directamente: no hay «ranura ocupada» que rechazar (a diferencia de `HeroLoadout.equip()`, que rechaza una ranura ya ocupada por otro producto). La razón de la diferencia: `HeroLoadout` tiene *varias* ranuras discretas donde dos productos distintos podrían competir por la misma; `HeroEpicSelection` tiene un único valor, así que "equipar la épica B" ya expresa sin ambigüedad "deja de estar equipada la épica A". No se inventa un `unequip` separado porque ningún escenario E2E obligatorio (Task #543) ni fuente formal lo exige; queda anotado como capacidad no incluida, no como omisión.
- Mutación: nueva pieza de dominio `HeroEpicSelection.equip(...)`, análoga a `HeroLoadout.equip()`, SIN los conceptos `EquipmentSlot`/`EquipmentCategory`/capacidad — no aplica a un agregado de cardinalidad 1.
- Ownership se valida en la capa de aplicación (igual que `EquipItemOnHero`): el héroe pertenece al jugador (`resolveOwnedHero`), el `itemId` de la épica está en el `Inventory` del jugador con cantidad ≥ 1, y Catalog resuelve ese producto con `type = EPICA`.
- Bloqueo de batalla: antes de escribir, se consulta `BattleStatePort.isHeroInActiveBattle(ownerId, heroId)` (el mismo puerto que ya usa `EquipItemOnHero`); si es `true`, se rechaza con el mismo error/forma que HU-29 (§9).
- Persistencia: Mongo, colección `hero-epic-selections`, migración `016-hero-epic-selections` (siguiente número tras `015-battle-drop-units` de HU-30), mismo mecanismo `replaceOne({_id, version: expectedVersion}, next)` / `insertOne` en `version 0` que `MongoHeroLoadoutRepository`.

## 4. Resolución de efectos (reutilizada, no reimplementada)

```text
Catalog (EpicAttributes: compatibleHeroSubtype, generalEffect?, specificEffect)
   │  resuelto vía CatalogReadPort, mismo cliente que ARMA/ARMADURA/ITEM
   ▼
parseEpicAttributes(attributes)              ← ya existe, src/domain/policies/hero-epic-effects.ts
   │
   ▼
applyEpicEffects({ heroType: hero.subtype, epic })   ← ya existe, EpicEffectPolicy.ts
   │
   ▼
AppliedEpicEffects { baseApplied, additionalApplied, combined }
```

Ninguna de estas tres funciones se modifica. La única pieza nueva es *quién las invoca con datos reales*: el nuevo caso de uso que ensambla `equipped-hero` (§5) lee `HeroEpicSelection`, resuelve el producto en Catalog, y llama a `computeHeroEffectsWithEpic`/`applyEpicEffects` con el subtipo real del héroe.

## 5. Contrato `equipped-hero` — extensión aditiva

Ruta sin cambios: `GET /api/internal/v1/players/{playerId}/equipped-hero` ([contrato existente](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/blob/develop/docs/equipped-hero-contract.md), Player-Inventory). Se añade un campo, **opcional y aditivo**, análogo a `abilities` (HU-19):

```jsonc
{
  // ...campos existentes sin cambios (baseStats, effectiveStats, activeEffects, abilities, ready, blockers, loadoutVersion, selectedAt)...
  "epic": {
    "epicProductId": "3f1e...",          // productId canonico de Catalog
    "epicReference": "golpe-de-defensa", // alias/sku si Catalog lo publica
    "name": "Golpe de defensa",
    "imageUrl": "https://.../golpe-de-defensa.png", // solo presentacion (Web); Combat la ignora (lista blanca de su parser)
    "compatibleHeroSubtype": "GUERRERO_TANQUE",
    "baseEffect": { "...": "..." } ,     // objeto de efecto, o null si "No aplica" (Chaman/Medico)
    "specificEffect": { "...": "..." },  // objeto de efecto, siempre presente en la definicion
    "applied": {
      "baseApplied": { "...": "..." },      // = baseEffect si no es null; null si "No aplica"
      "additionalApplied": { "...": "..." } // = specificEffect SOLO si subtype del heroe coincide; null si no coincide
    }
  } // ausente (no la clave con null) si el heroe no tiene epica equipada
}
```

- **Lista blanca, no el documento crudo de Catalog**: igual que `activeEffects`/`abilities`, nunca viaja `rawProduct`, precio, metadatos de administración ni inventario interno (§23 master-prompt).
- `baseEffect`/`specificEffect` son la definición cruda de Catalog (para que Web pueda mostrar "qué hace la épica" incluso sin coincidencia de subtipo); `applied.baseApplied`/`applied.additionalApplied` son el resultado YA resuelto por `applyEpicEffects` (lo que Combat congela y lo que Web usa para indicar "aplicado"/"no aplicado por subtipo").
- `epic` **ausente** (la clave entera no existe en el JSON) significa "sin épica equipada". No se envía `"epic": null` ni `"epic": {}` — mismo criterio que el resto del contrato: ausencia explícita, no un valor vacío inventado.
- Una épica cuyo producto de Catalog ya no resuelve (`CatalogUnavailableError`) o cuya definición no cumple el contrato canónico (`parseEpicAttributes` lanza `DomainError`) se trata igual que una habilidad no resoluble en `abilities` (§10.1 de HU-19): se omite de la respuesta en vez de tumbarla, salvo que Catalog esté completamente inalcanzable, en cuyo caso el contrato ya devuelve `503` como hoy.
- Compatibilidad: **aditivo puro**. Ningún consumidor existente de `equipped-hero` (Combat, Commerce, Notifications) se rompe por la ausencia de la clave `epic` en respuestas sin épica equipada.

## 6. Catalog — confirmado solo lectura

Catalog no cambia en esta HU. La brecha real (`specificEffect` como efecto único, no lista) queda documentada como `P-HU31-CATALOG-MULTI-EFFECT` (decisión #8, §2) y **no bloquea** ningún CA de HU-31: el E2E (HU-31.8) usa una épica sintética de prueba cuyo `specificEffect` es un único efecto — exactamente la forma que Catalog ya admite — sin pretender representar con fidelidad total las 8 filas reales de la Tabla 20. Crear las 8 épicas reales en Catalog, con nombre e identidad del SRS, es trabajo de contenido/datos fuera de este contrato y no depende de él.

## 7. HU-19 — qué se retira del bloqueo, qué sigue bloqueado

| Punto de [hu-19-skills-v1](hu-19-skills-v1.md) §11 | Antes de este contrato | Después de este contrato |
| --- | --- | --- |
| Fuente/estado de «épica activa/equipada» | No existe | **Resuelto**: `HeroEpicSelection` (Player-Inventory), publicado en `equipped-hero.epic` |
| Catalog con un solo efecto específico por épica | Bloqueado | **Sigue bloqueado** (`P-HU31-CATALOG-MULTI-EFFECT`, §6) |
| Comando `useSkill` para ejecutar la épica como acción de turno, con costo de Poder 0 y recarga 2 | Bloqueado | **Sigue bloqueado** — depende de ambos puntos anteriores resueltos; es `hu-19-skills-v2`, fuera de alcance de HU-31 |

Este contrato **no** publica `hu-19-skills-v2`: solo dejar escrito, aditivamente en `hu-19-skills-v1.md` §11 y §16, que la parte de fuente/persistencia ya no está bloqueada y que la parte de ejecución sigue pendiente de Catalog.

## 8. Combat — snapshot, no ejecución

```text
Player-Inventory  equipped-hero.epic  --(HTTP interno, HMAC)-->  Combat
                                                                      │
                                                        StartBattle.start()
                                                     revalidate() → freeze()
                                                                      │
                                                          CombatProfile.epic
                                                       (congelado, igual que
                                                     activeEffects/abilities)
```

- `PlayerInventoryEquippedHeroPort`/`PlayerInventoryHttpClient` (Combat) añaden el parseo de `epic` con el mismo rigor de lista blanca que el resto del parser (ningún campo se infiere ni se rellena con valores por defecto).
- `CombatProfile` añade un campo `epic: CombatEpic | null`, congelado en el mismo punto donde hoy se congelan `activeEffects`/`abilities` (`freeze()` → `combatProfileFrom()`).
- `Combatant` no necesita estado de ejecución propio para la épica en esta versión (sin cooldown/carga en runtime): eso pertenece a `hu-19-skills-v2`. Solo transporta el snapshot congelado.
- **StartTournamentRoom no cambia.** Reutiliza `StartBattle.startRoom()` → mismo `start()` → mismo snapshot. Confirmado por auditoría de código (`StartTournamentRoom.ts` delega sin lógica propia).
- El guard estático de Combat (`test/unit/hu-19-skills-guards.spec.ts`) se actualiza para seguir protegiendo únicamente los 3 ficheros de ejecución real de habilidades (decisión #6, §2).
- HU-30 no se toca (decisión #7, §2): `battle-drops/snapshots` sigue siendo un canal separado que solo lee `HeroLoadout`.

## 9. Bloqueo de batalla (HU-29) — aplicación aditiva, no reapertura

Reutiliza exactamente `BattleStatePort.isHeroInActiveBattle` (Player-Inventory, dato local, sin llamada a Combat en el camino crítico — igual que para HU-28). La decisión se expresa con una segunda función en el mismo módulo que ya declara `decideEquipmentChange`/`BATTLE_LOCK_MESSAGE` (`EquipmentCombatLockPolicy.ts`), sin crear un segundo mecanismo de bloqueo ni una tabla de categorías nueva (la épica no es una `EquipmentCategory`, así que no se fuerza a entrar en `LOCKED_CATEGORIES`). El error y su forma HTTP (`409 { reason: 'battle_lock', message }`) son los mismos que HU-29 ya define.

Esto **no reabre** [hu-29-battle-commitment-v1](hu-29-battle-commitment-v1.md): esa ruta de compromiso/liberación entre Combat y Player-Inventory no cambia. Lo único que cambia es que una mutación nueva (equipar épica), que no existía cuando se escribió ese contrato, consulta el mismo compromiso ya vigente antes de escribir.

## 10. Web — presentación, no autoridad

- Nueva superficie de lectura/escritura en Player-Inventory consumida directamente: `GET/PUT .../heroes/:heroId/epic` (§11).
- UI: una cuarta agrupación en el gestor de equipamiento de "Mi Inventario" (hoy `EquipmentSlots.tsx` solo agrupa armas/armadura/ítems), reutilizando `ProductThumb`, el patrón de tarjeta de `InventoryGrid`, `useHeroEquipment`-style React Query (una query por héroe, sin actualización optimista, `setQueryData` tras éxito) y `isBattleLockError`/`battleLockMessage` de HU-29 sin un segundo mecanismo.
- Sin asset PixelLab nuevo: no existe un paquete de rediseño aprobado para "Mi Inventario" (auditado). La representación visual de productos `EPICA` (glifo 2D, categoría `epic` de la librería visual) **ya existe** en Web desde antes de esta HU y se reutiliza sin cambios.
- Web no calcula `baseApplied`/`additionalApplied`: los lee de `epic.applied` ya resuelto por el backend.

## 11. Nuevas rutas públicas (Player-Inventory)

Mismo patrón que HU-28 (`PUT/GET /inventories/me/heroes/:heroId/equipment/...`), auth `@CurrentIdentity()`/JWT, sin ampliar el allow-list interno:

```text
GET /api/inventories/me/heroes/{heroId}/epic
PUT /api/inventories/me/heroes/{heroId}/epic
  body: { "productReference": "<productId o sku de la epica propia>" }
```

**Respuesta (200), misma forma resuelta que `equipped-hero.epic` (§5) más `version` para el bloqueo optimista del propio recurso.**

### Errores

| Código | Caso | Reutiliza |
| --- | --- | --- |
| `404` | Héroe no es del jugador | `HeroNotOwnedError` (igual que HU-28) |
| `404` | Épica no está en el inventario del jugador (cantidad 0) | Nuevo `EpicProductNotOwnedError`, mismo criterio anti-enumeración que `EquipmentProductNotOwnedError` |
| `422` | El producto referenciado no es `type = EPICA` | Nuevo `EpicProductInvalidTypeError`, mismo criterio que `InvalidEquipmentTypeError` |
| `409` | Bloqueo de batalla activo | `EquipmentLockedDuringBattleError` (reutilizado, §9) |
| `409` | Conflicto de versión (escritura concurrente) | Nuevo `HeroEpicSelectionConflictError`, mismo criterio que `HeroLoadoutConflictError` |
| `503` | Catalog no responde | `CatalogUnavailableError` (reutilizado) |

## 12. Trazabilidad CA-01…CA-07

| CA | Qué exige | Dónde se demuestra |
| --- | --- | --- |
| CA-01 | Regla principal: base + específico según corresponda | Resolver existente (PR #18), sin cambios; demostrado de nuevo en E2E con datos reales (§HU-31.8) |
| CA-02 | Identificar la épica **equipada** y el tipo real del héroe | **Este contrato**: `HeroEpicSelection` + `equipped-hero.epic`, con ownership verificado server-side |
| CA-03 | Efecto general se conserva cuando existe (o `null` = "No aplica") | Resolver existente; `parseEpicAttributes` ya preserva la semántica |
| CA-04 | Coincidencia de subtipo → base + específico | Resolver existente + E2E-01 |
| CA-05 | No coincidencia → solo base | Resolver existente + E2E-02 |
| CA-06 | Específico nunca sustituye al general | Resolver existente (invariante ya probada en PR #18) |
| CA-07 | Aceptación integral | Depende de CA-01…06 **y** de la integración real demostrada en HU-31.8; no se marca `PASS` por este documento solo |

## 13. Pendientes genuinos (no se resuelven por intuición)

- `P-HU31-EPIC-CARDINALITY` (§2, decisión 1): cardinalidad 0/1 es la lectura consistente de todas las fuentes, pero ninguna la fija con una frase explícita de cardinalidad.
- `P-HU31-CATALOG-MULTI-EFFECT` (§2, decisión 8; §6): Catalog necesita su propio proceso de ADR/contrato para representar los componentes múltiples de al menos 5/8 épicas de Tabla 20. Fuera de alcance de HU-31.
- Ejecución de la épica como acción de turno (`hu-19-skills-v2`, §7): bloqueada hasta que `P-HU31-CATALOG-MULTI-EFFECT` se resuelva y Management confirme el diseño de ejecución (costo 0, recarga 2, interacción con Poder).
- Desequipar la épica sin reemplazarla por otra no se implementa (§3): ningún escenario obligatorio lo exige; se deja como capacidad futura si se decide necesaria.
