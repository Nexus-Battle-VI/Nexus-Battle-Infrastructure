# Documento de Arquitectura de Software — Nexus Battles VI

- **Versión:** 0.1.0 (Sprint 1 — Foundation)
- **Fecha:** 2026-08-21
- **Estado:** Evolutivo. Cada ADR declara su estado y evidencia de aprobación.

## 1. Propósito y alcance

Este documento describe la arquitectura de Nexus Battles VI tal como existe al cierre del Sprint 1. Es la fuente de verdad técnica del sistema; el gobierno del producto, las Issues y el Product Backlog viven en [Nexus-Battle-Management](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management).

**Lo que este documento describe es lo que está construido y verificado.** Lo que no está construido se declara como tal, con su motivo y su condición de desbloqueo. Esa distinción es deliberada: un documento de arquitectura que describe intenciones como si fueran hechos es peor que no tenerlo.

## 2. Contexto del producto

Nexus Battles VI es un producto único desarrollado por tres Teams — Alfa, Beta y Gama — con 18 integrantes. Ofrece cuentas de jugador, inventario, catálogo de productos, comunidad y pedidos, con notificaciones transaccionales.

## 3. Restricciones que gobiernan la arquitectura

| Restricción | Origen | Efecto |
| --- | --- | --- |
| Techo de **USD 100/mes** en la demo | Presupuesto | Excluye persistencia gestionada, balanceadores y NAT |
| **Identidad delegada** | ADR-004 | Cognito emite JWT; Account posee roles y los refleja en grupos |
| RNF objetivo: 100 000 concurrentes, 99,95 % | Requisitos | **Incompatible** con el techo de coste: obliga a documentar dos arquitecturas |
| Management es fuente única de Issues | Gobierno | Los repositorios de código no tienen Issues ni Projects |
| Requisito de Directorio Activo | Requisitos | No se cumple por coste. Ver [ADR-004](../adr/ADR-004-identity-directory.md) |

Las dos primeras son las que más forma dan al sistema.

## 4. Bounded contexts

La cadena que determina cada servicio es:

```text
requisito -> dominio -> bounded context -> propiedad de datos
          -> dependencias -> contrato -> deployable -> Team -> repositorio
```

El punto que decide es la **propiedad exclusiva de datos**. Ver [ADR-001](../adr/ADR-001-repository-strategy.md).

| Contexto | Responsabilidad | Team | Repositorio |
| --- | --- | --- | --- |
| Account / Identity | Existencia de la cuenta, ciclo de vida y roles | Alfa | `Nexus-Battle-Account` |
| Player / Inventory | Qué posee un jugador y en qué cantidad; y el héroe: su equipamiento, su selección y su progresión | Alfa | `Nexus-Battle-Player-Inventory` |
| Catalog | Qué productos existen y a qué precio | Gama | `Nexus-Battle-Catalog` |
| Community | Hilos, mensajes y moderación | Gama | `Nexus-Battle-Community` |
| Commerce | Pedidos, líneas y totales | Beta | `Nexus-Battle-Commerce` |
| Notifications | Entrega de correo transaccional | Alfa | `Nexus-Battle-Notifications` |

Más dos repositorios que no son bounded contexts: `Nexus-Battle-Web` (interfaz de los seis) y `Nexus-Battle-Infrastructure` (este repositorio).

Detalle en [microservices.md](microservices.md) y [data-ownership.md](data-ownership.md).

### Combat / aleatoriedad

Combat (Sprint 2, [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md)) posee las salas, la batalla, el motor, **la aleatoriedad** y las tablas de efectos. El tiempo real de las salas se decide en [ADR-020](../adr/ADR-020-realtime-combat.md) y el generador pseudoaleatorio, su relación con la tabla de 8000 posiciones y la semilla validada en [ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md) (`Accepted`).

```text
semilla -> MT19937 -> Box-Müller -> Z ~ N(0,1) -> Φ(Z) -> indice uniforme 1..8000 -> tabla vigente (HU-25) -> efecto
```

