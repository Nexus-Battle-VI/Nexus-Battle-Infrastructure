# ---------------------------------------------------------------------------
# Entorno de demo. Topologia T2 de ADR-011: plano de aplicacion y plano de datos.
#
# APLICADO desde el 2026-08-26. El estado vive en local mientras ADR-008 no
# pase el respaldo a S3; `terraform.tfstate` esta fuera del control de versiones.
# ---------------------------------------------------------------------------

locals {
  name = "nexus-battles-vi"

  tags = {
    Project     = "nexus-battles-vi"
    Environment = "prod"
    ManagedBy   = "terraform"
    Repository  = "Nexus-Battle-Infrastructure"
  }
}

module "governance" {
  source = "../../modules/governance"

  account_id  = var.account_id
  alert_email = var.alert_email
}

/**
 * La identidad de operacion se declara ANTES que el computo, igual que el
 * presupuesto: crear veintidos recursos a nombre de root deja un rastro de
 * auditoria que despues no se puede reescribir.
 */
module "iam" {
  source = "../../modules/iam"

  allowed_instance_types = var.allowed_instance_types
}

module "network" {
  source = "../../modules/network"

  name                 = local.name
  tags                 = local.tags
  availability_zone    = var.availability_zone
  public_ingress_cidrs = var.public_ingress_cidrs
}

module "identity" {
  source = "../../modules/identity"

  name = local.name
  tags = local.tags
}

# Lo que cada rol de nodo escribe en disco al arrancar.
#
# Los ficheros se LEEN de `compose/`, no se duplican aqui. Es la unica forma de
# que el mismo `docker compose config` que valida el CI valide lo que de verdad
# acaba en la instancia: una copia dentro de Terraform seria una copia que se
# desvia sin que nada se queje.
locals {
  compose_dir = "${path.root}/../../../compose"

  bootstrap = {
    app = {
      compose = file("${local.compose_dir}/nodes/app.yml")
      ficheros = {
        "Caddyfile" = file("${local.compose_dir}/Caddyfile")
      }
      entorno = {
        DATA_HOST            = var.nodes["data"].private_ip
        DB_PASSWORD          = var.db_password
        AUTH_MODE            = var.auth_mode
        COGNITO_USER_POOL_ID = module.identity.user_pool_id
        COGNITO_CLIENT_ID    = module.identity.client_id
      }
    }

    data = {
      compose = file("${local.compose_dir}/nodes/data.yml")
      ficheros = {
        "init-postgres.sql" = file("${local.compose_dir}/init-postgres.sql")
        "init-mongo.js"     = file("${local.compose_dir}/init-mongo.js")
      }
      entorno = {
        DB_PASSWORD = var.db_password
      }
    }
  }
}

module "compute" {
  source = "../../modules/compute"

  name                  = local.name
  tags                  = local.tags
  subnet_id             = module.network.subnet_id
  security_group_ids    = module.network.security_group_ids
  nodes                 = var.nodes
  bootstrap             = local.bootstrap
  arrancar_stack        = var.arrancar_stack
  compose_plugin_url    = var.compose_plugin_url
  compose_plugin_sha256 = var.compose_plugin_sha256

  # El presupuesto y las alertas existen antes que cualquier recurso de computo.
  # Esta dependencia lo convierte en una garantia del grafo, no en una costumbre.
  depends_on = [module.governance]
}

# ---------------------------------------------------------------------------
# Los presupuestos YA EXISTEN: se crearon el 2026-08-25, antes de escribir este
# codigo, porque ADR-007 exige que las alertas precedan a cualquier recurso de
# computo. Estos bloques los traen bajo Terraform sin recrearlos.
#
# Los bloques `import` solo surten efecto en el modulo RAIZ. Declararlos dentro
# del modulo no da error: simplemente se ignoran, y el plan propone crear un
# presupuesto que ya existe. Lo detecto el `terraform plan`.
# ---------------------------------------------------------------------------
import {
  to = module.governance.aws_budgets_budget.ceiling
  id = "${var.account_id}:nexus-battles-monthly-100"
}

import {
  to = module.governance.aws_budgets_budget.operational
  id = "${var.account_id}:nexus-battles-operational-25"
}

# ---------------------------------------------------------------------------
# Activacion de etiquetas para imputacion de coste.
#
# Desactivado por defecto y NO es un olvido: AWS solo permite activar una
# etiqueta que ya ha visto en algun recurso, y tarda hasta 24 h en exponerla.
# Se activa en una SEGUNDA aplicacion, un dia despues de crear los recursos.
# Declararlo aqui con `depends_on` no bastaria: la dependencia del grafo no
# acelera el rastreo de etiquetas de AWS.
# ---------------------------------------------------------------------------
resource "aws_ce_cost_allocation_tag" "this" {
  for_each = var.activate_cost_allocation_tags ? toset(["Project", "Environment", "Role"]) : toset([])

  tag_key = each.value
  status  = "Active"

  depends_on = [module.compute]
}
