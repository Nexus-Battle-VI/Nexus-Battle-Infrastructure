# HU-08 — Evidencia de progresión: experiencia requerida por nivel

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#17](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/17)
- **Tasks:** [#188](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/188) (diseño · `open`), [#189](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/189) (implementación · `open`), [#190](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/190) (pruebas · `open`)
- **Fecha:** 2026-09-23
- **Requisito trazado:** `RF-08`
- **Bounded context:** Player / Inventory · Team Alfa
- **Pull Requests (Player/Inventory, contra `develop`, en orden de integración):** [#42](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/42) diseño (`docs/hu-08-1-diseno-progresion`) → [#43](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/43) implementación (`feat/hu-08-2-umbral-experiencia`) → [#44](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/44) pruebas (`test/hu-08-3-pruebas-progresion`)
- **Matriz de trazabilidad:** [Nexus-Battle-Player-Inventory/docs/hu-08-matriz-de-pruebas.md](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/blob/develop/docs/hu-08-matriz-de-pruebas.md)
- **Estado:** diseño, implementación y suite de pruebas entregados, **ajustados a la aclaración funcional del Product Owner**. **La HU no está aceptada**: falta revisión por pares y aceptación del PO, y `CA-03` y `CA-06` siguen sin resolverse.

## Qué cambió en esta revisión, y por qué

El Product Owner aclaró la regla funcional **después** del enunciado original de la HU `#17`, y la aclaración **cambia el comportamiento ya diseñado**. Las tres Tasks se rehicieron con ese contexto, y las cuatro cosas que se mezclan van separadas porque no tienen la misma autoridad:

| Origen | Contenido | ¿Gobierna hoy? |
| --- | --- | --- |
| **Requisito original** (HU `#17`) | `CA-03`: el umbral se calcula con `100 × 1,2^(Nivel − 1)` | **No** |
| **Aclaración del PO** (posterior y aprobada) | Tabla de umbrales acumulados `100 · 200 · 400 · 800 · 1.600 · 3.200 · 6.400 · 12.800`; el nivel sale del acumulado; la XP no se resta; un otorgamiento puede cruzar varios niveles; en el nivel 8 la XP sigue creciendo y no se descarta; la XP es entera y es del héroe | **Sí** |
| **Decisión arquitectónica** (`ADR-019`, `ADR-021`) | La tirada `1d8` nace en Combat y se persiste antes de cualquier efecto remoto; Missions coordina y calcula `10 × 1,2^(1d8)`; **Combat no calcula la recompensa**; Player/Inventory solo acredita la XP al `heroId` | Sí, y no es de esta HU |
| **Decisión técnica** (estas Tasks) | La tabla vive en un único punto; `amount` es XP acumulada y no un incremento; `restore` rechaza un documento incoherente; se retira el campo `decimal` y la aritmética racional | Sí, y es revisable |

**La divergencia con `CA-03` está medida, no tapada:** la fórmula antigua da `100, 120, 144, 172,8, 207,36, 248,832, 298,5984` y la tabla aprobada da otra serie. **No es una diferencia de redondeo** —el cociente entre ambas no es constante (1,667 en el nivel 2; 2,778 en el nivel 3)—, así que ninguna precisión convierte una en la otra. Gobierna la tabla; el Issue **no** se ha modificado y requiere corrección del PO.

## Estado de la verificación: qué se comprobó y qué NO

Este documento **no declara la HU aceptada**. Lo que existe es la especificación, su implementación y la evidencia de ejecución de sus pruebas. Declarar aquí una aceptación sería exactamente el error que el Project ya cometió con HU-29 y HU-31, marcadas `Done` sin código en `develop`.

| Nivel | Estado |
| --- | --- |
| Diseño de dominio, caso de uso y diagramas | **Entregado** en `Nexus-Battle-Player-Inventory/docs/hu-08-progresion.md` |
| Matriz de trazabilidad `RF-08 → CA → escenario → nivel → resultado → tipo → script` | **Entregada** en `Nexus-Battle-Player-Inventory/docs/hu-08-matriz-de-pruebas.md` |
| Modelo de dominio y objetos de valor | **Implementados** (`ExperiencePolicy`, `HeroLevel`, `Experience`, `HeroProgression`) |
| Persistencia: migración `008-hero-progressions` | **Implementada**, con validador `$jsonSchema` en el motor |
| Adaptadores Mongo y en memoria, con bloqueo optimista | **Implementados** |
| Registro en el contenedor y operación reutilizable | **Implementados**, con prueba de cableado |
| Tabla de umbrales aprobada, aplicada en un único punto | **Verificada** contra la tabla de referencia del PO, guardada en `test/fixtures/experience-threshold-reference.json` |
| Regresión con los vectores del PO | **Verificada**: `749 → 3`, `849 → 4`, `890 → 4`, `3.500 → 6`, `13.000 → 8`, `13.500 → 8`, `190 + 700`, `749 + 100` |
| Control de tabla única | **Ejecutado**: `no-duplicate-experience-thresholds.spec.ts` falla si otro archivo reproduce la serie o la calcula con una expresión |
| Coherencia nivel ↔ acumulado | **Verificada** en el dominio y contra MongoDB real: un documento incoherente da error controlado |
| Determinismo | **Verificado**: 50 consultas por nivel de referencia, 50 resoluciones por acumulado, y el orden no altera el resultado |
| Pruebas unitarias | **Ejecutadas: 32 suites / 697 pruebas, en verde** |
| Pruebas de integración HTTP | **Ejecutadas: 10 suites / 105 pruebas, en verde** |
| Pruebas contra MongoDB real | **Ejecutadas: 8 suites / 80 pruebas, en verde** |
| Casos de HU-08 | **121 en total**: 109 en la suite unitaria y 12 en la de base de datos |
| Cobertura de la regla (`ExperiencePolicy`) | **97,4 % sentencias · 92,9 % ramas · 100 % funciones** |
| Cobertura global | **92,4 % sentencias / 84,0 % ramas / 90,8 % funciones** — sobre el umbral del 80 % |
| `lint`, `format:check`, `typecheck`, `build` | **Ejecutados y limpios** |
| **Que el motor rechace persistir el umbral** | **Verificado con MongoDB real**: insertar `nextLevelThreshold` a mano falla |
| Pruebas de redondeo del umbral | **NO aplican, y es un cambio**: la tabla aprobada es entera y no hay nada que redondear. El redondeo que sigue abierto es el de la **recompensa**, que es de Missions |
| Casos de `CA-03` | **NO existen, y es deliberado**: el criterio enuncia la fórmula sustituida. Ver `D-3` |
| Casos de `CA-06` | **NO existen, y es deliberado**: la regla existe pero no es de esta historia. Ver `D-4` |
| Revisión por pares | **PENDIENTE.** Es requisito del ruleset: 1 aprobación + Code Owner |
| Aceptación del PO | **PENDIENTE**, y bloqueada por `CA-03` y `CA-06` |
| Uso del producto desplegado | **NO aplica**: no hay endpoint ni pantalla que consuma la progresión |

## Reporte de ejecución (punto 8 de la Task #190)

### Identificación de la ejecución

| Campo | Valor |
| --- | --- |
| Fecha | 2026-09-23 |
| Versión del paquete | `0.1.0` |
| Commit bajo prueba | `f205fce` (rama `feat/hu-08-2-umbral-experiencia`) y `16ddd42` (rama `test/hu-08-3-pruebas-progresion`) |
| Base | `develop` @ `67ed85a` (incluye HU-65) |
| Ambiente | Desarrollo local, Windows · Node `v24.19.0` · npm `11.17.0` |
| MongoDB para `test:db` | Contenedor `mongo:8.0` vía Testcontainers · lo ejecuta el CI |
| Comando | `npm run lint && npm run format:check && npm run typecheck && npm run test:unit && npm run test:integration && npm run test:coverage && npm run build && npm run test:db` |

### Casos ejecutados

| Suite | Suites | Casos | Aprobados | Fallidos | Bloqueados |
| --- | ---: | ---: | ---: | ---: | ---: |
| Unitaria (`test:unit`) | 32 | 697 | **697** | 0 | 0 |
| Integración HTTP (`test:integration`) | 10 | 105 | **105** | 0 | 0 |
| Base de datos (`test:db`) | 8 | 80 | **80** | 0 | 0 |
| **Total** | **50** | **882** | **882** | **0** | **0** |

**Casos de HU-08: 121** — 109 en la suite unitaria y 12 contra MongoDB real, repartidos en 8 archivos de prueba unitaria y 1 de base de datos. El detalle por escenario está en la matriz de trazabilidad.

### Cobertura disponible

| Ámbito | Sentencias | Ramas | Funciones | Líneas |
| --- | ---: | ---: | ---: | ---: |
| **Global del servicio** | 92,4 % | 84,0 % | 90,8 % | 92,4 % |
| `ExperiencePolicy.ts` (la regla) | 97,4 % | 92,9 % | **100 %** | 96,7 % |
| `HeroProgression.ts` | **100 %** | **100 %** | **100 %** | **100 %** |
| `GetHeroProgression.ts` | **100 %** | **100 %** | **100 %** | **100 %** |
| `QueryExperienceThreshold.ts` | **100 %** | **100 %** | **100 %** | **100 %** |
| `hero-progression-mapping.ts` | **100 %** | **100 %** | **100 %** | **100 %** |
| `InMemoryHeroProgressionRepository.ts` | **100 %** | **100 %** | **100 %** | **100 %** |
| `experience.ts` | **100 %** | **100 %** | **100 %** | **100 %** |
| `hero-level.ts` | 75 % | 64,3 % | **100 %** | 82,4 % |

Umbral configurado en Jest: **80 %**. Artefacto publicado por CI: `coverage-player-inventory` (`coverage/`, con `lcov`, `json-summary` y `json`).

**Cobertura no perseguida, y por qué:** quedan sin cubrir cinco sentencias de `hero-level.ts` —las ramas que formatean un valor rechazado en el mensaje de error— y una rama de `ExperiencePolicy.ts`, la guarda que lanza si se le pide el umbral de un nivel fuera de la tabla, **inalcanzable desde fuera** porque las dos operaciones públicas validan el rango antes de llamarla. La Task #190 prohíbe aumentar cobertura con pruebas triviales sin valor funcional, y comprobar cómo se escribe un mensaje de diagnóstico no verifica la tabla, el rango ni los límites. Se documenta el hueco en lugar de taparlo.

### Defectos

| # | Defecto | Estado |
| --- | --- | --- |
| D-1 | La regla estaba expresada con la fórmula `100 × 1,2^(Nivel−1)` que el PO sustituyó por la tabla | **Corregido** en `#188` y `#189`: la política aplica la tabla y la suite fija los ocho valores |
| D-2 | El umbral podía persistirse por descuido en un cambio futuro | **Prevenido**: `additionalProperties: false` y una prueba contra MongoDB real que lo comprueba |
| D-3 | `CA-03` enuncia la fórmula sustituida: **bloquea la aceptación de la HU** | **Abierto.** Requiere que el PO reescriba el criterio |
| D-4 | `CA-06` es criterio obligatorio sobre materia fuera de alcance, ahora con fórmula del PO pero sin implementar y sin cubrir las estadísticas de dado | **Abierto.** Requiere decisión de PO y arquitectura |
| D-5 | La migración `007` chocaba con la de HU-65, que ya ocupaba ese número en `develop` | **Corregido** al integrar: renumerada a `008-hero-progressions` |

**Sobre `D-1`, un efecto secundario que conviene registrar:** con la fórmula, el diseño tenía que resolver la representación exacta de `1,2` —`172.79999999999998` frente a `172,8`— con aritmética racional y un campo `decimal`. Con la tabla ese problema **desaparece**: no hay fracciones, así que el campo `decimal` y la aritmética con `BigInt` se retiraron junto con la fórmula que los necesitaba.

**Sobre `D-5`:** ninguna prueba lo habría detectado, porque las dos migraciones son válidas por separado; lo que quedaba roto era la numeración, que es lo que hace legible en qué orden se construyó el esquema.

### Observaciones para aceptación

1. **La HU no puede aceptarse todavía.** `CA-03` enuncia una fórmula que ya no gobierna el cálculo y `CA-06` es obligatorio y no está implementado: por `CA-08`, HU-08 queda formalmente inaceptable mientras los dos sigan en su redacción actual. Son decisiones de Product Owner, no trabajo de desarrollo.
2. **La política de redondeo del umbral ya no es una decisión pendiente**: la tabla aprobada es entera. Lo que sigue abierto es el redondeo de la **recompensa** (`10 × 1,2^(1d8)`), que vive en Missions y que Player/Inventory ni calcula ni decide.
3. **`CA-07` se cubre en proceso, no por HTTP.** No hay endpoint y ninguno está pedido; el consumidor verificado es el caso de uso y la operación reutilizable, no una ruta.
4. **Falta la revisión por pares**, que el ruleset exige (1 aprobación + Code Owner) y que ningún desarrollador puede darse a sí mismo.
5. **`EN-015` (#200) y `EN-016` (#201) siguen `open`.** Esta Task se apoya en lo ya existente: no añadió dependencias ni reporteros nuevos, salvo `json` en la configuración de cobertura, que es salida estándar de Jest.

## Criterios de aceptación

| Criterio | Estado | Evidencia |
| --- | --- | --- |
| **CA-01** — El nivel actual produce el umbral del siguiente nivel | **Cubierto y probado** | `experience-policy.spec.ts`: nivel 1 → `200` hacia el 2; nivel 4 → `1600` hacia el 5; nivel 7 → `12800` hacia el 8 |
| **CA-02** — Los héroes progresan de nivel 1 a nivel 8 | **Cubierto y probado** | `MIN_HERO_LEVEL` / `MAX_HERO_LEVEL` y `HeroLevel`, que valida la invariante. `hero-progression.spec.ts` rechaza nivel 0 y 9, y el acumulado incoherente |
| **CA-03** — El umbral se calcula con `100 × 1,2^(Nivel−1)` | **DIVERGENTE — no se declara cumplido** | El código aplica la tabla aprobada por el PO. La serie antigua se conserva en el fixture (`supersededFormula`) y una prueba comprueba que la tabla **no** la reproduce. Ver `D-3` |
| **CA-04** — El cálculo usa como entrada el nivel actual | **Cubierto y probado** | La firma recibe `currentLevel` y nada más. Se rechazan `'3'`, `null`, `NaN`, decimales y fuera de rango |
| **CA-05** — El sistema no calcula un siguiente nivel fuera del rango máximo | **Cubierto y probado** | Nivel 8 → `status: 'MAX_LEVEL'` con `forNextLevel: null`. La operación no puede producir un nivel 9 |
| **CA-06** — El nivel actúa como factor multiplicador sobre el resto de las estadísticas | **FUERA DE ALCANCE — y con la HU formalmente inaceptable mientras siga así** | El PO ya dio la regla, pero no es de esta historia y no cubre las estadísticas de dado. **No se automatiza ninguna prueba** de este criterio, de forma deliberada |
| **CA-07** — El valor queda disponible como umbral del siguiente nivel | **Cubierto y probado** | `QueryExperienceThreshold` es el único punto por el que los consumidores piden el umbral; `hero-progression-wiring.spec.ts` comprueba que se resuelve y calcula sin conocer la tabla |
| **CA-08** — Un criterio obligatorio fallido impide aceptar la HU | **NO SE CUMPLE, y es el hallazgo** | `CA-03` y `CA-06` son obligatorios y no pueden aprobarse: **HU-08 no puede aceptarse hoy** |

## Reglas del PO que no tienen `CA` propio, y sí tienen prueba

| Regla aclarada por el PO | Cómo se verifica |
| --- | --- |
| La XP es **acumulada** y no se resta al subir | `749 + 100 = 849` con nivel 4, en el agregado y leyendo el caso de uso |
| Un solo otorgamiento puede **cruzar varios niveles** | `190 + 700 = 890` deja al héroe en el nivel 4, no en el 2 |
| En el **tope** la XP sigue creciendo y no se descarta | `13.000 + 500 = 13.500`, nivel 8, sin rechazo |
| La XP es **entera** | `14,4` se rechaza en el agregado; la recompensa se redondea antes de llegar |
| El nivel sale del **acumulado** | Los cuatro vectores del PO y las fronteras exactas de los ocho umbrales |
| La XP es **del héroe** | Agregado por `(jugador, héroe)`, con aislamiento probado entre héroes del mismo jugador |

## CA-06 queda fuera, y bloquea la aceptación de la HU

`CA-06` exige que «el nivel del héroe actúe como factor multiplicador sobre el resto de sus estadísticas conforme a las reglas del juego». **No se implementa, no se modela y no se prueba.**

**El motivo cambió respecto de la primera versión de este documento, y hay que decirlo:** entonces no existía fórmula en ninguna fuente. **La aclaración del PO sí la da** —la estadística del nivel 1 multiplicada por el nivel actual, con el equipamiento aplicado después—, de modo que el criterio pasa a ser implementable. Sigue fuera de HU-08 por tres fundamentos que no dependen de que exista fórmula:

1. **La propia HU declara la materia fuera de alcance.** El cuerpo de la Task `#188` enumera lo que HU-08 **no** es responsable de hacer, y esa lista incluye **«recalcular reglas de combate»**. Las estadísticas del héroe son materia de combate.
2. **La Task exige no acoplarse.** `#188` pide que HU-08 «no quede acoplada a una modalidad específica como batalla o misiones», y en sus condiciones de finalización exige que «**no se incorporaron responsabilidades de batalla o misiones**».
3. **Tocaría dos contratos ajenos.** La multiplicación ocurriría en `computeEffectiveStats` (HU-28) y en el contrato interno `equipped-hero` (HU-15), que hoy es un subconjunto deliberado **sin nivel**. Ninguno de los dos es de esta historia.

**Y hay un caso que la aclaración no resuelve, y no se inventa aquí:** las estadísticas expresadas como **dados** —el `1d8` que Combat documenta en su `AttackProfile`— no tienen definida la multiplicación por nivel. Multiplicar una expresión de dado por un entero no es lo mismo que multiplicar un número.

**No se automatiza ninguna prueba que fije ese comportamiento**, siguiendo el patrón que HU-07 aplicó a su propio `CA-09`, con el mismo razonamiento textual de su Task:

> «Tampoco deben convertir en prueba de HU-07 la regla de modificación durante combate, ya que pertenece a HU-29 y actualmente existe una inconsistencia documental que debe ser resuelta antes de automatizar dicho comportamiento como requisito definitivo.»

### Consecuencia que hay que dejar escrita

Como `CA-08` establece que «un criterio obligatorio fallido impide aceptar la HU», y `CA-03` y `CA-06` son obligatorios y **no pueden aprobarse**, **HU-08 es hoy formalmente inaceptable**. No es un problema de la implementación: es un problema de la redacción de la historia.

Hay tres salidas para `CA-06` y **ninguna la puede elegir este documento**:

- **(a)** asignar la implementación a HU-08, aceptando que la historia crezca hacia las estadísticas y que dependa de `computeEffectiveStats` y del contrato `equipped-hero`;
- **(b)** reconocer que la materia pertenece a otra historia —HU-28 o una historia de estadísticas— y **retirar o mover `CA-06`**;
- **(c)** reformularlo como criterio **no obligatorio**.

Para `CA-03` la salida es una sola: **reescribir el criterio** para que diga que el umbral se obtiene de la tabla aprobada. Hasta entonces, este entregable **señala el hueco en lugar de taparlo**.

## Decisión funcional pendiente: el redondeo de la recompensa

Ya **no** es una decisión sobre el umbral: la tabla aprobada es entera y no hay nada que redondear. Lo que sigue abierto es el redondeo de la **recompensa** `10 × 1,2^(1d8)`, que vive en Missions:

| `1d8` | Valor exacto | Al entero más próximo |
| ---: | ---: | ---: |
| 1 | 12 | **12** |
| 2 | 14,4 | **14** |
| 3 | 17,28 | **17** |
| 4 | 20,736 | **21** |
| 5 | 24,8832 | **25** |
| 6 | 29,85984 | **30** |
| 7 | 35,831808 | **36** |
| 8 | 42,9981696 | **43** |

El PO describió el redondeo **al entero más próximo** y ofreció el **truncamiento** como alternativa; con truncamiento, el `1d8 = 4` daría `20`. **No bloquea HU-08** —Player/Inventory recibe un importe ya entero— pero conviene cerrarlo antes de la Task de Missions que lo implemente.

## Contrato entregado

**No hay superficie HTTP.** La Task `#188` dice que «no es obligatorio exponer esta operación mediante HTTP si la arquitectura final determina otro mecanismo de interacción», y el SAD registra como limitación vigente que «los puertos existen; el transporte no». El mecanismo es **en proceso**:

| Operación | Entrada | Salida |
| --- | --- | --- |
| `experienceRequiredForNextLevel(currentLevel)` | Nivel actual, entero `1..8` | `AVAILABLE` con `{ forNextLevel, amount }` o `MAX_LEVEL` |
| `levelFromTotalXp(totalXp)` | XP acumulada, entero `≥ 0` | Nivel alcanzado, de una vez y sin pasar por los intermedios |
| `QueryExperienceThreshold.execute(currentLevel)` | Ídem al primero | Ídem. Único punto por el que los consumidores piden el umbral |
| `QueryExperienceThreshold.resolveLevel(totalXp)` | Ídem al segundo | Ídem. La otra dirección de la misma tabla |
| `HeroProgression.awardExperience(amount)` | Importe entero ya calculado | Progresión nueva: acumulado sumado, nivel recalculado, `version` intacta |
| `HeroProgression.thresholdForNextLevel()` | — | El umbral, calculado desde el nivel persistido |
| `GetHeroProgression.execute(ownerId, heroId)` | Sujeto verificado y referencia de héroe | Nivel, XP acumulada, umbral derivado y nivel máximo |

Todas están **implementadas y registradas en el contenedor**. La prueba `hero-progression-wiring.spec.ts` resuelve los tres proveedores nuevos, de modo que un registro mal cableado se ve en la suite y no al arrancar en producción.

`amount` es **XP acumulada**, no un incremento: es el acumulado que hay que alcanzar, y es lo que `levelFromTotalXp` compara. La otra lectura —«cuánto falta»— confundiría a HU-09, que es quien acredita.

Errores funcionales: no entero, fuera de `1..8`, ausente o de tipo incorrecto → `DomainError` con mensaje en español, **sin normalizar en silencio**. Un documento cuyo nivel no corresponda a su acumulado → `DomainError` al restaurarlo. Guardar con una versión obsoleta → `HeroProgressionConflictError`, que se traduce a `409`. El nivel máximo **no** es un error.

## Modelo de datos implementado (Task `#189`)

| Aspecto | Valor |
| --- | --- |
| Colección | `hero-progressions` |
| Clave `_id` | `"<ownerId>::<heroId>"`, el **mismo separador `::`** que usa `hero-loadouts` |
| Campos | `ownerId`, `heroId`, `level` (`int`, `1..8`), `currentXp` (`int`, `≥ 0`), `version` (`int`, `≥ 0`) |
| **No se guarda** | El **umbral**. Ni como campo, ni como caché, ni como proyección |
| Cómo se impide | El validador lleva `additionalProperties: false`: **el motor rechaza** cualquier documento con un campo de más, así que persistir el umbral no depende de que nadie se acuerde |
| Migración | `008-hero-progressions`, con validador `$jsonSchema`, `validationLevel: 'strict'` y `down`. Numerada **después** de `007-auction-commitments` (HU-65) |
| Creación perezosa | Un héroe sin documento se lee como nivel 1 con 0, **sin escribir**. No hay backfill |
| Invariante | El nivel guardado es la tabla aplicada al acumulado; un documento que los contradiga se rechaza. **Cambiar la tabla obliga a migrar los documentos escritos** |

## Qué NO se entrega, y por qué

- **No hay endpoints.** La Task `#188` permite no exponer la operación por HTTP y no hay consumidor externo identificado: HU-09 vive en Combat y HU-10 en Missions. La operación reutilizable `QueryExperienceThreshold` está registrada **en proceso** para que esos consumidores pidan el umbral sin duplicar la tabla.
- **No se entrega la experiencia.** `HeroProgression` sabe sumar una recompensa —es aritmética del agregado— y recalcula el nivel, pero **no** decide cuándo se otorga, **no** genera la recompensa y **no** publica eventos. La tirada `1d8` es de Combat y la recompensa `10 × 1,2^(1d8)` es de Missions; la idempotencia de la acreditación es de HU-09.
- **No se toca `computeEffectiveStats` ni el contrato `equipped-hero`.** El umbral depende del nivel y **no** de las estadísticas, y el DTO que viaja a Combat sigue siendo el subconjunto deliberado que **no lleva nivel**. Si `CA-06` se resolviera hacia escalar estadísticas en combate, ampliar ese contrato sería un cambio aparte con su propio proceso.
- **No se renumera ni se reescribe la migración de HU-65.** El choque del `D-5` se resolvió moviendo la de HU-08 a `008`, no al revés: la de HU-65 ya está en `develop`.

## Lo que falta para cerrar HU-08

1. **Corrección de `CA-03` por el PO** para que enuncie la tabla aprobada. Sin ella la HU no puede aceptarse, haga lo que haga la implementación.
2. **Decisión del PO y de arquitectura sobre `CA-06`** (implementar aquí, mover o reformular). Sin ella tampoco.
3. **Cierre de la decisión de redondeo de la recompensa** antes de la Task de Missions que la implemente.
4. **Revisión por pares** de los tres Pull Requests, en orden: #42 → #43 → #44.
5. **Evidencia desde la Issue central**: enlazar PR, checks y resultados en #189.
6. Cerrar las Tasks en el Project **al mergear**, no antes.

## Archivos de este entregable

**Player/Inventory — diseño (rama `docs/hu-08-1-diseno-progresion`, PR #42):**

- `docs/hu-08-progresion.md` — diseño completo
- `docs/architecture.md`, `README.md` — la progresión como agregado propio y el enlace al diseño

**Player/Inventory — implementación (rama `feat/hu-08-2-umbral-experiencia`, PR #43):**

- `src/domain/policies/ExperiencePolicy.ts` — la tabla aprobada, en un único punto, y sus dos direcciones
- `src/domain/value-objects/hero-level.ts`, `src/domain/value-objects/experience.ts`
- `src/domain/entities/HeroProgression.ts` — agregado por `(jugador, héroe)`, con `awardExperience`
- `src/application/ports/HeroProgressionRepositoryPort.ts`, `src/application/dto/HeroProgressionDto.ts`
- `src/application/use-cases/GetHeroProgression.ts`, `src/application/use-cases/QueryExperienceThreshold.ts`
- `src/adapters/outbound/persistence/migrations/008-hero-progressions.ts`
- `src/adapters/outbound/persistence/hero-progression-mapping.ts`
- `src/adapters/outbound/persistence/MongoHeroProgressionRepository.ts`
- `src/adapters/outbound/persistence/InMemoryHeroProgressionRepository.ts`
- `src/infrastructure/persistence/database.ts` — registro de la migración
- `src/infrastructure/bootstrap/app.module.ts` — los tres proveedores
- `src/application/errors/ApplicationError.ts` — `HeroProgressionConflictError`
- `src/adapters/inbound/http/tokens.ts` — los dos tokens
- `jest.config.ts`, `jest.db.config.ts` — cobertura
- Suites: `experience-policy`, `hero-progression`, `hero-progression-mapping`,
  `in-memory-hero-progression-repository`, `get-hero-progression`,
  `no-duplicate-experience-thresholds`, `hero-progression-wiring` (unitaria) y
  `mongo-hero-progression` (base de datos)

**Player/Inventory — pruebas (rama `test/hu-08-3-pruebas-progresion`, PR #44):**

- `docs/hu-08-matriz-de-pruebas.md` — matriz de trazabilidad y criterios de prueba
- `test/fixtures/experience-threshold-reference.json` y `test/fixtures/README.md` — los valores del PO, fuera del código
- `test/unit/experience-threshold-reference.spec.ts` — regresión contra esos valores
- `test/db/mongo-hero-progression.spec.ts` — los tres estados del contrato contra MongoDB real

**Infrastructure:**

- este documento y las secciones 4 y 14 de `docs/architecture/SAD.md`
