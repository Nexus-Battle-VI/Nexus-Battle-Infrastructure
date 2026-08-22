# Despliegue — Sprint y demo

Diagrama en [sprint-demo-aws-deployment.puml](../diagrams/sprint-demo-aws-deployment.puml). Decisión en [ADR-007](../adr/ADR-007-aws-cost-optimized-platform.md).

> **Esta arquitectura NO ha sido provisionada.** No existe cuenta de AWS configurada, no se ha ejecutado ninguna herramienta de infraestructura y no hay coste incurrido. Lo que sigue es el diseño propuesto.

> **Esta arquitectura NO cumple los requisitos no funcionales del producto.** Ver [target-scale-deployment.md](target-scale-deployment.md) para la que sí lo haría.

## Topología

```text
                        Internet
                            |
                          HTTPS (443)
                            |
        +-------------------v--------------------------------+
        |  EC2 pequena, subred publica, IP elastica          |
        |                                                    |
        |  +----------------------------------------------+  |
        |  |  Caddy  — proxy inverso, TLS, estaticos      |  |
        |  +---+------------------------------------------+  |
        |      |                                             |
        |      +-- /                -> Web (estaticos)       |
        |      +-- /api/accounts    -> Account      :3000    |
        |      +-- /api/inventories -> Inventory    :3002    |
        |      +-- /api/products    -> Catalog      :3003    |
        |      +-- /api/threads     -> Community    :3004    |
        |      +-- /api/orders      -> Commerce     :3005    |
        |                                                    |
        |  Notifications worker  (sin puerto publico)        |
        |                                                    |
        |  PostgreSQL container ---+                         |
        |  MongoDB container    ---+--> volumenes Docker     |
        |                              sobre EBS             |
        +----------------------------------------------------+
```

Todo corre en **una sola instancia**. Es la consecuencia directa del techo de coste.

## Componentes y su justificación

| Componente | Elección | Por qué |
| --- | --- | --- |
| Cómputo | Una EC2 pequeña | Único recurso de coste fijo aceptado |
| Entrada | Caddy en la propia instancia | TLS automático, coste cero. ALB tendría coste fijo por hora |
| Estáticos | Servidos por el mismo Caddy | S3 + CloudFront añadiría transferencia sin beneficio a este volumen |
| Imágenes | **GHCR**, no ECR | Incluido en el plan de la organización; ECR cobra almacenamiento y transferencia |
| Bases de datos | Contenedores sobre volúmenes EBS | RDS y DocumentDB tienen coste fijo que consume el techo |
| Mensajería | SQS, **candidato no adoptado** | *Usage-based*. Ver [ADR-006](../adr/ADR-006-messaging.md) |
| API Gateway | **Propuesto, no adoptado** | Duplicaría el proxy inverso. Ver [ADR-010](../adr/ADR-010-reverse-proxy.md) |
| Correo | Mailpit en local, SES futuro | SES requiere aprobación y verificación de dominio |

## Servicios AWS excluidos

Lambda, DynamoDB, S3 (salvo estado de Terraform), CloudFront, ECS, Fargate, EKS, ALB, NLB, NAT Gateway, RDS, DocumentDB, ElastiCache y Managed Microsoft AD.

El motivo de cada exclusión está en [ADR-007](../adr/ADR-007-aws-cost-optimized-platform.md).

## Limitaciones — leer antes de presentar esta arquitectura

| Limitación | Consecuencia real |
| --- | --- |
| **Una sola EC2** | Punto único de fallo total. Si cae la instancia, cae el producto entero |
| **Sin autoescalado** | La capacidad es la de una instancia pequeña. No se acerca a 100 000 concurrentes |
| **Sin multi-AZ** | Un fallo de zona deja el sistema fuera |
| **Bases de datos en contenedor** | Sin réplica, sin conmutación por error, sin copias gestionadas |
| **Sin recuperación ante desastres** | Perder el volumen EBS es perder los datos |
| **Disponibilidad real** | Muy por debajo del 99,95 % objetivo |
| **Sin control de acceso** | Ver [ADR-004](../adr/ADR-004-identity-directory.md) |

**El último punto es el que impide desplegar.** Sin proveedor de identidad, ningún servicio verifica quién realiza la petición: cualquiera podría confirmar pedidos, ocultar mensajes o cambiar precios.

**Este sistema no debe exponerse a internet en su estado actual.**

## Ejecución local equivalente

`compose/compose.example.yml` reproduce la topología en una máquina de desarrollo, incluidos PostgreSQL, MongoDB y Mailpit. Sirve para validar la integración del sistema completo sin AWS.

## Antes de provisionar

Ninguna provisión ocurre sin completar esta lista:

- [ ] Cuenta de AWS designada y con responsable
- [ ] **Presupuesto en AWS Budgets** con el techo mensual
- [ ] **Alertas de coste** al 50 %, 80 % y 100 %
- [ ] Estimación revisada contra la calculadora oficial
- [ ] Lista cerrada de servicios a provisionar
- [ ] Supuesto de tráfico documentado
- [ ] **Política de apagado** para el periodo sin demo
- [ ] Etiquetado de recursos para imputación de coste
- [ ] **BLOCKER de identidad resuelto** si el entorno va a ser accesible

Detalle en [../costs/assumptions.md](../costs/assumptions.md) y [../costs/sprint-demo-estimate.md](../costs/sprint-demo-estimate.md).
