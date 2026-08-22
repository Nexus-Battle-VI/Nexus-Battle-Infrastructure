# Restricciones de coste

Ver [ADR-007](../adr/ADR-007-aws-cost-optimized-platform.md) y [../costs/sprint-demo-estimate.md](../costs/sprint-demo-estimate.md).

## El techo

**USD 100 al mes** para el Sprint y la demo. Se busca quedar **muy por debajo**.

Este número no es una guía: es la restricción que más forma da a la arquitectura. Explica por qué no hay RDS, ni balanceador, ni NAT Gateway, ni orquestador de contenedores gestionado.

## El conflicto que hay que nombrar

| Requisito no funcional | Lo que exige | Coste |
| --- | --- | --- |
| 100 000 concurrentes | Autoescalado multi-AZ | Muy superior al techo |
| 99,95 % disponibilidad | Redundancia en cada capa | Muy superior al techo |
| Persistencia gestionada | RDS Multi-AZ, DocumentDB | Solo RDS ya excede el techo |

**Los requisitos no funcionales y el techo de coste no caben en la misma arquitectura.** Por eso se documentan dos: [demo](sprint-demo-deployment.md) y [objetivo](target-scale-deployment.md).

Presentar la demo como si cumpliera los RNF sería el error más grave que este proyecto podría cometer en su documentación.

## Criterio de admisión de un servicio AWS

```text
¿Tiene coste fijo mensual significativo?
    SI  -> excluido del baseline
    NO  -> ¿es usage-based?
              SI  -> admisible, con supuesto de trafico documentado
              NO  -> excluido
```

### Excluidos por coste fijo

| Servicio | Naturaleza del coste |
| --- | --- |
| RDS, DocumentDB | Por hora de instancia, aunque no haya tráfico |
| ElastiCache | Por hora de nodo |
| ALB, NLB | Por hora, más unidades de capacidad |
| NAT Gateway | Por hora, más transferencia |
| ECS Fargate, EKS | Por tarea o por clúster |
| Managed Microsoft AD | Por hora de directorio |

### Admisibles por ser usage-based

| Servicio | Estado |
| --- | --- |
| **SQS** | Candidato. Sin tráfico, sin coste |
| **API Gateway HTTP API** | Admisible por coste, pero **no adoptado**: duplicaría el proxy inverso |
| **CloudWatch Logs** | Admisible con retención acotada |

Que un servicio sea admisible por coste **no significa que se adopte**. API Gateway lo demuestra: entra en el presupuesto y aun así se descarta, porque no aporta valor sobre lo que Caddy ya hace.

## Decisiones que ahorran coste

| Decisión | Alternativa descartada | Ahorro |
| --- | --- | --- |
| Caddy en la instancia | ALB | Todo el coste fijo del balanceador |
| Estáticos servidos por Caddy | S3 + CloudFront | Almacenamiento y transferencia |
| **GHCR** para imágenes | ECR | Almacenamiento y transferencia |
| Bases de datos en contenedor | RDS + DocumentDB | La partida más grande, con diferencia |
| Subred pública con IP elástica | NAT Gateway | Todo el coste fijo del NAT |
| Sin CI hacia AWS | Despliegue continuo | Transferencia y cómputo de despliegue |

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

El presupuesto y las alertas se crean **antes** que cualquier recurso de cómputo. Un despliegue sin alerta de coste es un riesgo de presupuesto sin control.

## Política de apagado

La demo **no necesita estar encendida de forma continua**. Detener la instancia fuera de los periodos de demostración reduce el coste de cómputo de forma proporcional al tiempo apagado, que es la palanca de ahorro más simple y efectiva disponible.

El volumen EBS sigue costando mientras exista, aunque la instancia esté detenida.

## Lo que no se puede afirmar

**No se dice «gratis para siempre».**

La capa gratuita de AWS tiene límites temporales y de volumen. Superarlos genera coste sin aviso previo, y precisamente por eso las alertas de presupuesto son un requisito previo al despliegue, no una mejora posterior.

## Estado actual

**Coste incurrido en AWS: USD 0.**

No hay cuenta configurada, no se ha provisionado ningún recurso y CI no requiere credenciales de AWS para ninguna de sus etapas.
