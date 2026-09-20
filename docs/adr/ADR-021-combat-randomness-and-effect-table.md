# ADR-021 — Aleatoriedad de Combat y mapeo uniforme a la tabla de efectos

- **Estado:** Proposed — la decisión funcional está implementada y aceptada en los cierres de HU-24, HU-25 y HU-26 (Management), pero no hay evidencia registrada de aprobación arquitectónica formal de este ADR; ver [Evidencia](#evidencia)
- **Fecha:** 2026-09-20
- **Decide:** Arquitectura, con validación de Product Owners y Scrum Masters cuando corresponda
- **Relacionado:** [ADR-001](ADR-001-repository-strategy.md), [ADR-019](ADR-019-sprint-2-bounded-contexts.md), [ADR-020](ADR-020-realtime-combat.md), [HU-24 #71](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/71), [HU-25 #72](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/72), [HU-26 #73](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/73), [EPIC-06 #6](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/6)

## Estado

**Proposed.** No se afirma una aprobación que no está registrada.

- **Lo que sí está decidido y en `develop`:** el mecanismo funcional descrito abajo. Los cierres de [HU-24](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/71), [HU-25](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/72) y [HU-26](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/73) lo declaran «decisión técnica vigente del proyecto», y el de HU-24 anuncia que se registraría en este repositorio como ADR.
- **Lo que falta para `Accepted`:** validación de este texto por quien el gobierno del proyecto exige para un ADR (ver [Evidencia](#evidencia)). Cuando exista, se actualiza este encabezado y el índice, sin cambiar el contenido.

## Contexto

Tres Historias de Usuario de EPIC-06 definen, juntas, cómo Combat decide un resultado aleatorio:

- **HU-24** exige: Mersenne Twister; transformación Box-Müller; un único generador centralizado; valores funcionales en `1..8000`; y que el cliente no genere ni conozca el resultado, la semilla ni el estado.
- **HU-25** exige: una tabla de **exactamente 8000 filas**; tablas dependientes del tipo de héroe (Tabla 21); modificación por equipamiento; un índice que selecciona una fila; y que todo incremento de probabilidad de un efecto se reste de «no causar daño».
- **HU-26** exige validar estadísticamente la semilla del generador (media, desviación, asimetría, curtosis, Kolmogorov-Smirnov, Ljung-Box, Q-Q) y seleccionarla con evidencia.

[ADR-019](ADR-019-sprint-2-bounded-contexts.md) ya decidió **dónde** vive la aleatoriedad (solo en Combat). Este ADR decide **qué** produce y cómo se relaciona con la tabla.

## Problema

El texto de HU-24 habla de una distribución **normal** para un valor en `1..8000`, y la tabla de HU-25 asigna probabilidad por **cantidad de filas** de esas 8000. Ambas cosas no son compatibles si la normal se aplica directamente al índice:

- En HU-25, «4800 filas de 8000» significa 60 %. Eso solo es cierto si **cada fila tiene la misma probabilidad, 1/8000**.
- Una normal sobre `1..8000` da más probabilidad a las filas centrales que a las extremas: las filas no pesan lo mismo.

El estudio de HU-26 lo midió: una zona configurada con el 60 % de las filas (`1..4800`, «causar daño») recibía **≈ 72,6 %** de las ocurrencias al usar directamente una normal como índice ([#363](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/363)). Con la normal centrada en 4000,5 y desviación ≈ 1333, la probabilidad de caer en `1..4800` es Φ((4800,5 − 4000,5) / 1333) ≈ Φ(0,60) ≈ 72,6 %, no 60 %.

## Decisión

**La normalidad es propiedad de la variable intermedia; la uniformidad es propiedad del índice que consulta la tabla.** Las dos se separan de forma explícita:

| Concepto | Distribución | Para qué sirve |
| --- | --- | --- |
| Variable intermedia `Z` (salida de Box-Müller en Combat) | Normal estándar, `Z ~ N(0,1)` | Cumple el requisito de MT19937 + Box-Müller y es la entrada de la CDF `Φ` |
| Representación normal escalada de la variable (estudio HU-26) | Normal con media ≈ 4000 y desviación ≈ 1333, sobre el rango del índice | Es sobre la que trabajó el estudio estadístico aceptado de HU-26 ([#363](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/363), [#364](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/364)) para seleccionar la semilla |
| Índice `RandomIndex` | **Uniforme** discreta sobre `1..8000` | Selecciona una fila de la tabla de HU-25; cada fila pesa `1/8000` |

Esta separación es una **decisión arquitectónica consciente**, no un detalle de implementación: es lo que permite que HU-24 (normal), HU-25 (filas como probabilidad) y HU-26 (estudio estadístico aceptado sobre la representación normal escalada) sean ciertas a la vez.

## Flujo de generación

```text
runtime actual:
  semilla ──► MT19937 ──► Box-Müller ──► Z ~ N(0,1) ──► U = Φ(Z) ──► índice 1..8000 ──► tabla vigente (HU-25) ──► efecto

HU-26 (estudio aceptado, no es código runtime):
  MT19937 + Box-Müller ──► variable normal escalada ──► media, desviación, asimetría, curtosis, KS, Ljung-Box, Q-Q
                                                    ──► selección de la semilla 3.000.000
```

1. Una **semilla** inicializa MT19937.
2. MT19937 aporta los uniformes que necesita Box-Müller.
3. Box-Müller produce valores aproximadamente `N(0,1)`.
4. Ese procedimiento (MT19937 + Box-Müller) es el que analizó el estudio estadístico aceptado de HU-26, sobre su **representación normal escalada** al rango del índice; el runtime actual usa `Z ~ N(0,1)` en este paso. Ver [Semilla validada HU-26](#semilla-validada-hu-26) y sus límites.
5. Se aplica la función de distribución acumulada de la normal estándar: `U = Φ(Z)`.
6. Por la transformación integral de probabilidad, `U ~ Uniforme(0,1)`.
7. El índice funcional es, conceptualmente, `floor(U × 8000) + 1`.
8. Se protege el límite superior para garantizar `1 ≤ índice ≤ 8000` (un `U` que redondee a 1 no produce 8001).
9. El índice se entrega como el objeto de valor `RandomIndex`, válido por construcción.
10. HU-25 usa **únicamente** ese `RandomIndex` para consultar la tabla.

La secuencia conserva su **estado**: la semilla se entrega al **crear** la secuencia y cada llamada avanza el generador. No hay reinicio por llamada, ni singleton, ni semilla global.

### Semilla ≠ índice

La **semilla inicializa MT19937**; el **índice es una salida posterior** del generador. No son la misma cosa y no comparten dominio:

- la semilla no está restringida conceptualmente a `1..8000` (la implementación la acepta como entero sin signo de 32 bits, decisión técnica de Combat porque el requisito no la define);
- la semilla no se usa como fila, como porcentaje ni como efecto;
- la semilla no se envía al cliente.

## Integración HU-24 / HU-25

**HU-24 genera el índice; HU-25 configura la tabla y lo resuelve.** Son responsabilidades separadas: HU-25 depende del contrato `RandomSequencePort.nextIndex()`, no de MT19937, Box-Müller, la semilla ni la normal.

### La tabla no es una colección de 8000 documentos

La representación productiva es `EffectControlTable`: **rangos contiguos** equivalentes conceptualmente a las 8000 filas, en un orden fijo (daño, daño crítico, evade, resiste, escapa, no causa daño; 1 punto porcentual = 80 filas). Ejemplo, Guerrero Armas base (Tabla 22):

| Efecto | Porcentaje | Filas | Rango |
| --- | ---: | ---: | --- |
| `DAMAGE` | 60 % | 4800 | 1–4800 |
| `CRITICAL_DAMAGE` | 5 % | 400 | 4801–5200 |
| `EVADE` | 3 % | 240 | 5201–5440 |
| `ESCAPE` | 2 % | 160 | 5441–5600 |
| `NO_DAMAGE` | 30 % | 2400 | 5601–8000 |

Un `RandomIndex(4975)` resuelve `CRITICAL_DAMAGE`. La tabla es una estructura de dominio construida **en memoria**; no se persiste.

### Tabla vigente: del equipamiento a las filas

```text
Player-Inventory ──► héroe equipado ──► subtype + activeEffects ──► Combat
   Combat: BuildHeroEffectTable ──► tabla base del subtype ──► modificadores soportados ──► tabla vigente
   Combat: ResolveRandomEffect(sequence, tabla vigente) ──► efecto y magnitud
```

- **Player-Inventory** es dueño del héroe, su equipamiento, sus estadísticas efectivas y sus `activeEffects`. Los entrega a Combat por el contrato interno firmado con HMAC (`GET /api/internal/v1/players/:playerId/equipped-hero`).
- **Combat** es dueño de las reglas de combate, la tabla probabilística, la aplicación de esos efectos a la tabla, la aleatoriedad y la resolución del índice. **No duplica reglas de equipamiento**: recibe los efectos ya normalizados.

### `CRITICAL_CHANCE`

Un efecto `STAT_MODIFIER` sobre `CRITICAL_CHANCE` con `INCREASE`, magnitud `PERCENTAGE`, objetivo `SELF`, sin condición de activación y sin duración se interpreta, **dentro de `EffectControlTable`**, como un incremento **absoluto** de probabilidad:

```text
100 puntos básicos = +1 punto porcentual = +80 filas
300 pb = +3 pp = +240 filas          600 pb = +6 pp = +480 filas
```

Justificación: la Tabla 23 del documento oficial lleva el crítico de Guerrero Armas de **5 % a 11 %** y «no causar daño» de **30 % a 24 %** con un equipamiento de «+6 %» (5 + 6 = 11; 30 − 6 = 24). Con `+300 pb` el crítico pasa de 400 a 640 filas (8 %) y «no causar daño» de 2400 a 2160 (27 %).

Esta semántica es **local** a `CRITICAL_CHANCE` y a la tabla de HU-25. **No redefine `PERCENTAGE`** para el resto de estadísticas ni en Catalog.

### Resolución

`ResolveRandomEffect` recibe una `RandomSequencePort` y una `EffectControlTable` vigente y ejecuta: `sequence.nextIndex()` → `table.resolve(index)` → `ResolvedRandomEffect` (efecto y magnitud). Consume **exactamente un índice** por resolución válida. No genera otra variable aleatoria y no usa `Math.random`, `node:crypto` como selector funcional, otro MT19937, otra semilla ni otro Box-Müller (hay una guarda estática en las pruebas de Combat que lo verifica).

## Semilla validada HU-26

**`SEMILLA_SELECCIONADA = 3.000.000`** es la semilla seleccionada y ratificada por HU-26.

- **Estudio aceptado** ([#362](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/362), [#363](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/363), [#364](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/364)): 11 candidatas; 100 000 observaciones por candidata; MT19937 + Box-Müller; media, desviación estándar, asimetría, exceso de curtosis, Kolmogorov-Smirnov, Ljung-Box (lags 10, 20, 30, 40 y 50) y gráfico Q-Q.
- **Criterio experimental documentado:** α = 0,05; se conservan las candidatas con KS *p* > 0,05 y mínimo de Ljung-Box *p* > 0,05, y entre ellas se elige la de menor KS *D*. Son decisiones experimentales del estudio, no requisitos funcionales.
- **Resultado registrado para 3.000.000** (aprox., según #363/#364): media 4000,909071; desviación 1312,287244; asimetría 0,001692; exceso de curtosis −0,179680; KS *D* 0,001678; KS *p* 0,940408; mínimo Ljung-Box *p* 0,565086; Q-Q alineado con la referencia.
- **Escala de esas cifras:** son las del estudio, expresadas sobre la variable normal escalada al rango del índice (media ≈ 4000, desviación ≈ 1333), no sobre la `Z ~ N(0,1)` (media 0, desviación 1) que genera hoy la implementación TypeScript. No son comparables en valor absoluto con las de `Z`.
- **Alcance de la evidencia:** el estudio aceptado valida el comportamiento normal del procedimiento y selecciona la semilla `3.000.000`, pero **no constituye una prueba de paridad numérica exacta** entre las muestras históricas del cuaderno y la secuencia `Z ~ N(0,1)` de la implementación TypeScript actual. HU-26 se acepta como estudio de selección y validación, no como verificación de la `Z` productiva.

> Se realizó posteriormente una re-ejecución exploratoria que no fue adoptada ni integrada y, por tanto, no sustituye la selección vigente de HU-26 ([Combat #19](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/19), cerrado sin merge).

### Qué significa y qué no significa la semilla 3.000.000

- **Es** la semilla de referencia validada del proyecto.
- **No implica** que todas las batallas reinicien MT19937 con 3.000.000. Auditado el código de Combat en `develop` (2026-09-20): existe la fábrica de secuencias y su registro en el contenedor, pero **ningún caso de uso la consume todavía y no hay política de semilla implementada**: ni creación por batalla o simulación, ni persistencia, ni repetición (*replay*), ni rotación, ni semilla global de arranque. `3.000.000` solo aparece en pruebas de Combat como valor de referencia.
- La política concreta de ciclo de vida de la semilla en cada Battle/Simulation queda **PENDIENTE DE IMPLEMENTACIÓN RUNTIME**. Como declara el cierre de HU-24, puede evolucionar con el agregado de batalla sin reabrir el mecanismo funcional.

## Seguridad

- **Ningún cliente genera `RandomIndex`.** Web no elige semilla, no elige efecto y no envía `activeEffects` a Combat.
- Los `activeEffects` provienen de **Player-Inventory** por la integración interna con HMAC (`x-internal-service`, `x-internal-timestamp`, `x-internal-signature`); las rutas `/api/internal*` no son accesibles desde fuera (Caddy responde `404`).
- La semilla **no forma parte de ningún DTO público**; el estado de MT19937 y la normal cruda no se exponen; el índice interno no tiene por qué mostrarse al jugador. No existe un endpoint de números aleatorios (`/random`, `/rng`, `/seed`).
- **MT19937 no es un generador criptográficamente seguro** y este ADR no afirma lo contrario. La protección actual es de **autoridad**: semilla, estado, secuencia y resultados internos permanecen en el servidor, bajo Combat. Un MT19937 es predecible a partir de suficientes salidas consecutivas del generador en bruto; por eso no se expone ninguna.
- Sigue vigente lo de [ADR-020](ADR-020-realtime-combat.md): nunca viajan la semilla, el estado del generador ni resultados aleatorios futuros.

## Missions y reutilización del motor

Se conserva y refuerza la decisión de [ADR-019](ADR-019-sprint-2-bounded-contexts.md): **Missions no implementa MT19937, Box-Müller, tablas de efectos ni selección de semilla.** Pide una simulación a Combat y guarda el resultado:

```text
Missions ──► contrato interno (previsto) ──► Combat: motor de combate + HU-24 + HU-25 ──► resultado ──► Missions
```

Así hay una sola implementación de la aleatoriedad y las reglas; un generador en Missions permitiría que los resultados divergieran de los de Combat.

**Estado:** el contrato `POST /api/internal/v1/combat/simulations` figura en la documentación de Combat como **previsto**; no está formalizado ni implementado. Queda por decidir, al formalizarlo, si la semilla la aporta el llamante o la fija Combat.

## Consecuencias

**Lo que se gana**

- Una única autoridad de aleatoriedad (Combat).
- Las probabilidades de las tablas se respetan: `4800/8000` filas son el 60 %.
- El PRNG es reproducible: misma semilla, misma secuencia (verificado en las pruebas de Combat).
- Separación explícita entre variable normal e índice.
- Sin dependencia del cliente.
- Missions reutiliza exactamente el mismo motor.
- HU-25 no depende de la implementación concreta del PRNG.

**Lo que cuesta**

- Una transformación adicional (la CDF `Φ`) entre la normal y el índice.
- El requisito textual («distribución normal» para un valor `1..8000`) debe leerse distinguiendo variable normal e índice. La interpretación está registrada en los cierres de HU-24/25/26; no fue ratificada por escrito por el Product Owner o el profesor como aclaración del requisito.
- MT19937 no es un CSPRNG.
- Cambiar esta interpretación exige **otro ADR o un ADR que supere a este**, no editar la historia en silencio.

## Alternativas consideradas

| Alternativa | Decisión | Motivo |
| --- | --- | --- |
| **A. Normal directa sobre el índice `1..8000`** | Descartada | Deforma las probabilidades que representan las filas: el 60 % de filas recibe ≈ 72,6 % de las ocurrencias |
| **B. Uniforme directo, sin Box-Müller** | Descartada | El requisito exige MT19937 + Box-Müller y la normal forma parte de HU-24 y del estudio de HU-26 |
| **C. Normal → CDF → uniforme → índice** | **Seleccionada** | Conserva la normal intermedia (y el estudio de HU-26 sobre ella) y da un índice uniforme por fila |
| **D. Microservicio Random independiente** | Descartada | Combat ya es dueño de la batalla, las simulaciones y el motor; un servicio RNG sin datos propios incumple [ADR-001](ADR-001-repository-strategy.md), añade un salto de red y contradice [ADR-019](ADR-019-sprint-2-bounded-contexts.md) |
| **E. Generador duplicado en Missions** | Descartada | Duplica reglas y permite que los resultados diverjan de los de Combat |

**Infraestructura nueva: ninguna.** Esta decisión no requiere Lambda, SQS, Redis, DynamoDB, RDS, una base nueva, un microservicio de aleatoriedad, una tabla SQL de probabilidades ni una colección de las 8000 filas. La tabla es una estructura de dominio en memoria.

## Limitaciones / decisiones aún pendientes

Son evolución posterior del motor o de las historias consumidoras, **no incumplimientos** de HU-24, HU-25 ni HU-26.

- **Política de semilla por Battle/Simulation:** creación, persistencia, repetición y rotación. Pendiente de implementación runtime; no existe agregado de batalla que la aloje.
- **Persistencia de semilla:** [ADR-019](ADR-019-sprint-2-bounded-contexts.md) la describe como diseño objetivo («cada batalla y simulación guarda su semilla»); no está implementada en Combat.
- **Paridad con el estudio:** el estudio aceptado de HU-26 valida el comportamiento normal del procedimiento y selecciona `3.000.000`, pero no prueba paridad numérica exacta entre las muestras históricas del cuaderno y la secuencia `Z ~ N(0,1)` de la implementación TypeScript actual (depende, entre otras cosas, de cómo inicializó el estudio el MT19937 y de la escala de la variable). La ratificación de 3.000.000 se apoya en #362–#364. Una validación estadística directa sobre la `Z` productiva sería una evolución posterior, no un requisito pendiente de HU-26.
- **Rango de semilla:** la implementación usa entero sin signo de 32 bits; una candidata histórica del estudio (7.294.967.295) excede ese rango. No afecta a la seleccionada (3.000.000).
- **Crítico 120–180 %:** sin selector formal de un valor concreto dentro del rango.
- **Chamán y Médico:** la Tabla 21 les da 0 % en todo; no tienen tabla válida y Combat lo rechaza de forma explícita, sin inventar una.
- **Efectos de equipamiento sin semántica aprobada:** condicionados, temporales, dirigidos a otro participante, operaciones distintas de `INCREASE` y magnitudes `FIXED`/`DICE` sobre `CRITICAL_CHANCE` no modifican la tabla.
- **Missions → Combat:** contrato de simulación previsto, no implementado.
- **HU-20 (Ataque > Defensa):** consumidora de HU-24 y HU-25, en desarrollo por separado; hoy nada en Combat invoca `BuildHeroEffectTable` ni `ResolveRandomEffect`.

## Evidencia

**Decisión y cierres (Management):**

- [HU-24 #71](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/71), [HU-25 #72](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/72) y [HU-26 #73](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/73): cerradas, con la decisión «normal intermedia → CDF → índice uniforme 1..8000 → tabla HU-25» en sus comentarios de cierre.
- [#362](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/362), [#363](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/363) y [#364](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/364): estudio de semillas y selección de 3.000.000 (cuaderno de Colab enlazado en ellas).

**Implementación integrada en `develop` (Combat):**

- [#14](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/14) motor pseudoaleatorio (HU-24) y [#15](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/15) separación de la secuencia normal y la de índices.
- [#16](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/16) y [#17](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/17) tabla de efectos (HU-25).
- [#22](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/22) integración del héroe equipado con Player-Inventory y [#23](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/23) aplicación de `CRITICAL_CHANCE` a la tabla.
- Documentación de Combat: [hu-24-randomness-engine.md](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/blob/develop/docs/hu-24-randomness-engine.md) y [hu-25-effect-control-table.md](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/blob/develop/docs/hu-25-effect-control-table.md).

**Integración (Player-Inventory):** [#35](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/35) expone `activeEffects` a Combat.

**No integrado y sin valor de fuente de verdad:** [Combat #19](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/19), re-ejecución exploratoria cerrada sin merge.

**Diagrama:** [combat-randomness.puml](../diagrams/combat-randomness.puml).

**Aprobación de este ADR:** no existe registro de validación arquitectónica. Para pasar a `Accepted` se necesita, como mínimo, la revisión de quien haya de validarlo según el gobierno del proyecto y la confirmación de los puntos de [Limitaciones](#limitaciones--decisiones-aún-pendientes) que dependan de ella (en particular, la lectura «variable normal / índice uniforme» del requisito).
