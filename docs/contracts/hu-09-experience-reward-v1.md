# Contrato HU-09 — Recompensa de experiencia por derrota de un rival (v1)

- **Estado:** diseño de la Task [#439](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/439). Lo que este documento llame «implementado» solo lo estará cuando lo integren las Tasks [#440](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/440) (Combat), [#441](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/441) (Player-Inventory), [#442](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/442) (Missions) y [#443](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/443) (Web); la validación integrada es la Task [#444](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/444). Hasta entonces todo lo de este documento es **diseño**.
- **Historia:** [HU-09 #18](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/18) · `RF-09` · [EPIC-01 #1](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/1) · Team Alfa (Player/Inventory) + Team Beta (Missions) + Team Alfa (Combat) · `ACT-02 — Preparar héroe, equipo e inventario` → `Gestionar progresión y Poder`.
- **Bloqueada por:** `HU-08` ([#17](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/17)), **entregada en los PRs [Nexus-Battle-Player-Inventory#42](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/42), [#43](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/43) y [#44](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/44)**, pendientes de merge; y `HU-24` ([#71](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/71)), **cerrada**. Consume el umbral de niveles de HU-08 y el motor de aleatoriedad de HU-24 sin reabrir ninguno de los dos.
- **Arquitectura aplicada, sin reabrirla:** [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md) (Player/Inventory es dueño del estado del héroe y solo él escribe su Mongo; HMAC interno; listas cerradas de servicios por ruta) y [ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md) (Combat es la única autoridad de aleatoriedad; no hay `/random`, `/rng` ni `/seed`, ni microservicio de RNG).
- **Aclaración funcional del PO:** la fórmula `10 × 1,2^(1d8)` pertenece a la **muerte de un rival NPC en una misión (JvE)**; **no** se otorga por PvP ni por «Jugar Online». Missions coordina y calcula la recompensa; Combat no conoce la fórmula. Registrada en el comentario de trazabilidad de [#18](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/18).
- **Diagramas:** [caso de uso](../diagrams/hu-09-use-case.puml), [actividad](../diagrams/hu-09-activity.puml), [secuencia](../diagrams/hu-09-sequence.puml), [dominio](../diagrams/hu-09-domain.puml).
- **Contratos vecinos, referenciados y no reabiertos:** [hu-72-mission-simulation-v1](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/132) (**propuesta abierta, sin mergear**), [hu-74-mission-report-v1](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/135) (**propuesta abierta, sin mergear**) y [hu-22-reward-contract-v1](hu-22-reward-contract-v1.md) §7, que es la **plantilla** del endpoint interno de acreditación.

## 1. Qué exige la HU y qué no

**Requisito explícito (`RF-09`, Issue #18):**

- al terminar un combate con victoria se calcula y se acredita al héroe ganador una cantidad de experiencia igual a `10 × 1,2^(1d8)`;
- `1d8` es un entero pseudoaleatorio entre 1 y 8 obtenido del motor centralizado de HU-24; **HU-09 no lo genera localmente**;
- el valor de `1d8` se usa como **exponente**: no se suma ni se multiplica directamente;
- la experiencia se **acumula** a la que el héroe ya tenía; no la reemplaza;
- después de acreditarla se verifica el umbral del siguiente nivel con las reglas de **HU-08** y, si se alcanza, se ejecuta la progresión;
- si no existe un resultado válido que dé derecho a la recompensa, **no se otorga**.

### 1.1 Clasificación de lo decidido

| # | Tipo | Contenido |
| --- | --- | --- |
| 1 | Requisito explícito (Issue #18) | Fórmula `10 × 1,2^(1d8)`; `1d8` entero `1..8` del motor centralizado; la XP se acumula; se verifica el umbral tras acreditar; sin victoria válida no hay recompensa. |
| 2 | Aclaración funcional del PO (posterior al enunciado) | La fórmula es de **JvE (muerte de NPC en misión)**; PvP / «Jugar Online» **no** la otorga. Missions coordina y calcula; Combat solo tira; Player/Inventory solo acredita. |
| 3 | Decisión arquitectónica `Accepted`, reutilizada | ADR-019 (ownership y HMAC interno), ADR-021 (única autoridad de aleatoriedad). |
| 4 | Contrato existente, reutilizado como plantilla | `POST /api/internal/v1/inventory/grants` (Player-Inventory, HU-59/HU-69) para la forma del endpoint interno y del ledger idempotente. |
| 5 | Decisión técnica interna (este documento) | Forma exacta de las dos operaciones internas, `operationId` deterministas, estados de la recompensa en Missions, matriz de fallos y contrato de la tirada. |
| 6 | Fuera de alcance | HU-10 (recompensa por misión completada), HU-30 (caída de ítems), HU-32/HU-73 (épica por derrota de Máster), PvP, y `CA-06` de HU-08 (el nivel como multiplicador de estadísticas). |

## 2. Ownership (recap de ADR-019, no se reabre)

| Contexto | Dueño de |
| --- | --- |
| **Combat** | La aleatoriedad (HU-24/25), el resultado de la batalla o simulación, y **la producción de la tirada** de la recompensa. |
| **Missions** | El enfrentamiento JvE, la coordinación de la recompensa, **el cálculo de la fórmula** y el estado de la recompensa. |
| **Player/Inventory** | El nivel, la experiencia acumulada y la acreditación persistida e idempotente. |
| **Web** | Presentar lo que los servicios devuelven. No calcula nada. |
| **Infrastructure** | Este contrato y sus diagramas. |

**Prohibido, y es la parte que más fácilmente se rompe:**

- Combat **no** conoce `10 × 1,2^(1d8)` ni ningún importe de experiencia. Devuelve la tirada.
- Missions **no** genera aleatoriedad de ninguna clase, ni usa `Math.random`, ni guarda una semilla.
- Player/Inventory **no** redondea, **no** aplica la fórmula y **no** conoce el `1d8` como regla: recibe un importe entero.
- Nadie lee la base de datos de otro contexto.

## 3. Reparto, paso a paso

| # | Quién | Qué hace | Dónde vive |
| --- | --- | --- | --- |
| 1 | Missions | Ejecuta la misión JvE y pide la simulación a Combat | `HU-72` |
| 2 | Combat | Simula y determina el resultado del enfrentamiento | `HU-72` |
| 3 | **Combat** | Obtiene el `1d8` con el motor centralizado, **lo persiste** y lo devuelve | §5 (Task `#440`) |
| 4 | **Missions** | Calcula `10 × 1,2^(1d8)`, lo redondea a entero y lo persiste | §6 (Task `#442`) |
| 5 | **Player/Inventory** | Acredita la XP, acumula y recalcula el nivel con la tabla de HU-08 | §7 (Task `#441`) |
| 6 | Missions | Marca la recompensa como acreditada y la refleja en el reporte | `HU-74` |

**La frontera con HU-10.** HU-09 otorga la experiencia **por derrota de un rival**. HU-10 ([#19](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/19)) otorga la recompensa de **misión completada** (créditos, productos, épicas y su propia línea de experiencia). El diseño del reporte de misión sitúa esa línea bajo HU-10; este contrato **no** la implementa ni la reserva.

## 4. Unidad de la recompensa (decisión abierta `P-1`)

**Pregunta al PO:** ¿un `1d8` **por rival derrotado** (el ejemplo de HU-72 enumera 19 NPC en cinco encuentros) o **uno por victoria** de combate/misión?

**Propuesta, marcada como provisional:** **uno por victoria sobre un rival**. Es la lectura literal de `CA-01` («Resultado *victoria* de la batalla; identificador del héroe ganador») y de `CA-03`, que habla de **una** cantidad por ejecución de «Otorgar experiencia por derrota de un rival». No se ha encontrado en el Issue ninguna redacción que pida una tirada por enemigo.

**Efecto en el contrato:** el `operationId` de la tirada (§5) incorpora `rivalRef`. Si el PO resuelve «una por victoria», `rivalRef` pasa a identificar al rival decisivo del encuentro y el resto del contrato **no cambia**; si resuelve «una por enemigo derrotado», el mismo esquema se aplica una vez por `enemyRef` de `summary.enemiesDefeated[]` y tampoco cambia nada más. Por eso la decisión puede quedar abierta sin bloquear el diseño.

## 5. La tirada: contrato Missions → Combat

### 5.1 De dónde sale el número

```text
RandomSequencePort.nextIndex()  (HU-24, MISMA secuencia de proceso que turnos y ataques)
        ↓
BoundedRandom(sequence).nextInt(8) + 1   →   1d8 ∈ {1..8}, uniforme y sin sesgo
```

`BoundedRandom.nextInt(bound)` usa muestreo por rechazo, así que el reparto es uniforme. **No** hay una secuencia por batalla ni por misión: es la única secuencia del proceso, sembrada al arrancar con `COMBAT_RANDOM_SEED` (HU-26), y HU-09 consume de ella igual que HU-17, HU-18, HU-19 y HU-22. Consecuencia aceptada y escrita: **el orden de consumo importa** y el `1d8` de HU-09 comparte cursor con los turnos, los ataques y el cofre.

### 5.2 Operación interna

```text
POST /api/internal/v1/combat/experience-rolls
```

Cabeceras del esquema vigente de ADR-019: `x-internal-service: missions`, `x-internal-timestamp`, `x-internal-signature` (HMAC-SHA256 sobre JSON canónico), secreto `INTERNAL_SERVICE_AUTH_SECRET` y lista cerrada de servicios por ruta. `/api/internal*` responde `404` desde Caddy.

```jsonc
{
  "schemaVersion": 1,
  "operationId": "mission:{enrollmentId}:rival:{rivalRef}:xp-roll", // determinista, la cadena literal, SIN hashear
  "enrollmentId": "enr_01JB8Y3K7Q",
  "simulationId": "sim_01JB8Y4B",
  "heroId": "7f3c2a9e-2d4b-4c1a-9e7f-1b2c3d4e5f60",
  "rivalRef": "guardian-eterno",
  "defeatedAt": "2026-10-02T03:00:04Z"
}
```

```jsonc
{
  "schemaVersion": 1,
  "operationId": "mission:{enrollmentId}:rival:{rivalRef}:xp-roll",
  "roll": 5,                        // entero 1..8
  "applied": true,                  // false si es un replay idempotente del mismo operationId+cuerpo
  "persistedAt": "2026-10-02T03:00:04.120Z"
}
```

| HTTP | `code` | Cuándo | Qué hace Missions |
| --- | --- | --- | --- |
| `200` | — | Tirada hecha, o repetida con el mismo `operationId` y el mismo cuerpo | Guarda y pasa a `ROLLED` |
| `400` | `SCHEMA_INVALID` | El cuerpo no cumple el esquema | `FAILED` y alerta |
| `401` | `INTERNAL_SIGNATURE_INVALID` | Firma ausente o inválida | Alerta; no reintenta |
| `409` | `OPERATION_ID_REUSED` | El `operationId` llegó con otro cuerpo | `FAILED` y alerta |
| `422` | `HERO_NOT_ELIGIBLE` | El héroe no puede recibir la recompensa | `FAILED`; no reintenta |
| `503` | `ROLL_UNAVAILABLE` | Combat no puede atender ahora | Reintenta con el **mismo** `operationId` |

**La tirada se persiste antes de responder.** Es la garantía de que un reintento de Missions —o un reinicio de Combat— **no vuelve a consumir el cursor aleatorio**: un segundo `1d8` daría otra recompensa por el mismo hecho.

### 5.3 Por qué una operación propia y no un campo de la simulación de HU-72

| Opción | Contenido | Valoración |
| --- | --- | --- |
| **A** | Extender la respuesta de `POST /api/internal/v1/combat/simulations` (HU-72) con la tirada | Un viaje menos, pero **acopla HU-09 a un contrato que aún no está mergeado** (PR #132) y obliga a producir la tirada dentro de la simulación, incluso cuando el resultado no da derecho a recompensa |
| **B (elegida)** | Operación propia de Combat, invocada por Missions **después** de saber que hubo victoria | Desacopla HU-09 de HU-72, mantiene intacto el contrato de simulación, permite persistir la tirada antes de cualquier efecto remoto y es directamente verificable con `operationId` |

**No es exponer aleatoriedad**, que es lo que `ADR-021` prohíbe: la operación no acepta un rango, no devuelve el índice ni la semilla, no es parametrizable y es idempotente por `operationId`. Es una operación de dominio («resolver la tirada de la recompensa de esta derrota»), el mismo criterio con el que HU-22 resuelve el cofre dentro de Combat.

## 6. La fórmula y el redondeo

**Dueño único: Missions.** Ni Combat ni Player/Inventory contienen la expresión.

```text
experiencia = redondear(10 × 1,2^(1d8))     con 1d8 ∈ {1..8}
```

| `1d8` | Valor exacto | Al entero más próximo (**propuesta**) | Con truncamiento (alternativa) |
| ---: | ---: | ---: | ---: |
| 1 | 12 | **12** | 12 |
| 2 | 14,4 | **14** | 14 |
| 3 | 17,28 | **17** | 17 |
| 4 | 20,736 | **21** | 20 |
| 5 | 24,8832 | **25** | 24 |
| 6 | 29,85984 | **30** | 29 |
| 7 | 35,831808 | **36** | 35 |
| 8 | 42,9981696 | **43** | 42 |

**`P-2` — decisión abierta.** El PO describió el redondeo **al entero más próximo** y ofreció el **truncamiento** como alternativa; ninguna de las dos está fijada por escrito en el Issue. El contrato adopta el redondeo al más próximo **como provisional** y la implementación debe dejar la regla en un único punto (la política pura de Missions) para que cambiarla no toque nada más.

**La experiencia que cruza la frontera es siempre entera.** La tabla de umbrales de HU-08 está en enteros y comparar un acumulado fraccionario con ella sería una fuente de errores de frontera imposible de justificar. Player/Inventory **rechaza** un importe no entero en lugar de redondearlo por su cuenta.

**Nota de aritmética:** con `1d8 = 8` la recompensa es `43`, y el umbral del nivel 1→2 es `200` (HU-08). Una sola victoria **no** sube de nivel a un héroe recién creado; sí puede subirlo si ya estaba cerca del umbral, y una sola acreditación puede cruzar **más de un umbral** si el acumulado previo lo permite.

## 7. La acreditación: contrato Missions → Player/Inventory

Se modela sobre el contrato ya implementado de HU-59/HU-69 (`POST /api/internal/v1/inventory/grants`, Player-Inventory) **sin reutilizar su ruta**: la experiencia no es un producto del inventario.

```text
POST /api/internal/v1/players/{playerId}/heroes/{heroId}/experience
```

Mismas cabeceras internas que §5.2, con `x-internal-service: missions`.

```jsonc
{
  "schemaVersion": 1,
  "operationId": "mission:{enrollmentId}:rival:{rivalRef}:hero:{heroId}:xp", // determinista, sin hashear
  "amount": 25,                       // entero; ya redondeado por Missions
  "source": {
    "kind": "MISSION_RIVAL_DEFEAT",
    "enrollmentId": "enr_01JB8Y3K7Q",
    "simulationId": "sim_01JB8Y4B",
    "rivalRef": "guardian-eterno",
    "roll": 5
  }
}
```

```jsonc
{
  "operationId": "…",
  "applied": true,          // false en un replay idempotente
  "heroId": "…",
  "level": 4,
  "currentXp": 890,         // ACUMULADO total; nunca se descuenta
  "leveledUp": true,
  "levelsGained": 1,
  "nextLevel": { "status": "AVAILABLE", "forNextLevel": 5, "amount": 1600 },
  "maxLevel": 8
}
```

`nextLevel` y `maxLevel` son **derivados en la lectura** con `thresholdForNextLevel()` de HU-08; no se persisten y no forman parte de la clave de idempotencia.

| HTTP | `code` | Cuándo |
| --- | --- | --- |
| `200` | — | Acreditado, o repetido con el mismo `operationId` y el mismo cuerpo |
| `400` | `SCHEMA_INVALID` | El cuerpo no cumple el esquema |
| `401` | `INTERNAL_SIGNATURE_INVALID` | Firma ausente o inválida |
| `409` | `EXPERIENCE_GRANT_CONFLICT` | El mismo `operationId` llegó con otro cuerpo |
| `422` | `EXPERIENCE_GRANT_REJECTED` | Importe no entero o negativo, o héroe no acreditable |
| `503` | `PLAYER_INVENTORY_UNAVAILABLE` | El servicio no puede atender ahora |

**Servicio permitido.** El allow-list global de Player/Inventory es hoy `['commerce', 'notifications', 'combat']` y **no incluye `missions`**. La ruta se protege con `@InternalOnly()` **y** `@InternalCallers('missions')`, que acota el permiso a esta ruta concreta **sin** ampliar el allow-list global: el mecanismo ya existe (`INTERNAL_CALLERS`) y es el de menor privilegio.

**Ledger y transacción.** La acreditación escribe un documento de ledger con `_id = operationId` (único) y actualiza la progresión **en la misma transacción**, como `GrantPurchasedItems`. El `_id` del documento de progresión sigue siendo `"<ownerId>::<heroId>"` (HU-08) y el bloqueo optimista sigue siendo responsabilidad del repositorio.

**Creación perezosa.** Un héroe sin documento de progresión se interpreta como nivel 1 con 0 (HU-08) y la acreditación crea el documento. No hay backfill.

## 8. Idempotencia (resumen)

| Operación | Clave | Mismo cuerpo | Cuerpo distinto |
| --- | --- | --- | --- |
| Missions → Combat (tirada) | `mission:{enrollmentId}:rival:{rivalRef}:xp-roll` | Misma tirada, `applied:false`. **No se vuelve a tirar** | `409 OPERATION_ID_REUSED` |
| Missions → Player/Inventory (acreditación) | `mission:{enrollmentId}:rival:{rivalRef}:hero:{heroId}:xp` | Mismo resultado, `applied:false`. **No se vuelve a acreditar** | `409 EXPERIENCE_GRANT_CONFLICT` |

**Semántica de entrega: al menos una vez, con efectos idempotentes.** No se promete transporte exactamente-una-vez, igual que HU-21 y HU-22. La regla que no se puede romper: **un reintento nunca cambia el resultado**.

## 9. Estados de la recompensa en Missions y fallos parciales

```text
PENDING ──► ROLLED ──► CREDITED
   │           │
   └───────────┴──► FAILED   (rechazo terminal o cuerpo incoherente)
```

| Estado | Significa | Se recupera tras reinicio |
| --- | --- | --- |
| `PENDING` | Recompensa creada; aún no se pidió la tirada | Reintenta `POST §5.2` con el mismo `operationId` |
| `ROLLED` | Tirada persistida en Combat; falta acreditar | Reintenta `POST §7` con el importe **ya calculado** y el mismo `operationId`; **no** vuelve a tirar |
| `CREDITED` | Terminal. La acreditación está confirmada | No-op |
| `FAILED` | Terminal. Rechazo definitivo (`422`) o cuerpo incoherente (`409`) | No reintenta solo; queda visible en observabilidad |

Cada transición se persiste **antes** de avanzar al paso siguiente, para que un reinicio recupere la recompensa donde quedó.

| Punto de falla | Estado persistido | Reintento | Resultado visible |
| --- | --- | --- | --- |
| Missions cae antes de pedir la tirada | `PENDING` | Sí, mismo `operationId` | Recompensa pendiente |
| Combat tira pero Missions cae antes de leer la respuesta | La tirada **ya está persistida** en Combat | Sí; el replay devuelve la **misma** tirada | Ninguno perdido |
| Missions calcula pero cae antes de acreditar | `ROLLED`, con el importe ya persistido | Sí, mismo `operationId` | Recompensa pendiente |
| Player/Inventory acredita pero Missions cae antes de leer la respuesta | Player/Inventory ya aplicó (idempotente) | Sí; el replay devuelve el mismo resultado | Ninguno perdido |
| Player/Inventory rechaza con `422` | `FAILED` | No automático | Sin experiencia; la misión no se revierte |
| Combat o Player/Inventory devuelven `503` | Se queda en el estado de origen | Sí, mismo `operationId` | Recompensa pendiente |

**Ningún fallo revierte la misión ni el resultado de la batalla**: la recompensa es un efecto posterior, no una condición del cierre.

## 10. Cómo se entera Web

Web **no** aplica la fórmula ni conoce la tabla de umbrales. Consume:

- el **reporte de misión** (`HU-74`), que ya prevé líneas de recompensa con tipo `EXPERIENCE` y estado (`PENDING`, `CREDITED`, `FAILED`), y
- el nivel y el acumulado que Missions devuelva con la recompensa confirmada.

La representación del **estado** es obligatoria: mostrar como concedida una recompensa `PENDING` es el error que el diseño de HU-74 (`P-T2`) ya quiso evitar separando la foto del reporte del estado de cada línea.

**Superficie pública:** este contrato **no** añade ninguna. Si `HU-09.5` necesita el nivel actual del héroe y el reporte no lo da, esa decisión se toma aquí y se convierte en una Task propia; **no** se inventa un endpoint público dentro de la Task de Web.

## 11. Seguridad

- Interno (`Missions → Combat`, `Missions → Player/Inventory`): HMAC-SHA256, ventana de sello, lista cerrada de servicios **por ruta**, y `/api/internal*` bloqueado en Caddy.
- `missions` **no** entra en el allow-list global de Player/Inventory: se acota con `@InternalCallers('missions')` en la ruta de experiencia, que es el permiso mínimo suficiente.
- El `heroId` y el `playerId` viajan en la ruta porque el llamante es un servicio autenticado; nunca se aceptan de un cliente.
- No se registran secretos HMAC ni el estado interno del generador. Sí se correlacionan `enrollmentId`, `operationId`, `roll` y estado.
- **No se expone la semilla** en ninguna respuesta (HU-24/ADR-021), y la operación de tirada no acepta rango ni parámetros de azar.

## 12. Fuera de alcance

- **HU-10** ([#19](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/19)): recompensas por misión completada, incluida su línea de experiencia en el reporte.
- **HU-30** ([#77](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/77)): probabilidad de caída de ítems.
- **HU-32/HU-73**: épica obtenida por derrota de un Máster.
- **PvP / «Jugar Online»**: no otorga experiencia por esta fórmula.
- **`CA-06` de HU-08**: el nivel como multiplicador de estadísticas base; sigue sin implementar y sin ser de esta historia.
- Cambios a HU-21 (notificación de fin de batalla), HU-24/25/26 (motor y tablas) y al contrato de simulación de HU-72.

## 13. Compatibilidad y orden de despliegue

**Aditivo.** Ningún mensaje existente cambia de forma y ninguna ruta existente se modifica.

**Orden:** Infrastructure (este contrato) → **Player/Inventory** (`#441`: ruta interna, ledger y `@InternalCallers`) → **Combat** (`#440`: operación de tirada y su colección) → **Missions** (`#442`: coordinación, política y estado) → **Web** (`#443`). Missions no debe llamar a un contrato que Combat o Player/Inventory todavía no exponen.

**Dependencias de calendario, dichas sin adornos:** `#442` no puede existir antes que el flujo de misión (`HU-72.2`, [#374](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/374)) ni antes del reporte (`HU-74.2`, [#380](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/380)), y **Missions no tiene hoy ninguna ruta de negocio ni ninguna tabla**. `#441` no puede compilar hasta que HU-08 esté en `develop`.

## 14. Casos límite

| Caso | Comportamiento exigido |
| --- | --- |
| Sin victoria válida (`CA-08`) | No se crea recompensa, no se pide tirada, no se acredita |
| Participante `AI` o `heroId` nulo | No hay beneficiario: no hay recompensa |
| Reintento con el mismo `operationId` | Misma tirada y misma acreditación; nunca se vuelve a tirar |
| `operationId` repetido con otro cuerpo | `409` en la frontera correspondiente |
| Una acreditación cruza dos o más umbrales | Sube al nivel más alto alcanzado (HU-08, `levelFromTotalXp`) |
| Héroe ya en nivel 8 | La experiencia sigue creciendo y **no se descarta**; no se rechaza |
| Importe no entero | `422`: el redondeo ocurre en Missions, antes de la frontera |
| El héroe no pertenece al jugador indicado | `422`; no se acredita a un héroe ajeno |
| Combat o Player/Inventory caídos | Reintento con el mismo `operationId`; la recompensa queda pendiente |
| Rechazo terminal (`422`) | `FAILED`; no se reintenta solo y la misión no se revierte |

## 15. Decisiones abiertas

| # | Decisión | Estado en este contrato | Efecto si cambia |
| --- | --- | --- | --- |
| `P-1` | Una tirada **por rival derrotado** o **una por victoria** | Provisional: **una por victoria sobre un rival** | Solo cambia cuántas veces se invoca §5.2; el resto del contrato no se mueve |
| `P-2` | Redondeo **al más próximo** o **truncamiento** | Provisional: **al más próximo** | Cambia un valor por cada `1d8` (`21`↔`20`, `25`↔`24`, `30`↔`29`, `36`↔`35`, `43`↔`42`); la regla vive en un único punto |
| `P-3` | Corrección del enunciado de #18 (restringir a JvE y añadir la cadena de Misiones como dependencia) | Pendiente del PO | No afecta al diseño; afecta a la trazabilidad |

**Las tres se registran aquí en lugar de resolverse en silencio.** Si el PO confirma los valores provisionales, este contrato pasa a `v1` cerrado sin cambiar ninguna forma.
