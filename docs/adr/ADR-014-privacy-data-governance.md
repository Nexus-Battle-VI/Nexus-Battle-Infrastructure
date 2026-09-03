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
2. HU-43 (eliminación) tiene su alcance ya formalizado en
   [EN-011 (Management #197)](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/197),
   sección "Decisión de alcance para HU-43 — Derecho al olvido": **Account es
   el owner de la cuenta y de los datos personales que administra**, y la
   mera presencia de un `subject` opaco en Player/Inventory, Community,
   Commerce, Catalog u otro bounded context no obliga a ese servicio a
   participar en la eliminación. La primera versión de este ADR no reflejaba
   esa decisión: describía HU-43 como un proceso coordinado por Account
   contra varios bounded contexts, lo cual contradice el alcance ya aprobado
   — se corrige en la Decisión 5. [ADR-006](ADR-006-messaging.md) sigue
   `Proposed`, pero es irrelevante para esta corrección: no define el derecho
   al olvido en su alcance y, con HU-43 acotada a Account, no hay ninguna
   orquestación entre bounded contexts cuyo transporte dependa de él.
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

### 1. Ownership y evidencia mínima de consentimiento versionado

La evidencia de consentimiento versionado (titular, versión de Política,
fecha/hora) es propiedad de **Account**, no de un servicio de privacidad
transversal nuevo. Razón: Account ya posee `terms_accepted` y es el bounded
context dueño de la cuenta ([data-ownership.md](../architecture/data-ownership.md));
crear un servicio nuevo solo para custodiar un dato adicional de la misma
cuenta duplicaría ownership sin necesidad.

Esta decisión distingue explícitamente dos cosas que la primera versión de
este ADR no separaba con claridad:

**REQUISITO (fijado en este ADR, `Proposed`):** cada aceptación registrada
debe permitir identificar, como mínimo:

- la cuenta/titular que aceptó;
- la versión de la Política que aceptó;
- la fecha y hora en que se produjo la aceptación, generada por el backend
  en el momento de procesar la solicitud — **nunca un valor de fecha/hora
  enviado por Web**, por la misma razón que `subject` no es un parámetro que
  el cliente controle (Decisión 3).

**DECISIÓN DE DISEÑO (NO se fija en este ADR):** la forma física concreta —
tabla nueva, columna adicional, evento de dominio append-only — queda para
la implementación de la Task que resuelva el gap descrito en
[consent-versioning.md](../privacy/consent-versioning.md). En particular,
este ADR **no afirma** que la solución deba ser "dos columnas nuevas en
`accounts`": esa es una posibilidad entre varias, no la decisión tomada aquí.

Una restricción sí se fija como parte del requisito, no del diseño: **la
evidencia debe permitir conservar historial**, no solo el estado de la
última aceptación. Si la Política cambia a una versión futura (v0.4, v0.5,
...) y un titular ya había aceptado v0.3, esa aceptación anterior no debe
quedar destruida ni sobrescrita — debe seguir siendo posible responder "qué
versión aceptó este titular y cuándo" para cualquier versión históricamente
aceptada, no solo la vigente. Un único campo mutable que se sobrescribe en
cada aceptación (equivalente al `terms_accepted` boolean actual, solo que
con versión y fecha) no cumpliría este requisito por sí solo si no conserva
el historial; queda para el diseño de la Task decidir la forma concreta que
lo satisfaga (tabla append-only, log de eventos, u otra).

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

### 5. Alcance y proceso del derecho al olvido (HU-43): ownership de Account, sin orquestación multi-contexto

**Esta decisión sustituye una versión anterior de este ADR** que describía
HU-43 como un proceso coordinado por Account contra varios bounded contexts
(Player/Inventory, Community, Commerce), invocando un endpoint de
eliminación/anonimización en cada uno solo porque conservaban un `subject`.
Esa arquitectura (Opción B) **contradice el alcance de HU-43 ya formalizado**
en [EN-011 (Management #197)](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/197),
sección "Decisión de alcance para HU-43 — Derecho al olvido" (Opción A), que
es la fuente de verdad y no se decide ni se reabre en este ADR — este
documento únicamente la refleja.

#### Ownership

`Nexus-Battle-Account` es responsable de:

- la cuenta;
- la relación `subject -> cuenta/titular` (Decisión 3);
- los datos personales propiedad de Account;
- la ejecución del tratamiento/eliminación de esos datos conforme a HU-43;
- las excepciones de conservación formalmente aprobadas que le correspondan
  a esos datos (Política §10 PARÁGRAFO, §11).

#### Otros bounded contexts

`Community`, `Commerce`, `Player/Inventory`, `Catalog` y demás servicios:

- **no participan automáticamente en HU-43** por el solo hecho de conservar
  un `subject` opaco;
- **no reciben endpoints de borrado por defecto** como parte de esta
  decisión;
- **no son coordinados por Account** para eliminar o anonimizar sus propios
  datos como parte de HU-43;
- mantienen su autonomía y su ownership de datos, sin cambios respecto a
  [data-ownership.md](../architecture/data-ownership.md).

Un `subject` opaco que quede fuera de Account no debe permitir reconstruir
directamente la identidad personal del titular mediante el acceso ordinario
al sistema (EN-011).

**Regla para el futuro:** si posteriormente se identifica en otro bounded
context un dato formalmente clasificado como personal y sujeto al derecho de
eliminación, su tratamiento deberá definirse mediante Refinement o decisión
arquitectónica explícita antes de incorporarse a HU-43. Este ADR no se
anticipa a esa clasificación ni la da por hecha.

#### El proceso, dentro de Account

La petición inicial del titular y el proceso de negocio completo siguen
siendo cosas distintas: HU-43 admite hasta 30 días de plazo (Política §10) y
ninguna petición HTTP puede ni debe permanecer abierta ese tiempo. Pero, a
diferencia de la versión anterior de esta decisión, ese proceso durable
**vive enteramente dentro de Account** — no coordina contextos externos:

```text
Titular autenticado
        |
        v
Account resuelve VerifiedIdentity.subject (Decisión 3)
        |
        v
Cuenta propia
        |
        v
Registrar solicitud (estado: recibida, de forma durable)
        |
        v
Confirmar recepción (la petición HTTP del titular termina aquí)
        |
        v
Proceso de tratamiento dentro de Account
        |
        v
Eliminar/tratar los datos personales propiedad de Account
        |
        v
Aplicar únicamente las excepciones de retención formalmente aprobadas
que correspondan a esos datos
        |
        v
Cerrar la solicitud
        |
        v
Solicitar la notificación de cierre
```

**Propiedades que el proceso dentro de Account puede necesitar** (requisito
de esta decisión cuando el tratamiento no se complete de forma inmediata; el
mecanismo concreto — tabla de estado, job periódico, u otro — es una
decisión de implementación de HU-43, no de este ADR):

- **Estado persistente:** la solicitud y su progreso se persisten, no viven
  solo en la memoria de un proceso.
- **Idempotencia:** reintentar el tratamiento de una misma solicitud no debe
  producir un error ni un efecto distinto de aplicarlo una vez.
- **Reanudación tras reinicio:** si Account se reinicia o despliega una
  nueva versión mientras hay solicitudes en curso, el proceso debe poder
  continuar desde el progreso ya registrado.
- **Manejo de errores:** un fallo transitorio dentro del tratamiento no
  cancela la solicitud; se reintenta dentro del plazo.
- **Seguimiento del plazo de 30 días:** fijado por la Política §10, no por
  este ADR.
- **No se elimina información expresamente retenida:** un dato de Account
  con una excepción de retención formalmente aprobada se marca como
  "aplicado, con excepción", no como pendiente ni como fallo.

Estas propiedades describen el proceso de HU-43 **dentro del alcance de
Account**, no una orquestación de borrado sobre múltiples bounded contexts:
no hay llamadas salientes a otros servicios que reintentar, ni progreso "por
contexto" que agregar, porque ningún otro contexto participa por defecto.

#### Notifications

HU-43 exige que, al cerrar la solicitud, el titular reciba una notificación
de cierre (Política §10). Esto **no convierte a Notifications en
participante de la eliminación**: su única intervención es materializar esa
notificación final, si ya existe un contrato apropiado para invocarla. A la
fecha de este ADR **no existe un contrato definido** para esa notificación
de cierre en [event-catalog.md](../contracts/event-catalog.md) ni en
ningún otro documento de contratos — se declara **pendiente de la
implementación de HU-43**, sin inventar aquí un endpoint o evento nuevo.

#### Por qué no se necesita una saga con compensación tipo checkout

El checkout reserva un recurso escaso (unidades de inventario) con riesgo
real de sobreventa si dos procesos compiten — por eso ADR-006 lo marca
"asíncrono con saga". El tratamiento interno de HU-43 en Account no compite
por ningún recurso escaso ni coordina otros bounded contexts: no hay nada
que "reservar" ni una condición de carrera entre servicios que una
compensación deba deshacer. Un proceso durable con estado persistido,
idempotencia y reintento (descrito arriba) resuelve el problema de
fiabilidad sin necesitar saga, compensación, ni construir infraestructura de
mensajería nueva solo para esto.

**Lo que sí sigue pendiente y no se fija en este ADR:** el endpoint HTTP
concreto de la solicitud, el formato exacto del registro de estado dentro de
Account, el contrato de la notificación de cierre con Notifications, y qué
pasa si el plazo de 30 días se agota sin completar el tratamiento — quedan
para la implementación de HU-43.

### 6. No se centraliza en una "base de privacidad"

Se mantiene el principio de `data-ownership.md`: cada bounded context sigue
siendo dueño de sus datos. Ni la evidencia de consentimiento ni la
agregación de portabilidad introducen una base de datos nueva que centralice
información personal de varios contextos. HU-45 agrega lectura de varios
servicios por su API, nunca por acceso directo a su base; HU-43, con su
alcance acotado a Account (Decisión 5), no necesita coordinar ni leer datos
de ningún otro bounded context.

## Consecuencias

### Lo que se gana

- HU-43 y HU-45 tienen un contrato estable de identidad, ownership y límites
  de exportación antes de empezar a implementar.
- La frontera exportable/no-portable queda fijada una sola vez, en lugar de
  decidirse de forma distinta por cada endpoint que HU-45 vaya agregando.
- HU-43 tiene un alcance y un proceso concretos (Decisión 5), alineados con
  EN-011: Account trata sus propios datos personales, sin depender de una
  decisión de orquestación entre bounded contexts que EN-011 ya descartó.
- HU-45 puede empezar a implementarse ya, porque su agregación es de lectura
  síncrona sobre APIs existentes.

### Lo que cuesta

- El proceso de HU-43 dentro de Account (Decisión 5) sigue exigiendo estado
  persistente, idempotencia y manejo de errores cuando el tratamiento no es
  inmediato — no es tan trivial como una respuesta síncrona única. Se acepta
  ese costo porque de todas formas se necesitaría persistir el estado de la
  solicitud para poder responder al titular durante la ventana de 30 días.
- La evidencia de consentimiento sigue sin tabla ni migración: este ADR fija
  ownership, requisito mínimo de evidencia y necesidad de historial
  (Decisión 1), pero no resuelve el gap — requiere una Task separada.

### Lo que permanece bloqueado

- La disponibilidad real de fuentes de datos para HU-45: héroes/estadísticas/
  progreso, y auditoría/sanciones, no existen en ningún servicio desplegado
  — ver [data-treatment-matrix-v0.3.md](../privacy/data-treatment-matrix-v0.3.md).
  Es una dependencia de HU-45 sobre datos inexistentes, no un bloqueo de
  EN-011 ni de este ADR: cuando esos bounded contexts se implementen, deberán
  cumplir la matriz ya documentada aquí.
- La forma física de la evidencia de consentimiento versionado.
- Si EN-011 exige, en sus criterios de aceptación reales (Management #197),
  comportamiento runtime — política publicada y accesible (CA-01),
  consentimiento efectivamente registrado y consultable (CA-02) — este PR,
  siendo puramente documental, no lo satisface. EN-011 **no debe cerrarse
  con este PR** por esa razón. Ver
  [en-011-closure-readiness.md](../privacy/en-011-closure-readiness.md).

## Alternativas consideradas

| Alternativa | Resultado |
| --- | --- |
| Crear un servicio/base de datos de "Privacidad" que centralice consentimiento, auditoría y evidencia de portabilidad | Descartada: contradice `data-ownership.md` y el principio de que cada bounded context es dueño de sus datos; convertiría un problema de coordinación en un octavo servicio con su propia base |
| Bloquear también HU-45 hasta que ADR-006 se acepte | Descartada: la portabilidad es una agregación de lectura, no requiere transacción distribuida ni compensación; el patrón síncrono ya existe y está probado (`Commerce -> Catalog`) |
| Dejar que cada implementador de HU-45 decida caso por caso qué es exportable | Descartada: produciría criterios distintos por bounded context y el riesgo de exponer un secreto (hash de respuesta de seguridad, token) por omisión, no por decisión |
| Fijar el owner de la evidencia de consentimiento en un servicio nuevo en vez de Account | Descartada: Account ya posee `terms_accepted`; separar la evidencia de consentimiento de la cuenta que consintió duplica ownership sin beneficio visible |
| Adoptar una orquestación general de eliminación sobre Community, Commerce, Player/Inventory, Catalog u otros bounded contexts solo porque conservan un `subject` opaco (versión anterior de esta Decisión 5) | Descartada: contradice el alcance de HU-43 ya formalizado en [EN-011 (Management #197)](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/197). Ningún dato personal sujeto a eliminación ha sido identificado ni clasificado fuera de Account; coordinar la eliminación en otros servicios solo por conservar un identificador técnico opaco invertiría exactamente la regla que EN-011 fija: la existencia de `subject` no obliga a participar |
| Que la petición HTTP inicial de eliminación permanezca abierta hasta que el tratamiento dentro de Account termine | Descartada: HU-43 admite hasta 30 días de plazo; ninguna petición HTTP puede ni debe mantenerse abierta ese tiempo. El titular recibe confirmación de RECEPCIÓN de inmediato; el tratamiento sigue de forma durable, fuera de esa petición (Decisión 5) |
| Que el agregador de HU-45 sea consultado, o que HU-43 modifique datos de otro bounded context, por acceso directo a su base de datos en vez de por su API | Descartada: viola directamente `data-ownership.md` ("un servicio que necesita más que el identificador pregunta por la API"); acoplaría el esquema interno de cada servicio a un agregador externo y rompería el aislamiento ya verificado entre bases (Postgres/Mongo por servicio) |

## Evidencia y aceptación

- [ ] Revisión del Tech Lead.
- [ ] Confirmación de que la estrategia síncrona de agregación para HU-45 es
      aceptable para el volumen de datos esperado.
- [ ] Confirmación de que el proceso de tratamiento dentro de Account, con
      estado persistente, idempotencia y manejo de errores (Decisión 5), es
      aceptable para HU-43, dado que su alcance ya está acotado a Account por
      EN-011 (Management #197) y no coordina otros bounded contexts.
- [ ] Confirmación del owner funcional/técnico y del requisito mínimo de
      evidencia de consentimiento versionado (Decisión 1) por parte de quien
      vaya a implementar la Task de Account.
- [x] Confirmación de que los CA reales de EN-011 (Management #197) exigen
      comportamiento runtime: CA-01 (política publicada y accesible) y CA-02
      (consentimiento explícito y trazable, no solo un estado visual de
      frontend) — ver [en-011-closure-readiness.md](../privacy/en-011-closure-readiness.md).
      **Conclusión: EN-011 no debe cerrarse con este PR**; CA-03/CA-04/CA-05
      quedan cubiertos a nivel documental/arquitectónico, CA-01/CA-02
      requieren implementación runtime fuera del alcance de esta rama.

Este ADR permanece en `Proposed` hasta que exista esa revisión y quede
registrada, siguiendo la misma regla que el resto de los ADR de este
repositorio (`CONTRIBUTING.md`: "Solo pasa a Accepted con evidencia de
aprobación registrada").

## Reversión

Ninguna de las decisiones de este ADR tiene runtime todavía: no hay tabla de
consentimiento, agregador de portabilidad ni proceso de tratamiento de HU-43
en Account que revertir. Revertirlo antes de implementación es simplemente no
adoptar estos principios; después de implementación, requeriría un ADR que lo
sustituya, igual que el resto de decisiones arquitectónicas de este
repositorio.
