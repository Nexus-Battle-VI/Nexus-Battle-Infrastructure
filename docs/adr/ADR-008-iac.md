# ADR-008 — Infraestructura como código: Terraform frente a AWS CDK v2

- **Estado:** **Accepted** el 2026-08-25 — el codigo existe. **Sigue sin aprovisionarse nada**
- **Fecha:** 2026-08-21, aceptado el 2026-08-25
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

1. **No se escribe IaC hasta que ADR-007 esté aprobado.** Condición cumplida el 2026-08-25.
2. Estructura real, en [`infra/`](../../infra/README.md):

```text
infra/
  modules/
    network/      VPC, subred publica, grupos de seguridad
    compute/      EC2, perfil de instancia, acceso por SSM
    identity/     Cognito user pool, cliente publico, grupos de rol
    governance/   Presupuestos y alertas de coste
  envs/
    prod/
```

Difiere de lo previsto en dos puntos, y conviene decir por qué:

- **No hay módulo `messaging`.** SQS sigue siendo candidato no adoptado en [ADR-006](ADR-006-messaging.md). Escribir el módulo antes de la decisión produciría código que nadie ejecuta.
- **`observability` se convirtió en `governance`, y se adelantó.** Las alertas de coste no son observabilidad: son la condición previa que ADR-007 impone a cualquier recurso de cómputo. `module.compute` depende de `module.governance` en el grafo, de modo que **es imposible crear una instancia antes que su alerta de presupuesto**. Deja de ser una costumbre y pasa a ser una garantía.
- **Solo existe `envs/prod`.** Duplicar el entorno multiplica el coste por el número de entornos, y el techo no lo admite. `dev` y `test` viven en la composición de Docker, no en AWS.

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

## Lo que el código añadió a la decisión

Tres cosas que no estaban en el ADR original y que salieron de escribirlo:

- **Sin claves SSH y sin puerto 22.** El acceso administrativo va por SSM Session Manager. Una clave SSH es un secreto de larga duración que hay que custodiar, rotar y revocar.
- **IMDSv2 obligatorio.** Con IMDSv1 basta una vulnerabilidad de petición del lado del servidor para leer las credenciales del rol de la instancia.
- **La topología es una variable, no código.** Ver [ADR-011](ADR-011-deployment-topology.md).

## El estado sigue siendo local

El backend S3 está escrito y **comentado**. Activarlo exige que el bucket exista, y crearlo requiere una primera aplicación con estado local: ese orden no se puede saltar.

Mientras el estado sea local **no está compartido ni respaldado**. Es aceptable porque no hay nada aplicado; deja de serlo el día que lo haya, y ese día es el límite para migrarlo.

## Lo que este ADR no autoriza

`terraform apply`. El código está escrito, validado y planificado, pero **no aplicado**: la cuenta no tiene ningún recurso. Aplicar exige además cerrar los pendientes que enumera [`infra/README.md`](../../infra/README.md).
