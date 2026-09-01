# ADR-014 — Gobierno de privacidad y tratamiento de datos personales

- **Estado:** Proposed — requiere revisión del Tech Lead antes de pasar a Accepted
- **Fecha:** 2026-09-01
- **Decide:** Arquitectura
- **Relacionado:** [ADR-004](ADR-004-identity-directory.md), [ADR-005](ADR-005-data-strategy.md), [ADR-006](ADR-006-messaging.md), [EN-011](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/197), [HU-43](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/37), [HU-45](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/39)

## Contexto

La [Política de Privacidad v0.3](../privacy/privacy-policy-v0.3.md) exige, entre
otras cosas: evidencia verificable de consentimiento con versión y fecha
(§6), un derecho de eliminación con excepciones de retención (§10–11), y un
Portal de privacidad con exportación JSON/XML/PDF que agrega datos de varios
bounded contexts sin exponer datos de terceros (§8–9).

Ninguno de estos requisitos tiene todavía una decisión arquitectónica que lo
sustente:

1. `Account` almacena consentimiento como un booleano sin versión ni fecha
   — ver el gap completo en [consent-versioning.md](../privacy/consent-versioning.md).
2. HU-43 (eliminación) necesita coordinar Account, Player/Inventory,
   Community, Commerce y owners todavía sin asignar (auditoría, sanciones),
   y no existe todavía una decisión de **cómo** se coordinan — ningún ADR
   define hoy una estrategia de orquestación entre bounded contexts para
   este caso. [ADR-006](ADR-006-messaging.md) sigue `Proposed`, pero su
   alcance cubre tres integraciones distintas (Notifications, precio de
   Catalog, reserva de Commerce/Inventory en checkout) y **no menciona el
   derecho al olvido**; no es una dependencia funcional de HU-43 por sí
   solo, aunque conviene resolver la estrategia de orquestación antes de
   implementar la eliminación multi-contexto.
3. HU-45 (portabilidad) necesita agregar lectura de varios bounded contexts
   en un solo reporte por titular, respetando que ningún servicio consulte
   directamente el almacén de otro ([data-ownership.md](../architecture/data-ownership.md)).
4. La frontera entre "dato exportable al titular" y "dato interno/secreto"
   no estaba fijada en ningún documento antes de este PR — sin ella, cada
   implementador de HU-45 decidiría el límite por su cuenta.

Este ADR no implementa ninguna de las piezas: fija las decisiones
arquitectónicas mínimas para que HU-43 y HU-45 tengan un contrato estable
sobre el que construir, evitando que cada bounded context resuelva estos
puntos de forma distinta.

## Decisión propuesta

### 1. Ownership de la evidencia de consentimiento

La evidencia de consentimiento versionado (titular, versión de Política,
fecha/hora) es propiedad de **Account**, no de un servicio de privacidad
transversal nuevo. Razón: Account ya posee `terms_accepted` y es el bounded
context dueño de la cuenta ([data-ownership.md](../architecture/data-ownership.md));
crear un servicio nuevo solo para custodiar un dato adicional de la misma
cuenta duplicaría ownership sin necesidad.

La forma concreta (tabla nueva append-only, columna adicional, evento de
dominio) **no se fija aquí** — es una decisión de implementación de la Task
que resuelva el gap descrito en
[consent-versioning.md](../privacy/consent-versioning.md).

### 2. Separación entre datos del titular y datos internos

Se adopta como principio arquitectónico transversal, aplicable a HU-45 y a
cualquier futura superficie que exponga datos al titular, la clasificación
fijada en [portability-contract-v1.md](../privacy/portability-contract-v1.md):
CONSULTABLE/EXPORTABLE frente a INTERNO/SECRETO/NO PORTABLE. Un dato solo
sale de esa segunda categoría mediante una decisión funcional explícita
registrada (Product Owner) o una actualización de este ADR si la excepción
tiene naturaleza arquitectónica.

### 3. Autoridad del titular: identidad verificada, no identificador enviado por el cliente

Toda superficie que resuelva "los datos de este titular" — HU-43, HU-45, o
cualquier extensión futura del Portal de privacidad — debe resolver la
identidad del titular exclusivamente mediante el patrón ya implementado y
verificado en código:

```text
VerifiedIdentity.subject -> findBySubject(...) -> Account
```

