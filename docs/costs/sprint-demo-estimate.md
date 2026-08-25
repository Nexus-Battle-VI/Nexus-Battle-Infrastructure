# Estimación de coste — Sprint y demo

> **Estimación, no factura.** Los supuestos que la sostienen están en [assumptions.md](assumptions.md) y **deben leerse antes que las cifras**.

## Estado actual

| Concepto | Valor |
| --- | --- |
| Cuenta de AWS | `658430303197`, designada el 2026-08-25 |
| Perfil del CLI | `nexus-battles` |
| Región | `us-east-1` |
| Recursos provisionados | **Ninguno**: 0 EC2, 0 EBS, 0 IP elástica, 0 NAT, 0 SQS, 0 SNS, 0 S3, 0 Cognito |
| Coste del mes en curso | `0.000025 USD`, íntegramente cubierto por créditos |

Solo existe la VPC por defecto de cada región, que AWS crea sola y no tiene coste.

## Techo

**USD 100 al mes**, con el objetivo explícito de **gastar lo mínimo para que el presupuesto aguante todo el proyecto**. El techo es un límite, no un objetivo de gasto.

## Precios reales

Obtenidos de la **AWS Price List API** el **2026-08-25** para `us-east-1`, bajo demanda, Linux, tenencia compartida. No son cifras de memoria ni de la calculadora: son la respuesta del catálogo de precios.

| Recurso | Precio unitario | Mensual a 730 h |
| --- | --- | --- |
| EC2 `t4g.nano` (0,5 GB) | 0,00420 USD/h | 3,07 USD |
| EC2 `t4g.micro` (1 GB) | 0,00840 USD/h | 6,13 USD |
| EC2 **`t4g.small`** (2 GB) | 0,01680 USD/h | 12,26 USD |
| EC2 **`t4g.medium`** (4 GB) | 0,03360 USD/h | 24,53 USD |
| EC2 `t3.micro` (1 GB, x86) | 0,01040 USD/h | 7,59 USD |
| EBS `gp3` | 0,08 USD/GB-mes | 2,40 USD por 30 GB |
| **IPv4 pública en uso** | 0,005 USD/h | **3,65 USD** |
| **IPv4 pública ociosa** | 0,005 USD/h | **3,65 USD** |

Las instancias `t4g` son Graviton (Arm64). Las imágenes del proyecto deben construirse para `linux/arm64` o la instancia no las ejecutará.

## Corrección: la IP pública se cobra siempre

**Versiones anteriores de este documento afirmaban que una IP elástica no cuesta mientras está asociada a una instancia en marcha. Eso es falso desde el 1 de febrero de 2024.**

AWS cobra **toda** dirección IPv4 pública, esté en uso o no, al mismo precio. La Price List API lo confirma: `PublicIPv4:InUseAddress` y `PublicIPv4:IdleAddress` cuestan ambas 0,005 USD/h.

La conclusión que se derivaba de aquel dato erróneo **queda invertida**:

- **Antes se decía:** apagar la instancia ahorra cómputo pero activa el cargo por IP, así que hay que sopesarlo.
- **Lo correcto:** el cargo por IP existe igual encendida que apagada. Apagar la instancia **ahorra sin contrapartida alguna**.

## Coste por régimen de operación

Cálculo determinista sobre los precios de la tabla anterior: `t4g` + 30 GB de `gp3` + una IPv4 pública.

| Instancia | Régimen | Cómputo | Fijos | **Total/mes** | % del techo |
| --- | --- | ---: | ---: | ---: | ---: |
| `t4g.small` | 24/7 encendida | 12,26 | 6,05 | **18,31** | 18,3 % |
| `t4g.small` | Lun-Vie 8 h/día (174 h) | 2,92 | 6,05 | **8,97** | 9,0 % |
| `t4g.small` | Solo demos (~20 h/mes) | 0,34 | 6,05 | **6,39** | 6,4 % |
| `t4g.small` | Apagada todo el mes | 0,00 | 6,05 | **6,05** | 6,1 % |
| `t4g.medium` | 24/7 encendida | 24,53 | 6,05 | **30,58** | 30,6 % |
| `t4g.medium` | Lun-Vie 8 h/día (174 h) | 5,85 | 6,05 | **11,90** | 11,9 % |
| `t4g.medium` | Solo demos (~20 h/mes) | 0,67 | 6,05 | **6,72** | 6,7 % |
| `t4g.medium` | Apagada todo el mes | 0,00 | 6,05 | **6,05** | 6,1 % |

**El dato que decide la política de apagado:** los 6,05 USD/mes de EBS más IPv4 **se pagan aunque la instancia esté apagada todo el mes**. Apagar reduce el cómputo a cero, pero no baja de ese suelo.

Para bajar de 6,05 hay que **liberar la IP y borrar el volumen**, lo que implica reconstruir el entorno en el siguiente despliegue. Es una decisión de operación, no de arquitectura, y depende de cuánto tiempo vaya a estar parado.

## Qué no está incluido en estas cifras

| Concepto | Motivo |
| --- | --- |
| Transferencia de salida | *Usage-based*. Es la partida más sensible al tráfico real |
| Cognito | Pendiente de decisión ([ADR-004](../adr/ADR-004-identity-directory.md)). Se estimará al aprobarse |
| SQS | *Usage-based*; sin tráfico, sin coste. Candidato no adoptado |
| CloudWatch Logs | Solo si se adopta, con retención acotada |
| S3 del estado de Terraform | Céntimos; solo cuando [ADR-008](../adr/ADR-008-iac.md) pase a `Accepted` |
| GHCR | Sin coste: incluido en el plan de la organización |
| Certificados TLS | Sin coste: Let's Encrypt automatizado por Caddy |

## Capa gratuita

**No se asume.** No se ha podido confirmar por API que la cuenta conserve la capa gratuita de 12 meses, y una estimación que dependa de ella deja de ser válida en cuanto caduca, sin aviso. Si existe, el coste real será **menor** que el estimado — nunca mayor. Esa asimetría es deliberada.

**No se dice «gratis para siempre».**

## Requisitos previos al despliegue

- [x] Cuenta de AWS designada y con responsable
- [x] Estimación calculada con precios reales de la Price List API
- [ ] **Presupuesto en AWS Budgets** con el techo mensual
- [ ] **Alertas al 50 %, 80 % y 100 %**
- [ ] Lista cerrada de servicios a provisionar
- [ ] Supuestos de tráfico revisados
- [ ] Política de apagado acordada
- [ ] Etiquetado de recursos para imputación
- [ ] **MFA activado en la cuenta root** y usuario o rol IAM dedicado
- [ ] **BLOCKER de identidad resuelto** si el entorno va a ser accesible

El presupuesto y las alertas se crean **antes** que cualquier recurso de cómputo.

## Seguimiento

| Cuándo | Qué |
| --- | --- |
| Primer mes | Comparar coste real con esta estimación y registrar la desviación |
| Cada mes | Revisar contra el techo y contra lo que queda de proyecto |
| Ante cualquier servicio nuevo | Revisar [assumptions.md](assumptions.md) **antes** de provisionarlo |
| Al cambiar de región | **Todos** los precios de este documento dejan de ser válidos |
