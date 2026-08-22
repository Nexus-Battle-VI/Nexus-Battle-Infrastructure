# ADR-008 — Infraestructura como código: Terraform frente a AWS CDK v2

- **Estado:** Proposed — **no se ha aprovisionado nada**
- **Fecha:** 2026-08-21
- **Decide:** Arquitectura, con aprobación de presupuesto ([ADR-007](ADR-007-aws-cost-optimized-platform.md))

## Contexto

Cuando exista aprobación para provisionar AWS, la infraestructura debe describirse como código. El plan exige **comparar Terraform y AWS CDK v2 sin aprovisionar**.

## Comparación

| Criterio | Terraform | AWS CDK v2 |
| --- | --- | --- |
| **Lenguaje** | HCL declarativo | TypeScript, el mismo del producto |
| **Curva de aprendizaje** | Lenguaje nuevo, pero pequeño y explícito | Ninguna sintaxis nueva para el equipo |
| **Modelo mental** | Se describe el estado deseado | Se escribe un programa que **genera** CloudFormation |
| **Estado** | Fichero de estado que hay que alojar y bloquear | Gestionado por CloudFormation |
| **Multi-nube** | Sí | Solo AWS |
| **`plan` / `diff`** | `terraform plan`, muy legible | `cdk diff`, sobre la plantilla generada |
| **Depuración** | El error apunta al recurso | El error puede apuntar a CloudFormation, no al código que lo generó |
| **Coste** | Gratuito en su edición abierta | Gratuito |
| **Encaje académico** | Estándar de la industria, transferible | Menos transferible fuera de AWS |

### El punto que decide

La ventaja de CDK —usar TypeScript— es también su riesgo principal en un equipo de 18 personas con tres Teams: **permite abstracciones que ocultan qué se está creando**. Un constructo de alto nivel puede provisionar en silencio un NAT Gateway o un balanceador, y con un techo de USD 100 al mes ese silencio es caro.

Terraform obliga a nombrar cada recurso. En un proyecto cuyo primer criterio de diseño es el control de coste, esa verbosidad es una ventaja, no un inconveniente.

El estado de Terraform es su desventaja real: hay que alojarlo y bloquearlo. Para el alcance de la demo, un backend S3 con bloqueo es suficiente y barato, aunque introduce el único uso de S3 que el proyecto contempla.

## Decisión

**Se propone Terraform**, con estas condiciones:

1. **No se escribe IaC hasta que ADR-007 esté aprobado.** Escribir Terraform para infraestructura que no se va a provisionar produce código sin verificar.
2. Estructura prevista cuando se desbloquee:

```text
infra/
  modules/
    network/        VPC, subred publica, grupos de seguridad
    compute/        EC2, IP elastica, perfil de instancia
    messaging/      Cola SQS y DLQ, si ADR-006 la adopta
    observability/  Grupos de logs y alarmas de coste
  envs/
    dev/
    test/
    prod/
```

3. **Presupuesto y alertas se crean en la primera aplicación**, antes que cualquier recurso de cómputo. Un despliegue sin alerta de coste es un riesgo de presupuesto sin control.
4. **Ningún secreto en el código.** Las credenciales de despliegue serán de corta duración vía OIDC ([ADR-009](ADR-009-observability.md) y la sección de OIDC de la arquitectura).

## Consecuencias

**Lo que se gana**

- Cada recurso es explícito y visible en revisión, que es lo que protege el techo de coste.
- `terraform plan` permite revisar el efecto antes de aplicarlo.
- Conocimiento transferible fuera del proyecto.

**Lo que cuesta**

- Un lenguaje más que aprender, además de TypeScript.
- Hay que alojar y bloquear el estado, lo que introduce el único uso de S3 del proyecto.
- Más verboso que CDK para infraestructuras grandes. A esta escala no es un problema.

## Alternativas consideradas

| Alternativa | Por qué se descartó |
| --- | --- |
| AWS CDK v2 | Sus abstracciones pueden provisionar recursos costosos sin que sea evidente en revisión |
| CloudFormation directo | Toda la verbosidad de Terraform sin `plan` legible ni ecosistema de módulos |
| Aprovisionamiento manual desde la consola | No reproducible, no revisable y no auditable |
| Pulumi | Comparte el riesgo de CDK y añade una dependencia menos extendida |

## Pendiente

Este ADR queda en `Proposed`. La decisión se confirma —o se revisa— cuando ADR-007 se apruebe y exista cuenta de AWS designada. **Hoy no existe ningún fichero de Terraform en el repositorio**, y eso es deliberado.
