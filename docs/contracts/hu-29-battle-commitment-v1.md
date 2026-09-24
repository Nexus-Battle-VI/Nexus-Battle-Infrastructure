# Contrato HU-29 — Compromiso de batalla del héroe (v1)

- **Estado:** **diseño.** Lo que este documento llame «implementado» solo lo estará cuando lo integren la Task [#232](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/232) (Player/Inventory y Combat). Hasta entonces todo lo de este documento es **diseño**. La verificación es la Task [#233](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/233).
- **Historia:** [HU-29 #76](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/76) · `RF-29` · Team Alfa · `ACT-02 — Preparar héroe, equipo e inventario` → `Consultar y equipar inventario`.
- **Diseño de la regla:** `Nexus-Battle-Player-Inventory/docs/hu-29-bloqueo-equipamiento-combate.md` (Task [#231](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/231), mergeado). Este contrato **no reabre** ese diseño: solo fija el transporte que el diseño dejó a la implementación.
- **Arquitectura aplicada, sin reabrirla:** [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md). Su tabla de integración ya decidió esta frontera: `Combat → Player/Inventory | Perfil de combate y compromiso del héroe al iniciar; liberar al terminar | Síncrono | operationId`. Este contrato **ejecuta** esa decisión; no la reinterpreta.
- **Contrato plantilla:** [hu-72-mission-enrollment-v1](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/132) y el compromiso de misión ya implementado (`POST /api/internal/v1/inventory/heroes/:heroId/commitments`, Player-Inventory PR [#50](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/50)). La forma se copia de ahí a propósito.

## 1. Qué resuelve este contrato, y qué no

**El problema.** HU-29 exige que, con una batalla activa, el equipamiento de entrada permanezca fijo: toda mutación de loadout se **rechaza**. Para saber si hay batalla activa, Player/Inventory necesita que **alguien se lo diga**: el estado de batalla pertenece al contexto de combate y Player/Inventory **no lo infiere ni lo consulta**.

**La solución.** Un **compromiso de batalla**: Combat compromete el héroe al **iniciar** la batalla y lo **libera** al **terminar**. Mientras el compromiso esté vigente, el héroe está «en batalla» y su loadout queda bloqueado.

**Lo que este contrato NO es:**

- **No es el estado de la sala.** No publica turnos, vida, orden ni resultado. Es una marca de ocupación: «este héroe está en una batalla».
- **No es un motor de batalla.** No decide cuándo empieza ni cuándo termina: lo decide Combat.
- **No reimplementa el compromiso de misión.** Es una ruta **hermana**, con su propio permiso y su propio cuerpo, para no ampliar la ruta de `missions` a `combat`.
- **No unifica todavía el «un héroe, un compromiso» entre propósitos.** Hoy un héroe podría quedar comprometido a `MISSION` y a `BATTLE` a la vez. Se deja escrito como límite conocido (§10) en lugar de inventar aquí la regla de exclusión cruzada, que toca la superficie de Missions.

## 2. Ownership (recap de ADR-019, no se reabre)

| Pieza | Dueño | Por qué |
| --- | --- | --- |
| El **ciclo de vida** de la batalla (inicio, fin, plazos) | **Combat** | Es su agregado |
| La **memoria** del compromiso (quién está ocupado y hasta cuándo) | **Player/Inventory** | `ADR-019` le asigna los compromisos del héroe y del ítem (`BATTLE`, `MISSION`, `AUCTION`, `TOURNAMENT`) |
| El **loadout** y su escritura | **Player/Inventory** (HU-28) | Una sola puerta de escritura |

Player/Inventory **no consulta** a Combat en el camino crítico del equipamiento: lee su propio compromiso, que es un dato local. Es exactamente el motivo por el que `ADR-019` eligió «compromiso publicado» y no «consulta al vecino».

## 3. Las dos operaciones internas

Servicio a servicio, nunca al cliente: firmadas con el HMAC-SHA256 de `ADR-019` (`x-internal-service`, `x-internal-timestamp`, `x-internal-signature`), `INTERNAL_SERVICE_AUTH_SECRET` compartido, y **no publicadas por Caddy** (`/api/internal*` responde `404` en el proxy).

Las dos llevan `@InternalOnly()` **y** `@InternalCallers('combat')`: el permiso se acota a **estas dos rutas**. La lista global de Player/Inventory (`commerce`, `notifications`, `combat`, `auction`) ya contiene `combat`, así que **el contrato no amplía ningún permiso**.

### 3.1 Comprometer al iniciar la batalla

```text
POST /api/internal/v1/inventory/heroes/{heroId}/battle-commitments
```

**Cuerpo:**

| Campo | Tipo | Obligatorio | Descripción |
| --- | --- | --- | --- |
| `operationId` | `string` (1..200) | sí | Clave de idempotencia del llamador. Combat usa el identificador estable de **su** compromiso; el mismo `operationId` con otro contenido es `409` |
| `playerId` | `string` (1..200) | sí | Jugador dueño del héroe |
| `reference` | `string` (1..200) | sí | Referencia del llamador: el `roomId` de la batalla. Es traza, no clave |
| `expiresAt` | `string` ISO-8601 | sí | Hasta cuándo vale el compromiso. **Obligatorio**: es lo que impide un bloqueo permanente si la liberación se pierde. Debe ser futura |

**Respuesta `201`:**

```json
{
  "commitmentId": "cmt_...",
  "heroId": "<productId canonico del heroe>",
  "purpose": "BATTLE",
  "reference": "room_...",
  "expiresAt": "2026-09-24T18:00:00.000Z"
}
```

**Idempotencia:** repetir la llamada con el **mismo** `operationId` y el **mismo** contenido devuelve `201` con el **mismo** compromiso (no crea otro). Con el mismo `operationId` y **otro** contenido devuelve `409 OPERATION_ID_REUSED` y **no** sobrescribe.

### 3.2 Liberar al terminar la batalla

```text
POST /api/internal/v1/inventory/battle-commitments/{operationId}/release
```

Sin cuerpo. **Respuesta `204`** tanto si el compromiso existía y se liberó como si ya no estaba: la liberación es **idempotente por definición**, porque un reintento tras un timeout es el caso normal, no la excepción.

## 4. Errores

| Código | `code` | Cuándo |
| --- | --- | --- |
| `400` | `SCHEMA_INVALID` | Cuerpo que no cumple el esquema, o `expiresAt` no futura |
| `401` | — | Sin firma válida, o servicio no autorizado para esta ruta |
| `409` | `OPERATION_ID_REUSED` | Mismo `operationId`, contenido distinto |
| `422` | `HERO_NOT_OWNED` | El héroe no es de ese jugador |
| `503` | `DEPENDENCY_UNAVAILABLE` | El servicio no puede confirmar la operación. **El llamador reintenta con el mismo `operationId`** |

Un `409` **no** se reintenta: es un defecto del llamador. Un `503` **sí**, y con la misma clave.

## 5. Caducidad, y por qué existe

`expiresAt` es obligatorio y **un compromiso caducado cuenta como inactivo**. La razón es la que el diseño de HU-29 nombra como riesgo: si la señal de fin se pierde —proceso caído entre persistir el fin y avisar—, un compromiso sin caducidad dejaría el loadout bloqueado **para siempre**. Con caducidad, el peor caso es un bloqueo que dura lo que dura la ventana declarada, y nunca un lock permanente.

El reconciliador de Combat (§7) es la primera defensa; la caducidad es la red debajo.

## 6. Efecto sobre el equipamiento: lo que ve el jugador

Este contrato es la **entrada**; la regla de HU-29 es la **salida**. Con un compromiso `BATTLE` vigente:

| Superficie | Efecto |
| --- | --- |
| `PUT /api/inventories/me/heroes/{heroId}/equipment/{slot}` | **`409`** con `{ "reason": "battle_lock", "message": "<explica que hay una batalla activa>" }`. El loadout **no se lee ni se escribe** |
| `GET /api/inventories/me/heroes/{heroId}/equipment` | Añade **`locked: boolean`**, para que la interfaz deshabilite el cambio **sin reimplementar la regla** |
| Cualquier categoría | Arma, armadura e ítem **por igual**: la categoría no cambia la decisión |
| Sin batalla, o batalla terminada | Esta regla **no interviene**: rige el flujo normal de HU-28 |

`reason` es el discriminador estable, y es deliberadamente **`reason`** y no `code`: es el nombre que fija el enunciado de la Task `#232` (`ok:false reason battle_lock`) y el que leerá la interfaz. El `message` es texto humano y **puede cambiar**; nadie debe ramificar por él.

**El copy exacto del mensaje sigue pendiente del PO**, como registra el diseño de HU-29 §11. Lo único contratado es que el mensaje **explica el motivo**.

## 7. Quién llama, y cuándo

| Momento | Quién | Qué hace |
| --- | --- | --- |
| La sala pasa a `IN_BATTLE` | Combat (`StartBattle`) | Compromete **cada** héroe participante, con su propio `operationId` |
| La sala queda `FINISHED` | Combat (`BattleFinalizer`, efectos posteriores de HU-21) | Libera los compromisos |
| Ventana entre «sala `FINISHED` persistida» y «efectos posteriores hechos» | Combat (`ReconcileRewardWorkflows`) | **Reintenta** la liberación. Es el mismo hueco que ese reconciliador ya cubre |

**Síncrono, y con consecuencia declarada:** al iniciar, si Player/Inventory no confirma el compromiso, **la batalla no arranca** (`503` al jugador). Es lo que decidió `ADR-019` con la palabra «Síncrono», y se acepta a cambio de que el bloqueo sea real y no una promesa.

## 8. Matriz de fallos parciales

| Qué falla | Qué queda | Qué se hace |
| --- | --- | --- |
| Comprometer: `503` | La sala no arranca | Combat reintenta la misma operación; el jugador ve `503` |
| Comprometer: respuesta perdida tras escribir | El compromiso existe | El reintento con el mismo `operationId` devuelve el mismo compromiso |
| Liberar: `503` o timeout | El compromiso sigue `ACTIVE` | El reconciliador reintenta; y si no, **caduca** por `expiresAt` |
| Combat cae entre `FINISHED` y la liberación | El compromiso sigue `ACTIVE` | Reconciliación al arrancar + caducidad |
| Player/Inventory responde a la liberación pero el proceso cae antes de registrarlo | El compromiso sigue `ACTIVE` | El reintento devuelve `204` sin efecto; convergen |

## 9. Seguridad

- **Permiso acotado por ruta**: `@InternalCallers('combat')` sobre estas dos rutas. **No** se amplía el allow-list global, que ya contiene `combat`.
- **Enumeración de héroes**: la comprobación de propiedad va **después** de resolver la propiedad del héroe en el caso de uso de equipar, no antes, para que el estado de batalla no se convierta en un canal para deducir héroes ajenos. La ruta interna sí responde `422 HERO_NOT_OWNED`, pero solo se expone a un servicio firmado.
- **Sin superficie pública nueva.** Web consume `locked` dentro de la ruta de equipamiento que ya existe.

## 10. Fuera de alcance, dicho

1. **Exclusión cruzada entre propósitos.** Que un héroe no pueda estar a la vez en `MISSION` y en `BATTLE` es una regla de producto que este contrato **no** implementa. Hoy no existe y no se finge que exista; queda como límite conocido.
2. **El copy del mensaje**, que decide el PO.
3. **Qué cuenta exactamente como «batalla activa» en el borde.** Este contrato transporta el compromiso; el borde lo fija Combat al decidir cuándo compromete. La lectura literal de la HU apunta a `IN_BATTLE`.
4. **La épica.** No entra en el bloqueo: la HU nombra arma, armadura e ítem, y HU-28 excluye `EPICA` de las categorías equipables.
5. **UI.** La pantalla es de Web; aquí solo se le da `locked`.

## 11. Compatibilidad y orden de despliegue

**Contract-first, y el orden importa:**

1. **Player/Inventory** publica las dos rutas y el guard. Antes de este paso, Combat no puede comprometer nada.
2. **Combat** empieza a comprometer y a liberar. **Antes de este paso, el bloqueo existe pero nunca se dispara**; después, se dispara para toda batalla nueva.
3. Ninguna ruta existente cambia de forma. `PUT` y `GET` de equipamiento **añaden** un comportamiento (`409 battle_lock`) y un campo (`locked`), y ningún consumidor actual se rompe: el `409` es un estado nuevo, y `locked` es aditivo.

**Compatibilidad hacia atrás:** mientras Combat no llame, el sistema se comporta exactamente como hoy. Es un despliegue seguro en cualquier orden, salvo que el bloqueo no protege hasta que ambos pasos están hechos —y eso queda dicho, no supuesto.
