# HU-29 — Evidencia del diseño y de la implementación del bloqueo de equipamiento en combate

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#76](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/76)
- **Task de este entregable:** [#231](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/231) (diseño · `open`), ampliada con la implementación de [#232](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/232) (`open`)
- **Tasks posteriores:** [#233](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/233) (pruebas de aceptación · `open`)
- **Fecha:** 2026-09-24 (diseño del 2026-09-23; la sección de implementación es de la misma fecha)
- **Requisito trazado:** `RF-29`
- **Bounded context:** Player / Inventory · Team Alfa
- **Diseño:** `Nexus-Battle-Player-Inventory/docs/hu-29-bloqueo-equipamiento-combate.md`
- **Contrato de la integración:** `docs/contracts/hu-29-battle-commitment-v1.md` (Infrastructure PR [#165](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/165))
- **Fuentes editables:** `docs/diagrams/hu-29-use-case.puml`, `hu-29-activity.puml`, `hu-29-sequence.puml`, `hu-29-domain.puml`
- **Estado:** **diseñado e implementado en ramas, sin mergear y sin verificar.** No cierra la HU, **no la da por desbloqueada** y **no sustituye a la Task `#233`**: lo que hay son los dos PR de implementación, con sus pruebas propias, y la verificación de aceptación sigue pendiente.

## Estado de la verificación: qué se comprobó y qué NO

Este documento **no declara la HU aceptada**. Declararla sería repetir el error que el Project ya
cometió: HU-29 figura `Done` en el Project **sin una sola línea en `develop`**. Lo que existe hoy es
la especificación de diseño que la Task `#231` pide **y** la implementación de `#232` en ramas, con
sus propias pruebas; **ninguna de las dos está mergeada**, y la verificación de aceptación de `#233`
**no se ha hecho**.

| Nivel | Estado |
| --- | --- |
| Caso de uso, actividades, secuencia y fragmento de dominio | **Entregados** en el diseño |
| Fuentes editables de los cuatro diagramas | **Entregadas** en `docs/diagrams/hu-29-*.puml`; las cuatro **abren sin error** con la imagen que usa CI (`ghcr.io/plantuml/plantuml:1.2026.6 -checkonly`, salida `0`). El `-checkonly` no es un colador: con un `.puml` roto a propósito devuelve `200` |
| Cobertura de arma, armadura e ítem como mutaciones bloqueadas | **Modelada**; las tres por igual, la categoría no altera la decisión |
| Rechazo + mensaje explicativo + equipo intacto | **Modelados** |
| Liberación al terminar la batalla | **Modelada**: la restricción deja de aplicarse |
| HU-28 no rediseñada | **Verificado**: el diseño la precede y no toca capacidades 2/6/2 ni recálculo |
| Revisión de persistencia | **Comprobada**: **no se crea ningún snapshot ni copia del loadout**. Como la mutación no llega a intentarse, no hay nada que restaurar, y una copia sería una segunda versión de la misma verdad. El diseño razona y descarta la alternativa de forma expresa |
| Sin firmas ni endpoints | **Verificado**: las cuatro menciones a `lockLoadout`, `EquipmentLockService`, `if (inBattle)` y HTTP están **en la sección que los prohíbe** |
| Trazabilidad `RF-29 → HU-29 → Diseño` | **Presente**, en la cabecera del diseño y en su §9 |
| Escenarios de prueba | **10 identificados** (los 5 de la Task más 5 derivados) |
| **Implementación** | **Existe, en ramas y sin mergear**: el guard y el compromiso en Player/Inventory (PR [#26](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/26)) y el lado de Combat que compromete y libera (PR [#55](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/55)). **No está en `develop`** |
| **Pruebas de la implementación** | **Existen en las dos ramas** y están verdes salvo fallos preexistentes de `develop` (ver «Implementación»). Son pruebas de la implementación, **no** la verificación de aceptación de `#233` |
| Endpoint o contrato HTTP | **Contratado**: `hu-29-battle-commitment-v1` (Infrastructure PR [#165](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/165)). El diseño no lo prescribía —era mandato de la Task— y la implementación sí necesitaba fijarlo |
| Revisión por pares | **PENDIENTE** en los tres PR |
| Aceptación del PO | **PENDIENTE**, y depende de las decisiones de la sección siguiente |
| PR de este entregable | [#148](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/148) |

## Qué queda pendiente y por qué no se inventó

La Task `#231` exige que los pendientes queden **explícitos** en lugar de resueltos por
intuición. Son seis, y este diseño los deja escritos:

1. **Qué cuenta como «combate iniciado» / «batalla activa».** No está el criterio de borde. El
   diseño modela un **estado que el contexto de combate publica** y **no inventa el ciclo de
   vida**. Lo que sí puede decirse con evidencia: el contrato de HU-21 define
   `WAITING_FOR_PLAYERS`, `PREPARING`, `IN_BATTLE`, `FINISHED` y `CANCELLED`, y la lectura
   literal de la HU apunta a **`IN_BATTLE`**. **Ampliar el bloqueo a `PREPARING` rompería el
   lobby de preparación de HU-15.3**, donde el jugador equipa a propósito.
2. **El texto del mensaje.** Se modela que **explica el motivo**; el copy no se fija.
3. **`HU-014`.** Se cita como bloqueo declarado; su contenido **no se inventa**.
4. **Si la épica entra en el bloqueo.** La HU nombra arma, armadura e ítem, y **no** la épica;
   además HU-28 excluye `EPICA` de las categorías equipables. **No se amplía sin decisión.**
5. **El transporte de la señal de liberación.** Se modela el **evento**, no cómo llega.
6. **El mecanismo de integración.** `ADR-019` ya lo enmarca —Player/Inventory posee los
   **compromisos** del héroe y Combat publica el compromiso al iniciar y lo libera al terminar—
   y este diseño **no reabre** esa decisión.

## Implementación (Task #232): qué existe hoy, y dónde

Medido el 2026-09-24, contra `develop` de cada repositorio:

| Repositorio | Rama / PR | Estado | Qué aporta |
| --- | --- | --- | --- |
| Infrastructure | `docs/hu-29-2-contrato-compromiso-batalla` · PR [#165](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/165) | `open`, mergeable | El contrato `hu-29-battle-commitment-v1`: las dos rutas internas, sus errores, la idempotencia y el orden de despliegue |
| Player / Inventory | `feat/hu-29-equipment-lock` · PR [#26](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/26) | `open`, `MERGEABLE`, al día con `develop` | La **regla**: el guard que rechaza la mutación, `locked` en la lectura, el compromiso `BATTLE` y sus dos rutas internas |
| Combat | `feat/hu-29-compromiso-equipamiento-batalla` · PR [#55](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/55) | `open` | La **otra mitad**: comprometer al iniciar, liberar al terminar y reconciliar la liberación perdida |
| Web | rama `feat/hu-29-battle-lock-feedback` · PR [#90](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/90) `closed` | **parada** | Consumiría `locked` y el `409`. **No forma parte de este entregable y no se ha tocado** |

**Nada de esto está en `develop` todavía.** La evidencia de esta sección es el contenido de esos PR,
no una afirmación sobre lo desplegado.

### Qué es real y qué está sustituido

**Real** —código de producción, no andamios—:

- la regla que **rechaza** la mutación del loadout con batalla activa, con `reason: 'battle_lock'`;
- el campo `locked` en `GET .../equipment`, para que la interfaz no reimplemente la regla;
- las dos rutas internas del compromiso, con `@InternalCallers('combat')` y **sin ampliar** el allow-list global de Player/Inventory, que ya contenía `combat`;
- la llamada saliente de Combat (HMAC, `operationId` UUID v5 determinista) al iniciar, y la liberación al terminar con reintento en el reconciliador;
- la caducidad obligatoria (`expiresAt`): un compromiso vencido **no** bloquea.

**Sustituido en las pruebas, y dicho**: en las suites HTTP y de base de datos de Combat no hay un
Player/Inventory real detrás, así que el puerto se sustituye por un doble que **registra** —igual que
ya se hacía con el héroe equipado—, y lo que se comprueba es el cableado: que iniciar compromete el
héroe de cada humano de la sala. El cliente HTTP tiene su propia prueba unitaria, que fija además el
`operationId` como **valor dorado**. **No hay todavía una prueba de extremo a extremo con los dos
servicios reales**: eso es `#233`.

### Qué NO resuelve, aunque ya haya código

1. **La exclusión cruzada entre propósitos** («un héroe, un compromiso» entre `MISSION` y `BATTLE`) sigue sin existir: hoy un héroe podría quedar comprometido a las dos cosas. Está escrito como límite conocido en el contrato §10, no fingido.
2. **El copy del mensaje** sigue pendiente del PO: lo contratado es que **explica el motivo**.
3. **La épica** sigue fuera del bloqueo: la HU nombra arma, armadura e ítem, y HU-28 excluye `EPICA` de lo equipable.
4. **`HU-014`** sigue citada como bloqueo declarado; su contenido no se inventa.

### Fallar cerrado, y su consecuencia operativa

Sin `PLAYER_INVENTORY_SERVICE_BASE_URL` configurada, Combat arranca el compromiso con un doble que
**rechaza** y registra `battle_commitment_client_sin_configurar`. Es deliberado —mejor un inicio de
batalla que falla que un bloqueo que existe en el papel y nunca se dispara— y tiene consecuencia
declarada: hasta que las rutas existan en el entorno **y** la URL esté puesta,
`POST /rooms/:id/start` responde `503`. Es el orden de despliegue del contrato §11.

### Eventos de registro

| Evento | Nivel | Cuándo |
| --- | --- | --- |
| `equipment_change_rejected` | `warn` | Un intento de mutación con batalla activa, con `reason: battle_lock` |
| `equipment_change_applied` | `info` | La mutación se aplicó. No es decorativo: sin él no se distingue «no se intentó» de «se intentó y pasó» |
| `battle_commitment_client_sin_configurar` | `warn` | Combat sin URL de Player/Inventory: el compromiso no se puede pedir |
| `battle_commitment_liberacion_fallo` | `error` | La liberación al terminar falló (fire-and-forget); quedan el reintento y la caducidad |
| `battle_commitment_reconciliacion_fallo` | `error` | El reintento de la liberación falló para un participante |

### Verificación de las ramas

| Puerta | Player / Inventory | Combat |
| --- | --- | --- |
| `lint`, `format:check`, `typecheck`, `build` | verde | verde |
| Suites | 59 suites / 1023 pruebas | 117 suites / 2865 (unit) · 12 suites / 190 (integración) |
| Cobertura | 89,38 % sentencias · 80,24 % ramas | 95,57 % sentencias · 88,86 % ramas |
| Base de datos real (Testcontainers) | 10 suites / 102 pruebas | 10 suites / 205 pruebas |

**Dos fallos preexistentes de `develop`** —no de esta HU— hacen que el CI de estos PR salga rojo:
`test/unit/mission-ability-policy.spec.ts` (los PR #51 y #52 de Combat pasaron CI **por separado** y su
fusión dejó una expectativa obsoleta; `develop` no volvió a ejecutar CI porque el workflow solo corre en
`push` a `main`) y una **fuga de temporizador** de `IntervalRewardWorkflowScheduler` (HU-22), que sigue
disparando después de cerrar el cliente de Mongo y hace caer el error dentro de la ventana de la prueba
en curso. Los dos se reproducen en `develop` **sin** estos cambios.

## Trabajo previo: qué se rescató y qué no

| Dónde | Estado al 2026-09-09 | Qué se hizo |
| --- | --- | --- |
| [Player-Inventory #26](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/26) | `open`, borrador, 1 commit, **22 commits por detrás** de `develop` | **Rescatado**: era la capa de dominio correcta de la regla, pero **no podía funcionar** —le faltaba la fuente del estado de batalla y no compilaba sobre `develop`—. Su rama se puso al día y se completó (rutas internas, `locked`, compromiso `BATTLE`, registro y las pruebas que faltaban) |
| Web `feat/hu-29-battle-lock-feedback` | rama publicada, **sin PR**; el PR [#90](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/90) está `closed` | **No rescatado**: la pantalla es otra HU. La rama sigue parada y **no se ha modificado** |

El modelo de estado de batalla del PR original era una **consulta** —Player/Inventory preguntaba si el
héroe estaba en batalla, con un registro en memoria (`InMemoryBattleStateRegistry`)—, mientras que
`ADR-019` decidió un **compromiso publicado** por Combat. Se resolvió hacia el compromiso: el registro
en memoria se eliminó y el estado de batalla se lee **siempre** del compromiso, también con
`PERSISTENCE_DRIVER=memory`.

### Estado medido, no heredado

Las afirmaciones anteriores de este documento —«dos Pull Requests **en borrador y con conflicto**
desde el 10 de septiembre» y «10 y 34 commits por detrás»— eran ciertas al escribirse y **ya no lo
son**: el PR de Web está cerrado, su trabajo vive en una rama sin PR, el de Player/Inventory ya no va
por detrás y las distancias a `develop` son otras. Se corrigen aquí, en el SAD y en la limitación del
§14, porque un dato de estado que nadie vuelve a medir es una afirmación falsa con formato de dato.

## Relación con HU-07

HU-07 dejó su propio `CA-09` fuera de alcance con esta nota textual de su Task:

> «Tampoco deben convertir en prueba de HU-07 la regla de modificación durante combate, ya que
> pertenece a HU-29 y actualmente existe una inconsistencia documental que debe ser resuelta
> antes de automatizar dicho comportamiento como requisito definitivo.»

**Qué se resuelve aquí y qué no.** La **inconsistencia documental** está resuelta: el body de la
Task `#231` reescribió el molde y convirtió lo que estaba implícito en **seis decisiones
declaradas** en lugar de dejarlas a la interpretación. Lo que **sigue abierto** es la **decisión
funcional**. Por eso este diseño **no automatiza** ningún comportamiento de equipamiento y **no
toca HU-07**: la única puerta de escritura del loadout sigue siendo la de HU-28.

## Criterios de aceptación

| CA | Enunciado | Estado |
| --- | --- | --- |
| **CA-01** | Intento en batalla activa → rechazo con mensaje, equipo sin modificaciones | **Diseñado e implementado en rama** (PR #26); escenarios 1, 2 y 3 |
| **CA-02** | No se permiten cambios de **armas** | **Diseñado e implementado en rama**; escenario 1 |
| **CA-03** | No se permiten cambios de **piezas de armadura** | **Diseñado e implementado en rama**; escenario 2 |
| **CA-04** | Ante un intento en batalla activa, se **rechaza** | **Diseñado e implementado en rama**; escenarios 1, 2 y 3 |
| **CA-05** | El jugador recibe un **mensaje explicativo** | **Implementado en rama**; el copy sigue pendiente del PO |
| **CA-06** | El equipamiento **permanece sin modificaciones** | **Diseñado e implementado en rama**; escenario 5 |
| **CA-07** | Al finalizar, las restricciones **pueden liberarse** | **Diseñado e implementado en rama**: la liberación la dispara Combat al terminar (PR #55), con reintento y caducidad |
| **CA-08** | Un criterio obligatorio fallido impide aceptar la HU | Condición de aceptación, **no cumplida**: falta mergear, verificar los 10 escenarios y la decisión del PO |

**Ningún criterio está cubierto todavía en el sentido de `CA-08`.** Que exista código en una rama, con
sus pruebas, **no** es la verificación de aceptación: eso es la Task `#233`, y no se adelanta aquí.

## Lo que falta para cerrar HU-29

1. **Decisión del PO** sobre el texto del mensaje (y confirmación de la lectura literal de «batalla
   activa» como `IN_BATTLE`, que es la que la implementación aplica).
2. **Decisión de arquitectura** sobre si la épica entra en el bloqueo —hoy **no**, por lo que dice la
   HU— y sobre la exclusión cruzada entre propósitos, que **no** se ha implementado.
3. **Mergear y verificar**: los tres PR (contrato #165, Player/Inventory #26, Combat #55) están
   abiertos y **ninguno está en `develop`**. Antes conviene resolver los **dos fallos preexistentes**
   de `develop` que dejan el CI rojo en cualquier PR de Combat.
4. **Task `#233`**: automatizar y verificar los 10 escenarios, incluido el extremo a extremo con los
   dos servicios reales, que hoy **no existe**.
5. **Corregir la trazabilidad del Project**: HU-29 y sus tres Tasks figuran `Done`. **Recomendación,
   no acción de este entregable.**
6. **Revisión por pares** y aceptación del PO.

## Archivos de este entregable

- `Nexus-Battle-Player-Inventory/docs/hu-29-bloqueo-equipamiento-combate.md` — el diseño (PR
  [Player-Inventory #45](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/45), mergeado)
- `docs/contracts/hu-29-battle-commitment-v1.md` — el contrato de las dos rutas internas
  (Infrastructure PR [#165](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/165))
- Implementación: Player/Inventory PR [#26](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/26)
  y Combat PR [#55](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/55)
- `docs/diagrams/hu-29-use-case.puml`, `hu-29-activity.puml`, `hu-29-sequence.puml`,
  `hu-29-domain.puml` — las cuatro fuentes editables
- `docs/architecture/SAD.md` — §4 (la subsección de HU-29 y sus diagramas) y §14 (limitación 11)
- este documento

**Sobre las dos copias de los diagramas.** El diseño de Player/Inventory lleva los cuatro
diagramas como Mermaid, para que se lean dentro de la narrativa; estos `.puml` son la **fuente
editable de registro** en Infrastructure, que es donde el repositorio guarda los diagramas y
donde la plantilla de PR exige que abran sin error. Se acepta la duplicación a cambio de tener
fuente editable, y se acota: el diseño está congelado y cualquier cambio mueve las dos copias en
el mismo PR.
