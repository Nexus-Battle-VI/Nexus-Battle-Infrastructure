# ADR-012 — Selección de ORM y ODM

- **Estado:** **Accepted** el 2026-08-25
- **Fecha:** 2026-08-25
- **Decide:** Arquitectura, ratificado por el equipo
- **Relacionado:** [ADR-005](ADR-005-data-strategy.md), [ADR-008](ADR-008-iac.md)

## Contexto

[ADR-005](ADR-005-data-strategy.md) dejó esta decisión **deliberadamente abierta** y enumeró el motivo: elegir un ORM determina el modelo de persistencia, la estrategia de migraciones y la forma de las consultas durante años.

La consecuencia se paga cada día: **los seis servicios operan con repositorios en memoria y un reinicio pierde todos los datos.** Es la limitación más visible del sistema después del blocker de identidad.

Este ADR aporta los criterios, las alternativas y la decisión. El equipo la ratificó el 2026-08-25.

## Lo que la arquitectura ya decidió por nosotros

Antes de comparar herramientas conviene ver qué necesita realmente este sistema, porque descarta media lista sin abrir la documentación de nadie.

Los repositorios **almacenan instantáneas y reconstituyen el agregado** con `restore(...)`. Esto significa que el adaptador solo tiene que traducir entre fila o documento e instantánea. **No hace falta** mapa de identidad, carga perezosa ni seguimiento de cambios; y esas tres funciones no son neutrales: **compiten con el agregado**, que es quien debe decidir cuándo cambia su estado.

Además, la regla de ESLint prohíbe que el dominio importe cualquier ORM. Una herramienta que exija decorar las entidades de dominio obliga a una de dos cosas, y ninguna es aceptable:

1. Meter la persistencia en el dominio, que es exactamente lo que la regla impide.
2. Mantener **entidades de persistencia duplicadas** en paralelo a las de dominio.

## Criterios

| # | Criterio | Por qué pesa aquí |
| --- | --- | --- |
| 1 | **El dominio no se entera** | La regla de ESLint no es negociable |
| 2 | **Consultas explícitas** | Una consulta oculta que degenera en N+1 sobre una `t4g.small` compartida con todo lo demás se nota |
| 3 | **Migraciones revisables** | El esquema se revisa en PR como cualquier otro cambio |
| 4 | **Tipado sin segunda fuente de verdad** | Un esquema que se desincroniza del código miente en silencio |
| 5 | **Dos motores** | PostgreSQL y MongoDB, sin forzar la misma herramienta en ambos |
| 6 | **Curva para 18 personas** | Tres Teams, la mayoría aprendiendo |
| 7 | **Tamaño de imagen** | El techo de coste se defiende también en el disco |

## Candidatos para PostgreSQL

Versiones consultadas al registro de npm el **2026-08-25**.

| Herramienta | Versión estable | Modelo |
| --- | --- | --- |
| **Kysely** | `0.29.5` | Constructor de consultas tipado |
| **Drizzle** | `drizzle-orm 0.45.2` · `drizzle-kit 0.31.10` | Esquema en TS + constructor |
| **Prisma** | `@prisma/client 7.10.0` | Cliente generado desde un esquema propio |
| **TypeORM** | `1.1.0` | ORM con decoradores |
| **`pg` a secas** | `8.23.0` | Driver, SQL a mano |

### Evaluación

| | Kysely | Drizzle | Prisma | TypeORM |
| --- | --- | --- | --- | --- |
| 1 · Dominio ajeno | ✅ devuelve objetos planos | ✅ objetos planos | ✅ objetos planos | ⚠️ decoradores en la entidad |
| 2 · Consultas explícitas | ✅ es SQL tipado | ✅ SQL con azúcar | ⚠️ API propia | ❌ carga perezosa |
| 3 · Migraciones | ✅ propias, en TS | ✅ **generadas por diferencia** | ✅ las mejores del grupo | ✅ generadas |
| 4 · Fuente de verdad | ✅ una interfaz TS | ✅ esquema TS | ⚠️ `.prisma` **aparte del código** | ⚠️ decoradores |
| 5 · MongoDB | ❌ no | ❌ no | ⚠️ soporte parcial | ⚠️ limitado |
| 6 · Curva | ⚠️ exige saber SQL | ⚠️ media | ✅ la mejor documentada | ⚠️ conceptos de ORM |
| 7 · Imagen | ✅ nada extra | ✅ nada extra | ❌ **binario de motor** | ✅ nada extra |

### TypeORM queda fuera por el criterio 1

Su modelo natural son decoradores sobre la clase de entidad. Aplicarlo aquí **rompe la regla de ESLint del dominio**, y evitarlo exige duplicar entidades. Además `1.1.0` es un mayor recién estrenado tras años en `0.3.x`: su superficie no tiene todavía el rodaje que sí tienen las alternativas.

### El detalle de Prisma que hay que conocer antes de elegirlo

**Hoy `npm install prisma` instala un _release candidate_.** La etiqueta `latest` del paquete de la CLI apunta a `8.0.0-rc.10`, mientras que `@prisma/client` sirve `7.10.0` estable.

```text
prisma           latest -> 8.0.0-rc.10     (release candidate)
@prisma/client   latest -> 7.10.0          (estable)
```

No es un impedimento —se resuelve fijando `7.10.0` en ambos paquetes, que es lo que este proyecto hace con todas sus dependencias— pero es exactamente la clase de detalle que produce una instalación rota el primer día si nadie lo mira.

## Candidatos para MongoDB

| Herramienta | Versión | Nota |
| --- | --- | --- |
| **Driver oficial `mongodb`** | `6.21.0` | Documentos planos, sin capa intermedia |
| **Mongoose** | `9.9.4` | ODM con esquemas y validación propias |

