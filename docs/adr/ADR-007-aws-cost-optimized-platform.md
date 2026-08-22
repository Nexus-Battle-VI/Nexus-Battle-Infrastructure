# ADR-007 — Plataforma AWS optimizada por coste para Sprint y demo

- **Estado:** Proposed — **no se ha provisionado nada**
- **Fecha:** 2026-08-21
- **Decide:** Arquitectura, con aprobación obligatoria de presupuesto
- **Relacionado:** [ADR-004](ADR-004-identity-directory.md), [ADR-005](ADR-005-data-strategy.md), [ADR-006](ADR-006-messaging.md), [ADR-010](ADR-010-reverse-proxy.md)

## Contexto

El Sprint y la demo tienen un techo de **USD 100 al mes**. Los requisitos no funcionales del producto objetivo hablan de 100 000 usuarios concurrentes, 99,95 % de disponibilidad, autoescalado y alta disponibilidad multi-AZ.

**Esas dos cosas no caben en la misma arquitectura**, y este ADR existe precisamente para no fingir que sí.

## Decisión

Se documentan **dos arquitecturas distintas y explícitamente separadas**:

- **Demo** — la que cabe en USD 100/mes. Descrita aquí y en [sprint-demo-deployment.md](../architecture/sprint-demo-deployment.md).
- **Objetivo** — la que cumple los RNF. Descrita en [target-scale-deployment.md](../architecture/target-scale-deployment.md).

**En esta ejecución no se ha provisionado ningún recurso de AWS.** No existe cuenta configurada, no se ha ejecutado IaC y no hay coste incurrido.

### Arquitectura de demo

```text
Internet
  |
  v  HTTPS
[ EC2 pequena, una sola instancia ]
  |
  +-- Caddy (proxy inverso + TLS + estaticos)
  |     |
  |     +-- Web (estaticos servidos por el propio Caddy)
  |     +-- /api/accounts    -> Account container      :3000
  |     +-- /api/inventories -> Player/Inventory       :3002
  |     +-- /api/products    -> Catalog                :3003
  |     +-- /api/threads     -> Community              :3004
  |     +-- /api/orders      -> Commerce               :3005
  |
  +-- Notifications worker (sin puerto publico)
  +-- PostgreSQL container   -> volumen Docker sobre EBS
  +-- MongoDB container      -> volumen Docker sobre EBS
```

### Servicios excluidos y por qué

| Servicio | Motivo de exclusión |
| --- | --- |
| RDS, DocumentDB | Coste fijo mensual que por sí solo consume el techo |
| ElastiCache | Coste fijo; no hay problema de latencia que resolver con el volumen de la demo |
| DynamoDB | Modelo de datos no encaja con los agregados definidos |
| Lambda | El worker de Notifications es de larga duración; Lambda invertiría el modelo de ejecución |
| ECS, Fargate, EKS | Coste y complejidad operativa desproporcionados para seis contenedores en una máquina |
| ALB, NLB | Coste fijo por hora. Caddy en la propia instancia cumple el papel a coste cero |
| NAT Gateway | Coste fijo elevado. La instancia va en subred pública con IP elástica |
| S3, CloudFront | Los estáticos los sirve el propio Caddy. Añadir S3 supondría coste de transferencia sin beneficio a este volumen |
| Managed Microsoft AD | Ver [ADR-004](ADR-004-identity-directory.md) |

### Servicios que sí pueden evaluarse

| Servicio | Por qué es admisible |
| --- | --- |
| **SQS** | *Usage-based*: sin tráfico, sin coste. Ver [ADR-006](ADR-006-messaging.md) |
| **API Gateway HTTP API** | *Usage-based*, pero **queda en `Proposed` sin adoptar**: duplicaría la función del proxy inverso sin aportar valor a este volumen. Ver [ADR-010](ADR-010-reverse-proxy.md) |
| **GHCR** en lugar de ECR | Las imágenes se publican en GitHub Container Registry, incluido en el plan de la organización |

### Imágenes: GHCR, no ECR

ECR cobra almacenamiento y transferencia. GHCR está incluido y las imágenes ya se construyen en GitHub Actions. No se introduce ECR mientras GHCR cubra la necesidad.

## Limitaciones de la arquitectura de demo

**Deben declararse porque son severas:**

| Limitación | Consecuencia |
| --- | --- |
| **Una sola EC2** | Es un punto único de fallo total. Si la instancia cae, cae el producto entero |
| **Sin autoescalado** | La capacidad es la de una instancia pequeña. No soporta 100 000 concurrentes ni se acerca |
| **Sin multi-AZ** | Un fallo de zona de disponibilidad deja el sistema fuera |
| **Bases de datos en contenedor** | Sin réplica, sin conmutación por error y sin copias de seguridad gestionadas |
| **Sin recuperación ante desastres** | Perder el volumen EBS es perder los datos |
| **Disponibilidad real** | Muy por debajo del 99,95 % objetivo |

**La arquitectura de demo NO cumple los requisitos no funcionales del producto y no debe presentarse como si lo hiciera.** Cumple un objetivo distinto: demostrar el sistema funcionando dentro de un presupuesto acotado.

## Antes de desplegar

Ninguna provisión ocurre sin completar esta lista:

- [ ] Cuenta de AWS designada y con responsable
- [ ] **Presupuesto de AWS Budgets creado** con el techo mensual
- [ ] **Alertas de coste** al 50 %, 80 % y 100 % del techo
- [ ] Estimación revisada contra la calculadora oficial
- [ ] Lista cerrada de servicios a provisionar
- [ ] Supuesto de tráfico documentado
- [ ] **Política de apagado** para el periodo sin demo
- [ ] Etiquetado de recursos para imputación de coste

La estimación y los supuestos están en [docs/costs](../costs/assumptions.md).

## Consecuencias

**Lo que se gana**

- Un objetivo de coste alcanzable y verificable.
- Ninguna dependencia de AWS en CI: las pruebas y la compilación corren sin credenciales.
- La separación entre demo y objetivo impide que la primera se presente como la segunda.

**Lo que cuesta**

- La demo tiene un punto único de fallo y ninguna garantía de disponibilidad.
- Migrar a la arquitectura objetivo no es un cambio de configuración: implica persistencia gestionada, balanceo y orquestación.

## Alternativas consideradas

| Alternativa | Coste estimado | Por qué se descartó |
| --- | --- | --- |
| ECS Fargate + ALB + RDS | Muy por encima de USD 100 | Solo ALB y RDS ya superan el techo |
| Lambda + API Gateway + DynamoDB | Podría entrar en el techo | Obligaría a rehacer el modelo de datos y a convertir el worker en función; contradice ADR-005 |
| Todo en contenedores sobre EC2 | Dentro del techo | **Seleccionada** |
| Alojamiento fuera de AWS | Menor | El requisito académico fija AWS como destino |

## Pendiente de aprobación

Este ADR permanece en `Proposed` hasta que exista **aprobación de presupuesto** y cuenta de AWS designada. Hasta entonces no se provisiona ningún recurso.
