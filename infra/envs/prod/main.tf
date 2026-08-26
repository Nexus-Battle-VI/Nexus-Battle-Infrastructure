# ---------------------------------------------------------------------------
# Entorno de demo. Topologia T2 de ADR-011: plano de aplicacion y plano de datos.
#
# NADA de esto esta aplicado. Ver infra/README.md.
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

module "compute" {
  source = "../../modules/compute"

  name               = local.name
  tags               = local.tags
  subnet_id          = module.network.subnet_id
  security_group_ids = module.network.security_group_ids
  nodes              = var.nodes

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