**Mongoose duplicaría la validación.** `Quantity` ya impide un saldo negativo o fraccionario, `Money` ya impide importes fraccionarios y la capacidad del inventario ya se aplica en el agregado. Un esquema de Mongoose repitiendo esas reglas crea **dos sitios donde la verdad puede divergir**, y el día que diverjan ganará el que no debería.

El driver oficial entrega documentos planos, que es justo la forma de la instantánea que el repositorio ya maneja.

### La versión anotada era `7.6.0`, y no conecta

Este ADR anotó `7.6.0` porque era la publicada como `latest`. Al implementar el adaptador de Catalog contra un MongoDB 8.0 real, el servidor rechaza el saludo:

```
MongoServerSelectionError: Missing required sub-document 'driver'
in the client metadata document
    at ... node_modules/mongodb/src/sdam/monitor.ts:388:7
```

No es el código del servicio: la traza apunta al **monitor** del driver. Y el driver siempre incluye `driver` en el saludo inicial —se lee en su propio `client_metadata.js`, que lanza si no cabe en los 512 bytes—, así que lo que falla es la ruta del monitor, donde el saludo continuo omite los metadatos por especificación.

Se comprobó cambiando **una sola variable**, la versión del driver, con la misma imagen del servidor: con `6.21.0` conecta y la suite completa pasa.

**La decisión no cambia** —driver oficial, no ODM—; lo que cambia es la versión, y queda dicho por qué. La línea `7.x` se podrá adoptar cuando esto se corrija aguas arriba, y entonces será un cambio de una línea en `package.json` respaldado por la suite contra motor real.

### Un detalle que la implementación obliga a fijar

Por defecto el driver **promociona** un entero de 64 bits a número de JavaScript cuando cabe en 53 bits, y lo deja como `Long` cuando no. Es decir, el tipo que recibe la traducción **depende del valor**, de modo que la comprobación de exactitud solo se ejercita con importes grandes: un camino que nadie prueba.

Los adaptadores de MongoDB fijan `promoteLongs: false`. Siempre llega un `Long`, y la comprobación se aplica siempre.

## Decisión

**PostgreSQL: Kysely. MongoDB: driver oficial.**

El argumento no es de gusto, es de **coherencia con una decisión que este proyecto ya tomó**. [ADR-008](ADR-008-iac.md) eligió Terraform sobre CDK con este razonamiento:

> permite abstracciones que **ocultan qué se está creando**. Un constructo de alto nivel puede provisionar en silencio un NAT Gateway [...] y con un techo de USD 100 al mes ese silencio es caro.

Aquí el silencio caro es otro: **una relación cargada de forma perezosa dentro de un bucle genera decenas de consultas sin que aparezca ninguna en el código**. Sobre una `t4g.small` que comparte host con otros cinco servicios y dos motores, eso se nota antes que en cualquier otro sitio.

Kysely obliga a escribir la consulta. Igual que Terraform obliga a nombrar el recurso.

Lo que se gana además: sin paso de generación de código, sin binario de motor en la imagen, sin segunda fuente de verdad, y migraciones que son TypeScript revisable en un PR.

### La alternativa que se consideró y no se eligió

**Prisma para PostgreSQL** es una elección razonable si el equipo prioriza el acompañamiento sobre la explicitud. Tiene la mejor documentación del grupo y las migraciones más pulidas, y su cliente devuelve objetos planos, así que **no compromete la arquitectura hexagonal**.

El intercambio, dicho entero:

| | Kysely | Prisma |
| --- | --- | --- |
| Hay que saber SQL | **Sí** | No |
| Consultas visibles en el código | **Sí** | Parcialmente |
| Segunda fuente de verdad | No | **Sí**, el fichero `.prisma` |
| Binario de motor en la imagen | No | **Sí** |
| Curva para quien empieza | Más pronunciada | **Más suave** |

En un proyecto académico de ingeniería de software, «hay que saber SQL» puede leerse como ventaja. Esa lectura le corresponde al equipo, no a este documento.

**Drizzle** queda como tercera opción coherente: mismo espíritu explícito que Kysely y migraciones generadas por diferencia, que reducen el SQL escrito a mano. Se descarta como recomendación por una razón de calendario, no de diseño: está en `0.45.2` con un `1.0.0-beta` en curso, y un cambio de mayor a mitad de proyecto cuesta más de lo que ahorra.

## Consecuencias

**Lo que se gana**

- Se desbloquea el paso 2 del camino de [ADR-005](ADR-005-data-strategy.md): esquema y migraciones por servicio.
- El adaptador real sustituye al repositorio en memoria **tocando un solo fichero por servicio**. Ni el dominio ni los casos de uso cambian, que es lo que la arquitectura hexagonal prometió y aquí se cobra.
- Las pruebas de integración contra el motor real, con Testcontainers, dejan de estar bloqueadas.

**Lo que cuesta**

- Cinco servicios necesitan adaptador, esquema y migraciones. No es trabajo pequeño.
- Con Kysely, quien no sepa SQL tendrá que aprenderlo.
- Aparece un componente con estado que hay que respaldar, y hoy **no hay copias de seguridad gestionadas**: perder el volumen del nodo de datos es perder los datos.

## Lo que este ADR no decide

- **El esquema.** Cada servicio define el suyo, y ninguno referencia al de otro: sin claves foráneas entre servicios, sin excepciones.
- **Los índices.** Dependen de las consultas reales, que todavía no existen.
- **La estrategia de copias de seguridad.** Merece su propio análisis y no debe resolverse como efecto colateral de elegir una biblioteca.
