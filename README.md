# Nexus-Battle-Infrastructure

**Fuente de verdad técnica** de Nexus Battles VI: arquitectura, decisiones, diagramas, contratos, costes y gobierno.

Este repositorio no contiene código ejecutable ni es un servicio. El gobierno del producto —Issues, Product Backlog, Sprints y métricas Scrum— vive en [Nexus-Battle-Management](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management).

- **Custodia:** Scrum Masters y Product Owners. **No tiene Team de desarrollo propietario y no se inventa uno.**

## El principio que gobierna esta documentación

**Lo que aquí se describe como implementado, lo está.** Lo que no, se declara como pendiente, con su motivo y su condición de desbloqueo.

Un documento de arquitectura que presenta intenciones como hechos es peor que no tenerlo: induce decisiones basadas en un sistema que no existe.

## Índice

### Arquitectura

| Documento | Contenido |
| --- | --- |
| [SAD.md](docs/architecture/SAD.md) | Documento de arquitectura de software. **Empezar aquí** |
| [system-context.md](docs/architecture/system-context.md) | Actores, sistemas externos y frontera |
| [microservices.md](docs/architecture/microservices.md) | Deployables, superficie y estructura interna |
| [data-ownership.md](docs/architecture/data-ownership.md) | Qué posee cada servicio y cómo se cruza la frontera |
| [integration.md](docs/architecture/integration.md) | Comunicación entre contextos |
| [security.md](docs/architecture/security.md) | Seguridad, identidad y RBAC desplegados |
| [hu-39-role-management.md](docs/architecture/hu-39-role-management.md) | Diseño, matriz RBAC y contratos conceptuales de HU-39 |
| [observability.md](docs/architecture/observability.md) | Registro, sondas y qué no se mide todavía |
| [testing.md](docs/architecture/testing.md) | Estrategia de pruebas y cobertura real |
| [developer-workflow.md](docs/architecture/developer-workflow.md) | Flujo de trabajo, CI y OIDC futuro |
| [branching-and-release.md](docs/architecture/branching-and-release.md) | Ramas, integración y publicación |
| [cost-constraints.md](docs/architecture/cost-constraints.md) | El techo de coste y su efecto en el diseño |
| [sprint-demo-deployment.md](docs/architecture/sprint-demo-deployment.md) | Despliegue de demo — **no provisionado** |
| [target-scale-deployment.md](docs/architecture/target-scale-deployment.md) | Arquitectura objetivo — **no implementada** |

### Decisiones

| ADR | Decisión | Estado |
| --- | --- | --- |
| [001](docs/adr/ADR-001-repository-strategy.md) | Estrategia de repositorios | Proposed |
| [002](docs/adr/ADR-002-backend-stack.md) | Stack de backend | Proposed |
| [003](docs/adr/ADR-003-frontend-stack.md) | Stack de frontend y TypeScript 7 | Proposed |
| [004](docs/adr/ADR-004-identity-directory.md) | Identidad y directorio | Proposed — **BLOCKER** |
| [005](docs/adr/ADR-005-data-strategy.md) | Estrategia de datos | Proposed |
| [006](docs/adr/ADR-006-messaging.md) | Mensajería e integración | Proposed |
| [007](docs/adr/ADR-007-aws-cost-optimized-platform.md) | Plataforma AWS por coste | Proposed |
| [008](docs/adr/ADR-008-iac.md) | Infraestructura como código | Proposed |
| [009](docs/adr/ADR-009-observability.md) | Observabilidad | Proposed |
| [010](docs/adr/ADR-010-reverse-proxy.md) | Proxy inverso y entrada | Proposed |
| [011](docs/adr/ADR-011-deployment-topology.md) | Topología de despliegue | Accepted |
| [012](docs/adr/ADR-012-orm-odm.md) | Selección de ORM y ODM | Accepted |
| [013](docs/adr/ADR-013-canonical-product-contract.md) | Contrato canónico de Producto y compatibilidad | Accepted |
| [014](docs/adr/ADR-014-privacy-data-governance.md) | Gobierno de privacidad y tratamiento de datos | Proposed |
| [015](docs/adr/ADR-015-catalog-atomicity-audit-outbox.md) | Atomicidad de Producto, auditoría y outbox | Accepted |
| [017](docs/adr/ADR-017-catalog-events-sqs.md) | Entrega de eventos de Producto mediante SQS | Proposed |

El estado vigente se declara dentro de cada ADR. Una decisión solo pasa a
`Accepted` con evidencia de aprobación registrada.

### Diagramas

Los diagramas PlantUML están en [docs/diagrams](docs/diagrams), incluidos los cuatro
editables de HU-39, el contrato canónico de Producto, la decisión de atomicidad
de auditoría/outbox y el flujo propuesto de `catalog.product.created` por SQS. Los de despliegue
**separan visualmente demo y objetivo** para que no se confundan; el de Producto
distingue explícitamente lo implementado, lo propuesto y lo bloqueado.

### Costes y contratos

| Documento | Contenido |
| --- | --- |
| [assumptions.md](docs/costs/assumptions.md) | Supuestos de la estimación. **Leer antes que las cifras** |
| [sprint-demo-estimate.md](docs/costs/sprint-demo-estimate.md) | Estimación y requisitos previos al despliegue |
| [catalog-events-sqs-estimate.md](docs/costs/catalog-events-sqs-estimate.md) | Estimación propuesta de eventos de Producto en SQS |
| [service-catalog.md](docs/contracts/service-catalog.md) | Superficie HTTP de cada servicio |
| [catalog-product-v1.openapi.yaml](docs/contracts/catalog-product-v1.openapi.yaml) | Contrato canónico de Producto |
| [catalog-events-v1.asyncapi.yaml](docs/contracts/catalog-events-v1.asyncapi.yaml) | AsyncAPI propuesto de `catalog.product.created` V1 |
| [event-catalog.md](docs/contracts/event-catalog.md) | Eventos de dominio y mensajes |

