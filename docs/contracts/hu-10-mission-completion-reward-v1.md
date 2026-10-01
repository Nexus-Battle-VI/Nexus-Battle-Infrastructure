# Contrato HU-10 — Liquidación de recompensas de finalización de misión (v1)

- **Estado:** **implementado y verificado técnicamente por HU-10.7.** Las integraciones de Player-Inventory, Wallet, Missions y Web están en `develop`; la cadena [HU-10.7 #457](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/457) registró 18 `PASS`, 0 `FAILED` y 2 `SKIPPED` declarados. Ver [evidencia final](../evidence/HU-10-recompensas-finalizacion-mision.md). Esto **no** cierra la HU ni sustituye aceptación humana.
- **Task:** [HU-10.1 #451](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/451).
- **Historia:** [HU-10 #19](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/19) · `RF-10` · [EPIC-08 #8](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/8) · Team Beta (Missions) + Team Alfa (Player-Inventory, Web) + Team Gama (Wallet).
- **Repositorios implicados:** Missions (dueño de la liquidación), Player-Inventory (XP y productos), Wallet (créditos), Web (presentación). Combat y Catalog: **solo regresión**.
- **Arquitectura aplicada, sin reabrirla:** [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md) (Missions → Player/Inventory «recompensas» y Missions → Wallet «acreditar recompensas en créditos», ambas síncronas por `operationId`; sin transacciones distribuidas) y [ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md) (Combat, única autoridad de aleatoriedad). **ADR-019 ya soporta este diseño y no se modifica.**
- **Dependencias (contratos vigentes, referenciados y no reabiertos):** [HU-08](../evidence/HU-08-calculo-de-experiencia-requerida-por-nivel.md) (progresión y umbrales), [HU-09](hu-09-experience-reward-v1.md) (XP por derrota; patrón de coordinación), [HU-72](hu-72-mission-simulation-v1.md) (resultado sellado, contenido congelado y botín ya sorteado), [HU-73](hu-73-master-encounter-v1.md) (épica de Máster), [HU-74](hu-74-mission-report-v1.md) (reporte y líneas de recompensa), [HU-75](hu-75-mission-difficulty-v1.md) (dificultad y `rewardTier`), [HU-22](hu-22-reward-contract-v1.md) (solo como **contraste**: es JcJ y no se reutiliza).
- **Diagramas:** [secuencia](../diagrams/hu-10-sequence-mission-reward.puml) · [estados](../diagrams/hu-10-state-mission-reward.puml).
- **Cómo leer este contrato.** Cada afirmación lleva su origen: **[PO]** requisito o aclaración de Management #19/#451; **[ADR]** decisión arquitectónica aceptada; **[VIGENTE]** contrato o código ya en `develop`; **[PROPUESTA HU-10.1]** decisión técnica nueva que este contrato propone y que **no viene del PO**; **[PENDIENTE]** decisión funcional que este contrato **no toma** (§19).

## 1. Qué exige HU-10 y qué NO

**Exige** [PO #19]:

- **XP de finalización** de la misión, **adicional y distinta** de la XP por derrota de HU-09;
- **créditos** y **productos/recompensas garantizadas** que estén **configurados** para la misión y la dificultad ejecutada;
- **bonificaciones** por objetivos y de primera vez **cuando estén configuradas** y sean elegibles;
- uso de la **dificultad realmente ejecutada** y del **snapshot** de configuración de esa ejecución (una edición posterior del contenido no cambia una liquidación);
- entrega al **jugador y héroe registrados en la matrícula** (nunca ids de Web);
- estado real de cada línea en el **reporte** (`PENDING | CREDITED | FAILED`);
- **idempotencia** y recuperación por línea.

**NO exige, porque ya pertenece a otra HU** [PO #19 / VIGENTE]:

| Tema | Dueño | Consecuencia para HU-10 |
| --- | --- | --- |
| XP por cada NPC derrotado, fórmula `10 × 1,2^(1d8)` | HU-09 | HU-10 **no** la recalcula ni reutiliza `MISSION_RIVAL_DEFEAT` |
| Sortear el botín del jefe | HU-72 / Combat | HU-10 **no** sortea: consume el resultado ya sellado (§11) |
| Conceder la épica de Máster | HU-73 | HU-10 **no** decide aparición, derrota ni épica, y **no** la vuelve a conceder (§11) |
| Recalcular el reporte completo | HU-74 | HU-10 solo **añade líneas** y mueve su estado |
| Reglas de desbloqueo de dificultad | HU-75 | HU-10 usa la dificultad ejecutada; no decide desbloqueos |
| Nueva fuente de aleatoriedad | Combat (ADR-021) | HU-10 no usa `Math.random` ni otro RNG |
| Recalcular el nivel | Player-Inventory (HU-08) | Missions solo guarda la progresión que Player-Inventory devuelve |
| Cofres y títulos de misión | — | **No** se crean automáticamente [PO #19] |

## 2. Clasificación de lo decidido

| # | Tipo | Contenido |
| --- | --- | --- |
| 1 | Requisito de Management #19 | Liquidación por resultado final válido; XP de finalización para `COMPLETED` **y** `FAILED`; `IN_PROGRESS` y `VOIDED` no liquidan; montos de la configuración de la misión/dificultad **congelada**; identidad de la matrícula; idempotencia; sin duplicar botín ni épica; créditos sin tocar progreso de victoria ni cofres de HU-22. |
| 2 | Requisito de Management #451 | Este contrato; XP de finalización con fuente distinta de HU-09; operación de créditos de misión sin efectos JcJ; reutilizar `inventory/grants`; snapshot, idempotencia, matriz de errores; sin montos inventados. |
| 3 | Decisión arquitectónica `Accepted`, reutilizada | ADR-019 (contextos, HMAC interno, lista cerrada de servicios, «sin transacción distribuida»: intención local → llamada → resultado → reintento idempotente) y ADR-021. |
| 4 | Contratos vigentes reutilizados | `POST /api/internal/v1/inventory/grants` (autoriza a `missions`), la ruta de experiencia de HU-09 (evolucionada, §8), el reporte de HU-74 (`mission_report_rewards`, origen `HU-10` ya admitido), los patrones de coordinación de HU-09 y de entrega de HU-72/HU-73. |
| 5 | **Decisiones técnicas nuevas [PROPUESTA HU-10.1]** | Fuente `MISSION_COMPLETION` (§8); operación `POST /api/internal/v1/wallet/credits/mission-reward` (§9); forma de la configuración liquidable `rewards.completion` (§6); liquidación congelada en el cierre (§4); claves de idempotencia (§12); clasificación de errores (§13). |
| 6 | **Pendientes funcionales [PENDIENTE]** | `ABANDONED`; créditos/productos garantizados en `FAILED`; definición de «primera vez»; montos concretos (§19). |

## 3. Ownership definitivo

| Contexto | Responsabilidad en HU-10 |
| --- | --- |
| **Missions** | Elegibilidad por desenlace; **snapshot** y cálculo de derechos a partir de la configuración congelada; persistir la liquidación y sus líneas; workflow, reintentos y estado de cada línea del reporte; guardar la progresión que devuelve Player-Inventory. |
| **Player-Inventory** | XP acumulada y nivel del héroe (HU-08) y entrega de productos al inventario, ambos **idempotentes** y con su propio ledger. |
| **Wallet** | Saldo y ledger de créditos, idempotente por `operationId`. |
| **Combat** | Resultado de la simulación y botín ya sorteado; **única** autoridad de RNG. HU-10 no le pide nada nuevo. |
| **Web** | Presentar el reporte y el historial. **No** calcula montos, umbrales ni elegibilidad. |
| **Infrastructure** | Este contrato, diagramas y evidencia. |

**Prohibiciones** (deben poder verificarse con pruebas de HU-10.2 a HU-10.7):

- Missions **no** escribe saldo, **no** escribe inventario, **no** recalcula nivel y **no** genera aleatoriedad.
- Wallet **no** conoce objetivos, dificultades ni misiones más allá de la trazabilidad que recibe.
- Player-Inventory **no** decide dificultad ni elegibilidad.
- Web **no** calcula recompensas.
- Ningún servicio lee ni escribe la base de otro.
- Ningún cliente público (Web) puede provocar una acreditación ni elegir a quién se acredita.

## 4. Modelo conceptual: la liquidación por matrícula

Una **liquidación** (`MissionRewardSettlement`) es el conjunto de **derechos de recompensa de finalización** de **una matrícula**, calculados **una sola vez** y congelados.

- **Identidad lógica** [PROPUESTA]: `mission:{enrollmentId}:settlement`, coherente con las convenciones vigentes (`mission:{enrollmentId}:xp-rolls` de HU-09). Es una identidad **interna de Missions** (su clave primaria es `enrollment_id`): **no viaja** a otros contextos, que reciben las claves por línea de §12.
- **Cuándo nace:** en la **misma transacción del cierre** de la misión (`RunMissionExecutions.close`), junto con las líneas del reporte, las recompensas de HU-09 y las entregas de botín/épica, y **solo** si el desenlace es `COMPLETED` o `FAILED`. La anulación (`voidMission`) **no** crea liquidación. Igual que HU-09 §9.1: **se persiste la intención antes de llamar a nadie**.
- **De dónde salen los valores:** de la **definición congelada de la ejecución** (`execution.request.contentSnapshot`, HU-72), **nunca** del catálogo vivo ni de una tabla global.

### 4.1 Qué se congela

| Campo | Origen | Nota |
| --- | --- | --- |
| `enrollmentId`, `missionId` | Matrícula | |
| `playerId`, `heroId` | **Matrícula** | Único origen del beneficiario (CA-10) |
| `simulationId` | Resultado sellado (HU-72) | Trazabilidad |
| `missionOutcome` | Liquidación de HU-72 | `COMPLETED` \| `FAILED` |
| `difficulty` | Matrícula | La **ejecutada**; no se relee |
| `rewardTier` | `scalingOf(difficulty)` de HU-75 en el momento del cierre | Es un descriptor determinista, pero **se congela como evidencia** |
| `objectives[].met` | `MissionSettled` (HU-72) | Base de las bonificaciones por objetivo |
| `rewardsConfig` | `contentSnapshot.rewards.completion` (§6) | Copia íntegra + huella `sha256` de su JSON canónico |
| `settledAt` | Reloj de Missions al cerrar | **Es el `occurredAt` de toda llamada a Wallet** (§9): no se recalcula en un reintento |
| `entitlements[]` | Derivado de lo anterior | `rewardKey`, `kind`, `amount`/`quantity`, `productId`, elegibilidad y motivo |

**Lo que hace imposible el error de CA-06** («inicio → el administrador cambia el premio → termina → el jugador recibe el valor nuevo»): los `entitlements` se calculan **una vez, al cerrar, desde el `contentSnapshot`**, y **desde ese momento nadie vuelve a leer la configuración**. Cada reintento reenvía **el valor congelado**. Además, el contenido de la ejecución ya está congelado desde que se pidió la simulación (HU-72; «una misión que ya se simuló conserva los productos con los que se simuló»).

**Ejecución sin `contentSnapshot`** [PROPUESTA]: hoy `close()` cae al catálogo vivo si la ejecución no lo trae (`contentSnapshot` es opcional en el tipo). Para HU-10 **eso no es aceptable**: usaría valores que no son los de la ejecución. En ese caso la liquidación se crea **sin derechos** con motivo `SNAPSHOT_MISSING` y se informa; **no** se liquida contra contenido vivo.

### 4.2 Estado agregado (derivado, no almacenado)

| Estado de la liquidación | Condición sobre sus líneas |
| --- | --- |
| `NOT_APPLICABLE` | No hay ningún derecho (nada configurado, o ninguno elegible) |
| `SETTLING` | Alguna línea `PENDING` |
| `SETTLED` | Todas `CREDITED` |
| `SETTLED_WITH_FAILURES` | Ninguna `PENDING` y alguna `FAILED` |

Se **deriva** de las líneas, igual que el resumen de experiencia de HU-09: un total guardado aparte acabaría contradiciendo sus líneas.

## 5. Semántica por desenlace

| Desenlace | XP de finalización | Créditos / productos / bonificaciones | Observación |
| --- | --- | --- | --- |
| `IN_PROGRESS` | **No** | **No** | No hay resultado final: no hay liquidación [PO] |
| `COMPLETED` | **Sí**, si hay monto configurado | Según **configuración** y elegibilidad (§6) | Desenlace final válido |
| `FAILED` | **Sí**, si hay monto configurado [PO] | **No se infiere.** Solo si la entrada configurada lo declara (`grantOn`, §6) | Management cerró explícitamente **solo** la XP para `FAILED`. Que créditos/garantizados apliquen en `FAILED` es **[PENDIENTE] P-HU10-3** |
| `VOIDED` | **No** | **No** | Ejecución técnica anulada [PO]: no hay liquidación, no hay reporte |
| `ABANDONED` | **[PENDIENTE] P-HU10-1** | **[PENDIENTE] P-HU10-1** | Ver §19. El contrato **no** inventa comportamiento |

**Nota sobre `ABANDONED`.** El vocabulario del reporte y de la matrícula lo contiene, pero **hoy Missions no tiene ningún camino que lo produzca** (no hay flujo de cancelación en `develop`). Un diseño previo registra una respuesta del PO sobre cancelar («el héroe queda cansado un tercio de la duración y **no recibe recompensas**», [misiones-jugabilidad](../architecture/misiones-jugabilidad.md)) que queda marcada «fuera de este diseño» y **no está formalizada en #19**. Este contrato **la cita como antecedente y no la adopta**: la matriz solo garantiza que **el motor de liquidación no se dispara para un desenlace que no reconoce** (lista cerrada `COMPLETED | FAILED`), de modo que `ABANDONED` sigue sin liquidar hasta que exista la regla.

**Regla técnica** [PROPUESTA]: la liquidación se dispara por **lista cerrada** de desenlaces, no por exclusión. Un desenlace desconocido no liquida.

## 6. Configuración liquidable de recompensas

**Hoy** `MissionDefinition.rewards` es `{ guaranteed: RewardLabel[], potential: PotentialReward[], objectiveBonuses: RewardLabel[], firstTime: RewardLabel[] }`. `guaranteed`, `objectiveBonuses` y `firstTime` son **etiquetas de texto** (`{ label: "50 créditos" }`): **no son liquidables** y nunca se parsean. `potential` es el botín del jefe (ya con `productId`, ver §11). La definición se guarda en `jsonb`.

**Diseño mínimo, aditivo y sin migración de datos** [PROPUESTA]: un bloque **opcional** `rewards.completion`, junto a lo existente. Las etiquetas siguen siendo **informativas** (lo que el jugador ve en el tablón); **lo que se liquida es solo `completion`**. Un contenido sin `completion` no genera derechos.

```jsonc
"rewards": {
  "guaranteed": [ { "label": "…" } ],          // texto informativo, NO liquidable
  "potential": [ /* botín del jefe: HU-72 */ ],
  "objectiveBonuses": [],                      // texto informativo
  "firstTime": [],                             // texto informativo
  "completion": {                              // ← NUEVO, opcional (HU-10.4)
    "schemaVersion": 1,
    "experience": { "amountByDifficulty": { "NORMAL": <int>=1>, "HEROIC": <int>, "LEGENDARY": <int>, "MYTHIC": <int> } },
    "entries": [
      {
        "key": "<slug único en la misión>",
        "group": "GUARANTEED | OBJECTIVE_BONUS | FIRST_TIME",
        "grantOn": ["COMPLETED"],              // desenlaces en los que aplica; OBLIGATORIO, sin valor por defecto
        "objectiveId": "<solo OBJECTIVE_BONUS: id de un objetivo del mismo contenido>",
        "reward": { "kind": "CREDITS", "amountByDifficulty": { "NORMAL": <int>=1> } }
                 // o { "kind": "PRODUCT", "productId": "<uuid Catalog>", "quantityByDifficulty": { "NORMAL": <1..9999> } }
      }
    ]
  }
}
```

Reglas de la forma (todas **técnicas**; ninguna fija un monto):

| Regla | Detalle |
| --- | --- |
| **Sin valor por defecto** | Si la dificultad ejecutada **no** figura en `amountByDifficulty`/`quantityByDifficulty`, **no hay derecho** para esa línea. **No** se usa otra dificultad, un múltiplo ni un valor global. |
| **Sin tabla global** | El contrato **no** define «Normal = X, Heroico = Y». Los números viven **solo** en el contenido aprobado de cada misión y quedan congelados (§4). |
| **`rewardTier`** | Es evidencia del snapshot; **no** es una tabla de montos. |
| **`grantOn` obligatorio** | Cada entrada declara los desenlaces en los que aplica. El motor **no** decide «los créditos se dan en `FAILED`» ni «no se dan»: lo dice el contenido aprobado. Falta o vacío → entrada **no liquidable**. *(Qué valores aprueba el PO es [PENDIENTE] P-HU10-3.)* |
| **XP** | `experience` no lleva `grantOn`: se liquida en `COMPLETED` y `FAILED` [PO]. |
| **Bonificación por objetivo** | Elegible si `MissionSettled.objectives[objectiveId].met === true`. `null` (no aplicó) y `false` no dan derecho. `objectiveId` debe existir en el mismo contenido. |
| **Primera vez** | La estructura existe (`FIRST_TIME`), pero **no es liquidable hasta que el PO defina «primera vez»** [PENDIENTE] P-HU10-4. Restricción técnica ya fijada: la elegibilidad se evalúa **dentro de la transacción del cierre y antes de insertar el *clear* de HU-75**, y se congela como evidencia. |
| **Cofres y títulos** | No existen como tipo de recompensa: **fuera** [PO]. |
| **Producto** | `productId` UUID de Catalog, `quantity` `1..9999` (los límites de `inventory/grants`). Un producto = una línea. |
| **Créditos** | Entero `≥ 1`. La **cota superior** es una guarda técnica de HU-10.3 (rango seguro de `bigint`), **no** una regla económica. |
| **Claves** | `key` cumple `^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$`, único por misión; no se reutiliza para otro contenido. Es parte de la clave de idempotencia (§12). |

**El ejemplo académico de «50 créditos» del Templo Olvidado** aparece hoy como **etiqueta** (`guaranteed: [{ label: '50 créditos' }, …]`, y `firstTime: [{ label: '10 créditos adicionales' }]`). **No es una regla universal ni un monto de este contrato.** Solo podrá aparecer como `completion.entries[…].reward.amountByDifficulty.NORMAL = 50` **si el contenido vigente de esa misión lo adopta explícitamente** (HU-10.4) y con el `grantOn` que apruebe el PO.

## 7. Modelo de líneas del reporte

HU-10 **coexiste** con las líneas de HU-09/72/73 en `mission_report_rewards` (clave `(enrollment_id, line_no)`). El origen `HU-10` **ya está admitido** por la restricción vigente; `quantity ≥ 0` ya está permitido.

| Origen | `kind` | Quién la escribe | Ciclo |
| --- | --- | --- | --- |
| `HU-09` | `EXPERIENCE` | Coordinación de HU-09 | Una por NPC derrotado |
| `HU-72` | `PRODUCT` | `GrantMissionLoot` | Botín del jefe |
| `HU-73` | `EPIC` | `GrantMasterEpics` | Épica del Máster |
| **`HU-10`** | **`EXPERIENCE`** | Liquidación de HU-10 | **Una**: XP de finalización |
| **`HU-10`** | **`CREDITS`** | Liquidación de HU-10 | Una por entrada de créditos |
| **`HU-10`** | **`PRODUCT`** | Liquidación de HU-10 | Una por entrada de producto |

**No hay líneas HU-10 de tipo `EPIC`**, y **no** hay líneas `HU-10` que dupliquen un `PRODUCT` de `HU-72` (§11). El **origen es parte de la clave semántica** de la línea (HU-09 §5): una línea `HU-10` solo la mueve la liquidación de HU-10.

| Campo | Valor en una línea HU-10 |
| --- | --- |
| `lineNo` | Siguiente libre, **detrás** de las de HU-73, HU-09 y HU-72 (orden estable de creación) |
| `kind` | `EXPERIENCE` \| `CREDITS` \| `PRODUCT` |
| `source` | `HU-10` |
| `reference` | La **`rewardKey`** (§12), estable e independiente del orden |
| `name` | Nombre legible del contenido (sin identificadores técnicos en la vista) |
| `quantity` | El **derecho congelado** (XP, créditos o unidades). **Nace con su valor**, a diferencia de HU-09 (cuyo importe lo decide una tirada posterior) |
| `status` | `PENDING` → `CREDITED` \| `FAILED` |
| `progression` | Solo en la línea `EXPERIENCE` de HU-10 y solo cuando está `CREDITED`, **tal como la devolvió Player-Inventory** (nivel, XP acumulada, nivel máximo, niveles cruzados). Nunca se calcula ni se completa en Missions |
| `updatedAt` | Momento del último cambio de estado |
| vínculo con la operación | La entrega asociada (§13) guarda `operationId`, intentos y último error; la línea y la entrega se mueven **en la misma transacción** (como HU-09 y HU-72) |

**«Derecho calculado», «entrega pendiente» y «entrega acreditada» no se confunden** [CA-09]:

| Concepto | Dónde vive |
| --- | --- |
| **Derecho calculado** | En la liquidación congelada (§4.1 `entitlements`), y en `quantity` de la línea |
| **Entrega pendiente** | Línea `PENDING` (+ su entrega con intentos y `nextAttemptAt`) |
| **Entrega acreditada** | Línea `CREDITED` — **solo** tras la confirmación del contexto dueño |
| **Rechazo terminal** | Línea `FAILED` con su motivo |

Una línea `PENDING` **nunca** se presenta como concedida. Un derecho que **no** es elegible (p. ej. crédito con `grantOn: ["COMPLETED"]` en una misión `FAILED`) **no genera línea**: no hay derecho que mostrar.

## 8. Missions → Player-Inventory: XP de finalización

**Evolución del endpoint vigente** (no una ruta nueva) [PROPUESTA]:

```text
POST /api/internal/v1/players/{playerId}/heroes/{heroId}/experience
```

Mismas cabeceras (`x-internal-service: missions`, `x-internal-timestamp`, `x-internal-signature`), misma autorización `@InternalOnly()` + `@InternalCallers('missions')`, mismos códigos (§8.2). `playerId` y `heroId` viajan **en la ruta** y salen **de la matrícula**.

### 8.1 Fuente distinta de HU-09

La ruta hoy solo acepta `source.kind = MISSION_RIVAL_DEFEAT` (validación `@IsIn`, tipo `ExperienceGrantSource` y guarda de dominio), con campos que solo tienen sentido para una derrota (`encounterId`, `enemyInstanceId`, `rivalRef`, `roll`). El código deja previsto que otro origen exigirá cambios. **HU-10 NO reutiliza ese origen ni inventa una derrota ficticia.** Se añade un **origen discriminado por `kind`**:

```jsonc
{
  "schemaVersion": 1,
  "operationId": "mission:{enrollmentId}:reward:completion:xp",
  "amount": 120,                              // entero ≥ 0 ya congelado por Missions; Player-Inventory no lo calcula
  "source": {
    "kind": "MISSION_COMPLETION",
    "enrollmentId": "enr_01JB8Y3K7Q",
    "missionId": "msn_templo_olvidado",
    "simulationId": "sim_01JB8Y4B",
    "difficulty": "NORMAL",
    "missionOutcome": "COMPLETED"             // COMPLETED | FAILED
  }
}
```

- **Sin** `encounterId`, `enemyInstanceId`, `rivalRef` ni `roll` en este origen. Cada `kind` tiene **su propio conjunto de campos obligatorios y prohibidos**: un `MISSION_COMPLETION` con `roll` (o un `MISSION_RIVAL_DEFEAT` sin él) es `400 SCHEMA_INVALID`.
- `MISSION_COMPLETION` es el nombre propuesto porque describe el hecho (finalización) sin sugerir victoria y **no colisiona** con el vocabulario vigente (`MISSION_RIVAL_DEFEAT`). Si HU-10.2 encuentra una convención mejor, lo cambia **aquí primero**.
- La respuesta **no cambia** (`operationId`, `applied`, `heroId`, `level`, `currentXp`, `leveledUp`, `levelsGained`, `nextLevel`, `maxLevel`): la progresión sale de la única autoridad, HU-08. Missions la guarda en la línea y **no** la recalcula.
- **Cambios internos que HU-10.2 debe absorber** (verificados en el código actual, no en este contrato): el ledger `experience_grants` guarda el origen **aplanado** con campos de derrota y `roll`; su documento y su huella (`fingerprint`) hoy asumen un único origen. Para `MISSION_COMPLETION` la huella debe incluir `kind` y sus campos propios, y la lectura del ledger debe distinguir el origen. **Los asientos de HU-09 existentes no se migran ni cambian.**
- Un `amount` de `0` sería válido para Player-Inventory, pero una línea de HU-10 **no se crea** con derecho `< 1` (§6).

### 8.2 Códigos y qué hace Missions

| HTTP | `code` | Significado | Missions (línea de XP) |
| --- | --- | --- | --- |
| `200` | — (`applied: true`) | Acreditado | `CREDITED` + guarda la progresión |
| `200` | — (`applied: false`) | Replay exacto: ya estaba acreditado | `CREDITED` (igual que `true`); **no** vuelve a acreditar |
| `400` | `SCHEMA_INVALID` | Cuerpo fuera del contrato | `FAILED` terminal + alerta (error de programación) |
| `401` | `INTERNAL_SIGNATURE_INVALID` (o sin `code`) | Firma/servicio no válido | **`PENDING` con alerta** (§13: es un problema de despliegue, no del derecho) |
| `409` | `EXPERIENCE_GRANT_CONFLICT` | Mismo `operationId`, contenido distinto | `FAILED` terminal + alerta (no puede ocurrir con un derecho congelado; indica un defecto) |
| `422` | `EXPERIENCE_GRANT_REJECTED` | Importe no entero o negativo, o héroe no acreditable | `FAILED` terminal |
| `503` | `PLAYER_INVENTORY_UNAVAILABLE` | No se pudo atender (incluye colisión de versión de la progresión) | `PENDING`; reintenta con el **mismo** `operationId` |
| timeout / red / respuesta ilegible | — | Resultado **incierto** | `PENDING`; reintenta con el **mismo** `operationId` |

En esta ruta `409` **solo** significa conflicto de contenido (la colisión concurrente responde `503`), así que es terminal sin ambigüedad.

## 9. Missions → Wallet: créditos de misión

### 9.1 Por qué una operación propia (justificación de la alternativa elegida)

`POST /api/internal/v1/wallet/credits/battle-reward` **pertenece a HU-21/HU-22 (JcJ)** y **no** se reutiliza. Verificado en el código actual de Wallet:

| Rasgo de `battle-reward` | Por qué no sirve para una misión |
| --- | --- |
| Catálogo **cerrado** de importes `{1, 2, 4}` y `victoryCreditsAmount ∈ {0,1,2,4}` | Los créditos de misión son contenido configurable, sin esa escala |
| Recalcula **progreso de victoria, semana y cofre** en la misma transacción (`computeNextWalletState`), y su respuesta devuelve `victoryProgress`, `weeklyChestCount`, `weekIdentity`, `chestEarned` | Una misión **no es una victoria JcJ** [PO]: no puede tocar esos campos ni el cambio de semana |
| Ledger `wallet_ledger` con `battle_id NOT NULL`, `victory_credits_amount`, `resulting_victory_progress`, `resulting_week_identity`, `chest_earned` | Un crédito de misión no tiene batalla ni progreso de victoria |
| `@InternalOnly()` **sin lista de servicios** | Ver §9.4 (hallazgo de seguridad) |

**Alternativas evaluadas.** (A) reutilizar `battle-reward` con `victoryCreditsAmount = 0`: **descartada**, sigue pasando por la lógica de semana/cofre y mezcla dos semánticas; (B) generalizar `battle-reward` (campos opcionales, ramas por `reason`): **descartada**, cambia un contrato productivo de HU-22 y acopla dos dominios; (C) **operación específica con su propio asiento de ledger** (patrón ya usado por Wallet para comisiones de publicación, retenciones y transferencias de subasta, cada una con su tabla y su `operation_id` único): **elegida**.

### 9.2 Operación

```text
POST /api/internal/v1/wallet/credits/mission-reward          [PROPUESTA]
x-internal-service: missions   (@InternalOnly('missions'), lista de ruta)
```

```jsonc
{
  "schemaVersion": 1,
  "operationId": "mission:enr_01JB8Y3K7Q:reward:guaranteed:credits",
  "playerId": "cognito-sub-del-jugador",       // de la matrícula
  "reason": "MISSION_REWARD",
  "enrollmentId": "enr_01JB8Y3K7Q",
  "missionId": "msn_templo_olvidado",
  "difficulty": "NORMAL",
  "rewardKey": "guaranteed:credits",
  "creditsAmount": 50,                         // entero ≥ 1, congelado por Missions; Wallet no lo calcula
  "occurredAt": "2026-10-02T03:00:05.000Z"     // = settledAt congelado; idéntico en cada reintento
}
```

```jsonc
{ "operationId": "…", "applied": true, "balance": 1250 }
```

- **Respuesta mínima:** `operationId`, `applied`, `balance`. **No** devuelve ni altera `victoryProgress`, `weeklyChestCount`, `weeklyChestLimit`, `weekIdentity` ni `chestEarned`. **HU-10.3 debe probar** que un crédito de misión **no cambia** ninguno de esos estados en `wallet_accounts` (aunque el jugador esté a un crédito del cofre, aunque cambie la semana).
- **Ledger:** asiento **insert-only** propio (no reutiliza las columnas de victoria), con `operation_id` **único**, y `balance` actualizado **en la misma transacción**. Incrementa **solo** `balance`; no toca `reserved`, progreso ni contador semanal.
- **Idempotencia:** misma `operationId` + **mismo contenido** (incluido `occurredAt`, `rewardKey`, importe y jugador) → replay `applied: false` con el **mismo** `balance` resultante del asiento original; contenido distinto → `409`. Por eso `occurredAt` se **congela** en la liquidación: un reintento con «ahora» produciría un `409` falso.
- **Alcance de la ruta:** solo acredita (`creditsAmount ≥ 1`). No hay débito, reserva ni reembolso de misión en HU-10.

### 9.3 Códigos (patrón vigente de Wallet)

| HTTP | `code` | Cuándo | Missions (línea de créditos) |
| --- | --- | --- | --- |
| `200` | — (`applied: true`) | Primera aplicación | `CREDITED` |
| `200` | — (`applied: false`) | Replay exacto | `CREDITED`; **no** vuelve a acreditar |
| `409` | `OPERATION_CONFLICT` | Mismo `operationId`, contenido distinto | `FAILED` terminal + alerta (defecto: el derecho está congelado) |
| `422` | `MISSION_REWARD_INVALID` *(nombre propuesto; sigue el estilo `*_INVALID` de Wallet)* | Importe fuera de contrato o rechazo terminal por contrato | `FAILED` terminal |
| `400` | `SCHEMA_INVALID` | Cuerpo fuera del contrato | `FAILED` terminal + alerta |
| `401` | firma inválida / servicio no permitido / sin secreto (`503`) | Fail-closed | **`PENDING` con alerta** (§13) |
| `503` | `DEPENDENCY_UNAVAILABLE` | Resultado no confirmable | `PENDING`; reintenta con el **mismo** `operationId` |
| timeout / red | — | Incierto | `PENDING`; **mismo** `operationId` |

### 9.4 Seguridad: hallazgo sobre la autorización vigente de Wallet

Wallet mantiene una lista global de servicios (`INTERNAL_CALLERS = ['auction', 'combat', 'missions']`) y **cada ruta** la acota con `@InternalOnly('<servicio>')`. `WalletInternalController` (`battle-reward`) usa `@InternalOnly()` **sin argumentos** —su comentario dice «solo `combat`»— y, con el guard actual, **cualquier servicio de la lista global (incluido `missions`) puede llamarla**. **Es una divergencia entre lo documentado y lo implementado.** Este contrato **no** la corrige (no cambia el contrato productivo de HU-22) pero **exige que HU-10.3 la cierre** (`@InternalOnly('combat')`) con su prueba, para que Missions **solo** pueda usar `mission-reward`. Ver §20.

## 10. Productos de finalización

**Se reutiliza `POST /api/internal/v1/inventory/grants`** (Player-Inventory; `@InternalCallers('commerce','notifications','combat','missions')`). **No se crea un endpoint nuevo:** cubre `operationId`, jugador, producto, cantidad, idempotencia y conflicto.

```jsonc
{
  "operationId": "<UUID v5>",                   // ver §12: este endpoint EXIGE UUID
  "playerId": "cognito-sub-del-jugador",        // de la matrícula
  "items": [ { "productId": "<uuid de Catalog>", "quantity": 1 } ]   // un producto por línea HU-10
}
```

- Tipos de recompensa de HU-10 que lo usan: `GUARANTEED`, `OBJECTIVE_BONUS` y `FIRST_TIME` **de tipo `PRODUCT`**, **solo si están estructuradas y configuradas** (§6).
- El **botín de HU-72** y la **épica de HU-73** siguen **su** flujo y **no** pasan por HU-10 (§11).
- **Semántica de `409` (ambigua por diseño de Player-Inventory):** ese endpoint responde `409` **tanto** por el mismo `operationId` con otro cuerpo **como** por una escritura concurrente sobre el inventario. Con un derecho congelado el cuerpo **no puede** cambiar entre reintentos, así que Missions lo trata como **incierto**, igual que el cliente de la épica (`409` → desconocido): **reintenta con el mismo `operationId`**, con alerta si persiste.

| HTTP | Missions (línea `PRODUCT`) |
| --- | --- |
| `200`, `applied: true` **o** replay con el mismo `operationId` | `CREDITED` |
| `422 INVENTORY_REJECTED`, `400` | `FAILED` terminal (p. ej. producto inexistente de forma definitiva; lo confirma HU-10.5 con el código real) |
| `409`, `401`, `404`, `5xx`, timeout, red, respuesta ilegible | `PENDING`; reintenta con el **mismo** `operationId` |

## 11. Botín aleatorio (HU-72) y épica de Máster (HU-73): frontera explícita

**Botín aleatorio.**

- **Definición**: `finalBoss.drops[]` (etiqueta, probabilidad, tiradas, `productId`) en el contenido.
- **Sorteo**: lo hace **Combat dentro de la simulación** (HU-72) con su motor centralizado. El resultado ya trae `loot: [{ label, productId, quantity }]`.
- **Entrega**: `GrantMissionLoot` ya la coordina (línea `PRODUCT` de origen `HU-72`, `operationId = uuidV5(enrollmentId:loot:label)`).
- **HU-10 NO hace**: `Math.random()`, un `nextInt()`, una segunda llamada a Combat para «volver a elegir», ni una segunda línea `PRODUCT` por el mismo botín. Solo **consume/refleja** el resultado y su estado en la vista completa de recompensas.

**Épica de Máster.**

- HU-73 es la autoridad del **derecho** (aparición, derrota, elección de la épica) y de su entrega (`GrantMasterEpics`, línea `EPIC` de origen `HU-73`, `operationId` UUID v5 propio).
- HU-10 **no** decide nada de eso y **no** concede la épica. Cuando exista, la línea `EPIC` de HU-73 **ya forma parte** del reporte.

**Cómo se garantiza que no haya doble entrega:**

1. **Sin línea HU-10 equivalente:** la configuración `completion` no admite entradas para botín del jefe ni épicas de Máster (no hay `kind` para ellas).
2. **Espacio de claves disjunto:** las claves de HU-10 (§12) llevan el prefijo `mission:{enrollmentId}:reward:` y usan un **namespace UUID v5 propio**, distinto de `LOOT_GRANT_NAMESPACE` (HU-72) y del de HU-73. Una colisión con un `operationId` ajeno es imposible por construcción.
3. **Regla de contenido:** un mismo `productId` **puede** aparecer como botín de HU-72 y como recompensa de HU-10 (son derechos distintos y entregas distintas con claves distintas); **eso es una decisión de contenido**, no un doble derecho. El contrato solo impide que **un mismo derecho** se entregue dos veces.

## 12. Idempotencia: claves deterministas

**Convención real verificada:** HU-09 usa **cadenas** `mission:{enrollmentId}:…` (XP y lote de tiradas); Wallet acepta cadenas de hasta 200 caracteres; **Player-Inventory `inventory/grants` exige UUID** y el botín/épica usan **UUID v5** sobre una cadena con un namespace fijo. HU-10 sigue esas convenciones.

**Clave lógica de una línea** [PROPUESTA]:

```text
mission:{enrollmentId}:reward:{group}:{key}
```

`group` ∈ `completion` (XP) · `guaranteed` · `objective-bonus` · `first-time`; `key` es el slug del contenido (`xp` para la XP de finalización).

| Línea | `operationId` en el cable | Destino |
| --- | --- | --- |
| XP de finalización | `mission:{enrollmentId}:reward:completion:xp` | Player-Inventory `…/experience` |
| Créditos | `mission:{enrollmentId}:reward:{group}:{key}` | Wallet `…/credits/mission-reward` |
| Producto | `uuidV5(NAMESPACE_HU10, "mission:{enrollmentId}:reward:{group}:{key}")` | Player-Inventory `inventory/grants` |
| Liquidación (interna) | `mission:{enrollmentId}:settlement` | Solo Missions (PK `enrollment_id`) |

**`NAMESPACE_HU10`** [PROPUESTA] = `7565c40b-1f2b-4854-bfde-124bf8c7db44` (UUID propio, distinto del de HU-72; se fija aquí para que Missions y las pruebas de los otros repos calculen el mismo `operationId`).

Reglas:

| Caso | Resultado |
| --- | --- |
| Mismo `operationId` + mismo contenido | **Replay estable** (`applied: false`); no duplica |
| Mismo `operationId` + contenido distinto | **Conflicto** (`409`) |
| Falla un producto después de acreditar créditos | El crédito **no se vuelve a tocar** (su línea ya está `CREDITED` y no se reintenta) |
| Wallet caído con un producto ya entregado | El producto **no se vuelve a entregar** (su línea ya está `CREDITED`) |

**Granularidad:** una operación por línea, **no** una clave única por liquidación, para que un fallo parcial no obligue a reejecutar todo.

## 13. Estados del workflow y clasificación de errores

Cada línea es independiente (sin saga compleja):

```text
PENDING ──► CREDITED                       (confirmación del contexto dueño)
PENDING ──► FAILED                         (rechazo terminal, con motivo)
PENDING ──► PENDING (intentos+1, nextAttemptAt)   (incierto o no disponible)
```

Reintento con el **escalonado que ya usan HU-09, HU-72 y el botín** (`retryDelayMs`), y **siempre con el mismo `operationId` y el mismo cuerpo congelado**.

| Clase | Condiciones | Efecto |
| --- | --- | --- |
| **REINTENTABLE** (`PENDING`) | timeout · error de red · respuesta ilegible · `503` · `409` **de inventario** (ambiguo, §10) · `404`/`5xx` · **`401`/servicio no permitido** (problema de despliegue: **no** se destruye un derecho por una clave mal rotada; se alerta) | Se conserva el derecho y se reintenta |
| **TERMINAL** (`FAILED`) | `422` contractual · `400 SCHEMA_INVALID` · `409` de conflicto **inequívoco** (XP: `EXPERIENCE_GRANT_CONFLICT`; Wallet: `OPERATION_CONFLICT`) · producto inexistente definitivo (`422 INVENTORY_REJECTED`) | Línea `FAILED`; **las demás líneas siguen** |
| **PROHIBIDO** | Tratar un resultado ambiguo como «no ocurrió» y **volver a acreditar desde cero con otra clave** | — |

**Divergencia declarada con HU-09.** El cliente de XP de HU-09 trata `401` como rechazo definitivo (`REJECTED`). Para HU-10 se propone **no** hacerlo: una firma inválida es de configuración, no del derecho del jugador. **HU-10.2/10.5 confirman** que el cliente de XP de HU-10 se comporte así sin cambiar el de HU-09.

**Reproceso de líneas `FAILED`:** el contrato **no** define un reproceso manual o administrativo; queda como decisión técnica abierta (§19, T-1). Una línea `FAILED` es terminal para el barrido.

**Cierre no se revierte:** ningún fallo revierte la misión ni el resultado (igual que HU-09): la recompensa es un efecto posterior, no una condición del cierre.

## 14. Matriz de fallos

| Dependencia | Resultado | Missions hace | Línea |
| --- | --- | --- | --- |
| Player-Inventory · XP | `200 applied:true` | Guarda progresión | `CREDITED` |
| Player-Inventory · XP | `200 applied:false` (replay) | Igual que `true`; no reacredita | `CREDITED` |
| Player-Inventory · XP | `409 EXPERIENCE_GRANT_CONFLICT` | Alerta; no reintenta | `FAILED` |
| Player-Inventory · XP | `422 EXPERIENCE_GRANT_REJECTED` | No reintenta | `FAILED` |
| Player-Inventory · XP | `400 SCHEMA_INVALID` | Alerta; no reintenta | `FAILED` |
| Player-Inventory · XP | `503` / timeout / red | Reintenta, **mismo** `operationId` | `PENDING` |
| Player-Inventory · XP | `401` | Alerta; reintenta tras el escalonado | `PENDING` |
| Player-Inventory · producto | `200 applied:true` | — | `CREDITED` |
| Player-Inventory · producto | replay (mismo `operationId`) | — | `CREDITED` |
| Player-Inventory · producto | `422 INVENTORY_REJECTED` / `400` | No reintenta | `FAILED` |
| Player-Inventory · producto | `409` (ambiguo) / `5xx` / timeout | Reintenta, **mismo** `operationId`; alerta si persiste | `PENDING` |
| Wallet · créditos | `200 applied:true` | — | `CREDITED` |
| Wallet · créditos | `200 applied:false` (replay) | No reacredita | `CREDITED` |
| Wallet · créditos | `409 OPERATION_CONFLICT` | Alerta; no reintenta | `FAILED` |
| Wallet · créditos | `422` / `400` | No reintenta | `FAILED` |
| Wallet · créditos | `503` / timeout / red | Reintenta, **mismo** `operationId` y **mismo** `occurredAt` | `PENDING` |
| Wallet · créditos | `401` / servicio no permitido | Alerta; reintenta tras el escalonado | `PENDING` |
| Missions cae tras persistir la liquidación, antes de llamar | Líneas `PENDING` | El barrido las retoma | `PENDING` |
| Missions cae tras la llamada, antes de guardar la respuesta | Dependencia ya aplicó | Reintento con la **misma** clave → replay `applied:false` | `PENDING` → `CREDITED` |
| Una línea falla y otra se acreditó | — | Conserva lo confirmado, reintenta **solo** lo pendiente | Independientes |

**Regla que no se rompe:** si el resultado de una dependencia es **incierto**, **no** se asume que «no ocurrió»: se reintenta con el **mismo** `operationId`.

## 15. Seguridad

- Todas las rutas son **internas**: `/api/internal/v1/…`, cabeceras `x-internal-service`, `x-internal-timestamp`, `x-internal-signature` (HMAC-SHA256 sobre JSON canónico, ventana de 30 s), **lista cerrada de servicios por ruta**, **fail-closed** (sin secreto o firma inválida, se niega) y **bloqueo en Caddy** (`/api/internal*` responde `404` desde fuera). Cada llamada lleva sello y firma nuevos; **el cuerpo, no**.
- `playerId` y `heroId` salen de la **matrícula** (y del snapshot), **nunca** de Web.
- Los **montos** salen del **snapshot** de Missions; **ningún** cliente público envía ni influye en un monto.
- **No se diseña ningún endpoint público** para acreditar recompensas.
- No se registran secretos HMAC. Sí se correlacionan `enrollmentId`, `operationId`, `rewardKey` y estado.
- Wallet: `mission-reward` acotado a `missions` (§9.4). Player-Inventory: XP acotada a `missions` (ya vigente) e `inventory/grants` ya autoriza a `missions`.

## 16. Consistencia (ADR-019)

**Sin** 2PC, transacción común, cross-database ni rollback de una base ajena:

```text
1. persistir la intención local (liquidación + líneas PENDING + entregas), en la transacción del cierre
2. llamar al contexto dueño con el operationId de la línea
3. persistir el resultado devuelto (línea + entrega + progresión), en UNA transacción
4. si el resultado es incierto → reintentar con el MISMO operationId
```

Si una parte se acredita y otra falla, **se conserva la parte confirmada** y se reintenta **solo** lo pendiente.

## 17. Reporte: cómo se ven las líneas HU-10

- `rewards[]` de `GET /api/v1/missions/me/reports/{enrollmentId}` **ya** expone `kind`, `reference`, `name`, `rarity`, `quantity`, `status` y `source` (el tipo de Web ya reconoce `CREDITS | PRODUCT | EPIC | EXPERIENCE` y el origen `HU-10`). Las líneas HU-10 aparecen ahí **sin cambiar el contrato existente**.
- **Cambio aditivo propuesto:** `rewards[].progression` (opcional, `null` salvo en la línea `EXPERIENCE` de origen `HU-10` **acreditada**), con la progresión que devolvió Player-Inventory. Hoy la vista pública **no** expone la progresión por línea (solo el bloque `experience`), así que sin esto la Web tendría que **recalcular** el nivel, que es justo lo prohibido.
- **El bloque `experience` no cambia:** se deriva **solo** de líneas `HU-09` (su filtro es `source = 'HU-09'`), de modo que la XP de finalización **no** infla `defeats` ni `totalXp` de derrotas. La XP de finalización se presenta por su propia línea.
- La foto del reporte sigue **inmutable** (HU-74 P-T2): solo cambia el estado de las líneas.
- Web **no** calcula montos, elegibilidad ni nivel; refresca el reporte mientras haya líneas `PENDING` (la política de refresco es de HU-10.6).

## 18. Matriz de criterios de aceptación → contrato → futuro escenario

Los escenarios **pertenecen a HU-10.2 a HU-10.7 y todavía no existen**.

| CA | Sección | Futuro escenario (Task) |
| --- | --- | --- |
| CA-01 Liquidación principal | §4, §7, §12 | Cierre `COMPLETED` con XP+créditos+producto: una liquidación, líneas `PENDING`→`CREDITED`, una vez, al jugador/héroe de la matrícula (10.5, 10.7) |
| CA-02 XP de finalización | §5, §8 | `COMPLETED` y `FAILED` acreditan el monto configurado con `MISSION_COMPLETION`; no usa `MISSION_RIVAL_DEFEAT`; `MISSION_COMPLETION` con `roll` → 400 (10.2, 10.5) |
| CA-03 Créditos | §9 | Crédito de misión aumenta el saldo una vez; ledger trazado; `victoryProgress`, `weeklyChestCount`, `chestEarned` **sin cambios**, incluso a 1 crédito del cofre y en cambio de semana (10.3) |
| CA-04 Productos garantizados | §6, §10 | Producto configurado y elegible → `inventory/grants` una vez; línea con estado real (10.5) |
| CA-05 Sin duplicar botín/épica | §11 | Cierre con botín y épica: ninguna llamada nueva a Combat/RNG, ninguna línea HU-10 duplicada, mismas claves de HU-72/HU-73 (10.5, 10.7) |
| CA-06 Snapshot | §4.1, §6 | Editar el contenido tras el cierre no cambia montos ni reenvíos; ejecución sin snapshot → sin derechos (10.4, 10.5) |
| CA-07 Idempotencia y recuperación | §12–§14 | Replay `applied:false`; caída de Wallet/PI: solo continúan las `PENDING`; crédito acreditado no se reenvía si falla un producto (10.2, 10.3, 10.5, 10.7) |
| CA-08 No liquidables | §5 | `IN_PROGRESS` y `VOIDED` no crean liquidación ni líneas; desenlace desconocido no liquida (10.5) |
| CA-09 Reporte e historial | §7, §17 | Líneas HU-10 con `PENDING\|CREDITED\|FAILED` reales; progresión de la línea; Web no recalcula (10.5, 10.6) |
| CA-10 Identidad | §3, §8, §9, §15 | Beneficiario = jugador/héroe de la matrícula; un cuerpo o ruta con otro id no se genera; ninguna entrega a otro jugador (10.2, 10.3, 10.5) |
| CA-11 Aceptación | §19 | Pruebas positivas, negativas y de frontera; contratos alineados; cadena verde (10.7) |

## 19. Decisiones funcionales pendientes que HU-10.1 NO inventa

| # | Pregunta | Por qué está abierta | ¿Bloquea? |
| --- | --- | --- | --- |
| **P-HU10-1** | ¿Qué liquida HU-10 cuando el desenlace es `ABANDONED`? | #19 no la define. Hay un antecedente sin formalizar («no recibe recompensas») y hoy **ningún flujo produce** `ABANDONED` | **No.** El motor liquida solo `COMPLETED`/`FAILED` (§5). Solo bloquea el día que exista un flujo de cancelación |
| **P-HU10-2** | ¿Cuáles son los **montos** de XP de finalización, créditos, productos garantizados, bonificaciones y primera vez, por misión y dificultad? | #19 dice expresamente que **no** hay tabla global: son contenido aprobado | **No bloquea el diseño ni 10.2/10.3.** Sí condiciona el **contenido** de 10.4 (sin montos aprobados, ninguna misión genera derechos) |
| **P-HU10-3** | ¿En qué desenlaces aplican créditos y productos **garantizados** y las bonificaciones (`COMPLETED` solo, o también `FAILED`)? | Management cerró **solo** la XP para `FAILED` | **No bloquea la forma:** `grantOn` es obligatorio y explícito en el contenido. Sí condiciona qué valores aprueba el PO para 10.4 |
| **P-HU10-4** | ¿Qué es «primera vez»: primera finalización de la misión, o por dificultad? ¿Solo `COMPLETED`? | #19 no lo define | **No bloquea** 10.2/10.3/10.5 para XP, créditos y productos garantizados. `FIRST_TIME` **no es liquidable** hasta responderla |
| **T-1** (técnica) | ¿Existe reproceso manual de una línea `FAILED`? | El contrato la trata como terminal para el barrido; no define un camino administrativo | No |
| **T-2** (técnica) | Umbral de alerta por `409`/`401` persistentes | Depende de la operación (10.5) | No |

**No se agregan preguntas que el código o Management ya resuelven** (p. ej. si `VOIDED` liquida, si HU-10 reutiliza `MISSION_RIVAL_DEFEAT` o si sortea botín: ya están decididas).

## 20. Contradicciones y documentación obsoleta encontradas

Detalle de auditoría en el **Anexo A**. Resumen:

| # | Hallazgo | Tratamiento |
| --- | --- | --- |
| 1 | `WalletInternalController` (`battle-reward`) usa `@InternalOnly()` sin lista; su comentario dice «solo `combat`» y el guard actual admite a `missions` | **Exigido a HU-10.3** (§9.4). No se cambia aquí |
| 2 | La documentación de HU-72 decía que el botín aleatorio de HU-10 «debe salir del generador de Combat: ¿se sortea dentro de la simulación?» y que los objetivos de botín «esperan a HU-10» | **Corregido en este PR**: el sorteo **ya ocurre dentro de la simulación de HU-72** y `COLLECT_LOOT` existe en el código; HU-10 solo consolida |
| 3 | La documentación de HU-72/HU-74/HU-75 presenta «montos y `rewardTier`» como pendientes de HU-10 | **Aclarado en este PR**: HU-10 define la **forma**; los montos siguen siendo contenido aprobado (P-HU10-2) |
| 4 | El contrato de HU-74 muestra `{ "kind": "CREDITS", "quantity": 50, "source": "HU-10" }` como ejemplo | Es un **valor ilustrativo** de HU-74 (ya lo dice); no es regla. Se deja tal cual |
| 5 | `close()` cae al catálogo vivo si la ejecución no tiene `contentSnapshot` | Incompatible con CA-06 para HU-10: §4.1 exige no liquidar contra contenido vivo |
| 6 | `GrantMissionLoot` toma el `productId` del **contenido vigente** si Combat no lo devolvió y aún no está congelado | Es comportamiento de HU-72 (**no se reabre**); se anota porque los productos de HU-10 se congelan al cerrar y no repiten ese patrón |
| 7 | El cliente de XP de HU-09 trata `401` como terminal | HU-10 propone otro criterio (§13); no se cambia HU-09 |

## 21. Compatibilidad y orden de implementación

**Aditivo.** Ningún mensaje existente cambia de forma: la ruta de XP añade un `kind`; Wallet añade una ruta; el reporte añade un campo opcional; la definición añade un bloque opcional.

**Orden** (el de #19): **HU-10.1 (este contrato)** → **HU-10.2** (XP en Player-Inventory) + **HU-10.3** (Wallet) + **HU-10.4** (configuración congelada en Missions, en paralelo) → **HU-10.5** (liquidación en Missions) → **HU-10.6** (Web) → **HU-10.7** (E2E). Missions **no debe llamar** a una operación que Player-Inventory o Wallet aún no expongan; hasta entonces, las líneas de HU-10 no se crean.

**Salida de la Task (no incluye código):** este contrato, los dos diagramas y la actualización de los documentos derivados. **No** se implementa ninguna lógica, migración ni endpoint.

## Anexo A — Auditoría previa

Clasificación: **VIGENTE** (código o contrato ya en `develop`), **HISTÓRICO**, **CONTRADICCIÓN**, **PENDIENTE**. Verificado contra `develop` el 2026-09-28 (Missions `286e074`, Player-Inventory `cb1853f`, Wallet `2a49a1e`, Combat `2c56839`, Web `117c485`).

| Hallazgo | Fuente | Clasificación | Acción |
| --- | --- | --- | --- |
| `MissionDefinition.rewards` = `{guaranteed, potential, objectiveBonuses, firstTime}`; los tres primeros son `RewardLabel` (texto) | Missions `MissionDefinition.ts` | Contrato vigente / **no liquidable** | §6: bloque aditivo `completion` |
| Contenido del Templo: «50 créditos», «1 Cofre de Bronce», «10 créditos adicionales», título | Missions `example-missions.ts` | Contenido textual | No es regla; cofres/títulos fuera [PO] (§6) |
| `contentSnapshot` = definición congelada al pedir la simulación; `close()` cae al catálogo si falta | Missions `RunMissionExecutions.ts` | Vigente / **riesgo CA-06** | §4.1 |
| `DeliverableRewardsPolicy` solo promete XP por derrota, botín enlazado y épicas; créditos/cofres/bonos/título «nadie los entrega todavía (HU-10)» | Missions | Vigente | §6, §11 |
| `mission_report_rewards`: PK `(enrollment_id, line_no)`; `kind` ∈ CREDITS/PRODUCT/EPIC/EXPERIENCE; `source` ∈ HU-10/73/09/72; `quantity ≥ 0`; progresión solo si `CREDITED` | Missions migraciones 005/008/011 | Vigente | §7 |
| El resumen `experience` del reporte se deriva **solo** de líneas `HU-09` | Missions `ReportPolicy.ts` | Vigente | §17 |
| La vista pública del reporte no expone la progresión por línea | Missions `GetMissionReport.ts`; Web `missionReportApi.ts` | Vigente / hueco | §17 (campo aditivo) |
| Botín: Combat lo sortea en la simulación (`loot` con `productId` y `quantity`); `GrantMissionLoot` lo entrega con `uuidV5(enrollmentId:loot:label)` | Combat `MissionSimulation.ts`; Missions `LootPolicy.ts` | Vigente | §11 |
| `rewardTier` = `scalingOf(difficulty).rewardTier` (constante de código); la matrícula solo persiste `difficulty` | Missions `difficulty-scaling.ts` | Vigente | §4.1 (se congela como evidencia) |
| `ABANDONED` en el vocabulario, sin flujo que lo produzca; antecedente del PO sin formalizar | Missions; `misiones-jugabilidad.md` | **Pendiente** | §5, §19 |
| Ruta de XP solo admite `MISSION_RIVAL_DEFEAT`; ledger aplanado con campos de derrota; `409` solo = conflicto (la colisión concurrente responde `503`); `amount` entero ≥ 0 | Player-Inventory `hero-experience.*`, `GrantHeroExperience`, `experience-grant-mapping` | Vigente | §8 |
| `inventory/grants`: `operationId` UUID, `items` 1..200, `quantity` 1..9999, `productId` UUID; `409` por conflicto **o** concurrencia; autoriza a `missions` | Player-Inventory `inventory-grants.*` | Vigente | §10 |
| Wallet: `battle-reward` con catálogo `{1,2,4}`, ledger con `battle_id` y columnas de victoria, respuesta con `victoryProgress`/`chestEarned`; comparación de contenido con `occurredAt` | Wallet `CreditBattleReward`, migración 001 | Vigente / **no reutilizable** | §9.1 |
| Wallet: patrón de una tabla y `operation_id` único por tipo de operación (comisiones, retenciones, transferencias) | Wallet migraciones 002–005 | Vigente | §9.1 (alternativa C) |
| `@InternalOnly()` sin lista en `battle-reward`, con comentario «solo combat» | Wallet `wallet-internal.controller.ts` | **Contradicción** | §9.4, §20 |
| ADR-019: «Missions → Wallet: acreditar recompensas en créditos» y «Missions → Player/Inventory: recompensas», síncronas por `operationId`; sin transacciones distribuidas | ADR-019 | Decisión `Accepted` | §2, §16; **sin modificar** |
| Web reconoce `CREDITS \| PRODUCT \| EPIC \| EXPERIENCE`, estados y origen `HU-10`; el reporte refresca; no calcula | Web `missionReportApi.ts` | Vigente | §17 |
| Documentación que presenta el sorteo del botín como pendiente de HU-10 | `hu-72-simulacion-mision.md` | **Obsoleta** | Corregida (§20 #2) |
| El HU-22 `battle-reward` no debe reutilizarse; su «Fuera de alcance» menciona HU-10 | `hu-22-reward-contract-v1.md` | Vigente | §9.1 |
