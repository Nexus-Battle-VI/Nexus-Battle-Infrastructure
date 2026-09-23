# HU-08 — Evidencia de progresión: experiencia requerida por nivel

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#17](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/17)
- **Tasks:** [#188](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/188) (diseño · `open`), [#189](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/189) (implementación · `open`), [#190](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/190) (pruebas · `open`)
- **Fecha:** 2026-09-23
- **Requisito trazado:** `RF-08`
- **Bounded context:** Player / Inventory · Team Alfa
- **Pull Requests:** pendientes de abrir. El diseño va en la rama `docs/hu-08-1-diseno-progresion`, la implementación en `feat/hu-08-2-umbral-experiencia` y las pruebas en la misma rama de implementación, todas contra `develop`.
- **Matriz de trazabilidad:** [Nexus-Battle-Player-Inventory/docs/hu-08-matriz-de-pruebas.md](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/blob/develop/docs/hu-08-matriz-de-pruebas.md)
- **Estado:** diseño, implementación y suite de pruebas entregados. **La HU no está aceptada**: falta revisión por pares y aceptación del PO, y `CA-06` sigue sin resolver.

## Estado de la verificación: qué se comprobó y qué NO

Este documento **no declara la HU aceptada**. Lo que existe es la especificación, su
implementación y la evidencia de ejecución de sus pruebas. Declarar aquí una aceptación sería
exactamente el error que el Project ya cometió con HU-29 y HU-31, marcadas `Done` sin código en
`develop`.

| Nivel | Estado |
| --- | --- |
| Diseño de dominio, caso de uso y diagramas | **Entregado** en `Nexus-Battle-Player-Inventory/docs/hu-08-progresion.md` |
| Matriz de trazabilidad `RF-08 → CA → escenario → nivel → resultado → tipo → script` | **Entregada** en `Nexus-Battle-Player-Inventory/docs/hu-08-matriz-de-pruebas.md` |
| Modelo de dominio y objetos de valor | **Implementados** (`ExperiencePolicy`, `HeroLevel`, `Experience`, `HeroProgression`) |
| Persistencia: migración `007-hero-progressions` | **Implementada**, con validador `$jsonSchema` en el motor |
| Adaptadores Mongo y en memoria, con bloqueo optimista | **Implementados** |
| Registro en el contenedor y operación reutilizable | **Implementados**, con prueba de cableado |
| Aritmética exacta de la fórmula | **Verificada** contra una tabla de referencia derivada **fuera del repositorio**: `100`, `120`, `144`, `172.8`, `207.36`, `248.832`, `298.5984` |
| Control de fórmula única | **Ejecutado**: `no-duplicate-experience-formula.spec.ts` falla si la fórmula se evalúa fuera de `ExperiencePolicy` |
| Control de ausencia de redondeo | **Verificado**: la política no usa `Math.round`, `floor`, `ceil` ni `trunc` |
| Determinismo | **Verificado**: 50 consultas por nivel de referencia, y el orden de consulta no altera el resultado |
| Pruebas unitarias | **Ejecutadas: 31 suites / 664 pruebas, en verde** |
| Pruebas de integración HTTP | **Ejecutadas: 9 suites / 101 pruebas, en verde** |
| Pruebas contra MongoDB real | **Ejecutadas: 7 suites / 74 pruebas, en verde** |
| Casos de HU-08 | **84 en total**: 73 en la suite unitaria y 11 en la de base de datos |
| Cobertura de la regla (`ExperiencePolicy`) | **100 % sentencias, ramas y funciones** |
| Cobertura global | **95,7 % sentencias / 87,6 % ramas / 94,2 % funciones** — sobre el umbral del 80 % |
| `lint`, `format:check`, `typecheck`, `build` | **Ejecutados y limpios** |
| **Que el motor rechace persistir el umbral** | **Verificado con MongoDB real**: insertar `nextLevelThreshold` a mano falla |
| Pruebas de redondeo | **NO existen, y es deliberado**: no hay política aprobada que verificar. Ver `D-3` |
| Casos de `CA-06` | **NO existen, y es deliberado**: el criterio no es implementable sin fórmula. Ver `D-3` |
| Revisión por pares | **PENDIENTE.** Es requisito del ruleset: 1 aprobación + Code Owner |
| Aceptación del PO | **PENDIENTE**, y bloqueada por `CA-06` |
| Uso del producto desplegado | **NO aplica**: no hay endpoint ni pantalla que consuma la progresión |

## Reporte de ejecución (punto 8 de la Task #190)

### Identificación de la ejecución

| Campo | Valor |
| --- | --- |
| Fecha | 2026-09-23 |
| Versión del paquete | `0.1.0` |
| Commit bajo prueba | `7fc0a9f` (rama `feat/hu-08-2-umbral-experiencia`) |
| Ambiente | Desarrollo local, Windows · Node `v24.19.0` · npm `11.17.0` |
| MongoDB para `test:db` | Contenedor `mongo:8.0` vía Testcontainers · Docker `29.7.2` |
| Comando | `npm run lint && npm run format:check && npm run typecheck && npm run test:unit && npm run test:integration && npm run test:coverage && npm run build && npm run test:db` |

### Casos ejecutados

| Suite | Suites | Casos | Aprobados | Fallidos | Bloqueados |
| --- | ---: | ---: | ---: | ---: | ---: |
| Unitaria (`test:unit`) | 31 | 664 | **664** | 0 | 0 |
| Integración HTTP (`test:integration`) | 9 | 101 | **101** | 0 | 0 |
| Base de datos (`test:db`) | 7 | 74 | **74** | 0 | 0 |
| **Total** | **47** | **839** | **839** | **0** | **0** |

**Casos de HU-08: 84** — 73 en la suite unitaria y 11 contra MongoDB real, repartidos en 8
archivos de prueba unitaria y 1 de base de datos. El detalle por escenario está en la matriz de
trazabilidad.

### Cobertura disponible

| Ámbito | Sentencias | Ramas | Funciones | Líneas |
| --- | ---: | ---: | ---: | ---: |
| **Global del servicio** | 95,7 % | 87,6 % | 94,2 % | 95,8 % |
| `ExperiencePolicy.ts` (la regla) | **100 %** | **100 %** | **100 %** | **100 %** |
| `HeroProgression.ts` | **100 %** | **100 %** | **100 %** | **100 %** |
| `GetHeroProgression.ts` | **100 %** | **100 %** | **100 %** | **100 %** |
| `hero-progression-mapping.ts` | **100 %** | **100 %** | **100 %** | **100 %** |
| `InMemoryHeroProgressionRepository.ts` | **100 %** | **100 %** | **100 %** | **100 %** |
| `experience.ts` | **100 %** | 85,7 % | **100 %** | **100 %** |
| `hero-level.ts` | 75 % | 64,3 % | **100 %** | 75 % |

Umbral configurado en Jest: **80 %**. Artefacto publicado por CI:
`coverage-player-inventory` (`coverage/`, con `lcov` y `json-summary`).

**Cobertura no perseguida, y por qué:** quedan cinco sentencias sin cubrir en `hero-level.ts`,
las ramas que formatean un valor rechazado en el mensaje de error. La Task #190 prohíbe
aumentar cobertura con pruebas triviales sin valor funcional, y comprobar cómo se escribe un
mensaje de diagnóstico no verifica la fórmula, el rango, la precisión ni los límites. Se
documenta el hueco en lugar de taparlo.

### Defectos

| # | Defecto | Estado |
| --- | --- | --- |
| D-1 | La fórmula en coma flotante daba `172.79999999999998` en el nivel 4 y desviaciones crecientes hasta el 7 | **Corregido**: aritmética racional exacta, con cuatro pruebas que fijan los valores |
| D-2 | El umbral podía persistirse por descuido en un cambio futuro | **Prevenido**: `additionalProperties: false` y una prueba contra MongoDB real que lo comprueba |
| D-3 | `CA-06` es criterio obligatorio, sin fórmula y sobre materia fuera de alcance: **bloquea la aceptación de la HU** | **Abierto.** Requiere decisión de PO y arquitectura |

No se encontraron defectos en la ejecución: las 839 pruebas pasaron en el primer intento tras
las correcciones de `D-1` y `D-2`, que se detectaron al construir la suite.

### Observaciones para aceptación

1. **La HU no puede aceptarse todavía.** `CA-06` es obligatorio y no puede aprobarse: por
   `CA-08`, HU-08 queda formalmente inaceptable mientras siga en su redacción actual. Es el
   punto que requiere decisión del Product Owner, no trabajo de desarrollo.
2. **La política de redondeo sigue sin aprobarse**, así que no hay pruebas de redondeo: no hay
   política que verificar. Lo que sí se prueba es la **ausencia** de redondeo, que es la
   garantía opuesta y la única verificable hoy.
3. **`CA-07` se cubre en proceso, no por HTTP.** No hay endpoint y ninguno está pedido; el
   consumidor verificado es el caso de uso y la operación reutilizable, no una ruta.
4. **Falta la revisión por pares**, que el ruleset exige (1 aprobación + Code Owner) y que
   ningún desarrollador puede darse a sí mismo.
5. **`EN-015` (#200) y `EN-016` (#201) siguen `open`.** Esta Task se apoya en lo ya existente:
   no añadió dependencias ni reporteros nuevos, salvo `json` en la configuración de cobertura,
   que es salida estándar de Jest.

## Criterios de aceptación

| Criterio | Estado | Evidencia |
| --- | --- | --- |
| **CA-01** — El nivel actual produce el umbral del siguiente nivel | **Cubierto y probado** | `experience-policy.spec.ts`: nivel 1 → `100` hacia el 2; nivel 4 → `172.8` hacia el 5; nivel 7 → `298.5984` hacia el 8 |
| **CA-02** — Los héroes progresan de nivel 1 a nivel 8 | **Cubierto y probado** | `MIN_HERO_LEVEL` / `MAX_HERO_LEVEL` y `HeroLevel`, que valida la invariante. `hero-progression.spec.ts` rechaza nivel 0 y 9 |
| **CA-03** — El umbral se calcula con `100 × 1,2^(Nivel−1)` | **Cubierto y probado, en un único punto** | `experienceRequiredForNextLevel` con aritmética racional exacta. `no-duplicate-experience-formula.spec.ts` **falla** si la fórmula se evalúa fuera de `ExperiencePolicy` |
| **CA-04** — El cálculo usa como entrada el nivel actual | **Cubierto y probado** | La firma recibe `currentLevel` y nada más. Se prueban 16 casos, incluidos `'3'`, `null`, `NaN` y decimales |
| **CA-05** — El sistema no calcula un siguiente nivel fuera del rango máximo | **Cubierto y probado** | Nivel 8 → `status: 'MAX_LEVEL'` con `forNextLevel: null`. La operación no puede producir un nivel 9 |
| **CA-06** — El nivel actúa como factor multiplicador sobre el resto de las estadísticas | **FUERA DE ALCANCE — y con la HU formalmente inaceptable mientras siga así** | Ver la sección siguiente. **No se automatiza ninguna prueba** de este criterio, de forma deliberada |
| **CA-07** — El valor queda disponible como umbral del siguiente nivel | **Cubierto y probado** | `QueryExperienceThreshold` es el único punto por el que los consumidores piden el umbral; `hero-progression-wiring.spec.ts` comprueba que se resuelve y calcula sin conocer la fórmula |
| **CA-08** — Un criterio obligatorio fallido impide aceptar la HU | **NO SE CUMPLE, y es el hallazgo** | `CA-06` es obligatorio y no puede aprobarse: **HU-08 no puede aceptarse hoy** |

## CA-06 queda fuera, y bloquea la aceptación de la HU

`CA-06` exige que «el nivel del héroe actúe como factor multiplicador sobre el resto de sus
estadísticas conforme a las reglas del juego». **No se implementa, no se modela y no se
prueba.** No es un olvido; es una frontera con tres fundamentos verificables:

1. **La propia HU declara la materia fuera de alcance.** El cuerpo de la Task `#188` enumera lo
   que HU-08 **no** es responsable de hacer, y esa lista incluye **«recalcular reglas de
   combate»**. Las estadísticas del héroe son materia de combate.
2. **La Task exige no acoplarse.** `#188` pide que HU-08 «no quede acoplada a una modalidad
   específica como batalla o misiones», y en sus condiciones de finalización exige que «**no se
   incorporaron responsabilidades de batalla o misiones**».
3. **No existe fórmula en ninguna fuente.** Ni el Issue `#17`, ni las tres Tasks, ni `ADR-019`,
   ni `ADR-021`, ni ningún contrato del proyecto definen cómo multiplica el nivel. La única
   frase es «conforme a las reglas del juego», que no es una fórmula. El precedente ya
   registrado en Player/Inventory es explícito: «La tabla de nivel 1 no define una formula para
   niveles superiores y **aqui no se inventa ninguna**» (`HeroPowerPolicy`).

**No se automatiza ninguna prueba que fije ese comportamiento**, siguiendo el patrón que HU-07
aplicó a su propio `CA-09`, con el mismo razonamiento textual de su Task:

> «Tampoco deben convertir en prueba de HU-07 la regla de modificación durante combate, ya que
> pertenece a HU-29 y actualmente existe una inconsistencia documental que debe ser resuelta
> antes de automatizar dicho comportamiento como requisito definitivo.»

### Consecuencia que hay que dejar escrita

Como `CA-08` establece que «un criterio obligatorio fallido impide aceptar la HU», y `CA-06` es
obligatorio y **no puede aprobarse**, **HU-08 es hoy formalmente inaceptable**. No es un
problema de la implementación: es un problema de la redacción de la historia.

Hay tres salidas y **ninguna la puede elegir este documento**:

- **(a)** definir la fórmula y asignarla a HU-08, aceptando que la historia crezca hacia las
  estadísticas;
- **(b)** reconocer que la materia pertenece a otra historia —HU-28 o una historia de
  estadísticas— y **retirar o mover `CA-06`**;
- **(c)** reformularlo como criterio **no obligatorio**.

Es una decisión de **Product Owner y arquitectura**. Hasta que se tome, este diseño entrega
todo lo demás y **señala el hueco en lugar de taparlo**.

## Decisión funcional pendiente: la política de redondeo

Es la decisión que la Task `#188` nombra explícitamente como bloqueante de la implementación
numérica. **Sigue sin tomarse y este diseño no la toma.**

La fórmula produce valores fraccionarios desde el nivel 4:

| Nivel | Umbral exacto | ¿Entero? |
| ---: | --- | --- |
| 1 | `100` | Sí |
| 2 | `120` | Sí |
| 3 | `144` | Sí |
| 4 | `172.8` | **No** |
| 5 | `207.36` | **No** |
| 6 | `248.832` | **No** |
| 7 | `298.5984` | **No** |

Lo que el diseño **sí** resolvió es un problema distinto que estaba oculto: en coma flotante
binaria la evaluación ingenua de la fórmula **está mal**. `100 * 1.2 ** 3` da
`172.79999999999998`, no `172.8`. La operación calcula el valor con **aritmética racional
exacta** y lo rinde en forma decimal canónica, de modo que el error de coma flotante no se
filtra. **Esto no es redondear**: es representar exactamente un número exacto.

**Dato útil para que el PO decida:** como el umbral **no se persiste** —es derivable del nivel,
y la Task prohíbe almacenar valores que puedan calcularse—, cambiar la política de redondeo
más adelante **no exige migración de datos**.

## Contrato entregado

**No hay superficie HTTP.** La Task `#188` dice que «no es obligatorio exponer esta operación
mediante HTTP si la arquitectura final determina otro mecanismo de interacción», y el SAD
registra como limitación vigente que «los puertos existen; el transporte no». El mecanismo es
**en proceso**:

| Operación | Entrada | Salida |
| --- | --- | --- |
| `experienceRequiredForNextLevel(currentLevel)` | Nivel actual, entero `1..8` | `AVAILABLE` con `{ forNextLevel, amount, decimal }`, o `MAX_LEVEL` |
| `QueryExperienceThreshold.execute(currentLevel)` | Ídem | Ídem. Único punto por el que los consumidores piden el umbral |
| `HeroProgression.thresholdForNextLevel()` | — | Ídem, calculado desde el nivel persistido |
| `GetHeroProgression.execute(ownerId, heroId)` | Sujeto verificado y referencia de héroe | Nivel, XP acumulada, umbral derivado y nivel máximo |

Las cuatro están **implementadas y registradas en el contenedor**. La prueba
`hero-progression-wiring.spec.ts` resuelve los tres proveedores nuevos, de modo que un registro
mal cableado se ve en la suite y no al arrancar en producción.

Errores funcionales: no entero, fuera de `1..8`, ausente o de tipo incorrecto → `DomainError`
con mensaje en español, **sin normalizar en silencio**. El nivel máximo **no** es un error.
Guardar con una versión obsoleta → `HeroProgressionConflictError`, que se traduce a `409`.

## Modelo de datos implementado (Task `#189`)

| Aspecto | Valor |
| --- | --- |
| Colección | `hero-progressions` |
| Clave `_id` | `"<ownerId>::<heroId>"`, el **mismo separador `::`** que usa `hero-loadouts` |
| Campos | `ownerId`, `heroId`, `level` (`int`, `1..8`), `currentXp` (`int`, `≥ 0`), `version` (`int`, `≥ 0`) |
| **No se guarda** | El **umbral**. Ni como campo, ni como caché, ni como proyección |
| Cómo se impide | El validador lleva `additionalProperties: false`: **el motor rechaza** cualquier documento con un campo de más, así que persistir el umbral no depende de que nadie se acuerde |
| Migración | `007-hero-progressions`, con validador `$jsonSchema`, `validationLevel: 'strict'` y `down` |
| Creación perezosa | Un héroe sin documento se lee como nivel 1 con 0, **sin escribir**. No hay backfill |

## Qué NO se entrega, y por qué

- **No hay endpoints.** La Task `#188` permite no exponer la operación por HTTP y no hay
  consumidor externo identificado: HU-09 vive en Combat y HU-10 en Missions. La operación
  reutilizable `QueryExperienceThreshold` está registrada **en proceso** para que esos
  consumidores pidan el umbral sin duplicar la fórmula.
- **No se acredita experiencia ni se sube de nivel.** Eso es HU-09. `HeroProgression` queda de
  solo lectura, con `version` ya lista para el bloqueo optimista que HU-09 necesitará.
- **No se toca `computeEffectiveStats` ni el contrato `equipped-hero`.** El umbral depende del
  nivel y **no** de las estadísticas, y el DTO que viaja a Combat sigue siendo el subconjunto
  deliberado que **no lleva nivel**. Si `CA-06` se resolviera hacia escalar estadísticas en
  combate, ampliar ese contrato sería un cambio aparte con su propio proceso.
- **No se redondea.** Ver la sección siguiente.

## Lo que falta para cerrar HU-08

1. **Decisión del PO sobre `CA-06`** (definir, mover o reformular). Sin ella la HU no puede
   aceptarse, haga lo que haga la implementación.
2. **Decisión del PO sobre la política de redondeo.** La implementación no la toma: devuelve el
   valor exacto. Cambiarla después **no exige migración de datos**, porque el umbral no se
   persiste.
3. Ratificar o corregir `HeroProgression` como agregado por `(jugador, héroe)`. Está
   implementado según el precedente de HU-11 y la simetría con `HeroLoadout`, pero no es una
   decisión ratificada.
4. **Abrir los dos Pull Requests** contra `develop` y atender la revisión del Code Owner.
5. **Evidencia desde la Issue central**: enlazar PR, checks y resultados en #189.
6. Task `#190`: completar la matriz de escenarios y las pruebas que excedan la verificación
   técnica inicial ya cubierta —55 unitarias y 9 contra MongoDB real—.
7. Cerrar las Tasks en el Project **al mergear**, no antes.

## Archivos de este entregable

**Player/Inventory — diseño (rama `docs/hu-08-1-diseno-progresion`):**

- `docs/hu-08-progresion.md` — diseño completo
- `src/domain/policies/ExperiencePolicy.ts` — la fórmula, en un único punto
- `src/domain/value-objects/hero-level.ts`, `src/domain/value-objects/experience.ts`
- `src/domain/entities/HeroProgression.ts`
- `src/application/ports/HeroProgressionRepositoryPort.ts`
- `src/application/dto/HeroProgressionDto.ts`
- `src/application/use-cases/GetHeroProgression.ts`, `src/application/use-cases/QueryExperienceThreshold.ts`
- `README.md`, `docs/architecture.md`

**Player/Inventory — implementación (rama `feat/hu-08-2-umbral-experiencia`):**

- `src/adapters/outbound/persistence/migrations/007-hero-progressions.ts`
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
  `no-duplicate-experience-formula`, `hero-progression-wiring` (unitaria) y
  `mongo-hero-progression` (base de datos)

**Infrastructure:**

- este documento y las secciones 4 y 14 de `docs/architecture/SAD.md`
