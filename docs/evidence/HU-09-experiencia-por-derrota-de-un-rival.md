# HU-09 — Evidencia: experiencia por derrota de un rival (JvE)

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#18](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/18)
- **Tasks:** [#439](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/439) (diseño), [#440](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/440) (Combat), [#441](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/441) (Player-Inventory), [#442](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/442) (Missions), [#443](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/443) (Web), [#444](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/444) (E2E)
- **Requisito trazado:** `RF-09`
- **Bounded context:** Missions (coordinación) + Combat (tirada) + Player/Inventory (estado del héroe)
- **Contrato entregado:** [hu-09-experience-reward-v1](../contracts/hu-09-experience-reward-v1.md)
- **Reporte de ejecución:** [`hu-09-ejecucion-e2e.json`](hu-09-ejecucion-e2e.json) — 12/12 casos en verde, tres repositorios sin cambios pendientes
- **Estado:** **verificación técnica entregada (Task `#444`). Las tres piezas de la cadena —Combat, Missions y Player/Inventory— están implementadas y la cadena se recorre de extremo a extremo.**
  **La HU NO está aceptada**: falta la revisión por pares y la aprobación del PO, y `P-2` sigue abierta. La visualización en Web (`#443`) no forma parte de esta verificación.

## Lo primero: qué NO dice este documento

Este documento **no declara la HU aceptada**. Que la cadena esté en verde es verificación técnica, no aceptación: esta exige revisión por pares y aprobación del PO, y el Project ya confundió una cosa con la otra con HU-29 y HU-31.

Y dice, en su propia tabla, **qué piezas se ejercen de verdad y cuáles se sustituyen**. Un escenario que prueba dobles y lo llama «la cadena» es peor que no tener escenario.

## Verificación de extremo a extremo (Task `#444`)

| Qué | Dónde |
| --- | --- |
| Escenario | `Nexus-Battle-Missions/test/e2e/hu-09-chain.e2e.spec.ts` |
| Configuración | `jest.e2e.config.ts` · `npm run test:e2e:chain` |
| Apoyo | `test/e2e/support/{harness,fixtures,missions-app,run-report}.ts` |
| CI | `.github/workflows/cadena-hu-09.yml` (clona los tres repositorios y publica el reporte como artefacto) |

### Qué se comprobó y qué NO

| Nivel | Estado |
| --- | --- |
| Cadena completa misión ganada → tirada → recompensa → acreditación → nivel | **Comprobado**, 19 derrotas reales (`S-01`) |
| Los ocho valores de `1d8` con el importe del contrato, acreditados de verdad | **Comprobado** (`S-02`) |
| Subida de un nivel, de varios y nivel máximo sin descarte | **Comprobado** (`S-03`) |
| Idempotencia del cierre (no vuelve a tirar ni a crear recompensas) | **Comprobado** (`S-04`) |
| Replay de la acreditación (mismo `operationId`, `applied:false`) | **Comprobado** (`S-05`) |
| `409` por clave reutilizada con otro contenido, **en las dos fronteras** | **Comprobado** (`S-06`) |
| `CA-08`: sin victoria válida no hay tirada, ni recompensa, ni acreditación | **Comprobado**, en sus dos formas (`S-07`) |
| Dos derrotas del mismo arquetipo son dos recompensas distintas | **Comprobado**, 10 derrotas de `sombra-corrompida` en 2 encuentros (`S-08`) |
| Una tirada sin acreditar la termina el barrido, sin volver a tirar | **Comprobado** (`S-09`) |
| Auditoría cruzada: ninguna tirada huérfana, en los dos sentidos | **Comprobado** (`S-10`) |
| Guardas de no-duplicación en verde **y capaces de fallar** | **Comprobado**, por control negativo y por mutación (`S-11`) |
| `CA-09` (condición de aceptación de la HU) | **NO es un escenario**: se documenta aquí, no se prueba |
| Revisión por pares | **PENDIENTE** |
| Aceptación del PO | **PENDIENTE**, y condicionada por `P-2` |
| Visualización en Web (`#443`) | **No entra** en esta verificación; la superficie pública es el reporte de misión de HU-74 |
| Escala, carga y concurrencia reales | **No comprobado**: el escenario es 1 jugador, 1 héroe y un servicio por pieza |
| La ruta interna de perfil de héroe (`HU-71.2`) | **Sustituida** por el doble de desarrollo: sigue sin estar en `develop` |
| Producción real (Cognito, AWS, réplicas) | **No comprobado**: no hay Cognito en la cadena y los contenedores son locales |

### Qué piezas fueron REALES y cuáles simuladas

Las tres piezas de la cadena son **código de producción en ejecución**, no dobles. Lo sustituido está aquí, entero y con su motivo.

| Pieza | Estado | Detalle |
| --- | --- | --- |
| Missions | **REAL** | La aplicación NestJS real de este repositorio, con `PERSISTENCE_DRIVER=postgres` sobre un PostgreSQL 17 en contenedor. Sus adaptadores son los de producción: `PostgresExperienceRewardRepository`, `PostgresReportRepository`, `CombatExperienceRollClient`, `PlayerInventoryExperienceClient` — el caso `S-00` **afirma el nombre de la clase** que el contenedor resolvió para cada token, así que un doble colado se vería |
| Combat | **REAL, como proceso** | `node dist/main.js` del repositorio hermano, sobre un MongoDB 8 real en réplica, con sus planificadores encendidos. Es quien **tira el dado**: las 19 caras de `S-01` salen de su motor centralizado, y el lote queda persistido en `experience-rolls` con el `operationId` del contrato |
| Player/Inventory | **REAL, como proceso** | `node dist/main.js` del repositorio hermano, sobre el mismo MongoDB. Es quien **acredita**: los asientos de `experience_grants` y el documento `hero-progressions` que se leen en los casos son los suyos, escritos por su propia ruta interna |
| Resultado de la simulación de Combat (HU-72) | **SUSTITUIDO** | `COMBAT_SIMULATION_DRIVER=memory`, el doble de desarrollo (`ScriptedCombatSimulation`): el ingreso de simulación de Combat todavía responde `503`, así que no hay bitácora de simulación que consumir. **No se sustituye nada de HU-09**: las derrotas que produce ese doble son las del contenido de la misión, y a partir de ahí la tirada, el cálculo y la acreditación son los reales |
| Perfil y compromiso del héroe (HU-71.2) | **SUSTITUIDO** | `HERO_ABILITIES_DRIVER=memory` y `HERO_COMMITMENTS_DRIVER=memory`: la ruta interna de perfil de héroe todavía no está en `develop` |
| Testimonio del jugador | **SUSTITUIDO** | Un verificador de tokens fijo: no hay Cognito en la cadena. Solo afecta a *quién* llama al reporte, no a la cadena de la recompensa |
| Puerto de tirada en `S-02` | **SUSTITUIDO, y solo ahí** | Para cubrir las **ocho** caras en una sola misión se guioniza el puerto de tirada con caras `1..8` en ciclo. **La acreditación sigue siendo la real de Player/Inventory**, y `S-01` —el caso de la cadena completa— usa la tirada **real** de Combat |
| Reloj | **NO se sustituye** | Los clientes internos firman con HMAC y Player/Inventory acepta un sello de ±30 s: adelantar el reloj rompería la cadena. El tiempo se maneja con dos **datos de partida**: la ventana de la matrícula se desplaza al pasado (una hora exacta, terminando un segundo antes) y el escalonado de reintento se vence escribiendo `next_attempt_at` |
| Base de datos | **REAL** | PostgreSQL 17 y MongoDB 8 en contenedores (Testcontainers), no dobles en memoria |

### Los doce casos, y qué observó cada uno

Los valores son los que quedaron escritos en el [reporte de ejecución](hu-09-ejecucion-e2e.json); no se resumen «a ojo».

| # | Caso | Resultado observado |
| --- | --- | --- |
| `S-00` | Las tres piezas reales y arriba | Combat y Player/Inventory responden `ready`; Missions resuelve `PlayerInventoryExperienceClient`, `CombatExperienceRollClient`, `PostgresExperienceRewardRepository` y `PostgresReportRepository` |
| `S-01` | La cadena completa | 19 derrotas → **19 tiradas** en un solo lote con el `operationId` del contrato → **19 recompensas** `CREDITED` → **19 asientos** con la clave de cada instancia → **447 XP**, nivel **3** |
| `S-02` | Los ocho valores de `1d8` | Caras `1..8` cubiertas, importes `12, 14, 17, 21, 25, 30, 36, 43`, **439 XP** acreditados de verdad en Player/Inventory |
| `S-03` | Subida de uno, de varios y nivel máximo | `195 → 207`, nivel **2** (+1); `190 → 629`, nivel **3** (+2); desde `12.800` → `13.239`, nivel **8**, `levelsGained: 0` y **sin descartar experiencia** |
| `S-04` | Repetir el cierre | El lote es el mismo documento (mismas caras y misma fecha de creación); siguen 19 recompensas, 19 líneas y 19 asientos |
| `S-05` | Replay de la acreditación | Misma petición, mismo `operationId` → `200` con `applied: false`; la progresión queda idéntica |
| `S-06` | Clave reutilizada con otro contenido | `409 OPERATION_ID_REUSED` en Combat y `409 EXPERIENCE_GRANT_CONFLICT` en Player/Inventory; **nada sobrescrito** |
| `S-07` | `CA-08` | (a) héroe derrotado y sin bajas enemigas → 0 recompensas, 0 tiradas pedidas, 0 asientos; (b) simulación rechazada → matrícula `VOIDED`, informe `404`, 0 recompensas y 0 asientos |
| `S-08` | Dos derrotas del mismo arquetipo | 10 derrotas de `sombra-corrompida` repartidas en **2 encuentros**, con `sombra-corrompida#1` presente en los dos; **10 claves distintas**, ninguna colapsada |
| `S-09` | Recuperación de una tirada sin acreditar | Con Player/Inventory caído: 19 recompensas `ROLLED` con importe y **sin acreditar** (no es un defecto, contrato §9.1); al volver el servicio y vencer el escalonado, el barrido las acredita **con la misma cara y el mismo importe**, sin volver a tirar |
| `S-10` | Auditoría cruzada | Toda cara tiene recompensa, línea y asiento, y todo asiento tiene su cara: 19/19/19/19 y **0 tiradas huérfanas**; informe ajeno `404 REPORT_NOT_FOUND` y misión en curso `404 REPORT_NOT_AVAILABLE` |
| `S-11` | Guardas de no-duplicación | Las dos guardas en verde (una sola suite cada una) y **su control negativo ejecutado** |

### La idempotencia, frontera por frontera

Se repite el mismo `operationId` en cada frontera y se comprueba que **no vuelve a tirar, no vuelve a calcular distinto y no vuelve a acreditar**.

| Frontera | Clave | Caso | Qué se observó |
| --- | --- | --- | --- |
| Missions → Combat (lote de tiradas) | `mission:{enrollmentId}:xp-rolls` | `S-04` | El cierre repetido no crea un segundo lote: mismas caras y `createdAt` |
| Missions → Combat, mismo `operationId` con otro contenido | ídem | `S-06` | `409 OPERATION_ID_REUSED`, y el lote original intacto |
| Missions → Player/Inventory (acreditación) | `mission:{enrollmentId}:encounter:{encounterId}:enemy:{enemyInstanceId}:hero:{heroId}:xp` | `S-05` | `applied: false`, 19 asientos y la progresión sin tocar |
| Missions → Player/Inventory, misma clave con otro importe | ídem | `S-06` | `409 EXPERIENCE_GRANT_CONFLICT`, y el importe original intacto |
| Barrido tras un fallo parcial | ídem | `S-09` | Acredita con la misma cara e importe; el lote de Combat es **el mismo documento** |

### Las guardas de no-duplicación: en verde y capaces de fallar

| Guarda | Repositorio | Qué vigila |
| --- | --- | --- |
| `test/unit/hu-09-no-alternative-randomness.spec.ts` | Combat (`HU-09.2`) | Que la tirada consume **la instancia inyectada** de `BoundedRandom` y ninguna otra fuente: ni `Math.random`, ni `node:crypto`, ni MT19937, ni Box-Müller, ni la semilla, ni la fábrica de secuencias, ni ninguna petición de rango distinta del dado |
| `test/unit/hu-09-reward-policy.spec.ts` | Missions (`HU-09.4`) | Que la fórmula `10 × 1,2^(1d8)` existe **una sola vez** en el código fuente, y que el cálculo se pide a `experienceForRoll` en lugar de copiarse |

Que estén en verde no basta: una guarda que solo afirma «ninguno coincide» pasa por vacía si su patrón está mal escrito, y esa es justo la forma de que una segunda fuente entre sin que nadie se entere. Se comprobó **de dos maneras**:

1. **Control negativo permanente** (dentro de cada guarda, y ejecutado por `S-11`): cada familia de patrones tiene que reconocer su forma prohibida en un fragmento sintético, y el uso legítimo del dado inyectado no puede marcarse. El caso `S-11` **falla si el control negativo desaparece o deja de correr**.
2. **Mutación** (acto de verificación de esta Task, no una prueba permanente): se introduce a propósito la violación que la guarda vigila, se comprueba que la guarda se pone **roja**, y se restaura el fichero.

| Guarda | Mutación inyectada | Resultado |
| --- | --- | --- |
| Missions, fórmula | `const copiaDeLaFormula = 10 * 1.2 ** roll` en `src/application/use-cases/CoordinateExperienceReward.ts` | **2 fallos**, `Test Suites: 1 failed`, salida `1` |
| Combat, azar | `const caraAlternativa = Math.random()` en `src/domain/reward/ExperienceRollPolicy.ts` | **1 fallo**, `Test Suites: 1 failed`, salida `1` |

### Dos defectos del escenario, encontrados y corregidos en esta Task

Ninguno es un defecto de producción: los dos estaban **en el andamiaje de la prueba**, y los dos hacían que la cadena no llegara a probarse.

| # | Defecto | Efecto real | Corrección |
| --- | --- | --- | --- |
| 1 | La ventana de la matrícula se desplazaba al pasado con **dos llamadas separadas a `now()`**, así que medía `59,9` minutos | El presupuesto de tiempo que viaja a Combat es esa resta en minutos y `toIsoDuration` solo admite enteros: el cierre moría con `mission_execution_error`, la misión **no se cerraba**, el informe daba `404` y **no se devengaba ninguna recompensa**. Los doce casos en rojo | Las dos fechas salen de **una sola lectura del reloj**, separadas por una hora exacta y con el fin un segundo en el pasado (`b4d6126`) |
| 2 | `S-11` ejecutaba las guardas con un **patrón posicional** (`npm run test:unit -- hu-09-reward-policy`) | **Jest 30 retiró el patrón posicional**: esa orden corre el proyecto unitario **entero**. El caso afirmaba «la guarda está en verde» sin haber ejecutado la guarda | Se pasa a `--testPathPatterns`, se afirma que corre **una sola suite** y que su **control negativo** se ejecuta; `runNpmScript` lee también `stderr`, que es donde Jest escribe el resumen (`f7c1e15`) |

Un tercer caso, menor y del mismo tipo: `S-09` contaba solo los asientos de *esa* matrícula, y con la base sucia «no se acreditó» y «se acreditó a otra matrícula» se ven igual. Ahora compara las dos cifras.

### Reporte de ejecución

El reporte completo, con commits, ambiente, casos, valores observados, cobertura y límites, está en [`hu-09-ejecucion-e2e.json`](hu-09-ejecucion-e2e.json). Su resumen:

| Dato | Valor |
| --- | --- |
| Comando | `npm run test:e2e:chain` (Missions) |
| Plataforma | Windows 11, Node `v24.19.0` |
| Bases | `postgres:17-alpine` y `mongo:8.0` (réplica), Testcontainers |
| Commits | Missions `f7c1e15` · Combat `c77aae9` · Player/Inventory `614acb9` — **los tres sin cambios pendientes** |
| Casos | **12/12 en verde** |
| Cobertura de la cadena (informativa) | Sentencias `60,31 %` · Ramas `35,67 %` · Funciones `53,26 %` · Líneas `58,79 %` |
| Duración | 60 s |
| Límites declarados | 7, en el propio reporte |

La cobertura es **informativa y deliberadamente sin umbral**: los umbrales viven donde se pueden exigir sin contenedores (`jest.config.ts` y `jest.db.config.ts`). Esta suite mide la cadena, no la superficie del servicio.


## Qué se decidió, y con qué autoridad

| # | Origen | Contenido |
| --- | --- | --- |
| 1 | Requisito explícito del Issue #18 | Fórmula `10 × 1,2^(1d8)`; `1d8` entero `1..8` del motor centralizado; la XP se acumula; se verifica el umbral tras acreditar; sin victoria válida no hay recompensa |
| 2 | Aclaración funcional del PO (posterior al enunciado) | La fórmula es de **JvE** (muerte de NPC en misión); **PvP no la otorga**; Missions coordina y calcula; Combat tira; Player/Inventory acredita. **Una recompensa, una tirada y una acreditación por cada NPC derrotado**, con clave por instancia real de la derrota |
| 3 | Decisión arquitectónica vigente | `ADR-019` (ownership y HMAC interno) y `ADR-021` (Combat, única autoridad de aleatoriedad) |
| 4 | Contrato reutilizado como plantilla | `POST /api/internal/v1/inventory/grants` (Player-Inventory, HU-59/HU-69): forma del endpoint interno y del ledger idempotente |
| 5 | Decisión técnica de esta Task | Las dos operaciones internas, los `operationId` deterministas, los estados de la recompensa, la matriz de fallos y la elección de operación propia para la tirada |
| 6 | Fuera de alcance | HU-10, HU-30, HU-32/HU-73, PvP y `CA-06` de HU-08 |

## Contrato entregado

| Operación | Frontera | Idempotencia |
| --- | --- | --- |
| `POST /api/internal/v1/combat/experience-rolls` | Missions → Combat | Lote por misión: `mission:{enrollmentId}:xp-rolls`; **una tirada por derrota**, persistida con `mission:{enrollmentId}:encounter:{encounterId}:enemy:{enemyInstanceId}:xp-roll` |
| `POST /api/internal/v1/players/{playerId}/heroes/{heroId}/experience` | Missions → Player/Inventory | **Una acreditación por derrota**: `mission:{enrollmentId}:encounter:{encounterId}:enemy:{enemyInstanceId}:hero:{heroId}:xp` |

**Una recompensa por cada NPC derrotado**, no una por misión. La clave es la **instancia real de la derrota** (`encounter` + `combatant` del `combatLog` de HU-72), nunca el arquetipo del enemigo: una misión puede enfrentar dos veces al mismo tipo.

- **Ninguna superficie pública nueva.** Web consume el reporte de misión (HU-74).
- **Ninguna ruta existente se modifica** y ningún mensaje de HU-21 cambia de forma.
- **`missions` no entra en el allow-list global** de Player/Inventory: la ruta se acota con `@InternalCallers('missions')`.
- **En Combat no hay nada que ampliar.** Su lista cerrada de servicios es global y ya vale exactamente `['missions']`, que es el llamante; y el mecanismo por ruta (`@InternalCallers`) **no existe** allí, así que no se inventa. La operación de tirada sería además la **primera ruta interna de Combat**.

### Correcciones posteriores a la entrega (revisión de la Task `#440`)

Dos defectos del contrato, encontrados al preparar la implementación de Combat. Ninguno cambia el reparto.

| # | Defecto | Corrección |
| --- | --- | --- |
| 1 | La tabla de errores traía `422 HERO_NOT_ELIGIBLE`, que **Combat no puede producir**: la elegibilidad del héroe no es suya ni tiene con qué comprobarla. Un código que nunca se dispara es una promesa falsa | Se retira. En su lugar queda `422 DUPLICATE_DEFEAT` (la misma instancia dos veces en un lote), que sí depende solo de lo que Combat recibe. `defeats` vacío pasa a ser `400 SCHEMA_INVALID` |
| 2 | El contrato prometía `409` cuando el mismo `operationId` llega con otro contenido, pero describía **una tirada por documento**: con documentos sueltos no hay dónde comparar el conjunto, y la promesa era inimplementable | El lote se persiste en **un único documento** con `_id = operationId` del lote y las tiradas dentro, cada una con su clave por derrota. Una escritura atómica y comparable |

Y un límite que queda escrito en lugar de tácito: **Combat no valida que la misión exista ni que el héroe sea elegible**. La confianza se apoya en el HMAC, en la lista cerrada (`missions` es hoy el único autorizado) y en la idempotencia.

## Decisiones abiertas del PO

| # | Decisión | Estado |
| --- | --- | --- |
| `P-1` | Una recompensa por **rival derrotado** o una por victoria | **CERRADA: una por rival derrotado**, con clave por instancia real de la derrota |
| `P-2` | Redondeo **al más próximo** o **truncamiento** | **PROVISIONAL: al más próximo**: `12, 14, 17, 21, 25, 30, 36, 43`. Con truncamiento: `12, 14, 17, 20, 24, 29, 35, 42` |
| `P-3` | Corrección del enunciado de #18 (Misiones/JvE y dependencia de la cadena de Misiones) | **Ejecutada** el 2026-09-23 en el cuerpo del Issue |

**`P-2` se mantiene marcada como provisional a propósito.** Que la XP deba ser entera es una decisión tomada; **cómo** se convierte `14,4` en entero no lo es hasta que se confirme «redondeo al entero más cercano» frente a truncamiento.

## Bloqueos, medidos

Los que había el 2026-09-23 y lo que ha pasado con cada uno. **Ninguno bloquea ya la verificación**; el único abierto afecta a una sustitución declarada.

| Bloqueo | Estado | Efecto real |
| --- | --- | --- |
| **HU-08** (#17) | **Resuelto**: `HeroProgression` y el umbral por nivel están en `develop` de Player-Inventory (`f54e176`, `6ba0f5e`) | `#441` compila y acredita; `S-03` comprueba la subida de nivel con la tabla vigente |
| **HU-24** (#71) | `closed` | El motor existe: `BoundedRandom.nextInt(8) + 1`, y es el que tira en `S-01` |
| **Cadena de Misiones** | **Resuelto**: `HU-70`, `HU-71`, `HU-72`, `HU-74`, `HU-75` y `HU-76` están implementados en `develop` de Missions | `#442` existe y la cadena se recorre entera |
| **HU-71.2 — ruta interna del perfil de héroe** | **ABIERTO** (Player-Inventory PR [#48](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/48)) | Es la **única** dependencia que obliga a sustituir algo de la cadena que no sea el resultado de la simulación: el perfil y el compromiso del héroe se sirven con los dobles de desarrollo. Está declarado en la tabla de piezas y en los límites del reporte |
| **Web** (`#443`) | Sin empezar | No afecta a esta verificación: la superficie pública de HU-09 es el reporte de misión de HU-74, no una pantalla nueva |

## Criterios de aceptación y su cobertura

`CA-01` a `CA-08` son los criterios de aceptación de la HU; `CA-09` es la **condición de aceptación** y no se convierte en escenario.

| CA | Qué exige | Dónde se comprueba | Resultado |
| --- | --- | --- | --- |
| `CA-01` flujo principal | Ganar la misión devenga experiencia | `S-01` (cadena completa, 19 derrotas y 447 XP) | Verde |
| `CA-02` se aplica al héroe ganador | La XP va al héroe del resultado | `S-01`/`S-03` por `heroId` en las claves y en `hero-progressions` | Verde |
| `CA-03` fórmula `10 × 1,2^(1d8)` | El importe es el del contrato | `S-02` (ocho caras) + guarda de la fórmula (`S-11`) | Verde |
| `CA-04` `1d8` entero `1..8` del motor centralizado | La cara viene de Combat | `S-01` (19 caras reales, todas en `1..8`) + guarda del azar (`S-11`) | Verde |
| `CA-05` sin fuente de aleatoriedad distinta | Nadie más tira | Guarda estática de Combat (`S-11`), **verificada por mutación** | Verde |
| `CA-06` se acumula en el perfil | La XP se suma, no se reemplaza | `S-01` (`currentXp` = suma de las 19 recompensas) y `S-03` | Verde |
| `CA-07` verifica el umbral tras acreditar | Sube de nivel, incluido el salto múltiple | `S-03` (+1, +2 y nivel máximo sin descarte) | Verde |
| `CA-08` sin victoria válida no se otorga | Ni tirada, ni recompensa, ni acreditación | `S-07`, en sus dos formas (derrota sin bajas y simulación rechazada) | Verde |
| `CA-09` condición de aceptación de la HU | — | **No es un escenario.** Se satisface con la revisión por pares y la aprobación del PO, que están **pendientes** | — |

## Peligros registrados para quien implemente

1. **No crear un generador.** `ADR-021` da la exclusiva a Combat y las guardas estáticas del repositorio ya vigilan `Math.random`/`crypto`.
2. **No duplicar la fórmula.** Vive solo en Missions; Combat devuelve la tirada y Player/Inventory recibe un importe entero.
3. **No volver a tirar en un reintento.** Las tiradas se persisten en Combat antes de responder, con `operationId` determinista.
4. **No acreditar dos veces.** El ledger de Player/Inventory tiene `_id = operationId` y la progresión se actualiza en la misma transacción.
5. **No identificar la recompensa por el arquetipo del enemigo.** Dos `sombra-corrompida` en encuentros distintos son dos derrotas distintas: la clave es `encounter` + instancia.
6. **No dejar una tirada sin recompensa que la reclame.** La recompensa se persiste **antes** de pedir la tirada; una tirada guardada sin acreditar es aceptable mientras el barrido pueda terminarla, pero una tirada huérfana no.
7. **No mostrar como concedida una recompensa pendiente.** El reporte de misión ya separa la foto del estado de cada línea.
8. **No dar por probada la cadena desde una suite con dobles.** Añadido por esta Task: el escenario vive en `test/e2e/`, se ejecuta con `npm run test:e2e:chain`, y **`S-00` afirma el nombre del adaptador que el contenedor resolvió** para que un doble colado se vea en lugar de pasar desapercibido.
9. **No confiar en el patrón posicional de Jest.** Añadido por esta Task: Jest 30 retiró el argumento suelto y `jest <patrón>` corre el proyecto entero **en verde**. Para seleccionar un fichero, `--testPathPatterns`.

## Qué falta para cerrar HU-09

1. **Confirmación de `P-2`** por el PO (redondeo al más próximo o truncamiento); hasta entonces el contrato mantiene la marca provisional. Es la única decisión funcional abierta.
2. **Revisión por pares** de los PRs de `#440`, `#441`, `#442` y `#444`.
3. **Aceptación del PO** (`CA-09`), que es lo que convierte la verificación en aceptación.
4. **Opcional, si el PO la pide:** la visualización en Web (`#443`), que no forma parte de esta verificación.
5. **Cuando `HU-71.2` entre en `develop`:** retirar del escenario la sustitución del perfil y el compromiso del héroe, que es la última pieza simulada que no es el resultado de la simulación.


## Alineación con la progresión de HU-08

Los ejemplos de nivel que usan el contrato y esta evidencia son los de la **tabla entera y duplicativa** ya formalizada:

| Acumulado | Nivel | Por qué |
| --- | ---: | --- |
| `< 200` | 1 | El nivel 1 es el suelo |
| `200` … `399` | 2 | |
| `400` … `799` | 3 | **`749` sigue siendo nivel 3**: el nivel 4 exige `800` |
| `800` … `1.599` | 4 | |
| `1.600` … `3.199` | 5 | |
| `3.200` … `6.399` | 6 | |
| `6.400` … `12.799` | 7 | |
| `≥ 12.800` | 8 | La experiencia **sigue acumulándose** y el nivel permanece en 8 |

Sin decimales en ningún punto, y con el nivel máximo 8 sin descarte de experiencia. Verificado además que **no existe ningún `128.000`** en el repositorio: el último umbral es `12.800`.

## Pull requests de HU-09

| Task | Repositorio | PR |
| --- | --- | --- |
| `#439` diseño y contrato | Infrastructure | [#147](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/147) — mergeado |
| `#440` tirada en Combat | Combat | [#43](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/43) — mergeado |
| `#441` acreditación en Player/Inventory | Player-Inventory | [#47](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/47) — mergeado |
| `#442` coordinación y fórmula en Missions | Missions | [#17](https://github.com/Nexus-Battle-VI/Nexus-Battle-Missions/pull/17) — abierto |
| `#443` experiencia en el reporte (HU-09.5) | Missions | [#18](https://github.com/Nexus-Battle-VI/Nexus-Battle-Missions/pull/18) — abierto |
| `#444` cadena E2E, guardas y workflow | Missions | [#19](https://github.com/Nexus-Battle-VI/Nexus-Battle-Missions/pull/19) — abierto, apilado sobre #18 |
| `#444` control negativo de la guarda del azar | Combat | [#49](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/49) — abierto |
| `#444` esta evidencia y el reporte | Infrastructure | [#157](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/157) — abierto |

**Ninguno de estos PRs cierra la User Story #18.** Cierran Tasks subordinadas; la aceptación de la HU exige la revisión por pares y la aprobación del PO.

## Archivos de este entregable

**Diseño (Task `#439`, ya mergeado):**

- `docs/contracts/hu-09-experience-reward-v1.md`
- `docs/architecture/hu-09-experiencia-mision.md`
- `docs/diagrams/hu-09-use-case.puml`, `hu-09-activity.puml`, `hu-09-sequence.puml`, `hu-09-domain.puml`
- `docs/architecture/SAD.md` (§4 y §14)
- `docs/contracts/service-catalog.md`
- `README.md`

**Verificación de extremo a extremo (Task `#444`):**

- `docs/evidence/hu-09-ejecucion-e2e.json` — el reporte de ejecución
- `Nexus-Battle-Missions/test/e2e/hu-09-chain.e2e.spec.ts` — el escenario
- `Nexus-Battle-Missions/test/e2e/support/` — arranque de los hermanos, datos, app real y reporte
- `Nexus-Battle-Missions/jest.e2e.config.ts` — la suite, separada de las otras dos
- `Nexus-Battle-Missions/.github/workflows/cadena-hu-09.yml` — la cadena en CI, con los tres repositorios
- `Nexus-Battle-Combat/test/unit/hu-09-no-alternative-randomness.spec.ts` — control negativo de la guarda del azar
- este documento

## La HU no está aceptada

Ni este documento, ni el reporte de ejecución, ni ningún PR de la Task `#444` declaran HU-09 aceptada. Lo que hay es **verificación técnica en verde sobre tres repositorios sin cambios pendientes**, con las sustituciones declaradas en su sitio. La aceptación (`CA-09`) exige revisión por pares y aprobación del PO, y `P-2` sigue abierta.

