# Supuestos de coste

Toda estimación depende de supuestos. Los de esta se declaran aquí para que puedan revisarse y, cuando sean falsos, se sepa qué parte de la cifra deja de ser válida.

## Estado

**Coste incurrido a la fecha: USD 0.** No hay cuenta de AWS configurada ni recurso provisionado.

## Supuestos de uso

| Supuesto | Valor asumido | Si es falso |
| --- | --- | --- |
| Usuarios concurrentes en demo | ≤ 30 | Una instancia pequeña deja de bastar |
| Peticiones por sesión | ≤ 100 | Aumenta la transferencia de salida |
| Sesiones al mes | ≤ 500 | Aumenta cómputo y transferencia |
| Correos al mes | ≤ 1 000 | Relevante solo si se adopta SES |
| Mensajes en cola al mes | ≤ 10 000 | SQS es *usage-based*; el impacto sería proporcional |
| Tamaño de la base de datos | ≤ 5 GB | Aumenta el volumen EBS |
| Transferencia de salida | ≤ 10 GB/mes | Es la partida que más se dispara con tráfico real |
| Horas encendida | Ver política de apagado | Es la palanca de ahorro principal |

Los números salen del uso previsto de una demostración académica, no de una medición. **Ninguno está validado con tráfico real.**

## Supuestos técnicos

| Supuesto | Base |
| --- | --- |
| Una sola instancia basta para los seis servicios | Los contenedores son ligeros; el volumen previsto es bajo |
| Los contenedores de base de datos caben en la misma instancia | Con ≤ 5 GB de datos y baja concurrencia |
| Un solo volumen EBS es suficiente | Ambos motores comparten disco, con directorios separados |
| No hace falta caché | Sin latencia problemática al volumen previsto |
| Sin balanceador | Un único destino que balancear |
| Sin NAT Gateway | La instancia va en subred pública con IP elástica |

## Supuestos de precio

| Supuesto | Riesgo |
| --- | --- |
| Región de coste medio | Cambiar de región altera todos los precios |
| Bajo demanda, sin compromiso | Un plan de ahorro reduciría el coste a cambio de compromiso anual |
| Capa gratuita **no** asumida | Deliberado: sus límites caducan y superarlos genera coste sin aviso |
| Precios de la fecha del documento | AWS los revisa periódicamente |

**No se asume capa gratuita.** Es una decisión consciente: una estimación que depende de ella deja de ser válida en cuanto caduca, y esa caducidad no avisa.

## Lo que la estimación no incluye

| Concepto | Motivo |
| --- | --- |
| SES | No aprobado; requiere verificación de dominio y salida del *sandbox* |
| Route 53 | El dominio no está decidido |
| Certificados | Let's Encrypt vía Caddy, sin coste |
| Copias de seguridad gestionadas | No hay servicio gestionado que las provea |
| Soporte de AWS | Plan básico, sin coste |
| Estado de Terraform en S3 | Céntimos; se incluirá cuando [ADR-008](../adr/ADR-008-iac.md) se apruebe |

## Lo que invalidaría la estimación

En orden de probabilidad:

1. **Adoptar RDS o DocumentDB.** Solo RDS ya excede el techo completo.
2. **Añadir un balanceador.** Coste fijo por hora.
3. **Añadir NAT Gateway.** Coste fijo elevado.
4. **Dejar la instancia encendida de forma continua** en lugar de aplicar la política de apagado.
5. **Tráfico real muy superior al previsto.** La transferencia de salida es la partida que más se dispara.
6. **Migrar hacia la arquitectura objetivo.** Es otro orden de magnitud, no un ajuste.

## Cómo se revisa

- La estimación se revisa **contra la calculadora oficial de AWS** antes de provisionar.
- El coste real se compara con la estimación **el primer mes** de uso.
- Las alertas de presupuesto al 50 %, 80 % y 100 % son el mecanismo de detección temprana.
- Cualquier servicio nuevo exige revisar este documento **antes** de provisionarlo.

## Lo que no se puede afirmar

**No se dice «gratis para siempre».** La capa gratuita tiene límites temporales y de volumen, y superarlos genera coste sin aviso previo. Por eso las alertas de presupuesto son un requisito previo al despliegue, no una mejora posterior.
