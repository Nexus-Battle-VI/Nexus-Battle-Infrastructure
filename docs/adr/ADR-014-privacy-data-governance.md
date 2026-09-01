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
   pero **no existe comunicación entre bounded contexts** —
   [ADR-006](ADR-006-messaging.md) sigue `Proposed` y la saga de checkout,
   un caso más simple, está declarada `No implementado`
   ([integration.md](../architecture/integration.md)).
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

### 5. Estrategia de orquestación para el derecho al olvido (HU-43): bloqueada por ADR-006

A diferencia de la portabilidad, la eliminación **sí depende** de que
[ADR-006](ADR-006-messaging.md) se acepte y se implemente un transporte
entre bounded contexts. Razón: eliminar o anonimizar datos en varios
servicios de forma coordinada, con posibilidad de fallo parcial y
excepciones de retención por categoría, es exactamente el tipo de proceso de
larga duración con compensaciones que ADR-006 ya identificó para la saga de
checkout (`Commerce -> Player/Inventory`, "asíncrono con saga", **no
implementado**).

Este ADR no reabre ni sustituye ADR-006. Registra la dependencia
explícitamente: **HU-43 no puede implementar eliminación multi-contexto
hasta que ADR-006 tenga transporte aceptado e implementado.** Mientras
tanto, HU-43 puede avanzar en la eliminación dentro de un único bounded
context (Account) y en el flujo de verificación/confirmación, sin
coordinación entre servicios.

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
- La dependencia real de HU-43 con ADR-006 queda explícita y trazable, en
  vez de descubrirse a mitad de implementación.
- HU-45 puede empezar a implementarse sin esperar a ADR-006, porque su
  agregación es de lectura síncrona.

### Lo que cuesta

- HU-43 queda formalmente bloqueada hasta que ADR-006 avance — no es un
  costo que este ADR introduce, es uno que ya existía y que este documento
  hace visible en vez de dejarlo implícito.
- La evidencia de consentimiento sigue sin tabla ni migración: este ADR fija
  ownership (Account) pero no resuelve el gap, que requiere una Task
  separada.

### Lo que permanece bloqueado

- La implementación de la eliminación multi-contexto (HU-43), por ADR-006.
- El owner de datos de héroes/estadísticas/progreso, y de
  auditoría/sanciones — no existen en ningún servicio desplegado; ver
  [data-treatment-matrix-v0.3.md](../privacy/data-treatment-matrix-v0.3.md).
- La forma física de la evidencia de consentimiento versionado.

## Alternativas consideradas

| Alternativa | Resultado |
| --- | --- |
| Crear un servicio/base de datos de "Privacidad" que centralice consentimiento, auditoría y evidencia de portabilidad | Descartada: contradice `data-ownership.md` y el principio de que cada bounded context es dueño de sus datos; convertiría un problema de coordinación en un octavo servicio con su propia base |
| Bloquear también HU-45 hasta que ADR-006 se acepte | Descartada: la portabilidad es una agregación de lectura, no requiere transacción distribuida ni compensación; el patrón síncrono ya existe y está probado (`Commerce -> Catalog`) |
| Dejar que cada implementador de HU-45 decida caso por caso qué es exportable | Descartada: produciría criterios distintos por bounded context y el riesgo de exponer un secreto (hash de respuesta de seguridad, token) por omisión, no por decisión |
| Fijar el owner de la evidencia de consentimiento en un servicio nuevo en vez de Account | Descartada: Account ya posee `terms_accepted`; separar la evidencia de consentimiento de la cuenta que consintió duplica ownership sin beneficio visible |

## Evidencia y aceptación

- [ ] Revisión del Tech Lead.
- [ ] Confirmación de que la estrategia síncrona de agregación para HU-45 es
      aceptable para el volumen de datos esperado.
- [ ] Decisión explícita sobre si HU-43 se acota a un solo bounded context
      (Account) como primera entrega, mientras ADR-006 avanza.

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