- La normal pertenece a la variable intermedia `Z`; el índice que consulta la tabla es **uniforme**, para que «4800 filas de 8000» sea realmente el 60 %. HU-26 aportó un estudio estadístico aceptado sobre la representación normal escalada de ese procedimiento y la selección de la semilla; no es una prueba de paridad numérica con la `Z ~ N(0,1)` que genera hoy Combat.
- Player/Inventory entrega el héroe equipado (`subtype`, `activeEffects`) por contrato interno; Combat construye la tabla vigente. Missions no genera números: pedirá simulaciones a Combat (contrato **previsto**).
- **Implementado** en Combat: motor HU-24, tabla y resolución HU-25, `CRITICAL_CHANCE` sobre la tabla y salas/lobby. **Pendiente:** política de semilla por batalla o simulación (la semilla 3.000.000 es la validada por HU-26, no una semilla global), Missions → Combat y el consumo por HU-20.
- Diagrama: [combat-randomness.puml](../diagrams/combat-randomness.puml).

### Progresión del héroe (HU-08)

Player/Inventory posee el **nivel** y la **experiencia acumulada** del héroe, en un agregado por `(jugador, héroe)` con su propio almacén. No es una decisión nueva de este documento: la ficha de ownership de [ADR-019](../adr/ADR-019-sprint-2-bounded-contexts.md) ya asigna a Player/Inventory el héroe, su equipamiento y sus estadísticas efectivas, y solo ese contexto escribe su Mongo.

La regla vive **en proceso**, en `ExperiencePolicy`, como política pura: no persiste, no expone HTTP y no entrega experiencia. Contiene la **tabla de umbrales vigente** —`100 · 300 · 500 · 700 · 900 · 1.100 · 1.300`, de experiencia **acumulada** para **pasar** de cada nivel al siguiente; nivel máximo 8— y las dos direcciones de esa tabla: el umbral para salir de un nivel y el nivel de un acumulado. Esa tabla sustituye la fórmula original del PDF y la tabla temporal anterior por decisión funcional posterior. El **umbral no se almacena** —es derivable del nivel—, de modo que la regla tiene un único punto conceptual y no puede desincronizarse.

```text
nivel actual (1..8)  -> ExperiencePolicy -> umbral del siguiente nivel, o MAX_LEVEL
xp acumulada         -> ExperiencePolicy -> nivel alcanzado (puede cruzar varios de golpe)
```

