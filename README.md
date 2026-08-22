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
| [security.md](docs/architecture/security.md) | Seguridad y el blocker de identidad |
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

**Todos están en `Proposed`.** Ninguna decisión pasa a `Accepted` sin evidencia de aprobación registrada.

### Diagramas

Siete diagramas PlantUML en [docs/diagrams](docs/diagrams). Los de despliegue **separan visualmente demo y objetivo** para que no se confundan.

### Costes y contratos

| Documento | Contenido |
| --- | --- |
| [assumptions.md](docs/costs/assumptions.md) | Supuestos de la estimación. **Leer antes que las cifras** |
| [sprint-demo-estimate.md](docs/costs/sprint-demo-estimate.md) | Estimación y requisitos previos al despliegue |
| [service-catalog.md](docs/contracts/service-catalog.md) | Superficie HTTP de cada servicio |
| [event-catalog.md](docs/contracts/event-catalog.md) | Eventos de dominio y mensajes |

### Gobierno

| Documento | Contenido |
| --- | --- |
| [rulesets](docs/governance/rulesets/) | Plantilla de `main-protection` y checks reales por repositorio |
| [compose](compose/) | Composición de referencia del sistema completo |

## Estado del sistema — resumen

| Aspecto | Estado |
| --- | --- |
| Repositorios con CI verde | 8 de 8 |
| Pruebas totales | 602 |
| Cobertura mínima exigida | 80 %, superada en todos |
| Control de acceso | **Ausente** — ver [ADR-004](docs/adr/ADR-004-identity-directory.md) |
| Persistencia real | **Ausente** — ver [ADR-005](docs/adr/ADR-005-data-strategy.md) |
| Comunicación entre servicios | **Ausente** — ver [ADR-006](docs/adr/ADR-006-messaging.md) |
| Infraestructura AWS | **No provisionada** — coste incurrido: USD 0 |

## Limitaciones del estado actual

Se enumeran juntas porque quien lea esta documentación necesita conocerlas antes de tomar cualquier decisión sobre el sistema:

1. **Sin control de acceso.** Ningún servicio verifica quién realiza la petición. **No debe desplegarse en un entorno accesible desde internet.**
2. **Sin persistencia real.** El estado se pierde al reiniciar.
3. **Sin comunicación entre servicios.** Los puertos existen; el transporte no.
4. **Sin saga de checkout.** Confirmar un pedido no reserva inventario.
5. **Cinco de las seis pantallas de Web** son marcadores declarados.
6. **La arquitectura de demo no cumple los RNF** y tiene un punto único de fallo.
7. **No hay infraestructura AWS provisionada.**
8. **Sin licencia asignada.**

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
