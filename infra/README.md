# Infraestructura como código

Terraform, por [ADR-008](../docs/adr/ADR-008-iac.md). Topología por [ADR-011](../docs/adr/ADR-011-deployment-topology.md).

## Estado

> **Nada de esto está aplicado. La cuenta de AWS no tiene ningún recurso.**
>
> Lo único que existe son los dos presupuestos, creados el 2026-08-25 antes que este código porque [ADR-007](../docs/adr/ADR-007-aws-cost-optimized-platform.md) exige que las alertas precedan a cualquier recurso de cómputo. Los bloques `import` los traen bajo Terraform sin recrearlos.

Resultado del último `terraform plan`:

```text
Plan: 2 to import, 22 to add, 2 to change, 0 to destroy.
```

Los dos cambios son **solo etiquetas** sobre los presupuestos existentes. Sus límites y sus alertas se conservan intactos.

## Estructura

```text
infra/
  modules/
    network/      VPC, subred publica, grupos de seguridad
    compute/      EC2, perfil de instancia, acceso por SSM
    identity/     Cognito user pool, cliente publico, grupos de rol
    governance/   Presupuestos y alertas de coste
  envs/
    prod/         Entorno de demo
```

## Cómo se ejecuta

```bash
cd infra/envs/prod
cp terraform.tfvars.example terraform.tfvars   # y se rellena
terraform init
terraform plan
```

`terraform.tfvars` **está ignorado por git**: contiene el identificador de cuenta y una dirección de correo, y este repositorio es público.

**No ejecutes `terraform apply` sin leer la sección siguiente.**

## Antes de aplicar

| Requisito | Estado |
| --- | --- |
| Cuenta designada | ✅ |
| Presupuesto y alertas | ✅ |
| Estimación con precios reales | ✅ |
| Topología decidida | ✅ ADR-011 |
| **MFA en la cuenta root** | ❌ |
| **Usuario o rol IAM en lugar de root** | ❌ |
| **BLOCKER de identidad cerrado** | ❌ |

Los tres pendientes **no impiden aplicar**, pero sí impiden abrir el sistema a internet. Por eso `public_ingress_cidrs` es una lista vacía y la salida `expuesto_a_internet` devuelve `false`: **la infraestructura aplica el blocker en lugar de confiar en que alguien lo recuerde**.

## Decisiones que conviene conocer antes de tocar nada

### La topología es una variable

El módulo de cómputo recibe un **mapa de nodos**. Pasar de dos instancias a tres, o a una por microservicio, es editar `nodes` en `terraform.tfvars` y ejecutar `plan`. La decisión se revisa con un plan delante, no con una discusión. Los números que llevaron a la topología actual están en ADR-011.

### No hay claves SSH ni puerto 22

El acceso administrativo va por **SSM Session Manager**. Una clave SSH es un secreto de larga duración que hay que custodiar, rotar y revocar; Session Manager no necesita ninguno y deja registro de la sesión.

```bash
aws ssm start-session --target <instance-id> --profile nexus-battles
```

### IMDSv2 obligatorio

Con IMDSv1 basta una vulnerabilidad de petición del lado del servidor para leer las credenciales del rol de la instancia. `http_tokens = "required"` lo impide.

### No se fija ningún identificador de AMI a mano

Se resuelve desde el parámetro público de SSM. Un identificador escrito a mano caduca y varía por región.

`ignore_changes = [ami]` evita que una AMI nueva recree la instancia en silencio y se lleve por delante el volumen del nodo de datos.

### El estado pasa a S3

La condición que este mismo documento fijaba —«es aceptable porque todavía no hay nada aplicado; deja de serlo en cuanto lo haya»— ya se cumplió: hay recursos aplicados.

