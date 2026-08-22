# Estimación de coste — Sprint y demo

> **Estimación, no factura.** No hay recursos provisionados. Los supuestos que la sostienen están en [assumptions.md](assumptions.md) y **deben leerse antes que las cifras**.

## Estado actual

**Coste incurrido: USD 0.**

No existe cuenta de AWS configurada, no se ha ejecutado ninguna herramienta de infraestructura y CI no requiere credenciales de AWS en ninguna etapa.

## Techo

**USD 100 al mes.** El objetivo es quedar muy por debajo.

## Partidas previstas

| Partida | Naturaleza | Comentario |
| --- | --- | --- |
| **EC2 pequeña** | Coste fijo por hora encendida | Partida dominante. Es donde actúa la política de apagado |
| **EBS** | Coste fijo por GB aprovisionado | Se paga aunque la instancia esté detenida |
| **IP elástica** | Sin coste mientras esté asociada a una instancia en marcha | **Se factura si queda sin asociar**. Detener la instancia expone a este cargo |
| **Transferencia de salida** | Usage-based | La partida más sensible al tráfico real |
| **SQS** | Usage-based | Sin tráfico, sin coste. Candidato, no adoptado |
| **CloudWatch Logs** | Usage-based | Solo si se adopta; con retención acotada |
| **S3 (estado de Terraform)** | Usage-based, marginal | Solo cuando [ADR-008](../adr/ADR-008-iac.md) se apruebe |
| **GHCR** | Sin coste | Incluido en el plan de la organización |
| **Certificados TLS** | Sin coste | Let's Encrypt automatizado por Caddy |

**No se publican cifras concretas por partida.** Los precios de AWS varían por región y se revisan periódicamente, y una cifra inventada aquí sería peor que ninguna. La estimación se calculará contra la **calculadora oficial de AWS** en el momento de solicitar la aprobación, y ese resultado se adjuntará a este documento.

Lo que sí se afirma con seguridad es la **estructura del coste**: una partida fija dominante (cómputo), una fija menor (almacenamiento) y el resto proporcional al uso.

## El detalle que suele pasarse por alto

La **IP elástica no cuesta mientras está asociada a una instancia en marcha**, pero **sí se factura si la instancia se detiene** y la dirección queda reservada sin usar.

Esto interactúa directamente con la política de apagado: apagar la instancia ahorra cómputo pero activa el cargo por IP. La decisión correcta depende de cuánto tiempo permanezca apagada, y debe tomarse con las cifras reales delante.

## Servicios excluidos y su impacto

| Servicio excluido | Impacto de incluirlo |
| --- | --- |
| RDS | **Excedería el techo por sí solo** |
| DocumentDB | Excedería el techo por sí solo |
| ElastiCache | Consumiría una parte muy significativa |
| ALB o NLB | Coste fijo por hora, más unidades de capacidad |
| NAT Gateway | Coste fijo elevado, más transferencia |
| ECS Fargate | Por tarea; con siete deployables se multiplica |
| Managed Microsoft AD | Varias veces el techo completo |

El motivo de cada exclusión está en [ADR-007](../adr/ADR-007-aws-cost-optimized-platform.md).

## Decisiones que reducen el coste

| Decisión | Alternativa evitada |
| --- | --- |
| Caddy en la instancia | ALB |
| Estáticos servidos por Caddy | S3 + CloudFront |
| GHCR | ECR |
| Bases de datos en contenedor | RDS + DocumentDB |
| Subred pública con IP elástica | NAT Gateway |
| Sin despliegue desde CI | Transferencia y cómputo de despliegue |
| **Política de apagado** | Instancia encendida de forma continua |

La última es la palanca con mayor efecto proporcional: el coste de cómputo se reduce en proporción directa al tiempo apagado.

## Requisitos previos al despliegue

Ninguna provisión ocurre sin completar esta lista:

- [ ] Cuenta de AWS designada y con responsable
- [ ] **Presupuesto en AWS Budgets** con el techo mensual
- [ ] **Alertas al 50 %, 80 % y 100 %**
- [ ] Estimación calculada en la calculadora oficial y adjuntada aquí
- [ ] Lista cerrada de servicios a provisionar
- [ ] Supuestos de tráfico revisados
- [ ] Política de apagado acordada
- [ ] Etiquetado de recursos para imputación
- [ ] **BLOCKER de identidad resuelto** si el entorno va a ser accesible

El presupuesto y las alertas se crean **antes** que cualquier recurso de cómputo.

## Seguimiento

| Cuándo | Qué |
| --- | --- |
| Antes de provisionar | Estimación contra la calculadora oficial |
| Primer mes | Comparar coste real con estimación y registrar la desviación |
| Cada mes | Revisar contra el techo |
| Ante cualquier servicio nuevo | Revisar [assumptions.md](assumptions.md) antes de provisionarlo |

## Lo que no se afirma

**No se dice «gratis para siempre».** La capa gratuita tiene límites temporales y de volumen, y superarlos genera coste sin aviso. La estimación **no la asume**, precisamente para que su caducidad no invalide el cálculo.