### Gobierno

| Documento | Contenido |
| --- | --- |
| [rulesets](docs/governance/rulesets/) | Plantilla de `main-protection` y checks reales por repositorio |
| [compose](compose/) | Composición de referencia del sistema completo |
| [privacy](docs/privacy/) | Gobierno de privacidad y tratamiento de datos (EN-011): política v0.3, matriz de tratamiento, contrato de portabilidad, consentimiento y diseño de alto nivel de HU-43/HU-45. **Documental — sin implementación runtime todavía** |

## Estado del sistema — resumen

| Aspecto | Estado |
| --- | --- |
| Repositorios con CI verde | 8 de 8 |
| Pruebas y cobertura | Se registran por entrega y repositorio; HU-39 enlaza sus ejecuciones en [evidencia](docs/evidence/HU-39-asignacion-de-roles.md) |
| Control de acceso | **Activo**: Cognito, JWT y RBAC; ver [ADR-004](docs/adr/ADR-004-identity-directory.md) |
| Persistencia real | **Activa**: PostgreSQL y MongoDB; ver [ADR-005](docs/adr/ADR-005-data-strategy.md) |
| Comunicación entre servicios | **Ausente** — ver [ADR-006](docs/adr/ADR-006-messaging.md) |
| Infraestructura AWS | **Provisionada** con Terraform para la demo |

## Limitaciones del estado actual

Se enumeran juntas porque quien lea esta documentación necesita conocerlas antes de tomar cualquier decisión sobre el sistema:

1. **Sin comunicación entre servicios.** Los puertos existen; el transporte no. Account solo tiene `LoggingNotificationRequester`, que escribe en el registro.
2. **Sin saga de checkout.** Confirmar un pedido no reserva inventario.
3. **Cinco de las seis pantallas de Web** son marcadores declarados. Catalog es la única real.
4. **La arquitectura de demo no cumple los RNF** y tiene un punto único de fallo.
5. **Sin licencia asignada.**
6. **Ventana de testimonios retirados.** El cierre global revoca las sesiones de
   Cognito, pero un access token ya emitido puede conservar sus claims hasta
   `exp`, como máximo 15 minutos.
7. **Aceptación humana de HU-39 en curso.** El despliegue, la automatización y
   el único rol raíz están comprobados; falta completar y registrar el ciclo
   real de asignación, acceso y retirada.

### Proceso normal de TOTP y gestión de roles

La persona inscribe TOTP desde **Mi Cuenta → Seguridad** mientras conserva
`PLAYER`. Después, el Super Administrador la busca y gestiona su rol desde
`/admin/roles`. La interfaz deshabilita la elevación a `ADMINISTRATOR` hasta que
el factor esté confirmado y Account aplica la misma precondición con un 409.

La operación ordinaria no exige ejecutar un guion: Web invoca Account, que
actualiza PostgreSQL y refleja los grupos en Cognito. Los guiones conservados
son controles de auditoría o aceptación, no puertas laterales para asignar
roles. La elevación a `ADMINISTRATOR` ocurre únicamente después de que TOTP
aparezca confirmado, así no existe una ventana administrativa con sola
contraseña.

### Tres limitaciones que esta lista declaraba y ya no son ciertas

Se dejan escritas en lugar de borrarlas, porque quien haya leído una versión
anterior de este README necesita saber qué cambió:

- ~~**Sin control de acceso.** Ningún servicio verifica quién realiza la petición.~~
  **Superado el 2026-08-29.** Los cinco servicios verifican el testimonio contra el
  JWKS del pool (`AUTH_MODE=jwt`), comprobado de extremo a extremo: las rutas
  protegidas responden 401 sin testimonio y 200 con él. El rol viaja dentro del
  testimonio. Ver [ADR-004](docs/adr/ADR-004-identity-directory.md).
- ~~**Sin persistencia real.** El estado se pierde al reiniciar.~~ **Superado.** Los
  cinco servicios declaran PostgreSQL o MongoDB, con migraciones propias.
  Comprobado con el caso que de verdad lo demuestra: una cuenta creada días antes
  sigue ahí **después de reemplazar por completo el nodo de aplicación**.
- ~~**No hay infraestructura AWS provisionada.**~~ **Superado.** 43 recursos con
  Terraform y estado remoto en S3. Ver [ADR-011](docs/adr/ADR-011-deployment-topology.md).

Ninguna es un descuido. Cada una tiene su motivo registrado y su condición de desbloqueo.

## Ejecución local del sistema completo

```bash
cd compose
cp compose.example.yml compose.yml
# revisar y sustituir las credenciales de ejemplo
docker compose up -d
```

Detalle en [compose/README.md](compose/README.md).

## Contribución

Se aplican las convenciones descritas en [CONTRIBUTING.md](CONTRIBUTING.md) y la [política de trazabilidad entre repositorios](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/blob/main/docs/governance/cross-repository-traceability.md) de Management.

## Licencia

`Licensing pending project governance`. Este repositorio todavía no tiene una licencia asignada; su definición requiere autorización del gobierno del proyecto.
