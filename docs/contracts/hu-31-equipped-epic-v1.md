# Contrato HU-31 — habilidad épica equipada (v1)

- **Estado:** **implementación completa, correcciones aplicadas, pendiente de revisión/merge.** Cierra la brecha auditada en [Management#78](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/78): el resolver puro `applyEpicEffects`/`computeHeroEffectsWithEpic` (Player-Inventory [PR #18](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/18), Tasks [#206](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/206)–[#208](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/208)) ya existía y **no se reimplementó**; la fuente autoritativa de «épica activa/equipada» (Tasks [#539](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/539)–[#543](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/543)) se construyó, y una ronda de corrección posterior (2026-10-02/03) resolvió los dos pendientes que esta primera versión dejaba abiertos: la cardinalidad quedó **confirmada** (§2, decisión 1) y la brecha de Catalog (`specificEffect` único) quedó **resuelta** (§2, decisión 8; §6) — lo que a su vez permitió implementar la **ejecución real** de la épica como acción de turno (§7, §8), que esta v1 original dejaba fuera de alcance.
- **Historia:** [HU-31 #78](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/78) · `RF-31`.
- **Este documento es HU-31.4 + su corrección** (Tasks #539 y #543): auditoría + contrato autoritativo, ampliado tras la correccion de 2026-10-03. No reabre el resolver de #206–#208 ni el diseño de HU-28/HU-29.
- **Fuentes auditadas:** comentarios consolidados de [#78](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/78) (estado auditado 2026-08-27, avance local 2026-09-15, auditoría final de `josemora090525` 2026-09-20, aclaración de ejecución 2026-10-02); HU-27 [#74](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/74) (cerrada); HU-28 [#75](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/75) (cerrada, excluye épicas); HU-19 [#63](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/63) (cerrada, ejecución de habilidades); HU-32 [#79](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/79) (abierta, obtención vía Máster); [hu-29-battle-commitment-v1](hu-29-battle-commitment-v1.md); [hu-19-skills-v1](hu-19-skills-v1.md) §11; [hu-30-versus-drop-v1](hu-30-versus-drop-v1.md); código real de `develop` en Player-Inventory, Catalog, Combat y Web (auditoría línea por línea, 2026-10-02); documento del proyecto integrador (Tabla 20, aclaración de la correcion de cardinalidad/multi-efecto, 2026-10-02/03); código real de las 4 ramas corregidas (2026-10-03).

## 0. Historial de revisiones

| Fecha | Cambio |
| --- | --- |
| 2026-10-02 | Version original: contrato de la fuente autoritativa (`HeroEpicSelection`, `equipped-hero.epic`, snapshot congelado en Combat). Cardinalidad y brecha de Catalog registradas como pendientes genuinos. |
| 2026-10-03 | **Corrección**: cardinalidad confirmada por el documento del proyecto integrador (ya no es un pendiente); Catalog resuelve `specificEffect` → `specificEffects[]` (PR [#70](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/70)); Player-Inventory/Web adaptan el resolver y la presentación al nuevo contrato; Combat implementa la ejecución real de la épica como acción de turno (`UseEpic`, `EpicSkillPolicy`, PR [#68](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/68)). Nuevo pendiente genuino registrado: `P-HU31-STAT-CONSULTATION-GAP`. |

## 1. Qué resuelve este contrato, y qué no

**El problema.** `applyEpicEffects` (Player-Inventory, dominio puro) decide qué capas de efecto de una épica aplican a un héroe según su subtipo. Es correcto y está probado, pero nadie lo invoca con datos reales: no existe un sitio donde se registre *qué* épica tiene equipada un héroe. Sin eso, CA-02 de HU-31 (identificar la épica equipada) queda sin demostrar y CA-07 (aceptación) está bloqueado.

**La solución.** Player-Inventory añade una nueva pieza de estado, **separada** del `HeroLoadout` de HU-28: la selección de épica equipada de un héroe. Resuelve su definición en Catalog, aplica `applyEpicEffects` con el subtipo real del héroe, y publica el resultado en `equipped-hero` como campo aditivo. Combat lo consume y lo congela en el snapshot de batalla. Web lo presenta y permite seleccionarlo, sin decidir nada.

**Lo que este contrato NO hace:**

- **No reimplementa `applyEpicEffects`/`computeHeroEffectsWithEpic`.** Se reutilizan tal cual existen hoy en `src/domain/policies/EpicEffectPolicy.ts` y `hero-epic-effects.ts` de Player-Inventory.
- **No mezcla la épica con las ranuras 2/6/2 de HU-28.** `EquipmentCategory` sigue siendo `WEAPON | ARMOR | ITEM`; `HeroLoadout` no gana una ranura de épica. La épica es un agregado hermano, no una undécima ranura.
- **No resuelve cómo se obtiene una épica.** Eso es HU-32/HU-73. Este contrato asume que el jugador ya posee la épica en su inventario (unidad ≥ 1, `type = EPICA`).

> **Nota de la corrección (2026-10-03):** la versión original de este documento tenía aquí dos afirmaciones más — «no implementa la ejecución de la épica como acción de turno» y «no cambia el contrato de Catalog» — que ya NO son ciertas: la corrección resolvió la brecha de Catalog (§6) y, con la fuente de efectos ya en forma ejecutable, implementó la ejecución real en Combat (§7, §8). Se retiran de esta lista (en vez de tachar) para que el documento no afirme lo contrario de lo que el código hace hoy; el historial de revisiones (§0) conserva la trazabilidad del cambio.

## 2. Decisiones de diseño (y su fuente)

| # | Decisión | Tipo | Fuente |
| --- | --- | --- | --- |
| 1 | Cardinalidad **CONFIRMADA** (corrección 2026-10-03): un jugador puede poseer **múltiples épicas** en su inventario/colección; cada héroe puede tener **como máximo una épica equipada simultáneamente** (0 o 1). | Requisito explícito (ya no es una decisión técnica por ausencia de fuente) | El documento del proyecto integrador lo fija explícitamente. `P-HU31-EPIC-CARDINALITY` se **retira** como pendiente: el modelo `HeroEpicSelection` (0/1 por héroe, equipar reemplaza directamente, §3) ya lo garantizaba por construcción desde la v1 de este contrato — la corrección fue de *redacción/confirmación*, no de código. |
| 2 | Ownership: **Player-Inventory**, agregado nuevo y separado de `HeroLoadout`. | Decisión técnica | Task #539/#540 lo asignan explícitamente a Player-Inventory («candidato natural», ya posee ownership de héroe/inventario). Separado de `HeroLoadout` porque HU-28 excluye expresamente `EPICA` de `EquipmentCategory` (`equipmentCategoryOfProductType` devuelve `null`) y porque mezclar capacidad 2/6/2 con una selección 0/1 reabriría HU-28 sin necesidad. |
| 3 | Catalog sigue siendo la única fuente de la definición (`compatibleHeroSubtype`, `generalEffect`, `specificEffect`). Player-Inventory no la copia ni la reinterpreta: la resuelve en cada publicación de `equipped-hero`. | Requisito explícito | Task #539/#540; mismo patrón ya usado por `GetHeroEquipment`/`EquipItemOnHero` para ARMA/ARMADURA/ITEM. |
| 4 | El bloqueo de batalla de HU-29 (`BattleStatePort.isHeroInActiveBattle`) se **reutiliza** para la mutación de épica. No es una ampliación del alcance textual de HU-29 (que nombra arma/armadura/ítem): es la aplicación del mismo mecanismo de «compromiso de batalla» a una mutación nueva que no existía cuando se escribió ese contrato. | Decisión técnica, instruida explícitamente | Task #540: «No cambiar la épica mientras exista un compromiso de batalla HU-29 si la mutación corresponde al loadout persistido»; master-prompt §14. [hu-29-battle-commitment-v1](hu-29-battle-commitment-v1.md) §10.4 decía «la épica. No entra en el bloqueo» porque en 2026-09 no existía todavía una mutación de épica que bloquear — no porque se decidiera excluirla a propósito. Este contrato cierra ese punto, aditivamente (§9). |
| 5 | Combat **no** re-ejecuta `applyEpicEffects`. Player-Inventory resuelve y normaliza una vez por petición (igual que ya hace con `abilities`, [hu-19-skills-v1](hu-19-skills-v1.md) §10.1); Combat solo congela el resultado ya resuelto. | Decisión técnica (reutiliza patrón existente) | Evita duplicar el resolver en dos servicios; mismo patrón que `abilities` en `equipped-hero`. |
| 6 | Combat **no** toca `UseSkill.ts`, `SkillEffectPolicy.ts`, `SkillRealtimeHandler.ts`, ni el protocolo `useSkill` del WebSocket. Solo extiende el DTO/snapshot (`PlayerInventoryEquippedHeroPort`, `CombatProfile`, `Combatant`). | Decisión técnica, instruida explícitamente | Task #541: «No convertir HU-31 en una reimplementación de HU-19»; [hu-19-skills-v1](hu-19-skills-v1.md) §11: «Cuando HU-31 defina la fuente, la épica se añade sin cambiar el contrato de `useSkill` salvo un identificador nuevo». El guard estático `test/unit/hu-19-skills-guards.spec.ts` (Combat) que impedía nombrar `activeEpic/epicSlot/selectedEpic/equippedEpic/epicId` en los 5 ficheros de ejecución de habilidades se **actualiza** (no se elimina) para seguir protegiendo los 3 ficheros de ejecución real (`SkillEffectPolicy.ts`, `UseSkill.ts`, `SkillRealtimeHandler.ts`) y dejar de cubrir `CombatProfile.ts`/`Combatant.ts`, que ahora sí declaran el campo `epic` por contrato, no por intuición. |
| 7 | HU-30 (drop PvP) no se toca. La épica nunca entra en `battle-drops/snapshots`: ese canal lo construye Player-Inventory a partir de `HeroLoadout` (ARMA/ARMADURA/ITEM únicamente); el nuevo agregado de épica no es una fuente que ese código lea. | Confirmación, no cambio | Auditoría de código: `CaptureBattleDropSnapshot` (Player-Inventory) y `ResolveVersusDrop`/`VersusDropCandidate` (Combat) no referencian el nuevo agregado; [hu-30-versus-drop-v1](hu-30-versus-drop-v1.md) ya excluye épicas explícitamente (§1). |
| 8 | Catalog **SÍ se modifica** (corrección 2026-10-03, PR [#70](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/70)): `GAP-HU31-CATALOG-MULTI-EFFECT` (antes `P-HU31-CATALOG-MULTI-EFFECT`) queda **resuelto**, no solo documentado. `EpicAttributes.specificEffect` (un único efecto) pasa a `specificEffects` (lista, mínimo 1): al menos 4/8 filas de Tabla 20 combinan dos efectos simultáneos (ej. +4 daño Y +2% crítico, Golpe de defensa) que un único `ProductEffect` no podía representar (un objeto solo declara una `statistic`/`magnitude`). Compatibilidad retroactiva real: `parseEpicAttributes` acepta también la forma legada `specificEffect` (normalizada a lista de un elemento); un documento con ambas claves a la vez se rechaza explícitamente. `generalEffect` se mantiene singular: ninguna fuente exige múltiples efectos generales. | Requisito explícito (ya no es un pendiente) | Auditoría de `src/domain/value-objects/product-attributes.ts` (Catalog, `develop`) + documento del proyecto integrador (Tabla 20) + Catalog PR #70 (`feat(catalog): soportar efectos compuestos de habilidades epicas`). |
| 9 | Web no calcula compatibilidad ni efectos. Presenta lo que el backend resuelve; reutiliza `isBattleLockError`/`locked` de HU-29 sin un segundo mecanismo. No se añade un asset/skin PixelLab nuevo para épica: no existe un paquete de rediseño aprobado para «Mi Inventario» (auditado: solo Commerce y Jugar Online tienen paquetes PixelLab propios). La UI usa los tokens/componentes actuales (`ProductThumb`, patrón de tarjeta de `InventoryGrid`/`EquipmentSlots`), ya preparados para que el rediseño futuro sustituya solo la capa visual. | Requisito explícito + decisión técnica | Task #542; master-prompt §29–§33. |
| 10 | **(Corrección 2026-10-03) Ejecución real de la épica en Combat**: NUEVOS ficheros (`UseEpic.ts`, `EpicSkillPolicy.ts`, `EpicRealtimeHandler.ts`), nunca modificando `UseSkill.ts`/`SkillEffectPolicy.ts`/`SkillRealtimeHandler.ts` (decisión #6 sigue vigente: esos 3 ficheros de HU-19 siguen sin saber nada de épicas). Comando WebSocket nuevo `useEpic`, SIN `abilityId`: la única épica ejecutable es la congelada en `CombatProfile.epic` del propio perfil — el cliente nunca elige cuál. Costo de Poder 0 (modo `NONE` de `HeroPowerPolicy`, no `FIXED` con monto 0, que esa política rechaza); recarga 2 turnos propios, reutilizando el MISMO mapa `Combatant.cooldowns` que las habilidades (bajo `epicProductId`). `STAT_MODIFIER` se trata SIEMPRE como efecto temporal (decisión técnica: usar la épica no es un ataque, no existe «esta resolución» a la que sumar un bono instantáneo). | Requisito explícito (ya no bloqueado) + decisión técnica | Tasks #541/#543; `hu-19-skills-v1.md` §11/§16 (actualizado); Combat PR #68. |

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
Catalog (EpicAttributes: compatibleHeroSubtype, generalEffect?, specificEffects[])
   │  resuelto vía CatalogReadPort, mismo cliente que ARMA/ARMADURA/ITEM
   ▼
parseEpicAttributes(attributes)              ← ya existe, src/domain/policies/hero-epic-effects.ts
   │  (corrección 2026-10-03: acepta specificEffects[] o, por compatibilidad
   │   retroactiva, la forma legada specificEffect; nunca ambas a la vez)
   ▼
applyEpicEffects({ heroType: hero.subtype, epic })   ← ya existe, EpicEffectPolicy.ts
   │
   ▼
AppliedEpicEffects { baseApplied, additionalApplied: EpicEffect[], combined }
```

Ninguna de estas funciones se **reimplementa**; `applyEpicEffects`/`computeHeroEffectsWithEpic` conservan exactamente la misma semántica base+específico(s) según subtipo (decisión #5, §2). La corrección 2026-10-03 solo pluralizó `additionalEffect`/`additionalApplied` a `additionalEffects[]`/`additionalApplied[]` (lista vacía cuando no hay coincidencia, en vez de `null`) — `baseEffect` se mantiene singular. La pieza que invoca estas funciones con datos reales sigue siendo la misma: el caso de uso que ensambla `equipped-hero` (§5) lee `HeroEpicSelection`, resuelve el producto en Catalog, y llama a `computeHeroEffectsWithEpic`/`applyEpicEffects` con el subtipo real del héroe.

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
    "powerCost": 0,                      // (corrección 2026-10-03) los mismos que Catalog deriva para TODA EPICA
    "cooldownTurns": 2,                  // -- Combat los ejecuta sin inventar constantes propias
    "baseEffect": { "...": "..." } ,     // objeto de efecto, o null si "No aplica" (Chaman/Medico)
    "specificEffects": [{ "...": "..." }], // (corrección 2026-10-03) LISTA, minimo 1 -- antes "specificEffect" (un unico objeto)
    "applied": {
      "baseApplied": { "...": "..." },      // = baseEffect si no es null; null si "No aplica"
      "additionalApplied": [{ "...": "..." }] // = TODOS los specificEffects SOLO si subtype del heroe coincide; [] si no coincide
    }
  } // ausente (no la clave con null) si el heroe no tiene epica equipada
}
```

- **Lista blanca, no el documento crudo de Catalog**: igual que `activeEffects`/`abilities`, nunca viaja `rawProduct`, precio, metadatos de administración ni inventario interno (§23 master-prompt).
- `baseEffect`/`specificEffects` son la definición cruda de Catalog (para que Web pueda mostrar "qué hace la épica" incluso sin coincidencia de subtipo); `applied.baseApplied`/`applied.additionalApplied` son el resultado YA resuelto por `applyEpicEffects` (lo que Combat congela y lo que Web usa para indicar "aplicado"/"no aplicado por subtipo"). Ambos son opacos para Player-Inventory/Combat: ninguno de los dos interpreta su contenido, solo lo transportan.
- `epic` **ausente** (la clave entera no existe en el JSON) significa "sin épica equipada". No se envía `"epic": null` ni `"epic": {}` — mismo criterio que el resto del contrato: ausencia explícita, no un valor vacío inventado.
- Una épica cuyo producto de Catalog ya no resuelve (`CatalogUnavailableError`) o cuya definición no cumple el contrato canónico (`parseEpicAttributes` lanza `DomainError`) se trata igual que una habilidad no resoluble en `abilities` (§10.1 de HU-19): se omite de la respuesta en vez de tumbarla, salvo que Catalog esté completamente inalcanzable, en cuyo caso el contrato ya devuelve `503` como hoy.
- Compatibilidad: **aditivo puro**. Ningún consumidor existente de `equipped-hero` (Combat, Commerce, Notifications) se rompe por la ausencia de la clave `epic` en respuestas sin épica equipada.

> **Corrección 2026-10-03 — Combat añade `executableEffects` por su cuenta.** Player-Inventory NO publica este campo: Combat (`PlayerInventoryHttpClient.parseEpic`) construye `executableEffects = [applied.baseApplied?, ...applied.additionalApplied].filter(notNull)`, parseando cada elemento con el MISMO `parseAbilityEffect` que ya valida los efectos de `abilities` (mismo vocabulario `kind`/`target`/`statistic`/`operation`/`magnitude`). Es la única lista que `UseEpic` ejecuta de verdad; `baseEffect`/`specificEffects`/`applied.*` siguen siendo opacos en el contrato público de Player-Inventory tal como se describe arriba.

## 6. Catalog — RESUELTO (correción 2026-10-03), ya no es de solo lectura

> Esta sección decía «Catalog no cambia en esta HU» y documentaba `P-HU31-CATALOG-MULTI-EFFECT` como un pendiente fuera de alcance. La corrección de 2026-10-03 lo resolvió: Catalog [PR #70](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/70).

`EpicAttributes.specificEffect` (un único `ProductEffect`) pasa a **`specificEffects`** (lista, mínimo 1): el documento del proyecto integrador (Tabla 20) confirma épicas oficiales con más de un efecto específico simultáneo (ej. +4 daño Y +2% crítico, Golpe de defensa) que un único objeto no podía representar — un `ProductEffect` solo declara una `statistic`/`magnitude` por objeto. `generalEffect` se mantiene singular. Compatibilidad retroactiva real: `parseEpicAttributes` acepta también la forma legada `specificEffect` (normalizada a una lista de un elemento); un documento con las dos claves a la vez se rechaza explícitamente (nunca se combinan ni se prioriza una en silencio). El validador `$jsonSchema` de Mongo no necesitó cambios (no restringe el interior de `attributes.values` más allá de `kind`).

El E2E (HU-31.8, ampliado en la corrección) ya usa la forma canónica `specificEffects` con dos efectos simultáneos para la épica de subtipo coincidente, y la forma legada `specificEffect` para la de subtipo no coincidente — ejercitando las dos formas reales en el mismo escenario. Crear las 8 épicas reales en Catalog, con nombre e identidad del SRS, sigue siendo trabajo de contenido/datos fuera de este contrato.

## 7. HU-19 — RESUELTO (corrección 2026-10-03): la ejecución ya no está bloqueada

> Esta sección documentaba tres puntos bloqueados o resueltos a medias. Tras la corrección, dos de los tres quedan resueltos; el tercero se divide en lo que sí se resolvió y lo que es una brecha distinta, pre-existente del motor.

| Punto de [hu-19-skills-v1](hu-19-skills-v1.md) §11 | Antes de HU-31 | Tras HU-31 (v1) | Tras la corrección (2026-10-03) |
| --- | --- | --- | --- |
| Fuente/estado de «épica activa/equipada» | No existe | **Resuelto**: `HeroEpicSelection` (Player-Inventory), publicado en `equipped-hero.epic` | Sin cambios, sigue resuelto |
| Catalog con un solo efecto específico por épica | Bloqueado | Seguía bloqueado (`P-HU31-CATALOG-MULTI-EFFECT`) | **Resuelto** (§6) |
| Comando para ejecutar la épica como acción de turno, con costo de Poder 0 y recarga 2 | Bloqueado | Seguía bloqueado (dependía de los dos puntos anteriores) | **Resuelto**: comando WebSocket `useEpic` (Combat PR #68, §8) |

Brecha **distinta**, no resuelta por esta corrección, descubierta al implementar la ejecución real (registrada como `P-HU31-STAT-CONSULTATION-GAP`, §13): las estadísticas `CRITICAL_CHANCE`/`POWER` de un efecto de épica se REGISTRAN como efecto activo (igual que `IMMUNITY` ya hace para habilidades desde `hu-19-skills-v1`) pero ningún punto de resolución de Combat las CONSULTA todavía (`Combatant.statBonus` solo lee `ATTACK`/`DAMAGE`/`DEFENSE`) — es una limitación pre-existente del motor de HU-19/HU-25, no introducida por esta corrección, y pertenece a una ampliación futura de ese motor, no de HU-31.

Tampoco soportados todavía por `EpicSkillPolicy` (rechazo explícito de la épica ENTERA, nunca aplicación a medias): efectos `REFLECT_DAMAGE`, `TEMPORARY_STATUS`, audiencia `ENEMY_GROUP`, y una épica cuyos efectos exijan audiencias incompatibles entre sí (p. ej. uno sobre `ALLY` y otro sobre `OPPONENT`) — ningún escenario de la Tabla 20 real lo necesita hoy.

## 8. Combat — snapshot Y ejecución real (corrección 2026-10-03)

> Esta sección se titulaba «snapshot, no ejecución» y decía que `Combatant` no necesitaba estado de ejecución propio. La corrección añadió la ejecución real; se conserva el diagrama original del congelamiento (sin cambios) y se documenta la ejecución debajo.

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

- `PlayerInventoryEquippedHeroPort`/`PlayerInventoryHttpClient` (Combat) añaden el parseo de `epic` con el mismo rigor de lista blanca que el resto del parser (ningún campo se infiere ni se rellena con valores por defecto). Construyen además `executableEffects` (§5) a partir de `applied.*`, validado como efecto de habilidad real.
- `CombatProfile` añade un campo `epic?: CombatEpic`, congelado en el mismo punto donde hoy se congelan `activeEffects`/`abilities` (`freeze()` → `combatProfileFrom()`).
- **StartTournamentRoom no cambia.** Reutiliza `StartBattle.startRoom()` → mismo `start()` → mismo snapshot. Confirmado por auditoría de código (`StartTournamentRoom.ts` delega sin lógica propia): hereda la épica, y ahora también su ejecución, sin código específico de torneo.
- HU-30 no se toca (decisión #7, §2): `battle-drops/snapshots` sigue siendo un canal separado que solo lee `HeroLoadout`; la épica nunca es candidata a drop.

### 8.1. Ejecución real (NUEVO, corrección 2026-10-03)

- **Ficheros nuevos**, nunca modificando los de HU-19 v1 (decisión #6/#10, §2): `EpicSkillPolicy.ts` (clasifica TODOS los efectos de la épica a la vez — a diferencia de `evaluateSkill`, que resuelve una habilidad como una sola familia nunca mezclada), `UseEpic.ts` (caso de uso, mismo patrón que `UseSkill`: validación pura sin sorteo en `BattleRoom.planEpic`, sorteo de dados en el caso de uso, una sola transición en `BattleRoom.applyEpic`), `EpicRealtimeHandler.ts` (comando WebSocket `useEpic`).
- **Sin `abilityId`**: a diferencia de `useSkill`, el cliente no elige QUÉ ejecutar — la única épica ejecutable es la congelada en `CombatProfile.epic` del propio perfil. `target` es opcional: solo se exige cuando algún efecto necesita una audiencia distinta de `SELF`.
- **Decisión técnica** (sin fuente formal que la fije, documentada explícitamente): `STAT_MODIFIER` se trata SIEMPRE como efecto temporal, nunca como el patrón «instantáneo para esta resolución» que sí existe para una habilidad ofensiva — usar la épica no es un ataque, no hay «esta resolución» a la que sumarle un bono. La duración es `durationTurns` si el efecto la declara, o `cooldownTurns` de la propia épica en caso contrario.
- **Recarga**: reutiliza el MISMO mapa `Combatant.cooldowns` que las habilidades, bajo la clave `epicProductId` (`Combatant.restoreCooldowns` ampliado para reconocerla junto a `abilityId`) — no un segundo mecanismo.
- **Costo de Poder**: siempre 0 (Catalog, §6); se paga con el modo `NONE` de `HeroPowerPolicy` (un costo `FIXED` no admite 0 — esa política ya lo validaba así).
- El guard estático de Combat (`test/unit/hu-19-skills-guards.spec.ts`) sigue protegiendo únicamente `SkillEffectPolicy.ts`/`UseSkill.ts`/`SkillRealtimeHandler.ts` (decisión #6, §2): los ficheros nuevos de la épica viven aparte, así que ese guard no necesitó tocarse de nuevo.
- Un dato directo de una épica que elimina a un rival en PvP activa el MISMO drop de HU-30 (`PersistVersusDropDecision`) que un ataque básico o una habilidad — consistencia entre acciones de turno, no una ampliación del alcance de HU-30 (la épica en sí sigue sin ser candidata a drop).

## 9. Bloqueo de batalla (HU-29) — aplicación aditiva, no reapertura

Reutiliza exactamente `BattleStatePort.isHeroInActiveBattle` (Player-Inventory, dato local, sin llamada a Combat en el camino crítico — igual que para HU-28). La decisión se expresa con una segunda función en el mismo módulo que ya declara `decideEquipmentChange`/`BATTLE_LOCK_MESSAGE` (`EquipmentCombatLockPolicy.ts`), sin crear un segundo mecanismo de bloqueo ni una tabla de categorías nueva (la épica no es una `EquipmentCategory`, así que no se fuerza a entrar en `LOCKED_CATEGORIES`). El error y su forma HTTP (`409 { reason: 'battle_lock', message }`) son los mismos que HU-29 ya define.

Esto **no reabre** [hu-29-battle-commitment-v1](hu-29-battle-commitment-v1.md): esa ruta de compromiso/liberación entre Combat y Player-Inventory no cambia. Lo único que cambia es que una mutación nueva (equipar épica), que no existía cuando se escribió ese contrato, consulta el mismo compromiso ya vigente antes de escribir.

## 10. Web — presentación, no autoridad

- Nueva superficie de lectura/escritura en Player-Inventory consumida directamente: `GET/PUT .../heroes/:heroId/epic` (§11).
- UI: una cuarta agrupación en el gestor de equipamiento de "Mi Inventario" (hoy `EquipmentSlots.tsx` solo agrupa armas/armadura/ítems), reutilizando `ProductThumb`, el patrón de tarjeta de `InventoryGrid`, `useHeroEquipment`-style React Query (una query por héroe, sin actualización optimista, `setQueryData` tras éxito) y `isBattleLockError`/`battleLockMessage` de HU-29 sin un segundo mecanismo.
- Sin asset PixelLab nuevo: no existe un paquete de rediseño aprobado para "Mi Inventario" (auditado). La representación visual de productos `EPICA` (glifo 2D, categoría `epic` de la librería visual) **ya existe** en Web desde antes de esta HU y se reutiliza sin cambios.
- Web no calcula `baseApplied`/`additionalApplied`: los lee de `epic.applied` ya resuelto por el backend.
- (Corrección 2026-10-03) `specificEffects`/`additionalApplied` son listas (§5): el panel del jugador mapea `specificEffects` y muestra una fila por efecto (numerada si hay más de uno). El panel de administración (creación de productos EPICA, ajeno al jugador, ya existente desde antes de HU-31) reutiliza EXACTAMENTE el mismo patrón de lista con «Añadir efecto»/«Quitar efecto» que ya usan ARMA/ARMADURA/ITEM/HABILIDAD — no se inventó un segundo mecanismo de lista para la épica.

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
| CA-01 | Regla principal: base + TODOS los específicos según corresponda | Resolver existente (PR #18), semántica sin cambios (ahora plural, §4); demostrado de nuevo en E2E con datos reales (§HU-31.8) |
| CA-02 | Identificar la épica **equipada** y el tipo real del héroe | **Este contrato**: `HeroEpicSelection` + `equipped-hero.epic`, con ownership verificado server-side |
| CA-03 | Efecto general se conserva cuando existe (o `null` = "No aplica") | Resolver existente; `parseEpicAttributes` ya preserva la semántica |
| CA-04 | Coincidencia de subtipo → base + TODOS los específicos | Resolver existente + E2E-01 (ahora con 2 efectos específicos simultáneos) |
| CA-05 | No coincidencia → solo base | Resolver existente + E2E-02 |
| CA-06 | Ningún específico sustituye al general | Resolver existente (invariante ya probada en PR #18) |
| CA-07 | Aceptación integral | CA-01…06 **y** la integración real demostrada en HU-31.8, incluida la ejecución real (§8.1) — ver evidencia consolidada |

## 13. Pendientes genuinos (no se resuelven por intuición)

- `P-HU31-STAT-CONSULTATION-GAP` (NUEVO, §7, §8.1): `CRITICAL_CHANCE`/`POWER` se registran como efecto activo pero ningún punto de resolución de Combat los consulta todavía (`Combatant.statBonus` solo lee `ATTACK`/`DAMAGE`/`DEFENSE`). Brecha pre-existente del motor de HU-19/HU-25 (misma categoría que `IMMUNITY`, que tampoco se consulta), no introducida por esta corrección. Requiere una ampliación de ese motor, fuera de alcance de HU-31.
- Efectos `REFLECT_DAMAGE`/`TEMPORARY_STATUS`, audiencia `ENEMY_GROUP`, y audiencias incompatibles en la misma épica (§7): no soportados todavía por `EpicSkillPolicy`; rechazo explícito de la épica entera, nunca aplicación a medias. Ningún escenario de la Tabla 20 real lo necesita hoy.
- Desequipar la épica sin reemplazarla por otra no se implementa (§3): ningún escenario obligatorio lo exige; se deja como capacidad futura si se decide necesaria.

**Retirados por la corrección 2026-10-03** (ya no son pendientes): `P-HU31-EPIC-CARDINALITY` (§2, decisión 1 — confirmada) y `P-HU31-CATALOG-MULTI-EFFECT` (§2, decisión 8; §6 — resuelta, Catalog PR #70).
- Ejecución de la épica como acción de turno (`hu-19-skills-v2`, §7): bloqueada hasta que `P-HU31-CATALOG-MULTI-EFFECT` se resuelva y Management confirme el diseño de ejecución (costo 0, recarga 2, interacción con Poder).
- Desequipar la épica sin reemplazarla por otra no se implementa (§3): ningún escenario obligatorio lo exige; se deja como capacidad futura si se decide necesaria.
