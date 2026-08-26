# ---------------------------------------------------------------------------
# Presupuestos y control de coste.
#
# ADR-007 exige que el presupuesto y las alertas existan ANTES que cualquier
# recurso de computo. Se crearon por CLI el 2026-08-25, antes de escribir este
# modulo, y los bloques `import` los traen bajo Terraform sin recrearlos: si se
# borrasen para recrearlos, habria una ventana sin ninguna alerta activa.
# ---------------------------------------------------------------------------

locals {
  ceiling_name     = "nexus-battles-monthly-100"
  operational_name = "nexus-battles-operational-25"

  cost_types = {
    include_tax                = true
    include_subscription       = true
    use_blended                = false
    include_refund             = false
    include_credit             = false
    include_upfront            = true
    include_recurring          = true
    include_other_subscription = true
    include_support            = true
    include_discount           = true
    use_amortized              = false
  }
}

resource "aws_budgets_budget" "ceiling" {
  name         = local.ceiling_name
  budget_type  = "COST"
  limit_amount = var.monthly_ceiling_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_tax                = local.cost_types.include_tax
    include_subscription       = local.cost_types.include_subscription
    use_blended                = local.cost_types.use_blended
    include_refund             = local.cost_types.include_refund
    include_credit             = local.cost_types.include_credit
    include_upfront            = local.cost_types.include_upfront
    include_recurring          = local.cost_types.include_recurring
    include_other_subscription = local.cost_types.include_other_subscription
    include_support            = local.cost_types.include_support
    include_discount           = local.cost_types.include_discount
    use_amortized              = local.cost_types.use_amortized
  }

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
    }
  }

  # Por proyeccion: avisa ANTES de gastarlo, no despues.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

resource "aws_budgets_budget" "operational" {
  name         = local.operational_name
  budget_type  = "COST"
  limit_amount = var.operational_target_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_tax                = local.cost_types.include_tax
    include_subscription       = local.cost_types.include_subscription
    use_blended                = local.cost_types.use_blended
    include_refund             = local.cost_types.include_refund
    include_credit             = local.cost_types.include_credit
    include_upfront            = local.cost_types.include_upfront
    include_recurring          = local.cost_types.include_recurring
    include_other_subscription = local.cost_types.include_other_subscription
    include_support            = local.cost_types.include_support
    include_discount           = local.cost_types.include_discount
    use_amortized              = local.cost_types.use_amortized
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
