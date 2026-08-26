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

## La IPv4 pública: qué se cobra y cuándo

Este documento se ha equivocado **dos veces** en el mismo punto, en direcciones opuestas. Queda la tercera versión, y esta sí está contrastada con la documentación de AWS y no solo con la Price List API.

**Primera versión — falsa.** Decía que una IP elástica no cuesta mientras está asociada a una instancia en marcha. Es falso desde el 1 de febrero de 2024: AWS cobra 0,005 USD/h por toda IPv4 pública asociada a un recurso en ejecución.

**Segunda versión — sobrecorregida.** De que `PublicIPv4:InUseAddress` y `PublicIPv4:IdleAddress` cuesten lo mismo se dedujo que la IP se paga igual con la instancia apagada. **El dato de precios es correcto; la inferencia no.** `IdleAddress` se refiere a una IP **elástica** reservada y sin asociar. No es el caso aquí.

**Lo que hay desplegado usa una IP autoasignada** (`associate_public_ip_address = true`), no elástica. Y la documentación de AWS es explícita:

> We release the public IP address when the instance is stopped, hibernated, or terminated.

Al apagar, la dirección se libera y **deja de cobrarse**. Al arrancar de nuevo se asigna **otra distinta**.

Consecuencia práctica: **la IPv4 no es un coste fijo, sino por hora encendida**, exactamente igual que el cómputo. El único suelo real es el disco.

La contrapartida de apagar no es económica sino operativa: se pierde la dirección. Hoy no importa —ningún nombre DNS apunta a ella—, y el día que importe la respuesta es una IP elástica, que **entonces sí** se paga esté o no asociada.

## Coste por régimen de operación

Cálculo determinista sobre los precios de la tabla anterior: `t4g` + 30 GB de `gp3` + una IPv4 pública.

Cómputo e IPv4 van juntos en la columna «por hora» porque **ambos dependen de las horas encendida**: 0,0168 + 0,005 = 0,0218 USD/h en `t4g.small`, y 0,0336 + 0,005 = 0,0386 en `t4g.medium`. El disco es el único fijo: 30 GB × 0,08 = **2,40 USD/mes**.

| Instancia | Régimen | Por hora encendida | Disco | **Total/mes** | % del techo |
| --- | --- | ---: | ---: | ---: | ---: |
| `t4g.small` | 24/7 encendida | 15,91 | 2,40 | **18,31** | 18,3 % |
| `t4g.small` | Lun-Vie 8 h/día (174 h) | 3,79 | 2,40 | **6,19** | 6,2 % |
| `t4g.small` | Solo demos (~20 h/mes) | 0,44 | 2,40 | **2,84** | 2,8 % |
| `t4g.small` | Apagada todo el mes | 0,00 | 2,40 | **2,40** | 2,4 % |
| `t4g.medium` | 24/7 encendida | 28,18 | 2,40 | **30,58** | 30,6 % |
| `t4g.medium` | Lun-Vie 8 h/día (174 h) | 6,72 | 2,40 | **9,12** | 9,1 % |
| `t4g.medium` | Solo demos (~20 h/mes) | 0,77 | 2,40 | **3,17** | 3,2 % |
| `t4g.medium` | Apagada todo el mes | 0,00 | 2,40 | **2,40** | 2,4 % |

Los totales de **24/7 no cambian** respecto a la versión anterior: con la instancia encendida, la IPv4 se cobra igual. Lo que cambia es todo lo demás, y mucho.

**El dato que decide la política de apagado:** el suelo con la instancia apagada es **2,40 USD/mes**, no 6,05. La versión anterior lo sobrestimaba en un 152 %, y con ello desanimaba precisamente la palanca de ahorro que este documento identifica como la principal.

Bajar de 2,40 exige **borrar el volumen**, lo que implica reconstruir el entorno en el siguiente despliegue. Eso sí es una decisión de operación que depende de cuánto tiempo vaya a estar parado.

> Lo desplegado hoy usa **20 GB**, no 30, así que su suelo real es **1,60 USD/mes por instancia**. La tabla mantiene 30 GB para no mezclar la estimación con la topología concreta, que puede cambiar.

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
