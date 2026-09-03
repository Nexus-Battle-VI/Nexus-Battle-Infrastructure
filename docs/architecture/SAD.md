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
| Player / Inventory | Qué posee un jugador y en qué cantidad | Alfa | `Nexus-Battle-Player-Inventory` |
| Catalog | Qué productos existen y a qué precio | Gama | `Nexus-Battle-Catalog` |
| Community | Hilos, mensajes y moderación | Gama | `Nexus-Battle-Community` |
| Commerce | Pedidos, líneas y totales | Beta | `Nexus-Battle-Commerce` |
| Notifications | Entrega de correo transaccional | Alfa | `Nexus-Battle-Notifications` |

Más dos repositorios que no son bounded contexts: `Nexus-Battle-Web` (interfaz de los seis) y `Nexus-Battle-Infrastructure` (este repositorio).

Detalle en [microservices.md](microservices.md) y [data-ownership.md](data-ownership.md).

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
| [017](../adr/ADR-017-catalog-events-sqs.md) | Entrega de eventos de Producto mediante SQS | Proposed |
