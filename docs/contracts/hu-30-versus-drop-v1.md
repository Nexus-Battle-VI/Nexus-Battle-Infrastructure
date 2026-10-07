# Contrato HU-30 — drop por derrota Versus (v1)

- **Estado:** **implementado en Combat, Player-Inventory, Notifications y Catalog, y verificado de extremo a extremo entre los servicios reales** (3 corridas consecutivas en verde). Management [HU-30 #77](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/77), Tasks [#534](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/534)–[#538](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/538). PRs abiertos, sin mergear: Combat [#66](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/66), Player-Inventory [#71](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/71), Notifications [#44](https://github.com/Nexus-Battle-VI/Nexus-Battle-Notifications/pull/44), Catalog [#69](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/69), Web [#195](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/195). Ver la [evidencia](../evidence/HU-30-drop-por-derrota-en-versus.md).
- **Fuente funcional vigente:** [aclaración consolidada de #77](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/77#issuecomment-5935391731). Prevalece sobre el emparejamiento de ganadores/perdedores al final descrito en el cuerpo histórico del issue.
- **Fuentes técnicas:** [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md), [ADR-020](../adr/ADR-020-realtime-combat.md), [ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md), [HU-21](hu-21-battle-finish-v1.md) y [HU-29](hu-29-battle-commitment-v1.md). El SRS «Proyecto Integrador II», §6.1.3, tablas 8–19, publica tasas de caída de piezas concretas, pero no un desempate entre probabilidades máximas iguales.

## 1. Regla y autoridades

La unidad de resolución es una **derrota válida de un jugador por otro jugador**. La identidad de la derrota nace del evento de acción persistido de Combat (`battleId` + `seq`); `killerPlayerId` y `defeatedPlayerId` se derivan de las posiciones de la cola de batalla, nunca del resultado del equipo ni de Web. En 2v2/3v3, cada derrota se procesa independientemente. El killer conserva el derecho aunque después pierda su equipo. Un killer puede recibir varios derechos, uno por víctima derrotada. No hay pairing posterior ni límite de un drop por partida.

Solo son candidatos los productos de tipo `ARMA`, `ARMADURA` o `ITEM` equipados en el loadout autoritativo del derrotado **al iniciar la batalla**. La selección de arma activa no modifica ese conjunto. Se excluyen épicas de Máster/Misiones y el inventario no equipado. El snapshot debe conservar las referencias concretas y su identidad de unidad; `activeEffects` y `loadoutVersion` por sí solos no permiten reconstruirlas.

| Dato/acción | Autoridad | Consumidor |
| --- | --- | --- |
| Batalla, acción letal, killer, víctima, `seq`, FINISHED | Combat | Resultados y flujo de drop |
| Equipamiento, unidades poseídas e identidad de instancia | Player-Inventory | Combat por HTTP interno |
| Porcentaje de caída del producto | Catalog, en su contrato canónico | Player-Inventory/Combat por HTTP interno; no copia manual en Web |
| Índices aleatorios | RNG central de Combat (HU-24, `RandomSequencePort`) | Resolución de cada candidato |
| Derecho pendiente y estado de liquidación | Combat | Reconciliación de Combat |
| Transferencia atómica de una unidad, loadout coherente | Player-Inventory | Combat por HTTP interno firmado |
| Comunicación in-app al recibir/perder | Notifications | Web, solo lectura |

**DROP DETERMINADO != DROP ACREDITADO.** Ninguna operación de ownership ocurre durante la partida. El derecho nace `PENDING` después de persistir la acción letal y solo es elegible para liquidación cuando la sala persistida está `FINISHED`, cualquiera que sea su resultado global.

## 2. Determinación por derrota

1. Combat identifica el cruce `targetHealth.before > 0 && targetHealth.after == 0` de un ataque o habilidad de daño entre dos humanos de equipos rivales. La acción lleva un `commandId`; el evento persistido tiene `seq` único en la sala. Curación, timeout, desconexión sin acción letal, AI y replay de comando no son una nueva derrota válida.
2. Para **cada** pieza equipada del derrotado, toma la tasa canónica en puntos básicos (`0..10000`; 100 = 1 %) y consume una evaluación individual de la única fuente RNG de Combat. Una tasa ausente no se interpreta como cero ni se inventa a partir de la rareza: es un error de contrato que requiere configuración del producto.
3. Entre las piezas que superan su evaluación, selecciona la de mayor tasa. Si no hay ninguna, guarda `NO_DROP` para esa derrota, de modo que un replay no vuelva a tirar. Si existe una ganadora inequívoca, guarda **un** derecho `PENDING`. No se ordenan primero los candidatos para tirar solo una vez.
4. Si dos o más elegibles comparten exactamente la tasa máxima, aplica `P-HU30-TIE`: **no se elige una pieza por orden implícito o azar inventado**. La derrota queda con resolución `AWAITING_TIE_RULE` y no se transfiere nada para ella hasta que Management fije una regla. Las demás derrotas y derechos siguen su curso.

La lista de candidatos, tasas y resultados de tirada se guarda con el derecho para auditoría/replay. No se repite RNG en un retry. `battleId + defeatEventSeq` identifica la derrota; el `operationId` de transferencia deriva establemente de ese par, sin depender de reloj, orden de reintentos o resultado del equipo. No se exponen estado/semilla del generador a Web.

## 3. Liquidación diferida e idempotencia

Combat conserva una línea por derrota: `NO_DROP`, `AWAITING_TIE_RULE`, `PENDING`, `CREDITED` o `FAILED_RETRYABLE`. Una línea `PENDING` o `FAILED_RETRYABLE` se envía solo después de leer `FINISHED` persistido. Un fallo en una línea no reabre las ya `CREDITED`. Un reconciliador vuelve a leer partidas terminadas con líneas pendientes/fallidas y reintenta la **misma** operación.

La operación interna de Player-Inventory recibe, exclusivamente de `combat` con HMAC y permiso por ruta: `operationId`, `battleId`, `defeatEventSeq`, `sourcePlayerId`, `targetPlayerId` y `productInstanceId`. Verifica `source != target`, identidad y ownership de la instancia, y mueve **esa misma instancia** en una sola transacción MongoDB junto con el registro idempotente y la limpieza de referencias del loadout del derrotado. No son dos grants separados ni un acceso cruzado a Mongo desde Combat. Mismo `operationId` y mismo payload devuelve la misma confirmación; mismo ID con payload distinto es `409`; el fallo previo a commit no deja medio traslado. La transferencia nunca se invoca desde Web.

La respuesta acreditada incluye `operationId`, `productInstanceId`, `productId`, `sourcePlayerId`, `targetPlayerId` y `creditedAt`. Combat marca `CREDITED` tras recibir confirmación; si pierde la respuesta, el replay del mismo `operationId` la recupera. Los dos avisos se publican **después** de `CREDITED`, con identificadores estables distintos por destinatario (`operationId` + rol); Notifications los guarda idempotentemente. Un fallo de aviso no revierte ownership: se reintenta el aviso, no la transferencia, hasta confirmar ambas comunicaciones.

## 4. Secuencia

```text
Player-Inventory -- loadout + identidad de unidades + tasas canónicas --> Combat
Combat -- acción letal persistida, battleId/seq/killer/víctima --> resolución RNG
       -- sin elegibles --> NO_DROP (terminal, ningún aviso)
       -- empate máximo --> AWAITING_TIE_RULE (P-HU30-TIE)
       -- elegido --> PENDING (ownership intacto; batalla continúa)
Combat -- batalla FINISHED persistida --> reconciliador de drops
       -- HMAC operationId estable --> Player-Inventory
Player-Inventory -- transacción Mongo: source - misma instancia + target;
                    limpiar loadout source; guardar resultado idempotente --> Combat
Combat -- CREDITED --> Notifications (aviso al que obtiene y al que pierde)
Web -- GET autoritativo --> Mi Inventario / notificaciones
```

## 5. Modalidades, límites y despliegue

La misma ruta de Combat sirve 1v1, 2v2 y 3v3. Tournament, cuando cree justas en Combat según [ADR-022](../adr/ADR-022-sprint-3-bounded-contexts.md), consumirá esa misma ruta; al 2026-10-01 no hay repositorio/servicio Tournament local ni integración de justas verificada. No se atribuye evidencia E2E a un torneo inexistente.

La identidad por unidad en Player-Inventory y la tasa de caída en Catalog, declaradas como brechas reales en el diseño, **ya están cerradas**: `battle-drop-units` materializa la identidad física de cada pieza equipada al congelar la instantánea (solo para lo efectivamente equipado, no para todo el inventario histórico), y Catalog acepta `dropChanceBasisPoints` en `ARMA`/`ARMADURA`/`ITEM` al crear un producto. El catálogo no asigna 0 % por omisión: un producto **existente** sin la tasa configurada hace que `CaptureBattleDropSnapshot` rechace la instantánea con `DROP_RATE_UNAVAILABLE` en vez de inventar un valor, y **bloquearía el inicio de cualquier batalla Versus** donde ese producto esté equipado (`StartBattle` captura la instantánea de cada humano síncronamente). Por eso Catalog añade `PATCH /api/v1/admin/products/{id}/drop-chance`: la única vía administrativa, mínima y deliberadamente acotada a ese único campo, para configurar la tasa de un producto creado antes de HU-30 sin reabrir la inmutabilidad general de `attributes` que `UpdateProductDetails` ya declara a propósito. El contrato de producto de tasa es aditivo y no modifica las probabilidades históricas del SRS sin decisión de producto.

### 5.1 Invariante de configuración de drop en producto equipable (incidente 2026-10, corrección quirúrgica)

**Lo anterior describía un campo *aceptado*, no *exigido*: esa brecha se materializó en producción.** Catalog permitía crear `ARMA`/`ARMADURA`/`ITEM` sin `dropChanceBasisPoints`, y Web no lo pedía en el asistente de alta. El resultado: productos equipables nuevos nacían sin tasa, y al equiparlos `CaptureBattleDropSnapshot` los rechazaba con `DROP_RATE_UNAVAILABLE`, propagando un 503 a `POST /api/v1/combat/rooms/{roomId}/start` — **esto llegó a bloquear Jugar Online**.

**Invariante, desde la corrección:**

```text
type == ARMA | ARMADURA | ITEM
  → dropChanceBasisPoints es OBLIGATORIO al CREAR el producto
  → rango 0..10000 (0 es un valor explícito válido, distinto de ausente)
  → HEROE | HABILIDAD | EPICA quedan fuera, sin ampliar el alcance
```

- **Catalog** (`CreateCanonicalProduct`): rechaza con 400 (`DomainError`) la creación de un `ARMA`/`ARMADURA`/`ITEM` sin `dropChanceBasisPoints`. La restricción aplica **solo a la creación**: `parseProductAttributes` sigue aceptando el campo ausente al *leer* un producto ya persistido, para no impedir que el servicio arranque o liste el catálogo histórico antes del backfill (§5.2).
- **Web**: el paso "Tipo y atributos" del asistente pide el porcentaje (0..100) para `ARMA`/`ARMADURA`/`ITEM`, lo convierte a basis points al construir la petición, y el paso de revisión muestra exactamente el valor que se va a persistir. Un producto sin esta tasa no permite avanzar.
- **Gestión de productos** (pantalla administrativa existente): un producto equipable sin tasa configurada puede corregirse ahí mismo, reutilizando `PATCH .../drop-chance` (ya descrito arriba) desde un formulario dedicado — no se duplica el mecanismo, solo se expone en la UI que antes no lo hacía.
- **Player-Inventory y Combat no cambian**: `DROP_RATE_UNAVAILABLE` sigue siendo la defensa correcta ante un dato incompleto; no se convierte en advertencia ni se asume `0` por su cuenta. El incidente no se originó en Combat — Combat detectaba correctamente que faltaba una precondición.

### 5.2 Backfill de productos históricos (operación puntual, no una regla de dominio)

Los productos equipables que ya existían en el entorno desplegado antes de esta corrección se reconcilian con un backfill controlado, no con código que invente tasas:

- **Productos oficiales** (coinciden por tipo + nombre normalizado con el documento del Proyecto Integrador II, Tabla 20): reciben exactamente el porcentaje oficial del SRS (`OFFICIAL_SRS_RATE`).
- **Productos sin regla oficial** (creados por el equipo, sin fila correspondiente en el SRS): reciben `0 bp` **explícito y documentado como `PROVISIONAL_NO_SRS_RATE`** — `0 bp` configurado es una decisión operativa para no bloquear Versus, no una afirmación de que el producto no debería caer nunca; el valor definitivo sigue pendiente de decisión de producto.
- El backfill usa el caso de uso oficial (`ConfigureProductDropChance`/`PATCH .../drop-chance`) producto a producto, nunca una escritura directa a MongoDB: conserva validación, versión optimista, auditoría y outbox.
- Es `dry-run` por defecto, idempotente, y no sobrescribe silenciosamente una tasa ya configurada (reporta conflicto en vez de pisarla).

`P-HU30-TIE` sigue abierto: ni el comentario de #77, ni las Tasks, ni las tablas 8–19 del SRS, ni los contratos/ADR vigentes fijan desempate. También queda pendiente confirmar cualquier regla de respawn/múltiples derrotas de la misma víctima si Combat llegase a admitirlas; el flujo actual de salud 0 no permite una nueva acción de esa víctima.

## 6. Criterios de aceptación

| CA | Trazabilidad de contrato |
| --- | --- |
| CA-01 | Resolución, transferencia real pos-FINISHED y dos avisos cuando hay drop |
| CA-02 | Cada pieza equipada se evalúa individualmente |
| CA-03 | Solo RNG central de Combat |
| CA-04 | Máximo uno **por derrota válida**; precisión del comentario vigente de #77 |
| CA-05 | Mayor tasa entre las elegibles; empate `P-HU30-TIE` pendiente |
| CA-06 | Killer real recibe derecho incluso si luego pierde su equipo; sustituye pairing histórico |
| CA-07 | Una misma instancia sale del source y entra al target atómicamente |
| CA-08 | Ambos avisos solo después de acreditación |
| CA-09 | Evidencia integral, regresión y CI requeridos; no se declara aprobada por este documento |
