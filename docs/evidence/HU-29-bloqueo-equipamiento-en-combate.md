# HU-29 — Evidencia del diseño del bloqueo de equipamiento en combate

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#76](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/76)
- **Task de este entregable:** [#231](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/231) (diseño · `open`)
- **Tasks posteriores:** [#232](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/232) (implementación · `open`), [#233](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/233) (pruebas · `open`)
- **Fecha:** 2026-09-23
- **Requisito trazado:** `RF-29`
- **Bounded context:** Player / Inventory · Team Alfa
- **Diseño:** `Nexus-Battle-Player-Inventory/docs/hu-29-bloqueo-equipamiento-combate.md`
- **Estado:** **solo diseño.** No implementa, **no cierra la HU** y **no la da por desbloqueada**.

## Estado de la verificación: qué se comprobó y qué NO

Este documento **no declara la HU aceptada**. Declararla sería repetir el error que el Project ya
cometió: HU-29 figura `Done` en el Project **sin una sola línea en `develop`**. Lo que existe es
la especificación de diseño que la Task `#231` pide.

| Nivel | Estado |
| --- | --- |
| Caso de uso, actividades, secuencia y fragmento de dominio | **Entregados** en el diseño |
| Cobertura de arma, armadura e ítem como mutaciones bloqueadas | **Modelada**; las tres por igual, la categoría no altera la decisión |
| Rechazo + mensaje explicativo + equipo intacto | **Modelados** |
| Liberación al terminar la batalla | **Modelada**: la restricción deja de aplicarse |
| HU-28 no rediseñada | **Verificado**: el diseño la precede y no toca capacidades 2/6/2 ni recálculo |
| Sin firmas ni endpoints | **Verificado**: las cuatro menciones a `lockLoadout`, `EquipmentLockService`, `if (inBattle)` y HTTP están **en la sección que los prohíbe** |
| Trazabilidad `RF-29 → HU-29 → Diseño` | **Presente** |
| Escenarios de prueba | **10 identificados** (los 5 de la Task más 5 derivados) |
| **Implementación** | **NO existe.** En `develop` no hay guard, ni puerto, ni adaptador. Son #232 y #233 |
| **Pruebas** | **NO existen.** Son #233 |
| Endpoint o contrato HTTP | **NO se prescribe, por mandato de la Task** |
| Revisión por pares | **PENDIENTE** |
| Aceptación del PO | **PENDIENTE**, y depende de las decisiones de la sección siguiente |
| PR | **Pendiente de abrir** |

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

## Nota sobre los Pull Requests en borrador

Existen dos Pull Requests de esta HU abiertos **en borrador, con conflicto y sin actividad desde
el 10 de septiembre de 2026**:

| PR | Repo | Estado | Observación |
| --- | --- | --- | --- |
| [#26](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/26) | Player-Inventory | `open`, **draft**, `mergeable_state: dirty` | 10 commits por detrás de `develop` |
| [#90](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/90) | Web | `open`, **draft** | 34 commits por detrás de `develop` |

**No forman parte de este entregable y no se han modificado.** Se dejan anotados porque son
trabajo real que conviene decidir si se rescata o se rehace, y porque su motivo declarado para
seguir en borrador —que HU-14 no publicaba el estado de batalla— **ya no se sostiene**: el issue
`#23` figura `closed` y HU-21 ya publica el estado terminal `FINISHED`.

Una observación técnica sobre el PR #26, para cuando se decida: su modelo de estado de batalla
es una **consulta** —Player-Inventory pregunta si el héroe está en batalla—, mientras que
`ADR-019` decidió un **compromiso publicado** por Combat. La diferencia importa, porque el
compromiso evita que Player/Inventory tenga que consultar el estado de otro contexto en el
camino crítico del equipamiento. Es una decisión de la implementación (#232), no de este
diseño, que no prescribe transporte.

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
| **CA-01** | Intento en batalla activa → rechazo con mensaje, equipo sin modificaciones | **Diseñado**; escenarios 1, 2 y 3 |
| **CA-02** | No se permiten cambios de **armas** | **Diseñado**; escenario 1 |
| **CA-03** | No se permiten cambios de **piezas de armadura** | **Diseñado**; escenario 2 |
| **CA-04** | Ante un intento en batalla activa, se **rechaza** | **Diseñado**; escenarios 1, 2 y 3 |
| **CA-05** | El jugador recibe un **mensaje explicativo** | **Diseñado**; el copy está pendiente |
| **CA-06** | El equipamiento **permanece sin modificaciones** | **Diseñado**; escenario 5 |
| **CA-07** | Al finalizar, las restricciones **pueden liberarse** | **Diseñado**; escenario 4 |
| **CA-08** | Un criterio obligatorio fallido impide aceptar la HU | Condición de aceptación, **no cumplida**: falta implementación, pruebas y decisión |

**Ningún criterio está cubierto todavía en el sentido de `CA-08`**: el diseño no sustituye a la
implementación ni a las pruebas.

## Lo que falta para cerrar HU-29

1. **Decisión del PO** sobre qué cuenta como batalla activa y el texto del mensaje.
2. **Decisión de arquitectura** sobre si la épica entra en el bloqueo —hoy **no**, por lo que
   dice la HU— y sobre el mecanismo de integración, que `ADR-019` ya enmarca.
3. **Task `#232`**: implementar. Aquí sí entra la decisión de transporte, y aquí conviene
   resolver el destino de los PR #26 y #90.
4. **Task `#233`**: automatizar los 10 escenarios.
5. **Corregir la trazabilidad del Project**: HU-29 y sus tres Tasks figuran `Done` sin código en
   `develop`. **Recomendación, no acción de este entregable.**
6. **Revisión por pares** y aceptación del PO.
