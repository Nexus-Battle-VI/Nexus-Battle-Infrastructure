variable "account_id" {
  type = string
}

variable "alert_email" {
  description = "Destino de las alertas de coste."
  type        = string
}

variable "monthly_ceiling_usd" {
  description = "Techo mensual declarado en ADR-007."
  type        = number
  default     = 100
}

variable "operational_target_usd" {
  description = "Objetivo operativo, muy por debajo del techo. Es el cable trampa real: el techo sirve para no pasarse, no para gastar."
  type        = number
  default     = 25
}