Y apareció el motivo concreto. Cuando otra persona del equipo clonó el repositorio y ejecutó `terraform plan`, obtuvo `2 to import, 29 to add`: sin el estado, Terraform propone crear lo que ya existe. La salida aparentemente obvia es pasarse el fichero, y **no se debe hacer**: el estado guarda `user_data` **entero y sin hashear**, y el arranque lleva dentro `DB_PASSWORD`. Mandar el `terraform.tfstate` por chat o correo es mandar la contraseña de las bases.

El estado compartido no es comodidad. Es la forma de no tener que mandar ese fichero.

`modules/tfstate` crea el bucket con versionado, cifrado SSE-S3, los cuatro bloqueos de acceso público, caducidad de versiones antiguas y una política que rechaza cualquier petición sin TLS. Es la **única** excepción a la prohibición de S3, prevista por ADR-007 y habilitada por ADR-008; la política de denegación de `modules/iam` ya lo permitía por nombre.

#### El orden de activación, que no se puede saltar

```bash
# 1. Crear el bucket, todavía con estado local.
terraform apply

# 2. Descomentar el bloque `backend "s3"` de `versions.tf`.

# 3. Migrar el estado local al bucket. Terraform pide confirmación.
terraform init -migrate-state

# 4. Comprobar que el estado remoto es el bueno ANTES de borrar nada.
terraform state list
terraform plan          # debe salir sin cambios pendientes

# 5. Solo entonces, retirar los ficheros locales.
rm terraform.tfstate terraform.tfstate.backup
```

El paso 4 no es opcional: es lo único que distingue «el estado se migró» de «el estado se perdió y Terraform empezó uno vacío».

A partir de ahí el bloqueo lo da `use_lockfile`, que usa escrituras condicionales de S3 y **no necesita DynamoDB** —que además está prohibida—. Exige Terraform 1.10 o superior, y por eso `required_version` subió de `>= 1.9` a `>= 1.10`: con 1.9 el backend se activa sin bloqueo y sin avisar.

El bucket se declara en la misma configuración cuyo estado aloja, así que acaba registrado dentro de sí mismo. Es el patrón habitual y funciona; lo que no se puede es destruirlo con `terraform destroy` sin sacarlo antes del estado, y por eso lleva `prevent_destroy`.

### Las etiquetas de coste se activan en una segunda aplicación

`activate_cost_allocation_tags` es `false` a propósito. AWS solo permite activar una etiqueta que ya ha visto en algún recurso, y tarda hasta 24 h en exponerla. Ponerlo a `true` en la primera aplicación falla.

## El job de Terraform del CI exige una acción en la lista permitida

El repositorio tiene `allowed_actions: selected`: **solo se pueden usar las acciones de una lista explícita**. Es un control de cadena de suministro deliberado, y tiene una consecuencia que conviene conocer porque su síntoma despista.

Cuando una acción no está en la lista, el workflow **no falla: no llega a arrancar**. Aparece como `startup_failure` con cero segundos de duración y sin ningún registro que leer, lo que se parece mucho a un error de sintaxis en el YAML y no lo es.

`hashicorp/setup-terraform@*` se añadió a la lista de **este repositorio y solo de este**: es el único con código de Terraform. Los otros siete conservan su lista original.

La acción sigue fijada por SHA de commit completo en el workflow. La lista permitida es un control grueso; el anclaje por SHA es el fino. Los dos se complementan y ninguno sustituye al otro.

## Coste de lo que este código crearía

| Concepto | Mensual |
| --- | ---: |
| 2 × `t4g.small` encendidas 24/7 | 24,53 |
| 2 × IPv4 pública | 7,30 |
| 2 × 20 GB `gp3` | 3,20 |
| Cognito Essentials a 100 usuarios activos | 1,50 |
| **Total 24/7** | **36,53** |
| **Total en régimen de demos (~20 h/mes)** | **~12,67** |

La IPv4 y el EBS se pagan **también con las instancias apagadas**. Ese suelo de 10,50 USD/mes es lo que no baja apagando.

Precios reales de la Price List API al 2026-08-25. Detalle en [sprint-demo-estimate.md](../docs/costs/sprint-demo-estimate.md).