- **Lo que está**: el diseño, el modelo de dominio, la migración `008-hero-progressions`, los adaptadores y la suite de pruebas (Tasks #188, #189 y #190). Ver [la evidencia de HU-08](../evidence/HU-08-calculo-de-experiencia-requerida-por-nivel.md) y el [diseño](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/blob/develop/docs/hu-08-progresion.md).
- La **experiencia solo crece**: subir de nivel no la descuenta, y en el nivel máximo sigue acumulándose sin descartarse. El nivel persistido es la tabla aplicada al acumulado, y esa coherencia se comprueba al leer el documento.
- **La recompensa no se calcula aquí.** `10 × 1,2^(1d8)` es de Missions y la tirada `1d8` es de Combat ([ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md)); Player/Inventory recibe un importe entero y lo acredita.
- El umbral es función del **nivel** y no de las estadísticas: **no** interviene en `computeEffectiveStats` ni en el contrato `equipped-hero`, que sigue sin llevar nivel. Ver las limitaciones correspondientes en §14.

### Experiencia por derrota de un rival (HU-09)

La recompensa de experiencia `10 × 1,2^(1d8)` se otorga **al derrotar a un rival NPC en una misión (JvE)**, según la aclaración funcional del Product Owner. **El PvP («Jugar Online») no la otorga.** La responsabilidad se reparte entre tres contextos, porque ninguna de las tres piezas puede vivir en los otros dos:

```text
Combat    -> produce y PERSISTE un 1d8 por NPC derrotado (ADR-021); no conoce la fórmula
Missions  -> calcula 10 x 1,2^(1d8) por derrota, lo redondea a entero y coordina la recompensa
Player/Inv-> acredita cada derrota y recalcula el nivel con la tabla de HU-08
```

- **Una recompensa, una tirada y una acreditación por cada NPC derrotado**, no una por misión. La clave es la **instancia real de la derrota** (encuentro + enemigo concreto del `combatLog` de HU-72), nunca el arquetipo: una misión puede enfrentar dos veces al mismo tipo de enemigo y el arquetipo colisionaría.

- **Combat no calcula experiencia** y **Missions no genera aleatoriedad**: `ADR-021` da la exclusiva del azar a Combat y `ADR-019` da la propiedad del estado del héroe a Player/Inventory. La tirada se persiste **antes de responder**, de modo que un reintento no vuelve a consumir el cursor aleatorio.
- La acreditación es **idempotente** por `operationId` determinista, con ledger propio en Player/Inventory (`_id = operationId`) y actualización de la progresión en la misma transacción. Un reintento nunca duplica experiencia.
- **Estado:** **implementada y verificada de extremo a extremo; NO aceptada.** Las tres piezas existen (Combat `#440`, Player/Inventory `#441` y Missions `#442`; la vista en Web `#443` no forma parte) y la cadena se recorre entera: 13/13 escenarios en verde (`S-00` a `S-12`) sobre las tres piezas reales, con las sustituciones declaradas, con el reporte en [`hu-09-ejecucion-e2e.json`](../evidence/hu-09-ejecucion-e2e.json). Falta la revisión por pares y la aprobación del PO (`CA-09`). **`P-2` está cerrada**: redondeo al entero más próximo (`12, 14, 17, 21, 25, 30, 36, 43`); el truncamiento quedó descartado. **`CA-08` se rige por la derrota válida de un NPC**, no por que la misión termine `COMPLETED`: una misión `FAILED` con NPC ya derrotados conserva su XP y una `VOIDED` no devenga esta recompensa (contrato §14.1). Ver el [contrato](../contracts/hu-09-experience-reward-v1.md), el [diseño](hu-09-experiencia-mision.md) y la [evidencia](../evidence/HU-09-experiencia-por-derrota-de-un-rival.md).
- **Límite conocido:** el escenario sustituye el resultado de la simulación de HU-72 y el perfil del héroe —son **la misma dependencia**: la ruta de simulación de Combat existe y valida `hero.profile.effectiveStats` y `hero.profile.subtype`. La ruta interna de perfil de Player/Inventory (`HU-71.2`, PR #48) **ya está en `develop`**, pero la cadena todavía no se ha migrado a ella ni se ha vuelto a medir—, más el compromiso del héroe y el testimonio. El escenario `S-12` (`FAILED` con bajas) sustituye además la bitácora de la simulación. La tirada, el cálculo, la acreditación y el nivel **sí** son los reales. Está declarado en la evidencia, pieza por pieza.

### Liquidación de recompensas de finalización de misión (HU-10)

HU-10 acredita la XP y las recompensas de **finalización** de una misión, **distintas** de la XP por derrota de HU-09. El reparto respeta ADR-019: **Missions** decide la elegibilidad, congela la liquidación desde el contenido de la ejecución y coordina cada entrega por línea; **Player/Inventory** acredita XP (con un origen propio, distinto de `MISSION_RIVAL_DEFEAT`) y productos (`inventory/grants`); **Wallet** acredita créditos con una operación específica de misión (no la de batalla de HU-22); **Combat** sigue siendo la única fuente de aleatoriedad y HU-10 **no** vuelve a sortear el botín (HU-72) ni a conceder la épica (HU-73); **Web** solo presenta.

- **Estado:** **implementada y verificada técnicamente; no aceptada ni cerrada.** La cadena HU-10.7 usa Missions, Player-Inventory y Wallet reales sobre sus propios motores, con HMAC interno y evidencia de 18 `PASS`, 0 `FAILED`, 2 `SKIPPED`. Ver el [contrato](../contracts/hu-10-mission-completion-reward-v1.md) y la [evidencia](../evidence/HU-10-recompensas-finalizacion-mision.md).
- **Sin transacción distribuida:** intención local → llamada con `operationId` por línea → resultado persistido → reintento idempotente.
- **Pendientes funcionales que el diseño no inventa:** `ABANDONED`, desenlaces en los que aplican créditos/garantizados, definición de «primera vez» y los montos concretos (contrato §19).

### Bloqueo de equipamiento en combate (HU-29)

Con una batalla **activa**, el equipamiento con el que el héroe **entró** permanece fijo: toda mutación del loadout —arma, armadura o ítem— se **rechaza** con un mensaje explicativo y el loadout **no se modifica**. Al terminar la batalla la restricción **deja de aplicarse**. La regla **precede** a la operación de equipar de HU-28; no la reimplementa ni toca las capacidades 2/6/2.

```text
estado de batalla publicado -> RestriccionEquipamientoEnCombate -> procede | rechazado con motivo
```

- **El estado de batalla lo publica Combat**, no Player/Inventory, y llega como un **compromiso** que Player/Inventory guarda y consulta localmente, no como una consulta al vecino en el camino crítico del equipamiento. El diseño no prescribía transporte; la implementación sí tuvo que fijarlo y lo hizo en [`hu-29-battle-commitment-v1`](../contracts/hu-29-battle-commitment-v1.md): `ADR-019` ya había decidido el **QUÉ** —Player/Inventory posee los **compromisos** del héroe (`BATTLE`, `MISSION`, `AUCTION`, `TOURNAMENT`) y Combat publica el compromiso **al iniciar** y lo **libera al terminar**, de forma síncrona y con `operationId`—, y el contrato solo fija el **CÓMO**.
- **El loadout no se clona.** Como la mutación no se aplica, no hace falta un snapshot que demuestre «sin modificaciones»: una copia sería una segunda versión de la misma verdad.
- **Sin lock permanente.** No hay nada que «desbloquear»: hay una condición que se cumple mientras dure la batalla.
- **Estado:** **implementada en `develop` y verificada de extremo a extremo entre los dos servicios reales.** El diseño es la Task [#231](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/231); la implementación es [#232](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/232), mergeada en Player/Inventory ([#26](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/26), matriz de pruebas [#59](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/59)) y en Combat ([#55](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/55)), con el contrato [`hu-29-battle-commitment-v1`](../contracts/hu-29-battle-commitment-v1.md) ([#165](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/165)). La verificación de aceptación es [#233](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/233): la matriz P1/P2/P3 unitaria ya estaba mergeada, y la prueba de extremo a extremo entre los dos servicios reales (Combat real → HMAC real → Player/Inventory real → MongoDB real de cada uno) se añadió en Combat PR [#62](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/62) (13 escenarios, en verde, **abierto, sin mergear**). La presentación en Web es PR [#191](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/191) (**abierto, sin mergear**; el PR anterior, Web #90, se cerró sin mergear). «Batalla activa» es la lectura literal `IN_BATTLE` (decisión del PO ya tomada, ver evidencia); el texto del mensaje no tiene un copy oficial fijo porque la HU solo exige que explique el motivo, no una frase normativa. La exclusión cruzada entre propósitos (`MISSION` y `BATTLE` a la vez) sigue sin implementarse y queda declarada como límite fuera de este alcance. La integración es la que `ADR-019` ya había decidido: **compromiso publicado por Combat al iniciar y liberado al terminar**, con `operationId` de idempotencia, y **no** una consulta de Player/Inventory a Combat en el camino crítico del equipamiento. Ver el [diseño](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/blob/develop/docs/hu-29-bloqueo-equipamiento-combate.md) y [la evidencia](../evidence/HU-29-bloqueo-equipamiento-en-combate.md).
- Diagramas: [caso de uso](../diagrams/hu-29-use-case.puml), [actividad](../diagrams/hu-29-activity.puml), [secuencia](../diagrams/hu-29-sequence.puml), [dominio](../diagrams/hu-29-domain.puml).

## 5. Arquitectura interna común

Los seis servicios comparten la misma estructura: **Clean + Hexagonal**.

```text
adapters/inbound   -> application -> domain
                                       ^
adapters/outbound  ---------------------
infrastructure     -> composicion de todo lo anterior
```

Dos restricciones **verificadas por CI**, no solo documentadas:

- El dominio no importa NestJS, SDK de AWS, ORM, HTTP ni drivers de base de datos.
- La capa de aplicación depende de sus puertos, nunca de adaptadores concretos.

Están implementadas como reglas `no-restricted-imports` de ESLint. Un cambio que las incumpla **no puede integrarse**.

Los casos de uso son clases planas sin decoradores, registradas mediante fábricas explícitas: la capa de aplicación podría ejecutarse fuera de NestJS sin cambios.

## 6. Patrones aplicados

| Patrón | Dónde | Por qué ahí |
| --- | --- | --- |
| Ports and Adapters | Los seis servicios | Permite sustituir persistencia, identidad y mensajería sin tocar el dominio |
| Repository | Los seis | Aísla el agregado del mecanismo de almacenamiento |
| Domain Events | Los seis | Registra hechos de forma trazable y desacoplada del transporte |
| State | Catalog, Commerce, Community | El conjunto de operaciones válidas depende del estado |
| Idempotent Consumer | Notifications | La entrega «al menos una vez» reentrega mensajes |
| Retry con retroceso exponencial | Notifications | Un proveedor caído no debe recibir reintentos en bucle |
| Dead Letter Queue | Notifications | Un mensaje irreprocesable debe salir del flujo |
| Anti-corruption layer | Commerce → Catalog | Traduce el modelo de producto a lo único que Commerce necesita: un importe |
| Compensación explícita | Account | Evita identidades huérfanas sin transacción distribuida |

**No se aplica CQRS ni Event Sourcing globalmente.** Ningún contexto tiene un modelo de lectura suficientemente distinto del de escritura como para justificar el coste, y ninguno necesita reconstruir estado histórico.

**Saga:** identificada para el checkout, **no implementada**. Ver [ADR-006](../adr/ADR-006-messaging.md).

## 7. Decisiones de dominio que conviene conocer

Cuatro decisiones concentran buena parte del valor del modelado:

| Decisión | Contexto | Por qué |
| --- | --- | --- |
| **La capacidad limita ranuras, no unidades** | Player/Inventory | Apilar más unidades de un objeto ya poseído no consume ranura, ni siquiera con el inventario lleno |
| **El dinero es un entero en la unidad mínima** | Catalog, Commerce | Con punto flotante, el total de un pedido puede no coincidir con la suma visible de sus líneas |
| **El precio se congela al añadir la línea** | Commerce | Consultarlo al confirmar dejaría que un cambio de catálogo alterase retroactivamente lo que la persona vio |
| **Ocultar no es borrar** | Community | Un mensaje moderado deja de verse pero se conserva, para que la decisión sea revisable |

Cada una está cubierta por pruebas específicas.

## 8. Persistencia

*Database per Service* con *Polyglot Persistence*. Ver [ADR-005](../adr/ADR-005-data-strategy.md) y [data-ownership.md](data-ownership.md).

**Estado real:** los seis servicios operan con **repositorios en memoria**. No son simulaciones: implementan el contrato completo y almacenan instantáneas, no referencias vivas al agregado. La elección de ORM u ODM queda deliberadamente abierta.

## 9. Integración

Ver [integration.md](integration.md) y [ADR-006](../adr/ADR-006-messaging.md).

**Estado real:** los servicios **no se comunican entre sí todavía**. Los puertos existen y tienen implementaciones locales completas; el transporte depende de una decisión pendiente. Es la limitación funcional más visible del Sprint 1.

## 10. Despliegue

Dos arquitecturas explícitamente separadas:

- [sprint-demo-deployment.md](sprint-demo-deployment.md) — la que cabe en USD 100/mes. **Punto único de fallo, sin autoescalado, sin multi-AZ.**
- [target-scale-deployment.md](target-scale-deployment.md) — la que cumpliría los RNF. **No provisionada, no implementada.**

**En esta ejecución no se ha provisionado ningún recurso de AWS.**

## 11. Seguridad

Ver [security.md](security.md).

Los cinco servicios verifican JWT emitidos por Cognito. Account conserva la
fuente de verdad de roles y refleja los grupos; solo el Super Administrador
gestiona `MODERATOR` y `ADMINISTRATOR`. La elevación administrativa exige TOTP
confirmado. Ver [ADR-004](../adr/ADR-004-identity-directory.md) y
[el diseño de HU-39](hu-39-role-management.md).

**Privacidad y tratamiento de datos:** el gobierno documental de EN-011 —
política versionada, matriz de tratamiento, contrato de portabilidad,
consentimiento y diseño de alto nivel de HU-43/HU-45 — vive en
[docs/privacy](../privacy/) y [ADR-014](../adr/ADR-014-privacy-data-governance.md)
(`Proposed`). El derecho al olvido (HU-43) ya tiene implementación runtime
completa, Account-only, mergeada a `develop` en Account, Notifications y Web
(Management #303–#307) — ver
[hu-43-account-deletion-design.md](../privacy/hu-43-account-deletion-design.md#qué-quedó-implementado-verificado-en-código-y-pr-mergeados-a-develop).
La evidencia de consentimiento versionado (Decisión 1 de ADR-014) y el
agregador de portabilidad multi-contexto de HU-45 (Decisión 4) siguen sin
runtime.

## 12. Observabilidad

Ver [observability.md](observability.md) y [ADR-009](../adr/ADR-009-observability.md).

Registro JSON estructurado y sondas de salud reales en los siete deployables. Sin trazas ni métricas, porque no hay tráfico entre servicios que trazar.

## 13. Calidad

Ver [testing.md](testing.md).

| Repositorio | Pruebas | Sentencias | Ramas |
| --- | --- | --- | --- |
| Notifications | 133 | 99,75 % | 96,63 % |
| Account | 94 | 99,72 % | 93,80 % |
| Player-Inventory | 83 | 98,03 % | 91,58 % |
| Catalog | 95 | 98,39 % | 92,74 % |
| Community | 67 | 98,65 % | 90,72 % |
| Commerce | 74 | 99,03 % | 92,56 % |
| Web | 56 | 92,08 % | 97,61 % |
| **Total** | **602** | — | — |

Umbral exigido: 80 %. Todos lo superan.

## 14. Limitaciones del estado actual

Se enumeran juntas porque quien lea este documento necesita conocerlas antes de tomar cualquier decisión sobre el sistema:

1. **Sin comunicación entre servicios.** Los puertos existen; el transporte no.
2. **Sin saga de checkout.** Confirmar un pedido no reserva inventario.
3. **Cinco de las seis pantallas de Web** son marcadores declarados.
4. **La arquitectura de demo no cumple los RNF** y tiene un punto único de fallo.
5. **Sin licencia asignada** (`Licensing pending project governance`).
6. **Ventana de access tokens retirados.** Un JWT anterior puede conservar sus
   claims hasta `exp`, máximo 15 minutos, aunque Cognito cierre las sesiones.
7. **Aceptación humana de HU-39 en curso.** La entrega técnica está desplegada;
   el ciclo real de TOTP, asignación, Catalog y retirada se conserva como
   evidencia pendiente de completar.
8. **`CA-03` de HU-08 se corrige al umbral acumulado vigente.** El criterio enunciaba
   `100 × 1,2^(Nivel−1)`; la fórmula original del PDF y la tabla temporal anterior
   (`100 · 200 · … · 12.800`) quedan sustituidas por `100 · 300 · 500 · 700 · 900 ·
   1.100 · 1.300` por decisión funcional posterior (no estaba en el PDF). La migración
   `013-hero-progressions-cumulative-thresholds` recalcula el nivel de los héroes ya
   persistidos sin tocar su XP. `CA-06` sigue sin implementarse.
9. **`CA-06` de HU-08 sin implementar, y bloquea la aceptación de la historia.** El
   Product Owner **ya dio la regla**: la estadística del nivel 1 multiplicada por el
   nivel actual, con el equipamiento aplicado después. Sigue fuera de HU-08 porque la
   propia HU declara que **no** recalcula reglas de combate, y porque implementarla
   tocaría `computeEffectiveStats` y el contrato `equipped-hero`. **Y hay un caso que
   la aclaración no resuelve:** las estadísticas expresadas como **dados** —el `1d8`
   que Combat documenta en su `AttackProfile`— no tienen definida la multiplicación
   por nivel. Como `CA-08` establece que un criterio obligatorio fallido impide
   aceptar la HU, HU-08 no puede aceptarse mientras `CA-06` siga asignado a esta
   historia. Requiere decisión de PO y arquitectura: implementarlo aquí, moverlo a
   otra historia, o reformularlo como no obligatorio. El precedente es HU-07/`CA-09`,
   que se declaró fuera de alcance con cita textual.
10. **`equipped-hero` no lleva el nivel del héroe.** El contrato interno que Combat
    consume es un subconjunto deliberado, y su propio código documenta que «si Combat
    necesita escalar por nivel, es una decision de producto pendiente». Con `CA-06` ya
    con fórmula, esta decisión es el camino crítico de esa parte: ampliar
    `EquippedHeroDto` es un cambio de contrato con su propio proceso.
11. **La política de redondeo de la recompensa de experiencia está cerrada, y no es
    de Player/Inventory.** `10 × 1,2^(1d8)` —la XP por muerte de NPC en misiones
    JvE— es de Missions, y su tirada `1d8` es de Combat ([ADR-021](../adr/ADR-021-combat-randomness-and-effect-table.md)).
    El PO decidió el redondeo al entero más próximo (Management #18) y descartó el
    truncamiento. La tabla de umbrales no tiene fracciones que redondear, así que esto
    no afecta al cálculo del nivel.
12. **HU-09 ya no está bloqueada: está implementada y verificada, y sigue SIN aceptar.**
   El bloqueo que se registró aquí —Missions sin rutas ni tablas, `HU-72.2`/`HU-74.2`
   solo diseñadas y `HU-08` sin mergear— se ha resuelto: las tres piezas están en
   `develop` y la cadena de experiencia se recorre de extremo a extremo, con 13/13
   escenarios en verde (`S-00` a `S-12`) sobre tres repositorios sin cambios pendientes
   ([reporte](../evidence/hu-09-ejecucion-e2e.json)). Lo que queda **no es técnico**:
   revisión por pares y aprobación del PO (`CA-09`).
   Ver el [contrato](../contracts/hu-09-experience-reward-v1.md) y la
   [evidencia](../evidence/HU-09-experiencia-por-derrota-de-un-rival.md).
13. **La decisión de redondeo de HU-09 (`P-2`) está CERRADA: redondeo al entero más
   próximo.** El PO la fijó en Management #18 y descartó el truncamiento
   (`4 → 21`, no `20`; `8 → 43`, no `42`). La regla vive en un único punto —la política
   pura de Missions— y Player/Inventory recibe siempre un entero. La propiedad se
   mantiene: Combat = aleatoriedad, Missions = fórmula, Player/Inventory = progresión.
   Ver el [contrato](../contracts/hu-09-experience-reward-v1.md) §6 y §15.
14. **`missions` no está en el allow-list interno de Player/Inventory.** Hoy es
    `['commerce', 'notifications', 'combat']`. La ruta de acreditación de
    experiencia se acota con `@InternalCallers('missions')` **sin** ampliar la
    lista global: es una decisión de mínimo privilegio, no un pendiente. La cadena
    de HU-09 lo ejerce de verdad (`S-05`, `S-06`).
11. **El bloqueo de equipamiento en combate (HU-29) no impide que un héroe esté comprometido a
    `MISSION` y a `BATTLE` a la vez.** El backend (Player/Inventory [#26](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/26)/[#59](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/pull/59),
    Combat [#55](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/55)) ya está mergeado y
    verificado de extremo a extremo entre los dos servicios reales (Combat PR
    [#62](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/62)); lo que sigue sin
    implementarse, a propósito, es la exclusión cruzada entre los dos propósitos de compromiso
    (`hu-29-battle-commitment-v1` §10). Es una regla de producto distinta, no una condición de
    aceptación de esta HU, y queda declarada como límite. La épica **no** entra en el bloqueo: la HU
    nombra arma, armadura e ítem, y HU-28 excluye `EPICA` de las categorías equipables. Ver el
    [diseño](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/blob/develop/docs/hu-29-bloqueo-equipamiento-combate.md)
    y [la evidencia](../evidence/HU-29-bloqueo-equipamiento-en-combate.md).

Ninguna es un descuido. Cada una tiene su motivo registrado y su condición de desbloqueo.

### Superadas el 2026-08-29, y por qué se dejan escritas

- ~~**Sin control de acceso.**~~ Los cinco servicios verifican el testimonio contra el JWKS del pool (`AUTH_MODE=jwt`). Comprobado de extremo a extremo. El rol viaja dentro del testimonio desde que Account lo refleja en el proveedor.
- ~~**Sin persistencia real.**~~ Los cinco declaran PostgreSQL o MongoDB, con migraciones propias. Comprobado con el caso que lo demuestra: una cuenta creada días antes sigue ahí tras reemplazar por completo el nodo de aplicación.
- ~~**No hay infraestructura AWS provisionada.**~~ 43 recursos con Terraform y estado remoto en S3.

Se dejan tachadas en lugar de borrarlas: quien haya leído una versión anterior necesita saber qué cambió, y una limitación que desaparece sin rastro parece que nunca existió.

## 15. Índice de decisiones

| ADR | Decisión | Estado |
| --- | --- | --- |
| [001](../adr/ADR-001-repository-strategy.md) | Estrategia de repositorios | Proposed |
| [002](../adr/ADR-002-backend-stack.md) | Stack de backend | Proposed |
| [003](../adr/ADR-003-frontend-stack.md) | Stack de frontend y TypeScript 7 | Proposed |
| [004](../adr/ADR-004-identity-directory.md) | Identidad y directorio | Proposed — **BLOCKER** |
| [005](../adr/ADR-005-data-strategy.md) | Estrategia de datos | Proposed |
| [006](../adr/ADR-006-messaging.md) | Mensajería e integración | Proposed |
| [007](../adr/ADR-007-aws-cost-optimized-platform.md) | Plataforma AWS por coste | Proposed |
| [008](../adr/ADR-008-iac.md) | Infraestructura como código | Proposed |
| [009](../adr/ADR-009-observability.md) | Observabilidad | Proposed |
| [010](../adr/ADR-010-reverse-proxy.md) | Proxy inverso y entrada | Proposed |
| [011](../adr/ADR-011-deployment-topology.md) | Topología de despliegue | Accepted |
| [012](../adr/ADR-012-orm-odm.md) | Selección de ORM y ODM | Accepted |
| [013](../adr/ADR-013-canonical-product-contract.md) | Contrato canónico de Producto y compatibilidad | Proposed |
| [014](../adr/ADR-014-privacy-data-governance.md) | Gobierno de privacidad y tratamiento de datos | Proposed |
| [015](../adr/ADR-015-catalog-atomicity-audit-outbox.md) | Atomicidad de Producto, auditoría y outbox | Accepted |
| [016](../adr/ADR-016-product-asset-storage.md) | Almacenamiento y ownership de recursos visuales de Producto | Accepted |
| [017](../adr/ADR-017-catalog-events-sqs.md) | Entrega de eventos de Producto mediante SQS | Accepted |
| [018](../adr/ADR-018-catalog-lifecycle-events-transport.md) | Transporte de eventos de ciclo de vida de Producto | Accepted |
| [019](../adr/ADR-019-sprint-2-bounded-contexts.md) | Contextos acotados de Sprint 2: Combat, Missions, Auction y Wallet | Accepted |
| [020](../adr/ADR-020-realtime-combat.md) | Tiempo real para Jugar Online | Accepted |
| [021](../adr/ADR-021-combat-randomness-and-effect-table.md) | Aleatoriedad de Combat y mapeo uniforme a la tabla de efectos | Accepted |
