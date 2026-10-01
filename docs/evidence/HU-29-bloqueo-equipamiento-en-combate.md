# HU-29 — Evidencia del diseño y de la implementación del bloqueo de equipamiento en combate

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#76](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/76)
- **Tasks:** [#231](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/231) (diseño) · [#232](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/232) (implementación) · [#233](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/233) (pruebas de aceptación)
- **Fecha de esta revisión:** 2026-10-01 (diseño original del 2026-09-23/24; esta revisión audita `develop` real, añade la verificación de extremo a extremo entre los dos servicios reales y la presentación en Web)
- **Requisito trazado:** `RF-29`
- **Bounded context:** Player / Inventory (regla y compromiso) · Combat (lifecycle y compromiso saliente) · Web (presentación)
- **Diseño:** `Nexus-Battle-Player-Inventory/docs/hu-29-bloqueo-equipamiento-combate.md`
- **Contrato de la integración:** `docs/contracts/hu-29-battle-commitment-v1.md`
- **Fuentes editables:** `docs/diagrams/hu-29-use-case.puml`, `hu-29-activity.puml`, `hu-29-sequence.puml`, `hu-29-domain.puml`

## Estado a 2026-10-01

**El backend está mergeado en `develop` de los dos servicios y verificado de extremo a extremo entre
los dos servicios reales.** La presentación en Web y la propia prueba de extremo a extremo viven en
dos PR todavía abiertos, sin mergear.

| Pieza | Repositorio / PR | Estado |
| --- | --- | --- |
| Diseño de la regla | Player-Inventory `docs/hu-29-bloqueo-equipamiento-combate.md` (PR #45) | **Mergeado** |
| Contrato del compromiso de batalla | Infrastructure [#165](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/165) | **Mergeado** (`9e9bed38c4c8acfea995509b1c3186db28be8a65`) |
| Evidencia y SAD (esta Task, versión anterior) | Infrastructure [#148](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/148) | **Mergeado** (`780166f9ef174cab7eb4e7b135c918f36c4e8a75`) |
| Guard, `locked`, compromiso `BATTLE`, rutas internas | Player-Inventory [#26](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/26) | **Mergeado** (`ff0e13f2b6a8d6f7257ad679381489ca1b7e8990`) |
| Matriz P1/P2/P3 + registro | Player-Inventory [#59](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/59) | **Mergeado** (`db7a9dbdfd1739a48ba53ed7ecd7168ac0b649b5`) |
| Comprometer al iniciar, liberar al terminar | Combat [#55](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/55) | **Mergeado** (`eff40a34673dbf668407bf29c723e1fb4d7bcff7`) |
| Presentación (`locked`, `409 battle_lock`) | Web [#191](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/191) | **Abierto, sin mergear** (`2255194b274f401ef5d20371023e5d9b819ae34b`). El PR anterior, Web #90, se cerró sin mergear; esta rama es nueva, auditada contra el `develop` actual |
| Verificación de extremo a extremo entre los dos servicios reales | Combat [#62](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/62) | **Abierto, sin mergear** (`f471f26595b5e61197113c28293dee9d00360e88`). 13/13 escenarios en verde, 4 ejecuciones consecutivas |
| Esta revisión de evidencia/SAD/README | Infrastructure (esta rama, `docs/hu-29-final-acceptance`) | **Abierta, sin mergear** |

**Este documento no declara la HU aceptada.** El backend está mergeado y verificado; la aceptación de
`#76` requiere además que Web #191 y Combat #62 se mergeen, y la decisión explícita del equipo/PO (ver
«Lo que falta para cerrar HU-29»).

## Qué se comprobó en el diseño (vigente, sin cambios)

| Nivel | Estado |
| --- | --- |
| Caso de uso, actividades, secuencia y fragmento de dominio | **Entregados** en el diseño |
| Fuentes editables de los cuatro diagramas | **Entregadas** en `docs/diagrams/hu-29-*.puml`; las cuatro abren sin error con la imagen que usa CI (`ghcr.io/plantuml/plantuml:1.2026.6 -checkonly`) |
| Cobertura de arma, armadura e ítem como mutaciones bloqueadas | **Modelada e implementada**; las tres por igual, la categoría no altera la decisión (`decideEquipmentChange`, `it.each` sobre las tres) |
| Rechazo + mensaje explicativo + equipo intacto | **Modelado e implementado**, verificado además en el E2E real (§«Verificación de extremo a extremo») |
| Liberación al terminar la batalla | **Modelada e implementada**, verificada en el E2E real con el fin de batalla disparado por el mecanismo real de Combat |
| HU-28 no rediseñada | **Verificado**: el guard corre antes de cualquier lectura/escritura del loadout y no toca capacidades 2/6/2 ni recálculo |
| Revisión de persistencia | **Comprobada**: no se crea ningún snapshot ni copia del loadout; la prueba compara el DTO completo antes/después, no solo «no se creó nada» |
| Trazabilidad `RF-29 → HU-29 → Diseño` | **Presente** |

## Decisiones que el diseño dejaba abiertas, y cómo quedaron

1. **Qué cuenta como «combate iniciado» / «batalla activa».** Resuelto: la lectura literal de la HU,
   `IN_BATTLE`. `PREPARING` no bloquea — se verificó explícitamente en el E2E real (E-00/E-02): la
   sala llega a `PREPARING` y el equipamiento sigue `locked:false`.
2. **El texto del mensaje.** No se fija un copy oficial único — **y no hace falta**: el requisito
   exige que el mensaje *explique el motivo*, no una frase normativa. Player-Inventory publica
   `"No se puede modificar el equipamiento porque el heroe participa en una batalla activa."`
   (`EquipmentCombatLockPolicy`); Web lo mapea a una explicación localizada en es/en/fr/pt.
3. **`HU-014`.** Sigue citada como bloqueo declarado en el diseño original; su contenido no se
   inventó ni fue necesario resolverlo para esta implementación.
4. **Si la épica entra en el bloqueo.** No: la HU nombra arma, armadura e ítem, y HU-28 excluye
   `EPICA` de las categorías equipables. No se amplió.
5. **El transporte de la señal de liberación.** Resuelto por `ADR-019`: compromiso publicado por
   Combat al iniciar, liberado al terminar, síncrono, con `operationId` de idempotencia. Verificado
   real en el E2E.
6. **La exclusión cruzada entre propósitos** (`MISSION` y `BATTLE` a la vez). **Sigue sin
   implementarse**, a propósito: es una regla de producto distinta a HU-29, declarada como límite
   en el contrato §10. No es una condición de aceptación de esta HU.

## Qué es real y qué está sustituido

**Real en Player-Inventory y Combat** (código de producción, mergeado en `develop`):

- la regla que rechaza la mutación del loadout con batalla activa, con `reason: 'battle_lock'`;
- el campo `locked` en `GET .../equipment`;
- las dos rutas internas del compromiso, con `@InternalCallers('combat')`, sin ampliar el
  allow-list global de Player-Inventory (que ya contenía `combat`);
- la llamada saliente de Combat (HMAC, `operationId` UUID v5 determinista) al iniciar, y la
  liberación al terminar con reintento en el reconciliador;
- la caducidad obligatoria (`expiresAt`): un compromiso vencido no bloquea.

**Verificado de extremo a extremo, real, en Combat PR #62** (ver sección dedicada más abajo): Combat
real → HMAC real → Player-Inventory real → MongoDB real de cada servicio. Es la pieza que faltaba:
hasta esta revisión, las suites de Combat (`test:db`, `test:integration`) sustituían
`BattleHeroCommitmentPort` por un doble que registra, y nadie había ejercitado la cadena real contra
un Player-Inventory real.

## Qué NO resuelve, aunque el backend ya esté mergeado

1. **La exclusión cruzada entre propósitos** (`MISSION` y `BATTLE` a la vez) sigue sin existir. Está
   escrita como límite conocido en el contrato §10 y en el SAD §14, no fingida ni oculta.
2. **El copy del mensaje** no tiene un texto oficial único — no lo exige la HU.
3. **La épica** sigue fuera del bloqueo.
4. **`HU-014`** sigue citada como bloqueo declarado; su contenido no se inventa.

Ninguno de estos cuatro puntos es una condición de aceptación de HU-29; se mantienen documentados
como lo que son, límites fuera de este alcance.

## Fallar cerrado, y su consecuencia operativa

Sin `PLAYER_INVENTORY_SERVICE_BASE_URL` configurada, Combat arranca el compromiso con un doble que
**rechaza** y registra `battle_commitment_client_sin_configurar`. Es deliberado — mejor un inicio de
batalla que falla que un bloqueo que existe en el papel y nunca se dispara — y tiene consecuencia
declarada: hasta que las rutas existan en el entorno **y** la URL esté puesta, `POST /rooms/:id/start`
responde `503`. Es el orden de despliegue del contrato §11.

## Eventos de registro

| Evento | Nivel | Cuándo |
| --- | --- | --- |
| `equipment_change_rejected` | `warn` | Un intento de mutación con batalla activa, con `reason: battle_lock` |
| `equipment_change_applied` | `info` | La mutación se aplicó. No es decorativo: sin él no se distingue «no se intentó» de «se intentó y pasó» |
| `battle_commitment_client_sin_configurar` | `warn` | Combat sin URL de Player/Inventory: el compromiso no se puede pedir |
| `battle_commitment_liberacion_fallo` | `error` | La liberación al terminar falló (fire-and-forget); quedan el reintento y la caducidad |
| `battle_commitment_reconciliacion_fallo` | `error` | El reintento de la liberación falló para un participante |

## Verificación por repositorio (medida en esta revisión, 2026-10-01)

### Combat (rama `test/hu-29-e2e-equipment-lock`, sobre `develop` al día)

| Puerta | Resultado |
| --- | --- |
| `typecheck` | ✅ |
| `lint` | ✅ |
| `format:check` | ✅ |
| `test:unit` | ✅ 117 suites / **2892 pruebas** |
| `test:integration` | ✅ 12 suites / **190 pruebas** |
| `test:db` (MongoDB real, Testcontainers) | ✅ 10 suites / **208 pruebas**; cobertura 94,87 % sentencias / 83,87 % ramas (umbral 80 %) |
| `build` | ✅ |
| `test:e2e:hu-29` (nuevo, extremo a extremo real) | ✅ **13/13**, 4 ejecuciones consecutivas sin inestabilidad |

### Player-Inventory (`develop`, sin cambios de código en esta revisión — ya cumplía el contrato completo)

Auditado en esta revisión y confirmado contra el código real de `develop` (no una medición heredada):
el guard resuelve antes de cualquier lectura/escritura del loadout, el índice único parcial
`{playerId, heroId}` sobre compromisos `ACTIVE` impide dos compromisos simultáneos a nivel de motor,
la expiración se aplica tanto por filtro de consulta como por liberación perezosa, la liberación es
idempotente, y la identidad del jugador se deriva siempre del sujeto verificado (JWT o, en este
entorno de prueba, `AUTH_MODE=disabled`), nunca de un campo manipulable del cuerpo. No se modificó
ningún archivo de producción de este repositorio: ya cumplía el contrato íntegro.

## Verificación de extremo a extremo entre los dos servicios reales (Task #233)

**El hueco que esta Task existía para cerrar.** Hasta esta revisión, `BattleHeroCommitmentPort`
siempre se sustituía por un doble (`recordingBattleCommitments()`) en las suites de Combat; nadie
había demostrado que Combat realmente provoca el bloqueo en un Player-Inventory real.

**Dónde vive:** Combat PR [#62](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/62),
`test/e2e/hu-29/equipment-lock.e2e.spec.ts`, fuera de `test:db`/CI (script dedicado
`npm run test:e2e:hu-29`): necesita el repositorio Player-Inventory desplegado localmente, en el
mismo checkout multirepo, porque levanta su build real como proceso aparte. El runner de GitHub
Actions de Combat solo hace checkout de ese repositorio, así que no puede ejecutar esta prueba sin
una reconfiguración de CI con checkout de dos repositorios — fuera de alcance de esta Task.

**Qué es real:**

- Combat: este mismo proceso, app Nest real, HTTP real sobre un puerto efímero.
- Player-Inventory: proceso Node aparte, **su build real** (`dist/main.js`), migrado contra su
  propio MongoDB real (Testcontainers).
- Dos contenedores MongoDB reales, uno por servicio (nunca comparten esquema, ADR-001).
- `PlayerInventoryBattleCommitmentHttpClient`: la clase real, sin doblar, firmando HMAC con el
  secreto compartido real, contra las rutas internas reales de Player-Inventory.
- Los endpoints públicos `GET`/`PUT` de equipamiento de Player-Inventory, contra su Mongo real.
- El ciclo de vida real de la sala de Combat (`create` → `join` → `start` → vencimiento global vía
  `ProcessBattleDeadlines` → `finish`), incluida la liberación real que dispara `BattleFinalizer`.

**Qué está sustituido, declarado explícitamente, por ser ajeno a HU-29 e imprescindible solo para
construir el fixture:**

- `CatalogReadPort` de Player-Inventory: un servidor HTTP mínimo de la propia prueba sirve el
  contrato canónico de Catalog v1 para un héroe y sus tres piezas equipables. Catalog es HU-27, no
  HU-29; sin él, Player-Inventory no podría resolver ningún producto.
- `ACCOUNT_BATTLE_PROFILE` y `PLAYER_INVENTORY_EQUIPPED_HERO` de Combat (HU-15/HU-16: perfil de
  cuenta y elegibilidad precombate).
- `TOKEN_VERIFIER` de Combat (JWT/Cognito no es parte de HU-29).
- El reloj que firma el HMAC saliente de Combat se separa del reloj de juego (que sí se adelanta
  6 minutos para simular el vencimiento de HU-21 sin esperar tiempo real): Player-Inventory
  verifica la firma contra **su propio reloj de pared real**, con una ventana de 30 s, así que
  firmar con un reloj de juego adelantado la rompería. La clase del cliente de compromiso sigue
  siendo la real; solo cambia qué reloj le da el sello.

**Escenarios y resultado** (los 13 ejercitados; E-00/E-02 comparten una sola prueba, igual que
E-07/E-08):

| Escenario | Qué verifica | Resultado |
| --- | --- | --- |
| E-00/E-02 | Stack real levantado; `PREPARING` no bloquea (`GET equipment` → `locked:false`) | ✅ REAL |
| E-01 | Antes de batalla: equipar arma/armadura/ítem reales funciona, `locked:false` | ✅ REAL |
| E-03 | Inicio real: `StartBattle` compromete de verdad contra Player-Inventory → `locked:true` | ✅ REAL |
| E-04 | Arma bloqueada en batalla: `409 reason=battle_lock`, mensaje explicativo | ✅ REAL |
| E-05 | Armadura bloqueada en batalla | ✅ REAL |
| E-06 | Ítem bloqueado en batalla | ✅ REAL |
| E-07/E-08 | Dos intentos seguidos no acumulan cambio; el servidor sigue siendo la autoridad | ✅ REAL |
| E-09 | Fuera de batalla, un producto no propio sigue siendo 404 (no se etiqueta como `battle_lock`) | ✅ REAL |
| E-12 | El loadout durante la batalla es idéntico, campo a campo, al de antes (salvo `locked`) | ✅ REAL |
| E-10 | Fin real vía `ProcessBattleDeadlines` (vencimiento global HU-21) → libera → `locked:false` | ✅ REAL |
| E-11 | El mismo cambio antes rechazado ahora lo acepta HU-28 | ✅ REAL |
| E-13 | Reconciliar de nuevo (`ReconcileRewardWorkflows`) no da error ni cambia el estado ya liberado | ✅ REAL |
| E-14 | Una llamada interna sin HMAC al compromiso de batalla se rechaza (401) | ✅ REAL |

**Resultado:** 13/13, 4 ejecuciones consecutivas (~32-37 s cada una), sin inestabilidad observada.

**Lo que esta prueba NO afirma:** no sustituye la exclusión cruzada entre propósitos (fuera de
alcance, declarado arriba), no prueba MISSION+BATTLE simultáneos, no prueba TOURNAMENT ni AUCTION, y
no corre en el CI de GitHub Actions de Combat (limitación estructural del checkout de un solo
repositorio, declarada en el propio spec y en `jest.e2e-hu29.config.ts`).

## Presentación en Web (Task #232, alcance de interfaz)

**Dónde vive:** Web PR [#191](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/191), rama
`feat/hu-29-finalize-battle-lock-feedback`. El PR anterior (#90) se cerró sin mergear; esta rama es
nueva, auditada contra el `develop` actual de Web, sin cherry-pick de aquel trabajo.

**Qué hace:** consume `locked: boolean` (ya presente en el contrato real de Player-Inventory) y el
`409 { reason: 'battle_lock' }`, sin calcular ni derivar nada por su cuenta. Aviso accesible
(`role="status"`) y controles de equipar deshabilitados mientras `locked === true` (arma, armadura e
ítem por igual); el equipo existente se sigue mostrando. Cubre la carrera lectura/escritura: si Web
leyó `locked:false` y el backend rechaza con `409 battle_lock` al intentar equipar, se reconoce
correctamente, sin optimistic update (se invalida la consulta y se vuelve a pedir el estado real).
Un `409` que no sea `battle_lock` conserva su tratamiento previo (ninguna regresión de HU-28).

**Validación:** `format:check`, `lint`, `typecheck` ✅; `test` → 240 archivos / 2924 pruebas ✅
(incluye HU-07, HU-28, Jugar Online, completitud i18n); `test:coverage` → 90,23 % sentencias / 83,81 %
ramas / 86,24 % funciones / 90,41 % líneas (umbral del repo: 80 % en las cuatro); `build` ✅.

**Backend sigue siendo la autoridad:** esto es solo UX. El servidor rechaza igual aunque Web crea que
`locked:false`.

## Matriz P1/P2/P3 y registro (Task #233, parte unitaria — vigente, mergeada)

`Nexus-Battle-Player-Inventory/test/unit/hu-29-3-matriz-bloqueo.spec.ts` (PR #59, mergeado en #26).

| # | Caso del enunciado | Qué afirma |
| --- | --- | --- |
| **P1** | fuera de batalla → `ok true` (o delega) | la mutación pasa, la lectura publica `locked: false`, y un producto que no es del jugador sigue siendo 404 |
| **P2** | en batalla → `ok false battle_lock`, equipo igual | DTO completo idéntico antes y después, versión del loadout intacta, héroe llegando a la batalla ya equipado |
| **P3** | fin batalla → lock liberado | el mismo cambio rechazado ahora pasa; un compromiso vencido deja de bloquear sin liberación explícita |
| **Log** | «Test + log» | `equipment_change_rejected` (`warn`, con `reason`) y `equipment_change_applied` (`info`); un rechazo que no es el bloqueo no se registra como bloqueo |

El estado de batalla no se simula con un doble: empezar una batalla es comprometer al héroe y
terminarla es liberarlo, por el mismo camino que usa Combat por la ruta interna.

## Trabajo previo: qué se rescató y qué no

| Dónde | Estado al 2026-09-09 | Qué se hizo |
| --- | --- | --- |
| Player-Inventory #26 | `open`, borrador, 22 commits por detrás de `develop` | **Rescatado**: era la capa de dominio correcta, pero le faltaba la fuente del estado de batalla y no compilaba sobre `develop`. Se completó y se mergeó |
| Web `feat/hu-29-battle-lock-feedback` | rama publicada sin PR; el PR #90 cerrado | **No rescatado**: Web se reconstruyó desde cero (PR #191) contra el `develop` actual, sin cherry-pick |

El modelo de estado de batalla del PR original de Player-Inventory era una **consulta** —preguntaba a
Combat si el héroe estaba en batalla—, mientras que `ADR-019` decidió un **compromiso publicado** por
Combat. Se resolvió hacia el compromiso: no hay consulta de Player-Inventory a Combat en el camino
crítico del equipamiento.

## Relación con HU-07

HU-07 dejó su propio `CA-09` fuera de alcance con esta nota textual de su Task:

> «Tampoco deben convertir en prueba de HU-07 la regla de modificación durante combate, ya que
> pertenece a HU-29 y actualmente existe una inconsistencia documental que debe ser resuelta
> antes de automatizar dicho comportamiento como requisito definitivo.»

La inconsistencia documental está resuelta (Task #231 la reescribió en seis decisiones declaradas) y
la decisión funcional también: HU-29 está implementada, sin tocar HU-07 ni su única puerta de
escritura del loadout (HU-28).

## Criterios de aceptación

| CA | Enunciado | Estado |
| --- | --- | --- |
| **CA-01** | Intento en batalla activa → rechazo con mensaje, equipo sin modificaciones | ✅ Backend mergeado y verificado (unitario + E2E real, E-04/E-05/E-06/E-12) |
| **CA-02** | No se permiten cambios de **armas** | ✅ Verificado en E2E real (E-04) y en la matriz unitaria |
| **CA-03** | No se permiten cambios de **piezas de armadura** | ✅ Verificado en E2E real (E-05) |
| **CA-04** | Ante un intento en batalla activa, se **rechaza** | ✅ Verificado, incluidos dos intentos seguidos (E-07/E-08) |
| **CA-05** | El jugador recibe un **mensaje explicativo** | ✅ Backend publica un mensaje que explica el motivo (`EquipmentCombatLockPolicy`); Web lo presenta localizado (PR #191, sin mergear) |
| **CA-06** | El equipamiento **permanece sin modificaciones** | ✅ Verificado campo a campo en E2E real (E-12) |
| **CA-07** | Al finalizar, las restricciones **pueden liberarse** | ✅ Verificado con el fin real de la batalla (E-10) y la vuelta a HU-28 (E-11) |
| **CA-08** | Un criterio obligatorio fallido impide aceptar la HU | Todos los CA obligatorios (01-07) están verificados contra código real; la aceptación formal de la HU sigue pendiente de que se mergeen Web #191 y Combat #62 |

La evidencia separa tres capas: **backend** (requisito impuesto por Player-Inventory, mergeado),
**E2E** (Combat realmente provoca el estado del backend, verificado en #62, sin mergear) y **Web**
(feedback visible, en #191, sin mergear).

## Lo que falta para cerrar HU-29

1. **Mergear** Web [#191](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/191) y Combat
   [#62](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/62). El backend (Player-Inventory
   #26/#59, Combat #55, contrato Infrastructure #165/#148) ya está en `develop`.
2. **Mergear** esta revisión de Infrastructure (evidencia, SAD, README).
3. **Revisión por pares** de los PR abiertos y aceptación del PO.
4. **Cerrar** las Tasks #231/#232/#233 y la HU #76 en Management, en ese orden, una vez lo anterior
   esté integrado — no antes.

Límites declarados que **no** bloquean el cierre, porque no son condición de aceptación de esta HU:
la exclusión cruzada entre propósitos (`MISSION`/`BATTLE`), el copy fijo del mensaje, y la épica fuera
del bloqueo.

## Archivos de este entregable

- `Nexus-Battle-Player-Inventory/docs/hu-29-bloqueo-equipamiento-combate.md` — el diseño (mergeado)
- `docs/contracts/hu-29-battle-commitment-v1.md` — el contrato de las dos rutas internas (actualizado
  en esta revisión)
- Implementación: Player-Inventory PR #26/#59 y Combat PR #55 (mergeados)
- Verificación de extremo a extremo: Combat PR #62 (abierto)
- Presentación: Web PR #191 (abierto)
- `docs/diagrams/hu-29-use-case.puml`, `hu-29-activity.puml`, `hu-29-sequence.puml`,
  `hu-29-domain.puml` — las cuatro fuentes editables (sin cambios)
- `docs/architecture/SAD.md` — §4 (la subsección de HU-29) y §14 (limitación 11, actualizada en esta
  revisión)
- `README.md` — fila de la tabla de contratos (actualizada en esta revisión)
- este documento
