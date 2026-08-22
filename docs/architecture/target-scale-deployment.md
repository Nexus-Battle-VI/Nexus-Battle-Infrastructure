# Despliegue — Arquitectura objetivo

Diagrama en [target-scale-aws-deployment.puml](../diagrams/target-scale-aws-deployment.puml).

> **Esta arquitectura NO está implementada, NO está provisionada y NO debe presentarse como existente.**
>
> Es la evolución documentada para cumplir los requisitos no funcionales del producto. Su coste está muy por encima del techo del Sprint.

## Requisitos que debe cumplir

| Requisito | Valor objetivo |
| --- | --- |
| Concurrencia | 100 000 usuarios simultáneos |
| Disponibilidad | 99,95 % |
| Escalado | Automático según demanda |
| Alta disponibilidad | Multi-AZ |
| Persistencia | Gestionada, con réplica y conmutación por error |
| Recuperación ante desastres | Con RPO y RTO definidos |

## Topología propuesta

```text
                          Internet
                              |
                      Route 53 + WAF
                              |
                        CloudFront
                              |
              +---------------+---------------+
              |                               |
       S3 (estaticos Web)          ALB (multi-AZ)
                                              |
                            +-----------------+-----------------+
                            |                                   |
                     ECS Fargate  (AZ-a)              ECS Fargate  (AZ-b)
                     servicios con autoescalado       replicas
                            |                                   |
              +-------------+-----------+---------------+-------+
              |             |           |               |
        RDS PostgreSQL  DocumentDB  ElastiCache        SQS
        Multi-AZ        replica set  Redis             + DLQ
        + replicas                                      |
        de lectura                                      v
                                                  Notifications
                                                  (workers escalables)
```

## Diferencias con la demo

| Aspecto | Demo | Objetivo |
| --- | --- | --- |
| Cómputo | 1 EC2 | ECS Fargate con autoescalado, multi-AZ |
| Entrada | Caddy en la instancia | Route 53 + CloudFront + WAF + ALB |
| Estáticos | Caddy | S3 + CloudFront |
| PostgreSQL | Contenedor | RDS Multi-AZ con réplicas de lectura |
| MongoDB | Contenedor | DocumentDB con réplicas |
| Caché | Ninguna | ElastiCache Redis |
| Mensajería | En memoria | SQS con DLQ |
| Imágenes | GHCR | ECR con escaneo de vulnerabilidades |
| Secretos | Variables de entorno | Secrets Manager o Parameter Store |
| Observabilidad | Logs por contenedor | CloudWatch + trazas OpenTelemetry |
| Punto único de fallo | **Sí** | No |
| Coste mensual | < USD 100 | Muy superior |

## Qué del trabajo actual sobrevive a la migración

Esta es la pregunta que hace útil la arquitectura hexagonal, y la respuesta es concreta:

| Elemento | ¿Sobrevive? |
| --- | --- |
| Dominio de los seis servicios | **Sí, sin cambios** |
| Casos de uso | **Sí, sin cambios** |
| Puertos | **Sí, sin cambios** |
| Contratos HTTP y OpenAPI | **Sí** |
| Adaptadores de persistencia | Se sustituyen: en memoria → RDS/DocumentDB |
| Adaptador de cola | Se sustituye: en memoria → SQS |
| Adaptador de identidad | Se sustituye: simulado → OIDC |
| Dockerfiles | Sirven; cambia dónde se ejecutan |
| Frontend | **Sin cambios**: habla con `/api` y no conoce la topología |

Los adaptadores son **un archivo por servicio**. Que la migración toque solo esos archivos es el resultado directo de haber mantenido el dominio libre de infraestructura, y esa restricción se verifica hoy en CI.

## Lo que la migración sí exige

No es un cambio de configuración. Requiere:

1. **ADR de ORM/ODM** y, con él, esquema, migraciones e índices ([ADR-005](../adr/ADR-005-data-strategy.md)).
2. **ADR de mensajería resuelto** y adaptador SQS ([ADR-006](../adr/ADR-006-messaging.md)).
3. **Proveedor de identidad aprobado** y adaptador OIDC ([ADR-004](../adr/ADR-004-identity-directory.md)).
4. **Saga de checkout** implementada, con compensaciones.
5. **Infraestructura como código** ([ADR-008](../adr/ADR-008-iac.md)).
6. **Observabilidad distribuida**: trazas, métricas y alertas por SLO ([ADR-009](../adr/ADR-009-observability.md)).
7. **Pruebas de carga** que validen los supuestos de concurrencia.
8. **Aprobación de presupuesto** para un coste de otro orden de magnitud.

## Sobre los 100 000 concurrentes

La cifra es un requisito declarado, no un resultado medido. Antes de dimensionar hay que responder:

- ¿Cuántas peticiones por segundo genera un usuario concurrente?
- ¿Qué proporción es lectura y cuál escritura?
- ¿Cuál es el tiempo de respuesta aceptable en el percentil 95?
- ¿Qué picos se esperan y con qué duración?

Sin esas respuestas, cualquier dimensionamiento sería una cifra inventada. **Las pruebas de carga son un prerrequisito del diseño de capacidad, no una validación posterior.**

## Estado

**Ningún elemento de esta arquitectura existe.** Este documento sirve para dos cosas: mostrar la evolución prevista y dejar constancia de qué separa la demo del objetivo, para que nadie confunda una con otra.
