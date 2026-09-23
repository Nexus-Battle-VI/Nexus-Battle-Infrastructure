# HU-08 — Evidencia del diseño de progresión: experiencia requerida por nivel

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#17](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/17)
- **Tasks:** [#188](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/188) (este diseño · `open`), [#189](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/189) (implementación · `open`), [#190](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/190) (pruebas · `open`)
- **Fecha:** 2026-09-23
- **Requisito trazado:** `RF-08`
- **Bounded context:** Player / Inventory · Team Alfa
- **Pull Requests:** **ninguno.** Este entregable es diseño y no abre PR de código.

## Estado de la verificación: qué se comprobó y qué NO

Este documento **no declara la HU aceptada**, y con `#188` menos motivo todavía: es un
entregable de **diseño**. Lo que existe es la especificación, no un comportamiento observable.
Declarar aquí una aceptación sería exactamente el error que el Project ya cometió con HU-29 y
HU-31, marcadas `Done` sin código en `develop`.

| Nivel | Estado |
| --- | --- |
| Diseño de dominio, caso de uso y diagramas | **Entregado** en `Nexus-Battle-Player-Inventory/docs/hu-08-progresion.md` |
| Modelo de dominio y objetos de valor | **Implementados** (`ExperiencePolicy`, `HeroLevel`, `Experience`, `HeroProgression`) |
| Aritmética exacta de la fórmula | **Verificada** en los 7 niveles con umbral: `100`, `120`, `144`, `172.8`, `207.36`, `248.832`, `298.5984` |
| Control de fórmula única | **Verificado**: la evaluación de la fórmula aparece **una sola vez** en todo `src/` |
| Control de ausencia de redondeo | **Verificado**: `ExperiencePolicy` no usa `Math.round`, `floor`, `ceil` ni `trunc` |
| `lint`, `typecheck`, `format:check` | **Ejecutados y limpios** en Player/Inventory |
| Suite unitaria de Player/Inventory | **Ejecutada: 23 suites / 585 pruebas, en verde.** Sin regresiones: la línea base era la misma antes de este entregable |
| Pruebas de la política | **NO existen todavía.** Son la Task `#190` |
| Persistencia real (migración `007-hero-progressions`) | **NO escrita.** Es la Task `#189` |
| Endpoint | **NO existe, y no está previsto** (ver «Qué NO se entrega») |
| Uso del producto desplegado, con una persona delante | **NO aplica todavía**: no hay nada desplegable |

## Criterios de aceptación

| Criterio | Estado | Evidencia |
| --- | --- | --- |
| **CA-01** — El nivel actual produce el umbral del siguiente nivel | **Diseñado, no probado** | Caso de uso `UC-HU08-01` y diagrama de secuencia en `hu-08-progresion.md`. La operación existe en `ExperiencePolicy`; su prueba es `#190` |
| **CA-02** — Los héroes progresan de nivel 1 a nivel 8 | **Cubierto** | `MIN_HERO_LEVEL` / `MAX_HERO_LEVEL` y `HeroLevel`, que valida la invariante. Tabla de niveles 1..8 en el diseño |
| **CA-03** — El umbral se calcula con `100 × 1,2^(Nivel−1)` | **Cubierto, en un único punto** | `experienceRequiredForNextLevel`. La fórmula aparece **una sola vez** en todo el servicio |
| **CA-04** — El cálculo usa como entrada el nivel actual | **Cubierto** | La firma recibe `currentLevel` y nada más: no recibe el héroe, ni su equipamiento, ni el jugador |
| **CA-05** — El sistema no calcula un siguiente nivel fuera del rango máximo | **Cubierto** | Nivel 8 → `status: 'MAX_LEVEL'`. La operación no puede producir un nivel 9: `forNextLevel` es `null` en esa rama |
| **CA-06** — El nivel actúa como factor multiplicador sobre el resto de las estadísticas | **FUERA DE ALCANCE — y con la HU formalmente inaceptable mientras siga así** | Ver la sección siguiente. No se automatiza ninguna prueba de este criterio |
| **CA-07** — El valor queda disponible como umbral del siguiente nivel | **Diseñado** | `QueryExperienceThreshold` es el único punto por el que los consumidores piden el umbral, y `HeroProgressionDto.nextLevel` lo expone |
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

Errores funcionales: no entero, fuera de `1..8`, ausente o de tipo incorrecto → `DomainError`
con mensaje en español, **sin normalizar en silencio**. El nivel máximo **no** es un error.

## Modelo de datos diseñado (implementación en `#189`)

| Aspecto | Valor |
| --- | --- |
| Colección | `hero-progressions` |
| Clave `_id` | `"<ownerId>:<heroId>"`, el mismo estilo de clave compuesta que `hero-loadouts` |
| Campos | `ownerId`, `heroId`, `level` (`int`, `1..8`), `currentXp` (`int`, `≥ 0`), `version` (`int`, `≥ 0`) |
| Índice | `{ ownerId: 1, heroId: 1 }`, único |
| **No se guarda** | El **umbral**, ni como campo, ni como caché, ni como proyección |
| Migración | `007-hero-progressions`, con migración numerada y validador `$jsonSchema`, patrón de `006` |

## Qué NO se entrega, y por qué

- **No hay migración escrita.** `#188` es diseño; `#189` la implementa.
- **No hay endpoints.** El diseño no los necesita y ninguno está pedido.
- **No hay pruebas de la política.** Son `#190`.
- **No se toca `computeEffectiveStats` ni el contrato `equipped-hero`.** El umbral depende del
  nivel y **no** de las estadísticas, y el DTO que viaja a Combat sigue siendo el subconjunto
  deliberado que **no lleva nivel**. Si `CA-06` se resolviera hacia escalar estadísticas en
  combate, ampliar ese contrato sería un cambio aparte con su propio proceso.
- **No se acredita experiencia ni se sube de nivel.** Eso es HU-09.

## Lo que falta para cerrar HU-08

1. **Decisión del PO sobre `CA-06`** (definir, mover o reformular). Sin ella la HU no puede
   aceptarse, haga lo que haga la implementación.
2. **Decisión del PO sobre la política de redondeo.**
3. Ratificar o corregir la propuesta de `HeroProgression` como agregado por `(jugador, héroe)`.
   Está fundada en el precedente de HU-11 y en la simetría con `HeroLoadout`, pero no es una
   decisión ratificada.
4. Task `#189`: migración `007`, adaptador Mongo del puerto y su registro en el contenedor.
5. Task `#190`: matriz de escenarios con el control de no-duplicación de la fórmula.
6. Cerrar las Tasks en el Project **al mergear**, no antes.

## Archivos de este entregable

**Player/Inventory:**

- `docs/hu-08-progresion.md` — diseño completo
- `src/domain/policies/ExperiencePolicy.ts` — la fórmula, en un único punto
- `src/domain/value-objects/hero-level.ts`, `src/domain/value-objects/experience.ts`
- `src/domain/entities/HeroProgression.ts`
- `src/application/ports/HeroProgressionRepositoryPort.ts`
- `src/application/dto/HeroProgressionDto.ts`
- `src/application/use-cases/GetHeroProgression.ts`, `src/application/use-cases/QueryExperienceThreshold.ts`
- `README.md`, `docs/architecture.md` — enlace y limitaciones

**Infrastructure:**

- este documento y las secciones 4, 7 y 14 de `docs/architecture/SAD.md`