Verificado en [`GetOwnAccount.ts`](https://github.com/Nexus-Battle-VI/Nexus-Battle-Account/blob/main/src/application/use-cases/GetOwnAccount.ts)
y [`UpdateOwnAccount.ts`](https://github.com/Nexus-Battle-VI/Nexus-Battle-Account/blob/main/src/application/use-cases/UpdateOwnAccount.ts).
Ningún bounded context debe aceptar un `accountId`/`customerId`/equivalente
enviado por Web como fuente de autorización — solo como parámetro de
presentación después de que la identidad ya esté resuelta desde el `subject`
verificado.

### 4. Estrategia de agregación para portabilidad (HU-45): lectura síncrona

La agregación de lectura para exportar (JSON/XML/PDF) **no depende de que
ADR-006 se acepte primero**. Se adopta el mismo patrón síncrono ya
implementado para `Commerce -> Catalog` (`ProductPricingPort.priceOf`,
ver [ADR-006](ADR-006-messaging.md)): un agregador de solo lectura consulta
a cada bounded context por su API, nunca por acceso directo a su almacén.

El agregador concreto (dónde vive: Account, un servicio nuevo, o cada
consumidor resolviendo su propia porción) **no se decide en este ADR** —
queda para la implementación de HU-45, con esta restricción: **ningún
agregador consulta la base de datos de otro servicio directamente**, en
línea con la regla ya vigente de `data-ownership.md`.

### 5. Estrategia de orquestación para el derecho al olvido (HU-43): coordinación síncrona por API, sin esperar a ADR-006

[ADR-006](ADR-006-messaging.md) fija el alcance de mensajería para tres
integraciones concretas: Account/Commerce → Notifications, Commerce → Catalog
y Commerce → Player/Inventory (reserva de checkout). **No menciona el
derecho al olvido y no lo define como dependiente de su transporte.** Tratar
"ADR-006 sigue Proposed" como un bloqueo de HU-43 sería una inferencia no
sustentada por ese ADR ni por la Política — la primera versión de este
documento cometió exactamente ese error, y se corrige aquí.

Lo que realmente falta para HU-43 es una **decisión de orquestación entre
bounded contexts** — quién invoca a quién, en qué orden, con qué manejo de
fallo parcial — y esa decisión no requiere esperar a que exista un transporte
de mensajería. Se propone:

**Orquestación síncrona coordinada, con registro de progreso por contexto.**

```text
Account (o un coordinador dedicado dentro de Account) recibe la solicitud,
verifica identidad, emite confirmación de RECEPCIÓN, y:

  1. invoca el endpoint de eliminación de cada bounded context relevante
     (Inventory, Community, Commerce, y los que se incorporen) por su API,
     nunca por acceso directo a su almacén — mismo patrón síncrono ya usado
     por Commerce -> Catalog para precio;
  2. cada bounded context expone su propio endpoint de "eliminar/anonimizar
     datos del titular" (por subject), aplicando su propia fila de la
     matriz de tratamiento;
  3. Account registra el progreso por contexto (pendiente/completado/
     fallido) para poder reintentar sin perder la ventana de 30 días, y
     emite la confirmación de CIERRE solo cuando todos los contextos
     relevantes confirman;
  4. un contexto que falla se reintenta dentro del plazo; agotar el plazo
     sin éxito se escala fuera del alcance de este ADR.
```

**Por qué no se necesita una saga con compensación tipo checkout:** el
checkout reserva un recurso escaso (unidades de inventario) con riesgo real
de sobreventa si dos procesos compiten — por eso ADR-006 lo marca
"asíncrono con saga". La eliminación no compite por ningún recurso escaso:
no hay nada que "reservar" ni una condición de carrera que una compensación
deba deshacer. Una orquestación síncrona con reintento simple es suficiente
y evita construir infraestructura de mensajería solo para esto.

Esta decisión es del mismo tipo que la síntesis de agregación de HU-45
(Decisión 4): composición de APIs síncronas entre bounded contexts, sin
depender de ADR-006. La diferencia con HU-45 es de dirección (escritura
coordinada con confirmación de cierre, no solo lectura), no de transporte.

**Lo que sí sigue pendiente y no se fija en este ADR:** el endpoint HTTP
concreto de cada contexto, el formato del registro de progreso, y qué pasa
si el plazo de 30 días se agota sin que todos los contextos confirmen —
quedan para la implementación de HU-43.

### 6. No se centraliza en una "base de privacidad"

Se mantiene el principio de `data-ownership.md`: cada bounded context sigue
siendo dueño de sus datos. Ni la evidencia de consentimiento, ni la
agregación de portabilidad, ni la orquestación de eliminación introducen una
base de datos nueva que centralice información personal de varios
contextos. HU-43 y HU-45 coordinan servicios; no leen directamente las
tablas o colecciones privadas de otro.

## Consecuencias

### Lo que se gana

- HU-43 y HU-45 tienen un contrato estable de identidad, ownership y límites
  de exportación antes de empezar a implementar.
- La frontera exportable/no-portable queda fijada una sola vez, en lugar de
  decidirse de forma distinta por cada endpoint que HU-45 vaya agregando.
- HU-43 tiene una estrategia de orquestación concreta (Decisión 5) sin
  esperar a ADR-006, en vez de quedar indefinida hasta que exista mensajería.
- HU-45 puede empezar a implementarse ya, porque su agregación es de lectura
  síncrona sobre APIs existentes.

### Lo que cuesta

- La orquestación síncrona de HU-43 (Decisión 5) es más simple que una saga,
  pero también más frágil ante fallos parciales largos: un contexto caído
  varios días exige reintento manual dentro de la ventana de 30 días, en
  lugar de una cola con reintento automático. Se acepta ese costo porque no
  hay condición de carrera que compensar, a diferencia del checkout.
- La evidencia de consentimiento sigue sin tabla ni migración: este ADR fija
  ownership (Account) pero no resuelve el gap, que requiere una Task
  separada.

### Lo que permanece bloqueado

- La disponibilidad real de fuentes de datos para HU-45: héroes/estadísticas/
  progreso, y auditoría/sanciones, no existen en ningún servicio desplegado
  — ver [data-treatment-matrix-v0.3.md](../privacy/data-treatment-matrix-v0.3.md).
  Es una dependencia de HU-45 sobre datos inexistentes, no un bloqueo de
  EN-011 ni de este ADR: cuando esos bounded contexts se implementen, deberán
  cumplir la matriz ya documentada aquí.
- La forma física de la evidencia de consentimiento versionado.
- Si EN-011 exige, en sus criterios de aceptación reales (Management #197),
  comportamiento runtime — política publicada y accesible, consentimiento
  efectivamente registrado y consultable — este PR, siendo puramente
  documental, no lo satisface. Ver
  [en-011-closure-readiness.md](../privacy/en-011-closure-readiness.md).

## Alternativas consideradas

| Alternativa | Resultado |
| --- | --- |
| Crear un servicio/base de datos de "Privacidad" que centralice consentimiento, auditoría y evidencia de portabilidad | Descartada: contradice `data-ownership.md` y el principio de que cada bounded context es dueño de sus datos; convertiría un problema de coordinación en un octavo servicio con su propia base |
| Bloquear también HU-45 hasta que ADR-006 se acepte | Descartada: la portabilidad es una agregación de lectura, no requiere transacción distribuida ni compensación; el patrón síncrono ya existe y está probado (`Commerce -> Catalog`) |
| Dejar que cada implementador de HU-45 decida caso por caso qué es exportable | Descartada: produciría criterios distintos por bounded context y el riesgo de exponer un secreto (hash de respuesta de seguridad, token) por omisión, no por decisión |
| Fijar el owner de la evidencia de consentimiento en un servicio nuevo en vez de Account | Descartada: Account ya posee `terms_accepted`; separar la evidencia de consentimiento de la cuenta que consintió duplica ownership sin beneficio visible |
| Esperar a que ADR-006 se acepte e implemente antes de decidir la orquestación de HU-43 | Descartada: ADR-006 no define el derecho al olvido en su alcance; esperar una decisión de mensajería ajena a este problema retrasaría HU-43 sin necesidad, cuando una orquestación síncrona con reintento ya es suficiente porque no hay condición de carrera que compensar |
| Orquestación asíncrona con saga y compensación para HU-43, igual que el checkout | Descartada por ahora: el checkout necesita saga porque compite por un recurso escaso (unidades de inventario); la eliminación no compite por nada, así que la complejidad de una saga con compensación no se justifica todavía. Puede reconsiderarse si el volumen de solicitudes de eliminación lo exige |

## Evidencia y aceptación

- [ ] Revisión del Tech Lead.
- [ ] Confirmación de que la estrategia síncrona de agregación para HU-45 es
      aceptable para el volumen de datos esperado.
- [ ] Confirmación de que la orquestación síncrona con registro de progreso
      (Decisión 5) es aceptable para HU-43, o revisión de una alternativa
      basada en eventos si el Tech Lead prefiere no depender de reintento
      manual.
- [ ] Confirmación de si los criterios de aceptación reales de EN-011
      (Management #197) exigen comportamiento runtime — ver
      [en-011-closure-readiness.md](../privacy/en-011-closure-readiness.md).

Este ADR permanece en `Proposed` hasta que exista esa revisión y quede
registrada, siguiendo la misma regla que el resto de los ADR de este
repositorio (`CONTRIBUTING.md`: "Solo pasa a Accepted con evidencia de
aprobación registrada").

## Reversión

Ninguna de las decisiones de este ADR tiene runtime todavía: no hay tabla de
consentimiento, agregador de portabilidad ni orquestador de eliminación que
revertir. Revertirlo antes de implementación es simplemente no adoptar estos
principios; después de implementación, requeriría un ADR que lo sustituya,
igual que el resto de decisiones arquitectónicas de este repositorio.
